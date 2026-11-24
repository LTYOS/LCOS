//
//  LCOSCore.m
//  LCOS.dylib
//

#import "LCOSCore.h"
#import "LCOSFloatingButton.h"
#import "LCOSLauncherView.h"
#import "LCOSGestureHandler.h"
#import "LCOSLogManager.h"
#import <objc/runtime.h>

// Pass-through window - like LCOrbitPassThroughWindow
// Transparent regions pass touches to underlying windows
// BUT gesture recognizers on the window work for multi-finger gestures when appropriate
// AND visible child view controllers (launcher, floating button) receive touches normally
@interface LCOSPassThroughWindow : UIWindow
@property (nonatomic, weak) UIViewController *launcherContainer; // For touch handling when launcher is visible
@property (nonatomic, weak) LCOSFloatingButton *floatingButton; // For touch handling
@end

@implementation LCOSPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!event || event.type == UIEventTypeTouches) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSOverlayScreenTouchedNotification" object:nil];
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
    
    // 2. If floating button is visible and touch is on it, let it handle
    if (self.floatingButton && !self.floatingButton.hidden && self.floatingButton.alpha > 0.01) {
        CGPoint localPoint = [self.floatingButton convertPoint:point fromView:self];
        // Use expanded bounds like floatingButton's hitTest
        CGRect expandedBounds = CGRectInset(self.floatingButton.bounds, -20, -20);
        if (CGRectContainsPoint(expandedBounds, localPoint)) {
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS PassThroughWindow: hitTest -> floatingButton (point=%@)", NSStringFromCGPoint(point)]];
            return [super hitTest:point withEvent:event]; // Normal hit test for button
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

// Debug hitTest
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = [super hitTest:point withEvent:event];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS LauncherContainer: hitTest point=%@ -> %@", NSStringFromCGPoint(point), result ? result.description : @"nil"]];
    return result;
}
@end

static LCOSCore *_sharedInstance = nil;

// Class extension for private properties
@interface LCOSCore ()
@property (nonatomic, strong) UILongPressGestureRecognizer *overlayLongPressGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *launcherLongPressGesture;
@end

@implementation LCOSCore

+ (void)load {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS load: +load invoked"];
    // Use dispatch_once to ensure initialization runs exactly once
    static dispatch_once_t initializationToken;
    dispatch_once(&initializationToken, ^{
        // Don't initialize immediately - wait for app to be ready
        dispatch_async(dispatch_get_main_queue(), ^{
            [[LCOSCore sharedInstance] initialize];
            [[LCOSLogManager sharedManager] forceLog:@"LCOS load: delayed initialize complete"];
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

- (void)initialize {
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
            
            // Create floating button
            self.floatingButton = [LCOSFloatingButton sharedButton];
            
            // Set floatingButton on pass-through window for touch handling
            if ([self.overlayWindow isKindOfClass:[LCOSPassThroughWindow class]]) {
                ((LCOSPassThroughWindow *)self.overlayWindow).floatingButton = self.floatingButton;
            }
            
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
        
        self.floatingButton = [LCOSFloatingButton sharedButton];
        
        if ([self.overlayWindow isKindOfClass:[LCOSPassThroughWindow class]]) {
            ((LCOSPassThroughWindow *)self.overlayWindow).floatingButton = self.floatingButton;
        }
    }
    
    // Register gesture recognizers on overlay window (three-finger long press for settings)
    [self registerGesturesOnOverlayWindow];
    
    // Show floating button
    [self showFloatingButton];
    
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
                
                UIScene *scene = [UIApplication sharedApplication].connectedScenes.anyObject;
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                UIWindow *window = windowScene.windows.firstObject;
                if (window && window.rootViewController) {
                    [window.rootViewController presentViewController:settingsView animated:YES completion:nil];
                    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Settings presented"];
                }
            }
        });
    }
}

- (void)showLauncher {
    if (self.isLauncherVisible) return;
    
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
    
    // Add launcher as child view controller (for proper safeAreaLayoutGuide)
    // Add launcherContainer to rootVC view (floatingButton is also on rootVC view)
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
    
    // Animate in
    self.launcherContainer.view.alpha = 0.0;
    [UIView animateWithDuration:0.3 animations:^{
        self.launcherContainer.view.alpha = 1.0;
    }];
    
    self.isLauncherVisible = YES;
    
    // Hide floating button when launcher is shown
    self.floatingButton.hidden = YES;
}

- (void)hideLauncher {
    if (!self.isLauncherVisible) return;
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: hideLauncher"];
    
    [UIView animateWithDuration:0.3 animations:^{
        self.launcherContainer.view.alpha = 0.0;
    } completion:^(BOOL finished) {
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
        
        // Show floating button again
        self.floatingButton.hidden = NO;
        [self.floatingButton showOnWindow:self.overlayWindow];
    }];
}

- (void)toggleLauncher {
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: toggleLauncher"];
    if (self.isLauncherVisible) {
        [self hideLauncher];
    } else {
        [self showLauncher];
    }
}

- (void)showFloatingButton {
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: showFloatingButton"];
    
    if (!self.overlayWindow || !self.overlayWindow.rootViewController) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: showFloatingButton - no overlayWindow/rootVC, retrying"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showFloatingButton];
        });
        return;
    }
    
    self.overlayWindow.hidden = NO;
    self.floatingButton.hidden = NO;
    [self.floatingButton showOnWindow:self.overlayWindow];
}

- (void)hideFloatingButton {
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: hideFloatingButton"];
    [self.floatingButton hide];
    self.overlayWindow.hidden = YES;
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