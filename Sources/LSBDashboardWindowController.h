#import <Cocoa/Cocoa.h>
#import "LSBStore.h"

NS_ASSUME_NONNULL_BEGIN

@protocol LSBDashboardDelegate <NSObject>
- (void)dashboardDidRequestScan;
- (void)dashboardDidRequestSettings;
- (void)dashboardDidRequestDataFolder;
@end

@interface LSBDashboardWindowController : NSWindowController
@property (nonatomic, weak, nullable) id<LSBDashboardDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *currentPeriod;
- (void)showDashboardWithStore:(LSBStore *)store;
- (void)updateWithSnapshot:(NSDictionary *)snapshot;
@end

NS_ASSUME_NONNULL_END
