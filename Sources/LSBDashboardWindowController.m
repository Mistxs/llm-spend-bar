#import "LSBDashboardWindowController.h"
#import <WebKit/WebKit.h>
#import "LSBSettings.h"

@interface LSBDashboardWindowController () <WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) LSBStore *store;
@property (nonatomic, strong) NSDictionary *pendingSnapshot;
@property (nonatomic, copy) NSString *period;
@property (nonatomic) BOOL loaded;
@end

@implementation LSBDashboardWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1120, 780)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"LLM Spend — аналитика";
    window.minSize = NSMakeSize(860, 600);
    window.releasedWhenClosed = NO;
    window.titlebarAppearsTransparent = YES;
    window.backgroundColor = [NSColor colorWithCalibratedWhite:0.07 alpha:1.0];
    window.delegate = self;
    window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
    self = [super initWithWindow:window];
    if (self) {
        _period = @"month";
        [self buildWebView];
    }
    return self;
}

- (void)buildWebView {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    WKUserContentController *controller = [WKUserContentController new];
    [controller addScriptMessageHandler:self name:@"llmSpend"];
    configuration.userContentController = controller;

    _webView = [[WKWebView alloc] initWithFrame:self.window.contentView.bounds configuration:configuration];
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _webView.navigationDelegate = self;
    _webView.allowsBackForwardNavigationGestures = NO;
    _webView.allowsMagnification = YES;
    if (@available(macOS 12.0, *)) {
        _webView.underPageBackgroundColor = [NSColor colorWithCalibratedWhite:0.07 alpha:1.0];
    }
    [self.window.contentView addSubview:_webView];

    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html" subdirectory:@"dashboard"];
    if (url) {
        [_webView loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
    }
}

- (void)showDashboardWithStore:(LSBStore *)store {
    self.store = store;
    if (!self.loaded && self.webView.URL == nil) {
        [self buildWebView];
    }
    NSScreen *screen = [NSScreen mainScreen];
    NSRect visible = screen.visibleFrame;
    NSRect frame = self.window.frame;
    frame.origin.x = visible.origin.x + (visible.size.width - frame.size.width) / 2.0;
    frame.origin.y = visible.origin.y + (visible.size.height - frame.size.height) / 2.0;
    [self.window setFrame:frame display:YES];
    [self.window setIsVisible:YES];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
    [self.window makeKeyWindow];
    if (store) {
        self.pendingSnapshot = [store dashboardSnapshotForPeriod:self.period now:[NSDate date]];
        [self flushPendingSnapshot];
    }
}

- (void)updateWithSnapshot:(NSDictionary *)snapshot {
    self.pendingSnapshot = snapshot;
    [self flushPendingSnapshot];
}

- (void)flushPendingSnapshot {
    if (!self.loaded || !self.pendingSnapshot) return;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.pendingSnapshot options:0 error:&error];
    if (!data) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *script = [NSString stringWithFormat:@"window.llmSpend && window.llmSpend.render(%@);", json];
    [self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.loaded = YES;
    [self flushPendingSnapshot];
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *body = message.body;
    NSString *action = body[@"action"];
    if ([action isEqualToString:@"setPeriod"]) {
        NSString *period = body[@"period"];
        if ([period isKindOfClass:[NSString class]]) {
            self.period = period;
            if (self.store) {
                self.pendingSnapshot = [self.store dashboardSnapshotForPeriod:period now:[NSDate date]];
                [self flushPendingSnapshot];
            }
        }
    } else if ([action isEqualToString:@"scan"]) {
        [self.delegate dashboardDidRequestScan];
    } else if ([action isEqualToString:@"settings"]) {
        [self.delegate dashboardDidRequestSettings];
    } else if ([action isEqualToString:@"dataFolder"]) {
        [self.delegate dashboardDidRequestDataFolder];
    } else if ([action isEqualToString:@"saveSettings"]) {
        NSDictionary *settings = body[@"settings"];
        if ([settings isKindOfClass:[NSDictionary class]]) {
            if (settings[@"daily"]) [LSBSettings setDailyBudget:[settings[@"daily"] doubleValue]];
            if (settings[@"weekly"]) [LSBSettings setWeeklyBudget:[settings[@"weekly"] doubleValue]];
            if (settings[@"monthly"]) [LSBSettings setMonthlyBudget:[settings[@"monthly"] doubleValue]];
            if (settings[@"scanInterval"]) [LSBSettings setScanInterval:[settings[@"scanInterval"] doubleValue]];
            [self.delegate dashboardDidRequestScan];
            if (self.store) {
                self.pendingSnapshot = [self.store dashboardSnapshotForPeriod:self.period now:[NSDate date]];
                [self flushPendingSnapshot];
            }
        }
    }
}

@end
