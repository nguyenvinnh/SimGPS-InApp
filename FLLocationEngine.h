#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface FLLocationEngine : NSObject

+ (instancetype)sharedEngine;

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

- (void)setLatitude:(CLLocationDegrees)latitude
          longitude:(CLLocationDegrees)longitude;

- (void)setLocation:(CLLocation *)location;
- (CLLocation *)fakeLocation;
- (void)reset;

@end