#import <Cocoa/Cocoa.h>

#import "LSBApiClient.h"
#import "LSBFormat.h"
#import "LSBMenuBarIcon.h"
#import "LSBModels+Internal.h"
#import "LSBSettings.h"

static void LSBPrintPeriod(NSString *title, LSBPeriodStats *stats, double budget) {
    NSString *budgetText = budget > 0
        ? [NSString stringWithFormat:@"%@ / %@ (%@)", [LSBFormat usd:stats.spend], [LSBFormat usd:budget], [LSBFormat percent:stats.spend / budget]]
        : [LSBFormat usd:stats.spend];
    printf("%-8s %s · %s токенов · %lld запросов · кэш %lld\n",
           title.UTF8String,
           budgetText.UTF8String,
           [LSBFormat tokens:stats.totalTokens].UTF8String,
           stats.requests,
           stats.cacheHits);
}

void LSBProbeRun(void) {
    @autoreleasepool {
        [LSBSettings registerDefaults];

        printf("base URL: %s\n", LSBSettings.baseURL.absoluteString.UTF8String ?: "(none)");
        NSString *key = LSBSettings.masterKey;
        const char *keySource = getenv("LSB_MASTER_KEY") != NULL ? "set (env)" : "set (Keychain)";
        printf("master key: %s\n", key.length > 0 ? keySource : "missing");
        printf("demo: %s\n", LSBSettings.demoMode ? "yes" : "no");

        NSURL *baseURL = LSBSettings.baseURL;
        if (!baseURL) baseURL = [NSURL URLWithString:@"http://127.0.0.1:4000"];
        LSBApiClient *client = [[LSBApiClient alloc] initWithBaseURL:baseURL apiKey:key];

        NSError *error = nil;
        BOOL healthy = [client checkHealthWithError:&error];
        printf("health: %s\n", healthy ? "ok" : (error.localizedDescription.UTF8String ?: "failed"));

        error = nil;
        LSBSummary *summary = [client fetchSummaryWithError:&error];
        if (!summary) {
            printf("summary: %s\n", error.localizedDescription.UTF8String ?: "failed");
            return;
        }

        printf("\nLLM Spend — LiteLLM\n");
        LSBPrintPeriod(@"Сегодня", summary.today, LSBSettings.dailyBudget);
        LSBPrintPeriod(@"Неделя", summary.week, LSBSettings.weeklyBudget);
        LSBPrintPeriod(@"Месяц", summary.month, LSBSettings.monthlyBudget);
        printf("логов в выборке: %ld%s\n", (long)summary.logCount, summary.truncated ? " (обрезано)" : "");

        if (summary.sessions.count > 0) {
            printf("\nСессии сегодня:\n");
            for (LSBSessionSpend *session in summary.sessions) {
                printf("  %-32s %8s  %8s tok  %3lld запр.  %s\n",
                       [LSBFormat truncate:session.title width:32].UTF8String,
                       [LSBFormat usd:session.spend].UTF8String,
                       [LSBFormat tokens:session.totalTokens].UTF8String,
                       session.requests,
                       session.sessionID.UTF8String);
            }
        }

        if (summary.today.models.count > 0) {
            printf("\nМодели сегодня:\n");
            for (LSBModelSpend *model in summary.today.models) {
                printf("  %-28s %8s  %8s tok  %3lld запр.\n",
                       model.model.UTF8String,
                       [LSBFormat usd:model.spend].UTF8String,
                       [LSBFormat tokens:model.totalTokens].UTF8String,
                       model.requests);
            }
        }
    }
}

void LSBSelfTestRun(NSString *path) {
    @autoreleasepool {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) {
            fprintf(stderr, "self-test: не удалось прочитать %s\n", path.UTF8String);
            exit(1);
        }

        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *rows = nil;
        if ([json isKindOfClass:[NSArray class]]) {
            rows = json;
        } else if ([json isKindOfClass:[NSDictionary class]]) {
            rows = ((NSDictionary *)json)[@"data"];
        }
        if (![rows isKindOfClass:[NSArray class]]) {
            fprintf(stderr, "self-test: ожидался массив или объект с data[]\n");
            exit(1);
        }

        NSMutableArray<LSBSpendLog *> *logs = [NSMutableArray array];
        for (NSDictionary *row in rows) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            LSBSpendLog *log = [LSBSpendLog logFromDictionary:row];
            if (log) [logs addObject:log];
        }

        NSDate *now = [NSDate date];
        for (LSBSpendLog *log in logs) {
            if ([log.startedAt compare:now] == NSOrderedDescending) now = log.startedAt;
        }
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDate *dayStart = [calendar startOfDayForDate:now];
        NSDate *weekStart = [calendar dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:dayStart options:0];
        NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:now];
        components.day = 1;
        components.hour = 0;
        components.minute = 0;
        components.second = 0;
        NSDate *monthStart = [calendar dateFromComponents:components];

        LSBSummary *summary = [LSBSummaryBuilder summaryFromLogs:logs
                                                        dayStart:dayStart
                                                       weekStart:weekStart
                                                      monthStart:monthStart
                                                             now:now
                                                       truncated:NO];

        printf("self-test: parsed %ld/%ld rows, sessions=%ld, today=$%.4f, week=$%.4f, month=$%.4f\n",
               (long)logs.count,
               (long)rows.count,
               (long)summary.sessions.count,
               summary.today.spend,
               summary.week.spend,
               summary.month.spend);

        if (logs.count == 0 || summary.sessions.count == 0 || summary.today.spend <= 0) {
            fprintf(stderr, "self-test: FAILED\n");
            exit(1);
        }

        printf("self-test: OK\n");
    }
}

void LSBPreviewRun(NSString *path) {
    @autoreleasepool {
        NSArray<NSNumber *> *fractions = @[@0.35, @0.62, @0.91];
        NSSize canvas = NSMakeSize(276, 216);
        NSImage *image = [NSImage imageWithSize:canvas
                                        flipped:NO
                                 drawingHandler:^BOOL(NSRect rect) {
            [[NSColor colorWithCalibratedWhite:0.12 alpha:1.0] setFill];
            NSRectFill(rect);
            NSImage *icon = [LSBMenuBarIcon imageWithFractions:fractions error:NO];
            [icon drawInRect:NSMakeRect(24, 24, 228, 168)
                    fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver
                    fraction:1.0];
            return YES;
        }];

        NSData *tiff = [image TIFFRepresentation];
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        BOOL ok = [png writeToFile:path atomically:YES];
        printf("icon preview: %s (%s)\n", ok ? "ok" : "failed", path.UTF8String);
    }
}
