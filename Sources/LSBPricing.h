#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSBPricing : NSObject
+ (instancetype)sharedPricing;

/// Returns the estimated USD cost. `priced` is NO when no rate matched.
- (double)costForModel:(NSString *)model
              provider:(NSString *)provider
                 input:(long long)input
                output:(long long)output
             reasoning:(long long)reasoning
             cacheRead:(long long)cacheRead
            cacheWrite:(long long)cacheWrite
                priced:(BOOL *)priced;

- (nullable NSDictionary *)ratesForModel:(NSString *)model provider:(NSString *)provider;
- (void)reload;
@end

NS_ASSUME_NONNULL_END
