#import "FLUI.h"
#import "FLLocationConfig.h"
#import "FLLocationEngine.h"
#import "FLRouteSimulator.h"
#import "FLPlusCode.h"
#import "FLGPXParser.h"
#import <CoreLocation/CoreLocation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kFloatWindowLevel = 2002.0;

@interface FLUI () <UIDocumentPickerDelegate>

@property (nonatomic, strong) UIWindow *floatWindow;
@property (nonatomic, strong) UIWindow *alertWindow;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) NSTimer *hudTimer;

@end

@implementation FLUI

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
        self.floatButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.8].CGColor;
        self.floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
        self.floatButton.layer.shadowOpacity = 0.6;
        self.floatButton.layer.shadowRadius = 6;
        self.floatButton.layer.shadowOffset = CGSizeMake(0, 3);

        [self updateButtonState];

        [self.floatButton addTarget:self
                             action:@selector(floatButtonTapped)
                   forControlEvents:UIControlEventTouchUpInside];
        [rootVC.view addSubview:self.floatButton];

        if (!self.hudTimer) {
            self.hudTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
                [[FLUI sharedUI] updateButtonState];
            }];
        }

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(handlePan:)];
        [self.floatButton addGestureRecognizer:pan];
    });
}

- (void)updateButtonState {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.floatButton) return;

        FLRouteSimulator *sim = [FLRouteSimulator sharedSimulator];
        if (sim.state == FLRouteStateRunning) {
            self.floatButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.58 blue:0.96 alpha:0.95];
            [self.floatButton setTitle:[NSString stringWithFormat:@"🚗\n%.0fkm", sim.currentSpeedKmh] forState:UIControlStateNormal];
        } else if (sim.state == FLRouteStatePaused) {
            self.floatButton.backgroundColor = [UIColor colorWithRed:0.95 green:0.60 blue:0.0 alpha:0.95];
            [self.floatButton setTitle:@"🚗\nPAUSE" forState:UIControlStateNormal];
        } else {
            BOOL on = [FLLocationEngine sharedEngine].isEnabled;
            if (on) {
                self.floatButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.75 blue:0.25 alpha:0.92];
                [self.floatButton setTitle:@"📍\nON" forState:UIControlStateNormal];
            } else {
                self.floatButton.backgroundColor = [UIColor colorWithRed:0.85 green:0.18 blue:0.18 alpha:0.92];
                [self.floatButton setTitle:@"📍\nOFF" forState:UIControlStateNormal];
            }
        }

        self.floatButton.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        self.floatButton.titleLabel.numberOfLines = 2;
        self.floatButton.titleLabel.textAlignment = NSTextAlignmentCenter;
        [self.floatButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
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
    frame.origin.y = MAX(20, MIN(frame.origin.y, screen.height - frame.size.height - 20));

    self.floatWindow.frame = frame;
    [pan setTranslation:CGPointZero inView:self.floatWindow];
}

// MARK: - Main Settings Alert

- (void)floatButtonTapped {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.alertWindow) return;

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

        NSString *authStatus = engine.fakeAuthorization ? @"🛡️ Quyền vị trí: Đang giả lập (Đã cấp quyền)" : @"🛡️ Quyền vị trí: Tắt giả lập";
        NSString *alertMessage = [NSString stringWithFormat:@"%@\n\nDán tọa độ số hoặc Plus Code\n(vd: 35.7619, 139.1578 hoặc 8FVC9G8F+6W hoặc PF35+Q8 Osaka, Japan)", authStatus];

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"📍 SimGPS-InApp"
                                                                       message:alertMessage
                                                                preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = @"Tọa độ hoặc Plus Code";
            tf.keyboardType = UIKeyboardTypeDefault;
            if (config.latitude != 0.0 || config.longitude != 0.0) {
                tf.text = [NSString stringWithFormat:@"%.6f, %.6f", config.latitude, config.longitude];
            }
        }];

        UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"✅ Lưu & Bật"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction *a) {
            NSString *rawText = alert.textFields[0].text;
            [FLPlusCode parseCoordinateString:rawText completion:^(BOOL success, double lat, double lon, NSString *error) {
                if (success) {
                    [engine setLatitude:lat longitude:lon];
                    engine.enabled = YES;
                }
                [[FLUI sharedUI] updateButtonState];
                [[FLUI sharedUI] dismissAlertWindow];
            }];
        }];

        FLRouteSimulator *sim = [FLRouteSimulator sharedSimulator];
        NSString *routeTitle = sim.state == FLRouteStateRunning ? [NSString stringWithFormat:@"🚗 Lộ trình GPX (%.0f km/h)...", sim.currentSpeedKmh] : @"🚗 Mô phỏng Lộ trình GPX...";
        UIAlertAction *routeAction = [UIAlertAction actionWithTitle:routeTitle
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction *a) {
            [self showRouteSimulatorMenu];
        }];

        BOOL isOn = engine.isEnabled;
        NSString *toggleTitle = isOn ? @"⏸ Tắt Fake Location" : @"▶ Bật Fake Location";
        UIAlertAction *toggleAction = [UIAlertAction actionWithTitle:toggleTitle
                                                               style:isOn ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction *a) {
            engine.enabled = !engine.isEnabled;
            [self updateButtonState];
            [self dismissAlertWindow];
        }];

        NSString *authToggleTitle = engine.fakeAuthorization ? @"🛡️ Tắt giả lập quyền vị trí" : @"🛡️ Bật giả lập quyền vị trí";
        UIAlertAction *authToggleAction = [UIAlertAction actionWithTitle:authToggleTitle
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *a) {
            engine.fakeAuthorization = !engine.fakeAuthorization;
            [self dismissAlertWindow];
        }];

        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"✖ Hủy"
                                                               style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction *a) {
            [self dismissAlertWindow];
        }];

        [alert addAction:saveAction];
        [alert addAction:routeAction];
        [alert addAction:toggleAction];
        [alert addAction:authToggleAction];
        [alert addAction:cancelAction];

        [hostVC presentViewController:alert animated:YES completion:nil];
    });
}

// MARK: - Route Simulator Menu

- (void)showRouteSimulatorMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        FLRouteSimulator *sim = [FLRouteSimulator sharedSimulator];

        NSString *stateDesc = @"Chưa chạy";
        if (sim.state == FLRouteStateRunning) {
            stateDesc = [NSString stringWithFormat:@"Đang chạy (%.0f km/h) - Tiến độ: %.1f%%", sim.currentSpeedKmh, sim.progress * 100.0];
        } else if (sim.state == FLRouteStatePaused) {
            stateDesc = [NSString stringWithFormat:@"Tạm dừng (Tiến độ: %.1f%%)", sim.progress * 100.0];
        } else if (sim.state == FLRouteStateCompleted) {
            stateDesc = @"Đã về đích!";
        }

        NSString *routeName = sim.routeName.length > 0 ? sim.routeName : @"Chưa chọn file";
        NSString *message = [NSString stringWithFormat:@"📁 File: %@\n⚡ Tốc độ tối đa: %.0f km/h\n🧭 Hướng đi: %.0f°\n📊 Trạng thái: %@",
                             routeName, sim.maxSpeedKmh, sim.currentCourse, stateDesc];

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🚗 Mô phỏng Lái xe Thực tế"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];

        // 1. Nút chọn file GPX từ Files
        [alert addAction:[UIAlertAction actionWithTitle:@"📁 Tải lên file GPX từ Files"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self openGPXDocumentPicker];
        }]];

        // 2. Nút cài đặt tốc độ tối đa
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"⚡ Đổi tốc độ tối đa (Hiện tại: %.0f km/h)", sim.maxSpeedKmh]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self promptMaxSpeed];
        }]];

        // 3. Nút điều khiển chạy / dừng
        if (sim.state == FLRouteStateRunning) {
            [alert addAction:[UIAlertAction actionWithTitle:@"⏸ Tạm dừng lái xe"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction * _Nonnull action) {
                [sim pause];
                [self updateButtonState];
                [self showRouteSimulatorMenu];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"⏹ Dừng hẳn lộ trình"
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction * _Nonnull action) {
                [sim stop];
                [self updateButtonState];
                [self showRouteSimulatorMenu];
            }]];
        } else if (sim.state == FLRouteStatePaused) {
            [alert addAction:[UIAlertAction actionWithTitle:@"▶ Tiếp tục lái xe"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction * _Nonnull action) {
                [sim resume];
                [self updateButtonState];
                [self dismissAlertWindow];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"⏹ Dừng hẳn lộ trình"
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction * _Nonnull action) {
                [sim stop];
                [self updateButtonState];
                [self showRouteSimulatorMenu];
            }]];
        } else {
            [alert addAction:[UIAlertAction actionWithTitle:@"▶ Bắt đầu lái xe mô phỏng"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction * _Nonnull action) {
                if (!sim.hasValidRoute) {
                    NSArray<NSString *> *locals = [FLGPXParser findLocalGPXFiles];
                    if (locals.count > 0) {
                        [sim loadGPXFromURL:[NSURL fileURLWithPath:locals.firstObject] error:nil];
                    }
                }
                if (sim.hasValidRoute) {
                    [sim start];
                    [self updateButtonState];
                    [self dismissAlertWindow];
                } else {
                    [self showAlertWithMessage:@"Vui lòng chọn hoặc tải lên file GPX trước!" title:@"Chưa có lộ trình"];
                }
            }]];
        }

        // 4. Các file gpx có sẵn
        NSArray<NSString *> *localGPXFiles = [FLGPXParser findLocalGPXFiles];
        if (localGPXFiles.count > 0) {
            for (NSString *filePath in localGPXFiles) {
                NSString *fileName = filePath.lastPathComponent;
                [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📄 Nạp có sẵn: %@", fileName]
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
                    NSString *err = nil;
                    BOOL ok = [sim loadGPXFromURL:[NSURL fileURLWithPath:filePath] error:&err];
                    if (ok) {
                        [self showRouteSimulatorMenu];
                    } else {
                        [self showAlertWithMessage:err title:@"Lỗi nạp GPX"];
                    }
                }]];
            }
        }

        [alert addAction:[UIAlertAction actionWithTitle:@"✖ Đóng"
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self dismissAlertWindow];
        }]];

        [self.alertWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

- (void)openGPXDocumentPicker {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIDocumentPickerViewController *picker = nil;
        if (@available(iOS 14.0, *)) {
            UTType *gpxType = [UTType typeWithFilenameExtension:@"gpx"];
            NSArray<UTType *> *types = gpxType ? @[gpxType, UTTypeItem] : @[UTTypeItem];
            picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        } else {
            picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item", @"public.data", @"public.xml"]
                                                                            inMode:UIDocumentPickerModeImport];
        }
        picker.delegate = self;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        [self.alertWindow.rootViewController presentViewController:picker animated:YES completion:nil];
    });
}

- (void)promptMaxSpeed {
    dispatch_async(dispatch_get_main_queue(), ^{
        FLRouteSimulator *sim = [FLRouteSimulator sharedSimulator];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚡ Cài đặt Tốc độ Tối đa"
                                                                       message:@"Nhập tốc độ tối đa mong muốn (km/h).\nHệ thống tự động hãm phanh khi vào cua gắt."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"Ví dụ: 40, 60, 80";
            textField.keyboardType = UIKeyboardTypeNumberPad;
            textField.text = [NSString stringWithFormat:@"%.0f", sim.maxSpeedKmh];
        }];

        [alert addAction:[UIAlertAction actionWithTitle:@"✅ Lưu"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            NSString *val = alert.textFields.firstObject.text;
            double speed = [val doubleValue];
            if (speed > 0) {
                sim.maxSpeedKmh = speed;
            }
            [self showRouteSimulatorMenu];
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"✖ Hủy"
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self showRouteSimulatorMenu];
        }]];

        [self.alertWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// MARK: - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) {
        [self showRouteSimulatorMenu];
        return;
    }
    NSURL *fileURL = urls.firstObject;
    BOOL accessing = [fileURL startAccessingSecurityScopedResource];

    NSString *err = nil;
    BOOL ok = [[FLRouteSimulator sharedSimulator] loadGPXFromURL:fileURL error:&err];
    if (accessing) {
        [fileURL stopAccessingSecurityScopedResource];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (ok) {
            [self showRouteSimulatorMenu];
        } else {
            [self showAlertWithMessage:err title:@"Lỗi nạp GPX"];
        }
    });
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self documentPicker:controller didPickDocumentsAtURLs:@[ url ]];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self showRouteSimulatorMenu];
}

- (void)showAlertWithMessage:(NSString *)message title:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"Thông báo"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self showRouteSimulatorMenu];
        }]];
        [self.alertWindow.rootViewController presentViewController:alert animated:YES completion:nil];
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