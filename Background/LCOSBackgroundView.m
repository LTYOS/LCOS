#import "LCOSBackgroundView.h"
#import "LCOSAppModel.h"

@interface LCOSAppCardView : UIView
@property (nonatomic, strong) LCOSAppModel *model;
@property (nonatomic, strong) UIView *surface;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation LCOSAppCardView
@end

@interface LCOSBackgroundView () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *sourceView;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIViewPropertyAnimator *blurAnimator;
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSMutableArray<LCOSAppModel *> *apps;
@property (nonatomic, strong) NSMutableArray<LCOSAppCardView *> *cards;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UILabel *listTitleLabel;
@property (nonatomic, strong) UIButton *returnButton;
@property (nonatomic, strong) UIPanGestureRecognizer *dismissGesture;
@property (nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedback;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) CGFloat transitionProgress;
@property (nonatomic, assign) CGFloat cardWidth;
@property (nonatomic, assign) CGFloat cardStride;
@end

@implementation LCOSBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.apps = [NSMutableArray array];
        self.cards = [NSMutableArray array];

        self.blurView = [[UIVisualEffectView alloc] initWithEffect:nil];
        [self addSubview:self.blurView];
        self.dimView = [[UIView alloc] init];
        self.dimView.backgroundColor = UIColor.blackColor;
        self.dimView.alpha = 0;
        [self addSubview:self.dimView];

        self.scrollView = [[UIScrollView alloc] init];
        self.scrollView.clipsToBounds = NO;
        self.scrollView.showsHorizontalScrollIndicator = NO;
        self.scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
        self.scrollView.directionalLockEnabled = YES;
        self.scrollView.delegate = self;
        [self addSubview:self.scrollView];

        self.listTitleLabel = [[UILabel alloc] init];
        self.listTitleLabel.text = @"已安装应用 · 非运行后台";
        self.listTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        self.listTitleLabel.textColor = UIColor.whiteColor;
        [self addSubview:self.listTitleLabel];
        self.returnButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.returnButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        self.returnButton.layer.cornerRadius = 18;
        [self.returnButton setTitle:@"返回" forState:UIControlStateNormal];
        [self.returnButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [self.returnButton addTarget:self action:@selector(returnTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.returnButton];

        self.emptyLabel = [[UILabel alloc] init];
        self.emptyLabel.text = @"没有已安装的应用";
        self.emptyLabel.textColor = UIColor.secondaryLabelColor;
        self.emptyLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        self.emptyLabel.textAlignment = NSTextAlignmentCenter;
        self.emptyLabel.hidden = YES;
        [self addSubview:self.emptyLabel];

        UITapGestureRecognizer *emptyTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];
        emptyTap.cancelsTouchesInView = NO;
        emptyTap.delegate = self;
        [self addGestureRecognizer:emptyTap];

        self.dismissGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dismissCardPan:)];
        self.dismissGesture.delegate = self;
        [self.scrollView addGestureRecognizer:self.dismissGesture];
        [self.scrollView.panGestureRecognizer requireGestureRecognizerToFail:self.dismissGesture];
        self.selectionFeedback = [[UISelectionFeedbackGenerator alloc] init];
        [self setTransitionProgress:0];
    }
    return self;
}

- (void)dealloc {
    [self.blurAnimator stopAnimation:YES];
}

- (void)prepareWithCurrentInterface:(UIView *)interfaceView {
    [self.sourceView removeFromSuperview];
    // Never include this switcher's previous cards in its next backdrop.
    self.hidden = YES;
    [interfaceView layoutIfNeeded];
    UIView *snapshot = [interfaceView snapshotViewAfterScreenUpdates:NO];
    self.hidden = NO;
    if (!snapshot) {
        snapshot = [[UIView alloc] initWithFrame:self.bounds];
        snapshot.backgroundColor = UIColor.systemBackgroundColor;
    }
    self.sourceView = snapshot;
    self.sourceView.clipsToBounds = YES;
    [self insertSubview:self.sourceView atIndex:0];
    self.sourceView.frame = self.bounds;
    [self setTransitionProgress:self.transitionProgress];
}

- (void)setApps:(NSArray *)apps {
    [self.apps setArray:apps ?: @[]];
    for (LCOSAppCardView *card in self.cards) [card removeFromSuperview];
    [self.cards removeAllObjects];
    for (LCOSAppModel *app in self.apps) {
        LCOSAppCardView *card = [[LCOSAppCardView alloc] init];
        card.model = app;
        card.backgroundColor = UIColor.clearColor;
        card.clipsToBounds = NO;

        card.surface = [[UIView alloc] init];
        card.surface.backgroundColor = UIColor.secondarySystemBackgroundColor;
        card.surface.layer.cornerRadius = 18;
        card.surface.layer.cornerCurve = kCACornerCurveContinuous;
        card.surface.layer.borderWidth = 0.5;
        card.surface.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
        card.layer.shadowColor = UIColor.blackColor.CGColor;
        card.layer.shadowOpacity = 0.22;
        card.layer.shadowRadius = 22;
        card.layer.shadowOffset = CGSizeMake(0, 12);
        card.surface.clipsToBounds = YES;
        [card addSubview:card.surface];

        // This is deliberately an entry card, not a fake running-app snapshot.
        UIImageView *icon = [[UIImageView alloc] initWithImage:app.icon];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.layer.cornerRadius = 20;
        icon.layer.cornerCurve = kCACornerCurveContinuous;
        icon.clipsToBounds = YES;
        [card.surface addSubview:icon];
        UILabel *entry = [[UILabel alloc] init];
        entry.text = @"已安装应用 · 点击启动";
        entry.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        entry.textColor = UIColor.secondaryLabelColor;
        entry.textAlignment = NSTextAlignmentCenter;
        [card.surface addSubview:entry];

        card.titleLabel = [[UILabel alloc] init];
        card.titleLabel.text = app.displayName;
        card.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        card.titleLabel.textColor = UIColor.whiteColor;
        card.titleLabel.textAlignment = NSTextAlignmentCenter;
        card.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        card.titleLabel.layer.shadowColor = UIColor.blackColor.CGColor;
        card.titleLabel.layer.shadowOpacity = 0.4;
        card.titleLabel.layer.shadowRadius = 4;
        card.titleLabel.layer.shadowOffset = CGSizeZero;
        [card addSubview:card.titleLabel];

        icon.translatesAutoresizingMaskIntoConstraints = NO;
        entry.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [icon.centerXAnchor constraintEqualToAnchor:card.surface.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:card.surface.centerYAnchor constant:-12],
            [icon.widthAnchor constraintEqualToConstant:82],
            [icon.heightAnchor constraintEqualToConstant:82],
            [entry.centerXAnchor constraintEqualToAnchor:card.surface.centerXAnchor],
            [entry.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:20],
        ]];

        UITapGestureRecognizer *open = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openCard:)];
        [open requireGestureRecognizerToFail:self.dismissGesture];
        [card addGestureRecognizer:open];
        [self.scrollView addSubview:card];
        [self.cards addObject:card];
    }
    self.emptyLabel.hidden = self.cards.count > 0;
    self.selectedIndex = 0;
    [self layoutIfNeeded];
    self.scrollView.contentOffset = CGPointMake(-self.scrollView.contentInset.left, 0);
}

- (void)layoutCardsWithoutRecentering {
    [self layoutSubviews];
    if (self.cards.count) {
        self.scrollView.contentOffset = CGPointMake(self.selectedIndex * self.cardStride - self.scrollView.contentInset.left, 0);
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    self.sourceView.frame = self.bounds;
    self.blurView.frame = self.bounds;
    self.dimView.frame = self.bounds;
    self.scrollView.frame = self.bounds;
    self.emptyLabel.frame = CGRectMake(24, (height - 30) / 2, width - 48, 30);
    self.listTitleLabel.frame = CGRectMake(24, self.safeAreaInsets.top + 18, width - 144, 36);
    self.returnButton.frame = CGRectMake(width - 104, self.safeAreaInsets.top + 18, 80, 36);
    self.cardWidth = MIN(360, width * 0.79);
    self.cardStride = self.cardWidth + 10;
    CGFloat cardHeight = MIN(570, height * 0.61);
    CGFloat cardY = MAX(self.safeAreaInsets.top + 82, (height - cardHeight) / 2 + 10);
    CGFloat sideInset = (width - self.cardWidth) / 2;
    self.scrollView.contentInset = UIEdgeInsetsMake(0, sideInset, 0, sideInset);
    self.scrollView.contentSize = CGSizeMake(self.cardStride * self.cards.count, height);
    for (NSInteger i = 0; i < (NSInteger)self.cards.count; i++) {
        LCOSAppCardView *card = self.cards[i];
        card.frame = CGRectMake(i * self.cardStride, cardY, self.cardWidth, cardHeight);
        card.surface.frame = CGRectMake(0, 34, self.cardWidth, cardHeight - 34);
        card.titleLabel.frame = CGRectMake(8, 0, self.cardWidth - 16, 25);
    }
    [self updateCardScales];
}

- (void)setTransitionProgress:(CGFloat)progress {
    _transitionProgress = MAX(0, MIN(1, progress));
    self.dimView.alpha = 0.24 * _transitionProgress;
    self.listTitleLabel.alpha = _transitionProgress;
    self.returnButton.alpha = _transitionProgress;
    self.returnButton.enabled = _transitionProgress > 0.85;
    self.sourceView.transform = CGAffineTransformMakeScale(1.0 - 0.035 * _transitionProgress,
                                                            1.0 - 0.035 * _transitionProgress);
    self.sourceView.layer.cornerRadius = 18 * _transitionProgress;
    self.sourceView.layer.cornerCurve = kCACornerCurveContinuous;
    self.scrollView.alpha = _transitionProgress;
    self.scrollView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(44 * (1 - _transitionProgress), 0),
        CGAffineTransformMakeScale(0.96 + 0.04 * _transitionProgress, 0.96 + 0.04 * _transitionProgress));
    if (_transitionProgress > 0 && !self.blurAnimator) {
        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
        self.blurAnimator = [[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{
            self.blurView.effect = effect;
        }];
        self.blurAnimator.pausesOnCompletion = YES;
    }
    self.blurAnimator.fractionComplete = _transitionProgress;
}

- (LCOSAppCardView *)selectedCard {
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.cards.count) return nil;
    return self.cards[self.selectedIndex];
}

- (void)updateCardScales {
    if (self.cardStride <= 0) return;
    CGFloat center = self.scrollView.contentOffset.x + self.scrollView.contentInset.left;
    for (NSInteger i = 0; i < (NSInteger)self.cards.count; i++) {
        CGFloat distance = MIN(1, ABS(center - i * self.cardStride) / self.cardStride);
        CGFloat scale = 1.0 - 0.045 * distance;
        LCOSAppCardView *card = self.cards[i];
        if (self.dismissGesture.state != UIGestureRecognizerStateBegan &&
            self.dismissGesture.state != UIGestureRecognizerStateChanged && !self.scrollView.isDragging) {
            card.surface.transform = CGAffineTransformMakeScale(scale, scale);
        }
        card.titleLabel.alpha = 1.0 - distance * 0.45;
    }
    NSInteger nearest = MAX(0, MIN((NSInteger)self.cards.count - 1,
                                   (NSInteger)floor(center / self.cardStride + 0.5)));
    if (nearest != self.selectedIndex && self.scrollView.isDragging) {
        self.selectedIndex = nearest;
        [self.selectionFeedback selectionChanged];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self updateCardScales];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(CGPoint *)targetContentOffset {
    if (self.cardStride <= 0 || !self.cards.count) return;
    CGFloat proposed = targetContentOffset->x + scrollView.contentInset.left;
    NSInteger index = MAX(0, MIN((NSInteger)self.cards.count - 1, (NSInteger)round(proposed / self.cardStride)));
    targetContentOffset->x = index * self.cardStride - scrollView.contentInset.left;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self updateCardScales];
}

- (void)openCard:(UITapGestureRecognizer *)gesture {
    LCOSAppCardView *card = (LCOSAppCardView *)gesture.view;
    if (![card isKindOfClass:LCOSAppCardView.class]) return;
    [UIView animateWithDuration:0.15 animations:^{ card.surface.transform = CGAffineTransformMakeScale(0.97, 0.97); }
                     completion:^(BOOL finished) { [card.model launch]; }];
}

- (void)dismissCardPan:(UIPanGestureRecognizer *)gesture {
    LCOSAppCardView *card = self.selectedCard;
    if (!card) return;
    CGFloat translation = [gesture translationInView:self].y;
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat upward = MIN(0, translation);
        card.surface.transform = CGAffineTransformMakeTranslation(0, upward);
        card.alpha = MAX(0.2, 1.0 + upward / (self.bounds.size.height * 0.65));
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        BOOL remove = gesture.state == UIGestureRecognizerStateEnded &&
            (translation < -110 || [gesture velocityInView:self].y < -850);
        if (!remove) {
            [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0 options:0 animations:^{
                card.surface.transform = CGAffineTransformIdentity;
                card.alpha = 1;
            } completion:nil];
            return;
        }
        NSInteger index = self.selectedIndex;
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            card.surface.transform = CGAffineTransformMakeTranslation(70, -self.bounds.size.height * 0.65);
            card.alpha = 0;
        } completion:^(BOOL finished) {
            if (index >= (NSInteger)self.cards.count) return;
            [self.cards removeObjectAtIndex:index];
            [self.apps removeObjectAtIndex:index];
            [card removeFromSuperview];
            self.selectedIndex = MIN(index, (NSInteger)self.cards.count - 1);
            self.emptyLabel.hidden = self.cards.count > 0;
            [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
                [self layoutCardsWithoutRecentering];
            } completion:nil];
        }];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.dismissGesture) {
        CGPoint velocity = [self.dismissGesture velocityInView:self];
        return self.cards.count > 0 && velocity.y < 0 && ABS(velocity.y) > ABS(velocity.x);
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([gestureRecognizer isKindOfClass:UITapGestureRecognizer.class] && gestureRecognizer.view == self) {
        return ![touch.view isDescendantOfView:self.scrollView];
    }
    return YES;
}

- (void)returnTapped {
    if (self.onClose) self.onClose();
}

- (void)backgroundTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded && self.onEmptySpaceTapped) self.onEmptySpaceTapped();
}

@end
