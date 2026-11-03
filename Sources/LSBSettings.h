#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const LSBDisplayModeBars;
extern NSString *const LSBDisplayModeDollars;
extern NSString *const LSBDisplayModeTokens;

@interface LSBSettings : NSObject
+ (void)registerDefaults;

+ (NSString *)baseURLString;
+ (void)setBaseURLString:(NSString *)value;
+ (nullable NSURL *)baseURL;

+ (nullable NSString *)masterKey;
+ (BOOL)setMasterKey:(nullable NSString *)key error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)deleteMasterKey;

+ (double)dailyBudget;
+ (double)weeklyBudget;
+ (double)monthlyBudget;
+ (void)setDailyBudget:(double)value;
+ (void)setWeeklyBudget:(double)value;
+ (void)setMonthlyBudget:(double)value;

+ (NSTimeInterval)refreshInterval;
+ (void)setRefreshInterval:(NSTimeInterval)value;

+ (NSString *)displayMode;
+ (void)setDisplayMode:(NSString *)value;

+ (NSString *)configPath;
+ (void)setConfigPath:(NSString *)value;

+ (BOOL)demoMode;
+ (void)setDemoMode:(BOOL)value;
@end

NS_ASSUME_NONNULL_END
