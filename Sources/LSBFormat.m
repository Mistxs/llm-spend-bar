#import "LSBFormat.h"

static NSDateFormatter *LSBFormatter(NSString *format) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"ru_RU"];
    formatter.dateFormat = format;
    return formatter;
}

@implementation LSBFormat

+ (NSString *)usd:(double)value {
    if (value <= 0) return @"$0.00";
    if (value >= 0.1) return [NSString stringWithFormat:@"$%.2f", value];
    if (value >= 0.001) return [NSString stringWithFormat:@"$%.3f", value];
    if (value >= 0.00001) return [NSString stringWithFormat:@"$%.5f", value];
    return [NSString stringWithFormat:@"$%.6f", value];
}

+ (NSString *)usdCompact:(double)value {
    if (value >= 1000) return [NSString stringWithFormat:@"$%.1fk", value / 1000.0];
    return [self usd:value];
}

+ (NSString *)tokens:(long long)value {
    if (value >= 1000000) {
        double millions = (double)value / 1000000.0;
        return millions >= 10 ? [NSString stringWithFormat:@"%.0fM", millions]
                              : [NSString stringWithFormat:@"%.1fM", millions];
    }
    if (value >= 1000) {
        double thousands = (double)value / 1000.0;
        return thousands >= 10 ? [NSString stringWithFormat:@"%.0fk", thousands]
                               : [NSString stringWithFormat:@"%.1fk", thousands];
    }
    return [NSString stringWithFormat:@"%lld", value];
}

+ (NSString *)requests:(long long)value {
    long long mod100 = value % 100;
    long long mod10 = value % 10;
    NSString *word = @"запросов";
    if (mod100 < 11 || mod100 > 14) {
        if (mod10 == 1) word = @"запрос";
        else if (mod10 >= 2 && mod10 <= 4) word = @"запроса";
    }
    return [NSString stringWithFormat:@"%lld %@", value, word];
}

+ (NSString *)percent:(double)fraction {
    double clamped = MIN(1, MAX(0, fraction));
    return [NSString stringWithFormat:@"%ld%%", (long)llround(clamped * 100)];
}

+ (NSString *)bar:(double)fraction {
    return [self bar:fraction width:10];
}

+ (NSString *)bar:(double)fraction width:(NSInteger)width {
    double clamped = MIN(1, MAX(0, fraction));
    NSInteger filled = (NSInteger)llround(clamped * (double)width);
    filled = MAX(0, MIN(width, filled));
    NSString *full = [@"" stringByPaddingToLength:(NSUInteger)filled withString:@"█" startingAtIndex:0];
    NSString *empty = [@"" stringByPaddingToLength:(NSUInteger)(width - filled) withString:@"░" startingAtIndex:0];
    return [full stringByAppendingString:empty];
}

+ (NSString *)relative:(NSDate *)date {
    if (!date) return @"";
    NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:date];
    if (interval < 60) return @"только что";
    if (interval < 3600) return [NSString stringWithFormat:@"%ld мин назад", (long)(interval / 60)];
    if (interval < 86400) return [NSString stringWithFormat:@"%ld ч назад", (long)(interval / 3600)];
    return [NSString stringWithFormat:@"%ld дн назад", (long)(interval / 86400)];
}

+ (NSString *)updated:(NSDate *)date {
    if (!date) return @"ещё не обновлялось";
    return [NSString stringWithFormat:@"обновлено в %@", [LSBFormatter(@"HH:mm:ss") stringFromDate:date]];
}

+ (NSString *)pad:(NSString *)value width:(NSInteger)width {
    NSUInteger length = value.length;
    if (length >= (NSUInteger)width) return value;
    return [value stringByPaddingToLength:(NSUInteger)width withString:@" " startingAtIndex:0];
}

+ (NSString *)shortSession:(NSString *)sessionID {
    if (sessionID.length <= 16) return sessionID;
    return [NSString stringWithFormat:@"…%@", [sessionID substringFromIndex:sessionID.length - 8]];
}

+ (NSString *)truncate:(NSString *)value width:(NSInteger)width {
    if (width <= 1 || value.length <= (NSUInteger)width) return value;
    return [[value substringToIndex:(NSUInteger)(width - 1)] stringByAppendingString:@"…"];
}

@end
