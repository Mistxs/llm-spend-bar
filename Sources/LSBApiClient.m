#import "LSBApiClient.h"
#import "LSBModels+Internal.h"
#import "LSBSettings.h"

static NSString *const LSBApiErrorDomain = @"dev.llmspendbar.api";

static NSError *LSBAPIError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:LSBApiErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSDateFormatter *LSBApiDateFormatter(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return formatter;
}

static NSDate *LSBStartOfMonth(NSDate *date, NSCalendar *calendar) {
    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:date];
    components.day = 1;
    components.hour = 0;
    components.minute = 0;
    components.second = 0;
    components.nanosecond = 0;
    return [calendar dateFromComponents:components];
}

static NSURL *LSBURLWithPath(NSURL *baseURL, NSString *path, NSArray<NSURLQueryItem *> *queryItems) {
    NSString *root = baseURL.absoluteString;
    if (![root hasSuffix:@"/"]) root = [root stringByAppendingString:@"/"];
    NSURL *url = [NSURL URLWithString:path relativeToURL:[NSURL URLWithString:root]];
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
    components.queryItems = queryItems;
    return components.URL;
}

@implementation LSBApiClient

- (instancetype)initWithBaseURL:(NSURL *)baseURL apiKey:(NSString *)apiKey {
    self = [super init];
    if (self) {
        _baseURL = baseURL;
        _apiKey = [apiKey copy] ?: @"";
    }
    return self;
}

#pragma mark - HTTP

- (nullable NSData *)GET:(NSString *)path
              queryItems:(NSArray<NSURLQueryItem *> *)queryItems
                  apiKey:(nullable NSString *)apiKey
                 timeout:(NSTimeInterval)timeout
                   error:(NSError **)error
              statusCode:(NSInteger *)statusCode {
    NSURL *url = LSBURLWithPath(self.baseURL, path, queryItems);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = timeout;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (apiKey.length > 0) {
        [request setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
    }

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = timeout;
    configuration.timeoutIntervalForResource = timeout;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *result = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *transportError = nil;

    [[session dataTaskWithRequest:request
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *requestError) {
        result = data;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse *)response;
        }
        transportError = requestError;
        dispatch_semaphore_signal(semaphore);
    }] resume];

    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 2.0) * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(semaphore, deadline);
    [session invalidateAndCancel];

    if (waitResult != 0) {
        if (error) *error = LSBAPIError(1, @"Таймаут подключения к LiteLLM");
        return nil;
    }

    if (statusCode) *statusCode = httpResponse ? httpResponse.statusCode : 0;

    if (transportError) {
        NSString *message = @"LiteLLM не запущен или недоступен";
        if ([transportError.domain isEqualToString:NSURLErrorDomain]) {
            switch (transportError.code) {
                case NSURLErrorCannotConnectToHost:
                case NSURLErrorCannotFindHost:
                case NSURLErrorNetworkConnectionLost:
                    message = @"LiteLLM не запущен или недоступен";
                    break;
                case NSURLErrorTimedOut:
                    message = @"Таймаут подключения к LiteLLM";
                    break;
                default:
                    message = transportError.localizedDescription ?: message;
                    break;
            }
        }
        if (error) *error = LSBAPIError(2, message);
        return nil;
    }

    return result;
}

- (BOOL)checkHealthWithError:(NSError **)error {
    if (error) *error = nil;
    if (self.baseURL.isFileURL || [[self.baseURL scheme] isEqualToString:@"demo"]) {
        return YES;
    }

    NSInteger status = 0;
    NSError *requestError = nil;
    NSData *data = [self GET:@"health/liveliness" queryItems:@[] apiKey:self.apiKey timeout:2.5 error:&requestError statusCode:&status];
    if (data && status == 200) return YES;

    requestError = nil;
    data = [self GET:@"health" queryItems:@[] apiKey:self.apiKey timeout:2.5 error:&requestError statusCode:&status];
    if (data && status == 200) return YES;

    if (requestError) {
        if (error) *error = requestError;
    } else {
        if (error) *error = LSBAPIError(3, [NSString stringWithFormat:@"LiteLLM вернул HTTP %ld", (long)status]);
    }
    return NO;
}

#pragma mark - Summary

- (LSBSummary *)fetchSummaryWithError:(NSError **)error {
    if (error) *error = nil;
    if (LSBSettings.demoMode || [[self.baseURL scheme] isEqualToString:@"demo"]) {
        LSBSummary *summary = [LSBSummary demoSummary];
        summary.generatedAt = [NSDate date];
        return summary;
    }

    if (self.apiKey.length == 0) {
        if (error) *error = LSBAPIError(4, @"Не задан master key LiteLLM. Откройте «Настройки…».");
        return nil;
    }

    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *dayStart = [calendar startOfDayForDate:now];
    NSDate *weekStart = [calendar dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:dayStart options:0];
    NSDate *monthStart = LSBStartOfMonth(now, calendar);
    NSDate *fetchStart = [monthStart compare:weekStart] == NSOrderedAscending ? monthStart : weekStart;

    NSDateFormatter *formatter = LSBApiDateFormatter();
    NSString *start = [formatter stringFromDate:fetchStart];
    NSString *end = [formatter stringFromDate:now];

    const NSInteger pageSize = 1000;
    const NSInteger maxPages = 10;
    BOOL truncated = NO;
    NSMutableArray<LSBSpendLog *> *logs = [NSMutableArray array];

    for (NSInteger page = 1; page <= maxPages; page++) {
        NSArray<NSURLQueryItem *> *query = @[
            [NSURLQueryItem queryItemWithName:@"start_date" value:start],
            [NSURLQueryItem queryItemWithName:@"end_date" value:end],
            [NSURLQueryItem queryItemWithName:@"page" value:[NSString stringWithFormat:@"%ld", (long)page]],
            [NSURLQueryItem queryItemWithName:@"page_size" value:[NSString stringWithFormat:@"%ld", (long)pageSize]],
        ];

        NSInteger status = 0;
        NSError *requestError = nil;
        NSData *data = [self GET:@"spend/logs/v2" queryItems:query apiKey:self.apiKey timeout:12.0 error:&requestError statusCode:&status];

        if (status == 404 && page == 1) {
            // Старый LiteLLM: /spend/logs?summarize=false
            NSArray<NSURLQueryItem *> *legacyQuery = @[
                [NSURLQueryItem queryItemWithName:@"start_date" value:start],
                [NSURLQueryItem queryItemWithName:@"end_date" value:end],
                [NSURLQueryItem queryItemWithName:@"summarize" value:@"false"],
            ];
            requestError = nil;
            data = [self GET:@"spend/logs" queryItems:legacyQuery apiKey:self.apiKey timeout:20.0 error:&requestError statusCode:&status];
            if (!data) {
                if (error) *error = requestError;
                return nil;
            }
            [self appendLogsFromJSONData:data toArray:logs];
            break;
        }

        if (!data) {
            if (error) *error = requestError;
            return nil;
        }

        if (status == 401 || status == 403) {
            if (error) *error = LSBAPIError(5, [NSString stringWithFormat:@"LiteLLM отклонил ключ (HTTP %ld)", (long)status]);
            return nil;
        }
        if (status < 200 || status >= 300) {
            if (error) *error = LSBAPIError(6, [NSString stringWithFormat:@"LiteLLM вернул HTTP %ld", (long)status]);
            return nil;
        }

        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
            if (error) *error = LSBAPIError(7, @"Некорректный ответ /spend/logs/v2");
            return nil;
        }

        NSDictionary *dictionary = (NSDictionary *)json;
        NSArray *rows = dictionary[@"data"];
        if (![rows isKindOfClass:[NSArray class]]) rows = @[];

        for (NSDictionary *row in rows) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            LSBSpendLog *log = [LSBSpendLog logFromDictionary:row];
            if (log) [logs addObject:log];
        }

        NSNumber *totalPages = [dictionary[@"total_pages"] isKindOfClass:[NSNumber class]] ? dictionary[@"total_pages"] : nil;
        BOOL capped = [dictionary[@"total_is_capped"] isKindOfClass:[NSNumber class]]
            ? [dictionary[@"total_is_capped"] boolValue]
            : NO;

        if (rows.count == 0) break;
        if (rows.count < (NSUInteger)pageSize) break;
        if (totalPages && page >= totalPages.integerValue) {
            if (capped) truncated = YES;
            break;
        }
        if (page == maxPages) {
            truncated = YES;
            break;
        }
    }

    return [LSBSummaryBuilder summaryFromLogs:logs
                                     dayStart:dayStart
                                    weekStart:weekStart
                                   monthStart:monthStart
                                          now:now
                                    truncated:truncated];
}

- (void)appendLogsFromJSONData:(NSData *)data toArray:(NSMutableArray<LSBSpendLog *> *)logs {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSArray *rows = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        rows = json;
    } else if ([json isKindOfClass:[NSDictionary class]]) {
        rows = ((NSDictionary *)json)[@"data"];
    }
    if (![rows isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *row in rows) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        LSBSpendLog *log = [LSBSpendLog logFromDictionary:row];
        if (log) [logs addObject:log];
    }
}

@end
