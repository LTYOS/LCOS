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
@interface LCOSPassThroughWindow : UIWindow
@end

@implementation LCOSPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!event || event.type == UIEventTypeTouches) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSOverlayScreenTouchedNotification" object:nil];
    }
    UIView *target = [super hitTest:point withEvent:event];
    // Pass through if touching empty area (self or root view)
    return (target == self || target == self.rootViewController.view) ? nil : target;
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
        
        self.floatingButton = [LCOSFloatingButton sharedButton];
    }
    
    // Register gesture recognizers on overlay window (three-finger long press for settings)
    [self registerGesturesOnOverlayWindow];
    
    // Show floating button
    [self showFloatingButton];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: initialize COMPLETE"];
}

- (void)registerGesturesOnOverlayWindow {
    // Register three-finger long press on overlay window too
    if (!self.overlayWindow) return;
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
        initWithTarget:self action:@selector(handleThreeFingerLongPress:)];
    longPress.numberOfTouchesRequired = 3;
    longPress.minimumPressDuration = 1.0;
    [self.overlayWindow addGestureRecognizer:longPress];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: Three-finger long press registered on overlay window"];
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
    }
    
    // Add launcher as child view controller (for proper safeAreaLayoutGuide)
    [self.overlayWindow.rootViewController addChildViewController:self.launcherContainer];
    [self.overlayWindow.rootViewController.view addSubview:self.launcherContainer.view];
    [self.overlayWindow.rootViewController.view bringSubviewToFront:self.launcherContainer.view];
    
    // Add launcher view to container
    self.launcherView.view.frame = self.launcherContainer.view.bounds;
    self.launcherView.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.launcherContainer addChildViewController:self.launcherView];
    [self.launcherContainer.view addSubview:self.launcherView.view];
    [self.launcherView didMoveToParentViewController:self.launcherContainer];
    
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
        
        self.isLauncherVisible = NO;
        
        // Show floating button again
        self.floatingButton.hidden = NO;
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