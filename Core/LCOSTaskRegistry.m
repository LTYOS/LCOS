#import "LCOSTaskRegistry.h"
#import "LCOSLogManager.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface LCOSTaskRecord : NSObject
@property (nonatomic, weak) UIView *view;
// A verified controller owns the task lifetime. The view's private delegate
// can temporarily disappear during scene/layout transitions.
@property (nonatomic, strong) UIViewController *controller;
@property (nonatomic, assign) BOOL fromLCOS;
@property (nonatomic, copy) NSString *uuid;
@end
@implementation LCOSTaskRecord
@end

static void (*orig_addRunningApp)(id, SEL, NSString *, NSString *, UIView *);
static void (*orig_removeRunningApp)(id, SEL, NSString *);
static void (*orig_appDidExit)(id, SEL, id);
static void LCOSAddRunningApp(id self, SEL _cmd, NSString *name, NSString *uuid, UIView *view);
static void LCOSRemoveRunningApp(id self, SEL _cmd, NSString *uuid);
static void LCOSAppDidExit(id self, SEL _cmd, id scene);

@interface LCOSTaskRegistry ()
@property (nonatomic, strong) NSMutableArray<LCOSTaskRecord *> *records;
@property (nonatomic, weak) UIView *activeNativeTask;
@property (nonatomic, weak) UIView *activeLCOSTask;
@property (nonatomic, assign) BOOL hooksInstalled;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSNumber *> *pendingPresentations;
@end

@implementation LCOSTaskRegistry

+ (instancetype)shared {
    static LCOSTaskRegistry *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ registry = [[self alloc] init]; });
    return registry;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _records = [NSMutableArray array];
        _pendingPresentations = [NSMutableDictionary dictionary];
        [self installHooksIfPossible];
    }
    return self;
}

static Class LCOSSwiftClass(NSString *name) {
    return NSClassFromString(name) ?: NSClassFromString([@"LiveContainerSwiftUI." stringByAppendingString:name]);
}

- (void)installHooksIfPossible {
    if (self.hooksInstalled || !NSThread.isMainThread) return;
    Class dock = LCOSSwiftClass(@"MultitaskDockManager");
    if (!dock) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self installHooksIfPossible];
        });
        return;
    }
    @try {
        Method add = class_getInstanceMethod(dock, @selector(addRunningApp:appUUID:view:));
        Method remove = class_getInstanceMethod(dock, @selector(removeRunningApp:));
        if (add) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(add)];
            if (signature.numberOfArguments == 5 && signature.methodReturnType[0] == 'v') {
                orig_addRunningApp = (void *)method_getImplementation(add);
                method_setImplementation(add, (IMP)LCOSAddRunningApp);
            }
        }
        if (remove) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(remove)];
            if (signature.numberOfArguments == 3 && signature.methodReturnType[0] == 'v') {
                orig_removeRunningApp = (void *)method_getImplementation(remove);
                method_setImplementation(remove, (IMP)LCOSRemoveRunningApp);
            }
        }
        Class decorated = LCOSSwiftClass(@"DecoratedAppSceneViewController");
        Method exit = class_getInstanceMethod(decorated, @selector(appSceneVCAppDidExit:));
        if (exit) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(exit)];
            if (signature.numberOfArguments == 3 && signature.methodReturnType[0] == 'v') {
                orig_appDidExit = (void *)method_getImplementation(exit);
                method_setImplementation(exit, (IMP)LCOSAppDidExit);
            }
        }
        self.hooksInstalled = YES;
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Task: verified runtime hooks installed"];
    } @catch (NSException *exception) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: hook setup skipped: %@", exception.name]];
    }
}

static void LCOSAddRunningApp(id self, SEL _cmd, NSString *name, NSString *uuid, UIView *view) {
    if (orig_addRunningApp) orig_addRunningApp(self, _cmd, name, uuid, view);
    if (![view isKindOfClass:UIView.class]) return;
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: host callback %@", view.class]];
    Class core = NSClassFromString(@"LCOSCore");
    id shared = ((id (*)(id, SEL))objc_msgSend)(core, @selector(sharedInstance));
    BOOL fromLCOS = NO;
    if ([shared respondsToSelector:NSSelectorFromString(@"isLauncherVisible")])
        fromLCOS = ((BOOL (*)(id, SEL))objc_msgSend)(shared, NSSelectorFromString(@"isLauncherVisible"));
    [[LCOSTaskRegistry shared] registerTask:view fromLCOS:fromLCOS];
}

static void LCOSRemoveRunningApp(id self, SEL _cmd, NSString *uuid) {
    if (orig_removeRunningApp) orig_removeRunningApp(self, _cmd, uuid);
    [[LCOSTaskRegistry shared] unregisterTaskWithUUID:uuid];
}

static void LCOSAppDidExit(id self, SEL _cmd, id scene) {
    // This callback is the verified lifecycle exit, unlike a missing private
    // view delegate during a transition.
    [[LCOSTaskRegistry shared] unregisterTaskWithController:self];
    if (orig_appDidExit) orig_appDidExit(self, _cmd, scene);
}

- (id)controllerForTask:(UIView *)view {
    if (![view isKindOfClass:UIView.class]) return nil;
    LCOSTaskRecord *record = [self recordForTask:view];
    if (record.controller) return record.controller;
    Class decorated = NSClassFromString(@"DecoratedAppSceneViewController");
    SEL delegate = NSSelectorFromString(@"_viewDelegate");
    if ([view respondsToSelector:delegate]) {
        id controller = ((id (*)(id, SEL))objc_msgSend)(view, delegate);
        if (controller && (!decorated || [controller isKindOfClass:decorated])) return controller;
    }
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class] &&
            [responder respondsToSelector:NSSelectorFromString(@"appSceneVC")] &&
            (!decorated || [responder isKindOfClass:decorated])) return responder;
    }
    return nil;
}

- (id)sceneForRecord:(LCOSTaskRecord *)record {
    UIViewController *controller = record.controller;
    SEL sceneSelector = NSSelectorFromString(@"appSceneVC");
    if (![controller respondsToSelector:sceneSelector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(controller, sceneSelector);
    } @catch (NSException *exception) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: scene temporarily unavailable %@", record.uuid ?: @"pending"]];
        return nil;
    }
}

- (BOOL)isRunning:(UIView *)view {
    LCOSTaskRecord *record = [self recordForTask:view];
    if (!record) return NO;
    id scene = [self sceneForRecord:record];
    SEL running = NSSelectorFromString(@"isAppRunning");
    if (![scene respondsToSelector:running]) return NO;
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(scene, running);
    } @catch (NSException *exception) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: running check unavailable %@", record.uuid ?: @"pending"]];
        return NO;
    }
}

- (BOOL)isTaskRunning:(UIView *)view {
    return [self isRunning:view];
}

- (BOOL)registerTask:(UIView *)view fromLCOS:(BOOL)fromLCOS {
    if (![view isKindOfClass:UIView.class]) return NO;
    id controller = [self controllerForTask:view];
    if (!controller) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
            @"LCOS Task: rejected %@, no DecoratedAppSceneViewController", view.class]];
        return NO;
    }
    LCOSTaskRecord *existing = nil;
    for (LCOSTaskRecord *record in self.records) {
        if (record.view == view) { existing = record; break; }
    }
    if (!existing) {
        existing = [[LCOSTaskRecord alloc] init];
        existing.view = view;
        existing.fromLCOS = fromLCOS;
        [self.records addObject:existing];
    }
    existing.controller = controller;
    SEL uuidSelector = NSSelectorFromString(@"dataUUID");
    if ([controller respondsToSelector:uuidSelector]) {
        @try {
            id uuid = ((id (*)(id, SEL))objc_msgSend)(controller, uuidSelector);
            if ([uuid isKindOfClass:NSString.class]) existing.uuid = uuid;
        } @catch (NSException *exception) {
            [[LCOSLogManager sharedManager] forceLog:@"LCOS Task: UUID temporarily unavailable"];
        }
    }
    [self activateTask:view fromLCOS:fromLCOS];
    [self presentTaskWhenReady:view fromLCOS:fromLCOS attempt:0];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
        @"LCOS Task: verified %@ controller=%@ UUID=%@ in %@", view.class, [controller class],
        existing.uuid ?: @"pending", fromLCOS ? @"LCOSShell" : @"NativeShell"]];
    return YES;
}

- (NSValue *)pendingKeyForTask:(UIView *)view {
    return [NSValue valueWithNonretainedObject:view];
}

- (void)presentTaskWhenReady:(UIView *)view fromLCOS:(BOOL)fromLCOS attempt:(NSUInteger)attempt {
    if (![self recordForTask:view]) return;
    Class core = NSClassFromString(@"LCOSCore");
    id shared = ((id (*)(id, SEL))objc_msgSend)(core, @selector(sharedInstance));
    NSString *shellName = fromLCOS ? @"lcosShell" : @"nativeShell";
    id shell = ((id (*)(id, SEL))objc_msgSend)(shared, NSSelectorFromString(shellName));
    if (![shell respondsToSelector:@selector(presentTask:)]) return;
    NSValue *key = [self pendingKeyForTask:view];
    if ([self isRunning:view]) {
        [self.pendingPresentations removeObjectForKey:key];
        ((void (*)(id, SEL, UIView *))objc_msgSend)(shell, @selector(presentTask:), view);
        return;
    }
    if (attempt >= 30) {
        [self.pendingPresentations removeObjectForKey:key];
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Task: app did not reach running state"];
        return;
    }
    if (self.pendingPresentations[key]) return;
    self.pendingPresentations[key] = @YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.pendingPresentations removeObjectForKey:key];
        if (![self recordForTask:view]) return;
        [self presentTaskWhenReady:view fromLCOS:fromLCOS attempt:attempt + 1];
    });
}

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
