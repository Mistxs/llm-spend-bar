#import <Foundation/Foundation.h>
#import "LSBModels.h"
#import "LSBLocalEvent.h"

NS_ASSUME_NONNULL_BEGIN

@interface LSBStore : NSObject
@property (nonatomic, readonly) NSString *databasePath;
@property (nonatomic, readonly) NSString *jsonlPath;
@property (nonatomic, readonly) NSString *directory;

- (instancetype)initWithDirectory:(NSString *)directory;
- (BOOL)open:(NSError **)error;
- (void)close;

- (BOOL)upsertEvents:(NSArray<LSBLocalEvent *> *)events error:(NSError **)error;
- (NSInteger)eventCount;
- (nullable LSBSummary *)summaryAt:(NSDate *)now;
- (NSDictionary *)dashboardSnapshotForPeriod:(NSString *)period now:(NSDate *)now;
- (NSArray<NSDictionary *> *)dailySeriesFrom:(NSDate *)start to:(NSDate *)end;
- (NSArray<NSDictionary *> *)heatmapFrom:(NSDate *)start to:(NSDate *)end;
- (NSArray<LSBGroupSpend *> *)groupsBy:(NSString *)field start:(NSDate *)start end:(NSDate *)end limit:(NSInteger)limit;
- (NSArray<LSBSessionSpend *> *)sessionsFrom:(NSDate *)start to:(NSDate *)end limit:(NSInteger)limit;

- (BOOL)fileUnchanged:(NSString *)path mtime:(double)mtime size:(long long)size;
- (void)recordFile:(NSString *)path mtime:(double)mtime size:(long long)size;
- (BOOL)hasEventID:(NSString *)eventID;
@end

NS_ASSUME_NONNULL_END
