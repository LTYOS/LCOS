#import "LCOSCore+Private.h"
#import "LCOSLogManager.h"
#import "LCOSLayout.h"
#import <objc/message.h>

// Launcher container view controller for proper child VC management
@interface LCOSLauncherContainerVC : UIViewController
@end

@implementation LCOSLauncherContainerVC
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end


@implementation LCOSCore (Lifecycle)

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
    if (self.isLauncherVisible || self.isBackgroundVisible ||
        (self.launcherTransitionActive && !self.dockTransitionActive)) return;
    if (!self.isLauncherVisible) self.launcherTransitionActive = YES;
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: creation started"];
    
    // Ensure overlay window is visible
    self.overlayWindow.hidden = NO;
    
    // Own the content controller before attaching the container. Never pass a
    // nil or foreign object into UIKit's childViewControllers array.
    if (!self.launcherView) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: content controller allocation"];
        self.launcherView = [[LCOSLauncherView alloc] init];
    }
    Class launcherClass = LCOSLauncherView.class;
    BOOL expectedType = [self.launcherView isKindOfClass:launcherClass];
    BOOL controllerType = [self.launcherView isKindOfClass:UIViewController.class];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
        @"LCOS Launcher: identity actual=%@ expected=%@ matches=%d controller=%d",
        self.launcherView ? NSStringFromClass([self.launcherView class]) : @"nil",
        NSStringFromClass(launcherClass), expectedType, controllerType]];
    if (!expectedType || !controllerType) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: invalid content controller, creation aborted"];
        self.launcherView = nil;
        self.launcherTransitionActive = NO;
        [self updateInteractionState];
        return;
    }
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: content controller validated"];
    
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
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: controllers created"];
    UIViewController *rootController = self.overlayWindow.rootViewController;
    if (![rootController isKindOfClass:UIViewController.class] ||
        ![self.launcherContainer isKindOfClass:UIViewController.class] ||
        self.launcherContainer.parentViewController && self.launcherContainer.parentViewController != rootController) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: invalid root or container parent, creation aborted"];
        [self cancelDockPreparation];
        return;
    }
    if (self.launcherContainer.parentViewController != rootController) {
        [rootController addChildViewController:self.launcherContainer];
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: container child attached"];
    }
    if (self.launcherContainer.view.superview != rootController.view) {
        [rootController.view addSubview:self.launcherContainer.view];
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: container view attached"];
    }
    [rootController.view bringSubviewToFront:self.launcherContainer.view];
    [self.launcherContainer didMoveToParentViewController:rootController];
    
    if (self.launcherView.parentViewController && self.launcherView.parentViewController != self.launcherContainer) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: content already belongs to another parent"];
        [self cancelDockPreparation];
        return;
    }
    if (self.launcherView.parentViewController != self.launcherContainer) {
        [self.launcherContainer addChildViewController:self.launcherView];
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: content child attached"];
    }
    UIView *contentView = self.launcherView.view;
    if (!contentView || self.launcherContainer.view.window == nil) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: content view or window unavailable"];
        [self cancelDockPreparation];
        return;
    }
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: content view loaded"];
    contentView.frame = self.launcherContainer.view.bounds;
    contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (contentView.superview != self.launcherContainer.view) {
        [self.launcherContainer.view addSubview:contentView];
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: content view attached"];
    }
    [self.launcherView didMoveToParentViewController:self.launcherContainer];
    [self.lcosShell setLauncherView:self.launcherContainer.view];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: controllers mounted"];
    
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
    
    self.isLauncherVisible = !self.dockTransitionActive;
    
    if (!self.launcherDismissGesture) {
        self.launcherDismissGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleLauncherDismissGesture:)];
        self.launcherDismissGesture.minimumNumberOfTouches = 3;
        self.launcherDismissGesture.maximumNumberOfTouches = 3;
        self.launcherDismissGesture.delegate = self;
        [self.launcherContainer.view addGestureRecognizer:self.launcherDismissGesture];
    }

    self.rightEdgeZone.hidden = YES;
    self.navigationBar.hidden = YES;
    // An interactive Dock presentation is not visible until it completes.
    // Saving early makes the next upward gesture reject itself.
    if (self.isLauncherVisible) [self saveLauncherState];
    [self updateInteractionState];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: presentation mounted"];
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
        if (self.launcherView.isViewLoaded) [self.launcherView.view removeFromSuperview];
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

- (void)showLauncherForDockInteraction {
    // dockTransitionActive is the sole reentry guard for Dock presentation.
    [self showLauncher];
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

@end
