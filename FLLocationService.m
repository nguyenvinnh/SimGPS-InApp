#import "FLLocationService.h"
#import "FLLocationEngine.h"

@implementation FLLocationService

+ (instancetype)sharedService {
    static FLLocationService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[self alloc] init];
    });
    return service;
}

- (void)enable {
    [FLLocationEngine sharedEngine].enabled = YES;
}

- (void)disable {
    [FLLocationEngine sharedEngine].enabled = NO;
}

- (void)setLatitude:(CLLocationDegrees)latitude
          longitude:(CLLocationDegrees)longitude {
    FLLocationEngine *engine = [FLLocationEngine sharedEngine];
    [engine setLatitude:latitude longitude:longitude];
}

- (void)setLocation:(CLLocation *)location {
    [[FLLocationEngine sharedEngine] setLocation:location];
}

- (void)reset {
    [[FLLocationEngine sharedEngine] reset];
}

- (BOOL)isEnabled {
    return [FLLocationEngine sharedEngine].isEnabled;
}

- (BOOL)isFakeAuthorizationEnabled {
    return [FLLocationEngine sharedEngine].fakeAuthorization;
}

- (CLLocation *)currentLocation {
    return [[FLLocationEngine sharedEngine] fakeLocation];
}

@end