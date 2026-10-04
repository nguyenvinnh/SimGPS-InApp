#import "FLUI.h"
#import "FLLocationEngine.h"
#import "FLLocationConfig.h"
#import <CoreLocation/CoreLocation.h>

// Mức window bằng UIWindowLevelAlert + 2.0 để ngay dưới AssistiveTouch (khoảng UIWindowLevelAlert + 3.0)
static const CGFloat kFloatWindowLevel = 2002.0;

@interface FLUI ()
@property (nonatomic, strong) UIWindow *floatWindow;   // 60x60 — chứa nút nổi kéo được
@property (nonatomic, strong) UIWindow *alertWindow;   // Full screen — chứa UIAlertController
@property (nonatomic, strong) UIButton *floatButton;
@end

@implementation FLUI

// MARK: - Parser Tọa Độ

static BOOL FLParseCoordinateString(NSString *input, double *outLat, double *outLon) {
    if (!input || input.length == 0) return NO;

    // Pattern tìm 2 số thực (có thể âm, có dấu thập phân) phân cách bởi dấu phẩy/khoảng trắng
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(-?\\d+(?:\\.\\d+)?)[\\s,]+(-?\\d+(?:\\.\\d+)?)"
                                                                           options:0
                                                                             error:&error];
    if (error) return NO;

    NSTextCheckingResult *match = [regex firstMatchInString:input options:0 range:NSMakeRange(0, input.length)];
    if (match && match.numberOfRanges >= 3) {
        NSString *latStr = [input substringWithRange:[match rangeAtIndex:1]];
        NSString *lonStr = [input substringWithRange:[match rangeAtIndex:2]];
        if (outLat) *outLat = [latStr doubleValue];
        if (outLon) *outLon = [lonStr doubleValue];
        return YES;
    }

    return NO;
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
        // Fallback lấy bất kỳ UIWindowScene nào nếu chưa có scene active
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
        [[NSNotificationCenter defaultCenter] addObserver:ui
                                                 selector:@selector(appDidBecomeActive)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    });
    return ui;
}

- (void)appDidBecomeActive {
    [self setupFloatingUI];
}

// MARK: - Setup Floating Button

- (void)setupFloatingUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *activeScene = [FLUI activeWindowScene];
        
        // Nếu đã khởi tạo rồi nhưng scene bị thay đổi hoặc chưa gán scene
        if (self.floatWindow) {
            if (@available(iOS 13.0, *)) {
                if (activeScene && self.floatWindow.windowScene != activeScene) {
                    self.floatWindow.windowScene = activeScene;
                }
            }
            self.floatWindow.hidden = NO;
            return;
        }

        // Window nhỏ 60x60 chỉ chứa nút tròn nổi
        self.floatWindow = [FLUI createWindowWithFrame:CGRectMake(20, 120, 60, 60)];
        self.floatWindow.windowLevel = kFloatWindowLevel;
        self.floatWindow.backgroundColor = [UIColor clearColor];

        UIViewController *rootVC = [[UIViewController alloc] init];
        rootVC.view.backgroundColor = [UIColor clearColor];
        self.floatWindow.rootViewController = rootVC;
        self.floatWindow.hidden = NO;

        // Nút tròn
        self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatButton.frame = CGRectMake(0, 0, 60, 60);
        self.floatButton.layer.cornerRadius = 30.0;
        self.floatButton.layer.masksToBounds = NO;   // NO để shadow hiện ra
        self.floatButton.layer.borderWidth = 2.0;
        self.floatButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.8].CGColor;

        // Shadow
        self.floatButton.layer.shadowColor   = [UIColor blackColor].CGColor;
        self.floatButton.layer.shadowOpacity = 0.6;
        self.floatButton.layer.shadowRadius  = 6;
        self.floatButton.layer.shadowOffset  = CGSizeMake(0, 3);

        [self updateButtonState];

        [self.floatButton addTarget:self
                             action:@selector(floatButtonTapped)
                   forControlEvents:UIControlEventTouchUpInside];
        [rootVC.view addSubview:self.floatButton];

        // Pan gesture kéo thả
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                       initWithTarget:self action:@selector(handlePan:)];
        [self.floatButton addGestureRecognizer:pan];
    });
}

// MARK: - Button Appearance

- (void)updateButtonState {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.floatButton) return;
        BOOL on = [FLLocationEngine sharedEngine].isEnabled;
        if (on) {
            self.floatButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.75 blue:0.25 alpha:0.92];
            [self.floatButton setTitle:@"📍\nON" forState:UIControlStateNormal];
        } else {
            self.floatButton.backgroundColor = [UIColor colorWithRed:0.85 green:0.18 blue:0.18 alpha:0.92];
            [self.floatButton setTitle:@"📍\nOFF" forState:UIControlStateNormal];
        }
        self.floatButton.titleLabel.font          = [UIFont boldSystemFontOfSize:12];
        self.floatButton.titleLabel.numberOfLines = 2;
        self.floatButton.titleLabel.textAlignment = NSTextAlignmentCenter;
        [self.floatButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.floatButton.layer.cornerRadius = 30.0;
    });
}

// MARK: - Pan Gesture (giới hạn trong màn hình)

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint delta  = [pan translationInView:self.floatWindow];
    CGRect  frame  = self.floatWindow.frame;
    CGSize  screen = [UIScreen mainScreen].bounds.size;

    frame.origin.x += delta.x;
    frame.origin.y += delta.y;

    // Kẹp trong biên màn hình
    frame.origin.x = MAX(0, MIN(frame.origin.x, screen.width  - frame.size.width));
    frame.origin.y = MAX(20, MIN(frame.origin.y, screen.height - frame.size.height - 20));

    self.floatWindow.frame = frame;
    [pan setTranslation:CGPointMake(0, 0) inView:self.floatWindow];
}

// MARK: - Alert trên window FULL SCREEN riêng

- (void)floatButtonTapped {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.alertWindow) return;   // Chặn mở 2 lần

        FLLocationConfig *config = [FLLocationConfig sharedConfig];
        FLLocationEngine *engine = [FLLocationEngine sharedEngine];

        // Window full screen cao hơn floatWindow 1 bậc để present alert không bị crop
        CGRect screen = [UIScreen mainScreen].bounds;
        self.alertWindow = [FLUI createWindowWithFrame:screen];
        self.alertWindow.windowLevel = kFloatWindowLevel + 1;
        self.alertWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];

        UIViewController *hostVC = [[UIViewController alloc] init];
        hostVC.view.backgroundColor = [UIColor clearColor];
        self.alertWindow.rootViewController = hostVC;
        self.alertWindow.hidden = NO;
        [self.alertWindow makeKeyAndVisible];

        // UIAlertController
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"📍 Fake Location"
                                               message:@"Dán tọa độ (Vĩ độ, Kinh độ)\nvỉ dụ: 35.7619257, 139.1578853"
                                        preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = @"Vĩ độ, Kinh độ (vd: 35.7619, 139.1578)";
            tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            if (config.latitude != 0 || config.longitude != 0) {
                tf.text = [NSString stringWithFormat:@"%.6f, %.6f", config.latitude, config.longitude];
            }
        }];

        // Action: Lưu & Bật
        UIAlertAction *saveAction =
            [UIAlertAction actionWithTitle:@"✅ Lưu & Bật"
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *a) {
            NSString *rawText = alert.textFields[0].text;
            double lat = 0.0, lon = 0.0;
            if (FLParseCoordinateString(rawText, &lat, &lon)) {
                [engine setLatitude:lat longitude:lon];
                engine.enabled = YES;
            } else {
                // Nếu người dùng nhập sai định dạng thì báo lỗi hoặc không lưu
                NSLog(@"[FakeLocation] Chuỗi tọa độ không hợp lệ: %@", rawText);
            }
            [self updateButtonState];
            [self dismissAlertWindow];
        }];

        // Action: Toggle ON / OFF
        BOOL isOn = engine.isEnabled;
        NSString *toggleTitle = isOn ? @"⏸ Tắt Fake Location" : @"▶️ Bật Fake Location";
        UIAlertAction *toggleAction =
            [UIAlertAction actionWithTitle:toggleTitle
                                     style:isOn ? UIAlertActionStyleDestructive
                                               : UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *a) {
            engine.enabled = !engine.isEnabled;
            [self updateButtonState];
            [self dismissAlertWindow];
        }];

        // Action: Hủy
        UIAlertAction *cancelAction =
            [UIAlertAction actionWithTitle:@"✖️ Hủy"
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
    NSLog(@"[FakeLocation] enabled=%@", engine.isEnabled ? @"YES" : @"NO");
}

- (void)showLocation {
    CLLocation *loc = [[FLLocationEngine sharedEngine] fakeLocation];
    if (!loc) {
        NSLog(@"[FakeLocation] no fake location configured");
        return;
    }
    NSLog(@"[FakeLocation] lat=%.6f lon=%.6f alt=%.2f",
          loc.coordinate.latitude,
          loc.coordinate.longitude,
          loc.altitude);
}

@end