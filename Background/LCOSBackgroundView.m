#import "LCOSBackgroundView.h"
#import <objc/runtime.h>

@interface LCOSTaskPlacement : NSObject
@property (nonatomic, weak) UIView *task;
@property (nonatomic, strong) UIView *parent;
@property (nonatomic, strong) UIView *shadow;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *externalConstraints;
@property (nonatomic, assign) CGPoint center;
@property (nonatomic, assign) CGRect originalFrame;
@property (nonatomic, assign) CGAffineTransform transform;
@property (nonatomic, assign) CGFloat alpha;
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) CGFloat depth;
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, assign) BOOL interaction;
@property (nonatomic, assign) BOOL clips;
@property (nonatomic, copy) CALayerCornerCurve cornerCurve;
- (instancetype)initWithTask:(UIView *)task;
- (void)restore;
@end

@implementation LCOSTaskPlacement
- (instancetype)initWithTask:(UIView *)task {
    self = [super init];
    if (self) {
        _task = task;
        _parent = task.superview;
        _center = task.center;
        _originalFrame = task.frame;
        _transform = task.transform;
        _alpha = task.alpha;
        _radius = task.layer.cornerRadius;
        _depth = task.layer.zPosition;
        _hidden = task.hidden;
        _interaction = task.userInteractionEnabled;
        _clips = task.clipsToBounds;
        _cornerCurve = task.layer.cornerCurve;
        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
        for (UIView *ancestor = _parent; ancestor; ancestor = ancestor.superview) {
            for (NSLayoutConstraint *constraint in ancestor.constraints) {
                if (constraint.firstItem == task || constraint.secondItem == task) [constraints addObject:constraint];
            }
        }
        _externalConstraints = [constraints copy];
        [NSLayoutConstraint deactivateConstraints:_externalConstraints];
        _shadow = [[UIView alloc] initWithFrame:task.bounds];
        _shadow.userInteractionEnabled = NO;
        _shadow.layer.shadowColor = UIColor.blackColor.CGColor;
        _shadow.layer.shadowOpacity = 0.28;
        _shadow.layer.shadowRadius = 16;
        _shadow.layer.shadowOffset = CGSizeMake(0, 8);
        [_parent insertSubview:_shadow belowSubview:task];
        task.hidden = NO;
        task.alpha = 1;
        task.userInteractionEnabled = NO;
    }
    return self;
}

- (void)restore {
    UIView *task = self.task;
    [self.shadow removeFromSuperview];
    if (!task) return;
    // Restore untransformed frame first so a previous card scale cannot become
    // the next presentation's geometry baseline.
    task.transform = CGAffineTransformIdentity;
    task.frame = self.originalFrame;
    task.transform = self.transform;
    task.center = self.center;
    task.alpha = self.alpha;
    task.hidden = self.hidden;
    task.userInteractionEnabled = self.interaction;
    task.clipsToBounds = self.clips;
    task.layer.cornerCurve = self.cornerCurve;
    task.layer.cornerRadius = self.radius;
    task.layer.zPosition = self.depth;
    [NSLayoutConstraint activateConstraints:self.externalConstraints];
}
@end

@interface LCOSBackgroundView () <UIGestureRecognizerDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) UIView *cardCanvas;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<UIView *> *taskViews;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSValue *> *cardFrames;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, UIView *> *cardProxies;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, LCOSTaskPlacement *> *placements;
@property (nonatomic, assign) CGFloat stride;
@property (nonatomic, assign) CGFloat transitionProgress;
@property (nonatomic, assign) BOOL presentingTask;
@property (nonatomic, weak) UIView *draggedTask;
@end

@implementation LCOSBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.taskViews = @[];
        self.cardFrames = [NSMutableDictionary dictionary];
        self.cardProxies = [NSMutableDictionary dictionary];
        self.placements = [NSMutableDictionary dictionary];
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:nil];
        [self addSubview:self.blurView];
        self.dimView = [[UIView alloc] init];
        self.dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
        self.dimView.alpha = 0;
        [self addSubview:self.dimView];
        self.cardCanvas = [[UIView alloc] init];
        self.cardCanvas.backgroundColor = UIColor.clearColor;
        [self addSubview:self.cardCanvas];
        self.scrollView = [[UIScrollView alloc] init];
        self.scrollView.backgroundColor = UIColor.clearColor;
        self.scrollView.clipsToBounds = NO;
        self.scrollView.showsHorizontalScrollIndicator = NO;
        self.scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
        self.scrollView.directionalLockEnabled = YES;
        self.scrollView.delegate = self;
        [self.cardCanvas addSubview:self.scrollView];
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

- (NSValue *)keyForTask:(UIView *)task { return [NSValue valueWithNonretainedObject:task]; }

- (void)setLiveTaskViews:(NSArray<UIView *> *)taskViews {
    self.taskViews = @[];
    [self.cardFrames removeAllObjects];
    [self.cardProxies removeAllObjects];
    [self.placements removeAllObjects];
    for (UIView *task in self.taskViews) {
        if (![task isKindOfClass:UIView.class] || !task.superview || task.bounds.size.width < 1 || task.bounds.size.height < 1) continue;
        NSValue *key = [self keyForTask:task];
        self.taskViews = [self.taskViews arrayByAddingObject:task];
        LCOSTaskPlacement *placement = [[LCOSTaskPlacement alloc] initWithTask:task];
        self.placements[key] = placement;
        UIView *proxy = [[UIView alloc] initWithFrame:task.bounds];
        proxy.backgroundColor = UIColor.clearColor;
        [self.scrollView addSubview:proxy];
        self.cardProxies[key] = proxy;
    }
    self.emptyLabel.hidden = self.taskViews.count > 0;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.presentingTask) return;
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    self.blurView.frame = self.bounds;
    self.dimView.frame = self.bounds;
    self.cardCanvas.frame = self.bounds;
    self.scrollView.frame = self.bounds;
    self.emptyLabel.frame = CGRectMake(24, (height - 30) / 2, width - 48, 30);
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat available = MAX(120, height - safe.top - safe.bottom - 70);
    CGFloat cardWidth = MIN(width * 0.76, available * 0.58);
    CGFloat cardHeight = MIN(available, cardWidth * 1.86);
    self.stride = cardWidth + 20;
    self.scrollView.contentInset = UIEdgeInsetsMake(0, (width - cardWidth) / 2, 0, (width - cardWidth) / 2);
    self.scrollView.contentSize = CGSizeMake(self.stride * self.taskViews.count, height);
    for (NSUInteger index = 0; index < self.taskViews.count; index++) {
        UIView *task = self.taskViews[index];
        CGSize source = task.bounds.size;
        CGFloat aspect = source.width > 0 && source.height > 0 ? source.width / source.height : cardWidth / cardHeight;
        CGFloat w = MIN(cardWidth, cardHeight * aspect);
        CGFloat h = MIN(cardHeight, cardWidth / aspect);
        CGRect frame = CGRectMake(index * self.stride + (cardWidth - w) / 2, safe.top + (available - h) / 2, w, h);
        self.cardFrames[[self keyForTask:task]] = [NSValue valueWithCGRect:frame];
        UIView *proxy = self.cardProxies[[self keyForTask:task]];
        if (proxy) proxy.frame = frame;
        if (self.transitionProgress > 0 && task != self.draggedTask) [self placeTaskInCard:task];
    }
}

- (void)placeTaskInCard:(UIView *)task {
    NSValue *key = [self keyForTask:task];
    LCOSTaskPlacement *placement = self.placements[key];
    UIView *proxy = self.cardProxies[key];
    if (!placement || !proxy || !placement.parent) return;
    CGRect frame = [proxy convertRect:proxy.bounds toView:placement.parent];
    CGSize source = task.bounds.size;
    if (source.width < 1 || source.height < 1 || CGRectIsEmpty(frame) ||
        !isfinite(frame.size.width) || !isfinite(frame.size.height)) return;
    CGFloat sx = frame.size.width / source.width;
    CGFloat sy = frame.size.height / source.height;
    if (!isfinite(sx) || !isfinite(sy) || sx <= 0 || sy <= 0) return;
    // Match LC-SS: absolute scale from the original bounds, never a product
    // of a previous gesture's transform.
    task.transform = CGAffineTransformMakeScale(sx, sy);
    task.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    task.layer.cornerRadius = 60.0 / MAX(0.01, sx);
    task.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    task.layer.cornerCurve = kCACornerCurveContinuous;
    task.layer.masksToBounds = YES;
    placement.shadow.bounds = task.bounds;
    placement.shadow.transform = task.transform;
    placement.shadow.center = task.center;
}

- (void)setTransitionProgress:(CGFloat)progress {
    _transitionProgress = MAX(0, MIN(1, progress));
    self.dimView.alpha = 0.18 * _transitionProgress;
    self.scrollView.alpha = _transitionProgress;
    self.emptyLabel.alpha = _transitionProgress;
    if (_transitionProgress > 0) [self layoutSubviews];
}

- (void)setBackdropActive:(BOOL)active {
    self.blurView.effect = active ? [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark] : nil;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self layoutSubviews]; }

- (void)restoreTaskGeometry {
    [self.layer removeAllAnimations];
    for (LCOSTaskPlacement *placement in self.placements.allValues) [placement restore];
    [self.placements removeAllObjects];
    for (UIView *proxy in self.cardProxies.allValues) [proxy removeFromSuperview];
    [self.cardProxies removeAllObjects];
}

- (void)prepareForTaskActivation {
    self.presentingTask = YES;
    [self.layer removeAllAnimations];
    [self.scrollView.layer removeAllAnimations];
}

- (void)removeTaskFromCards:(UIView *)task {
    if (!task || ![self.taskViews containsObject:task]) return;
    NSMutableArray *tasks = [self.taskViews mutableCopy];
    [tasks removeObjectIdenticalTo:task];
    [self restoreTaskGeometry];
    self.taskViews = @[];
    [self setLiveTaskViews:tasks];
    self.stride = 0;
    [self layoutIfNeeded];
    [self setNeedsLayout];
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    CGPoint location = [gesture locationInView:self.scrollView];
    for (UIView *task in self.taskViews) {
        if (!CGRectContainsPoint([self.cardFrames[[self keyForTask:task]] CGRectValue], location)) continue;
        if (!self.onActivateTask || !self.onActivateTask(task)) return;
        LCOSTaskPlacement *placement = self.placements[[self keyForTask:task]];
        if (!placement) return;
        [self prepareForTaskActivation];
        task.hidden = NO;
        task.alpha = 1;
        [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            task.transform = placement.transform;
            task.center = placement.center;
            task.layer.cornerRadius = placement.radius;
            self.alpha = 0;
        } completion:^(BOOL finished) {
            [self restoreTaskGeometry];
            [self removeFromSuperview];
            self.presentingTask = NO;
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
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat travel = MIN(0, translation) / MAX(0.1, task.transform.a);
        task.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(task.transform.a, task.transform.d), CGAffineTransformMakeTranslation(0, travel));
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.draggedTask = nil;
        BOOL remove = gesture.state == UIGestureRecognizerStateEnded &&
            (translation < -100 || [gesture velocityInView:self].y < -800);
        if (remove && self.onCloseTask && self.onCloseTask(task)) return;
        [UIView animateWithDuration:0.25 animations:^{ [self placeTaskInCard:task]; }];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class]) {
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
        return velocity.y < 0 && fabs(velocity.y) > fabs(velocity.x);
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch { return YES; }

- (void)dealloc {
    for (LCOSTaskPlacement *placement in self.placements.allValues) [placement restore];
}

@end
