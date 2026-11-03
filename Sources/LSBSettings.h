#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const LSBDisplayModeBars;
extern NSString *const LSBDisplayModeDollars;
extern NSString *const LSBDisplayModeTokens;

@interface LSBSettings : NSObject
+ (void)registerDefaults;

+ (double)dailyBudget;
+ (double)weeklyBudget;
+ (double)monthlyBudget;
+ (void)setDailyBudget:(double)value;
+ (void)setWeeklyBudget:(double)value;
+ (void)setMonthlyBudget:(double)value;

+ (NSString *)displayMode;
+ (void)setDisplayMode:(NSString *)value;

+ (NSString *)dataDirectory;
+ (NSTimeInterval)scanInterval;
+ (void)setScanInterval:(NSTimeInterval)value;
+ (NSString *)claudeProjectsPath;
+ (void)setClaudeProjectsPath:(NSString *)value;
+ (NSString *)codexSessionsPath;
+ (void)setCodexSessionsPath:(NSString *)value;
+ (NSString *)opencodeDBPath;
+ (void)setOpencodeDBPath:(NSString *)value;
+ (NSString *)pricingOverridePath;
+ (void)setPricingOverridePath:(NSString *)value;

+ (double)subscriptionPriceForTool:(NSString *)tool;
+ (void)setSubscriptionPrice:(double)price forTool:(NSString *)tool;
@end

NS_ASSUME_NONNULL_END
