#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol LSBSettingsWindowDelegate <NSObject>
- (void)settingsDidChange;
@end

@interface LSBSettingsWindowController : NSWindowController
@property (nonatomic, weak, nullable) id<LSBSettingsWindowDelegate> delegate;
- (void)showSettings;
@end

NS_ASSUME_NONNULL_END
