#import <Foundation/Foundation.h>
#import "LSBStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface LSBScanResult : NSObject
@property (nonatomic) NSInteger filesScanned;
@property (nonatomic) NSInteger eventsFound;
@property (nonatomic) NSInteger eventsWritten;
@property (nonatomic, copy) NSArray<NSString *> *warnings;
@end

@interface LSBCollector : NSObject
- (instancetype)initWithStore:(LSBStore *)store;
- (LSBScanResult *)scanWithError:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
