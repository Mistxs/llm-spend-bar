#import "LSBSettingsWindow.h"
#import "LSBApiClient.h"
#import "LSBSettings.h"

@interface LSBSettingsWindowController () <NSWindowDelegate>
@property (nonatomic, strong) NSTextField *baseURLField;
@property (nonatomic, strong) NSSecureTextField *keyField;
@property (nonatomic, strong) NSTextField *dailyField;
@property (nonatomic, strong) NSTextField *weeklyField;
@property (nonatomic, strong) NSTextField *monthlyField;
@property (nonatomic, strong) NSPopUpButton *refreshPopup;
@property (nonatomic, strong) NSPopUpButton *displayPopup;
@property (nonatomic, strong) NSTextField *configField;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *testButton;
@end

@implementation LSBSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 430)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"LLM Spend Bar — настройки";
    window.releasedWhenClosed = NO;
    window.delegate = self;
    self = [super initWithWindow:window];
    if (self) {
        [self buildInterface];
    }
    return self;
}

- (void)buildInterface {
    NSView *content = self.window.contentView;

    NSTextField *title = [NSTextField labelWithString:@"Подключение к LiteLLM"];
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];

    NSTextField *hint = [NSTextField wrappingLabelWithString:
        @"LiteLLM должен быть запущен локально (docker compose up -d). "
        @"Master key можно взять из .env или из LiteLLM UI."];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = [NSColor secondaryLabelColor];

    self.baseURLField = [NSTextField textFieldWithString:LSBSettings.baseURLString];
    self.baseURLField.placeholderString = @"http://127.0.0.1:4000";

    self.keyField = [NSSecureTextField textFieldWithString:@""];
    self.keyField.placeholderString = LSBSettings.masterKey.length > 0
        ? @"ключ сохранён в Keychain — оставьте пустым, чтобы не менять"
        : @"sk-... (master key LiteLLM)";

    NSButton *clearKey = [NSButton buttonWithTitle:@"Удалить ключ" target:self action:@selector(clearKey:)];
    clearKey.bezelStyle = NSBezelStyleRounded;
    clearKey.controlSize = NSControlSizeSmall;

    NSStackView *keyRow = [NSStackView stackViewWithViews:@[self.keyField, clearKey]];
    keyRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    keyRow.spacing = 8;

    self.dailyField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%.2f", LSBSettings.dailyBudget]];
    self.weeklyField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%.2f", LSBSettings.weeklyBudget]];
    self.monthlyField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%.2f", LSBSettings.monthlyBudget]];

    self.refreshPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSArray<NSString *> *refreshTitles = @[@"15 секунд", @"30 секунд", @"1 минута", @"5 минут"];
    NSArray<NSNumber *> *refreshValues = @[@15, @30, @60, @300];
    for (NSUInteger i = 0; i < refreshTitles.count; i++) {
        [self.refreshPopup addItemWithTitle:refreshTitles[i]];
        self.refreshPopup.lastItem.representedObject = refreshValues[i];
    }
    NSTimeInterval interval = LSBSettings.refreshInterval;
    NSInteger selected = 1;
    for (NSUInteger i = 0; i < refreshValues.count; i++) {
        if (fabs(refreshValues[i].doubleValue - interval) < 1) {
            selected = i;
            break;
        }
    }
    [self.refreshPopup selectItemAtIndex:selected];

    self.displayPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSArray<NSString *> *displayTitles = @[@"Три полоски", @"Доллары за сегодня", @"Токены за сегодня"];
    NSArray<NSString *> *displayValues = @[LSBDisplayModeBars, LSBDisplayModeDollars, LSBDisplayModeTokens];
    for (NSUInteger i = 0; i < displayTitles.count; i++) {
        [self.displayPopup addItemWithTitle:displayTitles[i]];
        self.displayPopup.lastItem.representedObject = displayValues[i];
    }
    NSUInteger displayIndex = [displayValues indexOfObject:LSBSettings.displayMode];
    [self.displayPopup selectItemAtIndex:displayIndex == NSNotFound ? 0 : (NSInteger)displayIndex];

    self.configField = [NSTextField textFieldWithString:LSBSettings.configPath];
    self.configField.placeholderString = @"~/llm-spend-bar/litellm/config.yaml";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self label:@"LiteLLM URL"], self.baseURLField],
        @[[self label:@"Master key"], keyRow],
        @[[self label:@"Бюджет на день, $"], self.dailyField],
        @[[self label:@"Бюджет на неделю, $"], self.weeklyField],
        @[[self label:@"Бюджет на месяц, $"], self.monthlyField],
        @[[self label:@"Обновлять"], self.refreshPopup],
        @[[self label:@"В строке меню"], self.displayPopup],
        @[[self label:@"Конфиг LiteLLM"], self.configField],
    ]];
    grid.rowSpacing = 10;
    grid.columnSpacing = 14;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.testButton = [NSButton buttonWithTitle:@"Проверить подключение" target:self action:@selector(testConnection:)];
    NSButton *save = [NSButton buttonWithTitle:@"Сохранить" target:self action:@selector(save:)];
    save.keyEquivalent = @"\r";
    NSButton *cancel = [NSButton buttonWithTitle:@"Отмена" target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";

    NSView *spacer = [NSView new];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [spacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.testButton, spacer, cancel, save]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;

    [content addSubview:title];
    [content addSubview:hint];
    [content addSubview:grid];
    [content addSubview:self.statusLabel];
    [content addSubview:buttons];

    title.translatesAutoresizingMaskIntoConstraints = NO;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:22],

        [hint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [hint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],

        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [grid.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [grid.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:18],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [self.statusLabel.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:14],

        [buttons.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [buttons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [buttons.topAnchor constraintGreaterThanOrEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
    ]];

    [self.baseURLField.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
    [self.keyField.widthAnchor constraintGreaterThanOrEqualToConstant:250].active = YES;
    [self.configField.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
}

- (NSTextField *)label:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.alignment = NSTextAlignmentRight;
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (void)showSettings {
    self.baseURLField.stringValue = LSBSettings.baseURLString;
    self.keyField.stringValue = @"";
    self.keyField.placeholderString = LSBSettings.masterKey.length > 0
        ? @"ключ сохранён в Keychain — оставьте пустым, чтобы не менять"
        : @"sk-... (master key LiteLLM)";
    self.dailyField.stringValue = [NSString stringWithFormat:@"%.2f", LSBSettings.dailyBudget];
    self.weeklyField.stringValue = [NSString stringWithFormat:@"%.2f", LSBSettings.weeklyBudget];
    self.monthlyField.stringValue = [NSString stringWithFormat:@"%.2f", LSBSettings.monthlyBudget];
    self.configField.stringValue = LSBSettings.configPath;
    self.statusLabel.stringValue = @"";

    NSTimeInterval interval = LSBSettings.refreshInterval;
    for (NSMenuItem *item in self.refreshPopup.itemArray) {
        NSNumber *value = item.representedObject;
        if (value && fabs(value.doubleValue - interval) < 1) {
            [self.refreshPopup selectItem:item];
            break;
        }
    }
    NSString *display = LSBSettings.displayMode;
    for (NSMenuItem *item in self.displayPopup.itemArray) {
        if ([item.representedObject isEqual:display]) {
            [self.displayPopup selectItem:item];
            break;
        }
    }

    [self.window center];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)clearKey:(id)sender {
    [LSBSettings deleteMasterKey];
    self.keyField.stringValue = @"";
    self.keyField.placeholderString = @"ключ удалён";
    self.statusLabel.stringValue = @"Master key удалён из Keychain.";
    self.statusLabel.textColor = [NSColor systemOrangeColor];
}

- (void)testConnection:(id)sender {
    NSString *raw = [self.baseURLField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) raw = @"http://127.0.0.1:4000";
    if (![raw hasPrefix:@"http://"] && ![raw hasPrefix:@"https://"]) raw = [@"http://" stringByAppendingString:raw];
    NSURL *url = [NSURL URLWithString:raw];
    NSString *key = self.keyField.stringValue;
    if (key.length == 0) key = LSBSettings.masterKey;

    self.testButton.enabled = NO;
    self.statusLabel.stringValue = @"Проверяю…";
    self.statusLabel.textColor = [NSColor secondaryLabelColor];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        LSBApiClient *client = [[LSBApiClient alloc] initWithBaseURL:url apiKey:key];
        NSError *error = nil;
        BOOL healthy = [client checkHealthWithError:&error];
        LSBSummary *summary = nil;
        if (healthy && key.length > 0) {
            summary = [client fetchSummaryWithError:&error];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testButton.enabled = YES;
            if (healthy && !error) {
                NSString *extra = summary
                    ? [NSString stringWithFormat:@" · запросов в выборке: %ld", (long)summary.logCount]
                    : @"";
                self.statusLabel.stringValue = [@"LiteLLM отвечает" stringByAppendingString:extra];
                self.statusLabel.textColor = [NSColor systemGreenColor];
            } else if (healthy && error) {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"LiteLLM отвечает, но ключ не принят: %@", error.localizedDescription];
                self.statusLabel.textColor = [NSColor systemOrangeColor];
            } else {
                self.statusLabel.stringValue = error.localizedDescription ?: @"Не удалось подключиться";
                self.statusLabel.textColor = [NSColor systemRedColor];
            }
        });
    });
}

- (void)save:(id)sender {
    NSString *raw = [self.baseURLField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) raw = @"http://127.0.0.1:4000";
    if (![raw hasPrefix:@"http://"] && ![raw hasPrefix:@"https://"]) raw = [@"http://" stringByAppendingString:raw];
    while ([raw hasSuffix:@"/"]) raw = [raw substringToIndex:raw.length - 1];
    [LSBSettings setBaseURLString:raw];

    NSString *key = self.keyField.stringValue;
    if (key.length > 0) {
        NSError *error = nil;
        if (![LSBSettings setMasterKey:key error:&error]) {
            self.statusLabel.stringValue = error.localizedDescription ?: @"Не удалось сохранить ключ";
            self.statusLabel.textColor = [NSColor systemRedColor];
            return;
        }
    }

    [LSBSettings setDailyBudget:MAX(0, self.dailyField.doubleValue)];
    [LSBSettings setWeeklyBudget:MAX(0, self.weeklyField.doubleValue)];
    [LSBSettings setMonthlyBudget:MAX(0, self.monthlyField.doubleValue)];

    NSNumber *refresh = self.refreshPopup.selectedItem.representedObject;
    if (refresh) [LSBSettings setRefreshInterval:refresh.doubleValue];

    NSString *display = self.displayPopup.selectedItem.representedObject;
    if (display) [LSBSettings setDisplayMode:display];

    NSString *config = [self.configField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (config.length > 0) [LSBSettings setConfigPath:[config stringByExpandingTildeInPath]];

    [self.delegate settingsDidChange];
    [self.window close];
}

- (void)cancel:(id)sender {
    [self.window close];
}

@end
