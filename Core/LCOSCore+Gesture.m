#import "LCOSCore+Private.h"
#import "LCOSLogManager.h"
#import "LCOSLayout.h"
#import <objc/message.h>

@implementation LCOSCore (Gesture)

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
    UIPanGestureRecognizer *gesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleNativeDockGesture:)];
    gesture.minimumNumberOfTouches = 1;
    gesture.maximumNumberOfTouches = 1;
    gesture.cancelsTouchesInView = NO;
    gesture.delegate = self;
    [dock addGestureRecognizer:gesture];
    self.nativeDockGesture = gesture;
    gesture.enabled = !self.isLauncherVisible;
    [[LCOSLogManager sharedManager] forceLog:@"LCOSCore: native Dock single-finger upward pan installed"];
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

- (void)handleNativeDockGesture:(UIPanGestureRecognizer *)gesture {
    if (self.isBackgroundVisible || self.isGuestNavigation || (self.isLauncherVisible && !self.dockTransitionActive)) return;
    CGPoint location = [gesture locationInView:self.overlayWindow];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Dock: upward gesture began"];
        if (![self canSwitchShellFromLCOS:NO]) {
            [[LCOSLogManager sharedManager] forceLog:@"LCOS Dock: blocked by running tasks"];
            gesture.enabled = NO;
            gesture.enabled = YES;
            return;
        }
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Dock: gate passed, creating launcher"];
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@YES];
        self.dockTransitionActive = YES;
        self.dockGestureStart = location;
        [self prepareLauncherForInteractivePresentation];
    } else if (self.dockTransitionActive && gesture.state == UIGestureRecognizerStateChanged) {
        if (self.dockPreparingLauncher || !self.launcherContainer) return;
        CGFloat upward = MAX(0.0, self.dockGestureStart.y - location.y);
        CGFloat height = self.launcherContainer.view.bounds.size.height;
        self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(0, MAX(0.0, height - upward));
    } else if (self.dockTransitionActive && (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed)) {
        CGFloat upward = MAX(0.0, self.dockGestureStart.y - location.y);
        BOOL shouldOpen = gesture.state == UIGestureRecognizerStateEnded && upward > self.overlayWindow.bounds.size.height * 0.18;
        [self completeDockPresentation:shouldOpen];
    }
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

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.nativeDockGesture) {
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.nativeDock];
        BOOL upward = velocity.y < -30 && fabs(velocity.y) > fabs(velocity.x);
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Dock: direction accepted=%d", upward]];
        return upward;
    }
    if (gestureRecognizer == self.launcherDismissGesture) {
        // Never compete with one-finger horizontal paging in the app grid.
        // The three-finger dismiss gesture is only eligible for three touches.
        return gestureRecognizer.numberOfTouches == 3;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: gestureRecognizer shouldReceiveTouch gesture=%@ touchView=%@", gestureRecognizer, touch.view]];
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSCore: shouldRecognizeSimultaneously %@ with %@", gestureRecognizer, otherGestureRecognizer]];
    return YES;
}

@end
