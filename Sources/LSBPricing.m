#import "LSBPricing.h"

static NSString *LSBNormalizeModel(NSString *value) {
    NSString *lower = [value lowercaseString];
    NSRange slash = [lower rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location != NSNotFound) lower = [lower substringFromIndex:slash.location + 1];
    lower = [lower stringByReplacingOccurrencesOfString:@"." withString:@"-"];
    lower = [lower stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    return lower;
}

static NSString *LSBNormalizeProvider(NSString *value) {
    NSString *lower = [[value lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    lower = [lower stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    if ([lower isEqualToString:@"opencodego"]) return @"opencode_go";
    if ([lower isEqualToString:@"google"]) return @"gemini";
    if ([lower isEqualToString:@"openai_compatible"]) return @"openai";
    return lower;
}

static NSNumber *LSBNumber(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        double number = [(NSString *)value doubleValue];
        return @(number);
    }
    return nil;
}

@implementation LSBPricing {
    NSDictionary<NSString *, NSDictionary *> *_raw;
    NSMutableDictionary<NSString *, NSDictionary *> *_byExact;
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *_byModel;
}

+ (instancetype)sharedPricing {
    static LSBPricing *pricing;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pricing = [LSBPricing new];
        [pricing reload];
    });
    return pricing;
}

- (void)reload {
    _raw = @{};
    _byExact = [NSMutableDictionary dictionary];
    _byModel = [NSMutableDictionary dictionary];

    NSURL *bundled = [[NSBundle mainBundle] URLForResource:@"pricing" withExtension:@"json"];
    if (bundled) {
        NSData *data = [NSData dataWithContentsOfURL:bundled];
        if (data) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if ([json isKindOfClass:[NSDictionary class]]) {
                [self mergePricingDictionary:json];
            }
        }
    }

    NSString *userPath = [@"~/Library/Application Support/LLM Spend Bar/pricing.json" stringByExpandingTildeInPath];
    NSData *userData = [NSData dataWithContentsOfFile:userPath];
    if (userData) {
        id json = [NSJSONSerialization JSONObjectWithData:userData options:0 error:NULL];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dictionary = json;
            if ([dictionary[@"models"] isKindOfClass:[NSDictionary class]]) {
                dictionary = dictionary[@"models"];
            }
            [self mergePricingDictionary:dictionary];
        }
    }
}

- (void)mergePricingDictionary:(NSDictionary *)dictionary {
    NSMutableDictionary *merged = [_raw mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in dictionary) {
        id value = dictionary[key];
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        merged[[key lowercaseString]] = value;
    }
    _raw = merged;

    [_byExact removeAllObjects];
    [_byModel removeAllObjects];
    for (NSString *key in _raw) {
        NSDictionary *rate = _raw[key];
        _byExact[key] = rate;
        NSString *model = key;
        NSRange slash = [model rangeOfString:@"/" options:NSBackwardsSearch];
        if (slash.location != NSNotFound) model = [model substringFromIndex:slash.location + 1];
        NSString *normalized = LSBNormalizeModel(model);
        if (normalized.length == 0) continue;
        if (!_byModel[normalized]) _byModel[normalized] = [NSMutableArray array];
        [_byModel[normalized] addObject:key];
    }
}

- (NSDictionary *)ratesForModel:(NSString *)model provider:(NSString *)provider {
    if (model.length == 0) return nil;
    NSString *normalizedProvider = LSBNormalizeProvider(provider ?: @"");
    NSString *lowerModel = [model lowercaseString];
    NSString *normalizedModel = LSBNormalizeModel(model);

    NSArray<NSString *> *candidates = @[
        [NSString stringWithFormat:@"%@/%@", normalizedProvider, lowerModel],
        [NSString stringWithFormat:@"%@/%@", normalizedProvider, normalizedModel],
        lowerModel,
        normalizedModel,
    ];
    for (NSString *candidate in candidates) {
        if (candidate.length == 0) continue;
        NSDictionary *rate = _byExact[candidate];
        if (rate) return rate;
    }

    NSArray<NSString *> *keys = _byModel[normalizedModel];
    if (keys.count > 0) {
        for (NSString *key in keys) {
            if ([key hasPrefix:[normalizedProvider stringByAppendingString:@"/"]]) {
                return _byExact[key];
            }
        }
        return _byExact[keys.firstObject];
    }

    // Fuzzy: strip common date suffixes and try a contains match.
    NSString *withoutDate = normalizedModel;
    NSRegularExpression *dateRegex = [NSRegularExpression regularExpressionWithPattern:@"-(20\\d{2}-?\\d{2}-?\\d{2})$" options:0 error:NULL];
    withoutDate = [dateRegex stringByReplacingMatchesInString:withoutDate options:0 range:NSMakeRange(0, withoutDate.length) withTemplate:@""];
    if (![withoutDate isEqualToString:normalizedModel]) {
        NSArray<NSString *> *fuzzyKeys = _byModel[withoutDate];
        if (fuzzyKeys.count > 0) {
            for (NSString *key in fuzzyKeys) {
                if ([key hasPrefix:[normalizedProvider stringByAppendingString:@"/"]]) {
                    return _byExact[key];
                }
            }
            return _byExact[fuzzyKeys.firstObject];
        }
    }

    return nil;
}

- (double)costForModel:(NSString *)model
              provider:(NSString *)provider
                 input:(long long)input
                output:(long long)output
             reasoning:(long long)reasoning
             cacheRead:(long long)cacheRead
            cacheWrite:(long long)cacheWrite
                priced:(BOOL *)priced {
    NSDictionary *rate = [self ratesForModel:model provider:provider];
    if (!rate) {
        if (priced) *priced = NO;
        return 0;
    }
    double inputRate = LSBNumber(rate[@"input_cost_per_token"] ?: rate[@"input"]).doubleValue;
    double outputRate = LSBNumber(rate[@"output_cost_per_token"] ?: rate[@"output"]).doubleValue;
    double cacheReadRate = LSBNumber(rate[@"cache_read_input_token_cost"] ?: rate[@"cache_read"]).doubleValue;
    double cacheWriteRate = LSBNumber(rate[@"cache_creation_input_token_cost"] ?: rate[@"cache_write"]).doubleValue;
    double reasoningRate = LSBNumber(rate[@"output_cost_per_reasoning_token"] ?: rate[@"reasoning"]).doubleValue;

    if (inputRate <= 0 && outputRate <= 0) {
        if (priced) *priced = NO;
        return 0;
    }
    if (cacheReadRate <= 0) cacheReadRate = inputRate;
    if (cacheWriteRate <= 0) cacheWriteRate = inputRate * 1.25;
    if (reasoningRate <= 0) reasoningRate = outputRate;

    double cost = 0;
    cost += (double)MAX(0LL, input) * inputRate;
    cost += (double)MAX(0LL, output) * outputRate;
    cost += (double)MAX(0LL, reasoning) * reasoningRate;
    cost += (double)MAX(0LL, cacheRead) * cacheReadRate;
    cost += (double)MAX(0LL, cacheWrite) * cacheWriteRate;
    if (priced) *priced = YES;
    return cost;
}

@end
