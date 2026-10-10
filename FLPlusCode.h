#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface FLPlusCode : NSObject

// Trích xuất mã Plus Code và tên địa danh nếu có
+ (NSDictionary *)extractPlusCodeInfoFromString:(NSString *)input;

// Giải mã full code
+ (BOOL)decodeFullCode:(NSString *)code latitude:(double *)outLat longitude:(double *)outLon;

// Khôi phục short code từ toạ độ tham chiếu
+ (BOOL)recoverAndDecodeShortCode:(NSString *)shortCode
                     referenceLat:(double)refLat
                     referenceLon:(double)refLon
                      outLatitude:(double *)outLat
                     outLongitude:(double *)outLon;

// Phân tích chuỗi đầu vào (hỗ trợ toạ độ số, Plus Code đầy đủ và Short Code kèm Geocoding)
+ (void)parseCoordinateString:(NSString *)input
                   completion:(void (^)(BOOL success, double lat, double lon, NSString *error))completion;

@end
