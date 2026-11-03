#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSBFormat : NSObject
+ (NSString *)usd:(double)value;
+ (NSString *)usdCompact:(double)value;
+ (NSString *)tokens:(long long)value;
+ (NSString *)requests:(long long)value;
+ (NSString *)percent:(double)fraction;
+ (NSString *)bar:(double)fraction;
+ (NSString *)bar:(double)fraction width:(NSInteger)width;
+ (NSString *)relative:(nullable NSDate *)date;
+ (NSString *)updated:(nullable NSDate *)date;
+ (NSString *)pad:(NSString *)value width:(NSInteger)width;
+ (NSString *)shortSession:(NSString *)sessionID;
+ (NSString *)truncate:(NSString *)value width:(NSInteger)width;
@end

NS_ASSUME_NONNULL_END
