#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSBMenuBarIcon : NSObject
/// fraction: 0..1 — доля израсходованного бюджета. Отрицательное значение — бюджет не задан.
+ (NSColor *)colorForSpendFraction:(double)fraction;
+ (NSImage *)imageWithFractions:(NSArray<NSNumber *> *)fractions error:(BOOL)hasError;
@end

NS_ASSUME_NONNULL_END
