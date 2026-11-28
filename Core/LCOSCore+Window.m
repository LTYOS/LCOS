#import "LCOSCore+Private.h"
#import "LCOSLogManager.h"

// Transparent regions pass touches to the native host. Only an active shell's
// background or actual navigation zone may consume touches.

@interface LCOSNavigationTouchZone () <UIGestureRecognizerDelegate>
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
    // Modal controllers presented in this window own their touches. Without
    // this early return the alert's confirmation button falls through to the
    // underlying LiveContainer window and can never be tapped.
    if (self.rootViewController.presentedViewController) {
        return [super hitTest:point withEvent:event];
    }
    if (!event || event.type == UIEventTypeTouches) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"LCOSOverlayScreenTouchedNotification" object:nil];
    }
    
    if (self.backgroundView && !self.backgroundView.hidden && self.backgroundView.alpha > 0.01) {
        return [super hitTest:point withEvent:event];
    }
    // Match the actual vertical navigation zone, not an invisible full-height strip.
    if (self.navigationTouchZone && !self.navigationTouchZone.hidden) {
        CGPoint localPoint = [self.navigationTouchZone convertPoint:point fromView:self];
        if ([self.navigationTouchZone pointInside:localPoint withEvent:event]) {
            // Shell edge zones are siblings of the launcher, not its children.
            // Route their narrow touch region explicitly before grid hit-testing.
            return self.navigationTouchZone;
        }
    }
    // 1. While the desktop is visible, hit-test its own view hierarchy only.
    // Calling super here would also include sibling NativeShell edge zones,
    // allowing the inactive shell to steal navigation and background gestures.
    if (self.launcherContainer && [self.launcherContainer isViewLoaded]) {
        UIView *launcherView = self.launcherContainer.view;
        if (launcherView && !launcherView.hidden && launcherView.alpha > 0.01) {
            CGPoint localPoint = [launcherView convertPoint:point fromView:self];
            if (CGRectContainsPoint(launcherView.bounds, localPoint)) {
                UIView *target = [launcherView hitTest:localPoint withEvent:event];
                [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS PassThroughWindow: launcher owns touch target=%@", target.class]];
                return target ?: launcherView;
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

@implementation LCOSCore (Window)

- (void)showBackground {
    if (self.isLauncherVisible) [self.lcosShell showBackground];
    else [self.nativeShell showBackground];
}

- (void)hideBackground {
    [self.nativeShell hideBackground];
    [self.lcosShell hideBackground];
}

- (BOOL)isBackgroundVisible {
    return self.nativeShell.isBackgroundVisible || self.lcosShell.isBackgroundVisible;
}

- (UIView *)navigationTouchZone {
    if (self.isBackgroundVisible) return nil;
    if (self.isLauncherVisible) return self.lcosShell.navigationZone;
    return self.nativeShell.navigationZone;
}

@end
