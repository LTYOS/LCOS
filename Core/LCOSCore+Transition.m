#import "LCOSCore+Private.h"
#import "LCOSLogManager.h"
#import "LCOSLayout.h"
#import <objc/message.h>

@implementation LCOSCore (Transition)

- (void)setLauncherRoundedCorners:(BOOL)rounded {
    UIView *view = self.launcherContainer.view;
    view.layer.cornerRadius = rounded ? [LCOSLayout value:@"sheetRadius"] : 0.0;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.maskedCorners = rounded ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner) : 0;
    view.layer.masksToBounds = rounded;
}

- (void)prepareLauncherForInteractivePresentation {
    if (self.dockPreparingLauncher) return;
    self.dockPreparingLauncher = YES;
    self.dockEndedWhilePreparing = NO;
    // Do not create and attach the entire controller tree inside a gesture
    // callback. UIKit can otherwise lay out a half-attached desktop.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.dockTransitionActive) {
            self.dockPreparingLauncher = NO;
            return;
        }
        @try {
            [self showLauncherForDockInteraction];
            if (!self.launcherContainer || !self.launcherView.viewIfLoaded.window) {
                [[LCOSLogManager sharedManager] forceLog:@"LCOS Dock: launcher not attached"];
                [self cancelDockPreparation];
                return;
            }
            [self.launcherContainer.view setNeedsLayout];
            [self.launcherContainer.view layoutIfNeeded];
            [self.launcherContainer.view.layer removeAllAnimations];
            self.launcherTransitionActive = YES;
            self.dockPreparingLauncher = NO;
            CGFloat upward = MAX(0, self.dockGestureStart.y - [self.nativeDockGesture locationInView:self.overlayWindow].y);
            self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(0, MAX(0, self.launcherContainer.view.bounds.size.height - upward));
            [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: first layout completed"];
            if (self.dockEndedWhilePreparing) {
                self.dockEndedWhilePreparing = NO;
                [self completeDockPresentation:self.dockShouldOpenAfterPreparing];
            }
        } @catch (NSException *exception) {
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Dock: preparation exception %@ %@", exception.name, exception.reason]];
            [self cancelDockPreparation];
        }
    });
}

- (void)cancelDockPreparation {
    self.dockPreparingLauncher = NO;
    self.dockEndedWhilePreparing = NO;
    self.dockTransitionActive = NO;
    self.launcherTransitionActive = NO;
    self.isLauncherVisible = NO;
    // A failed preparation must never restore this partial desktop on the next
    // LiveContainer launch. Leave the native UI available instead.
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:kLCOSLauncherVisibleKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@NO];
    if (self.launcherContainer) [self finishHidingLauncher];
    [self updateInteractionState];
}

- (void)completeDockPresentation:(BOOL)shouldOpen {
    if (self.dockPreparingLauncher) {
        self.dockEndedWhilePreparing = YES;
        self.dockShouldOpenAfterPreparing = shouldOpen;
        return;
    }
    self.dockTransitionActive = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSLauncherGestureActive" object:@NO];
    if (shouldOpen) {
        [self finishInteractivePresentation];
    } else {
        self.isLauncherVisible = NO;
        self.launcherTransitionActive = YES;
        [UIView animateWithDuration:0.2 animations:^{
            self.launcherContainer.view.transform = CGAffineTransformMakeTranslation(0, self.launcherContainer.view.bounds.size.height);
        } completion:^(BOOL finished) { [self finishHidingLauncher]; }];
    }
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
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: Dock presentation completed"];
    }];
}

@end
