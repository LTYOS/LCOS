#import "LCOSBackgroundView.h"
#import <objc/runtime.h>

static char kLCOSTaskGeometryKey;
static char kLCOSTaskRadiusKey;
static char kLCOSTaskParentKey;
static char kLCOSTaskParentIndexKey;

@interface LCOSBackgroundView () <UIGestureRecognizerDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) UIView *sourceView;
@property (nonatomic, strong) UIView *blurContainer;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<UIView *> *taskViews;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSValue *> *cardFrames;
@property (nonatomic, assign) CGFloat stride;
@property (nonatomic, assign) CGFloat transitionProgress;
@property (nonatomic, assign) BOOL presentingTask;
@property (nonatomic, assign) BOOL closingTask;
@property (nonatomic, assign) BOOL sourceScales;
@property (nonatomic, weak) UIView *draggedTask;
@property (nonatomic, assign) CGAffineTransform dragBaseTransform;
@property (nonatomic, weak) UIView *activatingTask;
@end

@implementation LCOSBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.sourceScales = YES;
        self.taskViews = @[];
        self.cardFrames = [NSMutableDictionary dictionary];
        self.blurContainer = [[UIView alloc] init];
        self.blurContainer.clipsToBounds = YES;
        [self addSubview:self.blurContainer];
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:nil];
        [self.blurContainer addSubview:self.blurView];
        self.dimView = [[UIView alloc] init];
        self.dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
        self.dimView.alpha = 0;
        [self addSubview:self.dimView];
        self.scrollView = [[UIScrollView alloc] init];
        self.scrollView.backgroundColor = UIColor.clearColor;
        self.scrollView.clipsToBounds = NO;
        self.scrollView.showsHorizontalScrollIndicator = NO;
        self.scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
        self.scrollView.directionalLockEnabled = YES;
        self.scrollView.delegate = self;
        [self addSubview:self.scrollView];
        self.emptyLabel = [[UILabel alloc] init];
        self.emptyLabel.text = @"没有正在运行的 App";
        self.emptyLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
        self.emptyLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        self.emptyLabel.textAlignment = NSTextAlignmentCenter;
        self.emptyLabel.hidden = YES;
        [self addSubview:self.emptyLabel];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self;
        [self addGestureRecognizer:pan];
        [self.scrollView.panGestureRecognizer requireGestureRecognizerToFail:pan];
    }
    return self;
}

- (NSValue *)keyForTask:(UIView *)task {
    return [NSValue valueWithNonretainedObject:task];
}

- (void)detachSourceDesktop {
    if (![self.sourceView isKindOfClass:UIWindow.class]) [self.sourceView removeFromSuperview];
    self.sourceView = nil;
}

- (void)setSourceDesktop:(UIView *)desktop {
    if ([desktop isKindOfClass:UIWindow.class]) {
        self.sourceView = desktop;
        return;
    }
    if (self.sourceView.superview && self.sourceView != self.blurContainer) [self restoreTaskGeometry];
    [self.sourceView removeFromSuperview];
    self.sourceView = desktop;
    if (desktop == self || [self isDescendantOfView:desktop]) return;
    desktop.userInteractionEnabled = NO;
    desktop.frame = self.blurContainer.bounds;
    [self.blurContainer insertSubview:desktop atIndex:0];
    [self setNeedsLayout];
}

- (void)setLiveTaskViews:(NSArray<UIView *> *)taskViews {
    if (![taskViews isKindOfClass:NSArray.class]) return;
    self.taskViews = [taskViews copy];
    [self.cardFrames removeAllObjects];
    self.emptyLabel.hidden = self.taskViews.count > 0;
    for (UIView *task in self.taskViews) {
        if (!objc_getAssociatedObject(task, &kLCOSTaskGeometryKey)) {
            NSDictionary *geometry = @{@"transform": [NSValue valueWithCGAffineTransform:task.transform],
                @"center": [NSValue valueWithCGPoint:task.center], @"alpha": @(task.alpha),
                @"hidden": @(task.hidden), @"interaction": @(task.userInteractionEnabled)};
            objc_setAssociatedObject(task, &kLCOSTaskGeometryKey, geometry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(task, &kLCOSTaskRadiusKey, @(task.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(task, &kLCOSTaskParentKey, task.superview, OBJC_ASSOCIATION_ASSIGN);
            NSUInteger index = [task.superview.subviews indexOfObjectIdenticalTo:task];
            objc_setAssociatedObject(task, &kLCOSTaskParentIndexKey, @(index), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIView *container = [[UIView alloc] initWithFrame:task.bounds];
        container.clipsToBounds = NO;
        [self.scrollView addSubview:container];
        task.hidden = NO;
        task.alpha = 1;
        task.userInteractionEnabled = NO;
        task.layer.zPosition = 2 + self.taskViews.count;
        [container addSubview:task];
    }
    [self setNeedsLayout];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.presentingTask) return nil;
    if (self.scrollView.dragging || self.scrollView.decelerating) return self.scrollView;
    UIView *hit = [super hitTest:point withEvent:event];
    // The blurred desktop is decorative. Let the task card and blank-area
    // gestures receive touches rather than allowing it to swallow the page.
    if (hit == self.sourceView || [hit isDescendantOfView:self.sourceView] || hit == self.blurView) return self;
    return hit;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.presentingTask) return;
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    self.blurContainer.frame = self.bounds;
    self.sourceView.frame = self.blurContainer.bounds;
    self.blurView.frame = self.blurContainer.bounds;
    self.blurContainer.hidden = !self.sourceView;
    self.blurView.alpha = self.sourceView ? _transitionProgress : 0;
    self.dimView.frame = self.bounds;
    self.scrollView.frame = self.bounds;
    self.emptyLabel.frame = CGRectMake(24, (height - 30) / 2, width - 48, 30);
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat available = MAX(120, height - safe.top - safe.bottom - 70);
    CGFloat cardWidth = MIN(width * 0.76, available * 0.58);
    CGFloat cardHeight = MIN(available, cardWidth * 1.86);
    self.stride = cardWidth + 20;
    self.scrollView.contentInset = UIEdgeInsetsMake(0, (width - cardWidth) / 2, 0, (width - cardWidth) / 2);
    self.scrollView.contentOffset = CGPointMake(-self.scrollView.contentInset.left, 0);
    self.scrollView.contentSize = CGSizeMake(self.stride * self.taskViews.count, height);
    for (NSUInteger index = 0; index < self.taskViews.count; index++) {
        UIView *task = self.taskViews[index];
        CGSize source = task.bounds.size;
        CGFloat aspect = source.width > 0 && source.height > 0 ? source.width / source.height : cardWidth / cardHeight;
        CGFloat w = MIN(cardWidth, cardHeight * aspect);
        CGFloat h = MIN(cardHeight, cardWidth / aspect);
        CGRect frame = CGRectMake(index * self.stride + (cardWidth - w) / 2,
            safe.top + (available - h) / 2, w, h);
        self.cardFrames[[self keyForTask:task]] = [NSValue valueWithCGRect:frame];
        UIView *container = task.superview;
        if (!self.presentingTask && !self.closingTask && container != self.scrollView) {
            container.frame = frame;
            container.clipsToBounds = NO;
            container.layer.shadowColor = UIColor.blackColor.CGColor;
            container.layer.shadowOpacity = 0.28;
            container.layer.shadowRadius = 16;
            container.layer.shadowOffset = CGSizeMake(0, 8);
        }
        if (self.transitionProgress > 0 && task != self.draggedTask) [self placeTaskInCard:task];
    }
}

- (void)placeTaskInCard:(UIView *)task {
    NSValue *value = self.cardFrames[[self keyForTask:task]];
    if (!value || !task.superview) return;
    CGRect frame = value.CGRectValue;
    CGSize source = task.bounds.size;
    if (source.width < 1 || source.height < 1 || CGRectIsEmpty(frame)) return;
    CGFloat scale = frame.size.width / source.width;
    CGAffineTransform original = [objc_getAssociatedObject(task, &kLCOSTaskGeometryKey)[@"transform"] CGAffineTransformValue];
    task.transform = CGAffineTransformConcat(original, CGAffineTransformMakeScale(scale, scale));
    task.center = CGPointMake(CGRectGetMidX(task.superview.bounds), CGRectGetMidY(task.superview.bounds));
    task.layer.cornerRadius = 60.0 / MAX(0.01, scale);
    task.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    task.layer.cornerCurve = kCACornerCurveContinuous;
    task.layer.masksToBounds = YES;
}

- (void)setTransitionProgress:(CGFloat)progress {
    _transitionProgress = MAX(0, MIN(1, progress));
    self.dimView.alpha = 0.18 * _transitionProgress;
    self.scrollView.alpha = _transitionProgress;
    self.emptyLabel.alpha = _transitionProgress;
    if (_transitionProgress > 0) [self layoutSubviews];
    self.blurContainer.transform = self.sourceScales ? CGAffineTransformMakeScale(1.0 - 0.035 * _transitionProgress, 1.0 - 0.035 * _transitionProgress) : CGAffineTransformIdentity;
    self.blurContainer.layer.cornerRadius = self.sourceScales ? 18 * _transitionProgress : 0;
    self.blurContainer.layer.cornerCurve = kCACornerCurveContinuous;
    if (_transitionProgress > 0 && !self.blurView.effect) {
        self.blurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    }
    self.blurView.alpha = _transitionProgress;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self layoutSubviews];
}

- (void)restoreTaskGeometry {
    [self.layer removeAllAnimations];
    if (self.closingTask) return;
    for (UIView *task in self.taskViews) {
        NSDictionary *geometry = objc_getAssociatedObject(task, &kLCOSTaskGeometryKey);
        if (!geometry) continue;
        UIView *parent = objc_getAssociatedObject(task, &kLCOSTaskParentKey);
        NSUInteger index = [objc_getAssociatedObject(task, &kLCOSTaskParentIndexKey) unsignedIntegerValue];
        if (parent && task.superview != parent) [parent insertSubview:task atIndex:MIN(index, parent.subviews.count)];
        task.transform = [geometry[@"transform"] CGAffineTransformValue];
        task.center = [geometry[@"center"] CGPointValue];
        task.alpha = [geometry[@"alpha"] doubleValue];
        task.hidden = [geometry[@"hidden"] boolValue];
        task.userInteractionEnabled = [geometry[@"interaction"] boolValue];
        task.layer.cornerRadius = [objc_getAssociatedObject(task, &kLCOSTaskRadiusKey) doubleValue];
        task.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        task.layer.masksToBounds = YES;
        task.layer.zPosition = 0;
    }
    for (UIView *container in [self.scrollView.subviews copy]) [container removeFromSuperview];
}

- (void)prepareForTaskActivation {
    self.presentingTask = YES;
    [self.layer removeAllAnimations];
    [self.scrollView.layer removeAllAnimations];
}

- (void)removeTaskFromCards:(UIView *)task {
    if (!task || ![self.taskViews containsObject:task]) return;
    self.closingTask = YES;
    [self restoreTaskGeometry];
    NSMutableArray *tasks = [self.taskViews mutableCopy];
    [tasks removeObjectIdenticalTo:task];
    self.taskViews = tasks;
    [self.cardFrames removeObjectForKey:[self keyForTask:task]];
    objc_setAssociatedObject(task, &kLCOSTaskGeometryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(task, &kLCOSTaskRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.closingTask = NO;
    self.emptyLabel.hidden = self.taskViews.count > 0;
    self.stride = 0;
    [self layoutIfNeeded];
    [self setNeedsLayout];
}

- (void)setSourceScales:(BOOL)scales {
    _sourceScales = scales;
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    CGPoint location = [gesture locationInView:self.scrollView];
    for (UIView *task in self.taskViews) {
        if (!CGRectContainsPoint([self.cardFrames[[self keyForTask:task]] CGRectValue], location)) continue;
        if (!self.onActivateTask || !self.onActivateTask(task)) return;
        UIView *container = task.superview;
        UIView *parent = objc_getAssociatedObject(task, &kLCOSTaskParentKey);
        NSUInteger index = [objc_getAssociatedObject(task, &kLCOSTaskParentIndexKey) unsignedIntegerValue];
        NSDictionary *geometry = objc_getAssociatedObject(task, &kLCOSTaskGeometryKey);
        if (!parent || !geometry) return;
        [self prepareForTaskActivation];
        self.activatingTask = task;
        [self layoutIfNeeded];
        [parent insertSubview:task atIndex:MIN(index, parent.subviews.count)];
        [parent layoutIfNeeded];
        UIWindow *targetWindow = parent.window;
        CGRect target = [parent convertRect:[container convertRect:container.bounds toView:self.window] fromView:self.window];
        if (targetWindow && targetWindow != self.window) {
            CGPoint screenPoint = [self.window convertPoint:CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target)) toWindow:targetWindow];
            target = [parent convertRect:CGRectMake(screenPoint.x - target.size.width / 2, screenPoint.y - target.size.height / 2, target.size.width, target.size.height) fromView:targetWindow];
        }
        task.transform = CGAffineTransformMakeScale(target.size.width / task.bounds.size.width, target.size.height / task.bounds.size.height);
        task.center = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
        task.alpha = 1;
        task.hidden = NO;
        [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            task.transform = [geometry[@"transform"] CGAffineTransformValue];
            task.center = [geometry[@"center"] CGPointValue];
            task.layer.cornerRadius = [objc_getAssociatedObject(task, &kLCOSTaskRadiusKey) doubleValue];
            self.alpha = 0;
        } completion:^(BOOL finished) {
            task.userInteractionEnabled = [geometry[@"interaction"] boolValue];
            [self restoreTaskGeometry];
            [self detachSourceDesktop];
            [self removeFromSuperview];
            self.presentingTask = NO;
            self.activatingTask = nil;
            self.alpha = 1;
            if (self.onTaskPresented) self.onTaskPresented(task);
        }];
        return;
    }
    if (self.onHome) self.onHome();
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.scrollView];
    UIView *task = nil;
    for (UIView *candidate in self.taskViews) {
        if (CGRectContainsPoint([self.cardFrames[[self keyForTask:candidate]] CGRectValue], location)) { task = candidate; break; }
    }
    if (!task) return;
    CGFloat translation = [gesture translationInView:self].y;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self placeTaskInCard:task];
        self.draggedTask = task;
        self.dragBaseTransform = task.transform;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        UIView *container = task.superview;
        CGFloat travel = MIN(0, translation) / MAX(0.1, task.transform.a);
        container.transform = CGAffineTransformMakeTranslation(0, travel);
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.draggedTask = nil;
        BOOL remove = gesture.state == UIGestureRecognizerStateEnded &&
            (translation < -100 || [gesture velocityInView:self].y < -800);
        if (remove && self.onCloseTask && self.onCloseTask(task)) return;
        [UIView animateWithDuration:0.25 animations:^{ task.superview.transform = CGAffineTransformIdentity; }];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class]) {
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
        return velocity.y < 0 && fabs(velocity.y) > fabs(velocity.x);
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}

@end
