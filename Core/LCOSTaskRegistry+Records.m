#import "LCOSTaskRegistry+Private.h"
#import "LCOSLogManager.h"
#import <objc/message.h>

@implementation LCOSTaskRegistry (Records)

- (LCOSTaskRecord *)recordForTask:(UIView *)view {
    for (LCOSTaskRecord *record in self.records) {
        if (record.view == view) return record;
    }
    return nil;
}

- (void)unregisterTaskWithUUID:(NSString *)uuid {
    if (![uuid isKindOfClass:NSString.class]) return;
    for (LCOSTaskRecord *record in [self.records copy]) {
        if ([record.uuid isEqualToString:uuid]) {
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: explicit host removal %@", uuid]];
            [self unregisterTask:record.view];
        }
    }
}

- (void)unregisterTaskWithController:(UIViewController *)controller {
    if (!controller) return;
    for (LCOSTaskRecord *record in [self.records copy]) {
        if (record.controller == controller) {
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: verified exit callback UUID=%@", record.uuid ?: @"pending"]];
            [self unregisterTask:record.view];
        }
    }
}

- (void)unregisterTask:(UIView *)view {
    LCOSTaskRecord *record = [self recordForTask:view];
    if (record) [self.records removeObject:record];
    [self.pendingPresentations removeObjectForKey:[self pendingKeyForTask:view]];
    if (self.activeNativeTask == view) self.activeNativeTask = nil;
    if (self.activeLCOSTask == view) self.activeLCOSTask = nil;
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Task: task removed"];
}

- (NSArray<UIView *> *)runningTasksFromLCOS:(BOOL)fromLCOS {
    NSMutableArray<UIView *> *tasks = [NSMutableArray array];
    NSUInteger retained = 0;
    for (LCOSTaskRecord *record in [self.records copy]) {
        if (record.fromLCOS != fromLCOS) continue;
        retained++;
        UIView *view = record.view;
        if (!view) {
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: view unavailable, record retained UUID=%@", record.uuid ?: @"pending"]];
            continue;
        }
        if (!record.controller) {
            [[LCOSLogManager sharedManager] forceLog:@"LCOS Task: controller unavailable, record retained"];
            continue;
        }
        if ([self isRunning:view]) [tasks addObject:view];
        else [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: not running yet, record retained UUID=%@", record.uuid ?: @"pending"]];
    }
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: query %@ retained=%lu running=%lu", fromLCOS ? @"LCOSShell" : @"NativeShell", (unsigned long)retained, (unsigned long)tasks.count]];
    return tasks;
}

- (UIView *)activeTaskFromLCOS:(BOOL)fromLCOS {
    UIView *view = fromLCOS ? self.activeLCOSTask : self.activeNativeTask;
    return [self isRunning:view] ? view : nil;
}

- (void)activateTask:(UIView *)view fromLCOS:(BOOL)fromLCOS {
    if (fromLCOS) self.activeLCOSTask = view;
    else self.activeNativeTask = view;
    for (UIView *other in [self runningTasksFromLCOS:fromLCOS]) {
        if (other != view) { other.hidden = YES; other.alpha = 0; }
    }
}

- (BOOL)closeTask:(UIView *)view {
    id controller = [self controllerForTask:view];
    SEL close = NSSelectorFromString(@"closeWindow");
    if (![controller respondsToSelector:close]) return NO;
    [self unregisterTask:view];
    ((void (*)(id, SEL))objc_msgSend)(controller, close);
    return YES;
}

- (BOOL)hasRunningTasksFromLCOS:(BOOL)fromLCOS {
    return [self runningTasksFromLCOS:fromLCOS].count > 0;
}

@end
