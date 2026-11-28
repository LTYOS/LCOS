#import "LCOSShellController.h"
#import "LCOSTaskRegistry.h"
#import "LCOSBackgroundView.h"
#import "LCOSNavigationBar.h"
#import "LCOSLogManager.h"
#import "LCOSPassThroughWindow.h"
#import "LCOSLaunchBridge.h"

@interface LCOSEdgeZone : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, copy) void (^onPan)(UIPanGestureRecognizer *gesture);
@property (nonatomic, copy) void (^onTap)(void);
@end
@implementation LCOSEdgeZone
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
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
- (void)handleTap:(UITapGestureRecognizer *)gesture { if (gesture.state == UIGestureRecognizerStateEnded && self.onTap) self.onTap(); }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (![recognizer isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:self];
    return velocity.x < -10 && fabs(velocity.x) > fabs(velocity.y);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
@end

@interface LCOSShellController ()
@property (nonatomic, assign) BOOL fromLCOS;
@property (nonatomic, assign) BOOL hasActiveTask;
@property (nonatomic, assign) BOOL isBackgroundVisible;
@property (nonatomic, weak) UIWindow *overlay;
@property (nonatomic, weak) UIView *launcherView;
@property (nonatomic, weak) UIView *navigationZone;
@property (nonatomic, weak) UIView *backgroundView;
@property (nonatomic, strong) LCOSNavigationBar *navigationBar;
@property (nonatomic, strong) LCOSEdgeZone *edgeZone;
@property (nonatomic, strong) UIView *taskStage;
@property (nonatomic, weak) UIView *activeTask;
@property (nonatomic, strong) LCOSBackgroundView *switcher;
@property (nonatomic, strong) NSMutableArray<UIVisualEffectView *> *hostBlurViews;
@property (nonatomic, strong) NSTimer *dwellTimer;
@property (nonatomic, assign) BOOL transitionActive;
@property (nonatomic, assign) BOOL launchingBackground;
@property (nonatomic, assign) BOOL dwellReached;
@property (nonatomic, assign) BOOL lastTaskIsBackground;
@property (nonatomic, assign) CGFloat startX;
@property (nonatomic, assign) CGFloat travel;
@property (nonatomic, strong) NSMutableDictionary *taskState;
@end

@implementation LCOSShellController

- (instancetype)initWithOverlay:(UIWindow *)overlay fromLCOS:(BOOL)fromLCOS {
    self = [super init];
    if (self) {
        _fromLCOS = fromLCOS;
        _overlay = overlay;
        [self setupNavigation];
    }
    return self;
}

- (UIView *)root { return self.overlay.rootViewController.view; }
- (LCOSTaskRegistry *)tasks { return [LCOSTaskRegistry shared]; }
- (NSString *)name { return self.fromLCOS ? @"LCOSShell" : @"NativeShell"; }

- (void)setLauncherView:(UIView *)launcherView { _launcherView = launcherView; }

- (void)setupNavigation {
    UIView *root = self.root;
    CGFloat width = root.bounds.size.width;
    CGFloat zoneWidth = MAX(32.0, width * 0.07);
    CGFloat barWidth = 23.0;
    CGFloat barHeight = 150.0;
    self.navigationBar = [[LCOSNavigationBar alloc] initWithFrame:CGRectMake(width - 2 - barWidth, (root.bounds.size.height - barHeight) / 2, barWidth, barHeight)];
    self.navigationBar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.navigationBar.userInteractionEnabled = NO;
    self.navigationBar.alpha = 0;
    [root addSubview:self.navigationBar];
    self.edgeZone = [[LCOSEdgeZone alloc] initWithFrame:CGRectMake(width - zoneWidth, (root.bounds.size.height - barHeight) / 2 - 44, zoneWidth, barHeight + 88)];
    self.edgeZone.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.edgeZone.backgroundColor = UIColor.clearColor;
    __weak typeof(self) weakSelf = self;
    self.edgeZone.onPan = ^(UIPanGestureRecognizer *gesture) { [weakSelf handleEdge:gesture]; };
    self.edgeZone.onTap = ^{ [weakSelf showTapFeedback]; };
    [root addSubview:self.edgeZone];
    _navigationZone = self.edgeZone;
    [self updateNavigation];
}

- (void)updateNavigation {
    BOOL nativeNavigationEnabled = LCOSNativeInteractionEnabled();
    if (!self.fromLCOS && !nativeNavigationEnabled) {
        // This switch owns only the native navigation strip and switcher.
        // Dock's independent upward gesture remains available.
        if (self.isBackgroundVisible) [self hideBackground];
    }
    BOOL allowed = !self.isBackgroundVisible && (self.fromLCOS || nativeNavigationEnabled);
    if (!self.fromLCOS && (self.launcherView || [self.tasks activeTaskFromLCOS:YES])) allowed = NO;
    self.edgeZone.hidden = !allowed;
    // Hidden zones must not compete for the other shell's edge gestures.
    self.edgeZone.userInteractionEnabled = allowed;
    if (!allowed) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeNavigationBar) object:nil];
        [self.navigationBar.layer removeAllAnimations];
        self.navigationBar.alpha = 0;
        self.navigationBar.transform = CGAffineTransformIdentity;
    }
    [self.root bringSubviewToFront:self.edgeZone];
    [self.root bringSubviewToFront:self.navigationBar];
}

- (void)showTapFeedback {
    if (self.isBackgroundVisible || self.transitionActive) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeNavigationBar) object:nil];
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

- (void)fadeNavigationBar {
    if (self.transitionActive) return;
    [UIView animateWithDuration:0.3 animations:^{ self.navigationBar.alpha = 0; }];
}

- (void)presentTask:(UIView *)task {
    if (![self.tasks isTaskRunning:task]) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: task not running yet", self.name]];
        return;
    }
    self.activeTask = task;
    self.hasActiveTask = YES;
    [self.tasks activateTask:task fromLCOS:self.fromLCOS];
    [task.layer removeAllAnimations];
    task.hidden = NO;
    task.alpha = 1;
    task.userInteractionEnabled = YES;
    [self updateNavigation];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: task active", self.name]];
}

- (void)prepareTaskStage {
    if (self.taskState) return;
    if (!self.activeTask) self.activeTask = [self.tasks activeTaskFromLCOS:self.fromLCOS];
    UIView *task = self.activeTask;
    if (!task || ![self.tasks isTaskRunning:task] || !task.superview) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: no verified active task for transition", self.name]];
        return;
    }
    [task.layer removeAllAnimations];
    self.taskStage = task.superview;
    self.taskState = [@{@"center": [NSValue valueWithCGPoint:task.center], @"frame": [NSValue valueWithCGRect:task.frame],
        @"transform": [NSValue valueWithCGAffineTransform:task.transform],
        @"alpha": @(task.alpha), @"hidden": @(task.hidden), @"radius": @(task.layer.cornerRadius),
        @"interaction": @(task.userInteractionEnabled)} mutableCopy];
    task.userInteractionEnabled = NO;
}

- (void)restoreTaskStage {
    UIView *task = self.activeTask;
    if (task && self.taskState) {
        task.frame = [self.taskState[@"frame"] CGRectValue];
        task.transform = [self.taskState[@"transform"] CGAffineTransformValue];
        task.center = [self.taskState[@"center"] CGPointValue];
        task.alpha = [self.taskState[@"alpha"] doubleValue];
        task.hidden = [self.taskState[@"hidden"] boolValue];
        task.userInteractionEnabled = [self.taskState[@"interaction"] boolValue];
        task.layer.cornerRadius = [self.taskState[@"radius"] doubleValue];
    }
    self.taskState = nil;
    self.taskStage = nil;
}

- (void)handleEdge:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.overlay];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (self.transitionActive || self.isBackgroundVisible || self.overlay.rootViewController.presentedViewController) {
            gesture.enabled = NO;
            gesture.enabled = YES;
            return;
        }
        self.transitionActive = YES;
        self.launchingBackground = NO;
        self.dwellReached = NO;
        self.startX = point.x;
        self.travel = 0;
        self.lastTaskIsBackground = NO;
        [self prepareTaskStage];
        if (self.hasActiveTask && !self.taskState) {
            self.transitionActive = NO;
            self.navigationBar.alpha = 0;
            gesture.enabled = NO;
            gesture.enabled = YES;
            return;
        }
        self.navigationBar.transform = CGAffineTransformIdentity;
        self.navigationBar.alpha = 1;
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: navigation began", self.name]];
    } else if (self.transitionActive && gesture.state == UIGestureRecognizerStateChanged) {
        if (self.launchingBackground) return;
        self.travel = MAX(0, self.startX - point.x);
        if (self.travel >= 8) [self scheduleDwell];
        else { [self cancelDwell]; self.dwellReached = NO; }
        [self updateInteractiveProgress];
    } else if (self.transitionActive && (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed)) {
        [self cancelDwell];
        BOOL dwell = self.dwellReached;
        self.dwellReached = NO;
        CGFloat velocity = [gesture velocityInView:self.overlay].x;
        BOOL home = gesture.state == UIGestureRecognizerStateEnded && !self.launchingBackground && !dwell &&
            ((self.travel > 24 && velocity < -120) || self.travel > 64);
        if (self.isBackgroundVisible) { [self resetTransition]; return; }
        [self finishTransitionHome:home cancelled:gesture.state != UIGestureRecognizerStateEnded];
    }
}

- (void)updateInteractiveProgress {
    if (!self.taskState || !self.activeTask) return;
    self.lastTaskIsBackground = self.dwellTimer != nil || self.dwellReached;
    // A dwell is a card transition, not a home transition. Do not run the
    // home scale/alpha path and then apply another card scale on top.
    if (self.lastTaskIsBackground) {
        self.navigationBar.transform = CGAffineTransformIdentity;
        return;
    }
    CGFloat progress = MIN(1, MAX(0, self.travel / MAX(80, self.overlay.bounds.size.width * 0.42)));
    self.activeTask.transform = CGAffineTransformMakeScale(1 - 0.22 * progress, 1 - 0.22 * progress);
    self.activeTask.alpha = 1 - 0.65 * progress;
    self.activeTask.layer.cornerRadius = 60 * progress;
    self.activeTask.layer.masksToBounds = YES;
    self.navigationBar.transform = CGAffineTransformMakeScale(1 - 0.22 * progress, 1 - 0.22 * progress);
}

- (void)finishTransitionHome:(BOOL)home cancelled:(BOOL)cancelled {
    if (home) {
        [UIView animateWithDuration:0.22 animations:^{
            self.activeTask.alpha = 0;
            self.navigationBar.alpha = 0;
        } completion:^(BOOL finished) { [self returnHome]; }];
        return;
    }
    CGAffineTransform original = self.taskState ? [self.taskState[@"transform"] CGAffineTransformValue] : CGAffineTransformIdentity;
    CGFloat originalAlpha = self.taskState ? [self.taskState[@"alpha"] doubleValue] : 1;
    CGFloat originalRadius = self.taskState ? [self.taskState[@"radius"] doubleValue] : 0;
    [UIView animateWithDuration:0.20 animations:^{
        self.activeTask.transform = original;
        self.activeTask.alpha = originalAlpha;
        self.activeTask.layer.cornerRadius = originalRadius;
        self.navigationBar.transform = CGAffineTransformIdentity;
        self.navigationBar.alpha = 0;
    } completion:^(BOOL finished) { [self cancelTransition]; }];
}

- (void)returnHome {
    [self cancelDwell];
    if (self.hasActiveTask && !self.taskState) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: home skipped, no verified task stage", self.name]];
        [self resetTransition];
        return;
    }
    UIView *returningTask = self.activeTask;
    [self restoreTaskStage];
    for (UIView *task in [self.tasks runningTasksFromLCOS:self.fromLCOS]) {
        task.hidden = YES;
        task.alpha = 0;
        task.userInteractionEnabled = NO;
    }
    self.activeTask = returningTask;
    self.hasActiveTask = returningTask != nil;
    [self restoreNativeWindowInteraction];
    [self resetTransition];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: returned home, tasks hidden", self.name]];
}

- (void)cancelTransition {
    [self cancelDwell];
    [self restoreTaskStage];
    self.activeTask.userInteractionEnabled = YES;
    [self resetTransition];
}

- (void)resetTransition {
    self.transitionActive = NO;
    self.launchingBackground = NO;
    self.dwellReached = NO;
    self.travel = 0;
    [self cancelDwell];
    self.navigationBar.transform = CGAffineTransformIdentity;
    self.navigationBar.alpha = 0;
    [self updateNavigation];
}

- (void)scheduleDwell {
    if (self.dwellTimer || self.launchingBackground || self.dwellReached || self.isBackgroundVisible) return;
    self.dwellTimer = [NSTimer scheduledTimerWithTimeInterval:0.22 repeats:NO block:^(NSTimer *timer) {
        if (!self.transitionActive || self.isBackgroundVisible) return;
        self.dwellReached = YES;
        self.launchingBackground = YES;
        [self showBackground];
    }];
}

- (void)cancelDwell {
    [self.dwellTimer invalidate];
    self.dwellTimer = nil;
}

- (void)showBackground {
    if (!self.fromLCOS && !LCOSNativeInteractionEnabled()) return;
    if (self.isBackgroundVisible) return;
    self.isBackgroundVisible = YES;
    UIView *presentedTask = self.activeTask;
    // Save the current transition baseline before removing taskState. Returning
    // from a card later restores this geometry, not a previous hidden frame.
    [self restoreTaskStage];
    self.switcher = [[LCOSBackgroundView alloc] initWithFrame:self.root.bounds];
    self.switcher.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.switcher.backgroundColor = self.fromLCOS ? UIColor.clearColor : [UIColor colorWithWhite:0.10 alpha:0.35];
    self.switcher.onHome = ^{ [self hideBackground]; };
    self.switcher.onActivateTask = ^BOOL(UIView *task) {
        return [[LCOSTaskRegistry shared] isTaskRunning:task];
    };
    self.switcher.onCloseTask = ^BOOL(UIView *task) {
        BOOL closed = [[LCOSTaskRegistry shared] closeTask:task];
        if (closed) [self.switcher removeTaskFromCards:task];
        return closed;
    };
    __weak typeof(self) weakSelf = self;
    self.switcher.onTaskPresented = ^(UIView *task) {
        [weakSelf restoreTaskStage];
        weakSelf.isBackgroundVisible = NO;
        weakSelf.switcher = nil;
        weakSelf.backgroundView = nil;
        ((LCOSPassThroughWindow *)weakSelf.overlay).backgroundView = nil;
        for (UIVisualEffectView *blur in weakSelf.hostBlurViews) [blur removeFromSuperview];
        [weakSelf.hostBlurViews removeAllObjects];
        weakSelf.hasActiveTask = YES;
        [weakSelf presentTask:task];
        [weakSelf resetTransition];
    };
    NSMutableArray<UIView *> *tasks = [[self.tasks runningTasksFromLCOS:self.fromLCOS] mutableCopy];
    if (presentedTask && [self.tasks isTaskRunning:presentedTask] && ![tasks containsObject:presentedTask]) [tasks addObject:presentedTask];
    [self.switcher setLiveTaskViews:tasks];
    // A desktop switcher has the desktop as its backdrop, not the foreground
    // guest app's window. NativeShell keeps its existing task-host backdrop.
    UIView *host = self.fromLCOS ? self.launcherView : presentedTask.superview;
    // Never blur an arbitrary lower guest window as an LCOS desktop backdrop.
    [self.switcher setBackdropActive:self.fromLCOS || !host];
    self.hostBlurViews = [NSMutableArray array];
    if (self.fromLCOS && self.launcherView) {
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
        blur.frame = self.launcherView.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blur.userInteractionEnabled = NO;
        [self.launcherView addSubview:blur];
        [self.hostBlurViews addObject:blur];
    }
    NSMutableArray<UIView *> *hosts = [NSMutableArray array];
    for (UIView *task in self.switcher.taskViews) {
        UIView *taskHost = task.superview;
        if (!taskHost || [hosts containsObject:taskHost]) continue;
        [hosts addObject:taskHost];
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
        blur.frame = taskHost.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blur.userInteractionEnabled = NO;
        [taskHost insertSubview:blur belowSubview:task];
        [self.hostBlurViews addObject:blur];
    }
    // Bring every card above the single backdrop in each host, not just the
    // last presented application.
    for (UIView *task in self.switcher.taskViews) [task.superview bringSubviewToFront:task];
    [self.root addSubview:self.switcher];
    [self.switcher setNeedsLayout];
    [self.switcher layoutIfNeeded];
    [self.switcher setTransitionProgress:1];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: switcher placements=%lu cards=%lu", self.name, (unsigned long)self.switcher.placementCount, (unsigned long)self.switcher.cardCount]];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: switcher tasks=%lu content=%@ frame=%@ host=%@", self.name, (unsigned long)self.switcher.taskViews.count, NSStringFromCGSize(self.switcher.scrollView.contentSize), NSStringFromCGRect(self.switcher.scrollView.frame), host ?: self.root]];
    _backgroundView = self.switcher;
    ((LCOSPassThroughWindow *)self.overlay).backgroundView = self.switcher;
    self.activeTask = nil;
    self.hasActiveTask = NO;
    [self resetTransition];
    [self.root bringSubviewToFront:self.switcher];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: background presented", self.name]];
}

- (void)restoreNativeWindowInteraction {
    // Keep the real host window in place. Choosing an arbitrary visible window
    // and making it key can reorder LiveContainer's task and desktop layers.
    for (UIWindow *window in self.overlay.windowScene.windows) {
        if (window == self.overlay || window.hidden || window.alpha < 0.01) continue;
        window.userInteractionEnabled = YES;
    }
}

- (void)hideBackground {
    if (!self.isBackgroundVisible) return;
    LCOSBackgroundView *switcher = self.switcher;
    self.isBackgroundVisible = NO;
    [switcher restoreTaskGeometry];
    [switcher removeFromSuperview];
    self.switcher = nil;
    for (UIVisualEffectView *blur in self.hostBlurViews) [blur removeFromSuperview];
    [self.hostBlurViews removeAllObjects];
    _backgroundView = nil;
    ((LCOSPassThroughWindow *)self.overlay).backgroundView = nil;
    [self restoreNativeWindowInteraction];
    for (UIView *task in [self.tasks runningTasksFromLCOS:self.fromLCOS]) {
        task.hidden = YES;
        task.alpha = 0;
        task.userInteractionEnabled = NO;
    }
    self.activeTask = nil;
    self.hasActiveTask = NO;
    [self resetTransition];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"%@: background closed, interaction restored", self.name]];
}

@end
