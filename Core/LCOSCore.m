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
// BUT gesture recognizers on the window itself still work
// AND visible child view controllers receive touches normally
@interface LCOSPassThroughWindow : UIWindow
@property (nonatomic, weak) UIViewController *launcherContainer; // For touch handling when launcher is visible
@property (nonatomic, weak) UIView *gestureView; // Full-screen view for gesture recognition
@end

@implementation LCOSPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!event || event.type == UIEventTypeTouches) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSOverlayScreenTouchedNotification" object:nil];
    }
    UIView *target = [super hitTest:point withEvent:event];
    
    // If launcher container is visible and touch is on it, let it handle normally
    if (self.launcherContainer && [self.launcherContainer isViewLoaded]) {
        UIView *launcherView = self.launcherContainer.view;
        if (launcherView && !launcherView.hidden && launcherView.alpha > 0.01) {
            CGPoint localPoint = [launcherView convertPoint:point fromView:self];
            if (CGRectContainsPoint(launcherView.bounds, localPoint)) {
                return [super hitTest:point withEvent:event]; // Normal hit test for launcher
            }
        }
    }
    
    // If gestureView exists and touch is on it, let it receive for gesture recognizers
    if (self.gestureView && !self.gestureView.hidden && self.gestureView.alpha > 0.01) {
        CGPoint localPoint = [self.gestureView convertPoint:point fromView:self];
        if (CGRectContainsPoint(self.gestureView.bounds, localPoint)) {
            return self.gestureView; // Let gestureView handle touches for its gesture recognizers
        }
    }
    
    // Pass through only for root view controller's transparent view
    return (target == self.rootViewController.view) ? nil : target;
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
            
            // Create full-screen gesture view (transparent) for gesture recognition
            UIView *gestureView = [[UIView alloc] initWithFrame:rootVC.view.bounds];
            gestureView.backgroundColor = [UIColor clearColor];
            gestureView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            gestureView.userInteractionEnabled = YES;
            [rootVC.view addSubview:gestureView];
            
            if ([self.overlayWindow isKindOfClass:[LCOSPassThroughWindow class]]) {
                ((LCOSPassThroughWindow *)self.overlayWindow).gestureView = gestureView;
            }
            
            // Create floating button
            self.floatingButton = [LCOSFloatingButton sharedButton];
            
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
        
        // Create full-screen gesture view
        UIView *gestureView = [[UIView alloc] initWithFrame:rootVC.view.bounds];
        gestureView.backgroundColor = [UIColor clearColor];
        gestureView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        gestureView.userInteractionEnabled = YES;
        [rootVC.view addSubview:gestureView];
        
        if ([self.overlayWindow isKindOfClass:[LCOSPassThroughWindow class]]) {
            ((LCOSPassThroughWindow *)self.overlayWindow).gestureView = gestureView;
        }
        
        self.floatingButton = [LCOSFloatingButton sharedButton];
    }
    
    // Register gesture recognizers on gestureView (three-finger long press for settings)
    [self registerGesturesOnGestureView];
    
    // Show floating button
    [self showFloatingButton];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: initialize COMPLETE"];
}

// Register gesture recognizers on gestureView (three-finger long press for settings)
- (void)registerGesturesOnGestureView {
    if (!self.overlayWindow) return;
    
    // Get gestureView from pass-through window
    UIView *gestureView = nil;
    if ([self.overlayWindow isKindOfClass:[LCOSPassThroughWindow class]]) {
        gestureView = ((LCOSPassThroughWindow *)self.overlayWindow).gestureView;
    }
    if (!gestureView) return;
    
    // Register three-finger long press on gestureView
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
        initWithTarget:self action:@selector(handleThreeFingerLongPress:)];
    longPress.numberOfTouchesRequired = 3;
    longPress.minimumPressDuration = 1.0;
    // Don't cancel touches - let them pass through to LiveContainer
    longPress.cancelsTouchesInView = NO;
    [gestureView addGestureRecognizer:longPress];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Three-finger long press registered on gestureView"];
}

// Handle three-finger long press on overlay window
- (void)handleThreeFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Three finger long press on overlay - showing settings"];
        
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
                    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Settings presented from overlay"];
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
    
    // Get gestureView from pass-through window
    UIView *gestureView = nil;
    if ([self.overlayWindow isKindOfClass:[LCOSPassThroughWindow class]]) {
        gestureView = ((LCOSPassThroughWindow *)self.overlayWindow).gestureView;
    }
    
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
        // Allow other gestures to receive touches simultaneously
        longPress.cancelsTouchesInView = NO;
        [self.launcherContainer.view addGestureRecognizer:longPress];
        
        [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Three-finger long press registered on launcher container"];
    }
    
    // Add launcher as child view controller (for proper safeAreaLayoutGuide)
    // Add launcherContainer ABOVE gestureView but BELOW floatingButton
    [self.overlayWindow.rootViewController addChildViewController:self.launcherContainer];
    [self.overlayWindow.rootViewController.view insertSubview:self.launcherContainer.view aboveSubview:gestureView];
    
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
    
    // Allow simultaneous gesture recognition between gestureView and launcher container
    UILongPressGestureRecognizer *gestureViewLongPress = nil;
    if (gestureView) {
        for (UIGestureRecognizer *gr in gestureView.gestureRecognizers) {
            if ([gr isKindOfClass:[UILongPressGestureRecognizer class]]) {
                UILongPressGestureRecognizer *lp = (UILongPressGestureRecognizer *)gr;
                if (lp.numberOfTouchesRequired == 3) {
                    gestureViewLongPress = lp;
                    break;
                }
            }
        }
    }
    UILongPressGestureRecognizer *launcherLongPress = nil;
    for (UIGestureRecognizer *gr in self.launcherContainer.view.gestureRecognizers) {
        if ([gr isKindOfClass:[UILongPressGestureRecognizer class]]) {
            UILongPressGestureRecognizer *lp = (UILongPressGestureRecognizer *)gr;
            if (lp.numberOfTouchesRequired == 3) {
                launcherLongPress = lp;
                break;
            }
        }
    }
    if (gestureViewLongPress && launcherLongPress) {
        // Both can recognize simultaneously - launcher has priority when visible
        [gestureViewLongPress requireGestureRecognizerToFail:launcherLongPress];
        [launcherLongPress requireGestureRecognizerToFail:gestureViewLongPress];
    }
    
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

@end