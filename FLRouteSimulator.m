#import "FLRouteSimulator.h"
#import "FLGPXParser.h"
#import "FLLocationConfig.h"
#import "FLLocationEngine.h"
#import <math.h>

// Hàm broadcast toạ độ và heading được export từ FLLocationHook.x
extern void FLBroadcastLocationAndHeading(void);

@interface FLRouteSimulator ()

@property (nonatomic, assign, readwrite) FLRouteState state;
@property (nonatomic, assign, readwrite) double currentSpeedKmh;
@property (nonatomic, assign, readwrite) double currentCourse;
@property (nonatomic, assign, readwrite) double progress;
@property (nonatomic, copy, readwrite) NSString *statusDescription;
@property (nonatomic, copy, readwrite) NSString *routeName;
@property (nonatomic, assign, readwrite) NSUInteger waypointsCount;

@property (nonatomic, strong) FLRouteData *routeData;
@property (nonatomic, assign) double currentDistance;    // Cự ly xe đã đi (mét)
@property (nonatomic, assign) double currentSpeed_mps;   // Vận tốc xe (mét / giây)
@property (nonatomic, strong) NSTimer *simulationTimer;

@end

@implementation FLRouteSimulator

// MARK: - Singleton & Init

+ (instancetype)sharedSimulator {
    static FLRouteSimulator *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = FLRouteStateIdle;
        _maxSpeedKmh = 50.0;
        _currentSpeedKmh = 0.0;
        _currentCourse = 0.0;
        _progress = 0.0;
        _statusDescription = @"Chưa nạp lộ trình";
        _routeName = @"";
        _waypointsCount = 0;
        _currentDistance = 0.0;
        _currentSpeed_mps = 0.0;
        _routeData = nil;
    }
    return self;
}

- (BOOL)hasValidRoute {
    return self.routeData != nil && self.routeData.count >= 2 && self.routeData.totalDistance > 10.0;
}

// MARK: - Math & Bearing Helpers

static double FLBearingDegrees(CLLocationCoordinate2D from, CLLocationCoordinate2D to) {
    double lat1 = from.latitude * M_PI / 180.0;
    double lon1 = from.longitude * M_PI / 180.0;
    double lat2 = to.latitude * M_PI / 180.0;
    double lon2 = to.longitude * M_PI / 180.0;

    double dLon = lon2 - lon1;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double radians = atan2(y, x);
    double degrees = radians * 180.0 / M_PI;
    if (degrees < 0.0) {
        degrees += 360.0;
    }
    return degrees;
}

// MARK: - Arc-Length Interpolation

- (CLLocationCoordinate2D)coordinateAtDistance:(double)dist altitude:(double *)outAlt {
    if (!self.hasValidRoute) {
        if (outAlt) *outAlt = 0.0;
        return CLLocationCoordinate2DMake(0, 0);
    }
    NSUInteger count = self.routeData.count;
    CLLocationCoordinate2D *coords = self.routeData.coords;
    double *cum = self.routeData.cumDistances;
    double total = self.routeData.totalDistance;

    if (dist <= 0.0 || count == 1) {
        if (outAlt) *outAlt = (self.routeData.hasElevation && self.routeData.elevations) ? self.routeData.elevations[0] : [FLLocationConfig sharedConfig].altitude;
        return coords[0];
    }
    if (dist >= total) {
        if (outAlt) *outAlt = (self.routeData.hasElevation && self.routeData.elevations) ? self.routeData.elevations[count - 1] : [FLLocationConfig sharedConfig].altitude;
        return coords[count - 1];
    }

    // Binary search tìm phân đoạn [k, k+1]
    NSUInteger low = 0;
    NSUInteger high = count - 1;
    while (low < high) {
        NSUInteger mid = (low + high) / 2;
        if (cum[mid] <= dist) {
            if (mid + 1 == count || cum[mid + 1] > dist) {
                low = mid;
                break;
            }
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    NSUInteger k = low;
    if (k >= count - 1) {
        k = count - 2;
    }

    double d0 = cum[k];
    double d1 = cum[k + 1];
    double segLen = d1 - d0;
    double ratio = 0.0;
    if (segLen > 0.0001) {
        ratio = (dist - d0) / segLen;
    }
    ratio = fmax(0.0, fmin(1.0, ratio));

    CLLocationCoordinate2D p0 = coords[k];
    CLLocationCoordinate2D p1 = coords[k + 1];

    double lat = p0.latitude + ratio * (p1.latitude - p0.latitude);
    double lon = p0.longitude + ratio * (p1.longitude - p0.longitude);

    if (outAlt) {
        if (self.routeData.hasElevation && self.routeData.elevations) {
            double e0 = self.routeData.elevations[k];
            double e1 = self.routeData.elevations[k + 1];
            *outAlt = e0 + ratio * (e1 - e0);
        } else {
            *outAlt = [FLLocationConfig sharedConfig].altitude;
        }
    }

    return CLLocationCoordinate2DMake(lat, lon);
}

- (CLLocationCoordinate2D)coordinateAtDistance:(double)dist {
    return [self coordinateAtDistance:dist altitude:NULL];
}

// MARK: - Route Loading (Delegated to FLGPXParser)

- (BOOL)loadGPXFromURL:(NSURL *)fileURL error:(NSString **)errorOut {
    FLRouteData *data = [FLGPXParser parseGPXFromURL:fileURL error:errorOut];
    if (!data) return NO;
    return [self applyRouteData:data];
}

- (BOOL)loadGPXFromString:(NSString *)gpxString routeName:(NSString *)name error:(NSString **)errorOut {
    FLRouteData *data = [FLGPXParser parseGPXFromString:gpxString routeName:name error:errorOut];
    if (!data) return NO;
    return [self applyRouteData:data];
}

- (BOOL)applyRouteData:(FLRouteData *)data {
    [self stop];
    self.routeData = data;
    self.waypointsCount = data.count;
    self.routeName = data.name;
    self.currentDistance = 0.0;
    self.currentSpeed_mps = 0.0;
    self.currentSpeedKmh = 0.0;
    self.progress = 0.0;
    self.state = FLRouteStateIdle;

    // Khởi tạo hướng đầu tiên
    self.currentCourse = FLBearingDegrees(data.coords[0], data.coords[1]);
    self.statusDescription = [NSString stringWithFormat:@"Đã nạp %lu điểm (%.2f km)", (unsigned long)data.count, data.totalDistance / 1000.0];

    // Cập nhật vị trí xuất phát vào config
    FLLocationConfig *config = [FLLocationConfig sharedConfig];
    config.latitude = data.coords[0].latitude;
    config.longitude = data.coords[0].longitude;
    config.speed = 0.0;
    config.course = self.currentCourse;
    if (data.hasElevation && data.elevations) {
        config.altitude = data.elevations[0];
    }
    config.enabled = YES;
    [config saveConfig];

    return YES;
}

// MARK: - Simulation Controls

- (void)start {
    if (!self.hasValidRoute) return;
    self.currentDistance = 0.0;
    self.currentSpeed_mps = 0.0;
    self.currentSpeedKmh = 0.0;
    self.state = FLRouteStateRunning;
    self.statusDescription = @"Đang xuất phát...";
    [self startTimer];
}

- (void)pause {
    if (self.state == FLRouteStateRunning) {
        self.state = FLRouteStatePaused;
        self.statusDescription = @"Tạm dừng";
        [self stopTimer];
    }
}

- (void)resume {
    if (self.state == FLRouteStatePaused) {
        self.state = FLRouteStateRunning;
        self.statusDescription = @"Đang di chuyển";
        [self startTimer];
    }
}

- (void)stop {
    self.state = FLRouteStateIdle;
    self.currentSpeed_mps = 0.0;
    self.currentSpeedKmh = 0.0;
    self.statusDescription = self.hasValidRoute ? @"Đã dừng mô phỏng" : @"Chưa nạp lộ trình";
    [self stopTimer];
}

- (void)startTimer {
    [self stopTimer];
    self.simulationTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                            target:self
                                                          selector:@selector(simulationStep)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)stopTimer {
    if (self.simulationTimer) {
        [self.simulationTimer invalidate];
        self.simulationTimer = nil;
    }
}

// MARK: - Step Animation

- (void)simulationStep {
    if (self.state != FLRouteStateRunning || !self.hasValidRoute) {
        return;
    }

    double totalDist = self.routeData.totalDistance;

    if (self.currentDistance >= totalDist) {
        // Đã về đến đích
        self.state = FLRouteStateCompleted;
        self.statusDescription = @"Đã về đích!";
        self.currentSpeed_mps = 0.0;
        self.currentSpeedKmh = 0.0;
        self.progress = 1.0;
        [self stopTimer];

        CLLocationCoordinate2D dest = self.routeData.coords[self.routeData.count - 1];
        FLLocationConfig *config = [FLLocationConfig sharedConfig];
        config.latitude = dest.latitude;
        config.longitude = dest.longitude;
        config.speed = 0.0;
        [config saveConfig];

        FLBroadcastLocationAndHeading();
        return;
    }

    // 1. Tính toán hệ số góc cua (Lookahead Curvature Factor)
    CLLocationCoordinate2D curCoord = [self coordinateAtDistance:self.currentDistance];
    CLLocationCoordinate2D lookAhead1 = [self coordinateAtDistance:fmin(totalDist, self.currentDistance + 10.0)];
    CLLocationCoordinate2D lookAhead2 = [self coordinateAtDistance:fmin(totalDist, self.currentDistance + 22.0)];

    double b1 = FLBearingDegrees(curCoord, lookAhead1);
    double b2 = FLBearingDegrees(lookAhead1, lookAhead2);
    double turnAngle = fabs(b2 - b1);
    if (turnAngle > 180.0) turnAngle = 360.0 - turnAngle;

    double curveFactor = fmax(0.35, 1.0 - (turnAngle / 75.0));

    // 2. Tốc độ mục tiêu & Hard Clamp
    double maxSpeed_mps = (self.maxSpeedKmh > 0 ? self.maxSpeedKmh : 50.0) / 3.6;
    double targetSpeed_mps = maxSpeed_mps * curveFactor;

    double remainDist = totalDist - self.currentDistance;
    if (remainDist < 35.0) {
        targetSpeed_mps *= fmax(0.15, remainDist / 35.0);
    }

    // 3. Quán tính xe (Inertia)
    self.currentSpeed_mps += (targetSpeed_mps - self.currentSpeed_mps) * 0.15;

    // Hard clamp
    if (self.currentSpeed_mps > maxSpeed_mps) self.currentSpeed_mps = maxSpeed_mps;
    if (self.currentSpeed_mps < 1.0) self.currentSpeed_mps = 1.0;

    self.currentSpeedKmh = self.currentSpeed_mps * 3.6;
    if (self.currentSpeedKmh > self.maxSpeedKmh) self.currentSpeedKmh = self.maxSpeedKmh;

    // 4. Cập nhật cự ly
    double dt = 0.2;
    self.currentDistance += (self.currentSpeed_mps * dt);
    if (self.currentDistance >= totalDist) {
        self.currentDistance = totalDist;
    }

    double currentAlt = 0.0;
    CLLocationCoordinate2D newCoord = [self coordinateAtDistance:self.currentDistance altitude:&currentAlt];

    // 6. Hướng tầm nhìn
    CLLocationCoordinate2D forwardCoord = [self coordinateAtDistance:fmin(totalDist, self.currentDistance + 4.0)];
    double targetBearing = FLBearingDegrees(newCoord, forwardCoord);

    double diff = targetBearing - self.currentCourse;
    while (diff > 180.0) diff -= 360.0;
    while (diff < -180.0) diff += 360.0;
    self.currentCourse += diff * 0.35;
    while (self.currentCourse < 0.0) self.currentCourse += 360.0;
    while (self.currentCourse >= 360.0) self.currentCourse -= 360.0;

    self.progress = totalDist > 0 ? (self.currentDistance / totalDist) : 0.0;

    if (curveFactor < 0.7) {
        self.statusDescription = [NSString stringWithFormat:@"Đang vào cua (%.0f km/h)", self.currentSpeedKmh];
    } else {
        self.statusDescription = [NSString stringWithFormat:@"Đang chạy (%.0f km/h)", self.currentSpeedKmh];
    }

    // 7. Đồng bộ config
    FLLocationConfig *config = [FLLocationConfig sharedConfig];
    config.latitude = newCoord.latitude;
    config.longitude = newCoord.longitude;
    config.speed = self.currentSpeed_mps;
    config.course = self.currentCourse;
    config.horizontalAccuracy = 3.0;
    if (self.routeData.hasElevation) {
        config.altitude = currentAlt;
    }
    config.enabled = YES;

    // 8. Bắn trực tiếp toạ độ và la bàn tầm nhìn 5Hz
    FLBroadcastLocationAndHeading();
}

@end
