#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface FLUI : NSObject

+ (instancetype)sharedUI;
- (void)setupFloatingUI;
- (void)showStatus;
- (void)showLocation;

@end