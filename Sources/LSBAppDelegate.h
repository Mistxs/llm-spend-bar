#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSBAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
/// Служебный режим: собрать меню и напечатать его содержимое.
- (void)dumpMenuToStandardOutput;
@end

NS_ASSUME_NONNULL_END
