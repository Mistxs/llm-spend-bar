#import <Cocoa/Cocoa.h>

#import "LSBAppDelegate.h"
#import "LSBSettings.h"

void LSBSelfTestRun(NSString *path);
void LSBPreviewRun(NSString *path);
void LSBScanRun(BOOL printSummary);
void LSBDashboardJSONRun(NSString *path);

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];

        if ([arguments containsObject:@"--demo"]) {
            setenv("LSB_DEMO", "1", 1);
        }
        if ([arguments containsObject:@"--settings"]) {
            setenv("LSB_OPEN_SETTINGS", "1", 1);
        }
        if ([arguments containsObject:@"--dashboard"]) {
            setenv("LSB_OPEN_DASHBOARD", "1", 1);
        }

        if ([arguments containsObject:@"--scan"]) {
            LSBScanRun(YES);
            return 0;
        }

        NSUInteger dashboardJSONIndex = [arguments indexOfObject:@"--dashboard-json"];
        if (dashboardJSONIndex != NSNotFound && dashboardJSONIndex + 1 < arguments.count) {
            LSBDashboardJSONRun(arguments[dashboardJSONIndex + 1]);
            return 0;
        }

        NSUInteger selfTestIndex = [arguments indexOfObject:@"--self-test"];
        if (selfTestIndex != NSNotFound && selfTestIndex + 1 < arguments.count) {
            LSBSelfTestRun(arguments[selfTestIndex + 1]);
            return 0;
        }

        NSUInteger previewIndex = [arguments indexOfObject:@"--icon-preview"];
        if (previewIndex != NSNotFound && previewIndex + 1 < arguments.count) {
            LSBPreviewRun(arguments[previewIndex + 1]);
            return 0;
        }

        if ([arguments containsObject:@"--dump-menu"]) {
            NSApplication *application = [NSApplication sharedApplication];
            (void)application;
            LSBAppDelegate *delegate = [LSBAppDelegate new];
            [delegate dumpMenuToStandardOutput];
            return 0;
        }

        NSApplication *application = [NSApplication sharedApplication];
        static LSBAppDelegate *delegate;
        delegate = [LSBAppDelegate new];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application run];
        return 0;
    }
}
