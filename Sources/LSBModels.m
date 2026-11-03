#import "LSBModels.h"
#import "LSBModels+Internal.h"

#pragma mark - Helpers

static NSString *LSBString(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return nil;
}

static double LSBDouble(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value doubleValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value doubleValue];
    return 0;
}

static long long LSBLongLong(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value longLongValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value longLongValue];
    return 0;
}

static BOOL LSBBool(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value boolValue];
    if ([value isKindOfClass:[NSString class]]) {
        NSString *lower = [(NSString *)value lowercaseString];
        return [lower isEqualToString:@"true"] || [lower isEqualToString:@"1"] || [lower isEqualToString:@"yes"];
    }
    return NO;
}

static NSDictionary *LSBDictionary(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        NSData *data = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return @{};
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([parsed isKindOfClass:[NSDictionary class]]) return parsed;
    }
    return @{};
}

static NSDate *LSBParseDate(id value) {
    if ([value isKindOfClass:[NSDate class]]) return value;
    if (![value isKindOfClass:[NSString class]]) return nil;

    NSString *raw = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) return nil;

    NSString *string = [raw stringByReplacingOccurrencesOfString:@" " withString:@"T"];
    if (string.length == 10) {
        string = [string stringByAppendingString:@"T00:00:00Z"];
    }

    NSRange t = [string rangeOfString:@"T"];
    if (t.location != NSNotFound) {
        NSString *after = [string substringFromIndex:t.location + 1];
        BOOL hasZone = [after hasSuffix:@"Z"]
            || [after rangeOfString:@"+"].location != NSNotFound
            || [after rangeOfString:@"-"].location != NSNotFound;
        if (!hasZone) string = [string stringByAppendingString:@"Z"];
    }

    static NSISO8601DateFormatter *fractionalFormatter;
    static NSISO8601DateFormatter *plainFormatter;
    static NSDateFormatter *fallbackFormatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fractionalFormatter = [NSISO8601DateFormatter new];
        fractionalFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime
            | NSISO8601DateFormatWithFractionalSeconds;

        plainFormatter = [NSISO8601DateFormatter new];
        plainFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;

        fallbackFormatter = [NSDateFormatter new];
        fallbackFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fallbackFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        fallbackFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX";
    });

    NSDate *date = [fractionalFormatter dateFromString:string];
    if (!date) date = [plainFormatter dateFromString:string];
    if (!date) date = [fallbackFormatter dateFromString:string];
    return date;
}

#pragma mark - LSBModelSpend

@implementation LSBModelSpend
@end

#pragma mark - LSBSessionSpend

@implementation LSBSessionSpend
- (instancetype)init {
    self = [super init];
    if (self) {
        _models = @[];
        _title = @"";
        _primaryModel = @"";
        _sessionID = @"";
    }
    return self;
}
@end

#pragma mark - LSBPeriodStats

@implementation LSBPeriodStats
- (instancetype)init {
    self = [super init];
    if (self) {
        _models = @[];
    }
    return self;
}
@end

#pragma mark - LSBSummary

@implementation LSBSummary
+ (instancetype)demoSummary {
    LSBSummary *summary = [LSBSummary new];
    NSDate *now = [NSDate date];

    LSBModelSpend *gpt = [LSBModelSpend new];
    gpt.model = @"gpt-5.1";
    gpt.spend = 1.84;
    gpt.promptTokens = 612000;
    gpt.completionTokens = 184000;
    gpt.totalTokens = 796000;
    gpt.requests = 18;

    LSBModelSpend *claude = [LSBModelSpend new];
    claude.model = @"claude-sonnet-4.5";
    claude.spend = 1.21;
    claude.promptTokens = 288000;
    claude.completionTokens = 92000;
    claude.totalTokens = 380000;
    claude.requests = 12;

    LSBModelSpend *gemini = [LSBModelSpend new];
    gemini.model = @"gemini-2.5-pro";
    gemini.spend = 0.37;
    gemini.promptTokens = 94000;
    gemini.completionTokens = 31000;
    gemini.totalTokens = 125000;
    gemini.requests = 8;

    LSBPeriodStats *today = [LSBPeriodStats new];
    today.spend = 3.42;
    today.promptTokens = 994000;
    today.completionTokens = 307000;
    today.totalTokens = 1301000;
    today.requests = 38;
    today.cacheHits = 11;
    today.models = @[gpt, claude, gemini];

    LSBPeriodStats *week = [LSBPeriodStats new];
    week.spend = 18.73;
    week.promptTokens = 4380000;
    week.completionTokens = 1020000;
    week.totalTokens = 5400000;
    week.requests = 210;
    week.cacheHits = 64;
    week.models = @[gpt, claude, gemini];

    LSBPeriodStats *month = [LSBPeriodStats new];
    month.spend = 64.21;
    month.promptTokens = 15100000;
    month.completionTokens = 3800000;
    month.totalTokens = 18900000;
    month.requests = 780;
    month.cacheHits = 231;
    month.models = @[gpt, claude, gemini];

    LSBSessionSpend *opencode = [LSBSessionSpend new];
    opencode.sessionID = @"ses_8f31c2a1";
    opencode.title = @"opencode · auth refactor";
    opencode.primaryModel = @"gpt-5.1";
    opencode.models = @[@"gpt-5.1", @"claude-sonnet-4.5"];
    opencode.spend = 1.12;
    opencode.totalTokens = 418000;
    opencode.requests = 14;
    opencode.startedAt = [now dateByAddingTimeInterval:-7200];
    opencode.lastActivity = [now dateByAddingTimeInterval:-240];

    LSBSessionSpend *chat = [LSBSessionSpend new];
    chat.sessionID = @"ses_2bd90e77";
    chat.title = @"ChatGPT · SQL review";
    chat.primaryModel = @"gpt-5.1";
    chat.models = @[@"gpt-5.1"];
    chat.spend = 0.72;
    chat.totalTokens = 267000;
    chat.requests = 9;
    chat.startedAt = [now dateByAddingTimeInterval:-5400];
    chat.lastActivity = [now dateByAddingTimeInterval:-900];

    LSBSessionSpend *claudeSession = [LSBSessionSpend new];
    claudeSession.sessionID = @"ses_71aa03cd";
    claudeSession.title = @"Claude Code · payments";
    claudeSession.primaryModel = @"claude-sonnet-4.5";
    claudeSession.models = @[@"claude-sonnet-4.5", @"gemini-2.5-pro"];
    claudeSession.spend = 0.91;
    claudeSession.totalTokens = 352000;
    claudeSession.requests = 10;
    claudeSession.startedAt = [now dateByAddingTimeInterval:-10800];
    claudeSession.lastActivity = [now dateByAddingTimeInterval:-1800];

    LSBSessionSpend *agent = [LSBSessionSpend new];
    agent.sessionID = @"ses_4ce18b90";
    agent.title = @"Codex · flaky tests";
    agent.primaryModel = @"gemini-2.5-pro";
    agent.models = @[@"gemini-2.5-pro"];
    agent.spend = 0.37;
    agent.totalTokens = 125000;
    agent.requests = 5;
    agent.startedAt = [now dateByAddingTimeInterval:-3600];
    agent.lastActivity = [now dateByAddingTimeInterval:-2400];

    summary.today = today;
    summary.week = week;
    summary.month = month;
    summary.sessions = @[opencode, chat, claudeSession, agent];
    summary.generatedAt = now;
    summary.logCount = 38;
    summary.demo = YES;
    return summary;
}
@end

#pragma mark - LSBSpendLog

@implementation LSBSpendLog

+ (instancetype)logFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;

    NSDate *startedAt = LSBParseDate(dictionary[@"startTime"]);
    if (!startedAt) startedAt = LSBParseDate(dictionary[@"start_time"]);
    if (!startedAt) startedAt = LSBParseDate(dictionary[@"created_at"]);
    if (!startedAt) return nil;

    LSBSpendLog *log = [LSBSpendLog new];
    log.requestID = LSBString(dictionary[@"request_id"]) ?: @"";
    log.startedAt = startedAt;
    log.endedAt = LSBParseDate(dictionary[@"endTime"]) ?: LSBParseDate(dictionary[@"end_time"]) ?: startedAt;

    NSDictionary *metadata = LSBDictionary(dictionary[@"metadata"]);
    NSDictionary *spendMetadata = LSBDictionary(metadata[@"spend_logs_metadata"]);

    NSString *sessionID = LSBString(dictionary[@"session_id"]);
    if (sessionID.length == 0) sessionID = LSBString(metadata[@"session_id"]);
    if (sessionID.length == 0) sessionID = LSBString(metadata[@"trace_id"]);
    if (sessionID.length == 0) sessionID = LSBString(spendMetadata[@"session_id"]);
    if (sessionID.length == 0) sessionID = LSBString(spendMetadata[@"trace_id"]);
    if (sessionID.length == 0) sessionID = log.requestID;
    if (sessionID.length == 0) sessionID = @"unknown";
    log.sessionID = sessionID;

    NSString *modelGroup = LSBString(dictionary[@"model_group"]);
    NSString *model = LSBString(dictionary[@"model"]);
    if (model.length == 0) model = LSBString(dictionary[@"model_id"]);
    log.modelID = model ?: @"";
    log.model = modelGroup.length > 0 ? modelGroup : (model.length > 0 ? model : @"unknown");
    log.provider = LSBString(dictionary[@"custom_llm_provider"]) ?: @"";
    log.callType = LSBString(dictionary[@"call_type"]) ?: @"";
    log.status = LSBString(dictionary[@"status"]) ?: @"success";

    log.spend = LSBDouble(dictionary[@"spend"]);
    if (log.spend == 0) log.spend = LSBDouble(dictionary[@"response_cost"]);

    log.promptTokens = LSBLongLong(dictionary[@"prompt_tokens"]);
    log.completionTokens = LSBLongLong(dictionary[@"completion_tokens"]);
    log.totalTokens = LSBLongLong(dictionary[@"total_tokens"]);
    if (log.totalTokens == 0) log.totalTokens = log.promptTokens + log.completionTokens;

    log.cacheHit = LSBBool(dictionary[@"cache_hit"]);

    NSString *title = LSBString(spendMetadata[@"title"]);
    if (title.length == 0) title = LSBString(spendMetadata[@"session_title"]);
    if (title.length == 0) title = LSBString(spendMetadata[@"name"]);
    if (title.length == 0) title = LSBString(metadata[@"session_title"]);
    if (title.length == 0) title = LSBString(dictionary[@"end_user"]);
    if (title.length == 0) title = LSBString(dictionary[@"user"]);
    if ([title isEqualToString:@"default_user_id"] || [title hasPrefix:@"litellm_proxy"]) title = nil;
    if (title.length == 0) title = log.model;
    log.title = title ?: @"";

    return log;
}

@end

#pragma mark - Accumulators

@interface LSBPeriodAccumulator : NSObject
@property (nonatomic) double spend;
@property (nonatomic) long long promptTokens;
@property (nonatomic) long long completionTokens;
@property (nonatomic) long long totalTokens;
@property (nonatomic) long long requests;
@property (nonatomic) long long cacheHits;
@property (nonatomic, strong) NSMutableDictionary<NSString *, LSBModelSpend *> *models;
- (void)addLog:(LSBSpendLog *)log;
- (LSBPeriodStats *)stats;
@end

@implementation LSBPeriodAccumulator
- (instancetype)init {
    self = [super init];
    if (self) {
        _models = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)addLog:(LSBSpendLog *)log {
    self.spend += log.spend;
    self.promptTokens += log.promptTokens;
    self.completionTokens += log.completionTokens;
    self.totalTokens += log.totalTokens;
    self.requests += 1;
    if (log.cacheHit) self.cacheHits += 1;

    LSBModelSpend *model = self.models[log.model];
    if (!model) {
        model = [LSBModelSpend new];
        model.model = log.model;
        self.models[log.model] = model;
    }
    model.spend += log.spend;
    model.promptTokens += log.promptTokens;
    model.completionTokens += log.completionTokens;
    model.totalTokens += log.totalTokens;
    model.requests += 1;
}

- (LSBPeriodStats *)stats {
    LSBPeriodStats *stats = [LSBPeriodStats new];
    stats.spend = self.spend;
    stats.promptTokens = self.promptTokens;
    stats.completionTokens = self.completionTokens;
    stats.totalTokens = self.totalTokens;
    stats.requests = self.requests;
    stats.cacheHits = self.cacheHits;
    stats.models = [self.models.allValues sortedArrayUsingComparator:^NSComparisonResult(LSBModelSpend *a, LSBModelSpend *b) {
        if (a.spend != b.spend) return a.spend > b.spend ? NSOrderedAscending : NSOrderedDescending;
        if (a.totalTokens != b.totalTokens) return a.totalTokens > b.totalTokens ? NSOrderedAscending : NSOrderedDescending;
        return [a.model compare:b.model];
    }];
    return stats;
}
@end

#pragma mark - Summary builder

@implementation LSBSummaryBuilder

+ (LSBSummary *)summaryFromLogs:(NSArray<LSBSpendLog *> *)logs
                       dayStart:(NSDate *)dayStart
                      weekStart:(NSDate *)weekStart
                     monthStart:(NSDate *)monthStart
                            now:(NSDate *)now
                      truncated:(BOOL)truncated {
    LSBPeriodAccumulator *today = [LSBPeriodAccumulator new];
    LSBPeriodAccumulator *week = [LSBPeriodAccumulator new];
    LSBPeriodAccumulator *month = [LSBPeriodAccumulator new];

    NSMutableDictionary<NSString *, LSBSessionSpend *> *sessions = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *sessionModels = [NSMutableDictionary dictionary];

    for (LSBSpendLog *log in logs) {
        NSDate *date = log.startedAt;
        if ([date compare:monthStart] != NSOrderedAscending) [month addLog:log];
        if ([date compare:weekStart] != NSOrderedAscending) [week addLog:log];
        if ([date compare:dayStart] == NSOrderedAscending) continue;

        [today addLog:log];

        LSBSessionSpend *session = sessions[log.sessionID];
        if (!session) {
            session = [LSBSessionSpend new];
            session.sessionID = log.sessionID;
            session.title = log.title;
            session.primaryModel = log.model;
            session.startedAt = log.startedAt;
            session.lastActivity = log.endedAt ?: log.startedAt;
            sessions[log.sessionID] = session;
            sessionModels[log.sessionID] = [NSMutableSet set];
        }

        session.spend += log.spend;
        session.promptTokens += log.promptTokens;
        session.completionTokens += log.completionTokens;
        session.totalTokens += log.totalTokens;
        session.requests += 1;
        if (log.title.length > 0 && (session.title.length == 0 || [session.title isEqualToString:session.primaryModel])) {
            session.title = log.title;
        }
        if ([log.startedAt compare:session.startedAt] == NSOrderedAscending) session.startedAt = log.startedAt;
        NSDate *activity = log.endedAt ?: log.startedAt;
        if ([activity compare:session.lastActivity] == NSOrderedDescending) session.lastActivity = activity;
        if (log.model.length > 0) [sessionModels[log.sessionID] addObject:log.model];
    }

    for (LSBSessionSpend *session in sessions.allValues) {
        NSSet *models = sessionModels[session.sessionID];
        session.models = [models.allObjects sortedArrayUsingSelector:@selector(compare:)];
        if (session.models.count > 0 && session.primaryModel.length == 0) {
            session.primaryModel = session.models.firstObject;
        }
    }

    NSArray<LSBSessionSpend *> *sortedSessions = [sessions.allValues sortedArrayUsingComparator:^NSComparisonResult(LSBSessionSpend *a, LSBSessionSpend *b) {
        if (a.spend != b.spend) return a.spend > b.spend ? NSOrderedAscending : NSOrderedDescending;
        return [b.lastActivity compare:a.lastActivity];
    }];

    LSBSummary *summary = [LSBSummary new];
    summary.today = [today stats];
    summary.week = [week stats];
    summary.month = [month stats];
    summary.sessions = sortedSessions;
    summary.generatedAt = now;
    summary.logCount = (NSInteger)logs.count;
    summary.truncated = truncated;
    return summary;
}

@end
