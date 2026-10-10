#import "FLFakeHeading.h"

@interface FLFakeHeading () {
    CLLocationDirection _headingVal;
    NSDate *_timeVal;
}
@end

@implementation FLFakeHeading

- (instancetype)initWithHeading:(CLLocationDirection)heading {
    self = [super init];
    if (self) {
        _headingVal = heading;
        _timeVal = [NSDate date];
    }
    return self;
}

- (CLLocationDirection)magneticHeading {
    return _headingVal;
}

- (CLLocationDirection)trueHeading {
    return _headingVal;
}

- (CLLocationDirection)headingAccuracy {
    return 3.0;
}

- (CLLocationDirection)x {
    return 0.0;
}

- (CLLocationDirection)y {
    return 0.0;
}

- (CLLocationDirection)z {
    return 0.0;
}

- (NSDate *)timestamp {
    return _timeVal ?: [NSDate date];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[FLFakeHeading allocWithZone:zone] initWithHeading:_headingVal];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<FLFakeHeading: true=%.1f mag=%.1f acc=3.0>", _headingVal, _headingVal];
}

@end
