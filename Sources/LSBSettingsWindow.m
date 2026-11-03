#import "LSBSettingsWindow.h"
#import "LSBSettings.h"

@interface LSBSettingsWindowController () <NSWindowDelegate>
@property (nonatomic, strong) NSTextField *dailyField;
@property (nonatomic, strong) NSTextField *weeklyField;
@property (nonatomic, strong) NSTextField *monthlyField;
@property (nonatomic, strong) NSPopUpButton *refreshPopup;
@property (nonatomic, strong) NSPopUpButton *displayPopup;
@property (nonatomic, strong) NSTextField *claudeField;
@property (nonatomic, strong) NSTextField *codexField;
@property (nonatomic, strong) NSTextField *opencodeField;
@property (nonatomic, strong) NSTextField *pricingField;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation LSBSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 680, 560)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"LLM Spend — настройки";
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

    NSTextField *title = [NSTextField labelWithString:@"Локальный аудит"];
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];

    NSTextField *hint = [NSTextField wrappingLabelWithString:
        @"Приложение читает локальные логи агентов и считает токены/стоимость. "
        @"Тексты диалогов не читаются. Docker и LiteLLM не нужны."];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = [NSColor secondaryLabelColor];

    self.dailyField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%.2f", LSBSettings.dailyBudget]];
    self.weeklyField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%.2f", LSBSettings.weeklyBudget]];
    self.monthlyField = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%.2f", LSBSettings.monthlyBudget]];

    self.refreshPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSArray<NSString *> *refreshTitles = @[@"30 секунд", @"1 минута", @"5 минут", @"15 минут"];
    NSArray<NSNumber *> *refreshValues = @[@30, @60, @300, @900];
    for (NSUInteger i = 0; i < refreshTitles.count; i++) {
        [self.refreshPopup addItemWithTitle:refreshTitles[i]];
        self.refreshPopup.lastItem.representedObject = refreshValues[i];
    }

    self.displayPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSArray<NSString *> *displayTitles = @[@"Три полоски", @"Доллары за сегодня", @"Токены за сегодня"];
    NSArray<NSString *> *displayValues = @[LSBDisplayModeBars, LSBDisplayModeDollars, LSBDisplayModeTokens];
    for (NSUInteger i = 0; i < displayTitles.count; i++) {
        [self.displayPopup addItemWithTitle:displayTitles[i]];
        self.displayPopup.lastItem.representedObject = displayValues[i];
    }

    self.claudeField = [NSTextField textFieldWithString:LSBSettings.claudeProjectsPath];
    self.codexField = [NSTextField textFieldWithString:LSBSettings.codexSessionsPath];
    self.opencodeField = [NSTextField textFieldWithString:LSBSettings.opencodeDBPath];
    self.pricingField = [NSTextField textFieldWithString:LSBSettings.pricingOverridePath];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self label:@"Бюджет на день, $"], self.dailyField],
        @[[self label:@"Бюджет на неделю, $"], self.weeklyField],
        @[[self label:@"Бюджет на месяц, $"], self.monthlyField],
        @[[self label:@"Сканировать"], self.refreshPopup],
        @[[self label:@"В строке меню"], self.displayPopup],
        @[[self label:@"Claude Code"], self.claudeField],
        @[[self label:@"Codex"], self.codexField],
        @[[self label:@"OpenCode DB"], self.opencodeField],
        @[[self label:@"Свои цены"], self.pricingField],
    ]];
    grid.rowSpacing = 9;
    grid.columnSpacing = 14;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSButton *scan = [NSButton buttonWithTitle:@"Сканировать сейчас" target:self action:@selector(scanNow:)];
    NSButton *folder = [NSButton buttonWithTitle:@"Открыть папку данных" target:self action:@selector(openDataFolder:)];
    NSButton *save = [NSButton buttonWithTitle:@"Сохранить" target:self action:@selector(save:)];
    save.keyEquivalent = @"\r";
    NSButton *cancel = [NSButton buttonWithTitle:@"Отмена" target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";

    NSView *spacer = [NSView new];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [spacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[scan, folder, spacer, cancel, save]];
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
        [self.statusLabel.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:12],
        [buttons.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [buttons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [buttons.topAnchor constraintGreaterThanOrEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
    ]];
    [self.claudeField.widthAnchor constraintGreaterThanOrEqualToConstant:400].active = YES;
    [self.codexField.widthAnchor constraintGreaterThanOrEqualToConstant:400].active = YES;
    [self.opencodeField.widthAnchor constraintGreaterThanOrEqualToConstant:400].active = YES;
    [self.pricingField.widthAnchor constraintGreaterThanOrEqualToConstant:400].active = YES;
}

- (NSTextField *)label:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.alignment = NSTextAlignmentRight;
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (void)showSettings {
    self.dailyField.stringValue = [NSString stringWithFormat:@"%.2f", LSBSettings.dailyBudget];
    self.weeklyField.stringValue = [NSString stringWithFormat:@"%.2f", LSBSettings.weeklyBudget];
    self.monthlyField.stringValue = [NSString stringWithFormat:@"%.2f", LSBSettings.monthlyBudget];
    self.claudeField.stringValue = LSBSettings.claudeProjectsPath;
    self.codexField.stringValue = LSBSettings.codexSessionsPath;
    self.opencodeField.stringValue = LSBSettings.opencodeDBPath;
    self.pricingField.stringValue = LSBSettings.pricingOverridePath;
    self.statusLabel.stringValue = @"";

    NSTimeInterval interval = LSBSettings.scanInterval;
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

    NSScreen *screen = [NSScreen mainScreen];
    NSRect visible = screen.visibleFrame;
    NSRect frame = self.window.frame;
    frame.origin.x = visible.origin.x + (visible.size.width - frame.size.width) / 2.0;
    frame.origin.y = visible.origin.y + (visible.size.height - frame.size.height) / 2.0;
    [self.window setFrame:frame display:YES];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
}

- (void)scanNow:(id)sender {
    [self saveSettingsWithoutClosing];
    self.statusLabel.stringValue = @"Сканирование запущено…";
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    [self.delegate settingsDidChange];
}

- (void)openDataFolder:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:LSBSettings.dataDirectory]];
}

- (void)saveSettingsWithoutClosing {
    [LSBSettings setDailyBudget:MAX(0, self.dailyField.doubleValue)];
    [LSBSettings setWeeklyBudget:MAX(0, self.weeklyField.doubleValue)];
    [LSBSettings setMonthlyBudget:MAX(0, self.monthlyField.doubleValue)];
    NSNumber *refresh = self.refreshPopup.selectedItem.representedObject;
    if (refresh) [LSBSettings setScanInterval:refresh.doubleValue];
    NSString *display = self.displayPopup.selectedItem.representedObject;
    if (display) [LSBSettings setDisplayMode:display];

    NSString *claude = [self.claudeField.stringValue stringByExpandingTildeInPath];
    NSString *codex = [self.codexField.stringValue stringByExpandingTildeInPath];
    NSString *opencode = [self.opencodeField.stringValue stringByExpandingTildeInPath];
    NSString *pricing = [self.pricingField.stringValue stringByExpandingTildeInPath];
    if (claude.length > 0) [LSBSettings setClaudeProjectsPath:claude];
    if (codex.length > 0) [LSBSettings setCodexSessionsPath:codex];
    if (opencode.length > 0) [LSBSettings setOpencodeDBPath:opencode];
    if (pricing.length > 0) [LSBSettings setPricingOverridePath:pricing];
}

- (void)save:(id)sender {
    [self saveSettingsWithoutClosing];
    [self.delegate settingsDidChange];
    [self.window close];
}

- (void)cancel:(id)sender {
    [self.window close];
}

- (void)windowWillClose:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

@end
