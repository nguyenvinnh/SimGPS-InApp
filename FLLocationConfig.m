#import "FLLocationConfig.h"

@implementation FLLocationConfig

+ (instancetype)sharedConfig {
    static FLLocationConfig *config;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [[self alloc] init];
        [config reset];
        [config loadSavedConfig];
    });
    return config;
}

- (void)reset {
    self.enabled = NO;
    self.latitude = 0.0;
    self.longitude = 0.0;
    self.altitude = 0.0;
    self.horizontalAccuracy = 10.0;
    self.verticalAccuracy = 10.0;
    self.speed = -1.0;
    self.course = -1.0;
}

- (void)loadSavedConfig {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"FLLatitude"]) {
        self.latitude = [defaults doubleForKey:@"FLLatitude"];
        self.longitude = [defaults doubleForKey:@"FLLongitude"];
        self.enabled = [defaults boolForKey:@"FLEnabled"];
    }
}

- (void)saveConfig {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:self.latitude forKey:@"FLLatitude"];
    [defaults setDouble:self.longitude forKey:@"FLLongitude"];
    [defaults setBool:self.enabled forKey:@"FLEnabled"];
    [defaults synchronize];
}

- (void)setCoordinate:(CLLocationCoordinate2D)coordinate {
    self.latitude = coordinate.latitude;
    self.longitude = coordinate.longitude;
}

- (CLLocation *)currentFakeLocation {
    if (!self.enabled) {
        return nil;
    }

    CLLocationCoordinate2D coordinate =
        CLLocationCoordinate2DMake(self.latitude, self.longitude);

    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        return nil;
    }

    return [[CLLocation alloc]
        initWithCoordinate:coordinate
        altitude:self.altitude
        horizontalAccuracy:self.horizontalAccuracy
        verticalAccuracy:self.verticalAccuracy
        course:self.course
        speed:self.speed
        timestamp:[NSDate date]];
}

@end