#import "FLPlusCode.h"
#import "FLLocationConfig.h"
#import <math.h>

static NSString *const kOLCAlphabet = @"23456789CFGHJMPQRVWX";

static int FLAlphabetIndex(unichar c) {
    if (c >= 'a' && c <= 'z') {
        c = c - 'a' + 'A';
    }
    NSString *s = [NSString stringWithCharacters:&c length:1];
    NSRange r = [kOLCAlphabet rangeOfString:s];
    if (r.location == NSNotFound) return -1;
    return (int)r.location;
}

@implementation FLPlusCode

+ (BOOL)decodeFullCode:(NSString *)code latitude:(double *)outLat longitude:(double *)outLon {
    if (!code) return NO;
    NSString *clean = [[code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    NSRange plusRange = [clean rangeOfString:@"+"];
    if (plusRange.location == NSNotFound || plusRange.location != 8) {
        return NO;
    }

    NSString *noPlus = [clean stringByReplacingOccurrencesOfString:@"+" withString:@""];
    if (noPlus.length < 2) return NO;

    double lat = -90.0;
    double lon = -180.0;
    double latRes = 20.0;
    double lonRes = 20.0;
    NSUInteger pairCount = 0;
    NSUInteger maxPair = MIN(noPlus.length, (NSUInteger)10);

    for (NSUInteger i = 0; i + 1 < maxPair; i += 2) {
        unichar c1 = [noPlus characterAtIndex:i];
        unichar c2 = [noPlus characterAtIndex:i + 1];
        if (c1 == '0' || c2 == '0') break;
        int latIdx = FLAlphabetIndex(c1);
        int lonIdx = FLAlphabetIndex(c2);
        if (latIdx < 0 || lonIdx < 0) return NO;
        if (pairCount == 0 && latIdx > 8) return NO;
        lat += latIdx * latRes;
        lon += lonIdx * lonRes;
        latRes /= 20.0;
        lonRes /= 20.0;
        pairCount++;
    }
    if (pairCount == 0) return NO;

    double latArea = latRes * 20.0;
    double lonArea = lonRes * 20.0;

    // Grid refinement (11-15 ký tự)
    if (noPlus.length > 10) {
        for (NSUInteger i = 10; i < noPlus.length && i < 15; i++) {
            unichar c = [noPlus characterAtIndex:i];
            if (c == '0') break;
            int idx = FLAlphabetIndex(c);
            if (idx < 0) return NO;
            int row = idx / 4;
            int col = idx % 4;
            double latStep = latArea / 5.0;
            double lonStep = lonArea / 4.0;
            lat += row * latStep;
            lon += col * lonStep;
            latArea = latStep;
            lonArea = lonStep;
        }
    }

    double centerLat = lat + latArea / 2.0;
    double centerLon = lon + lonArea / 2.0;

    if (centerLat < -90) centerLat = -90;
    if (centerLat > 90) centerLat = 90;
    while (centerLon < -180) centerLon += 360;
    while (centerLon >= 180) centerLon -= 360;

    if (outLat) *outLat = centerLat;
    if (outLon) *outLon = centerLon;
    return YES;
}

+ (BOOL)recoverAndDecodeShortCode:(NSString *)shortCode
                     referenceLat:(double)refLat
                     referenceLon:(double)refLon
                      outLatitude:(double *)outLat
                     outLongitude:(double *)outLon {
    if (!shortCode) return NO;
    NSString *clean = [[shortCode stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    NSRange plusRange = [clean rangeOfString:@"+"];
    if (plusRange.location == NSNotFound) return NO;
    NSInteger plusPos = (NSInteger)plusRange.location;
    if (plusPos == 8) {
        return [self decodeFullCode:clean latitude:outLat longitude:outLon];
    }
    if (plusPos < 2 || plusPos > 6) return NO;

    NSInteger missing = 8 - plusPos;
    NSInteger prefixLen = 8 - missing;
    double resolution = pow(20.0, 2.0 - (double)prefixLen / 2.0);

    double refLatClipped = fmax(-90.0, fmin(90.0, refLat));
    double refLonNorm = refLon;
    while (refLonNorm < -180) refLonNorm += 360;
    while (refLonNorm >= 180) refLonNorm -= 360;

    double refLatN = refLatClipped + 90.0;
    double refLonN = refLonNorm + 180.0;
    refLonN = fmod(refLonN, 360.0);
    if (refLonN < 0) refLonN += 360.0;

    double prefixLatN = floor(refLatN / resolution) * resolution;
    double prefixLonN = floor(refLonN / resolution) * resolution;

    NSString *digits = [clean stringByReplacingOccurrencesOfString:@"+" withString:@""];
    NSUInteger totalPairExpected = 10 - prefixLen;
    if (digits.length < totalPairExpected && digits.length < 2) return NO;

    NSUInteger pairCountInShort = MIN(digits.length, totalPairExpected);
    if (pairCountInShort % 2 == 1 && pairCountInShort < totalPairExpected) {
        pairCountInShort = pairCountInShort - 1;
    }
    NSUInteger gridCount = (digits.length > totalPairExpected) ? (digits.length - totalPairExpected) : 0;

    double latOffset = 0;
    double lonOffset = 0;
    double res = resolution / 20.0;

    for (NSUInteger p = 0; p < pairCountInShort / 2; p++) {
        unichar cLat = [digits characterAtIndex:p * 2];
        unichar cLon = [digits characterAtIndex:p * 2 + 1];
        int latIdx = FLAlphabetIndex(cLat);
        int lonIdx = FLAlphabetIndex(cLon);
        if (latIdx < 0 || lonIdx < 0) return NO;
        latOffset += latIdx * res;
        lonOffset += lonIdx * res;
        res /= 20.0;
    }

    double latArea = res * 20.0;
    double lonArea = res * 20.0;

    for (NSUInteger g = 0; g < gridCount; g++) {
        unichar c = [digits characterAtIndex:pairCountInShort + g];
        if (c == '0') break;
        int idx = FLAlphabetIndex(c);
        if (idx < 0) return NO;
        int row = idx / 4;
        int col = idx % 4;
        double latStep = latArea / 5.0;
        double lonStep = lonArea / 4.0;
        latOffset += row * latStep;
        lonOffset += col * lonStep;
        latArea = latStep;
        lonArea = lonStep;
    }

    double candLatN = prefixLatN + latOffset + latArea / 2.0;
    double candLonN = prefixLonN + lonOffset + lonArea / 2.0;

    double candLat = candLatN - 90.0;
    double candLon = candLonN - 180.0;
    while (candLon < -180) candLon += 360;
    while (candLon >= 180) candLon -= 360;

    double latDiff = refLatClipped - candLat;
    while (latDiff > resolution / 2.0) {
        candLat += resolution;
        latDiff -= resolution;
    }
    while (latDiff < -resolution / 2.0) {
        candLat -= resolution;
        latDiff += resolution;
    }

    double lonDiff = refLonNorm - candLon;
    while (lonDiff > 180) lonDiff -= 360;
    while (lonDiff < -180) lonDiff += 360;
    while (lonDiff > resolution / 2.0) {
        candLon += resolution;
        lonDiff -= resolution;
    }
    while (lonDiff < -resolution / 2.0) {
        candLon -= resolution;
        lonDiff += resolution;
    }

    while (candLon < -180) candLon += 360;
    while (candLon >= 180) candLon -= 360;
    if (candLat < -90) candLat = -90;
    if (candLat > 90) candLat = 90;

    if (outLat) *outLat = candLat;
    if (outLon) *outLon = candLon;
    return YES;
}

+ (NSDictionary *)extractPlusCodeInfoFromString:(NSString *)input {
    if (!input) return nil;
    NSString *pattern = @"[23456789CFGHJMPQRVWX]{2,8}\\+[23456789CFGHJMPQRVWX]{2,7}";
    NSError *err = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&err];
    if (err) return nil;
    NSTextCheckingResult *match = [regex firstMatchInString:input options:0 range:NSMakeRange(0, input.length)];
    if (!match) return nil;

    NSString *plusCode = [input substringWithRange:match.range];
    NSString *place = @"";
    NSUInteger end = NSMaxRange(match.range);
    if (end < input.length) {
        place = [[input substringFromIndex:end] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([place hasPrefix:@","]) {
            place = [[place substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    return @{@"code" : plusCode, @"place" : place};
}

+ (void)parseCoordinateString:(NSString *)input
                   completion:(void (^)(BOOL success, double lat, double lon, NSString *error))completion {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (completion) completion(NO, 0, 0, @"Chuỗi rỗng");
        return;
    }

    // 1. Dạng toạ độ số: "35.7619, 139.1578"
    NSError *reErr = nil;
    NSRegularExpression *numRegex = [NSRegularExpression regularExpressionWithPattern:@"(-?\\d+(?:\\.\\d+)?)[\\s,]+(-?\\d+(?:\\.\\d+)?)"
                                                                              options:0
                                                                                error:&reErr];
    NSTextCheckingResult *numMatch = [numRegex firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (numMatch && numMatch.numberOfRanges >= 3) {
        NSString *latStr = [trimmed substringWithRange:[numMatch rangeAtIndex:1]];
        NSString *lonStr = [trimmed substringWithRange:[numMatch rangeAtIndex:2]];
        double lat = [latStr doubleValue];
        double lon = [lonStr doubleValue];
        if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
            if (completion) completion(YES, lat, lon, nil);
            return;
        }
    }

    // 2. Plus Code
    NSDictionary *info = [self extractPlusCodeInfoFromString:trimmed];
    if (!info) {
        if (completion) completion(NO, 0, 0, @"Không tìm thấy tọa độ hoặc Plus Code");
        return;
    }

    NSString *plusCode = info[@"code"];
    NSString *placeName = info[@"place"];
    NSRange plusRange = [plusCode rangeOfString:@"+"];
    NSInteger plusPos = (NSInteger)plusRange.location;

    if (plusPos == 8) {
        double lat, lon;
        if ([self decodeFullCode:plusCode latitude:&lat longitude:&lon]) {
            if (completion) completion(YES, lat, lon, nil);
        } else {
            if (completion) completion(NO, 0, 0, @"Plus Code đầy đủ không hợp lệ");
        }
        return;
    } else {
        // Short Code cần toạ độ tham chiếu
        if (placeName.length > 0) {
            CLGeocoder *geocoder = [[CLGeocoder alloc] init];
            [geocoder geocodeAddressString:placeName completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
                double refLat, refLon;
                if (placemarks.count > 0 && placemarks.firstObject.location) {
                    refLat = placemarks.firstObject.location.coordinate.latitude;
                    refLon = placemarks.firstObject.location.coordinate.longitude;
                } else {
                    FLLocationConfig *cfg = [FLLocationConfig sharedConfig];
                    if (cfg.latitude != 0 || cfg.longitude != 0) {
                        refLat = cfg.latitude;
                        refLon = cfg.longitude;
                    } else {
                        refLat = 21.0285;
                        refLon = 105.8544; // fallback Hà Nội
                    }
                }
                double outLat, outLon;
                if ([FLPlusCode recoverAndDecodeShortCode:plusCode referenceLat:refLat referenceLon:refLon outLatitude:&outLat outLongitude:&outLon]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(YES, outLat, outLon, nil);
                    });
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(NO, 0, 0, @"Không thể khôi phục Short Code");
                    });
                }
            }];
        } else {
            FLLocationConfig *cfg = [FLLocationConfig sharedConfig];
            double refLat = (cfg.latitude != 0 || cfg.longitude != 0) ? cfg.latitude : 21.0285;
            double refLon = (cfg.latitude != 0 || cfg.longitude != 0) ? cfg.longitude : 105.8544;
            double outLat, outLon;
            if ([self recoverAndDecodeShortCode:plusCode referenceLat:refLat referenceLon:refLon outLatitude:&outLat outLongitude:&outLon]) {
                if (completion) completion(YES, outLat, outLon, nil);
            } else {
                if (completion) completion(NO, 0, 0, @"Không thể khôi phục Short Code (cần thêm địa danh)");
            }
        }
    }
}

@end
