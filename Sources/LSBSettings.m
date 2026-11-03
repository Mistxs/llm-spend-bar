#import "LSBSettings.h"

NSString *const LSBDisplayModeBars = @"bars";
NSString *const LSBDisplayModeDollars = @"dollars";
NSString *const LSBDisplayModeTokens = @"tokens";

static NSString *const LSBDefaultsDailyBudget = @"dailyBudget";
static NSString *const LSBDefaultsWeeklyBudget = @"weeklyBudget";
static NSString *const LSBDefaultsMonthlyBudget = @"monthlyBudget";
static NSString *const LSBDefaultsDisplayMode = @"displayMode";
static NSString *const LSBDefaultsScanInterval = @"scanInterval";
static NSString *const LSBDefaultsClaudePath = @"claudeProjectsPath";
static NSString *const LSBDefaultsCodexPath = @"codexSessionsPath";
static NSString *const LSBDefaultsOpenCodePath = @"opencodeDBPath";
static NSString *const LSBDefaultsPricingPath = @"pricingOverridePath";
static NSString *const LSBDefaultsSubscriptionPrefix = @"subscription.";

@implementation LSBSettings

+ (void)registerDefaults {
    NSDictionary *defaults = @{
        LSBDefaultsDailyBudget: @10.0,
        LSBDefaultsWeeklyBudget: @50.0,
        LSBDefaultsMonthlyBudget: @200.0,
        LSBDefaultsDisplayMode: LSBDisplayModeBars,
        LSBDefaultsScanInterval: @60.0,
        LSBDefaultsClaudePath: [@"~/.claude/projects" stringByExpandingTildeInPath],
        LSBDefaultsCodexPath: [@"~/.codex/sessions" stringByExpandingTildeInPath],
        LSBDefaultsOpenCodePath: [@"~/.local/share/opencode/opencode.db" stringByExpandingTildeInPath],
        LSBDefaultsPricingPath: [@"~/Library/Application Support/LLM Spend Bar/pricing.json" stringByExpandingTildeInPath],
        @"subscription.opencode": @0.0,
        @"subscription.claude": @0.0,
        @"subscription.codex": @0.0,
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
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

+ (NSString *)dataDirectory {
    const char *override = getenv("LSB_DATA_DIR");
    if (override != NULL) return [NSString stringWithUTF8String:override];
    return [@"~/Library/Application Support/LLM Spend Bar" stringByExpandingTildeInPath];
}

+ (NSTimeInterval)scanInterval {
    double value = [[NSUserDefaults standardUserDefaults] doubleForKey:LSBDefaultsScanInterval];
    return value >= 10 ? value : 60.0;
}

+ (void)setScanInterval:(NSTimeInterval)value {
    [[NSUserDefaults standardUserDefaults] setDouble:MAX(10, value) forKey:LSBDefaultsScanInterval];
}

+ (NSString *)claudeProjectsPath {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:LSBDefaultsClaudePath];
    return value.length > 0 ? value : [@"~/.claude/projects" stringByExpandingTildeInPath];
}

+ (void)setClaudeProjectsPath:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:LSBDefaultsClaudePath];
}

+ (NSString *)codexSessionsPath {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:LSBDefaultsCodexPath];
    return value.length > 0 ? value : [@"~/.codex/sessions" stringByExpandingTildeInPath];
}

+ (void)setCodexSessionsPath:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:LSBDefaultsCodexPath];
}

+ (NSString *)opencodeDBPath {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:LSBDefaultsOpenCodePath];
    return value.length > 0 ? value : [@"~/.local/share/opencode/opencode.db" stringByExpandingTildeInPath];
}

+ (void)setOpencodeDBPath:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:LSBDefaultsOpenCodePath];
}

+ (NSString *)pricingOverridePath {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:LSBDefaultsPricingPath];
    return value.length > 0 ? value : [@"~/Library/Application Support/LLM Spend Bar/pricing.json" stringByExpandingTildeInPath];
}

+ (void)setPricingOverridePath:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:LSBDefaultsPricingPath];
}

+ (double)subscriptionPriceForTool:(NSString *)tool {
    if (tool.length == 0) return 0;
    NSString *key = [LSBDefaultsSubscriptionPrefix stringByAppendingString:tool.lowercaseString];
    return [[NSUserDefaults standardUserDefaults] doubleForKey:key];
}

+ (void)setSubscriptionPrice:(double)price forTool:(NSString *)tool {
    if (tool.length == 0) return;
    NSString *key = [LSBDefaultsSubscriptionPrefix stringByAppendingString:tool.lowercaseString];
    [[NSUserDefaults standardUserDefaults] setDouble:MAX(0, price) forKey:key];
}

@end
