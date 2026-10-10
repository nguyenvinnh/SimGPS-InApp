#import "FLLocationEngine.h"
#import "FLLocationConfig.h"

@implementation FLLocationEngine

// Suppress auto-synthesize since we provide custom getter/setter
@dynamic enabled;

+ (instancetype)sharedEngine {
  static FLLocationEngine *engine;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    engine = [[self alloc] init];
  });
  return engine;
}

- (BOOL)isEnabled {
  return [FLLocationConfig sharedConfig].isEnabled;
}

- (void)setEnabled:(BOOL)enabled {
  [FLLocationConfig sharedConfig].enabled = enabled;
  [[FLLocationConfig sharedConfig] saveConfig];
}

- (BOOL)fakeAuthorization {
  return [FLLocationConfig sharedConfig].fakeAuthorization;
}

- (void)setFakeAuthorization:(BOOL)fakeAuthorization {
  [FLLocationConfig sharedConfig].fakeAuthorization = fakeAuthorization;
  [[FLLocationConfig sharedConfig] saveConfig];
}

- (void)setLatitude:(CLLocationDegrees)latitude
          longitude:(CLLocationDegrees)longitude {
  FLLocationConfig *config = [FLLocationConfig sharedConfig];
  config.latitude = latitude;
  config.longitude = longitude;
  [config saveConfig];
}

- (void)setLocation:(CLLocation *)location {
  if (!location) {
    return;
  }

  FLLocationConfig *config = [FLLocationConfig sharedConfig];
  config.latitude = location.coordinate.latitude;
  config.longitude = location.coordinate.longitude;
  config.altitude = location.altitude;
  config.horizontalAccuracy = location.horizontalAccuracy;
  config.verticalAccuracy = location.verticalAccuracy;
  config.speed = location.speed;
  config.course = location.course;
  [config saveConfig];
}

- (CLLocation *)fakeLocation {
  return [[FLLocationConfig sharedConfig] currentFakeLocation];
}

- (void)reset {
  [[FLLocationConfig sharedConfig] reset];
  [[FLLocationConfig sharedConfig] saveConfig];
}

@end