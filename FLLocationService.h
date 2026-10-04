#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface FLLocationService : NSObject

+ (instancetype)sharedService;

- (void)enable;
- (void)disable;
- (void)setLatitude:(CLLocationDegrees)latitude
          longitude:(CLLocationDegrees)longitude;
- (void)setLocation:(CLLocation *)location;
- (void)reset;
- (BOOL)isEnabled;
- (CLLocation *)currentLocation;

@end