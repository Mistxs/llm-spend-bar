#import <Foundation/Foundation.h>
#import "LSBModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface LSBApiClient : NSObject
@property (nonatomic, readonly) NSURL *baseURL;
@property (nonatomic, readonly, copy) NSString *apiKey;
- (instancetype)initWithBaseURL:(NSURL *)baseURL apiKey:(nullable NSString *)apiKey;
- (BOOL)checkHealthWithError:(NSError * _Nullable * _Nullable)error;
- (nullable LSBSummary *)fetchSummaryWithError:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
