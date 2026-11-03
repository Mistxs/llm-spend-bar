#import <Foundation/Foundation.h>

#import "LSBCollector.h"
#import "LSBFormat.h"
#import "LSBModels.h"
#import "LSBSettings.h"
#import "LSBStore.h"

static void LSBPrintLocalPeriod(NSString *title, LSBPeriodStats *stats) {
    printf("%-8s %10s  %10s tok  %6lld запросов\n",
           title.UTF8String,
           [LSBFormat usd:stats.spend].UTF8String,
           [LSBFormat tokens:stats.totalTokens].UTF8String,
           stats.requests);
}

void LSBScanRun(BOOL printSummary) {
    @autoreleasepool {
        [LSBSettings registerDefaults];
        LSBStore *store = [[LSBStore alloc] initWithDirectory:[LSBSettings dataDirectory]];
        NSError *error = nil;
        if (![store open:&error]) {
            fprintf(stderr, "store: %s\n", error.localizedDescription.UTF8String);
            return;
        }

        LSBCollector *collector = [[LSBCollector alloc] initWithStore:store];
        LSBScanResult *result = [collector scanWithError:&error];
        printf("scan: found=%ld written=%ld warnings=%ld\n",
               (long)result.eventsFound,
               (long)result.eventsWritten,
               (long)result.warnings.count);
        for (NSString *warning in result.warnings) {
            printf("  warning: %s\n", warning.UTF8String);
        }
        if (error) {
            printf("  error: %s\n", error.localizedDescription.UTF8String);
        }

        if (printSummary) {
            LSBSummary *summary = [store summaryAt:[NSDate date]];
            printf("\nLLM Spend — локальные логи\n");
            LSBPrintLocalPeriod(@"Сегодня", summary.today);
            LSBPrintLocalPeriod(@"Неделя", summary.week);
            LSBPrintLocalPeriod(@"Месяц", summary.month);
            printf("событий в базе: %ld\n", (long)summary.logCount);

            if (summary.tools.count > 0) {
                printf("\nИнструменты сегодня:\n");
                for (LSBGroupSpend *group in summary.tools) {
                    printf("  %-24s %10s  %10s tok  %6lld\n",
                           group.name.UTF8String,
                           [LSBFormat usd:group.spend].UTF8String,
                           [LSBFormat tokens:group.tokens].UTF8String,
                           group.requests);
                }
            }
            if (summary.today.models.count > 0) {
                printf("\nМодели сегодня:\n");
                for (LSBModelSpend *model in summary.today.models) {
                    printf("  %-28s %10s  %10s tok  %6lld\n",
                           model.model.UTF8String,
                           [LSBFormat usd:model.spend].UTF8String,
                           [LSBFormat tokens:model.totalTokens].UTF8String,
                           model.requests);
                }
            }
            if (summary.projects.count > 0) {
                printf("\nПроекты сегодня:\n");
                for (LSBGroupSpend *group in summary.projects) {
                    printf("  %-28s %10s  %10s tok  %6lld\n",
                           group.name.UTF8String,
                           [LSBFormat usd:group.spend].UTF8String,
                           [LSBFormat tokens:group.tokens].UTF8String,
                           group.requests);
                }
            }
            if (summary.sessions.count > 0) {
                printf("\nСессии сегодня:\n");
                NSInteger limit = MIN((NSInteger)summary.sessions.count, 10);
                for (NSInteger index = 0; index < limit; index++) {
                    LSBSessionSpend *session = summary.sessions[(NSUInteger)index];
                    printf("  %-36s %-10s %10s  %10s tok  %6lld\n",
                           [LSBFormat truncate:session.title width:36].UTF8String,
                           session.tool.UTF8String,
                           [LSBFormat usd:session.spend].UTF8String,
                           [LSBFormat tokens:session.totalTokens].UTF8String,
                           session.requests);
                }
            }
        }
        [store close];
    }
}

void LSBDashboardJSONRun(NSString *path) {
    @autoreleasepool {
        [LSBSettings registerDefaults];
        LSBStore *store = [[LSBStore alloc] initWithDirectory:[LSBSettings dataDirectory]];
        NSError *error = nil;
        if (![store open:&error]) {
            fprintf(stderr, "store: %s\n", error.localizedDescription.UTF8String);
            return;
        }
        LSBCollector *collector = [[LSBCollector alloc] initWithStore:store];
        [collector scanWithError:&error];
        NSDictionary *snapshot = [store dashboardSnapshotForPeriod:@"month" now:[NSDate date]];
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:&error];
        if (!data) {
            fprintf(stderr, "json: %s\n", error.localizedDescription.UTF8String);
        } else {
            [data writeToFile:path atomically:YES];
            printf("dashboard json: %s (%lu bytes)\n", path.UTF8String, (unsigned long)data.length);
        }
        [store close];
    }
}
