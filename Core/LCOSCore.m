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
#import <objc/runtime.h>

// Pass-through window - like LCOrbitPassThroughWindow
// Transparent regions pass touches to underlying windows
// BUT gesture recognizers on the window work for multi-finger gestures when appropriate
// Visible launcher, navigation, and background views receive touches normally
@interface LCOSPassThroughWindow : UIWindow
@property (nonatomic, weak) UIViewController *launcherContainer; // For touch handling when launcher is visible
@property (nonatomic, weak) LCOSBackgroundView *backgroundView;
@end

@interface LCOSNavigationTouchZone : UIControl
@property (nonatomic, copy) void (^onPan)(UIPanGestureRecognizer *gesture);
@end
@implementation LCOSNavigationTouchZone
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)handlePan:(UIPanGestureRecognizer *)gesture { if (self.onPan) self.onPan(gesture); }
@end

@implementation LCOSPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!event || event.type == UIEventTypeTouches) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSOverlayScreenTouchedNotification" object:nil];
    }
    
    if (self.backgroundView && !self.backgroundView.hidden && self.backgroundView.alpha > 0.01) {
        return [super hitTest:point withEvent:event];
    }
    // The right navigation strip remains interactive on the native host UI.
    if (!self.launcherContainer && point.x >= self.bounds.size.width - 32.0) {
        return [super hitTest:point withEvent:event];
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
@property (nonatomic, assign) BOOL edgeTransitionActive;
@property (nonatomic, assign) BOOL edgeDwellReached;
@property (nonatomic, assign) BOOL edgeLaunchingBackground;
@property (nonatomic, strong) NSTimer *edgeDwellTimer;
@property (nonatomic, assign) CGFloat edgeStartX;
@end

// Hook UIWindow.makeKeyAndVisible: as soon as LiveContainer's native window
// becomes visible, synchronously restore the desktop so no native frame is shown.
static BOOL LCOSAutoRestoreEnabled(void);
static void (*orig_makeKeyAndVisible)(id self, SEL _cmd);
static void lcos_makeKeyAndVisible(id self, SEL _cmd) {
    // Restore desktop BEFORE the native window becomes visible.
    if ([NSThread isMainThread]) {
        UIWindow *window = (UIWindow *)self;
        if (![window isKindOfClass:[LCOSPassThroughWindow class]] &&
            LCOSAutoRestoreEnabled() &&
            [[NSUserDefaults standardUserDefaults] boolForKey:@"LCOSLauncherVisible"]) {
            LCOSCore *core = [LCOSCore sharedInstance];
            if (!core.overlayWindow) {
                [[LCOSLogManager sharedManager] forceLog:@"LCOS: makeKeyAndVisible -> initialize early"];
                [core initialize];
            }
            if (!core.isLauncherVisible) {
                [[LCOSLogManager sharedManager] forceLog:@"LCOS: makeKeyAndVisible -> restore launcher before native shows"];
                [core showLauncherImmediately];
            }
        }
    }
    if (orig_makeKeyAndVisible) orig_makeKeyAndVisible(self, _cmd);
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
            [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: guest app detected, host UI disabled"];
            return;
        }
        // The host has no guestAppInfo. Wait for LiveContainerMain to publish
        // lcMainBundle rather than rejecting the host during early +load.
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: waiting for LiveContainer host initialization"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self initialize];
        });
        return;
    }
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: initialize START"];
    
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
    
    // Register gesture recognizers on overlay window (three-finger long press for settings)
    [self registerGesturesOnOverlayWindow];
    [self installNativeDockGestureIfNeeded];
    [self setupNavigationAndBackground];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(layoutRadiusChanged) name:LCOSLayoutDidChangeNotification object:nil];
    [self updateInteractionState];
    
    // Restore launcher state: if auto-restore enabled and was visible, show immediately
    BOOL wasVisible = LCOSAutoRestoreEnabled() && [self loadLauncherState];
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
    // Restore desktop without animation so the native UI never flashes.
    [UIView setAnimationsEnabled:NO];
    [self showLauncher];
    if (self.launcherContainer) {
        self.launcherContainer.view.alpha = 1.0;
        self.launcherContainer.view.transform = CGAffineTransformIdentity;
    }
    [UIView setAnimationsEnabled:YES];
}

- (void)showLauncher {
    if (self.isLauncherVisible) return;
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

    [self.overlayWindow.rootViewController.view bringSubviewToFront:self.rightEdgeZone];
    [self.overlayWindow.rootViewController.view bringSubviewToFront:self.navigationBar];
    // Save state
    [self saveLauncherState];
    [self updateInteractionState];
}

- (void)hideLauncher {
    if (!self.isLauncherVisible || self.launcherTransitionActive) return;
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
    // Disabling a long-press while it tracks the Dock cancels the active
    // transition immediately. Keep it alive until the gesture ends.
    self.nativeDockGesture.enabled = self.dockTransitionActive || (!self.isLauncherVisible && !self.isBackgroundVisible);
    self.launcherDismissGesture.enabled = self.isLauncherVisible && !self.dockTransitionActive && !self.isBackgroundVisible;
    self.rightEdgeZone.hidden = NO;
    self.navigationBar.hidden = NO;
    self.overlayWindow.hidden = NO;
}

- (void)setupNavigationAndBackground {
    if (self.navigationBar) return;
    UIView *root = self.overlayWindow.rootViewController.view;
    CGFloat zoneWidth = MAX(32.0, root.bounds.size.width * 0.07);
    CGFloat barWidth = 23.0;
    CGFloat barHeight = 134.0;
    self.navigationBar = [[LCOSNavigationBar alloc] initWithFrame:CGRectMake(root.bounds.size.width - 9.0 - barWidth,
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
    [root addSubview:self.rightEdgeZone];
    [root bringSubviewToFront:self.navigationBar];
}

- (void)handleRightEdgeGesture:(UIPanGestureRecognizer *)gesture {
    CGFloat width = self.overlayWindow.bounds.size.width;
    CGPoint point = [gesture locationInView:self.overlayWindow];
    CGFloat zoneWidth = MAX(32.0, width * 0.07);
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (self.launcherTransitionActive || self.overlayWindow.rootViewController.presentedViewController || point.x < width - zoneWidth) {
            gesture.enabled = NO;
            gesture.enabled = YES;
            return;
        }
        [self cancelEdgeDwell];
        self.edgeTransitionActive = YES;
        self.edgeDwellReached = NO;
        self.edgeLaunchingBackground = NO;
        self.edgeStartX = point.x;
        [self.overlayWindow.rootViewController.view bringSubviewToFront:self.rightEdgeZone];
        [self.overlayWindow.rootViewController.view bringSubviewToFront:self.navigationBar];
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@YES];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeNavigationBar) object:nil];
        self.navigationBar.transform = CGAffineTransformIdentity;
        [UIView animateWithDuration:0.18 animations:^{ self.navigationBar.alpha = 1.0; }];
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
        [self scheduleEdgeDwell];
    } else if (self.edgeTransitionActive && gesture.state == UIGestureRecognizerStateChanged) {
        if (self.edgeLaunchingBackground) return;
        CGFloat travel = point.x - self.edgeStartX;
        if (ABS(travel) > 12.0) [self cancelEdgeDwell];
        if (self.edgeDwellReached) {
            [self.backgroundView setTransitionProgress:MIN(1.0, MAX(0, travel / 80.0))];
        } else if (self.isBackgroundVisible) {
            [self updateEdgeInteractivePosition:MAX(0, travel)];
        } else if (travel > 0 && !self.launcherTransitionActive) {
            [self updateEdgeInteractivePosition:travel];
        }
        [self scheduleEdgeDwell];
    } else if (self.edgeTransitionActive &&
               (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed)) {
        [self cancelEdgeDwell];
        self.edgeDwellReached = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@NO];
        BOOL returnsHome = !self.edgeLaunchingBackground && gesture.state == UIGestureRecognizerStateEnded &&
            point.x - self.edgeStartX > 55.0 && [gesture velocityInView:self.overlayWindow].x > 350.0;
        [self finishEdgeTransitionReturningHome:returnsHome cancelled:gesture.state != UIGestureRecognizerStateEnded];
        self.edgeLaunchingBackground = NO;
    }
}

- (void)updateEdgeInteractivePosition:(CGFloat)travel {
    if (self.isBackgroundVisible) {
        [self.backgroundView setTransitionProgress:1.0 - MIN(1.0, MAX(0, travel / 180.0))];
    } else if (self.isLauncherVisible) {
        CGFloat width = self.launcherContainer.view.bounds.size.width;
        self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(MAX(0, travel), 0);
        self.navigationBar.transform = CGAffineTransformMakeTranslation(MAX(0, travel) - width, 0);
    } else {
        self.navigationBar.transform = CGAffineTransformMakeTranslation(-MIN(40, MAX(0, travel)), 0);
    }
}

- (void)finishEdgeTransitionReturningHome:(BOOL)returningHome cancelled:(BOOL)cancelled {
    if (self.isBackgroundVisible) {
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0 options:0 animations:^{
            [self.backgroundView setTransitionProgress:returningHome ? 0.0 : 1.0];
            self.navigationBar.transform = CGAffineTransformIdentity;
            self.navigationBar.alpha = returningHome ? 0.65 : 0.0;
        } completion:^(BOOL finished) {
            self.edgeTransitionActive = NO;
            if (returningHome) [self hideBackground];
            [self performSelector:@selector(fadeNavigationBar) withObject:nil afterDelay:1.8];
        }];
        return;
    }
    if (self.isLauncherVisible && returningHome) {
        self.launcherTransitionActive = YES;
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:0 animations:^{
            self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(self.launcherContainer.view.bounds.size.width, 0);
            self.navigationBar.transform = CGAffineTransformIdentity;
            self.navigationBar.alpha = 0;
        } completion:^(BOOL finished) {
            [self finishHidingLauncher];
            self.edgeTransitionActive = NO;
        }];
        return;
    }
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:0 animations:^{
        self.launcherContainer.view.transform = CGAffineTransformIdentity;
        self.navigationBar.transform = CGAffineTransformIdentity;
        self.navigationBar.alpha = 0;
    } completion:^(BOOL finished) {
        self.edgeTransitionActive = NO;
        [self fadeNavigationBar];
    }];
}

- (void)scheduleEdgeDwell {
    if (self.edgeLaunchingBackground || self.edgeDwellReached || self.isBackgroundVisible) return;
    [self cancelEdgeDwell];
    self.edgeDwellTimer = [NSTimer scheduledTimerWithTimeInterval:0.9 repeats:NO block:^(NSTimer *timer) {
        if (!self.edgeTransitionActive || self.isBackgroundVisible) return;
        self.edgeDwellReached = YES;
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
        [feedback impactOccurred];
        [self showBackground];
        self.edgeLaunchingBackground = YES;
    }];
}

- (void)cancelEdgeDwell {
    [self.edgeDwellTimer invalidate];
    self.edgeDwellTimer = nil;
}

- (void)fadeNavigationBar {
    if (self.edgeTransitionActive) return;
    [UIView animateWithDuration:0.3 animations:^{ self.navigationBar.alpha = 0.0; }];
}

- (void)prepareBackgroundForCurrentInterface {
    if (!self.backgroundView) {
        self.backgroundView = [[LCOSBackgroundView alloc] initWithFrame:self.overlayWindow.rootViewController.view.bounds];
        self.backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        __weak typeof(self) weakSelf = self;
        self.backgroundView.onClose = ^{ [weakSelf hideBackground]; };
        self.backgroundView.onEmptySpaceTapped = ^{ [weakSelf hideBackground]; };
    }
    // The visible host layer is authoritative: native UI remains native and
    // the LCOS desktop remains LCOS when the switcher is dismissed.
    self.navigationBar.hidden = YES;
    self.rightEdgeZone.hidden = YES;
    [self.backgroundView prepareWithCurrentInterface:self.overlayWindow];
    self.navigationBar.hidden = NO;
    self.rightEdgeZone.hidden = NO;
    if (!self.backgroundView.superview) [self.overlayWindow.rootViewController.view addSubview:self.backgroundView];
    if ([self.overlayWindow isKindOfClass:LCOSPassThroughWindow.class]) {
        ((LCOSPassThroughWindow *)self.overlayWindow).backgroundView = self.backgroundView;
    }
    [self.overlayWindow.rootViewController.view bringSubviewToFront:self.backgroundView];
    [self.overlayWindow.rootViewController.view bringSubviewToFront:self.navigationBar];
    self.backgroundView.hidden = NO;
}

- (void)animateBackgroundProgress:(CGFloat)progress completion:(void (^)(void))completion {
    [UIView animateWithDuration:0.38 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0 options:0 animations:^{
        [self.backgroundView setTransitionProgress:progress];
    } completion:^(BOOL finished) { if (completion) completion(); }];
}

- (void)showBackground {
    if (self.isBackgroundVisible) return;
    [self prepareBackgroundForCurrentInterface];
    [self.backgroundView setApps:[LCOSAppModel allInstalledApps]];
    [self.backgroundView setTransitionProgress:0.35];
    self.isBackgroundVisible = YES;
    [self updateInteractionState];
    [self animateBackgroundProgress:1.0 completion:nil];
}

- (void)hideBackground {
    if (!self.isBackgroundVisible) return;
    [self animateBackgroundProgress:0.0 completion:^{
        self.backgroundView.hidden = YES;
        [self.backgroundView removeFromSuperview];
        if ([self.overlayWindow isKindOfClass:LCOSPassThroughWindow.class]) {
            ((LCOSPassThroughWindow *)self.overlayWindow).backgroundView = nil;
        }
        self.isBackgroundVisible = NO;
        [self updateInteractionState];
        [self performSelector:@selector(fadeNavigationBar) withObject:nil afterDelay:1.8];
    }];
}

- (void)layoutRadiusChanged {
    if (self.launcherTransitionActive || self.dockTransitionActive) [self setLauncherRoundedCorners:YES];
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

- (void)handleNativeDockGesture:(UILongPressGestureRecognizer *)gesture {
    if (self.isBackgroundVisible || (self.isLauncherVisible && !self.dockTransitionActive)) return;
    CGPoint location = [gesture locationInView:self.overlayWindow];
    if (gesture.state == UIGestureRecognizerStateBegan) {
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
    } else if (self.dockTransitionActive && (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled)) {
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
    [self showLauncher];
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
        [self updateInteractionState];
    }];
}

- (void)handleLauncherDismissGesture:(UIPanGestureRecognizer *)gesture {
    if (self.isBackgroundVisible || !self.isLauncherVisible) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
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