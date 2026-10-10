#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

typedef NS_ENUM(NSInteger, FLRouteState) {
    FLRouteStateIdle,
    FLRouteStateRunning,
    FLRouteStatePaused,
    FLRouteStateCompleted
};

@interface FLRouteSimulator : NSObject

@property (nonatomic, assign, readonly) FLRouteState state;
@property (nonatomic, assign) double maxSpeedKmh; // Tốc độ tối đa (km/h)
@property (nonatomic, assign, readonly) double currentSpeedKmh; // Tốc độ hiện tại (km/h)
@property (nonatomic, assign, readonly) double currentCourse; // Góc xoay hướng đi (độ)
@property (nonatomic, assign, readonly) double progress; // 0.0 - 1.0
@property (nonatomic, copy, readonly) NSString *statusDescription;
@property (nonatomic, copy, readonly) NSString *routeName;
@property (nonatomic, assign, readonly) NSUInteger waypointsCount;
@property (nonatomic, assign, readonly) BOOL hasValidRoute;

+ (instancetype)sharedSimulator;

// Nạp lộ trình từ file GPX (đường dẫn hoặc data/string)
- (BOOL)loadGPXFromURL:(NSURL *)fileURL error:(NSString **)errorOut;
- (BOOL)loadGPXFromString:(NSString *)gpxString routeName:(NSString *)name error:(NSString **)errorOut;

// Điều khiển mô phỏng
- (void)start;
- (void)pause;
- (void)resume;
- (void)stop;

@end
