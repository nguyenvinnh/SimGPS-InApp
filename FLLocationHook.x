#import <CoreLocation/CoreLocation.h>
#import "FLLocationService.h"

static NSHashTable *activeManagers = nil;
static NSTimer *updateTimer = nil;

static void FLDeliverFakeLocation(CLLocationManager *manager) {
    FLLocationService *service = [FLLocationService sharedService];
    if (!service.isEnabled) {
        return;
    }

    CLLocation *location = service.currentLocation;
    id<CLLocationManagerDelegate> delegate = manager.delegate;

    if (!location || !delegate) {
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
        updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:[NSBlockOperation blockOperationWithBlock:^{
            FLTimerFired(nil);
        }]
                                                     selector:@selector(main)
                                                     userInfo:nil
                                                      repeats:YES];
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

%end