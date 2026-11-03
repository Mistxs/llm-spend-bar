#import "LSBModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Нормализованная строка из /spend/logs/v2.
@interface LSBSpendLog : NSObject
@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *modelID;
@property (nonatomic, copy) NSString *provider;
@property (nonatomic, copy) NSString *callType;
@property (nonatomic, copy) NSString *status;
@property (nonatomic) double spend;
@property (nonatomic) long long promptTokens;
@property (nonatomic) long long completionTokens;
@property (nonatomic) long long totalTokens;
@property (nonatomic) BOOL cacheHit;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, strong) NSDate *endedAt;
+ (nullable instancetype)logFromDictionary:(NSDictionary *)dictionary;
@end

@interface LSBSummaryBuilder : NSObject
+ (LSBSummary *)summaryFromLogs:(NSArray<LSBSpendLog *> *)logs
                       dayStart:(NSDate *)dayStart
                      weekStart:(NSDate *)weekStart
                     monthStart:(NSDate *)monthStart
                            now:(NSDate *)now
                      truncated:(BOOL)truncated;
@end

NS_ASSUME_NONNULL_END
