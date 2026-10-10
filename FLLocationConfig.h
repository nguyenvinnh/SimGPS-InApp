#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface FLLocationConfig : NSObject

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign) BOOL fakeAuthorization;
@property (nonatomic, assign) CLLocationDegrees latitude;
@property (nonatomic, assign) CLLocationDegrees longitude;
@property (nonatomic, assign) CLLocationDistance altitude;
@property (nonatomic, assign) CLLocationAccuracy horizontalAccuracy;
@property (nonatomic, assign) CLLocationAccuracy verticalAccuracy;
@property (nonatomic, assign) CLLocationSpeed speed;
@property (nonatomic, assign) CLLocationDirection course;

+ (instancetype)sharedConfig;
- (CLLocation *)currentFakeLocation;
- (void)setCoordinate:(CLLocationCoordinate2D)coordinate;
- (void)reset;
- (void)loadSavedConfig;
- (void)saveConfig;

@end