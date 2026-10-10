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
  self.enabled = YES;
  self.fakeAuthorization = YES;
  self.latitude = 21.028511;
  self.longitude = 105.854444;
  self.staticLatitude = 21.028511;
  self.staticLongitude = 105.854444;
  self.altitude = 10.0;
  self.horizontalAccuracy = 5.0;
  self.verticalAccuracy = 5.0;
  self.speed = 0.0;
  self.course = 0.0; // Luôn có hướng hợp lệ (0° Bắc) để la bàn và hình nón xuất hiện ngay
}

- (void)loadSavedConfig {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults objectForKey:@"FLStaticLatitude"]) {
    self.staticLatitude = [defaults doubleForKey:@"FLStaticLatitude"];
    self.staticLongitude = [defaults doubleForKey:@"FLStaticLongitude"];
    // Khi thoát app và mở lại: luôn khôi phục về toạ độ giả lập tĩnh thông thường
    self.latitude = self.staticLatitude;
    self.longitude = self.staticLongitude;
    self.speed = 0.0;
    self.course = [defaults objectForKey:@"FLCourse"] ? [defaults doubleForKey:@"FLCourse"] : 0.0;
    if (self.course < 0.0) self.course = 0.0;
  } else if ([defaults objectForKey:@"FLLatitude"]) {
    self.latitude = [defaults doubleForKey:@"FLLatitude"];
    self.longitude = [defaults doubleForKey:@"FLLongitude"];
    self.staticLatitude = self.latitude;
    self.staticLongitude = self.longitude;
    self.speed = 0.0;
    self.course = [defaults objectForKey:@"FLCourse"] ? [defaults doubleForKey:@"FLCourse"] : 0.0;
    if (self.course < 0.0) self.course = 0.0;
  } else {
    // Lần đầu mở ứng dụng: tự động kích hoạt và lưu giá trị mặc định
    [self reset];
    [self saveConfig];
    return;
  }

  self.enabled = [defaults boolForKey:@"FLEnabled"];
  self.fakeAuthorization = [defaults objectForKey:@"FLFakeAuth"] ? [defaults boolForKey:@"FLFakeAuth"] : YES;
  if ([defaults objectForKey:@"FLAltitude"]) {
    self.altitude = [defaults doubleForKey:@"FLAltitude"];
    self.horizontalAccuracy = [defaults doubleForKey:@"FLHorizontalAccuracy"];
    self.verticalAccuracy = [defaults doubleForKey:@"FLVerticalAccuracy"];
  }
}

- (void)saveConfig {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setDouble:self.latitude forKey:@"FLLatitude"];
  [defaults setDouble:self.longitude forKey:@"FLLongitude"];
  [defaults setDouble:self.staticLatitude forKey:@"FLStaticLatitude"];
  [defaults setDouble:self.staticLongitude forKey:@"FLStaticLongitude"];
  [defaults setBool:self.enabled forKey:@"FLEnabled"];
  [defaults setBool:self.fakeAuthorization forKey:@"FLFakeAuth"];
  [defaults setDouble:self.altitude forKey:@"FLAltitude"];
  [defaults setDouble:self.horizontalAccuracy forKey:@"FLHorizontalAccuracy"];
  [defaults setDouble:self.verticalAccuracy forKey:@"FLVerticalAccuracy"];
  [defaults setDouble:self.speed forKey:@"FLSpeed"];
  [defaults setDouble:self.course forKey:@"FLCourse"];
  [defaults synchronize];
}

- (void)setCoordinate:(CLLocationCoordinate2D)coordinate {
  self.latitude = coordinate.latitude;
  self.longitude = coordinate.longitude;
  self.staticLatitude = coordinate.latitude;
  self.staticLongitude = coordinate.longitude;
}

- (void)saveStaticCoordinate:(CLLocationCoordinate2D)coordinate {
  self.staticLatitude = coordinate.latitude;
  self.staticLongitude = coordinate.longitude;
  self.latitude = coordinate.latitude;
  self.longitude = coordinate.longitude;
  self.speed = 0.0;
  if (self.course < 0.0) self.course = 0.0;
  [self saveConfig];
}

- (void)restoreStaticCoordinate {
  if (self.staticLatitude != 0.0 || self.staticLongitude != 0.0) {
    self.latitude = self.staticLatitude;
    self.longitude = self.staticLongitude;
  }
  self.speed = 0.0;
  if (self.course < 0.0) self.course = 0.0;
  [self saveConfig];
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

  NSDate *now = [NSDate date];
  if (@available(iOS 13.4, *)) {
    CLLocationDirection courseAcc = (self.course >= 0.0) ? 3.0 : -1.0;
    CLLocationSpeed speedAcc = (self.speed >= 0.0) ? 0.5 : -1.0;
    return [[CLLocation alloc] initWithCoordinate:coordinate
                                         altitude:self.altitude
                               horizontalAccuracy:self.horizontalAccuracy
                                 verticalAccuracy:self.verticalAccuracy
                                           course:self.course
                                   courseAccuracy:courseAcc
                                            speed:self.speed
                                    speedAccuracy:speedAcc
                                        timestamp:now];
  }

  return [[CLLocation alloc] initWithCoordinate:coordinate
                                       altitude:self.altitude
                             horizontalAccuracy:self.horizontalAccuracy
                               verticalAccuracy:self.verticalAccuracy
                                         course:self.course
                                          speed:self.speed
                                      timestamp:now];
}

@end