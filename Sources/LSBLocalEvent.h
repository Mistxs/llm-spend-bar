#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One billable LLM turn read from a local agent log.
@interface LSBLocalEvent : NSObject
@property (nonatomic, copy) NSString *eventID;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, copy) NSString *tool;
@property (nonatomic, copy) NSString *provider;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic, copy) NSString *sessionTitle;
@property (nonatomic, copy) NSString *project;
@property (nonatomic) long long inputTokens;
@property (nonatomic) long long outputTokens;
@property (nonatomic) long long reasoningTokens;
@property (nonatomic) long long cacheReadTokens;
@property (nonatomic) long long cacheWriteTokens;
@property (nonatomic) long long totalTokens;
@property (nonatomic) double costUSD;
@property (nonatomic, copy) NSString *costSource;
@property (nonatomic, copy) NSString *sourcePath;
@property (nonatomic, copy) NSString *rawMeta;
@end

NS_ASSUME_NONNULL_END
