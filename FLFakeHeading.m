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
    // 3.0 độ là độ chính xác rất cao của la bàn
    return 3.0;
}

- (CLLocationDirection)x {
    // Chuyển đổi heading thành vector từ trường mô phỏng (microteslas)
    double rad = _headingVal * M_PI / 180.0;
    return sin(rad) * 25.0;
}

- (CLLocationDirection)y {
    double rad = _headingVal * M_PI / 180.0;
    return cos(rad) * 25.0;
}

- (CLLocationDirection)z {
    return -40.0;
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
