//
//  LCOSCore.m
//  LCOS.dylib
//

#import "LCOSCore.h"
#import "LCOSLauncherView.h"
#import "LCOSGestureHandler.h"
#import "LCOSLogManager.h"
#import "LCOSNavigationBar.h"
#import "LCOSBackgroundView.h"
#import "LCOSAppModel.h"
#import "LCOSLayout.h"
#import "LCOSTaskRegistry.h"
#import "LCOSShellController.h"
#import "LCOSPassThroughWindow.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Transparent regions pass touches to the native host. Only an active shell's
// background or actual navigation zone may consume touches.

@interface LCOSNavigationTouchZone : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, copy) void (^onPan)(UIPanGestureRecognizer *gesture);
@property (nonatomic, copy) void (^onTap)(void);
@end
@implementation LCOSNavigationTouchZone
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // UIControl's touch tracking can prevent a scroll-style pan before it
        // begins. A plain view with explicit recognizers keeps the edge swipe
        // reliable in both native and guest interfaces.
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.maximumNumberOfTouches = 1;
        pan.cancelsTouchesInView = NO;
        pan.delegate = self;
        [self addGestureRecognizer:pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tap.cancelsTouchesInView = NO;
        tap.delegate = self;
        [tap requireGestureRecognizerToFail:pan];
        [self addGestureRecognizer:tap];
    }
    return self;
}
- (void)handlePan:(UIPanGestureRecognizer *)gesture { if (self.onPan) self.onPan(gesture); }
- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded && self.onTap) self.onTap();
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (![recognizer isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:self];
    return velocity.x < -10 && fabs(velocity.x) > fabs(velocity.y);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}
@end

@implementation LCOSPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!event || event.type == UIEventTypeTouches) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSOverlayScreenTouchedNotification" object:nil];
    }
    
    if (self.backgroundView && !self.backgroundView.hidden && self.backgroundView.alpha > 0.01) {
        return [super hitTest:point withEvent:event];
    }
    // Match the actual vertical navigation zone, not an invisible full-height strip.
    if (!self.launcherContainer && self.navigationTouchZone && !self.navigationTouchZone.hidden) {
        CGPoint localPoint = [self.navigationTouchZone convertPoint:point fromView:self];
        if ([self.navigationTouchZone pointInside:localPoint withEvent:event]) {
            return [super hitTest:point withEvent:event];
        }
    }
    // 1. If launcher container is visible and touch is on it, let it handle normally
    if (self.launcherContainer && [self.launcherContainer isViewLoaded]) {
        UIView *launcherView = self.launcherContainer.view;
        if (launcherView && !launcherView.hidden && launcherView.alpha > 0.01) {
            CGPoint localPoint = [launcherView convertPoint:point fromView:self];
            if (CGRectContainsPoint(launcherView.bounds, localPoint)) {
                [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS PassThroughWindow: hitTest -> launcherContainer (point=%@)", NSStringFromCGPoint(point)]];
                return [super hitTest:point withEvent:event]; // Normal hit test for launcher
            }
        }
    }
    
    // 3. For 3+ finger touches, return self so window's gesture recognizers work
    // BUT only when launcher is NOT visible (launcher has its own gesture)
    // We check this by seeing if launcherContainer is set and visible
    BOOL launcherVisible = (self.launcherContainer && [self.launcherContainer isViewLoaded] && 
                           self.launcherContainer.view && !self.launcherContainer.view.hidden && 
                           self.launcherContainer.view.alpha > 0.01);
    
    if (!launcherVisible && event && event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];
        if (touches.count >= 3) {
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS PassThroughWindow: hitTest -> self (3+ fingers, count=%ld)", (long)touches.count]];
            return self; // Window receives touch for its gesture recognizers
        }
    }
    
    // 4. All other touches pass through to LiveContainer
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS PassThroughWindow: hitTest -> nil (passthrough, point=%@)", NSStringFromCGPoint(point)]];
    return nil;
}
@end

// Launcher container view controller for proper child VC management
@interface LCOSLauncherContainerVC : UIViewController
@end

@implementation LCOSLauncherContainerVC
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

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

// Class extension for private properties
@interface LCOSCore ()
- (void)finishHidingLauncher;
- (BOOL)isBackgroundVisible;
- (UIView *)navigationTouchZone;
@property (nonatomic, strong) UILongPressGestureRecognizer *overlayLongPressGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *launcherLongPressGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *nativeDockGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *launcherDismissGesture;
@property (nonatomic, weak) UITabBar *nativeDock;
@property (nonatomic, assign) BOOL dockTransitionActive;
@property (nonatomic, assign) BOOL launcherTransitionActive;
@property (nonatomic, assign) CGPoint dockGestureStart;
@property (nonatomic, strong) LCOSNavigationBar *navigationBar;
@property (nonatomic, strong) LCOSBackgroundView *backgroundView;
@property (nonatomic, strong) LCOSNavigationTouchZone *rightEdgeZone;
@property (nonatomic, assign) BOOL isBackgroundVisible;
@property (nonatomic, assign) BOOL isGuestNavigation;
@property (nonatomic, assign) BOOL launcherPreloading;
@end

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
                [core showLauncherImmediately];
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
static NSString *const kLCOSLauncherVisibleKey = @"LCOSLauncherVisible";
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
- (void)registerGesturesOnOverlayWindow {
    if (!self.overlayWindow) return;
    
    // Register three-finger long press on overlay window
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
        initWithTarget:self action:@selector(handleThreeFingerLongPress:)];
    longPress.numberOfTouchesRequired = 3;
    longPress.minimumPressDuration = 1.0;
    // Don't cancel touches - let them pass through to LiveContainer when gesture fails
    longPress.cancelsTouchesInView = NO;
    longPress.delegate = self;
    [self.overlayWindow addGestureRecognizer:longPress];
    self.overlayLongPressGesture = longPress;
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Three-finger long press registered on overlay window"];
}

// Handle three-finger long press on overlay window
- (void)handleThreeFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: Three finger long press (%@) - showing settings", gesture == self.overlayLongPressGesture ? @"overlay" : @"launcher"]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Import at runtime to avoid circular dependency
            Class settingsClass = NSClassFromString(@"LCOSSettingsView");
            if (settingsClass) {
                id settingsView = [settingsClass alloc];
                if ([settingsView respondsToSelector:@selector(initWithNibName:bundle:)]) {
                    settingsView = [settingsView initWithNibName:nil bundle:nil];
                } else {
                    settingsView = [settingsView init];
                }
                
                // Present settings on overlay window's root view controller (within overlay window)
                // This keeps settings inside overlay window layer (L1-b), not on LiveContainer window
                if (self.overlayWindow && self.overlayWindow.rootViewController) {
                    [self.overlayWindow.rootViewController presentViewController:settingsView animated:YES completion:nil];
                    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Settings presented on overlay window"];
                }
            }
        });
    }
}

- (void)showLauncherImmediately {
    BOOL animations = UIView.areAnimationsEnabled;
    [UIView setAnimationsEnabled:NO];
    @try { [self showLauncher]; }
    @finally {
        if (self.launcherContainer) {
            self.launcherContainer.view.alpha = 1.0;
            self.launcherContainer.view.transform = CGAffineTransformIdentity;
        }
        [UIView setAnimationsEnabled:animations];
    }
}

- (void)showLauncher {
    if (!self.isGuestNavigation && !self.isLauncherVisible && ![self canSwitchShellFromLCOS:NO]) return;
    if (self.isLauncherVisible || self.launcherPreloading || self.isBackgroundVisible ||
        (self.launcherTransitionActive && !self.dockTransitionActive)) return;
    if (!self.isLauncherVisible) self.launcherTransitionActive = YES;
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: showLauncher"];
    
    // Ensure overlay window is visible
    self.overlayWindow.hidden = NO;
    
    // Create launcher view if needed
    if (!self.launcherView) {
        self.launcherView = [[LCOSLauncherView alloc] init];
    }
    
    // Create container VC if needed
    if (!self.launcherContainer) {
        self.launcherContainer = [[LCOSLauncherContainerVC alloc] init];
        self.launcherContainer.view.backgroundColor = [UIColor clearColor];
        self.launcherContainer.view.frame = self.overlayWindow.rootViewController.view.bounds;
        self.launcherContainer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        // Add three-finger long press gesture to launcher container for settings
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
            initWithTarget:self action:@selector(handleThreeFingerLongPress:)];
        longPress.numberOfTouchesRequired = 3;
        longPress.minimumPressDuration = 1.0;
        longPress.cancelsTouchesInView = NO;
        longPress.delegate = self;
        [self.launcherContainer.view addGestureRecognizer:longPress];
        self.launcherLongPressGesture = longPress;
        
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Three-finger long press registered on launcher container"];
    }
    
    [self setLauncherRoundedCorners:self.dockTransitionActive];
    // Add launcher as child view controller (for proper safeAreaLayoutGuide)
    // Add launcherContainer to rootVC view
    [self.overlayWindow.rootViewController addChildViewController:self.launcherContainer];
    [self.overlayWindow.rootViewController.view addSubview:self.launcherContainer.view];
    [self.overlayWindow.rootViewController.view bringSubviewToFront:self.launcherContainer.view];
    
    // Add launcher view to container
    self.launcherView.view.frame = self.launcherContainer.view.bounds;
    self.launcherView.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.launcherContainer addChildViewController:self.launcherView];
    [self.launcherContainer.view addSubview:self.launcherView.view];
    [self.launcherView didMoveToParentViewController:self.launcherContainer];
    
    // Set launcherContainer on pass-through window for touch handling
    if ([self.overlayWindow isKindOfClass:[LCOSPassThroughWindow class]]) {
        ((LCOSPassThroughWindow *)self.overlayWindow).launcherContainer = self.launcherContainer;
    }
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: launcherContainer.view frame=%@, rootVC.view.frame=%@", NSStringFromCGRect(self.launcherContainer.view.frame), NSStringFromCGRect(self.overlayWindow.rootViewController.view.frame)]];
    
    // Allow simultaneous gesture recognition between overlay window and launcher container
    if (self.overlayLongPressGesture && self.launcherLongPressGesture) {
        // Both can recognize simultaneously - launcher has priority when visible
        [self.overlayLongPressGesture requireGestureRecognizerToFail:self.launcherLongPressGesture];
        [self.launcherLongPressGesture requireGestureRecognizerToFail:self.overlayLongPressGesture];
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: requireGestureRecognizerToFail set between overlay and launcher gestures"];
    }
    
    // IMPORTANT: Disable overlay window gesture when launcher is visible
    // Launcher has its own gesture recognizer
    self.overlayLongPressGesture.enabled = NO;
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: overlayLongPressGesture disabled (launcher visible)"];
    
    // Match the settings sheet: the desktop slides up from the bottom.
    self.launcherContainer.view.alpha = 1.0;
    [self setLauncherRoundedCorners:YES];
    if (self.dockTransitionActive) {
        self.launcherContainer.view.transform = CGAffineTransformIdentity;
    } else {
        self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(0, self.launcherContainer.view.bounds.size.height);
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.launcherContainer.view.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            self.launcherTransitionActive = NO;
            [self setLauncherRoundedCorners:NO];
        }];
    }
    
    self.isLauncherVisible = YES;
    
    if (!self.launcherDismissGesture) {
        self.launcherDismissGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleLauncherDismissGesture:)];
        self.launcherDismissGesture.minimumNumberOfTouches = 3;
        self.launcherDismissGesture.maximumNumberOfTouches = 3;
        self.launcherDismissGesture.delegate = self;
        [self.launcherContainer.view addGestureRecognizer:self.launcherDismissGesture];
    }

    self.rightEdgeZone.hidden = YES;
    self.navigationBar.hidden = YES;
    // Save state
    [self saveLauncherState];
    [self updateInteractionState];
}

- (void)hideLauncher {
    if (!self.isLauncherVisible || self.launcherTransitionActive || ![self canSwitchShellFromLCOS:YES]) return;
    self.launcherTransitionActive = YES;
    [self setLauncherRoundedCorners:YES];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: hideLauncher"];
    
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(0, self.launcherContainer.view.bounds.size.height);
    } completion:^(BOOL finished) {
        [self finishHidingLauncher];
    }];
}

- (void)finishHidingLauncher {
        [self setLauncherRoundedCorners:NO];
        self.launcherContainer.view.transform = CGAffineTransformIdentity;
        [self.launcherView willMoveToParentViewController:nil];
        [self.launcherView.view removeFromSuperview];
        [self.launcherView removeFromParentViewController];
        
        [self.launcherContainer willMoveToParentViewController:nil];
        [self.launcherContainer.view removeFromSuperview];
        [self.launcherContainer removeFromParentViewController];
        
        // Clear launcherContainer on pass-through window for touch handling
        if ([self.overlayWindow isKindOfClass:[LCOSPassThroughWindow class]]) {
            ((LCOSPassThroughWindow *)self.overlayWindow).launcherContainer = nil;
        }
        
        self.isLauncherVisible = NO;
        
        // Re-enable overlay window gesture when launcher is hidden
        self.overlayLongPressGesture.enabled = YES;
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: overlayLongPressGesture enabled (launcher hidden)"];
        
        // Save state
        [self saveLauncherState];
        self.launcherTransitionActive = NO;
        [self.overlayWindow.rootViewController.view bringSubviewToFront:self.rightEdgeZone];
        [self.overlayWindow.rootViewController.view bringSubviewToFront:self.navigationBar];
        [self updateInteractionState];
}

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

#if 0 // Removed: single-source navigation and background controller.
- (void)showNavigationTapFeedback {
    if (self.isLauncherVisible || self.isBackgroundVisible || self.edgeTransitionActive) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeNavigationBar) object:nil];
    self.navigationBar.hidden = NO;
    [self.navigationBar.layer removeAllAnimations];
    self.navigationBar.transform = CGAffineTransformIdentity;
    self.navigationBar.alpha = 0.85;
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.navigationBar.transform = CGAffineTransformMakeTranslation(-3, 0);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.15 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.navigationBar.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
    [self performSelector:@selector(fadeNavigationBar) withObject:nil afterDelay:1.5];
}

- (void)setupNavigationAndBackground {
    if (self.navigationBar) return;
    UIView *root = self.overlayWindow.rootViewController.view;
    CGFloat zoneWidth = MAX(32.0, root.bounds.size.width * 0.07);
    CGFloat barWidth = 23.0;
    CGFloat barHeight = 150.0;
    self.navigationBar = [[LCOSNavigationBar alloc] initWithFrame:CGRectMake(root.bounds.size.width - 2.0 - barWidth,
        (root.bounds.size.height - barHeight) / 2.0, barWidth, barHeight)];
    self.navigationBar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.navigationBar.alpha = 0.0;
    self.navigationBar.userInteractionEnabled = NO;
    [root addSubview:self.navigationBar];
    self.rightEdgeZone = [[LCOSNavigationTouchZone alloc] initWithFrame:CGRectMake(root.bounds.size.width - zoneWidth,
        (root.bounds.size.height - barHeight) / 2.0 - 44.0, zoneWidth, barHeight + 88.0)];
    self.rightEdgeZone.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.rightEdgeZone.backgroundColor = UIColor.clearColor;
    __weak typeof(self) weakSelf = self;
    self.rightEdgeZone.onPan = ^(UIPanGestureRecognizer *gesture) { [weakSelf handleRightEdgeGesture:gesture]; };
    self.rightEdgeZone.onTap = ^{ [weakSelf showNavigationTapFeedback]; };
    [root addSubview:self.rightEdgeZone];
    if ([self.overlayWindow isKindOfClass:LCOSPassThroughWindow.class]) {
        ((LCOSPassThroughWindow *)self.overlayWindow).navigationTouchZone = self.rightEdgeZone;
    }
    [root bringSubviewToFront:self.navigationBar];
}

- (void)handleRightEdgeGesture:(UIPanGestureRecognizer *)gesture {
    CGFloat width = self.overlayWindow.bounds.size.width;
    CGPoint point = [gesture locationInView:self.overlayWindow];
    CGFloat zoneWidth = MAX(32.0, width * 0.07);
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self.navigationBar.layer removeAllAnimations];
        if (self.edgeTransitionActive || self.edgeLaunchingBackground || self.isBackgroundVisible || self.isLauncherVisible ||
            self.launcherTransitionActive || self.overlayWindow.rootViewController.presentedViewController || point.x < width - zoneWidth) {
            gesture.enabled = NO;
            gesture.enabled = YES;
            return;
        }
        [self cancelEdgeDwell];
        self.edgeTransitionActive = YES;
        self.edgeDwellReached = NO;
        self.edgeLaunchingBackground = NO;
        self.edgeStartX = point.x;
        self.lastEdgeTravel = 0;
        @try {
            [self prepareAppReturnTransition];
        } @catch (NSException *exception) {
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
                @"LCOS Navigation: preparation failed safely: %@ %@", exception.name, exception.reason]];
            [self discardFailedBackground];
            return;
        }
        [self.overlayWindow.rootViewController.view bringSubviewToFront:self.rightEdgeZone];
        [self.overlayWindow.rootViewController.view bringSubviewToFront:self.navigationBar];
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@YES];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeNavigationBar) object:nil];
        self.navigationBar.transform = CGAffineTransformIdentity;
        [UIView animateWithDuration:0.18 animations:^{ self.navigationBar.alpha = 1.0; }];
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Navigation: began guest=%d background=%d", self.isGuestNavigation, self.isBackgroundVisible]];
    } else if (self.edgeTransitionActive && gesture.state == UIGestureRecognizerStateChanged) {
        if (self.edgeLaunchingBackground) return;
        CGFloat travel = self.edgeStartX - point.x;
        self.lastEdgeTravel = MAX(0, travel);
        // Dwell starts only after a real leftward movement, not on a tap.
        if (travel >= 8) [self scheduleEdgeDwell];
        else { [self cancelEdgeDwell]; self.edgeDwellReached = NO; }
        if (self.edgeDwellReached) {
            [self.backgroundView setTransitionProgress:MIN(1.0, MAX(0, travel / 80.0))];
        } else if (self.isBackgroundVisible) {
            [self updateEdgeInteractivePosition:MAX(0, travel)];
        } else if (travel > 0 && !self.launcherTransitionActive) {
            [self updateEdgeInteractivePosition:travel];
        }
    } else if (self.edgeTransitionActive &&
               (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed)) {
        [self cancelEdgeDwell];
        BOOL dwell = self.edgeDwellReached;
        self.edgeDwellReached = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@NO];
        CGFloat velocityX = [gesture velocityInView:self.overlayWindow].x;
        BOOL returnsHome = gesture.state == UIGestureRecognizerStateEnded && !self.edgeLaunchingBackground && !dwell &&
            ((self.lastEdgeTravel > 24.0 && velocityX < -120.0) || self.lastEdgeTravel > 64.0);
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Navigation: end travel=%.1f dwell=%d returnsHome=%d", self.lastEdgeTravel, dwell, returnsHome]];
        if (self.isBackgroundVisible) {
            [self resetEdgeTransitionState];
            return;
        }
        [self finishEdgeTransitionReturningHome:returnsHome cancelled:gesture.state != UIGestureRecognizerStateEnded];
        self.edgeLaunchingBackground = NO;
    }
}

- (void)updateEdgeInteractivePosition:(CGFloat)travel {
    CGFloat progress = MIN(1, MAX(0, travel / MAX(80, self.overlayWindow.bounds.size.width * 0.42)));
    [self updateLiveTaskReturnProgress:progress];
    if (self.appTransitionSnapshot) {
        CGFloat scale = 1.0 - 0.22 * progress;
        self.appTransitionSnapshot.transform = CGAffineTransformMakeScale(scale, scale);
        self.appTransitionSnapshot.layer.cornerRadius = 20 * progress;
        self.appTransitionSnapshot.layer.masksToBounds = YES;
        self.navigationBar.transform = CGAffineTransformMakeTranslation(-36 * progress, 0);
    } else {
        self.navigationBar.transform = CGAffineTransformMakeTranslation(-MIN(40, travel), 0);
    }
}

- (void)prepareAppReturnTransition {
    if (self.isBackgroundVisible || self.isLauncherVisible) return;
    self.nativeTransition = !self.activeTaskView;
    self.nativeSourceOnly = self.nativeTransition && !self.returnToLCOSDesktop;
    if (!self.nativeSourceOnly) LCOSNativeWindowBeforeTask = nil;
    UIView *root = self.overlayWindow.rootViewController.view;
    self.sourceDesktopView = [self sourceDesktop];
    self.navigationBar.hidden = YES;
    self.rightEdgeZone.hidden = YES;
    if (self.activeTaskView) {
        [self prepareTaskStageForCurrentTask];
        [self bringLiveTasksAboveSource];
    } else {
        // Native source desktops blur in place. Never snapshot the LCOS overlay
        // itself: it contains no running application and can capture the bar.
        self.appTransitionSnapshot = nil;
    }
    self.navigationBar.hidden = NO;
    self.rightEdgeZone.hidden = NO;
    [root bringSubviewToFront:self.rightEdgeZone];
    [root bringSubviewToFront:self.navigationBar];
}

- (void)prepareTaskStageForCurrentTask {
    UIView *task = self.activeTaskView;
    if (!task || self.taskStage) return;
    UIView *root = self.overlayWindow.rootViewController.view;
    self.taskStage = [[UIView alloc] initWithFrame:root.bounds];
    self.taskStage.backgroundColor = UIColor.clearColor;
    self.taskStage.clipsToBounds = NO;
    [root insertSubview:self.taskStage belowSubview:self.rightEdgeZone];
    if (!self.taskTransitionStates) self.taskTransitionStates = [NSMutableDictionary dictionary];
    NSValue *key = [NSValue valueWithNonretainedObject:task];
    self.taskTransitionStates[key] = @{@"transform": [NSValue valueWithCGAffineTransform:task.transform],
        @"center": [NSValue valueWithCGPoint:task.center],
        @"alpha": @(task.alpha), @"hidden": @(task.hidden), @"interaction": @(task.userInteractionEnabled),
        @"parent": task.superview, @"index": @([task.superview.subviews indexOfObjectIdenticalTo:task])};
    CGFloat sx = task.bounds.size.width > 0 ? self.taskStage.bounds.size.width / task.bounds.size.width : 1;
    CGFloat sy = task.bounds.size.height > 0 ? self.taskStage.bounds.size.height / task.bounds.size.height : 1;
    CGAffineTransform stageTransform = CGAffineTransformMakeScale(sx, sy);
    [self.taskStage addSubview:task];
    task.transform = stageTransform;
    task.center = CGPointMake(CGRectGetMidX(self.taskStage.bounds), CGRectGetMidY(self.taskStage.bounds));
    task.alpha = 1;
    task.hidden = NO;
    task.userInteractionEnabled = NO;
}

- (void)bringLiveTasksAboveSource {
    [self.overlayWindow.rootViewController.view bringSubviewToFront:self.taskStage];
    self.rightEdgeZone.hidden = YES;
    self.navigationBar.hidden = YES;
}

- (void)updateLiveTaskReturnProgress:(CGFloat)progress {
    for (NSValue *key in self.taskTransitionStates) {
        UIView *task = key.nonretainedObjectValue;
        NSDictionary *state = self.taskTransitionStates[key];
        CGAffineTransform base = task.transform;
        CGFloat scale = 1.0 - 0.22 * progress;
        task.transform = CGAffineTransformScale(base, scale, scale);
        task.layer.cornerRadius = 60 * progress;
        task.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        task.layer.masksToBounds = YES;
        self.navigationBar.transform = CGAffineTransformMakeScale(1.0 - 0.22 * progress, 1.0 - 0.22 * progress);
    }
}

- (void)restoreLiveTaskTransitionStates {
    for (NSValue *key in self.taskTransitionStates) {
        UIView *task = key.nonretainedObjectValue;
        NSDictionary *state = self.taskTransitionStates[key];
        UIView *parent = state[@"parent"];
        if ([parent isKindOfClass:UIView.class]) [parent insertSubview:task atIndex:MIN([state[@"index"] unsignedIntegerValue], parent.subviews.count)];
        task.transform = [state[@"transform"] CGAffineTransformValue];
        task.center = [state[@"center"] CGPointValue];
        task.alpha = [state[@"alpha"] doubleValue];
        task.hidden = [state[@"hidden"] boolValue];
        task.userInteractionEnabled = [state[@"interaction"] boolValue];
        task.layer.cornerRadius = 0;
    }
    [self.taskTransitionStates removeAllObjects];
    [self.taskStage removeFromSuperview];
    self.taskStage = nil;
}

- (void)restoreSourceDesktop {
    if (self.sourceDesktopView == LCOSNativeWindowBeforeTask) {
        self.sourceDesktopView.userInteractionEnabled = YES;
        return;
    }
    // A detached native snapshot must not re-hide or disable the real window.
    self.sourceDesktopView.hidden = NO;
    self.sourceDesktopView.alpha = 1;
    self.sourceDesktopView.userInteractionEnabled = NO;
    [self.sourceDesktopView removeFromSuperview];
}

- (void)returnToSourceDesktop {
    [self.appTransitionSnapshot removeFromSuperview];
    self.appTransitionSnapshot = nil;
    if (self.isGuestNavigation) {
        [self returnToLiveContainer];
        [self resetEdgeTransitionState];
        return;
    }
    BOOL showLCOS = self.returnToLCOSDesktop;
    [self restoreLiveTaskTransitionStates];
    for (UIView *task in [self runningTaskViews]) {
        task.hidden = YES;
        task.alpha = 0;
        task.userInteractionEnabled = NO;
    }
    self.activeTaskView = nil;
    [self restoreSourceDesktop];
    self.sourceDesktopView = nil;
    if (showLCOS) {
        if (!self.launcherContainer) [self showLauncher];
        if (self.launcherContainer) {
            UIView *root = self.overlayWindow.rootViewController.view;
            UIView *launcher = self.launcherContainer.view;
            if (self.launcherContainer.parentViewController != self.overlayWindow.rootViewController)
                [self.overlayWindow.rootViewController addChildViewController:self.launcherContainer];
            launcher.frame = root.bounds;
            launcher.transform = CGAffineTransformIdentity;
            launcher.alpha = 1;
            [root addSubview:launcher];
            [self.launcherContainer didMoveToParentViewController:self.overlayWindow.rootViewController];
            if (self.launcherView.parentViewController != self.launcherContainer)
                [self.launcherContainer addChildViewController:self.launcherView];
            self.launcherView.view.frame = launcher.bounds;
            [launcher addSubview:self.launcherView.view];
            [self.launcherView didMoveToParentViewController:self.launcherContainer];
            ((LCOSPassThroughWindow *)self.overlayWindow).launcherContainer = self.launcherContainer;
            self.isLauncherVisible = YES;
            self.launcherTransitionActive = NO;
            self.overlayLongPressGesture.enabled = NO;
            [self setLauncherRoundedCorners:NO];
            [self saveLauncherState];
        }
    } else {
        if (self.isLauncherVisible) [self finishHidingLauncher];
        LCOSNativeWindowBeforeTask.userInteractionEnabled = YES;
        [LCOSNativeWindowBeforeTask makeKeyAndVisible];
    }
    [self updateInteractionState];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
        @"LCOS Home: restored source desktop=%@ tasks hidden", showLCOS ? @"LCOS" : @"LiveContainer"]];
}

- (void)finishEdgeTransitionReturningHome:(BOOL)returningHome cancelled:(BOOL)cancelled {
    if (returningHome) {
        [UIView animateWithDuration:0.24 animations:^{
            self.appTransitionSnapshot.transform = CGAffineTransformMakeScale(0.72, 0.72);
            self.appTransitionSnapshot.alpha = 0;
            self.navigationBar.alpha = 0;
        } completion:^(BOOL finished) {
            [self returnToSourceDesktop];
            [self resetEdgeTransitionState];
        }];
        return;
    }
    [UIView animateWithDuration:0.22 animations:^{
        self.appTransitionSnapshot.transform = CGAffineTransformIdentity;
        self.appTransitionSnapshot.layer.cornerRadius = 0;
        [self restoreLiveTaskTransitionStates];
        self.navigationBar.transform = CGAffineTransformIdentity;
        self.navigationBar.alpha = 0;
    } completion:^(BOOL finished) {
        [self.appTransitionSnapshot removeFromSuperview];
        self.appTransitionSnapshot = nil;
        [self.backgroundView restoreTaskGeometry];
        [self restoreSourceDesktop];
        [self resetEdgeTransitionState];
    }];
}

- (void)scheduleEdgeDwell {
    if (self.edgeLaunchingBackground || self.edgeDwellReached || self.isBackgroundVisible) return;
    [self cancelEdgeDwell];
    self.edgeDwellTimer = [NSTimer scheduledTimerWithTimeInterval:0.22 repeats:NO block:^(NSTimer *timer) {
        if (!self.edgeTransitionActive || self.isBackgroundVisible) return;
        self.edgeDwellReached = YES;
        self.edgeLaunchingBackground = YES;
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
        [feedback impactOccurred];
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Navigation: dwell reached"];
        [self showBackground];
    }];
}

- (void)cancelEdgeDwell {
    [self.edgeDwellTimer invalidate];
    self.edgeDwellTimer = nil;
}

- (void)resetEdgeTransitionState {
    [self cancelEdgeDwell];
    self.edgeTransitionActive = NO;
    self.edgeDwellReached = NO;
    self.edgeLaunchingBackground = NO;
    self.lastEdgeTravel = 0;
    [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@NO];
    [self.navigationBar.layer removeAllAnimations];
    self.navigationBar.transform = CGAffineTransformIdentity;
    self.navigationBar.alpha = 0;
}

- (void)discardFailedBackground {
    [self.backgroundView.layer removeAllAnimations];
    [self.backgroundView restoreTaskGeometry];
    [self.backgroundView detachSourceDesktop];
    [self.backgroundView removeFromSuperview];
    [self restoreLiveTaskTransitionStates];
    [self.appTransitionSnapshot removeFromSuperview];
    self.appTransitionSnapshot = nil;
    [self restoreSourceDesktop];
    self.sourceDesktopView = nil;
    self.activeTaskView = nil;
    [self.taskStage removeFromSuperview];
    self.taskStage = nil;
    self.backgroundView = nil;
    ((LCOSPassThroughWindow *)self.overlayWindow).backgroundView = nil;
    self.isBackgroundVisible = NO;
    [self resetEdgeTransitionState];
    [self updateInteractionState];
}

- (void)fadeNavigationBar {
    if (self.edgeTransitionActive) return;
    [UIView animateWithDuration:0.3 animations:^{ self.navigationBar.alpha = 0.0; }];
}

- (UIView *)sourceDesktop {
    if (self.isGuestNavigation) {
        NSString *source = @"native";
        Class utils = NSClassFromString(@"LCSharedUtils");
        SEL selector = NSSelectorFromString(@"appGroupPath");
        if ([utils respondsToSelector:selector]) {
            NSURL *group = ((id (*)(id, SEL))objc_msgSend)(utils, selector);
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[group.path stringByAppendingPathComponent:@"LiveContainer/LCOSLaunchSource.plist"]];
            if ([info[@"source"] isEqualToString:@"lcos"]) source = @"lcos";
        }
        if ([source isEqualToString:@"lcos"]) {
            LCOSLauncherView *launcher = [[LCOSLauncherView alloc] init];
            [launcher loadViewIfNeeded];
            launcher.view.frame = self.overlayWindow.bounds;
            [launcher.view layoutIfNeeded];
            return launcher.view;
        }
        UIView *native = [[UIView alloc] initWithFrame:self.overlayWindow.bounds];
        native.backgroundColor = UIColor.systemBackgroundColor;
        UILabel *label = [[UILabel alloc] initWithFrame:native.bounds];
        label.text = @"LiveContainer";
        label.textColor = UIColor.secondaryLabelColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [native addSubview:label];
        return native;
    }
    if (self.nativeSourceOnly) {
        UIWindow *native = LCOSNativeWindowBeforeTask;
        if (!native) {
            for (UIWindow *candidate in self.overlayWindow.windowScene.windows.reverseObjectEnumerator) {
                if (candidate != self.overlayWindow && !candidate.hidden && candidate.alpha > 0.01) { native = candidate; break; }
            }
        }
        // Only a truly native source may use its live window for blur. An
        // application window is never treated as the source desktop.
        if (native && !native.rootViewController.presentedViewController) {
            native.userInteractionEnabled = NO;
            return native;
        }
        LCOSNativeWindowBeforeTask = nil;
        self.nativeSourceOnly = NO;
    }
    if (self.isLauncherVisible) return self.launcherContainer.view;
    // The overlay root is an ancestor of the background view and must never be
    // inserted into its own hierarchy. Use an independent native-window view
    // instead, preserving the native source desktop without a view cycle.
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows.reverseObjectEnumerator) {
            if (window == self.overlayWindow || window.hidden || window.alpha < 0.01) continue;
            UIView *snapshot = [window snapshotViewAfterScreenUpdates:NO];
            if (snapshot) {
                snapshot.frame = self.overlayWindow.bounds;
                return snapshot;
            }
        }
    }
    UIView *fallback = [[UIView alloc] initWithFrame:self.overlayWindow.bounds];
    fallback.backgroundColor = UIColor.systemBackgroundColor;
    return fallback;
}

- (id)controllerForTask:(UIView *)task {
    if (![task isKindOfClass:UIView.class]) return nil;
    Class decorated = NSClassFromString(@"DecoratedAppSceneViewController") ?: NSClassFromString(@"LiveContainerSwiftUI.DecoratedAppSceneViewController");
    SEL delegateSelector = NSSelectorFromString(@"_viewDelegate");
    if ([task respondsToSelector:delegateSelector]) {
        id controller = ((id (*)(id, SEL))objc_msgSend)(task, delegateSelector);
        if (!decorated || [controller isKindOfClass:decorated]) return controller;
    }
    for (UIResponder *responder = task.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class] &&
            [responder respondsToSelector:NSSelectorFromString(@"appSceneVC")] &&
            (!decorated || [responder isKindOfClass:decorated])) return responder;
    }
    return nil;
}

- (NSArray<UIView *> *)runningTaskViews {
    if (self.isGuestNavigation) return @[];
    @try {
    NSMutableArray *tasks = [NSMutableArray array];
    for (NSValue *entry in [LCOSTaskWindows() copy]) {
        UIView *view = entry.nonretainedObjectValue;
        if (![view isKindOfClass:UIView.class]) { [LCOSTaskWindows() removeObject:entry]; continue; }
        id controller = [self controllerForTask:view];
        if (!controller) {
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Task: no verified controller for %@", view.class]];
            continue;
        }
        SEL sceneSelector = NSSelectorFromString(@"appSceneVC");
        if (![controller respondsToSelector:sceneSelector]) continue;
        id scene = ((id (*)(id, SEL))objc_msgSend)(controller, sceneSelector);
        SEL running = NSSelectorFromString(@"isAppRunning");
        if (!scene || ![scene respondsToSelector:running]) continue;
        BOOL alive = ((BOOL (*)(id, SEL))objc_msgSend)(scene, running);
        if (alive) [tasks addObject:view];
    }
    return tasks;
    } @catch (NSException *exception) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
            @"LCOS Task: incompatible task ignored: %@ %@", exception.name, exception.reason]];
        return @[];
    }
}

- (BOOL)activateLiveTask:(UIView *)task {
    if (![self.runningTaskViews containsObject:task]) return NO;
    for (UIView *other in self.runningTaskViews) {
        other.hidden = other != task;
        if (other != task) other.alpha = 0;
    }
    id controller = [self controllerForTask:task];
    if (!controller) return NO;
    id scene = ((id (*)(id, SEL))objc_msgSend)(controller, NSSelectorFromString(@"appSceneVC"));
    if ([controller respondsToSelector:NSSelectorFromString(@"appSceneVCWillActivateScene:")])
        ((void (*)(id, SEL, id))objc_msgSend)(controller, NSSelectorFromString(@"appSceneVCWillActivateScene:"), scene);
    self.activeTaskView = task;
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Task: activating verified live task"];
    return YES;
}

- (BOOL)closeLiveTask:(UIView *)task {
    if (![self.runningTaskViews containsObject:task]) return NO;
    id controller = [self controllerForTask:task];
    SEL close = NSSelectorFromString(@"closeWindow");
    if (![controller respondsToSelector:close]) return NO;
    for (NSValue *entry in [LCOSTaskWindows() copy]) if (entry.nonretainedObjectValue == task) [LCOSTaskWindows() removeObject:entry];
    [self.backgroundView removeTaskFromCards:task];
    if (self.activeTaskView == task) self.activeTaskView = nil;
    ((void (*)(id, SEL))objc_msgSend)(controller, close);
    [self.backgroundView setNeedsLayout];
    return YES;
}

- (void)prepareBackgroundForCurrentInterface {
    [self.appTransitionSnapshot removeFromSuperview];
    self.appTransitionSnapshot = nil;
    [self restoreLiveTaskTransitionStates];
    self.taskStage = nil;
    self.isBackgroundVisible = YES;
    [self updateInteractionState];
    if (!self.backgroundView) {
        self.backgroundView = [[LCOSBackgroundView alloc] initWithFrame:self.overlayWindow.bounds];
        self.backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        __weak typeof(self) weakSelf = self;
        self.backgroundView.onHome = ^{ [weakSelf returnFromBackgroundToSourceDesktop]; };
        self.backgroundView.onActivateTask = ^BOOL(UIView *task) { return [weakSelf activateLiveTask:task]; };
        self.backgroundView.onCloseTask = ^BOOL(UIView *task) { return [weakSelf closeLiveTask:task]; };
        self.backgroundView.onTaskPresented = ^(UIView *task) {
            weakSelf.isBackgroundVisible = NO;
            [weakSelf resetEdgeTransitionState];
            weakSelf.activeTaskView = task;
            weakSelf.sourceDesktopView = nil;
            weakSelf.backgroundView = nil;
            ((LCOSPassThroughWindow *)weakSelf.overlayWindow).backgroundView = nil;
            [weakSelf updateInteractionState];
        };
    }
    UIView *desktop = [self sourceDesktop];
    self.sourceDesktopView = desktop;
    desktop.hidden = NO;
    [self.backgroundView setSourceDesktop:desktop];
    [self.backgroundView setSourceScales:!self.nativeTransition];
    self.liveTaskViews = [self runningTaskViews];
    [self.backgroundView setLiveTaskViews:self.liveTaskViews];
    [self.backgroundView setTransitionProgress:0.01];
    [self.backgroundView layoutIfNeeded];
    [self.overlayWindow.rootViewController.view addSubview:self.backgroundView];
    if ([self.overlayWindow isKindOfClass:LCOSPassThroughWindow.class])
        ((LCOSPassThroughWindow *)self.overlayWindow).backgroundView = self.backgroundView;
    self.backgroundView.hidden = NO;
}

- (void)animateBackgroundProgress:(CGFloat)progress completion:(void (^)(void))completion {
    [UIView animateWithDuration:0.38 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0 options:0 animations:^{
        [self.backgroundView setTransitionProgress:progress];
    } completion:^(BOOL finished) { if (completion) completion(); }];
}

- (void)showBackground {
    if (self.isLauncherVisible) [self.lcosShell showBackground];
    else [self.nativeShell showBackground];
}

- (void)legacyShowBackgroundUnused {
    if (self.isBackgroundVisible) return;
    @try {
        [self prepareBackgroundForCurrentInterface];
        [self.backgroundView setTransitionProgress:1];
        self.isBackgroundVisible = YES;
        [self updateInteractionState];
        [self animateBackgroundProgress:1.0 completion:^{
            [self resetEdgeTransitionState];
            [[LCOSLogManager sharedManager] forceLog:@"LCOS Background: presentation completed"];
        }];
    } @catch (NSException *exception) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
            @"LCOS Background: preparation failed safely: %@ %@", exception.name, exception.reason]];
        [self discardFailedBackground];
    }
}

- (void)hideBackground {
    [self.nativeShell hideBackground];
    [self.lcosShell hideBackground];
}

- (void)returnFromBackgroundToSourceDesktop {
    [self hideBackground];
    return;
    if (!self.isBackgroundVisible) return;
    LCOSBackgroundView *background = self.backgroundView;
    self.isBackgroundVisible = NO;
    self.edgeLaunchingBackground = NO;
    [UIView animateWithDuration:0.20 animations:^{ background.alpha = 0; } completion:^(BOOL finished) {
        [background restoreTaskGeometry];
        [background detachSourceDesktop];
        [background removeFromSuperview];
        [self restoreLiveTaskTransitionStates];
        self.backgroundView = nil;
        ((LCOSPassThroughWindow *)self.overlayWindow).backgroundView = nil;
        [self restoreSourceDesktop];
        self.sourceDesktopView = nil;
        [self resetEdgeTransitionState];
        if (self.isGuestNavigation) [self returnToLiveContainer];
        else [self returnToSourceDesktop];
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Background: source desktop and interaction restored"];
    }];
}



#endif

- (void)returnToLiveContainer {
    if (!self.isGuestNavigation) return;
    Class sharedUtils = NSClassFromString(@"LCSharedUtils");
    SEL selector = @selector(launchToGuestAppWithClassicMode:);
    if (![sharedUtils respondsToSelector:selector]) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Guest: LiveContainer return API unavailable"];
        return;
    }
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Guest: returning to LiveContainer host"];
    BOOL accepted = ((BOOL (*)(id, SEL, NSUInteger))objc_msgSend)(sharedUtils, selector, 0);
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Guest: host return accepted=%d", accepted]];
}

- (void)setLauncherView:(UIView *)launcherView {
    [self.lcosShell setLauncherView:launcherView];
}

- (BOOL)isBackgroundVisible {
    return self.nativeShell.isBackgroundVisible || self.lcosShell.isBackgroundVisible;
}

- (UIView *)navigationTouchZone {
    if (self.isBackgroundVisible) return nil;
    if (self.isLauncherVisible) return self.lcosShell.navigationZone;
    return self.nativeShell.navigationZone;
}

- (void)showLauncherForDockInteraction {
    if (self.launcherPreloading) return;
    self.launcherPreloading = YES;
    @try { [self showLauncher]; }
    @finally { self.launcherPreloading = NO; }
}

- (void)showSettings {
    Class settingsClass = NSClassFromString(@"LCOSSettingsView");
    if (!settingsClass || self.overlayWindow.rootViewController.presentedViewController) return;
    [self.overlayWindow.rootViewController presentViewController:[[settingsClass alloc] init] animated:YES completion:nil];
}

- (void)installNativeDockGestureIfNeeded {
    if (self.nativeDockGesture) return;
    UITabBar *dock = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window == self.overlayWindow || window.hidden) continue;
            dock = [self findTabBarInView:window];
            if (dock) break;
        }
        if (dock) break;
    }
    if (!dock) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.nativeDockGesture) [self installNativeDockGestureIfNeeded];
        });
        return;
    }
    self.nativeDock = dock;
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleNativeDockGesture:)];
    gesture.minimumPressDuration = 0.35;
    gesture.numberOfTouchesRequired = 1;
    gesture.allowableMovement = CGFLOAT_MAX;
    gesture.cancelsTouchesInView = NO;
    gesture.delegate = self;
    [dock addGestureRecognizer:gesture];
    self.nativeDockGesture = gesture;
    gesture.enabled = !self.isLauncherVisible;
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: native Dock long-press upward gesture installed"];
}

- (UITabBar *)findTabBarInView:(UIView *)view {
    if ([view isKindOfClass:UITabBar.class]) return (UITabBar *)view;
    for (UIView *child in view.subviews) {
        UITabBar *result = [self findTabBarInView:child];
        if (result) return result;
    }
    return nil;
}

- (BOOL)canSwitchShellFromLCOS:(BOOL)fromLCOS {
    if (![[LCOSTaskRegistry shared] hasRunningTasksFromLCOS:fromLCOS]) return YES;
    if (self.overlayWindow.rootViewController.presentedViewController) return NO;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"请先退出全部后台应用" message:@"关闭全部后台应用后，才能切换桌面。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self.overlayWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Gate: blocked switch from %@", fromLCOS ? @"LCOSShell" : @"NativeShell"]];
    return NO;
}

- (void)handleNativeDockGesture:(UILongPressGestureRecognizer *)gesture {
    if (self.isBackgroundVisible || self.isGuestNavigation || (self.isLauncherVisible && !self.dockTransitionActive)) return;
    CGPoint location = [gesture locationInView:self.overlayWindow];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (![self canSwitchShellFromLCOS:NO]) {
            gesture.enabled = NO;
            gesture.enabled = YES;
            return;
        }
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@YES];
        self.dockTransitionActive = YES;
        self.dockGestureStart = location;
        [self prepareLauncherForInteractivePresentation];
        self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(0, self.launcherContainer.view.bounds.size.height);
        [self setLauncherRoundedCorners:YES];
    } else if (self.dockTransitionActive && gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat upward = MAX(0.0, self.dockGestureStart.y - location.y);
        CGFloat height = self.launcherContainer.view.bounds.size.height;
        self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(0, MAX(0.0, height - upward));
    } else if (self.dockTransitionActive && (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed)) {
        CGFloat upward = MAX(0.0, self.dockGestureStart.y - location.y);
        BOOL shouldOpen = gesture.state == UIGestureRecognizerStateEnded && upward > self.launcherContainer.view.bounds.size.height * 0.18;
        self.dockTransitionActive = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@NO];
        if (shouldOpen) {
            [self finishInteractivePresentation];
        } else {
            self.isLauncherVisible = NO;
            self.launcherTransitionActive = YES;
            [UIView animateWithDuration:0.2 animations:^{
                self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(0, self.launcherContainer.view.bounds.size.height);
            } completion:^(BOOL finished) {
                [self finishHidingLauncher];
            }];
        }
    }
}

- (void)setLauncherRoundedCorners:(BOOL)rounded {
    UIView *view = self.launcherContainer.view;
    view.layer.cornerRadius = rounded ? [LCOSLayout value:@"sheetRadius"] : 0.0;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.maskedCorners = rounded ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner) : 0;
    view.layer.masksToBounds = rounded;
}

- (void)prepareLauncherForInteractivePresentation {
    [self showLauncherForDockInteraction];
    if (!self.launcherContainer) { self.dockTransitionActive = NO; return; }
    [self.launcherContainer.view.layer removeAllAnimations];
    self.launcherTransitionActive = YES;
}

- (void)finishInteractivePresentation {
    self.launcherTransitionActive = YES;
    [self setLauncherRoundedCorners:NO];
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.launcherContainer.view.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.launcherTransitionActive = NO;
        self.isLauncherVisible = YES;
        [self saveLauncherState];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kLCOSLauncherVisibleKey];
        [self updateInteractionState];
    }];
}

- (void)handleLauncherDismissGesture:(UIPanGestureRecognizer *)gesture {
    if (self.isBackgroundVisible || !self.isLauncherVisible) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (![self canSwitchShellFromLCOS:YES]) {
            gesture.enabled = NO;
            gesture.enabled = YES;
            return;
        }
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@YES];
        [self setLauncherRoundedCorners:YES];
    }
    CGFloat translation = [gesture translationInView:self.launcherContainer.view].y;
    if (gesture.state == UIGestureRecognizerStateChanged) {
        self.launcherTransitionActive = YES;
        self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(0, MAX(0.0, translation));
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@NO];
        BOOL shouldClose = gesture.state == UIGestureRecognizerStateEnded && translation > self.launcherContainer.view.bounds.size.height * 0.18;
        if (shouldClose) {
            self.launcherTransitionActive = NO;
            [self hideLauncher];
        } else {
            [UIView animateWithDuration:0.22 animations:^{
                self.launcherContainer.view.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished) {
                self.launcherTransitionActive = NO;
                [self setLauncherRoundedCorners:NO];
            }];
        }
    }
}

- (void)toggleLauncher {
    if (self.launcherTransitionActive) return;
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: toggleLauncher"];
    if (self.isLauncherVisible) {
        [self hideLauncher];
    } else {
        [self showLauncher];
    }
}


// UIGestureRecognizerDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: gestureRecognizer shouldReceiveTouch gesture=%@ touchView=%@", gestureRecognizer, touch.view]];
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: shouldRecognizeSimultaneously %@ with %@", gestureRecognizer, otherGestureRecognizer]];
    return YES;
}

@end