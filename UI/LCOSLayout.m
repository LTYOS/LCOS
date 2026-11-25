#import "LCOSLayout.h"

NSNotificationName const LCOSLayoutDidChangeNotification = @"LCOSLayoutDidChangeNotification";
static NSString *const kPrefix = @"LCOSLayout.";

static NSDictionary<NSString *, NSNumber *> *LCOSDefaults(void) {
    return @{ @"iconSize": @60, @"cornerRadius": @14, @"labelGap": @3,
              @"topInset": @80, @"bottomInset": @20, @"rowSpacing": @20,
              @"columnSpacing": @8, @"pageSize": @8, @"pageOffset": @0 };
}

@implementation LCOSLayout
+ (NSDictionary<NSString *,NSNumber *> *)values {
    NSMutableDictionary *values = [LCOSDefaults() mutableCopy];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in values) {
        NSString *storedKey = [kPrefix stringByAppendingString:key];
        if ([defaults objectForKey:storedKey]) values[key] = @([defaults doubleForKey:storedKey]);
    }
    return values;
}
+ (CGFloat)value:(NSString *)key { return [self values][key].doubleValue; }
+ (void)setValue:(CGFloat)value forKey:(NSString *)key {
    if (!LCOSDefaults()[key]) return;
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:[kPrefix stringByAppendingString:key]];
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
