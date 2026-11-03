#import "LSBCollector.h"
#import <sqlite3.h>
#import "LSBPricing.h"
#import "LSBSettings.h"

static NSString *LSBStableHash(NSString *input) {
    uint64_t hash = 1469598103934665603ULL;
    const unsigned char *bytes = (const unsigned char *)input.UTF8String;
    for (size_t i = 0; bytes[i] != 0; i++) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", hash];
}

static NSString *LSBLastComponent(NSString *path) {
    if (path.length == 0) return @"";
    NSString *trimmed = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.lastPathComponent ?: @"";
}

static NSString *LSBString(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return @"";
}

static long long LSBLongLong(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value longLongValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value longLongValue];
    return 0;
}

static double LSBDouble(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value doubleValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value doubleValue];
    return 0;
}

static NSDictionary *LSBDictionary(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) return value;
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([parsed isKindOfClass:[NSDictionary class]]) return parsed;
    }
    return @{};
}

static NSDate *LSBDateFromMilliseconds(id value) {
    long long milliseconds = LSBLongLong(value);
    if (milliseconds <= 0) return nil;
    return [NSDate dateWithTimeIntervalSince1970:(double)milliseconds / 1000.0];
}

static NSDate *LSBDateFromISO(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        double number = [(NSNumber *)value doubleValue];
        if (number > 100000000000) number /= 1000.0;
        return [NSDate dateWithTimeIntervalSince1970:number];
    }
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *text = value;
    if (text.length == 0) return nil;
    text = [text stringByReplacingOccurrencesOfString:@" " withString:@"T"];
    if ([text hasSuffix:@"Z"]) text = [[text substringToIndex:text.length - 1] stringByAppendingString:@"+00:00"];
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [formatter dateFromString:text];
    if (!date) {
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        date = [formatter dateFromString:text];
    }
    return date;
}

static void LSBSetEventCost(LSBLocalEvent *event, LSBPricing *pricing) {
    BOOL priced = NO;
    double estimated = [pricing costForModel:event.model
                                    provider:event.provider
                                       input:event.inputTokens
                                      output:event.outputTokens
                                   reasoning:event.reasoningTokens
                                   cacheRead:event.cacheReadTokens
                                  cacheWrite:event.cacheWriteTokens
                                      priced:&priced];
    if (event.costUSD <= 0 && estimated > 0) {
        event.costUSD = estimated;
        event.costSource = priced ? @"estimated" : @"unpriced";
    } else if (event.costUSD > 0) {
        event.costSource = @"actual";
    } else {
        event.costSource = @"unpriced";
    }
}

static void LSBSetEventTotal(LSBLocalEvent *event) {
    event.totalTokens = event.inputTokens + event.outputTokens + event.reasoningTokens
        + event.cacheReadTokens + event.cacheWriteTokens;
}

@implementation LSBScanResult
- (instancetype)init {
    self = [super init];
    if (self) {
        _warnings = @[];
    }
    return self;
}
@end

@implementation LSBCollector {
    LSBStore *_store;
    LSBPricing *_pricing;
}

- (instancetype)initWithStore:(LSBStore *)store {
    self = [super init];
    if (self) {
        _store = store;
        _pricing = [LSBPricing sharedPricing];
    }
    return self;
}

- (NSString *)homePath:(NSString *)relative {
    return [relative stringByExpandingTildeInPath];
}

- (NSArray<NSString *> *)jsonlFilesAtRoot:(NSString *)root {
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtPath:root];
    for (NSString *relative in enumerator) {
        if ([relative.pathExtension.lowercaseString isEqualToString:@"jsonl"]) {
            [files addObject:[root stringByAppendingPathComponent:relative]];
        }
    }
    return files;
}

- (LSBScanResult *)scanWithError:(NSError **)error {
    LSBScanResult *result = [LSBScanResult new];
    NSMutableArray<LSBLocalEvent *> *events = [NSMutableArray array];
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];

    [self scanOpenCodeInto:events warnings:warnings];
    [self scanClaudeInto:events warnings:warnings];
    [self scanCodexInto:events warnings:warnings];

    result.eventsFound = events.count;
    NSError *storeError = nil;
    if (![_store upsertEvents:events error:&storeError]) {
        if (error) *error = storeError;
        return result;
    }
    result.eventsWritten = events.count;
    result.warnings = warnings;
    return result;
}

#pragma mark - OpenCode

- (void)scanOpenCodeInto:(NSMutableArray<LSBLocalEvent *> *)events warnings:(NSMutableArray<NSString *> *)warnings {
    NSString *path = [[[NSProcessInfo processInfo] environment][@"OPENCODE_DB"] stringByExpandingTildeInPath];
    if (path.length == 0) path = LSBSettings.opencodeDBPath;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;

    sqlite3 *db = NULL;
    if (sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        [warnings addObject:@"OpenCode: не удалось открыть базу"];
        if (db) sqlite3_close(db);
        return;
    }
    sqlite3_busy_timeout(db, 2000);
    const char *sql =
        "SELECT m.id, m.session_id, m.time_created, m.data, s.title, s.directory, p.name"
        " FROM session_message m"
        " JOIN session_v2 s ON s.id = m.session_id"
        " LEFT JOIN project p ON p.id = s.project_id"
        " WHERE m.type = 'assistant'"
        " ORDER BY m.time_created ASC";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, sql, -1, &statement, NULL) != SQLITE_OK) {
        [warnings addObject:@"OpenCode: не удалось прочитать session_message"];
        sqlite3_close(db);
        return;
    }

    while (sqlite3_step(statement) == SQLITE_ROW) {
        NSString *messageID = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)] ?: @"";
        NSString *sessionID = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 1)] ?: @"";
        double createdAt = sqlite3_column_double(statement, 2);
        const unsigned char *rawData = sqlite3_column_text(statement, 3);
        NSString *title = sqlite3_column_text(statement, 4) ? [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 4)] : @"";
        NSString *directory = sqlite3_column_text(statement, 5) ? [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 5)] : @"";
        NSString *projectName = sqlite3_column_text(statement, 6) ? [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 6)] : @"";
        if (!rawData) continue;
        NSData *data = [NSData dataWithBytes:rawData length:strlen((const char *)rawData)];
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (![json isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *dictionary = json;
        NSDictionary *tokens = LSBDictionary(dictionary[@"tokens"]);
        if (tokens.count == 0) continue;
        NSDictionary *cache = LSBDictionary(tokens[@"cache"]);
        NSDictionary *modelInfo = LSBDictionary(dictionary[@"model"]);
        NSDate *timestamp = LSBDateFromMilliseconds(LSBDictionary(dictionary[@"time"])[@"created"]) ?: LSBDateFromMilliseconds(@(createdAt));
        if (!timestamp) timestamp = [NSDate date];

        LSBLocalEvent *event = [LSBLocalEvent new];
        event.eventID = [@"opencode:" stringByAppendingString:(messageID.length > 0 ? messageID : LSBStableHash([NSString stringWithFormat:@"%@:%f", sessionID, createdAt]))];
        event.timestamp = timestamp;
        event.tool = @"opencode";
        event.provider = LSBString(modelInfo[@"providerID"]);
        event.model = LSBString(modelInfo[@"id"]);
        event.sessionID = sessionID;
        event.project = projectName.length > 0 ? projectName : LSBLastComponent(directory);
        event.sessionTitle = title.length > 0 ? title : event.project;
        event.inputTokens = LSBLongLong(tokens[@"input"]);
        event.outputTokens = LSBLongLong(tokens[@"output"]);
        event.reasoningTokens = LSBLongLong(tokens[@"reasoning"]);
        event.cacheReadTokens = LSBLongLong(cache[@"read"]);
        event.cacheWriteTokens = LSBLongLong(cache[@"write"]);
        event.costUSD = LSBDouble(dictionary[@"cost"]);
        event.sourcePath = path;
        LSBSetEventTotal(event);
        if (event.totalTokens <= 0) continue;
        LSBSetEventCost(event, _pricing);
        [events addObject:event];
    }
    sqlite3_finalize(statement);
    sqlite3_close(db);
}

#pragma mark - Claude Code

- (void)scanClaudeInto:(NSMutableArray<LSBLocalEvent *> *)events warnings:(NSMutableArray<NSString *> *)warnings {
    NSString *root = [[[NSProcessInfo processInfo] environment][@"CLAUDE_PROJECTS_DIR"] stringByExpandingTildeInPath];
    if (root.length == 0) root = LSBSettings.claudeProjectsPath;
    if (![[NSFileManager defaultManager] fileExistsAtPath:root]) return;

    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *path in [self jsonlFilesAtRoot:root]) {
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        double mtime = [attributes[NSFileModificationDate] timeIntervalSince1970];
        long long size = [attributes[NSFileSize] longLongValue];
        if ([_store fileUnchanged:path mtime:mtime size:size]) continue;

        NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (contents.length == 0) continue;
        NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            if (line.length < 2) continue;
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if (![json isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *dictionary = json;
            if (![LSBString(dictionary[@"type"]) isEqualToString:@"assistant"]) continue;
            NSDictionary *message = LSBDictionary(dictionary[@"message"]);
            NSDictionary *usage = LSBDictionary(message[@"usage"]);
            if (usage.count == 0) continue;

            NSString *messageID = LSBString(message[@"id"]);
            NSString *requestID = LSBString(dictionary[@"requestId"]);
            NSString *sessionID = LSBString(dictionary[@"sessionId"]);
            NSDate *timestamp = LSBDateFromISO(dictionary[@"timestamp"]) ?: [NSDate date];
            NSString *cwd = LSBString(dictionary[@"cwd"]);
            NSString *project = LSBLastComponent(cwd);
            if (project.length == 0) project = LSBLastComponent([path stringByDeletingLastPathComponent]);

            LSBLocalEvent *event = [LSBLocalEvent new];
            NSString *identity = messageID.length > 0 ? messageID : (requestID.length > 0 ? requestID : LSBStableHash([NSString stringWithFormat:@"%@:%f", sessionID, timestamp.timeIntervalSince1970]));
            event.eventID = [@"claude:" stringByAppendingString:identity];
            event.timestamp = timestamp;
            event.tool = @"claude";
            event.provider = @"anthropic";
            event.model = LSBString(message[@"model"]);
            event.sessionID = sessionID;
            event.project = project;
            event.sessionTitle = project;
            event.inputTokens = LSBLongLong(usage[@"input_tokens"]);
            event.outputTokens = LSBLongLong(usage[@"output_tokens"]);
            event.reasoningTokens = LSBLongLong(usage[@"reasoning_tokens"]);
            event.cacheReadTokens = LSBLongLong(usage[@"cache_read_input_tokens"]);
            event.cacheWriteTokens = LSBLongLong(usage[@"cache_creation_input_tokens"]);
            double actualCost = LSBDouble(message[@"costUSD"]);
            if (actualCost <= 0) actualCost = LSBDouble(dictionary[@"costUSD"]);
            if (actualCost > 0) event.costUSD = actualCost;
            event.sourcePath = path;
            LSBSetEventTotal(event);
            if (event.totalTokens <= 0) continue;
            LSBSetEventCost(event, _pricing);
            [events addObject:event];
        }
        [_store recordFile:path mtime:mtime size:size];
    }
}

#pragma mark - Codex

- (void)scanCodexInto:(NSMutableArray<LSBLocalEvent *> *)events warnings:(NSMutableArray<NSString *> *)warnings {
    NSString *root = [[[NSProcessInfo processInfo] environment][@"CODEX_SESSIONS_DIR"] stringByExpandingTildeInPath];
    if (root.length == 0) root = LSBSettings.codexSessionsPath;
    if (![[NSFileManager defaultManager] fileExistsAtPath:root]) return;

    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *path in [self jsonlFilesAtRoot:root]) {
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        double mtime = [attributes[NSFileModificationDate] timeIntervalSince1970];
        long long size = [attributes[NSFileSize] longLongValue];
        if ([_store fileUnchanged:path mtime:mtime size:size]) continue;

        NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (contents.length == 0) continue;
        NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

        NSString *sessionID = LSBLastComponent(path.stringByDeletingPathExtension);
        NSString *cwd = @"";
        NSString *model = @"";
        NSString *provider = @"openai";
        long long previousTotal = 0;

        for (NSString *line in lines) {
            if (line.length < 2) continue;
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if (![json isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *dictionary = json;
            NSString *type = LSBString(dictionary[@"type"]);
            NSDictionary *payload = LSBDictionary(dictionary[@"payload"]);
            if ([type isEqualToString:@"session_meta"]) {
                sessionID = LSBString(payload[@"id"]) ?: sessionID;
                cwd = LSBString(payload[@"cwd"]);
                model = LSBString(payload[@"model"]);
                provider = LSBString(payload[@"model_provider"]) ?: provider;
                continue;
            }
            if ([type isEqualToString:@"turn_context"]) {
                model = LSBString(payload[@"model"]) ?: model;
                continue;
            }
            if (![type isEqualToString:@"event_msg"] || ![LSBString(payload[@"type"]) isEqualToString:@"token_count"]) continue;
            NSDictionary *info = LSBDictionary(payload[@"info"]);
            NSDictionary *last = LSBDictionary(info[@"last_token_usage"]);
            NSDictionary *total = LSBDictionary(info[@"total_token_usage"]);
            NSDictionary *usage = last.count > 0 ? last : total;
            if (usage.count == 0) continue;

            long long input = LSBLongLong(usage[@"input_tokens"]);
            long long cached = LSBLongLong(usage[@"cached_input_tokens"]);
            long long output = LSBLongLong(usage[@"output_tokens"]);
            long long reasoning = LSBLongLong(usage[@"reasoning_output_tokens"]);
            long long totalTokens = LSBLongLong(usage[@"total_tokens"]);
            if (last.count == 0 && total.count > 0) {
                long long deltaInput = MAX(0, input - previousTotal);
                // When only cumulative totals are available, use the growth of
                // the total as the per-turn token count.
                long long delta = MAX(0, totalTokens - previousTotal);
                if (delta <= 0) continue;
                input = delta;
                cached = 0;
                output = 0;
                reasoning = 0;
                totalTokens = delta;
                (void)deltaInput;
            }
            previousTotal = MAX(previousTotal, LSBLongLong(total[@"total_tokens"]));

            NSDate *timestamp = LSBDateFromISO(dictionary[@"timestamp"]) ?: [NSDate date];
            LSBLocalEvent *event = [LSBLocalEvent new];
            NSString *requestID = LSBString(payload[@"request_id"]);
            event.eventID = [@"codex:" stringByAppendingString:(requestID.length > 0
                ? [NSString stringWithFormat:@"%@:%@", sessionID, requestID]
                : LSBStableHash([NSString stringWithFormat:@"%@:%f:%lld", sessionID, timestamp.timeIntervalSince1970, totalTokens]))];
            event.timestamp = timestamp;
            event.tool = @"codex";
            event.provider = provider;
            event.model = model.length > 0 ? model : @"gpt-5";
            event.sessionID = sessionID;
            event.project = LSBLastComponent(cwd);
            event.sessionTitle = event.project.length > 0 ? event.project : @"Codex session";
            event.cacheReadTokens = cached;
            event.inputTokens = MAX(0, input - cached);
            event.outputTokens = output;
            event.reasoningTokens = reasoning;
            event.sourcePath = path;
            LSBSetEventTotal(event);
            if (event.totalTokens <= 0) continue;
            LSBSetEventCost(event, _pricing);
            [events addObject:event];
        }
        [_store recordFile:path mtime:mtime size:size];
    }
}

@end
