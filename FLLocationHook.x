#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "FLLocationService.h"
#import "FLLocationConfig.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSHashTable *activeManagers = nil;
static NSTimer *updateTimer = nil;
static NSMutableSet *hookedDelegateClasses = nil;
static NSMutableDictionary<NSString *, NSValue *> *origIMPMap = nil;
static CLAuthorizationStatus sFakeAuthStatus = kCLAuthorizationStatusAuthorizedWhenInUse;

#import "FLFakeHeading.h"

// MARK: - Delivery Functions

static void FLDeliverFakeLocation(CLLocationManager *manager) {
    if (!manager) return;
    FLLocationService *service = [FLLocationService sharedService];
    if (!service.isEnabled) {
        return;
    }

    CLLocation *location = service.currentLocation;
    id<CLLocationManagerDelegate> delegate = manager.delegate;

    if (!location || !delegate) {
        return;
    }

    CLLocation *capturedLocation = location;
    id<CLLocationManagerDelegate> capturedDelegate = delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([capturedDelegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            [capturedDelegate locationManager:manager
                           didUpdateLocations:@[ capturedLocation ]];
        } else if ([capturedDelegate respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
            [capturedDelegate locationManager:manager
                          didUpdateToLocation:capturedLocation
                                 fromLocation:capturedLocation];
        }
    });
}

static void FLDeliverFakeHeading(CLLocationManager *manager) {
    if (!manager) return;
    FLLocationService *service = [FLLocationService sharedService];
    if (!service.isEnabled) {
        return;
    }

    id<CLLocationManagerDelegate> delegate = manager.delegate;
    if (!delegate) {
        return;
    }

    // Đảm bảo luôn có góc heading hợp lệ để vẽ hình nón (kể cả đứng yên tĩnh)
    CLLocationDirection course = [FLLocationConfig sharedConfig].course;
    double validHeading = (course >= 0.0) ? course : 0.0;

    if (![delegate respondsToSelector:@selector(locationManager:didUpdateHeading:)]) {
        return;
    }

    FLFakeHeading *heading = [[FLFakeHeading alloc] initWithHeading:validHeading];
    id<CLLocationManagerDelegate> capturedDelegate = delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        [capturedDelegate locationManager:manager didUpdateHeading:heading];
    });
}

// Hàm phát đồng bộ cả Location và Heading ra bên ngoài (được gọi từ FLRouteSimulator)
void FLBroadcastLocationAndHeading(void) {
    FLLocationService *service = [FLLocationService sharedService];
    if (!service.isEnabled) return;

    @synchronized(activeManagers) {
        for (CLLocationManager *manager in activeManagers) {
            FLDeliverFakeLocation(manager);
            FLDeliverFakeHeading(manager);
        }
    }
}

static void FLNotifyAuthorizationStatus(CLLocationManager *manager) {
    if (!manager) return;
    FLLocationService *service = [FLLocationService sharedService];
    if (!service.isFakeAuthorizationEnabled) {
        return;
    }

    id<CLLocationManagerDelegate> delegate = manager.delegate;
    if (!delegate) {
        return;
    }

    CLAuthorizationStatus currentStatus = sFakeAuthStatus;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Delegate callback iOS 14+
        if (@available(iOS 14.0, *)) {
            if ([delegate respondsToSelector:@selector(locationManagerDidChangeAuthorization:)]) {
                [delegate locationManagerDidChangeAuthorization:manager];
            }
        }
        // Delegate callback tiêu chuẩn
        if ([delegate respondsToSelector:@selector(locationManager:didChangeAuthorizationStatus:)]) {
            [delegate locationManager:manager didChangeAuthorizationStatus:currentStatus];
        }
    });
}

static void FLTimerFired(NSTimer *timer) {
    FLLocationService *service = [FLLocationService sharedService];
    if (!service.isEnabled) {
        return;
    }

    @synchronized(activeManagers) {
        for (CLLocationManager *manager in activeManagers) {
            FLDeliverFakeLocation(manager);
            FLDeliverFakeHeading(manager);
        }
    }
}

static void FLStartTimerIfNeeded(void) {
    if (!updateTimer) {
        if (@available(iOS 10.0, *)) {
            updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
                FLTimerFired(timer);
            }];
        } else {
            updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                           target:[NSBlockOperation blockOperationWithBlock:^{
                FLTimerFired(nil);
            }]
                                                         selector:@selector(main)
                                                         userInfo:nil
                                                          repeats:YES];
        }
    }
}

// MARK: - Swizzle Delegates

static void FLSwizzleDidUpdateLocations(Class cls) {
    SEL selector = @selector(locationManager:didUpdateLocations:);
    Method originalMethod = class_getInstanceMethod(cls, selector);
    if (!originalMethod) return;

    NSString *key = [NSString stringWithFormat:@"%@_didUpdateLocations", NSStringFromClass(cls)];
    if (origIMPMap[key]) return;

    IMP origIMP = method_getImplementation(originalMethod);
    origIMPMap[key] = [NSValue valueWithPointer:origIMP];

    id replacementBlock = ^(id selfObj, CLLocationManager *manager, NSArray<CLLocation *> *locations) {
        FLLocationService *service = [FLLocationService sharedService];
        if (service.isEnabled) {
            CLLocation *fakeLoc = service.currentLocation;
            if (fakeLoc) {
                locations = @[ fakeLoc ];
            }
        }
        IMP storedIMP = [origIMPMap[key] pointerValue];
        if (storedIMP) {
            ((void (*)(id, SEL, CLLocationManager *, NSArray *))storedIMP)(selfObj, selector, manager, locations);
        }
    };

    IMP newIMP = imp_implementationWithBlock(replacementBlock);
    method_setImplementation(originalMethod, newIMP);
}

static void FLSwizzleDidUpdateToLocation(Class cls) {
    SEL selector = @selector(locationManager:didUpdateToLocation:fromLocation:);
    Method originalMethod = class_getInstanceMethod(cls, selector);
    if (!originalMethod) return;

    NSString *key = [NSString stringWithFormat:@"%@_didUpdateToLocation", NSStringFromClass(cls)];
    if (origIMPMap[key]) return;

    IMP origIMP = method_getImplementation(originalMethod);
    origIMPMap[key] = [NSValue valueWithPointer:origIMP];

    id replacementBlock = ^(id selfObj, CLLocationManager *manager, CLLocation *newLoc, CLLocation *oldLoc) {
        FLLocationService *service = [FLLocationService sharedService];
        CLLocation *finalLoc = newLoc;
        if (service.isEnabled) {
            CLLocation *fakeLoc = service.currentLocation;
            if (fakeLoc) {
                finalLoc = fakeLoc;
            }
        }
        IMP storedIMP = [origIMPMap[key] pointerValue];
        if (storedIMP) {
            ((void (*)(id, SEL, CLLocationManager *, CLLocation *, CLLocation *))storedIMP)(selfObj, selector, manager, finalLoc, oldLoc);
        }
    };

    IMP newIMP = imp_implementationWithBlock(replacementBlock);
    method_setImplementation(originalMethod, newIMP);
}

static void FLSwizzleDidUpdateHeading(Class cls) {
    SEL selector = @selector(locationManager:didUpdateHeading:);
    Method originalMethod = class_getInstanceMethod(cls, selector);

    NSString *key = [NSString stringWithFormat:@"%@_didUpdateHeading", NSStringFromClass(cls)];
    if (origIMPMap[key]) return;

    if (!originalMethod) {
        // Nếu delegate của app chưa implement locationManager:didUpdateHeading:, tự động bổ sung vào class!
        // Đây chính là lý do Google Maps không nhận được callback la bàn!
        id addedBlock = ^(id selfObj, CLLocationManager *manager, CLHeading *heading) {
            // Không làm gì thêm, chỉ cần delegate tiếp nhận thành công
        };
        const char *types = "v@:@@";
        IMP addedIMP = imp_implementationWithBlock(addedBlock);
        class_addMethod(cls, selector, addedIMP, types);
        origIMPMap[key] = [NSValue valueWithPointer:addedIMP];
        return;
    }

    IMP origIMP = method_getImplementation(originalMethod);
    origIMPMap[key] = [NSValue valueWithPointer:origIMP];

    id replacementBlock = ^(id selfObj, CLLocationManager *manager, CLHeading *heading) {
        FLLocationService *service = [FLLocationService sharedService];
        CLHeading *finalHeading = heading;
        if (service.isEnabled) {
            CLLocationDirection course = [FLLocationConfig sharedConfig].course;
            double validHeading = (course >= 0.0) ? course : 0.0;
            finalHeading = [[FLFakeHeading alloc] initWithHeading:validHeading];
        }
        IMP storedIMP = [origIMPMap[key] pointerValue];
        if (storedIMP) {
            ((void (*)(id, SEL, CLLocationManager *, CLHeading *))storedIMP)(selfObj, selector, manager, finalHeading);
        }
    };

    IMP newIMP = imp_implementationWithBlock(replacementBlock);
    method_setImplementation(originalMethod, newIMP);
}

static void FLSwizzleDidChangeAuthorizationStatus(Class cls) {
    SEL selector = @selector(locationManager:didChangeAuthorizationStatus:);
    Method originalMethod = class_getInstanceMethod(cls, selector);
    if (!originalMethod) return;

    NSString *key = [NSString stringWithFormat:@"%@_didChangeAuth", NSStringFromClass(cls)];
    if (origIMPMap[key]) return;

    IMP origIMP = method_getImplementation(originalMethod);
    origIMPMap[key] = [NSValue valueWithPointer:origIMP];

    id replacementBlock = ^(id selfObj, CLLocationManager *manager, CLAuthorizationStatus status) {
        FLLocationService *service = [FLLocationService sharedService];
        CLAuthorizationStatus finalStatus = status;
        if (service.isFakeAuthorizationEnabled) {
            finalStatus = sFakeAuthStatus;
        }
        IMP storedIMP = [origIMPMap[key] pointerValue];
        if (storedIMP) {
            ((void (*)(id, SEL, CLLocationManager *, CLAuthorizationStatus))storedIMP)(selfObj, selector, manager, finalStatus);
        }
    };

    IMP newIMP = imp_implementationWithBlock(replacementBlock);
    method_setImplementation(originalMethod, newIMP);
}

static void FLSwizzleDidFailWithError(Class cls) {
    SEL selector = @selector(locationManager:didFailWithError:);
    Method originalMethod = class_getInstanceMethod(cls, selector);
    if (!originalMethod) return;

    NSString *key = [NSString stringWithFormat:@"%@_didFailWithError", NSStringFromClass(cls)];
    if (origIMPMap[key]) return;

    IMP origIMP = method_getImplementation(originalMethod);
    origIMPMap[key] = [NSValue valueWithPointer:origIMP];

    id replacementBlock = ^(id selfObj, CLLocationManager *manager, NSError *error) {
        FLLocationService *service = [FLLocationService sharedService];
        if (service.isFakeAuthorizationEnabled && [error.domain isEqualToString:kCLErrorDomain] && error.code == kCLErrorDenied) {
            if (service.isEnabled) {
                FLDeliverFakeLocation(manager);
                FLDeliverFakeHeading(manager);
            }
            return;
        }
        IMP storedIMP = [origIMPMap[key] pointerValue];
        if (storedIMP) {
            ((void (*)(id, SEL, CLLocationManager *, NSError *))storedIMP)(selfObj, selector, manager, error);
        }
    };

    IMP newIMP = imp_implementationWithBlock(replacementBlock);
    method_setImplementation(originalMethod, newIMP);
}

static void FLSwizzleDelegateMethodsIfNeeded(Class cls) {
    if (!cls) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hookedDelegateClasses = [NSMutableSet set];
        origIMPMap = [NSMutableDictionary dictionary];
    });

    NSString *className = NSStringFromClass(cls);
    @synchronized(hookedDelegateClasses) {
        if ([hookedDelegateClasses containsObject:className]) return;
        [hookedDelegateClasses addObject:className];

        FLSwizzleDidUpdateLocations(cls);
        FLSwizzleDidUpdateToLocation(cls);
        FLSwizzleDidUpdateHeading(cls);
        FLSwizzleDidChangeAuthorizationStatus(cls);
        FLSwizzleDidFailWithError(cls);
    }
}

// MARK: - CLLocationManager Hooks

%hook CLLocationManager

+ (BOOL)locationServicesEnabled {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isFakeAuthorizationEnabled) {
        return YES;
    }
    return %orig;
}

+ (CLAuthorizationStatus)authorizationStatus {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isFakeAuthorizationEnabled) {
        return sFakeAuthStatus;
    }
    return %orig;
}

- (CLAuthorizationStatus)authorizationStatus {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isFakeAuthorizationEnabled) {
        return sFakeAuthStatus;
    }
    return %orig;
}

- (CLAccuracyAuthorization)accuracyAuthorization {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isFakeAuthorizationEnabled) {
        return CLAccuracyAuthorizationFullAccuracy;
    }
    return %orig;
}

- (BOOL)isAuthorizedForWidgetUpdates {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isFakeAuthorizationEnabled) {
        return YES;
    }
    return %orig;
}

+ (BOOL)headingAvailable {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isFakeAuthorizationEnabled || service.isEnabled) {
        return YES;
    }
    return %orig;
}

- (CLHeading *)heading {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isEnabled) {
        CLLocationDirection course = [FLLocationConfig sharedConfig].course;
        if (course >= 0.0) {
            return [[FLFakeHeading alloc] initWithHeading:course];
        }
    }
    return %orig;
}

- (void)startUpdatingHeading {
    %orig;
    @synchronized(activeManagers) {
        [activeManagers addObject:self];
    }
    FLDeliverFakeHeading(self);
}

- (void)setHeadingFilter:(CLLocationDegrees)filter {
    // Nếu ứng dụng đang dùng tính năng fake location, đặt filter cực nhỏ để Google Maps cập nhật mượt mà
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isEnabled) {
        %orig(kCLHeadingFilterNone);
        return;
    }
    %orig(filter);
}

- (void)requestWhenInUseAuthorization {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isFakeAuthorizationEnabled) {
        if (sFakeAuthStatus != kCLAuthorizationStatusAuthorizedAlways) {
            sFakeAuthStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
        }
        FLNotifyAuthorizationStatus(self);
        return;
    }
    %orig;
}

- (void)requestAlwaysAuthorization {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isFakeAuthorizationEnabled) {
        sFakeAuthStatus = kCLAuthorizationStatusAuthorizedAlways;
        FLNotifyAuthorizationStatus(self);
        return;
    }
    %orig;
}

- (instancetype)init {
    CLLocationManager *manager = %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activeManagers = [NSHashTable weakObjectsHashTable];
    });
    @synchronized(activeManagers) {
        [activeManagers addObject:manager];
    }
    FLStartTimerIfNeeded();
    return manager;
}

- (void)setDelegate:(id<CLLocationManagerDelegate>)delegate {
    if (delegate) {
        FLSwizzleDelegateMethodsIfNeeded([delegate class]);
    }
    %orig;
    if (delegate) {
        FLNotifyAuthorizationStatus(self);
        FLDeliverFakeLocation(self);
        FLDeliverFakeHeading(self);
    }
}

- (CLLocation *)location {
    FLLocationService *service = [FLLocationService sharedService];
    if (service.isEnabled) {
        CLLocation *location = service.currentLocation;
        if (location) {
            return location;
        }
    }
    return %orig;
}

- (void)startUpdatingLocation {
    FLLocationService *service = [FLLocationService sharedService];
    @synchronized(activeManagers) {
        [activeManagers addObject:self];
    }
    FLStartTimerIfNeeded();
    if (service.isEnabled) {
        FLDeliverFakeLocation(self);
        FLDeliverFakeHeading(self);
    }
    %orig;
}

- (void)requestLocation {
    FLLocationService *service = [FLLocationService sharedService];
    @synchronized(activeManagers) {
        [activeManagers addObject:self];
    }
    if (service.isEnabled) {
        FLDeliverFakeLocation(self);
        FLDeliverFakeHeading(self);
        return;
    }
    %orig;
}

- (void)startMonitoringSignificantLocationChanges {
    FLLocationService *service = [FLLocationService sharedService];
    @synchronized(activeManagers) {
        [activeManagers addObject:self];
    }
    FLStartTimerIfNeeded();
    if (service.isEnabled) {
        FLDeliverFakeLocation(self);
        FLDeliverFakeHeading(self);
    }
    %orig;
}

%end

#pragma clang diagnostic pop