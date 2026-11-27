#import "LCOSTaskRegistry.h"
#import "LCOSLogManager.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface LCOSTaskRecord : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, assign) BOOL fromLCOS;
@end
@implementation LCOSTaskRecord
@end

static void (*orig_addRunningApp)(id, SEL, NSString *, NSString *, UIView *);
static void (*orig_removeRunningApp)(id, SEL, NSString *);
static void LCOSAddRunningApp(id self, SEL _cmd, NSString *name, NSString *uuid, UIView *view);
static void LCOSRemoveRunningApp(id self, SEL _cmd, NSString *uuid);

@interface LCOSTaskRegistry ()
@property (nonatomic, strong) NSMutableArray<LCOSTaskRecord *> *records;
@property (nonatomic, weak) UIView *activeNativeTask;
@property (nonatomic, weak) UIView *activeLCOSTask;
@property (nonatomic, assign) BOOL hooksInstalled;
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
    NSString *name = fromLCOS ? @"lcosShell" : @"nativeShell";
    id controller = ((id (*)(id, SEL))objc_msgSend)(shared, NSSelectorFromString(name.UTF8String));
    if ([controller respondsToSelector:@selector(presentTask:)])
        ((void (*)(id, SEL, UIView *))objc_msgSend)(controller, @selector(presentTask:), view);
}

static void LCOSRemoveRunningApp(id self, SEL _cmd, NSString *uuid) {
    if (orig_removeRunningApp) orig_removeRunningApp(self, _cmd, uuid);
}

- (id)controllerForTask:(UIView *)view {
    if (![view isKindOfClass:UIView.class]) return nil;
    Class decorated = LCOSSwiftClass(@"DecoratedAppSceneViewController");
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

- (BOOL)isRunning:(UIView *)view {
    @try {
        id controller = [self controllerForTask:view];
        SEL sceneSelector = NSSelectorFromString(@"appSceneVC");
        if (![controller respondsToSelector:sceneSelector]) return NO;
        id scene = ((id (*)(id, SEL))objc_msgSend)(controller, sceneSelector);
        SEL running = NSSelectorFromString(@"isAppRunning");
        return scene && [scene respondsToSelector:running] && ((BOOL (*)(id, SEL))objc_msgSend)(scene, running);
    } @catch (NSException *exception) {
        return NO;
    }
}

- (BOOL)isTaskRunning:(UIView *)view {
    return [self isRunning:view];
}

- (void)registerTask:(UIView *)view fromLCOS:(BOOL)fromLCOS {
    if (![view isKindOfClass:UIView.class]) return;
    for (LCOSTaskRecord *record in self.records) {
        if (record.view == view) {
            [self activateTask:view fromLCOS:record.fromLCOS];
            return;
        }
    }
    LCOSTaskRecord *record = [[LCOSTaskRecord alloc] init];
    record.view = view;
    record.fromLCOS = fromLCOS;
    [self.records addObject:record];
    [self activateTask:view fromLCOS:fromLCOS];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
        @"LCOS Task: registered %@ in %@", view.class, fromLCOS ? @"LCOSShell" : @"NativeShell"]];
}

- (NSArray<UIView *> *)runningTasksFromLCOS:(BOOL)fromLCOS {
    NSMutableArray<UIView *> *tasks = [NSMutableArray array];
    for (LCOSTaskRecord *record in [self.records copy]) {
        UIView *view = record.view;
        if (!view || ![self isRunning:view]) { [self.records removeObject:record]; continue; }
        if (record.fromLCOS == fromLCOS) [tasks addObject:view];
    }
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
    for (LCOSTaskRecord *record in [self.records copy]) {
        if (record.view == view) [self.records removeObject:record];
    }
    if (self.activeNativeTask == view) self.activeNativeTask = nil;
    if (self.activeLCOSTask == view) self.activeLCOSTask = nil;
    ((void (*)(id, SEL))objc_msgSend)(controller, close);
    return YES;
}

- (BOOL)hasRunningTasksFromLCOS:(BOOL)fromLCOS {
    return [self runningTasksFromLCOS:fromLCOS].count > 0;
}

@end
