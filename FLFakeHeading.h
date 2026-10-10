#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface FLFakeHeading : CLHeading

- (instancetype)initWithHeading:(CLLocationDirection)heading;

@end
