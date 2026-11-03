#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Расход по одной модели за период.
@interface LSBModelSpend : NSObject
@property (nonatomic, copy) NSString *model;
@property (nonatomic) double spend;
@property (nonatomic) long long promptTokens;
@property (nonatomic) long long completionTokens;
@property (nonatomic) long long totalTokens;
@property (nonatomic) long long requests;
@end

/// Один диалог / сессия агента.
@interface LSBSessionSpend : NSObject
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *primaryModel;
@property (nonatomic, copy) NSArray<NSString *> *models;
@property (nonatomic) double spend;
@property (nonatomic) long long promptTokens;
@property (nonatomic) long long completionTokens;
@property (nonatomic) long long totalTokens;
@property (nonatomic) long long requests;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, strong) NSDate *lastActivity;
@end

/// Агрегаты за день / неделю / месяц.
@interface LSBPeriodStats : NSObject
@property (nonatomic) double spend;
@property (nonatomic) long long promptTokens;
@property (nonatomic) long long completionTokens;
@property (nonatomic) long long totalTokens;
@property (nonatomic) long long requests;
@property (nonatomic) long long cacheHits;
@property (nonatomic, copy) NSArray<LSBModelSpend *> *models;
@end

/// Всё, что нужно меню для отрисовки.
@interface LSBSummary : NSObject
@property (nonatomic, strong) LSBPeriodStats *today;
@property (nonatomic, strong) LSBPeriodStats *week;
@property (nonatomic, strong) LSBPeriodStats *month;
@property (nonatomic, copy) NSArray<LSBSessionSpend *> *sessions;
@property (nonatomic, strong) NSDate *generatedAt;
@property (nonatomic) NSInteger logCount;
@property (nonatomic) BOOL truncated;
@property (nonatomic) BOOL demo;
+ (instancetype)demoSummary;
@end

NS_ASSUME_NONNULL_END
