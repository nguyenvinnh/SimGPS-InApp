#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface FLRouteData : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) CLLocationCoordinate2D *coords;
@property (nonatomic, assign) double *cumDistances;
@property (nonatomic, assign) double *elevations;
@property (nonatomic, assign) BOOL hasElevation;
@property (nonatomic, assign) NSUInteger count;
@property (nonatomic, assign) double totalDistance;

- (instancetype)initWithCoords:(CLLocationCoordinate2D *)coords
                  cumDistances:(double *)cumDistances
                    elevations:(double *)elevations
                  hasElevation:(BOOL)hasElevation
                         count:(NSUInteger)count
                 totalDistance:(double)totalDistance
                          name:(NSString *)name;

@end

@interface FLGPXParser : NSObject

// Nạp và phân tích GPX từ URL, Data hoặc String
// Ưu tiên chuẩn: <trkpt> (Track) -> <rtept> (Route) -> <wpt> (Waypoint)
+ (FLRouteData *)parseGPXFromURL:(NSURL *)fileURL error:(NSString **)errorOut;
+ (FLRouteData *)parseGPXFromData:(NSData *)data routeName:(NSString *)name error:(NSString **)errorOut;
+ (FLRouteData *)parseGPXFromString:(NSString *)gpxString routeName:(NSString *)name error:(NSString **)errorOut;

// Quét các file GPX có sẵn trong sandbox / Documents / App bundle
+ (NSArray<NSString *> *)findLocalGPXFiles;

@end
