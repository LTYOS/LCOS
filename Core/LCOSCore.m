//
//  LCOSCore.m
//  LCOS.dylib
//

#import "LCOSCore.h"
#import "LCOSFloatingButton.h"
#import "LCOSLauncherView.h"
#import "LCOSGestureHandler.h"
#import "LCOSLogManager.h"

static LCOSCore *_sharedInstance = nil;

@implementation LCOSCore

+ (void)load {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS load: +load invoked"];
    [LCOSCore sharedInstance];
    // Initialize the core (overlay window, floating button) immediately
    [[LCOSCore sharedInstance] initialize];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS load: initialize complete"];
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

- (void)initialize {
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: initialize START"];
    
    // Create overlay window (like LCOrbitOverlayManager)
    if (@available(iOS 13.0, *)) {
        UIScene *scene = [UIApplication sharedApplication].connectedScenes.anyObject;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene) {
            self.overlayWindow = [[UIWindow alloc] initWithWindowScene:windowScene];
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
            
            // Add floating button to overlay window
            [self.overlayWindow.rootViewController.view addSubview:self.floatingButton];
            
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: overlayWindow created level=%ld", (long)self.overlayWindow.windowLevel]];
        }
    } else {
        // iOS 12 fallback
        self.overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self.overlayWindow.backgroundColor = [UIColor clearColor];
        self.overlayWindow.windowLevel = UIWindowLevelNormal + 100;
        self.overlayWindow.hidden = YES;
        
        UIViewController *rootVC = [[UIViewController alloc] init];
        rootVC.view.backgroundColor = [UIColor clearColor];
        self.overlayWindow.rootViewController = rootVC;
        
        self.floatingButton = [LCOSFloatingButton sharedButton];
        
        [self.overlayWindow.rootViewController.view addSubview:self.floatingButton];
    }
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: initialize COMPLETE"];
    
    // Register gesture recognizers (three-finger long press for settings)
    [LCOSGestureHandler registerGestureRecognizers];
    
    // Show floating button
    [self showFloatingButton];
}

- (void)showLauncher {
    if (self.isLauncherVisible) return;
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: showLauncher"];
    
    // Ensure overlay window is visible
    self.overlayWindow.hidden = NO;
    
    // Create launcher view if needed
    if (!self.launcherView) {
        self.launcherView = [[LCOSLauncherView alloc] init];
        self.launcherView.view.frame = self.overlayWindow.rootViewController.view.bounds;
        self.launcherView.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    
    // Add launcher to overlay window (on top of floating button)
    [self.overlayWindow.rootViewController.view addSubview:self.launcherView.view];
    [self.overlayWindow.rootViewController.view bringSubviewToFront:self.launcherView.view];
    
    // Animate in
    self.launcherView.view.alpha = 0.0;
    [UIView animateWithDuration:0.3 animations:^{
        self.launcherView.view.alpha = 1.0;
    }];
    
    self.isLauncherVisible = YES;
    
    // Hide floating button when launcher is shown
    self.floatingButton.hidden = YES;
}

- (void)hideLauncher {
    if (!self.isLauncherVisible) return;
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: hideLauncher"];
    
    [UIView animateWithDuration:0.3 animations:^{
        self.launcherView.view.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self.launcherView.view removeFromSuperview];
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