#import "LCOSLayout.h"
#import <math.h>

NSNotificationName const LCOSLayoutDidChangeNotification = @"LCOSLayoutDidChangeNotification";
static NSString *const kPrefix = @"LCOSLayout.";

static NSDictionary<NSString *, NSNumber *> *LCOSDefaults(void) {
    return @{ @"iconSize": @60, @"cornerRadius": @14, @"labelGap": @3,
              @"topInset": @80, @"bottomInset": @20, @"rowSpacing": @20,
              @"columnSpacing": @8, @"pageSize": @8, @"pageOffset": @0 };
}

@implementation LCOSLayout

+ (BOOL)getMinimum:(CGFloat *)minimum maximum:(CGFloat *)maximum forKey:(NSString *)key {
    NSDictionary<NSString *, NSArray<NSNumber *> *> *ranges = @{
        @"iconSize": @[@40, @100], @"cornerRadius": @[@0, @30],
        @"labelGap": @[@0, @24], @"topInset": @[@0, @200],
        @"bottomInset": @[@0, @120], @"rowSpacing": @[@0, @60],
        @"columnSpacing": @[@0, @60], @"pageSize": @[@4, @16],
        @"pageOffset": @[@-60, @60]
    };
    NSArray<NSNumber *> *range = ranges[key];
    if (!range) return NO;
    *minimum = range[0].doubleValue;
    *maximum = range[1].doubleValue;
    return YES;
}

+ (CGFloat)sanitizedValue:(CGFloat)value forKey:(NSString *)key {
    CGFloat minimum = 0, maximum = 0;
    if (![self getMinimum:&minimum maximum:&maximum forKey:key] || !isfinite(value)) {
        return [LCOSDefaults()[key] doubleValue];
    }
    return MIN(maximum, MAX(minimum, value));
}

+ (NSDictionary<NSString *,NSNumber *> *)values {
    NSMutableDictionary *values = [LCOSDefaults() mutableCopy];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in values) {
        NSString *storedKey = [kPrefix stringByAppendingString:key];
        if ([defaults objectForKey:storedKey]) {
            values[key] = @([self sanitizedValue:[defaults doubleForKey:storedKey] forKey:key]);
        }
    }
    return values;
}
+ (CGFloat)value:(NSString *)key { return [self values][key].doubleValue; }
+ (void)setValue:(CGFloat)value forKey:(NSString *)key {
    if (!LCOSDefaults()[key]) return;
    [NSUserDefaults.standardUserDefaults setDouble:[self sanitizedValue:value forKey:key]
                                            forKey:[kPrefix stringByAppendingString:key]];
    [NSNotificationCenter.defaultCenter postNotificationName:LCOSLayoutDidChangeNotification object:nil];
}
+ (void)reset {
    for (NSString *key in LCOSDefaults()) [NSUserDefaults.standardUserDefaults removeObjectForKey:[kPrefix stringByAppendingString:key]];
    [NSNotificationCenter.defaultCenter postNotificationName:LCOSLayoutDidChangeNotification object:nil];
}
+ (NSString *)summary {
    NSDictionary *v = self.values;
    return [NSString stringWithFormat:@"iconSize=%.1f, cornerRadius=%.1f, labelGap=%.1f, topInset=%.1f, bottomInset=%.1f, rowSpacing=%.1f, columnSpacing=%.1f, pageSize=%.1f, pageOffset=%.1f",
        [v[@"iconSize"] doubleValue], [v[@"cornerRadius"] doubleValue], [v[@"labelGap"] doubleValue],
        [v[@"topInset"] doubleValue], [v[@"bottomInset"] doubleValue], [v[@"rowSpacing"] doubleValue],
        [v[@"columnSpacing"] doubleValue], [v[@"pageSize"] doubleValue], [v[@"pageOffset"] doubleValue]];
}
@end
