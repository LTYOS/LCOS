//
//  LCOSCore.m
//  LCOS.dylib
//

#import "LCOSCore+Private.h"
#import "LCOSGestureHandler.h"
#import "LCOSLogManager.h"
#import "LCOSAppModel.h"
#import "LCOSLayout.h"
#import <objc/runtime.h>
#import <objc/message.h>

static LCOSCore *_sharedInstance = nil;

// The global tweak folder is injected into every guest app too. LCOS UI is
// host-only until the future background/gesture layer explicitly opts in.
static BOOL LCOSIsLiveContainerHost(void) {
    SEL mainBundleSelector = NSSelectorFromString(@"lcMainBundle");
    SEL guestInfoSelector = NSSelectorFromString(@"guestAppInfo");
    if (![NSUserDefaults respondsToSelector:mainBundleSelector] ||
        ![NSUserDefaults respondsToSelector:guestInfoSelector]) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSBundle *hostBundle = [NSUserDefaults performSelector:mainBundleSelector];
    NSDictionary *guestInfo = [NSUserDefaults performSelector:guestInfoSelector];
#pragma clang diagnostic pop
    if (![hostBundle isKindOfClass:NSBundle.class]) return NO;
    return [hostBundle.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier] &&
           ![guestInfo isKindOfClass:NSDictionary.class];
}


// Hook UIWindow.makeKeyAndVisible: as soon as LiveContainer's native window
// becomes visible, synchronously restore the desktop so no native frame is shown.
static BOOL LCOSAutoRestoreEnabled(void);
static void (*orig_makeKeyAndVisible)(id self, SEL _cmd);
static void lcos_makeKeyAndVisible(id self, SEL _cmd) {
    if ([NSThread isMainThread]) {
        UIWindow *window = (UIWindow *)self;
        if (![window isKindOfClass:[LCOSPassThroughWindow class]]) {
            LCOSCore *core = [LCOSCore sharedInstance];
            if (!core.overlayWindow) [core initialize];
            if (LCOSAutoRestoreEnabled() && !core.isBackgroundVisible && [[NSUserDefaults standardUserDefaults] boolForKey:@"LCOSLauncherVisible"] && !core.isLauncherVisible) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (core.isLauncherVisible || core.isBackgroundVisible) return;
                    @try {
                        [core showLauncherImmediately];
                    } @catch (NSException *exception) {
                        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher: startup restore exception %@", exception.reason]];
                        [core cancelDockPreparation];
                    }
                });
            }
        }
    }
    if (orig_makeKeyAndVisible) orig_makeKeyAndVisible(self, _cmd);
}

static void LCOSRecordLaunchSource(id self, SEL _cmd, BOOL fromLCOS) {
    SEL groupSelector = NSSelectorFromString(@"appGroupPath");
    if (![self respondsToSelector:groupSelector]) return;
    NSURL *group = ((id (*)(id, SEL))objc_msgSend)(self, groupSelector);
    NSString *path = [group.path stringByAppendingPathComponent:@"LiveContainer/LCOSLaunchSource.plist"];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [@{@"source": fromLCOS ? @"lcos" : @"native"} writeToFile:path atomically:YES];
}

static void LCOSInstallLaunchSourceHook(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class utils = NSClassFromString(@"LCSharedUtils");
        class_addMethod(utils, NSSelectorFromString(@"lcosRecordLaunchSource:"), (IMP)LCOSRecordLaunchSource, "v@:B");
    });
}

@implementation LCOSCore

+ (void)load {
    // LCSharedUtils' host markers are not guaranteed to be initialized when
    // a tweak's +load runs. Defer the host/guest decision to UI initialization.
    [[LCOSLogManager sharedManager] forceLog:@"LCOS load: +load invoked"];
    static dispatch_once_t initializationToken;
    dispatch_once(&initializationToken, ^{
        // Swizzle makeKeyAndVisible to cover the native window before it renders.
        Method m = class_getInstanceMethod([UIWindow class], @selector(makeKeyAndVisible));
        if (m) {
            orig_makeKeyAndVisible = (void (*)(id, SEL))method_getImplementation(m);
            method_setImplementation(m, (IMP)lcos_makeKeyAndVisible);
        }
        // Initialize at the earliest scene connection, before SwiftUI renders.
        [NSNotificationCenter.defaultCenter addObserverForName:@"UISceneWillConnectNotification"
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification *note) {
            [[LCOSCore sharedInstance] initialize];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[LCOSCore sharedInstance] initialize];
        });
    });
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[LCOSCore alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: init"];
    }
    return self;
}

- (BOOL)hasValidWindowScene {
    if (@available(iOS 13.0, *)) {
        UIScene *scene = [UIApplication sharedApplication].connectedScenes.anyObject;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        return windowScene != nil;
    }
    return YES; // iOS 12 always valid
}

// Persistence key for launcher state
NSString *const kLCOSLauncherVisibleKey = @"LCOSLauncherVisible";
static NSString *const kLCOSAutoRestoreKey = @"LCOSAutoRestoreDesktop";

// Auto-restore defaults to YES unless explicitly disabled.
static BOOL LCOSAutoRestoreEnabled(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:kLCOSAutoRestoreKey] == nil) return YES;
    return [d boolForKey:kLCOSAutoRestoreKey];
}

- (void)saveLauncherState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.isLauncherVisible forKey:kLCOSLauncherVisibleKey];
    [defaults synchronize];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: Saved launcher state = %@", self.isLauncherVisible ? @"visible" : @"hidden"]];
}

- (BOOL)loadLauncherState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL wasVisible = [defaults boolForKey:kLCOSLauncherVisibleKey];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: Loaded launcher state = %@", wasVisible ? @"visible" : @"hidden"]];
    return wasVisible;
}

- (void)initialize {
    // Idempotent: scene notification + async + hook may all call this.
    if (self.overlayWindow) return;
    if (!LCOSIsLiveContainerHost()) {
        SEL guestInfoSelector = NSSelectorFromString(@"guestAppInfo");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id guestInfo = [NSUserDefaults respondsToSelector:guestInfoSelector] ?
            [NSUserDefaults performSelector:guestInfoSelector] : nil;
#pragma clang diagnostic pop
        if ([guestInfo isKindOfClass:NSDictionary.class]) {
            self.isGuestNavigation = YES;
            [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: guest app detected, enabling navigation only"];
        } else {
        // The host has no guestAppInfo. Wait for LiveContainerMain to publish
        // lcMainBundle rather than rejecting the host during early +load.
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: waiting for LiveContainer host initialization"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self initialize];
        });
        return;
        }
    }
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: initialize START"];
    if (!self.isGuestNavigation) { (void)[LCOSTaskRegistry shared]; LCOSInstallLaunchSourceHook(); }
    
    // Check if window scene is ready
    if (![self hasValidWindowScene]) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: No window scene yet, retrying in 1s"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self initialize];
        });
        return;
    }
    
    // Create pass-through overlay window (like LCOrbitOverlayManager)
    if (@available(iOS 13.0, *)) {
        UIScene *scene = [UIApplication sharedApplication].connectedScenes.anyObject;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene) {
            self.overlayWindow = [[LCOSPassThroughWindow alloc] initWithWindowScene:windowScene];
            self.overlayWindow.frame = windowScene.coordinateSpace.bounds;
            self.overlayWindow.backgroundColor = [UIColor clearColor];
            self.overlayWindow.windowLevel = UIWindowLevelNormal + 100; // Above LiveContainer
            self.overlayWindow.hidden = YES;
            
            // Root view controller to host UI
            UIViewController *rootVC = [[UIViewController alloc] init];
            rootVC.view.backgroundColor = [UIColor clearColor];
            self.overlayWindow.rootViewController = rootVC;
            
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: overlayWindow created level=%ld", (long)self.overlayWindow.windowLevel]];
        }
    } else {
        // iOS 12 fallback
        self.overlayWindow = [[LCOSPassThroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self.overlayWindow.backgroundColor = [UIColor clearColor];
        self.overlayWindow.windowLevel = UIWindowLevelNormal + 100;
        self.overlayWindow.hidden = YES;
        
        UIViewController *rootVC = [[UIViewController alloc] init];
        rootVC.view.backgroundColor = [UIColor clearColor];
        self.overlayWindow.rootViewController = rootVC;
        
    }
    
    // Guest apps get only the navigation layer; never restore the host desktop here.
    [self registerGesturesOnOverlayWindow];
    if (!self.isGuestNavigation) [self installNativeDockGestureIfNeeded];
    self.nativeShell = [[LCOSShellController alloc] initWithOverlay:self.overlayWindow fromLCOS:NO];
    self.lcosShell = [[LCOSShellController alloc] initWithOverlay:self.overlayWindow fromLCOS:YES];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(layoutRadiusChanged) name:LCOSLayoutDidChangeNotification object:nil];
    [self updateInteractionState];
    
    // Restore launcher state: if auto-restore enabled and was visible, show immediately
    BOOL wasVisible = !self.isGuestNavigation && LCOSAutoRestoreEnabled() && [self loadLauncherState];
    if (wasVisible) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Restoring launcher state - showing launcher immediately"];
        [self showLauncherImmediately];
    }
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: initialize COMPLETE"];
}

// Register gesture recognizers on overlay window (three-finger long press for settings)

// Handle three-finger long press on overlay window





- (void)updateInteractionState {
    self.nativeDockGesture.enabled = self.dockTransitionActive || (!self.isLauncherVisible && !self.isBackgroundVisible);
    self.launcherDismissGesture.enabled = self.isLauncherVisible && !self.dockTransitionActive && !self.isBackgroundVisible;
    self.rightEdgeZone.hidden = YES;
    self.navigationBar.hidden = YES;
    [self.nativeShell updateNavigation];
    [self.lcosShell updateNavigation];
    ((LCOSPassThroughWindow *)self.overlayWindow).backgroundView = self.nativeShell.isBackgroundVisible ? self.nativeShell.backgroundView : self.lcosShell.backgroundView;
    ((LCOSPassThroughWindow *)self.overlayWindow).navigationTouchZone = self.navigationTouchZone;
    self.overlayWindow.hidden = NO;
}



- (void)setLauncherView:(LCOSLauncherView *)launcherView {
    // This property owns the controller. Forward only its view to the shell;
    // forwarding the object itself without storing it leaves self.launcherView
    // nil even after UIKit has successfully initialized the controller.
    _launcherView = launcherView;
    [self.lcosShell setLauncherView:launcherView.view];
}




- (void)showSettings {
    Class settingsClass = NSClassFromString(@"LCOSSettingsView");
    if (!settingsClass || self.overlayWindow.rootViewController.presentedViewController) return;
    UIViewController *settings = [[settingsClass alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    [self.overlayWindow.rootViewController presentViewController:navigation animated:YES completion:nil];
}













// UIGestureRecognizerDelegate



@end