#import "FLGPXParser.h"
#import <math.h>

@implementation FLRouteData

- (instancetype)initWithCoords:(CLLocationCoordinate2D *)coords
                  cumDistances:(double *)cumDistances
                    elevations:(double *)elevations
                  hasElevation:(BOOL)hasElevation
                         count:(NSUInteger)count
                 totalDistance:(double)totalDistance
                          name:(NSString *)name {
    self = [super init];
    if (self) {
        _coords = coords;
        _cumDistances = cumDistances;
        _elevations = elevations;
        _hasElevation = hasElevation;
        _count = count;
        _totalDistance = totalDistance;
        _name = [name copy];
    }
    return self;
}

- (void)dealloc {
    if (_coords) {
        free(_coords);
        _coords = NULL;
    }
    if (_cumDistances) {
        free(_cumDistances);
        _cumDistances = NULL;
    }
    if (_elevations) {
        free(_elevations);
        _elevations = NULL;
    }
}

@end

// MARK: - SAX XML Parser Handler

@interface FLGPXSAXHandler : NSObject <NSXMLParserDelegate>

@property (nonatomic, strong) NSMutableArray<NSValue *> *trkPoints;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *trkElevations;

@property (nonatomic, strong) NSMutableArray<NSValue *> *rtePoints;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *rteElevations;

@property (nonatomic, strong) NSMutableArray<NSValue *> *wptPoints;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *wptElevations;

@property (nonatomic, copy) NSString *parsedRouteName;

@property (nonatomic, copy) NSString *currentElement;
@property (nonatomic, assign) CLLocationCoordinate2D currentCoord;
@property (nonatomic, assign) double currentElevation;
@property (nonatomic, assign) BOOL hasCurrentCoord;
@property (nonatomic, assign) BOOL hasCurrentElevation;
@property (nonatomic, strong) NSMutableString *currentText;

@end

@implementation FLGPXSAXHandler

- (instancetype)init {
    self = [super init];
    if (self) {
        _trkPoints = [NSMutableArray array];
        _trkElevations = [NSMutableArray array];
        _rtePoints = [NSMutableArray array];
        _rteElevations = [NSMutableArray array];
        _wptPoints = [NSMutableArray array];
        _wptElevations = [NSMutableArray array];
        _currentText = [NSMutableString string];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName
    attributes:(NSDictionary<NSString *, NSString *> *)attributeDict {
    self.currentElement = [elementName lowercaseString];
    [self.currentText setString:@""];

    if ([self.currentElement isEqualToString:@"trkpt"] ||
        [self.currentElement isEqualToString:@"rtept"] ||
        [self.currentElement isEqualToString:@"wpt"]) {
        NSString *latStr = attributeDict[@"lat"] ?: attributeDict[@"LAT"];
        NSString *lonStr = attributeDict[@"lon"] ?: attributeDict[@"LON"];
        if (latStr && lonStr) {
            double lat = [latStr doubleValue];
            double lon = [lonStr doubleValue];
            if (CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon))) {
                self.currentCoord = CLLocationCoordinate2DMake(lat, lon);
                self.hasCurrentCoord = YES;
                self.currentElevation = 0.0;
                self.hasCurrentElevation = NO;
            }
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.currentText appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName {
    NSString *elem = [elementName lowercaseString];

    if ([elem isEqualToString:@"ele"] && self.hasCurrentCoord) {
        NSString *clean = [self.currentText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (clean.length > 0) {
            self.currentElevation = [clean doubleValue];
            self.hasCurrentElevation = YES;
        }
    } else if ([elem isEqualToString:@"name"] && self.parsedRouteName == nil) {
        NSString *clean = [self.currentText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (clean.length > 0) {
            self.parsedRouteName = clean;
        }
    } else if ([elem isEqualToString:@"trkpt"]) {
        if (self.hasCurrentCoord) {
            [self.trkPoints addObject:[NSValue valueWithBytes:&_currentCoord objCType:@encode(CLLocationCoordinate2D)]];
            [self.trkElevations addObject:@(self.currentElevation)];
        }
        self.hasCurrentCoord = NO;
    } else if ([elem isEqualToString:@"rtept"]) {
        if (self.hasCurrentCoord) {
            [self.rtePoints addObject:[NSValue valueWithBytes:&_currentCoord objCType:@encode(CLLocationCoordinate2D)]];
            [self.rteElevations addObject:@(self.currentElevation)];
        }
        self.hasCurrentCoord = NO;
    } else if ([elem isEqualToString:@"wpt"]) {
        if (self.hasCurrentCoord) {
            [self.wptPoints addObject:[NSValue valueWithBytes:&_currentCoord objCType:@encode(CLLocationCoordinate2D)]];
            [self.wptElevations addObject:@(self.currentElevation)];
        }
        self.hasCurrentCoord = NO;
    }
}

@end

// MARK: - Main FLGPXParser Implementation

@implementation FLGPXParser

static double FLCalcDistance(CLLocationCoordinate2D c1, CLLocationCoordinate2D c2) {
    double lat1 = c1.latitude * M_PI / 180.0;
    double lon1 = c1.longitude * M_PI / 180.0;
    double lat2 = c2.latitude * M_PI / 180.0;
    double lon2 = c2.longitude * M_PI / 180.0;

    double dLat = lat2 - lat1;
    double dLon = lon2 - lon1;

    double a = sin(dLat / 2.0) * sin(dLat / 2.0) +
               cos(lat1) * cos(lat2) * sin(dLon / 2.0) * sin(dLon / 2.0);
    double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
    return 6371000.0 * c;
}

+ (FLRouteData *)parseGPXFromURL:(NSURL *)fileURL error:(NSString **)errorOut {
    if (!fileURL) {
        if (errorOut) *errorOut = @"Đường dẫn file không hợp lệ";
        return nil;
    }

    NSError *readErr = nil;
    NSData *data = [NSData dataWithContentsOfURL:fileURL options:0 error:&readErr];
    if (!data || readErr) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Không thể đọc file: %@", readErr.localizedDescription];
        return nil;
    }

    NSString *name = fileURL.lastPathComponent ?: @"Lộ trình GPX";
    return [self parseGPXFromData:data routeName:name error:errorOut];
}

+ (FLRouteData *)parseGPXFromString:(NSString *)gpxString routeName:(NSString *)name error:(NSString **)errorOut {
    if (!gpxString || gpxString.length == 0) {
        if (errorOut) *errorOut = @"Nội dung GPX trống";
        return nil;
    }
    NSData *data = [gpxString dataUsingEncoding:NSUTF8StringEncoding];
    return [self parseGPXFromData:data routeName:name error:errorOut];
}

+ (FLRouteData *)parseGPXFromData:(NSData *)data routeName:(NSString *)name error:(NSString **)errorOut {
    if (!data || data.length == 0) {
        if (errorOut) *errorOut = @"Dữ liệu GPX rỗng";
        return nil;
    }

    NSXMLParser *xmlParser = [[NSXMLParser alloc] initWithData:data];
    FLGPXSAXHandler *handler = [[FLGPXSAXHandler alloc] init];
    xmlParser.delegate = handler;

    BOOL ok = [xmlParser parse];
    if (!ok && xmlParser.parserError && handler.trkPoints.count == 0 && handler.rtePoints.count == 0 && handler.wptPoints.count == 0) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Lỗi phân tích cú pháp XML: %@", xmlParser.parserError.localizedDescription];
        return nil;
    }

    // 1. CHỌN NGUỒN TOẠ ĐỘ THEO THỨ BẬC CHUẨN GPX (Không bao giờ trộn lẫn trkpt và wpt!)
    NSArray<NSValue *> *selectedPoints = nil;
    NSArray<NSNumber *> *selectedElevations = nil;

    if (handler.trkPoints.count >= 2) {
        // Ưu tiên cao nhất: Track points (Đường đi thực tế chi tiết của tuyến đường)
        selectedPoints = handler.trkPoints;
        selectedElevations = handler.trkElevations;
    } else if (handler.rtePoints.count >= 2) {
        // Ưu tiên thứ hai: Route points (Các điểm dẫn đường tuần tự)
        selectedPoints = handler.rtePoints;
        selectedElevations = handler.rteElevations;
    } else if (handler.wptPoints.count >= 2) {
        // Ưu tiên cuối: Waypoints (Chỉ dùng khi file không có trkpt/rtept)
        selectedPoints = handler.wptPoints;
        selectedElevations = handler.wptElevations;
    }

    if (!selectedPoints || selectedPoints.count < 2) {
        if (errorOut) *errorOut = @"Không tìm thấy chuỗi tọa độ lộ trình hợp lệ trong file GPX (cần tối thiểu 2 điểm)";
        return nil;
    }

    // 2. LỌC BỎ CÁC ĐIỂM TRÙNG LẶP HOÀN TOÀN (chống nhảy cóc và chia cho 0)
    // Ngưỡng lọc 0.3m chỉ loại bỏ các điểm trùng toạ độ (0.0m) do ghi đè, giữ nguyên 100% các khúc cua
    NSMutableArray<NSValue *> *cleanCoords = [NSMutableArray arrayWithCapacity:selectedPoints.count];
    NSMutableArray<NSNumber *> *cleanElevations = [NSMutableArray arrayWithCapacity:selectedPoints.count];

    CLLocationCoordinate2D lastC;
    [selectedPoints[0] getValue:&lastC];
    [cleanCoords addObject:selectedPoints[0]];
    [cleanElevations addObject:selectedElevations.count > 0 ? selectedElevations[0] : @(0.0)];

    BOOL hasRealElevation = NO;

    for (NSUInteger i = 1; i < selectedPoints.count; i++) {
        CLLocationCoordinate2D curC;
        [selectedPoints[i] getValue:&curC];
        double d = FLCalcDistance(lastC, curC);

        // Bỏ qua nếu khoảng cách < 0.3m (trùng điểm), trừ khi là điểm cuối cùng
        if (d >= 0.3 || i == selectedPoints.count - 1) {
            [cleanCoords addObject:selectedPoints[i]];
            double ele = i < selectedElevations.count ? [selectedElevations[i] doubleValue] : 0.0;
            [cleanElevations addObject:@(ele)];
            if (fabs(ele) > 0.001) {
                hasRealElevation = YES;
            }
            lastC = curC;
        }
    }

    if (cleanCoords.count < 2) {
        if (errorOut) *errorOut = @"Lộ trình quá ngắn (dưới 2 điểm) sau khi lọc trùng lặp";
        return nil;
    }

    // 3. TÍNH TOÁN MẢNG KHOẢNG CÁCH TÍCH LUỸ (CUMULATIVE DISTANCES)
    NSUInteger count = cleanCoords.count;
    CLLocationCoordinate2D *coords = (CLLocationCoordinate2D *)malloc(sizeof(CLLocationCoordinate2D) * count);
    double *cumDistances = (double *)malloc(sizeof(double) * count);
    double *elevations = (double *)malloc(sizeof(double) * count);

    cumDistances[0] = 0.0;
    [cleanCoords[0] getValue:&coords[0]];
    elevations[0] = [cleanElevations[0] doubleValue];

    for (NSUInteger i = 1; i < count; i++) {
        [cleanCoords[i] getValue:&coords[i]];
        elevations[i] = [cleanElevations[i] doubleValue];
        double seg = FLCalcDistance(coords[i - 1], coords[i]);
        cumDistances[i] = cumDistances[i - 1] + seg;
    }

    double totalDist = cumDistances[count - 1];
    NSString *finalName = handler.parsedRouteName ?: name ?: @"Lộ trình GPX";

    return [[FLRouteData alloc] initWithCoords:coords
                                  cumDistances:cumDistances
                                    elevations:elevations
                                  hasElevation:hasRealElevation
                                         count:count
                                 totalDistance:totalDist
                                          name:finalName];
}

+ (NSArray<NSString *> *)findLocalGPXFiles {
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1. Documents thư mục app
    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (docDir) {
        NSArray *files = [fm contentsOfDirectoryAtPath:docDir error:nil];
        for (NSString *f in files) {
            if ([f.pathExtension.lowercaseString isEqualToString:@"gpx"]) {
                [results addObject:[docDir stringByAppendingPathComponent:f]];
            }
        }
    }

    // 2. App bundle
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    if (bundlePath) {
        NSArray *files = [fm contentsOfDirectoryAtPath:bundlePath error:nil];
        for (NSString *f in files) {
            if ([f.pathExtension.lowercaseString isEqualToString:@"gpx"]) {
                [results addObject:[bundlePath stringByAppendingPathComponent:f]];
            }
        }
    }

    // 3. Library / Caches
    NSString *cachesDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    if (cachesDir) {
        NSArray *files = [fm contentsOfDirectoryAtPath:cachesDir error:nil];
        for (NSString *f in files) {
            if ([f.pathExtension.lowercaseString isEqualToString:@"gpx"]) {
                [results addObject:[cachesDir stringByAppendingPathComponent:f]];
            }
        }
    }

    return results;
}

@end
