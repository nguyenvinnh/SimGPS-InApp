#import "FLUI.h"
#import "FLLocationConfig.h"
#import "FLLocationEngine.h"
#import <CoreLocation/CoreLocation.h>
#import <math.h>

// Window level ngay dưới AssistiveTouch (UIWindowLevelAlert + 3.0 ≈ 2003)
static const CGFloat kFloatWindowLevel = 2002.0;

@interface FLUI ()
@property(nonatomic, strong) UIWindow *floatWindow; // 60×60 — nút nổi kéo được
@property(nonatomic, strong)
    UIWindow *alertWindow; // Full-screen — chứa UIAlertController
@property(nonatomic, strong) UIButton *floatButton;
@end

@implementation FLUI

// MARK: - Open Location Code Core (Chuẩn Google)

static NSString *const kOLCAlphabet = @"23456789CFGHJMPQRVWX";

static int FLAlphabetIndex(unichar c) {
  // Uppercase
  if (c >= 'a' && c <= 'z')
    c = c - 'a' + 'A';
  NSString *s = [NSString stringWithCharacters:&c length:1];
  NSRange r = [kOLCAlphabet rangeOfString:s];
  if (r.location == NSNotFound)
    return -1;
  return (int)r.location;
}

// Decode full code (plus ở vị trí 8) -> center lat/lon
static BOOL FLDecodeFullCode(NSString *code, double *outLat, double *outLon) {
  if (!code)
    return NO;
  NSString *clean = [[code
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]]
      uppercaseString];
  NSRange plusRange = [clean rangeOfString:@"+"];
  if (plusRange.location == NSNotFound)
    return NO;
  if (plusRange.location != 8)
    return NO; // full code bắt buộc + ở 8

  NSString *noPlus = [clean stringByReplacingOccurrencesOfString:@"+"
                                                      withString:@""];
  if (noPlus.length < 2)
    return NO;

  double lat = -90.0;
  double lon = -180.0;
  double latRes = 20.0;
  double lonRes = 20.0;
  NSUInteger pairCount = 0;
  NSUInteger maxPair = MIN(noPlus.length, (NSUInteger)10);

  for (NSUInteger i = 0; i + 1 < maxPair; i += 2) {
    unichar c1 = [noPlus characterAtIndex:i];
    unichar c2 = [noPlus characterAtIndex:i + 1];
    if (c1 == '0' || c2 == '0')
      break; // padding -> dừng
    int latIdx = FLAlphabetIndex(c1);
    int lonIdx = FLAlphabetIndex(c2);
    if (latIdx < 0 || lonIdx < 0)
      return NO;
    if (pairCount == 0 && latIdx > 8)
      return NO; // lat đầu chỉ 0-8 (9 hàng)
    lat += latIdx * latRes;
    lon += lonIdx * lonRes;
    latRes /= 20.0;
    lonRes /= 20.0;
    pairCount++;
  }
  if (pairCount == 0)
    return NO;

  double latArea = latRes * 20.0;
  double lonArea = lonRes * 20.0;

  // Grid refinement (11-15 ký tự)
  if (noPlus.length > 10) {
    for (NSUInteger i = 10; i < noPlus.length && i < 15; i++) {
      unichar c = [noPlus characterAtIndex:i];
      if (c == '0')
        break;
      int idx = FLAlphabetIndex(c);
      if (idx < 0)
        return NO;
      int row = idx / 4;
      int col = idx % 4;
      double latStep = latArea / 5.0;
      double lonStep = lonArea / 4.0;
      lat += row * latStep;
      lon += col * lonStep;
      latArea = latStep;
      lonArea = lonStep;
    }
  }

  double centerLat = lat + latArea / 2.0;
  double centerLon = lon + lonArea / 2.0;

  // Clip/normalize
  if (centerLat < -90)
    centerLat = -90;
  if (centerLat > 90)
    centerLat = 90;
  while (centerLon < -180)
    centerLon += 360;
  while (centerLon >= 180)
    centerLon -= 360;

  if (outLat)
    *outLat = centerLat;
  if (outLon)
    *outLon = centerLon;
  return YES;
}

// Recover short code + reference -> final lat/lon (nearest)
static BOOL FLRecoverAndDecodeShortCode(NSString *shortCode, double refLat,
                                        double refLon, double *outLat,
                                        double *outLon) {
  if (!shortCode)
    return NO;
  NSString *clean = [[shortCode
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]]
      uppercaseString];
  NSRange plusRange = [clean rangeOfString:@"+"];
  if (plusRange.location == NSNotFound)
    return NO;
  NSInteger plusPos = (NSInteger)plusRange.location;
  if (plusPos == 8) {
    // đã là full
    return FLDecodeFullCode(clean, outLat, outLon);
  }
  if (plusPos < 2 || plusPos > 6)
    return NO; // short chỉ 2,4,6 trước +

  NSInteger missing = 8 - plusPos;                              // 2,4,6
  NSInteger prefixLen = 8 - missing;                            // 6,4,2
  double resolution = pow(20.0, 2.0 - (double)prefixLen / 2.0); // 0.05,1,20

  // Clip ref
  double refLatClipped = fmax(-90.0, fmin(90.0, refLat));
  double refLonNorm = refLon;
  while (refLonNorm < -180)
    refLonNorm += 360;
  while (refLonNorm >= 180)
    refLonNorm -= 360;

  double refLatN = refLatClipped + 90.0;
  double refLonN = refLonNorm + 180.0;
  // Normalize 0-360 cho lon
  refLonN = fmod(refLonN, 360.0);
  if (refLonN < 0)
    refLonN += 360.0;

  double prefixLatN = floor(refLatN / resolution) * resolution;
  double prefixLonN = floor(refLonN / resolution) * resolution;

  NSString *digits = [clean stringByReplacingOccurrencesOfString:@"+"
                                                      withString:@""];
  NSUInteger totalPairExpected =
      10 - prefixLen; // số pair digit còn thiếu phải có
  if (digits.length < totalPairExpected && digits.length < 2)
    return NO;

  NSUInteger pairCountInShort = MIN(digits.length, totalPairExpected);
  // đảm bảo chẵn cho pair
  if (pairCountInShort % 2 == 1 && pairCountInShort < totalPairExpected) {
    // nếu lẻ do grid lẫn, giữ nguyên nhưng pairCount phải chẵn
    pairCountInShort = pairCountInShort - 1;
  }
  NSUInteger gridCount = (digits.length > totalPairExpected)
                             ? (digits.length - totalPairExpected)
                             : 0;

  double latOffset = 0;
  double lonOffset = 0;
  double res = resolution / 20.0;

  for (NSUInteger p = 0; p < pairCountInShort / 2; p++) {
    unichar cLat = [digits characterAtIndex:p * 2];
    unichar cLon = [digits characterAtIndex:p * 2 + 1];
    int latIdx = FLAlphabetIndex(cLat);
    int lonIdx = FLAlphabetIndex(cLon);
    if (latIdx < 0 || lonIdx < 0)
      return NO;
    latOffset += latIdx * res;
    lonOffset += lonIdx * res;
    res /= 20.0;
  }

  double latArea = res * 20.0;
  double lonArea = res * 20.0;

  for (NSUInteger g = 0; g < gridCount; g++) {
    unichar c = [digits characterAtIndex:pairCountInShort + g];
    if (c == '0')
      break;
    int idx = FLAlphabetIndex(c);
    if (idx < 0)
      return NO;
    int row = idx / 4;
    int col = idx % 4;
    double latStep = latArea / 5.0;
    double lonStep = lonArea / 4.0;
    latOffset += row * latStep;
    lonOffset += col * lonStep;
    latArea = latStep;
    lonArea = lonStep;
  }

  double candLatN = prefixLatN + latOffset + latArea / 2.0;
  double candLonN = prefixLonN + lonOffset + lonArea / 2.0;

  double candLat = candLatN - 90.0;
  double candLon = candLonN - 180.0;
  while (candLon < -180)
    candLon += 360;
  while (candLon >= 180)
    candLon -= 360;

  // Điều chỉnh nearest: nếu cách ref > resolution/2 thì dịch cell
  double latDiff = refLatClipped - candLat;
  while (latDiff > resolution / 2.0) {
    candLat += resolution;
    latDiff -= resolution;
  }
  while (latDiff < -resolution / 2.0) {
    candLat -= resolution;
    latDiff += resolution;
  }

  double lonDiff = refLonNorm - candLon;
  while (lonDiff > 180)
    lonDiff -= 360;
  while (lonDiff < -180)
    lonDiff += 360;
  while (lonDiff > resolution / 2.0) {
    candLon += resolution;
    lonDiff -= resolution;
  }
  while (lonDiff < -resolution / 2.0) {
    candLon -= resolution;
    lonDiff += resolution;
  }

  while (candLon < -180)
    candLon += 360;
  while (candLon >= 180)
    candLon -= 360;
  if (candLat < -90)
    candLat = -90;
  if (candLat > 90)
    candLat = 90;

  if (outLat)
    *outLat = candLat;
  if (outLon)
    *outLon = candLon;
  return YES;
}

// MARK: - Helper UIWindowScene

+ (UIWindowScene *)activeWindowScene {
  if (@available(iOS 13.0, *)) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
      if ([scene isKindOfClass:[UIWindowScene class]]) {
        if (scene.activationState == UISceneActivationStateForegroundActive ||
            scene.activationState == UISceneActivationStateForegroundInactive) {
          return (UIWindowScene *)scene;
        }
      }
    }
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
      if ([scene isKindOfClass:[UIWindowScene class]]) {
        return (UIWindowScene *)scene;
      }
    }
  }
  return nil;
}

+ (UIWindow *)createWindowWithFrame:(CGRect)frame {
  UIWindow *window = nil;
  if (@available(iOS 13.0, *)) {
    UIWindowScene *scene = [self activeWindowScene];
    if (scene) {
      window = [[UIWindow alloc] initWithWindowScene:scene];
      window.frame = frame;
    }
  }
  if (!window) {
    window = [[UIWindow alloc] initWithFrame:frame];
  }
  return window;
}

// MARK: - Singleton

+ (instancetype)sharedUI {
  static FLUI *ui;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    ui = [[self alloc] init];
    [[NSNotificationCenter defaultCenter]
        addObserver:ui
           selector:@selector(appDidBecomeActive)
               name:UIApplicationDidBecomeActiveNotification
             object:nil];
  });
  return ui;
}

- (void)appDidBecomeActive {
  [self setupFloatingUI];
}

// MARK: - Floating UI

- (void)setupFloatingUI {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindowScene *activeScene = [FLUI activeWindowScene];

    if (self.floatWindow) {
      if (@available(iOS 13.0, *)) {
        if (activeScene && self.floatWindow.windowScene != activeScene) {
          self.floatWindow.windowScene = activeScene;
        }
      }
      self.floatWindow.hidden = NO;
      return;
    }

    self.floatWindow = [FLUI createWindowWithFrame:CGRectMake(20, 120, 60, 60)];
    self.floatWindow.windowLevel = kFloatWindowLevel;
    self.floatWindow.backgroundColor = [UIColor clearColor];

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    self.floatWindow.rootViewController = rootVC;
    self.floatWindow.hidden = NO;

    self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatButton.frame = CGRectMake(0, 0, 60, 60);
    self.floatButton.layer.cornerRadius = 30.0;
    self.floatButton.layer.masksToBounds = NO;
    self.floatButton.layer.borderWidth = 2.0;
    self.floatButton.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:0.8].CGColor;

    self.floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatButton.layer.shadowOpacity = 0.6;
    self.floatButton.layer.shadowRadius = 6;
    self.floatButton.layer.shadowOffset = CGSizeMake(0, 3);

    [self updateButtonState];

    [self.floatButton addTarget:self
                         action:@selector(floatButtonTapped)
               forControlEvents:UIControlEventTouchUpInside];
    [rootVC.view addSubview:self.floatButton];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(handlePan:)];
    [self.floatButton addGestureRecognizer:pan];
  });
}

- (void)updateButtonState {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.floatButton)
      return;
    BOOL on = [FLLocationEngine sharedEngine].isEnabled;
    if (on) {
      self.floatButton.backgroundColor = [UIColor colorWithRed:0.15
                                                         green:0.75
                                                          blue:0.25
                                                         alpha:0.92];
      [self.floatButton setTitle:@"📍\nON" forState:UIControlStateNormal];
    } else {
      self.floatButton.backgroundColor = [UIColor colorWithRed:0.85
                                                         green:0.18
                                                          blue:0.18
                                                         alpha:0.92];
      [self.floatButton setTitle:@"📍\nOFF" forState:UIControlStateNormal];
    }
    self.floatButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.floatButton.titleLabel.numberOfLines = 2;
    self.floatButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.floatButton setTitleColor:[UIColor whiteColor]
                           forState:UIControlStateNormal];
    self.floatButton.layer.cornerRadius = 30.0;
  });
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
  CGPoint delta = [pan translationInView:self.floatWindow];
  CGRect frame = self.floatWindow.frame;
  CGSize screen = [UIScreen mainScreen].bounds.size;

  frame.origin.x += delta.x;
  frame.origin.y += delta.y;

  frame.origin.x = MAX(0, MIN(frame.origin.x, screen.width - frame.size.width));
  frame.origin.y =
      MAX(20, MIN(frame.origin.y, screen.height - frame.size.height - 20));

  self.floatWindow.frame = frame;
  [pan setTranslation:CGPointZero inView:self.floatWindow];
}

// MARK: - Parser mới (hỗ trợ CLGeocoder như note.txt)

- (NSDictionary *)extractPlusCodeInfoFromString:(NSString *)input {
  if (!input)
    return nil;
  NSString *pattern =
      @"[23456789CFGHJMPQRVWX]{2,8}\\+[23456789CFGHJMPQRVWX]{2,7}";
  NSError *err = nil;
  NSRegularExpression *regex = [NSRegularExpression
      regularExpressionWithPattern:pattern
                           options:NSRegularExpressionCaseInsensitive
                             error:&err];
  if (err)
    return nil;
  NSTextCheckingResult *match =
      [regex firstMatchInString:input
                        options:0
                          range:NSMakeRange(0, input.length)];
  if (!match)
    return nil;
  NSString *plusCode = [input substringWithRange:match.range];
  NSString *place = @"";
  NSUInteger end = NSMaxRange(match.range);
  if (end < input.length) {
    place = [[input substringFromIndex:end]
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if ([place hasPrefix:@","]) {
      place = [[place substringFromIndex:1]
          stringByTrimmingCharactersInSet:
              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
  }
  return @{@"code" : plusCode, @"place" : place};
}

- (void)parseCoordinateString:(NSString *)input
                   completion:(void (^)(BOOL success, double lat, double lon,
                                        NSString *error))completion {
  NSString *trimmed = [input
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    if (completion)
      completion(NO, 0, 0, @"Chuỗi rỗng");
    return;
  }

  // 1. Thử dạng số: "35.7619, 139.1578"
  NSError *reErr = nil;
  NSRegularExpression *numRegex = [NSRegularExpression
      regularExpressionWithPattern:
          @"(-?\\d+(?:\\.\\d+)?)[\\s,]+(-?\\d+(?:\\.\\d+)?)"
                           options:0
                             error:&reErr];
  NSTextCheckingResult *numMatch =
      [numRegex firstMatchInString:trimmed
                           options:0
                             range:NSMakeRange(0, trimmed.length)];
  if (numMatch && numMatch.numberOfRanges >= 3) {
    NSString *latStr = [trimmed substringWithRange:[numMatch rangeAtIndex:1]];
    NSString *lonStr = [trimmed substringWithRange:[numMatch rangeAtIndex:2]];
    double lat = [latStr doubleValue];
    double lon = [lonStr doubleValue];
    if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
      if (completion)
        completion(YES, lat, lon, nil);
      return;
    }
  }

  // 2. Plus Code
  NSDictionary *info = [self extractPlusCodeInfoFromString:trimmed];
  if (!info) {
    if (completion)
      completion(NO, 0, 0, @"Không tìm thấy tọa độ hoặc Plus Code");
    return;
  }
  NSString *plusCode = info[@"code"];
  NSString *placeName = info[@"place"];
  NSRange plusRange = [plusCode rangeOfString:@"+"];
  NSInteger plusPos = (NSInteger)plusRange.location;

  if (plusPos == 8) {
    double lat, lon;
    if (FLDecodeFullCode(plusCode, &lat, &lon)) {
      if (completion)
        completion(YES, lat, lon, nil);
    } else {
      if (completion)
        completion(NO, 0, 0, @"Plus Code đầy đủ không hợp lệ");
    }
    return;
  } else {
    // Short Code
    if (placeName.length > 0) {
      // Dùng CLGeocoder như note.txt đề xuất
      CLGeocoder *geocoder = [[CLGeocoder alloc] init];
      [geocoder
          geocodeAddressString:placeName
             completionHandler:^(NSArray<CLPlacemark *> *_Nullable placemarks,
                                 NSError *_Nullable error) {
               double refLat, refLon;
               if (placemarks.count > 0 && placemarks.firstObject.location) {
                 refLat = placemarks.firstObject.location.coordinate.latitude;
                 refLon = placemarks.firstObject.location.coordinate.longitude;
                 NSLog(@"[SimGPS-InApp] Geocode '%@' -> %.6f, %.6f", placeName,
                       refLat, refLon);
               } else {
                 FLLocationConfig *cfg = [FLLocationConfig sharedConfig];
                 if (cfg.latitude != 0 || cfg.longitude != 0) {
                   refLat = cfg.latitude;
                   refLon = cfg.longitude;
                 } else {
                   refLat = 34.6937;
                   refLon = 135.5023; // fallback Osaka
                 }
                 NSLog(@"[SimGPS-InApp] Geocode fail for '%@', fallback %.6f, "
                       @"%.6f",
                       placeName, refLat, refLon);
               }
               double outLat, outLon;
               if (FLRecoverAndDecodeShortCode(plusCode, refLat, refLon,
                                               &outLat, &outLon)) {
                 dispatch_async(dispatch_get_main_queue(), ^{
                   if (completion)
                     completion(YES, outLat, outLon, nil);
                 });
               } else {
                 dispatch_async(dispatch_get_main_queue(), ^{
                   if (completion)
                     completion(NO, 0, 0, @"Không thể khôi phục Short Code");
                 });
               }
             }];
    } else {
      FLLocationConfig *cfg = [FLLocationConfig sharedConfig];
      double refLat, refLon;
      if (cfg.latitude != 0 || cfg.longitude != 0) {
        refLat = cfg.latitude;
        refLon = cfg.longitude;
      } else {
        refLat = 34.6937;
        refLon = 135.5023;
      }
      double outLat, outLon;
      if (FLRecoverAndDecodeShortCode(plusCode, refLat, refLon, &outLat,
                                      &outLon)) {
        if (completion)
          completion(YES, outLat, outLon, nil);
      } else {
        if (completion)
          completion(NO, 0, 0,
                     @"Short Code thiếu vị trí tham chiếu. Hãy nhập kèm địa "
                     @"danh VD: PF35+Q8 Osaka, Japan");
      }
    }
    return;
  }
}

// MARK: - Alert Window

- (void)floatButtonTapped {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.alertWindow)
      return;

    FLLocationConfig *config = [FLLocationConfig sharedConfig];
    FLLocationEngine *engine = [FLLocationEngine sharedEngine];

    CGRect screen = [UIScreen mainScreen].bounds;
    self.alertWindow = [FLUI createWindowWithFrame:screen];
    self.alertWindow.windowLevel = kFloatWindowLevel + 1;
    self.alertWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];

    UIViewController *hostVC = [[UIViewController alloc] init];
    hostVC.view.backgroundColor = [UIColor clearColor];
    self.alertWindow.rootViewController = hostVC;
    self.alertWindow.hidden = NO;
    [self.alertWindow makeKeyAndVisible];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"📍 SimGPS-InApp"
                         message:@"Dán tọa độ số hoặc Plus Code\n(vd: 35.7619, "
                                 @"139.1578 hoặc 8FVC9G8F+6W hoặc PF35+Q8 "
                                 @"Osaka, Japan)"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
      tf.placeholder = @"Tọa độ hoặc Plus Code";
      tf.keyboardType = UIKeyboardTypeDefault;
      if (config.latitude != 0.0 || config.longitude != 0.0) {
        tf.text = [NSString
            stringWithFormat:@"%.6f, %.6f", config.latitude, config.longitude];
      }
    }];

    UIAlertAction *saveAction = [UIAlertAction
        actionWithTitle:@"✅ Lưu & Bật"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *a) {
                  NSString *rawText = alert.textFields[0].text;
                  // Parse async hỗ trợ geocoding
                  [[FLUI sharedUI]
                      parseCoordinateString:rawText
                                 completion:^(BOOL success, double lat,
                                              double lon, NSString *error) {
                                   if (success) {
                                     [engine setLatitude:lat longitude:lon];
                                     engine.enabled = YES;
                                     NSLog(@"[SimGPS-InApp] Set to %.6f, %.6f",
                                           lat, lon);
                                   } else {
                                     NSLog(@"[SimGPS-InApp] Parse fail: %@ "
                                           @"input=%@",
                                           error, rawText);
                                     // Hiển thị lỗi nhẹ qua log, không set
                                   }
                                   [[FLUI sharedUI] updateButtonState];
                                   [[FLUI sharedUI] dismissAlertWindow];
                                 }];
                }];

    BOOL isOn = engine.isEnabled;
    NSString *toggleTitle =
        isOn ? @"⏸ Tắt Fake Location" : @"▶ Bật Fake Location";
    UIAlertAction *toggleAction =
        [UIAlertAction actionWithTitle:toggleTitle
                                 style:isOn ? UIAlertActionStyleDestructive
                                            : UIAlertActionStyleDefault
                               handler:^(UIAlertAction *a) {
                                 engine.enabled = !engine.isEnabled;
                                 [self updateButtonState];
                                 [self dismissAlertWindow];
                               }];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:@"✖ Hủy"
                                 style:UIAlertActionStyleCancel
                               handler:^(UIAlertAction *a) {
                                 [self dismissAlertWindow];
                               }];

    [alert addAction:saveAction];
    [alert addAction:toggleAction];
    [alert addAction:cancelAction];

    [hostVC presentViewController:alert animated:YES completion:nil];
  });
}

- (void)dismissAlertWindow {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.alertWindow.hidden = YES;
    self.alertWindow = nil;
  });
}

// MARK: - Logging

- (void)showStatus {
  FLLocationEngine *engine = [FLLocationEngine sharedEngine];
  NSLog(@"[SimGPS-InApp] enabled=%@", engine.isEnabled ? @"YES" : @"NO");
}

- (void)showLocation {
  CLLocation *loc = [[FLLocationEngine sharedEngine] fakeLocation];
  if (!loc) {
    NSLog(@"[SimGPS-InApp] no fake location configured");
    return;
  }
  NSLog(@"[SimGPS-InApp] lat=%.6f lon=%.6f alt=%.2f", loc.coordinate.latitude,
        loc.coordinate.longitude, loc.altitude);
}

@end