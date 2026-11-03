#import "LSBStore.h"
#import <sqlite3.h>
#import "LSBSettings.h"

static NSError *LSBStoreError(NSString *message) {
    return [NSError errorWithDomain:@"dev.llmspendbar.store"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *LSBStringColumn(sqlite3_stmt *statement, int index) {
    const unsigned char *text = sqlite3_column_text(statement, index);
    return text ? [NSString stringWithUTF8String:(const char *)text] : @"";
}

static void LSBAppendJSONLine(NSFileHandle *handle, NSDictionary *dictionary) {
    if (!handle) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:NULL];
    if (!data) return;
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

@implementation LSBStore {
    sqlite3 *_db;
    NSFileHandle *_jsonlHandle;
}

- (instancetype)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (self) {
        _directory = [directory copy];
        _databasePath = [directory stringByAppendingPathComponent:@"usage.sqlite"];
        _jsonlPath = [directory stringByAppendingPathComponent:@"events.jsonl"];
    }
    return self;
}

- (BOOL)open:(NSError **)error {
    [[NSFileManager defaultManager] createDirectoryAtPath:self.directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:error];
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.jsonlPath]) {
        [[NSFileManager defaultManager] createFileAtPath:self.jsonlPath contents:nil attributes:nil];
    }
    _jsonlHandle = [NSFileHandle fileHandleForWritingAtPath:self.jsonlPath];

    int result = sqlite3_open_v2([self.databasePath fileSystemRepresentation],
                                 &_db,
                                 SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                                 NULL);
    if (result != SQLITE_OK) {
        if (error) *error = LSBStoreError([NSString stringWithFormat:@"Не удалось открыть SQLite: %s", sqlite3_errmsg(_db)]);
        return NO;
    }
    sqlite3_busy_timeout(_db, 3000);
    sqlite3_exec(_db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", NULL, NULL, NULL);

    const char *schema =
        "CREATE TABLE IF NOT EXISTS events ("
        " event_id TEXT PRIMARY KEY,"
        " ts REAL NOT NULL,"
        " tool TEXT NOT NULL DEFAULT '',"
        " provider TEXT NOT NULL DEFAULT '',"
        " model TEXT NOT NULL DEFAULT '',"
        " session_id TEXT NOT NULL DEFAULT '',"
        " session_title TEXT NOT NULL DEFAULT '',"
        " project TEXT NOT NULL DEFAULT '',"
        " input_tokens INTEGER NOT NULL DEFAULT 0,"
        " output_tokens INTEGER NOT NULL DEFAULT 0,"
        " reasoning_tokens INTEGER NOT NULL DEFAULT 0,"
        " cache_read_tokens INTEGER NOT NULL DEFAULT 0,"
        " cache_write_tokens INTEGER NOT NULL DEFAULT 0,"
        " total_tokens INTEGER NOT NULL DEFAULT 0,"
        " cost_usd REAL NOT NULL DEFAULT 0,"
        " cost_source TEXT NOT NULL DEFAULT 'estimated',"
        " source_path TEXT NOT NULL DEFAULT '',"
        " raw_meta TEXT NOT NULL DEFAULT ''"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);"
        "CREATE INDEX IF NOT EXISTS idx_events_tool ON events(tool);"
        "CREATE INDEX IF NOT EXISTS idx_events_model ON events(model);"
        "CREATE INDEX IF NOT EXISTS idx_events_project ON events(project);"
        "CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);"
        "CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, mtime REAL NOT NULL, size INTEGER NOT NULL);"
        "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);";

    char *errorMessage = NULL;
    if (sqlite3_exec(_db, schema, NULL, NULL, &errorMessage) != SQLITE_OK) {
        if (error) *error = LSBStoreError([NSString stringWithFormat:@"Не удалось создать схему: %s", errorMessage ?: "unknown"]);
        sqlite3_free(errorMessage);
        return NO;
    }
    return YES;
}

- (void)close {
    [_jsonlHandle closeFile];
    _jsonlHandle = nil;
    if (_db) {
        sqlite3_close(_db);
        _db = NULL;
    }
}

- (NSInteger)eventCount {
    if (!_db) return 0;
    sqlite3_stmt *statement = NULL;
    NSInteger count = 0;
    if (sqlite3_prepare_v2(_db, "SELECT COUNT(*) FROM events", -1, &statement, NULL) == SQLITE_OK
        && sqlite3_step(statement) == SQLITE_ROW) {
        count = sqlite3_column_int64(statement, 0);
    }
    sqlite3_finalize(statement);
    return count;
}

- (BOOL)hasEventID:(NSString *)eventID {
    if (!_db || eventID.length == 0) return NO;
    sqlite3_stmt *statement = NULL;
    BOOL found = NO;
    if (sqlite3_prepare_v2(_db, "SELECT 1 FROM events WHERE event_id = ? LIMIT 1", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, eventID.UTF8String, -1, SQLITE_TRANSIENT);
        found = sqlite3_step(statement) == SQLITE_ROW;
    }
    sqlite3_finalize(statement);
    return found;
}

- (BOOL)existingEventID:(NSString *)eventID total:(long long *)total cost:(double *)cost {
    if (!_db || eventID.length == 0) return NO;
    sqlite3_stmt *statement = NULL;
    BOOL found = NO;
    if (sqlite3_prepare_v2(_db, "SELECT total_tokens, cost_usd FROM events WHERE event_id = ? LIMIT 1", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, eventID.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) == SQLITE_ROW) {
            found = YES;
            if (total) *total = sqlite3_column_int64(statement, 0);
            if (cost) *cost = sqlite3_column_double(statement, 1);
        }
    }
    sqlite3_finalize(statement);
    return found;
}

- (BOOL)upsertEvents:(NSArray<LSBLocalEvent *> *)events error:(NSError **)error {
    if (!_db) {
        if (error) *error = LSBStoreError(@"База не открыта");
        return NO;
    }
    const char *sql =
        "INSERT INTO events (event_id, ts, tool, provider, model, session_id, session_title, project,"
        " input_tokens, output_tokens, reasoning_tokens, cache_read_tokens, cache_write_tokens,"
        " total_tokens, cost_usd, cost_source, source_path, raw_meta)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        " ON CONFLICT(event_id) DO UPDATE SET"
        " ts=excluded.ts, tool=excluded.tool, provider=excluded.provider, model=excluded.model,"
        " session_id=excluded.session_id, session_title=excluded.session_title, project=excluded.project,"
        " input_tokens=excluded.input_tokens, output_tokens=excluded.output_tokens,"
        " reasoning_tokens=excluded.reasoning_tokens, cache_read_tokens=excluded.cache_read_tokens,"
        " cache_write_tokens=excluded.cache_write_tokens, total_tokens=excluded.total_tokens,"
        " cost_usd=excluded.cost_usd, cost_source=excluded.cost_source,"
        " source_path=excluded.source_path, raw_meta=excluded.raw_meta";

    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &statement, NULL) != SQLITE_OK) {
        if (error) *error = LSBStoreError([NSString stringWithFormat:@"SQL insert: %s", sqlite3_errmsg(_db)]);
        return NO;
    }

    for (LSBLocalEvent *event in events) {
        long long existingTotal = -1;
        double existingCost = 0;
        BOOL existing = [self existingEventID:event.eventID total:&existingTotal cost:&existingCost];
        if (existing && existingTotal >= event.totalTokens && fabs(existingCost - event.costUSD) < 0.000000001) {
            continue;
        }
        sqlite3_reset(statement);
        sqlite3_clear_bindings(statement);
        sqlite3_bind_text(statement, 1, event.eventID.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970);
        sqlite3_bind_text(statement, 3, event.tool.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 4, event.provider.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 5, event.model.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 6, event.sessionID.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 7, event.sessionTitle.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 8, event.project.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(statement, 9, event.inputTokens);
        sqlite3_bind_int64(statement, 10, event.outputTokens);
        sqlite3_bind_int64(statement, 11, event.reasoningTokens);
        sqlite3_bind_int64(statement, 12, event.cacheReadTokens);
        sqlite3_bind_int64(statement, 13, event.cacheWriteTokens);
        sqlite3_bind_int64(statement, 14, event.totalTokens);
        sqlite3_bind_double(statement, 15, event.costUSD);
        sqlite3_bind_text(statement, 16, event.costSource.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 17, event.sourcePath.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 18, event.rawMeta.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) != SQLITE_DONE) {
            if (error) *error = LSBStoreError([NSString stringWithFormat:@"SQL insert: %s", sqlite3_errmsg(_db)]);
            sqlite3_finalize(statement);
            return NO;
        }

        NSDictionary *line = @{
            @"op": existing ? @"update" : @"upsert",
            @"event_id": event.eventID,
            @"ts": @(event.timestamp.timeIntervalSince1970),
            @"tool": event.tool,
            @"provider": event.provider,
            @"model": event.model,
            @"session_id": event.sessionID,
            @"title": event.sessionTitle,
            @"project": event.project,
            @"input": @(event.inputTokens),
            @"output": @(event.outputTokens),
            @"reasoning": @(event.reasoningTokens),
            @"cache_read": @(event.cacheReadTokens),
            @"cache_write": @(event.cacheWriteTokens),
            @"total": @(event.totalTokens),
            @"cost": @(event.costUSD),
            @"cost_source": event.costSource,
            @"source": event.sourcePath,
        };
        LSBAppendJSONLine(_jsonlHandle, line);
    }
    sqlite3_finalize(statement);
    return YES;
}

- (NSDate *)startOfDay:(NSDate *)date {
    return [[NSCalendar currentCalendar] startOfDayForDate:date];
}

- (NSDate *)startOfMonth:(NSDate *)date {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:date];
    components.day = 1;
    components.hour = 0;
    components.minute = 0;
    components.second = 0;
    return [calendar dateFromComponents:components];
}

- (LSBPeriodStats *)statsFrom:(NSDate *)start to:(NSDate *)end includeModels:(BOOL)includeModels {
    LSBPeriodStats *stats = [LSBPeriodStats new];
    if (!_db) return stats;

    const char *sql =
        "SELECT COALESCE(SUM(cost_usd),0), COALESCE(SUM(total_tokens),0),"
        " COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0),"
        " COALESCE(SUM(cache_read_tokens),0),"
        " COALESCE(SUM(CASE WHEN cache_read_tokens > 0 THEN 1 ELSE 0 END),0),"
        " COUNT(*), COALESCE(SUM(cache_write_tokens),0) FROM events WHERE ts >= ? AND ts <= ?";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970);
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970);
        if (sqlite3_step(statement) == SQLITE_ROW) {
            stats.spend = sqlite3_column_double(statement, 0);
            stats.totalTokens = sqlite3_column_int64(statement, 1);
            stats.promptTokens = sqlite3_column_int64(statement, 2);
            stats.completionTokens = sqlite3_column_int64(statement, 3);
            stats.cacheHits = sqlite3_column_int64(statement, 5);
            stats.requests = sqlite3_column_int64(statement, 6);
            stats.cacheReadTokens = sqlite3_column_int64(statement, 4);
            stats.cacheWriteTokens = sqlite3_column_int64(statement, 7);
        }
    }
    sqlite3_finalize(statement);

    if (includeModels) {
        NSMutableArray<LSBModelSpend *> *models = [NSMutableArray array];
        const char *modelSQL =
            "SELECT model, SUM(cost_usd), SUM(input_tokens), SUM(output_tokens),"
            " SUM(total_tokens), COUNT(*) FROM events WHERE ts >= ? AND ts <= ?"
            " GROUP BY model ORDER BY SUM(cost_usd) DESC, SUM(total_tokens) DESC";
        if (sqlite3_prepare_v2(_db, modelSQL, -1, &statement, NULL) == SQLITE_OK) {
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970);
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970);
            while (sqlite3_step(statement) == SQLITE_ROW) {
                LSBModelSpend *model = [LSBModelSpend new];
                model.model = LSBStringColumn(statement, 0);
                model.spend = sqlite3_column_double(statement, 1);
                model.promptTokens = sqlite3_column_int64(statement, 2);
                model.completionTokens = sqlite3_column_int64(statement, 3);
                model.totalTokens = sqlite3_column_int64(statement, 4);
                model.requests = sqlite3_column_int64(statement, 5);
                [models addObject:model];
            }
        }
        sqlite3_finalize(statement);
        stats.models = models;
    }
    return stats;
}

- (NSArray<LSBGroupSpend *> *)groupsBy:(NSString *)field start:(NSDate *)start end:(NSDate *)end limit:(NSInteger)limit {
    if (!_db) return @[];
    NSSet *allowed = [NSSet setWithObjects:@"tool", @"model", @"project", nil];
    if (![allowed containsObject:field]) return @[];
    NSString *sql = [NSString stringWithFormat:
        @"SELECT %@, SUM(cost_usd), SUM(total_tokens), COUNT(*) FROM events"
         " WHERE ts >= ? AND ts <= ? GROUP BY %@"
         " ORDER BY SUM(cost_usd) DESC, SUM(total_tokens) DESC LIMIT ?", field, field];
    sqlite3_stmt *statement = NULL;
    NSMutableArray<LSBGroupSpend *> *groups = [NSMutableArray array];
    if (sqlite3_prepare_v2(_db, sql.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970);
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970);
        sqlite3_bind_int64(statement, 3, limit > 0 ? limit : 50);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            LSBGroupSpend *group = [LSBGroupSpend new];
            group.name = LSBStringColumn(statement, 0);
            group.spend = sqlite3_column_double(statement, 1);
            group.tokens = sqlite3_column_int64(statement, 2);
            group.requests = sqlite3_column_int64(statement, 3);
            if (group.name.length == 0) group.name = @"unknown";
            [groups addObject:group];
        }
    }
    sqlite3_finalize(statement);
    return groups;
}

- (NSArray<LSBSessionSpend *> *)sessionsFrom:(NSDate *)start to:(NSDate *)end limit:(NSInteger)limit {
    if (!_db) return @[];
    const char *sql =
        "SELECT session_id, MAX(session_title), MAX(tool), MAX(model), MAX(project),"
        " SUM(cost_usd), SUM(total_tokens), SUM(input_tokens), SUM(output_tokens),"
        " COUNT(*), MIN(ts), MAX(ts)"
        " FROM events WHERE ts >= ? AND ts <= ? GROUP BY session_id"
        " ORDER BY MAX(ts) DESC LIMIT ?";
    sqlite3_stmt *statement = NULL;
    NSMutableArray<LSBSessionSpend *> *sessions = [NSMutableArray array];
    if (sqlite3_prepare_v2(_db, sql, -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970);
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970);
        sqlite3_bind_int64(statement, 3, limit > 0 ? limit : 100);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            LSBSessionSpend *session = [LSBSessionSpend new];
            session.sessionID = LSBStringColumn(statement, 0);
            session.title = LSBStringColumn(statement, 1);
            NSString *tool = LSBStringColumn(statement, 2);
            session.tool = tool;
            session.primaryModel = LSBStringColumn(statement, 3);
            NSString *project = LSBStringColumn(statement, 4);
            if (session.title.length == 0) session.title = project.length > 0 ? project : session.sessionID;
            session.spend = sqlite3_column_double(statement, 5);
            session.totalTokens = sqlite3_column_int64(statement, 6);
            session.promptTokens = sqlite3_column_int64(statement, 7);
            session.completionTokens = sqlite3_column_int64(statement, 8);
            session.requests = sqlite3_column_int64(statement, 9);
            session.startedAt = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(statement, 10)];
            session.lastActivity = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(statement, 11)];
            session.models = session.primaryModel.length > 0 ? @[session.primaryModel] : @[];
            if (tool.length > 0 && session.title.length == 0) session.title = tool;
            [sessions addObject:session];
        }
    }
    sqlite3_finalize(statement);
    return sessions;
}

- (LSBSummary *)summaryAt:(NSDate *)now {
    NSDate *dayStart = [self startOfDay:now];
    NSDate *weekStart = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:dayStart options:0];
    NSDate *monthStart = [self startOfMonth:now];

    LSBSummary *summary = [LSBSummary new];
    summary.today = [self statsFrom:dayStart to:now includeModels:YES];
    summary.week = [self statsFrom:weekStart to:now includeModels:NO];
    summary.month = [self statsFrom:monthStart to:now includeModels:NO];
    summary.sessions = [self sessionsFrom:dayStart to:now limit:50];
    summary.tools = [self groupsBy:@"tool" start:dayStart end:now limit:20];
    summary.projects = [self groupsBy:@"project" start:dayStart end:now limit:20];
    summary.generatedAt = now;
    summary.logCount = [self eventCount];
    return summary;
}

- (NSArray<NSDictionary *> *)dailySeriesFrom:(NSDate *)start to:(NSDate *)end {
    if (!_db) return @[];
    NSDate *startDay = [self startOfDay:start];
    NSDate *endDay = [self startOfDay:end];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd";

    NSMutableDictionary<NSString *, NSMutableDictionary *> *days = [NSMutableDictionary dictionary];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *cursor = startDay;
    while ([cursor compare:endDay] != NSOrderedDescending) {
        NSString *key = [formatter stringFromDate:cursor];
        days[key] = [@{@"date": key, @"spend": @0, @"tokens": @0, @"requests": @0, @"byTool": [NSMutableDictionary dictionary], @"byModel": [NSMutableDictionary dictionary]} mutableCopy];
        cursor = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:cursor options:0];
    }

    const char *sql =
        "SELECT date(ts,'unixepoch','localtime') AS day, tool, SUM(cost_usd), SUM(total_tokens), COUNT(*)"
        " FROM events WHERE ts >= ? AND ts <= ? GROUP BY day, tool ORDER BY day ASC";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_double(statement, 1, startDay.timeIntervalSince1970);
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            NSString *day = LSBStringColumn(statement, 0);
            NSString *tool = LSBStringColumn(statement, 1);
            NSMutableDictionary *entry = days[day];
            if (!entry) continue;
            entry[@"spend"] = @([entry[@"spend"] doubleValue] + sqlite3_column_double(statement, 2));
            entry[@"tokens"] = @([entry[@"tokens"] longLongValue] + sqlite3_column_int64(statement, 3));
            entry[@"requests"] = @([entry[@"requests"] longLongValue] + sqlite3_column_int64(statement, 4));
            NSMutableDictionary *byTool = entry[@"byTool"];
            byTool[tool.length > 0 ? tool : @"unknown"] = @([byTool[tool.length > 0 ? tool : @"unknown"] longLongValue] + sqlite3_column_int64(statement, 3));
        }
    }
    sqlite3_finalize(statement);

    const char *modelSQL =
        "SELECT date(ts,'unixepoch','localtime') AS day, model, SUM(total_tokens)"
        " FROM events WHERE ts >= ? AND ts <= ? GROUP BY day, model ORDER BY day ASC";
    if (sqlite3_prepare_v2(_db, modelSQL, -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_double(statement, 1, startDay.timeIntervalSince1970);
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            NSString *day = LSBStringColumn(statement, 0);
            NSString *model = LSBStringColumn(statement, 1);
            NSMutableDictionary *entry = days[day];
            if (!entry) continue;
            NSMutableDictionary *byModel = entry[@"byModel"];
            NSString *key = model.length > 0 ? model : @"unknown";
            byModel[key] = @([byModel[key] longLongValue] + sqlite3_column_int64(statement, 2));
        }
    }
    sqlite3_finalize(statement);

    NSMutableArray *result = [NSMutableArray array];
    cursor = startDay;
    while ([cursor compare:endDay] != NSOrderedDescending) {
        NSString *key = [formatter stringFromDate:cursor];
        NSDictionary *entry = days[key];
        [result addObject:@{
            @"date": key,
            @"spend": entry[@"spend"] ?: @0,
            @"tokens": entry[@"tokens"] ?: @0,
            @"requests": entry[@"requests"] ?: @0,
            @"byTool": entry[@"byTool"] ?: @{},
            @"byModel": entry[@"byModel"] ?: @{},
        }];
        cursor = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:cursor options:0];
    }
    return result;
}

- (NSArray<NSDictionary *> *)heatmapFrom:(NSDate *)start to:(NSDate *)end {
    NSArray<NSDictionary *> *series = [self dailySeriesFrom:start to:end];
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *day in series) {
        [result addObject:@{
            @"date": day[@"date"],
            @"tokens": day[@"tokens"],
            @"spend": day[@"spend"],
            @"requests": day[@"requests"],
        }];
    }
    return result;
}

- (NSDictionary *)dashboardSnapshotForPeriod:(NSString *)period now:(NSDate *)now {
    NSDate *dayStart = [self startOfDay:now];
    NSDate *weekStart = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:dayStart options:0];
    NSDate *monthStart = [self startOfMonth:now];
    NSDate *start = monthStart;
    if ([period isEqualToString:@"today"]) start = dayStart;
    else if ([period isEqualToString:@"week"]) start = weekStart;
    else if ([period isEqualToString:@"all"]) start = [NSDate dateWithTimeIntervalSince1970:0];

    LSBPeriodStats *stats = [self statsFrom:start to:now includeModels:NO];
    NSArray<LSBGroupSpend *> *tools = [self groupsBy:@"tool" start:start end:now limit:30];
    NSArray<LSBGroupSpend *> *models = [self groupsBy:@"model" start:start end:now limit:30];
    NSArray<LSBGroupSpend *> *projects = [self groupsBy:@"project" start:start end:now limit:30];
    NSArray<LSBSessionSpend *> *sessions = [self sessionsFrom:start to:now limit:100];

    NSMutableArray *toolsJSON = [NSMutableArray array];
    for (LSBGroupSpend *group in tools) {
        [toolsJSON addObject:@{@"name": group.name, @"spend": @(group.spend), @"tokens": @(group.tokens), @"requests": @(group.requests)}];
    }
    NSMutableArray *modelsJSON = [NSMutableArray array];
    for (LSBGroupSpend *group in models) {
        [modelsJSON addObject:@{@"name": group.name, @"spend": @(group.spend), @"tokens": @(group.tokens), @"requests": @(group.requests)}];
    }
    NSMutableArray *projectsJSON = [NSMutableArray array];
    for (LSBGroupSpend *group in projects) {
        [projectsJSON addObject:@{@"name": group.name, @"spend": @(group.spend), @"tokens": @(group.tokens), @"requests": @(group.requests)}];
    }
    NSMutableArray *sessionsJSON = [NSMutableArray array];
    for (LSBSessionSpend *session in sessions) {
        [sessionsJSON addObject:@{
            @"id": session.sessionID,
            @"title": session.title,
            @"tool": session.tool,
            @"model": session.primaryModel,
            @"spend": @(session.spend),
            @"tokens": @(session.totalTokens),
            @"requests": @(session.requests),
            @"lastAt": @(session.lastActivity.timeIntervalSince1970),
        }];
    }

    NSDate *seriesStart = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay value:-29 toDate:dayStart options:0];
    NSDate *heatmapStart = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay value:-364 toDate:dayStart options:0];

    NSMutableArray *unpriced = [NSMutableArray array];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_db, "SELECT DISTINCT model FROM events WHERE ts >= ? AND ts <= ? AND cost_source = 'unpriced'", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970);
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            NSString *model = LSBStringColumn(statement, 0);
            if (model.length > 0) [unpriced addObject:model];
        }
    }
    sqlite3_finalize(statement);

    NSDictionary *todayStats = @{@"spend": @([self statsFrom:dayStart to:now includeModels:NO].spend)};
    NSDictionary *weekStats = @{@"spend": @([self statsFrom:weekStart to:now includeModels:NO].spend)};
    NSDictionary *monthStats = @{@"spend": @([self statsFrom:monthStart to:now includeModels:NO].spend)};

    return @{
        @"generatedAt": @([[NSDate date] timeIntervalSince1970]),
        @"period": period ?: @"month",
        @"totals": @{
            @"spend": @(stats.spend),
            @"tokens": @(stats.totalTokens),
            @"input": @(stats.promptTokens),
            @"output": @(stats.completionTokens),
            @"requests": @(stats.requests),
            @"cacheHits": @(stats.cacheHits),
            @"cacheRead": @(stats.cacheReadTokens),
            @"cacheWrite": @(stats.cacheWriteTokens),
        },
        @"scanInterval": @([LSBSettings scanInterval]),
        @"budgets": @{
            @"daily": @([LSBSettings dailyBudget]),
            @"weekly": @([LSBSettings weeklyBudget]),
            @"monthly": @([LSBSettings monthlyBudget]),
            @"todaySpend": todayStats[@"spend"],
            @"weekSpend": weekStats[@"spend"],
            @"monthSpend": monthStats[@"spend"],
        },
        @"series": [self dailySeriesFrom:seriesStart to:now],
        @"heatmap": [self heatmapFrom:heatmapStart to:now],
        @"tools": toolsJSON,
        @"models": modelsJSON,
        @"projects": projectsJSON,
        @"sessions": sessionsJSON,
        @"unpriced": unpriced,
    };
}

- (BOOL)fileUnchanged:(NSString *)path mtime:(double)mtime size:(long long)size {
    if (!_db) return NO;
    sqlite3_stmt *statement = NULL;
    BOOL unchanged = NO;
    if (sqlite3_prepare_v2(_db, "SELECT mtime, size FROM files WHERE path = ?", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, path.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) == SQLITE_ROW) {
            unchanged = fabs(sqlite3_column_double(statement, 0) - mtime) < 0.001
                && sqlite3_column_int64(statement, 1) == size;
        }
    }
    sqlite3_finalize(statement);
    return unchanged;
}

- (void)recordFile:(NSString *)path mtime:(double)mtime size:(long long)size {
    if (!_db) return;
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_db, "INSERT INTO files (path, mtime, size) VALUES (?, ?, ?) ON CONFLICT(path) DO UPDATE SET mtime=excluded.mtime, size=excluded.size", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, path.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(statement, 2, mtime);
        sqlite3_bind_int64(statement, 3, size);
        sqlite3_step(statement);
    }
    sqlite3_finalize(statement);
}

@end
