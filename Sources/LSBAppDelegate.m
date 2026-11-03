#import "LSBAppDelegate.h"
#import <ServiceManagement/ServiceManagement.h>

#import "LSBApiClient.h"
#import "LSBFormat.h"
#import "LSBMenuBarIcon.h"
#import "LSBModels.h"
#import "LSBSettings.h"
#import "LSBSettingsWindow.h"

@interface LSBAppDelegate () <LSBSettingsWindowDelegate>
@end

@implementation LSBAppDelegate {
    NSStatusItem *_statusItem;
    NSTimer *_timer;
    LSBSummary *_summary;
    NSDate *_lastUpdated;
    NSString *_lastError;
    BOOL _refreshing;
    BOOL _healthy;
    BOOL _menuOpen;
    LSBSettingsWindowController *_settingsWindow;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [LSBSettings registerDefaults];

    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.behavior = NSStatusItemBehaviorRemovalAllowed;

    _settingsWindow = [LSBSettingsWindowController new];
    _settingsWindow.delegate = self;

    [self rebuildMenu];
    [self updateButton];
    [self scheduleTimer];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                          selector:@selector(didWake:)
                                                              name:NSWorkspaceDidWakeNotification
                                                            object:nil];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf refreshForced:YES];
        if (getenv("LSB_OPEN_SETTINGS") != NULL) {
            [weakSelf openSettings:nil];
        }
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_timer invalidate];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

- (void)dumpMenuToStandardOutput {
    [LSBSettings registerDefaults];
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    LSBApiClient *client = [self currentClient];
    NSError *error = nil;
    _healthy = [client checkHealthWithError:&error];
    _summary = [client fetchSummaryWithError:&error];
    _lastError = _summary ? nil : (error.localizedDescription ?: @"нет данных");
    _lastUpdated = [NSDate date];

    [self updateButton];
    [self rebuildMenu];

    printf("menu bar title: %s\n",
           (_statusItem.button.attributedTitle.string ?: @"").UTF8String);
    printf("menu bar tooltip:\n%s\n\n",
           (_statusItem.button.toolTip ?: @"").UTF8String);

    [self dumpMenu:_statusItem.menu indent:0];
}

- (void)dumpMenu:(NSMenu *)menu indent:(NSInteger)indent {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) {
            printf("%*s---\n", (int)(indent * 2), "");
            continue;
        }
        NSString *title = item.attributedTitle.string ?: item.title;
        printf("%*s%s%s%s\n",
               (int)(indent * 2), "",
               item.enabled ? "" : "[disabled] ",
               title.UTF8String,
               item.state == NSControlStateValueOn ? "  ✓" : "");
        if (item.submenu) {
            [self dumpMenu:item.submenu indent:indent + 1];
        }
    }
}

- (void)didWake:(NSNotification *)notification {
    [self refreshForced:YES];
}

#pragma mark - Loading

- (LSBApiClient *)currentClient {
    NSURL *baseURL = LSBSettings.baseURL;
    if (!baseURL) baseURL = [NSURL URLWithString:@"http://127.0.0.1:4000"];
    return [[LSBApiClient alloc] initWithBaseURL:baseURL apiKey:LSBSettings.masterKey];
}

- (void)refreshNow:(id)sender {
    [self refreshForced:YES];
}

- (void)refreshForced:(BOOL)force {
    if (_refreshing) return;
    if (!force && _lastUpdated && [[NSDate date] timeIntervalSinceDate:_lastUpdated] < 5) return;

    if (!LSBSettings.demoMode && LSBSettings.masterKey.length == 0) {
        _lastError = @"LiteLLM не настроен: укажите master key в «Настройках…».";
        _summary = nil;
        [self updateButton];
        if (!_menuOpen) [self rebuildMenu];
        return;
    }

    _refreshing = YES;
    [self updateButton];

    LSBApiClient *client = [self currentClient];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        BOOL healthy = [client checkHealthWithError:&error];
        LSBSummary *summary = [client fetchSummaryWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf applySummary:summary healthy:healthy error:error];
        });
    });
}

- (void)applySummary:(LSBSummary *)summary healthy:(BOOL)healthy error:(NSError *)error {
    _refreshing = NO;
    _healthy = healthy || summary != nil;

    if (summary) {
        _summary = summary;
        _lastUpdated = [NSDate date];
        _lastError = nil;
    } else {
        _lastError = error.localizedDescription ?: @"Неизвестная ошибка";
    }

    [self updateButton];
    if (!_menuOpen) [self rebuildMenu];
}

- (void)scheduleTimer {
    [_timer invalidate];
    NSTimeInterval interval = LSBSettings.refreshInterval;
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:interval
                                            repeats:YES
                                              block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        [weakSelf refreshForced:NO];
    }];
    timer.tolerance = MIN(10, interval * 0.1);
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    _timer = timer;
}

#pragma mark - Status item

- (double)fractionForSpend:(double)spend budget:(double)budget {
    if (budget <= 0) return -1;
    return spend / budget;
}

- (void)updateButton {
    NSStatusBarButton *button = _statusItem.button;
    if (!button) return;

    if (_summary) {
        NSString *mode = LSBSettings.displayMode;
        if ([mode isEqualToString:LSBDisplayModeDollars]) {
            double fraction = [self fractionForSpend:_summary.today.spend budget:LSBSettings.dailyBudget];
            button.image = nil;
            button.imagePosition = NSNoImage;
            button.attributedTitle = [self textTitle:[LSBFormat usdCompact:_summary.today.spend]
                                               color:[LSBMenuBarIcon colorForSpendFraction:fraction]];
        } else if ([mode isEqualToString:LSBDisplayModeTokens]) {
            button.image = nil;
            button.imagePosition = NSNoImage;
            button.attributedTitle = [self textTitle:[LSBFormat tokens:_summary.today.totalTokens]
                                               color:[NSColor labelColor]];
        } else {
            NSArray<NSNumber *> *fractions = @[
                @([self fractionForSpend:_summary.today.spend budget:LSBSettings.dailyBudget]),
                @([self fractionForSpend:_summary.week.spend budget:LSBSettings.weeklyBudget]),
                @([self fractionForSpend:_summary.month.spend budget:LSBSettings.monthlyBudget]),
            ];
            button.image = [LSBMenuBarIcon imageWithFractions:fractions error:_lastError != nil];
            button.imagePosition = NSImageOnly;
            button.attributedTitle = [[NSAttributedString alloc] initWithString:@""];
        }
        button.toolTip = [self tooltipText];
    } else if (_refreshing) {
        button.image = [LSBMenuBarIcon imageWithFractions:@[] error:NO];
        button.imagePosition = NSImageOnly;
        button.attributedTitle = [[NSAttributedString alloc] initWithString:@""];
        button.toolTip = @"Загружаю расходы из LiteLLM…";
    } else {
        button.image = nil;
        button.imagePosition = NSNoImage;
        button.attributedTitle = [self textTitle:@"LLM ?" color:[NSColor systemOrangeColor]];
        button.toolTip = _lastError ?: @"Нет данных LiteLLM";
    }

    button.accessibilityLabel = button.toolTip ?: @"LLM Spend Bar";
}

- (NSAttributedString *)textTitle:(NSString *)text color:(NSColor *)color {
    return [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: color,
        NSBaselineOffsetAttributeName: @1,
    }];
}

- (NSString *)tooltipText {
    if (!_summary) return _lastError ?: @"LLM Spend Bar";

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:@"LLM Spend · LiteLLM"];
    [lines addObject:[NSString stringWithFormat:@"Сегодня: %@ · %@ токенов · %@",
                      [self spendDescription:_summary.today.spend budget:LSBSettings.dailyBudget],
                      [LSBFormat tokens:_summary.today.totalTokens],
                      [LSBFormat requests:_summary.today.requests]]];
    [lines addObject:[NSString stringWithFormat:@"Неделя: %@ · %@ токенов · %@",
                      [self spendDescription:_summary.week.spend budget:LSBSettings.weeklyBudget],
                      [LSBFormat tokens:_summary.week.totalTokens],
                      [LSBFormat requests:_summary.week.requests]]];
    [lines addObject:[NSString stringWithFormat:@"Месяц: %@ · %@ токенов · %@",
                      [self spendDescription:_summary.month.spend budget:LSBSettings.monthlyBudget],
                      [LSBFormat tokens:_summary.month.totalTokens],
                      [LSBFormat requests:_summary.month.requests]]];
    [lines addObject:[NSString stringWithFormat:@"LiteLLM: %@", _healthy ? @"работает" : @"недоступен"]];
    if (_summary.truncated) {
        [lines addObject:@"⚠︎ выборка обрезана: больше 10 000 записей за период"];
    }
    if (_lastError) [lines addObject:[@"⚠︎ " stringByAppendingString:_lastError]];
    [lines addObject:[LSBFormat updated:_lastUpdated]];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)spendDescription:(double)spend budget:(double)budget {
    if (budget <= 0) return [LSBFormat usd:spend];
    return [NSString stringWithFormat:@"%@ / %@ (%@)",
            [LSBFormat usd:spend],
            [LSBFormat usd:budget],
            [LSBFormat percent:spend / budget]];
}

#pragma mark - Menu

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"LLM Spend"];
    menu.autoenablesItems = NO;
    menu.delegate = self;

    [menu addItem:[self headerItem]];

    if (!_summary && LSBSettings.masterKey.length == 0 && !LSBSettings.demoMode) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self infoItem:@"LiteLLM не настроен"]];
        NSMenuItem *setup = [self actionItem:@"Настроить LiteLLM…" action:@selector(openSettings:) key:@","];
        setup.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil];
        [menu addItem:setup];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self actionItem:@"Выйти" action:@selector(quit:) key:@"q"]];
        _statusItem.menu = menu;
        return;
    }

    if (_summary) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self periodItem:@"Сегодня" stats:_summary.today budget:LSBSettings.dailyBudget]];
        [menu addItem:[self periodItem:@"Неделя" stats:_summary.week budget:LSBSettings.weeklyBudget]];
        [menu addItem:[self periodItem:@"Месяц" stats:_summary.month budget:LSBSettings.monthlyBudget]];
    } else if (_refreshing) {
        [menu addItem:[self infoItem:@"Загружаю расходы…"]];
    } else {
        [menu addItem:[self infoItem:@"Нет данных о расходах"]];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *sessions = [[NSMenuItem alloc] initWithTitle:@"Сессии сегодня" action:nil keyEquivalent:@""];
    sessions.image = [NSImage imageWithSystemSymbolName:@"bubble.left.and.bubble.right" accessibilityDescription:nil];
    sessions.submenu = [self sessionsMenu];
    [menu addItem:sessions];

    NSMenuItem *models = [[NSMenuItem alloc] initWithTitle:@"Модели сегодня" action:nil keyEquivalent:@""];
    models.image = [NSImage imageWithSystemSymbolName:@"cpu" accessibilityDescription:nil];
    models.submenu = [self modelsMenu];
    [menu addItem:models];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self statusItem]];
    [menu addItem:[self infoItem:[LSBFormat updated:_lastUpdated]]];

    if (_summary.truncated) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self errorItem:@"Выборка обрезана: больше 10 000 записей за период"]];
    }

    if (_lastError.length > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self errorItem:_lastError]];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *refresh = [self actionItem:@"Обновить" action:@selector(refreshNow:) key:@"r"];
    refresh.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:nil];
    refresh.enabled = !_refreshing;
    [menu addItem:refresh];

    NSMenuItem *ui = [self actionItem:@"Открыть LiteLLM UI" action:@selector(openLiteLLMUI:) key:@"o"];
    ui.image = [NSImage imageWithSystemSymbolName:@"safari" accessibilityDescription:nil];
    [menu addItem:ui];

    NSMenuItem *config = [self actionItem:@"Открыть конфиг LiteLLM" action:@selector(openConfig:) key:@""];
    config.image = [NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:nil];
    [menu addItem:config];

    NSMenuItem *folder = [self actionItem:@"Открыть папку проекта" action:@selector(openProjectFolder:) key:@""];
    folder.image = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil];
    [menu addItem:folder];

    NSMenuItem *settings = [self actionItem:@"Настройки…" action:@selector(openSettings:) key:@","];
    settings.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil];
    [menu addItem:settings];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *view = [[NSMenuItem alloc] initWithTitle:@"Вид" action:nil keyEquivalent:@""];
    view.image = [NSImage imageWithSystemSymbolName:@"chart.bar" accessibilityDescription:nil];
    view.submenu = [self viewMenu];
    [menu addItem:view];

    NSMenuItem *interval = [[NSMenuItem alloc] initWithTitle:@"Обновлять" action:nil keyEquivalent:@""];
    interval.image = [NSImage imageWithSystemSymbolName:@"clock" accessibilityDescription:nil];
    interval.submenu = [self intervalMenu];
    [menu addItem:interval];

    NSMenuItem *login = [self actionItem:@"Запускать при входе" action:@selector(toggleLaunchAtLogin:) key:@""];
    login.image = [NSImage imageWithSystemSymbolName:@"power" accessibilityDescription:nil];
    login.state = [self launchAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:login];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [self actionItem:@"Выйти" action:@selector(quit:) key:@"q"];
    quit.image = [NSImage imageWithSystemSymbolName:@"xmark.circle" accessibilityDescription:nil];
    [menu addItem:quit];

    _statusItem.menu = menu;
}

- (NSMenuItem *)headerItem {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
        initWithString:@"LLM Spend"
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName: [NSColor labelColor],
            }];
    [text appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"  ·  LiteLLM"
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            }]];
    if (_summary.demo) {
        [text appendAttributedString:[[NSAttributedString alloc]
            initWithString:@"  ·  DEMO"
                attributes:@{
                    NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
                    NSForegroundColorAttributeName: [NSColor systemOrangeColor],
                }]];
    }

    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.attributedTitle = text;
    item.enabled = NO;
    return item;
}

- (NSMenuItem *)periodItem:(NSString *)title stats:(LSBPeriodStats *)stats budget:(double)budget {
    NSFont *mono = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
    NSFont *monoRegular = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];

    [line appendAttributedString:[[NSAttributedString alloc]
        initWithString:[LSBFormat pad:title width:8]
            attributes:@{NSFontAttributeName: mono, NSForegroundColorAttributeName: [NSColor labelColor]}]];

    double fraction = budget > 0 ? stats.spend / budget : -1;
    if (budget > 0) {
        [line appendAttributedString:[[NSAttributedString alloc]
            initWithString:[LSBFormat bar:fraction]
                attributes:@{
                    NSFontAttributeName: monoRegular,
                    NSForegroundColorAttributeName: [LSBMenuBarIcon colorForSpendFraction:fraction],
                }]];
        [line appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"  %@", [LSBFormat pad:[LSBFormat percent:fraction] width:4]]
                attributes:@{NSFontAttributeName: mono, NSForegroundColorAttributeName: [NSColor labelColor]}]];
        [line appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"  %@ / %@",
                            [LSBFormat usd:stats.spend],
                            [LSBFormat usd:budget]]
                attributes:@{NSFontAttributeName: monoRegular, NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}]];
    } else {
        [line appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"  %@", [LSBFormat usd:stats.spend]]
                attributes:@{NSFontAttributeName: mono, NSForegroundColorAttributeName: [NSColor labelColor]}]];
    }

    [line appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"  %@ tok", [LSBFormat tokens:stats.totalTokens]]
            attributes:@{
                NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
            }]];

    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.attributedTitle = line;
    item.toolTip = [NSString stringWithFormat:@"%@: %@, %@ токенов, %@, кэш-хитов: %lld",
                    title,
                    [self spendDescription:stats.spend budget:budget],
                    [LSBFormat tokens:stats.totalTokens],
                    [LSBFormat requests:stats.requests],
                    stats.cacheHits];
    item.enabled = NO;
    return item;
}

- (NSMenu *)sessionsMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Сессии сегодня"];
    menu.autoenablesItems = NO;

    if (_summary.sessions.count == 0) {
        [menu addItem:[self infoItem:@"Нет запросов сегодня"]];
        return menu;
    }

    NSInteger limit = MIN((NSInteger)_summary.sessions.count, 12);
    for (NSInteger index = 0; index < limit; index++) {
        LSBSessionSpend *session = _summary.sessions[(NSUInteger)index];
        [menu addItem:[self sessionItem:session]];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *all = [self actionItem:@"Открыть LiteLLM UI" action:@selector(openLiteLLMUI:) key:@""];
    all.image = [NSImage imageWithSystemSymbolName:@"safari" accessibilityDescription:nil];
    [menu addItem:all];
    return menu;
}

- (NSMenuItem *)sessionItem:(LSBSessionSpend *)session {
    NSFont *titleFont = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    NSFont *mono = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];

    [line appendAttributedString:[[NSAttributedString alloc]
        initWithString:[LSBFormat truncate:session.title width:24]
            attributes:@{NSFontAttributeName: titleFont, NSForegroundColorAttributeName: [NSColor labelColor]}]];
    [line appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@" %@", [LSBFormat shortSession:session.sessionID]]
            attributes:@{
                NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
            }]];
    [line appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"  %@", [LSBFormat usd:session.spend]]
            attributes:@{NSFontAttributeName: mono, NSForegroundColorAttributeName: [NSColor labelColor]}]];
    [line appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"  %@ tok  %@",
                        [LSBFormat tokens:session.totalTokens],
                        [LSBFormat requests:session.requests]]
            attributes:@{
                NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
            }]];

    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.attributedTitle = line;
    item.toolTip = [NSString stringWithFormat:@"%@\nID: %@\nМодели: %@\nНачало: %@\nАктивность: %@",
                    session.title,
                    session.sessionID,
                    [session.models componentsJoinedByString:@", "],
                    [NSDateFormatter localizedStringFromDate:session.startedAt dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle],
                    [LSBFormat relative:session.lastActivity]];
    item.target = self;
    item.action = @selector(openSession:);
    item.representedObject = session.sessionID;
    item.enabled = YES;
    return item;
}

- (NSMenu *)modelsMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Модели сегодня"];
    menu.autoenablesItems = NO;

    NSArray<LSBModelSpend *> *models = _summary.today.models;
    if (models.count == 0) {
        [menu addItem:[self infoItem:@"Нет данных"]];
        return menu;
    }

    NSInteger limit = MIN((NSInteger)models.count, 10);
    for (NSInteger index = 0; index < limit; index++) {
        LSBModelSpend *model = models[(NSUInteger)index];
        NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
        [line appendAttributedString:[[NSAttributedString alloc]
            initWithString:[LSBFormat pad:[LSBFormat truncate:model.model width:28] width:28]
                attributes:@{
                    NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName: [NSColor labelColor],
                }]];
        [line appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"  %@", [LSBFormat usd:model.spend]]
                attributes:@{
                    NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium],
                    NSForegroundColorAttributeName: [NSColor labelColor],
                }]];
        [line appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"  %@ tok  %@",
                            [LSBFormat tokens:model.totalTokens],
                            [LSBFormat requests:model.requests]]
                attributes:@{
                    NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
                }]];
        NSMenuItem *item = [[NSMenuItem alloc] init];
        item.attributedTitle = line;
        item.enabled = NO;
        [menu addItem:item];
    }
    return menu;
}

- (NSMenuItem *)statusItem {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    [text appendAttributedString:[[NSAttributedString alloc]
        initWithString:_healthy ? @"● " : @"○ "
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightBold],
                NSForegroundColorAttributeName: _healthy ? [NSColor systemGreenColor] : [NSColor systemRedColor],
            }]];
    NSString *host = LSBSettings.baseURL.absoluteString ?: @"demo";
    [text appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"LiteLLM  %@", host]
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            }]];
    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.attributedTitle = text;
    item.enabled = NO;
    return item;
}

- (NSMenuItem *)infoItem:(NSString *)text {
    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.attributedTitle = [[NSAttributedString alloc]
        initWithString:text
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            }];
    item.enabled = NO;
    return item;
}

- (NSMenuItem *)errorItem:(NSString *)text {
    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.attributedTitle = [[NSAttributedString alloc]
        initWithString:[@"⚠︎  " stringByAppendingString:text]
            attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: [NSColor systemRedColor],
            }];
    item.enabled = NO;
    return item;
}

- (NSMenuItem *)actionItem:(NSString *)title action:(SEL)action key:(NSString *)key {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    item.enabled = YES;
    return item;
}

- (NSMenu *)viewMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Вид"];
    menu.autoenablesItems = NO;
    NSArray<NSString *> *titles = @[@"Три полоски", @"Доллары за сегодня", @"Токены за сегодня"];
    NSArray<NSString *> *values = @[LSBDisplayModeBars, LSBDisplayModeDollars, LSBDisplayModeTokens];
    NSString *current = LSBSettings.displayMode;

    for (NSInteger index = 0; index < (NSInteger)titles.count; index++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[(NSUInteger)index]
                                                      action:@selector(selectMode:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = values[(NSUInteger)index];
        item.state = [current isEqualToString:values[(NSUInteger)index]] ? NSControlStateValueOn : NSControlStateValueOff;
        item.enabled = YES;
        [menu addItem:item];
    }
    return menu;
}

- (NSMenu *)intervalMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Обновлять"];
    menu.autoenablesItems = NO;
    NSArray<NSString *> *titles = @[@"15 секунд", @"30 секунд", @"1 минуту", @"5 минут"];
    NSArray<NSNumber *> *values = @[@15, @30, @60, @300];
    NSTimeInterval current = LSBSettings.refreshInterval;

    for (NSInteger index = 0; index < (NSInteger)titles.count; index++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[(NSUInteger)index]
                                                      action:@selector(selectInterval:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = values[(NSUInteger)index];
        item.state = fabs(current - values[(NSUInteger)index].doubleValue) < 1
            ? NSControlStateValueOn
            : NSControlStateValueOff;
        item.enabled = YES;
        [menu addItem:item];
    }
    return menu;
}

#pragma mark - Menu delegate

- (void)menuWillOpen:(NSMenu *)menu {
    _menuOpen = YES;
    [self refreshForced:YES];
}

- (void)menuDidClose:(NSMenu *)menu {
    _menuOpen = NO;
    [self rebuildMenu];
}

#pragma mark - Actions

- (void)openSession:(NSMenuItem *)sender {
    NSString *sessionID = [sender.representedObject isKindOfClass:[NSString class]] ? sender.representedObject : nil;
    if (sessionID.length > 0) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard setString:sessionID forType:NSPasteboardTypeString];
    }
    [self openLiteLLMUI:sender];
}

- (void)openLiteLLMUI:(id)sender {
    NSURL *base = LSBSettings.baseURL;
    if (!base || [[base scheme] isEqualToString:@"demo"]) {
        NSBeep();
        return;
    }
    NSURL *url = [NSURL URLWithString:@"ui" relativeToURL:[NSURL URLWithString:[base.absoluteString stringByAppendingString:@"/"]]];
    if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openConfig:(id)sender {
    NSString *path = LSBSettings.configPath;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Конфиг LiteLLM не найден";
        alert.informativeText = [NSString stringWithFormat:@"Файл %@ не существует. Проверьте путь в настройках.", path];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)openProjectFolder:(id)sender {
    NSString *config = LSBSettings.configPath;
    NSString *project = [[config stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    if (project.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:project]) {
        NSBeep();
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:project]];
}

- (void)openSettings:(id)sender {
    [_settingsWindow showSettings];
}

- (void)selectMode:(NSMenuItem *)sender {
    NSString *value = [sender.representedObject isKindOfClass:[NSString class]] ? sender.representedObject : nil;
    if (!value) return;
    [LSBSettings setDisplayMode:value];
    [self updateButton];
    [self rebuildMenu];
}

- (void)selectInterval:(NSMenuItem *)sender {
    NSNumber *value = [sender.representedObject isKindOfClass:[NSNumber class]] ? sender.representedObject : nil;
    if (!value) return;
    [LSBSettings setRefreshInterval:value.doubleValue];
    [self scheduleTimer];
    [self rebuildMenu];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

- (BOOL)launchAtLoginEnabled {
    if (@available(macOS 13.0, *)) {
        return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
    }
    return NO;
}

- (void)toggleLaunchAtLogin:(id)sender {
    if (@available(macOS 13.0, *)) {
        NSError *error = nil;
        SMAppService *service = [SMAppService mainAppService];
        if (service.status == SMAppServiceStatusEnabled) {
            [service unregisterAndReturnError:&error];
        } else {
            [service registerAndReturnError:&error];
        }
        if (error) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Не удалось изменить автозапуск";
            alert.informativeText = error.localizedDescription ?: @"";
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
    }
    [self rebuildMenu];
}

#pragma mark - Settings delegate

- (void)settingsDidChange {
    [self scheduleTimer];
    [self updateButton];
    [self rebuildMenu];
    [self refreshForced:YES];
}

@end
