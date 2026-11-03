#import "LSBSettings.h"
#import <Security/Security.h>

NSString *const LSBDisplayModeBars = @"bars";
NSString *const LSBDisplayModeDollars = @"dollars";
NSString *const LSBDisplayModeTokens = @"tokens";

static NSString *const LSBDefaultsBaseURL = @"baseURL";
static NSString *const LSBDefaultsDailyBudget = @"dailyBudget";
static NSString *const LSBDefaultsWeeklyBudget = @"weeklyBudget";
static NSString *const LSBDefaultsMonthlyBudget = @"monthlyBudget";
static NSString *const LSBDefaultsRefreshInterval = @"refreshInterval";
static NSString *const LSBDefaultsDisplayMode = @"displayMode";
static NSString *const LSBDefaultsConfigPath = @"configPath";
static NSString *const LSBDefaultsDemoMode = @"demoMode";

static NSString *const LSBKeychainService = @"dev.llmspendbar";
static NSString *const LSBKeychainAccount = @"litellm-master-key";

static NSError *LSBKeychainError(OSStatus status) {
    NSString *message = [NSString stringWithFormat:@"Keychain вернул ошибку %d", (int)status];
    return [NSError errorWithDomain:@"dev.llmspendbar.keychain"
                               code:status
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation LSBSettings

+ (void)registerDefaults {
    NSDictionary *defaults = @{
        LSBDefaultsBaseURL: @"http://127.0.0.1:4000",
        LSBDefaultsDailyBudget: @10.0,
        LSBDefaultsWeeklyBudget: @50.0,
        LSBDefaultsMonthlyBudget: @200.0,
        LSBDefaultsRefreshInterval: @30.0,
        LSBDefaultsDisplayMode: LSBDisplayModeBars,
        LSBDefaultsConfigPath: [@"~/llm-spend-bar/litellm/config.yaml" stringByExpandingTildeInPath],
        LSBDefaultsDemoMode: @NO,
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

+ (NSString *)baseURLString {
    const char *override = getenv("LSB_BASE_URL");
    if (override != NULL) return [NSString stringWithUTF8String:override];
    return [[NSUserDefaults standardUserDefaults] stringForKey:LSBDefaultsBaseURL] ?: @"http://127.0.0.1:4000";
}

+ (void)setBaseURLString:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:LSBDefaultsBaseURL];
}

+ (NSURL *)baseURL {
    if (self.demoMode) return [NSURL URLWithString:@"demo://summary"];
    NSString *raw = self.baseURLString;
    if (raw.length == 0) raw = @"http://127.0.0.1:4000";
    if (![raw hasPrefix:@"http://"] && ![raw hasPrefix:@"https://"]) {
        raw = [@"http://" stringByAppendingString:raw];
    }
    while ([raw hasSuffix:@"/"]) {
        raw = [raw substringToIndex:raw.length - 1];
    }
    return [NSURL URLWithString:raw];
}

+ (NSString *)masterKey {
    const char *override = getenv("LSB_MASTER_KEY");
    if (override != NULL) return [NSString stringWithUTF8String:override];

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: LSBKeychainService,
        (__bridge id)kSecAttrAccount: LSBKeychainAccount,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)setMasterKey:(NSString *)key error:(NSError **)error {
    if (key.length == 0) return [self deleteMasterKey];

    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: LSBKeychainService,
        (__bridge id)kSecAttrAccount: LSBKeychainAccount,
    };

    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    if (status == errSecSuccess) {
        NSDictionary *attributes = @{(__bridge id)kSecValueData: data};
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    } else {
        NSMutableDictionary *item = [query mutableCopy];
        item[(__bridge id)kSecValueData] = data;
        item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }

    if (status != errSecSuccess) {
        if (error) *error = LSBKeychainError(status);
        return NO;
    }
    return YES;
}

+ (BOOL)deleteMasterKey {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: LSBKeychainService,
        (__bridge id)kSecAttrAccount: LSBKeychainAccount,
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}

+ (double)dailyBudget {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:LSBDefaultsDailyBudget];
}

+ (double)weeklyBudget {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:LSBDefaultsWeeklyBudget];
}

+ (double)monthlyBudget {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:LSBDefaultsMonthlyBudget];
}

+ (void)setDailyBudget:(double)value {
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:LSBDefaultsDailyBudget];
}

+ (void)setWeeklyBudget:(double)value {
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:LSBDefaultsWeeklyBudget];
}

+ (void)setMonthlyBudget:(double)value {
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:LSBDefaultsMonthlyBudget];
}

+ (NSTimeInterval)refreshInterval {
    double value = [[NSUserDefaults standardUserDefaults] doubleForKey:LSBDefaultsRefreshInterval];
    return value > 0 ? value : 30.0;
}

+ (void)setRefreshInterval:(NSTimeInterval)value {
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:LSBDefaultsRefreshInterval];
}

+ (NSString *)displayMode {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:LSBDefaultsDisplayMode];
    if ([value isEqualToString:LSBDisplayModeDollars] || [value isEqualToString:LSBDisplayModeTokens]) {
        return value;
    }
    return LSBDisplayModeBars;
}

+ (void)setDisplayMode:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:LSBDefaultsDisplayMode];
}

+ (NSString *)configPath {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:LSBDefaultsConfigPath];
    return value.length > 0 ? value : [@"~/llm-spend-bar/litellm/config.yaml" stringByExpandingTildeInPath];
}

+ (void)setConfigPath:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:LSBDefaultsConfigPath];
}

+ (BOOL)demoMode {
    if (getenv("LSB_DEMO") != NULL) return YES;
    return [[NSUserDefaults standardUserDefaults] boolForKey:LSBDefaultsDemoMode];
}

+ (void)setDemoMode:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:LSBDefaultsDemoMode];
}

@end
