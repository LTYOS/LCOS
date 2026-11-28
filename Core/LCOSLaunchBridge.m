#import "LCOSLaunchBridge.h"
#import <objc/message.h>

NSString *const LCOSNativeInteractionPreferenceKey = @"LCOSNativeNavigationEnabled";

static NSString *LCOSGroupFile(NSString *name) {
    Class sharedUtils = NSClassFromString(@"LCSharedUtils");
    SEL selector = NSSelectorFromString(@"appGroupPath");
    if (![sharedUtils respondsToSelector:selector]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(sharedUtils, selector);
    NSString *path = [value isKindOfClass:NSURL.class] ? [value path] : [value isKindOfClass:NSString.class] ? value : nil;
    return path.length ? [[path stringByAppendingPathComponent:@"LiveContainer"] stringByAppendingPathComponent:name] : nil;
}

static NSMutableDictionary *LCOSPreferences(void) {
    NSString *path = LCOSGroupFile(@"LCOSPreferences.plist");
    NSDictionary *saved = path.length ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    return [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

BOOL LCOSNativeInteractionEnabled(void) {
    NSString *path = LCOSGroupFile(@"LCOSPreferences.plist");
    NSDictionary *preferences = path.length ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    NSNumber *value = [preferences isKindOfClass:NSDictionary.class] ? preferences[LCOSNativeInteractionPreferenceKey] : nil;
    return value ? value.boolValue : YES;
}

void LCOSSetNativeInteractionEnabled(BOOL enabled) {
    NSMutableDictionary *preferences = LCOSPreferences();
    preferences[LCOSNativeInteractionPreferenceKey] = @(enabled);
    NSString *path = LCOSGroupFile(@"LCOSPreferences.plist");
    if (path.length) [preferences writeToFile:path atomically:YES];
}

void LCOSRecordLaunchSource(NSString *uuid, BOOL fromLCOS) {
    if (!fromLCOS || uuid.length == 0) return;
    NSString *path = LCOSGroupFile(@"LCOSLaunchSource.plist");
    if (path.length) [@{@"source": @"lcos", @"uuid": uuid, @"timestamp": @([NSDate date].timeIntervalSince1970)} writeToFile:path atomically:YES];
}

NSNumber *LCOSConsumeLaunchSource(NSString *uuid) {
    NSString *path = LCOSGroupFile(@"LCOSLaunchSource.plist");
    if (!path.length || !uuid.length) return nil;
    NSDictionary *source = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![source isKindOfClass:NSDictionary.class] || ![source[@"uuid"] isEqualToString:uuid] ||
        fabs([NSDate date].timeIntervalSince1970 - [source[@"timestamp"] doubleValue]) > 120 ||
        ![source[@"source"] isEqualToString:@"lcos"]) return nil;
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    return @YES;
}
