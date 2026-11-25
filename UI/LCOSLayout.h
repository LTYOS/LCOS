#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

extern NSNotificationName const LCOSLayoutDidChangeNotification;

@interface LCOSLayout : NSObject
+ (NSDictionary<NSString *, NSNumber *> *)values;
+ (CGFloat)value:(NSString *)key;
+ (void)setValue:(CGFloat)value forKey:(NSString *)key;
+ (void)reset;
+ (NSString *)summary;
@end
