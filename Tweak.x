#import <UIKit/UIKit.h>
#import "FLLocationService.h"
#import "FLUI.h"

%ctor {
    @autoreleasepool {
        [[FLUI sharedUI] showStatus];
        [[FLUI sharedUI] showLocation];
        
        // Đăng ký thông báo khi app hoàn tất khởi chạy
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            [[FLUI sharedUI] setupFloatingUI];
        }];

        // Lắng nghe khi app trở nên active
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            [[FLUI sharedUI] setupFloatingUI];
        }];
        
        if (@available(iOS 13.0, *)) {
            [[NSNotificationCenter defaultCenter] addObserverForName:UISceneDidActivateNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification * _Nonnull note) {
                [[FLUI sharedUI] setupFloatingUI];
            }];
        }
    }
}