#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "FLLocationService.h"

static NSHashTable *activeManagers = nil;
static NSTimer *updateTimer = nil;
static NSMutableSet *hookedDelegateClasses = nil;

static void FLDeliverFakeLocation(CLLocationManager *manager) {
    FLLocationService *service = [FLLocationService sharedService];
    if (!service.isEnabled) {
        return;
    }

    CLLocation *location = service.currentLocation;
    id<CLLocationManagerDelegate> delegate = manager.delegate;

    if (!location ||!delegate) {
        return;
    }

    if (![delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        return;
    }

    CLLocation *capturedLocation = location;
    id<CLLocationManagerDelegate> capturedDelegate = delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        [capturedDelegate locationManager:manager
                      didUpdateLocations:@[ capturedLocation ]];
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
            // Fallback cho iOS cũ
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

// Map để lưu trữ original IMP của didUpdateLocations cho từng Class
static NSMutableDictionary<NSString *, NSValue *> *origIMPMap = nil;

static void FLSwizzleDidUpdateLocations(Class cls) {
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

        SEL selector = @selector(locationManager:didUpdateLocations:);
        Method originalMethod = class_getInstanceMethod(cls, selector);
        if (!originalMethod) return;

        IMP origIMP = method_getImplementation(originalMethod);
        origIMPMap[className] = [NSValue valueWithPointer:origIMP];

        // Tạo block thay thế hàm callback vị trí
        id replacementBlock = ^(id selfObj, CLLocationManager *manager, NSArray<CLLocation *> *locations) {
            FLLocationService *service = [FLLocationService sharedService];
            if (service.isEnabled) {
                CLLocation *fakeLoc = service.currentLocation;
                if (fakeLoc) {
                    locations = @[ fakeLoc ];
                }
            }
            IMP storedIMP = [origIMPMap[className] pointerValue];
            if (storedIMP) {
                ((void (*)(id, SEL, CLLocationManager *, NSArray *))storedIMP)(selfObj, selector, manager, locations);
            }
        };

        IMP newIMP = imp_implementationWithBlock(replacementBlock);
        method_setImplementation(originalMethod, newIMP);
    }
}

%hook CLLocationManager

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
        FLSwizzleDidUpdateLocations([delegate class]);
    }
    %orig;
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
    %orig;
    @synchronized(activeManagers) {
        [activeManagers addObject:self];
    }
    FLDeliverFakeLocation(self);
}

- (void)requestLocation {
    %orig;
    @synchronized(activeManagers) {
        [activeManagers addObject:self];
    }
    FLDeliverFakeLocation(self);
}

- (void)startMonitoringSignificantLocationChanges {
    %orig;
    @synchronized(activeManagers) {
        [activeManagers addObject:self];
    }
    FLDeliverFakeLocation(self);
}

%end