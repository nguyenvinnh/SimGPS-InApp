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

    // Phát ngay toạ độ xuất phát cho ứng dụng mục tiêu nhận diện
    FLBroadcastLocationAndHeading();

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

- (void)endSimulation {
    [self stopTimer];
    self.state = FLRouteStateIdle;
    self.currentSpeed_mps = 0.0;
    self.currentSpeedKmh = 0.0;
    self.progress = 0.0;
    self.routeData = nil;
    self.waypointsCount = 0;
    self.routeName = @"";
    self.statusDescription = @"Đã về vị trí tĩnh";

    // Khôi phục toạ độ giả lập tĩnh thông thường
    FLLocationConfig *config = [FLLocationConfig sharedConfig];
    [config restoreStaticCoordinate];

    // Phát broadcast vị trí tĩnh ngay lập tức
    FLBroadcastLocationAndHeading();
}

- (void)startTimer {
    [self stopTimer];
    // Tần số cập nhật 10Hz (0.1 giây) giúp Google Maps và Apple Maps nội suy chuyển động siêu mượt
    self.simulationTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
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

// MARK: - Step Animation & Kinematic Speed Controller

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

    // 1. Giới hạn tốc độ cấu hình tối đa (m/s)
    double userMaxKmh = (self.maxSpeedKmh > 5.0) ? self.maxSpeedKmh : 50.0;
    double maxSpeed_mps = userMaxKmh / 3.6;

    // Gia tốc giảm tốc (m/s^2) và gia tốc tăng tốc (m/s^2)
    const double a_brake = 2.8;
    const double a_accel = 1.6;
    const double dt = 0.1; // Chu kỳ timer 100ms (10Hz)

    // 2. Thuật toán Lookahead Corner Braking Point:
    double targetSpeed_mps = maxSpeed_mps;
    BOOL isApproachingTurn = NO;

    double lookaheadDistances[] = { 10.0, 20.0, 35.0, 55.0, 80.0, 110.0 };
    int numChecks = sizeof(lookaheadDistances) / sizeof(lookaheadDistances[0]);

    for (int i = 0; i < numChecks; i++) {
        double d_forward = lookaheadDistances[i];
        double d_corner = self.currentDistance + d_forward;
        if (d_corner >= totalDist) break;

        CLLocationCoordinate2D pCorner = [self coordinateAtDistance:d_corner];
        CLLocationCoordinate2D pBefore = [self coordinateAtDistance:fmax(0.0, d_corner - 6.0)];
        CLLocationCoordinate2D pAfter  = [self coordinateAtDistance:fmin(totalDist, d_corner + 6.0)];

        double bearingIn = FLBearingDegrees(pBefore, pCorner);
        double bearingOut = FLBearingDegrees(pCorner, pAfter);
        double turnAngle = fabs(bearingOut - bearingIn);
        if (turnAngle > 180.0) turnAngle = 360.0 - turnAngle;

        double cornerLimitKmh = userMaxKmh;
        if (turnAngle >= 75.0) {
            cornerLimitKmh = fmin(userMaxKmh, 32.0);
        } else if (turnAngle >= 55.0) {
            cornerLimitKmh = fmin(userMaxKmh, 45.0);
        } else if (turnAngle >= 35.0) {
            cornerLimitKmh = fmin(userMaxKmh, 60.0);
        } else if (turnAngle >= 20.0) {
            cornerLimitKmh = fmin(userMaxKmh, 75.0);
        }

        double cornerLimit_mps = cornerLimitKmh / 3.6;
        double safeSpeed_mps = sqrt((cornerLimit_mps * cornerLimit_mps) + (2.0 * a_brake * d_forward));

        if (safeSpeed_mps < targetSpeed_mps) {
            targetSpeed_mps = safeSpeed_mps;
            if (turnAngle >= 35.0) {
                isApproachingTurn = YES;
            }
        }
    }

    // Giảm tốc độ an toàn khi gần về đích
    double remainDist = totalDist - self.currentDistance;
    double stopSafeSpeed_mps = sqrt(2.0 * a_brake * fmax(1.0, remainDist));
    if (stopSafeSpeed_mps < targetSpeed_mps) {
        targetSpeed_mps = stopSafeSpeed_mps;
    }

    if (targetSpeed_mps > maxSpeed_mps) targetSpeed_mps = maxSpeed_mps;
    if (targetSpeed_mps < 2.5) targetSpeed_mps = 2.5;

    // 4. Cập nhật tốc độ xe theo động lực học
    if (self.currentSpeed_mps < targetSpeed_mps) {
        self.currentSpeed_mps += a_accel * dt;
        if (self.currentSpeed_mps > targetSpeed_mps) {
            self.currentSpeed_mps = targetSpeed_mps;
        }
    } else if (self.currentSpeed_mps > targetSpeed_mps) {
        self.currentSpeed_mps -= a_brake * dt;
        if (self.currentSpeed_mps < targetSpeed_mps) {
            self.currentSpeed_mps = targetSpeed_mps;
        }
    }

    if (self.currentSpeed_mps > maxSpeed_mps) {
        self.currentSpeed_mps = maxSpeed_mps;
    }
    if (self.currentSpeed_mps < 1.0) {
        self.currentSpeed_mps = 1.0;
    }

    self.currentSpeedKmh = self.currentSpeed_mps * 3.6;
    if (self.currentSpeedKmh > userMaxKmh) {
        self.currentSpeedKmh = userMaxKmh;
    }

    // 5. Cập nhật cự ly di chuyển
    self.currentDistance += (self.currentSpeed_mps * dt);
    if (self.currentDistance >= totalDist) {
        self.currentDistance = totalDist;
    }

    double currentAlt = 0.0;
    CLLocationCoordinate2D newCoord = [self coordinateAtDistance:self.currentDistance altitude:&currentAlt];

    // 6. Xoay góc la bàn / hướng nhìn tầm nhìn:
    // Tự động điều chỉnh khoảng cách ngắm hướng phía trước tỷ lệ theo tốc độ (3.0m - 12.0m)
    // để tránh bị giật góc hay bị dại khi đi qua các đoạn cua gấp trong Google Maps
    double lookAheadHeadingDist = fmax(3.5, fmin(12.0, self.currentSpeed_mps * 0.8));
    CLLocationCoordinate2D forwardCoord = [self coordinateAtDistance:fmin(totalDist, self.currentDistance + lookAheadHeadingDist)];
    double targetBearing = FLBearingDegrees(newCoord, forwardCoord);

    double diff = targetBearing - self.currentCourse;
    while (diff > 180.0) diff -= 360.0;
    while (diff < -180.0) diff += 360.0;
    
    // Hệ số nội suy 0.20 ở chu kỳ 10Hz tạo cảm giác xoay la bàn rất đầm và êm ái
    self.currentCourse += diff * 0.20;
    while (self.currentCourse < 0.0) self.currentCourse += 360.0;
    while (self.currentCourse >= 360.0) self.currentCourse -= 360.0;

    self.progress = totalDist > 0 ? (self.currentDistance / totalDist) : 0.0;

    if (isApproachingTurn) {
        self.statusDescription = [NSString stringWithFormat:@"Hãm phanh vào cua (%.0f km/h)", self.currentSpeedKmh];
    } else {
        self.statusDescription = [NSString stringWithFormat:@"Đang chạy đều (%.0f km/h)", self.currentSpeedKmh];
    }

    // 7. Đồng bộ sang Location Engine & Config
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
