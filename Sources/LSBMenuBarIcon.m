#import "LSBMenuBarIcon.h"

@implementation LSBMenuBarIcon

+ (NSColor *)colorForSpendFraction:(double)fraction {
    if (fraction < 0) return [NSColor secondaryLabelColor];
    if (fraction >= 0.8) return [NSColor systemRedColor];
    if (fraction >= 0.5) return [NSColor systemOrangeColor];
    return [NSColor systemGreenColor];
}

+ (NSImage *)imageWithFractions:(NSArray<NSNumber *> *)fractions error:(BOOL)hasError {
    NSSize size = NSMakeSize(23, 18);
    NSImage *image = [NSImage imageWithSize:size
                                    flipped:NO
                             drawingHandler:^BOOL(NSRect destinationRect) {
        (void)destinationRect;
        CGFloat barWidth = 5;
        CGFloat gap = 3;
        CGFloat height = 14;
        CGFloat totalWidth = barWidth * 3 + gap * 2;
        CGFloat startX = (size.width - totalWidth) / 2;
        CGFloat startY = (size.height - height) / 2;

        for (NSInteger index = 0; index < 3; index++) {
            CGFloat x = startX + (CGFloat)index * (barWidth + gap);
            NSRect background = NSMakeRect(x, startY, barWidth, height);
            [[[NSColor labelColor] colorWithAlphaComponent:0.22] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:background xRadius:1.5 yRadius:1.5] fill];

            if (index >= (NSInteger)fractions.count) continue;
            double fraction = fractions[(NSUInteger)index].doubleValue;

            if (fraction < 0) {
                // Бюджет не задан: нейтральная короткая заливка, чтобы полоска не выглядела пустой.
                NSRect neutral = NSMakeRect(x, startY, barWidth, 5);
                [[[NSColor labelColor] colorWithAlphaComponent:0.45] setFill];
                [[NSBezierPath bezierPathWithRoundedRect:neutral xRadius:1.5 yRadius:1.5] fill];
                continue;
            }

            double clamped = MIN(1, MAX(0, fraction));
            if (clamped <= 0.02) continue;
            CGFloat fillHeight = MAX(1.5, height * clamped);
            NSRect fill = NSMakeRect(x, startY, barWidth, fillHeight);
            [[self colorForSpendFraction:fraction] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:1.5 yRadius:1.5] fill];
        }

        if (hasError) {
            NSRect dot = NSMakeRect(size.width - 4.5, size.height - 4.5, 4.5, 4.5);
            [[NSColor systemRedColor] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
        return YES;
    }];

    image.template = NO;
    image.accessibilityDescription = @"Расход LLM за день, неделю и месяц";
    return image;
}

@end
