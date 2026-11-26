//
//  LCOSGrid.m
//  LCOS.dylib
//

#import "LCOSGrid.h"
#import "LCOSAppIconView.h"
#import "LCOSAppModel.h"
#import "LCOSLogManager.h"
#import "LCOSLayout.h"

@interface LCOSGrid () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, assign) NSInteger currentPage;
@property (nonatomic, assign) CGFloat itemWidth;
@property (nonatomic, assign) CGFloat itemHeight;
@property (nonatomic, assign) NSInteger columns;
@property (nonatomic, assign) NSInteger rows;
@property (nonatomic, assign) NSInteger itemsPerPage;
@property (nonatomic, strong) NSArray<LCOSAppModel *> *allApps;
@property (nonatomic, assign) CGSize lastLayoutSize;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *lastLayoutValues;
@end

@implementation LCOSGrid

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;
        self.columns = 4;
        self.rows = 6;
        self.itemsPerPage = self.columns * self.rows;
        self.itemWidth = 60.0;
        self.itemHeight = 80.0;
        self.pages = [NSMutableArray array];
        self.currentPageItems = [NSMutableArray array];

        self.scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.scrollView.showsHorizontalScrollIndicator = NO;
        self.scrollView.showsVerticalScrollIndicator = NO;
        self.scrollView.pagingEnabled = YES;
        self.scrollView.bounces = YES;
        self.scrollView.delaysContentTouches = NO;
        self.scrollView.canCancelContentTouches = NO;
        self.scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
        self.scrollView.directionalLockEnabled = YES;
        self.scrollView.delegate = self;
        [self addSubview:self.scrollView];
        [[LCOSLogManager sharedManager] forceLog:@"LCOSGrid: scroll view stage"];
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(gridTapGestureRecognized:)];
        tapGesture.cancelsTouchesInView = NO;
        tapGesture.delaysTouchesBegan = NO;
        tapGesture.delaysTouchesEnded = NO;
        tapGesture.numberOfTapsRequired = 1;
        tapGesture.numberOfTouchesRequired = 1;
        tapGesture.delegate = self;
        [self.scrollView addGestureRecognizer:tapGesture];

        // Icon hit testing happens on a completed tap; paging must not wait
        // for that tap to fail after the finger has already started moving.
        self.scrollView.panGestureRecognizer.delegate = self;
        [[LCOSLogManager sharedManager] forceLog:@"LCOSGrid: gestures stage"];

        self.pageControl = [[UIPageControl alloc] initWithFrame:CGRectZero];
        self.pageControl.hidesForSinglePage = YES;
        self.pageControl.userInteractionEnabled = NO;
        self.pageControl.currentPageIndicatorTintColor = UIColor.whiteColor;
        self.pageControl.pageIndicatorTintColor = [UIColor colorWithWhite:1.0 alpha:0.35];
        self.pageControl.preferredIndicatorImage = [UIImage systemImageNamed:@"circle.fill"];
        [self addSubview:self.pageControl];
        [[LCOSLogManager sharedManager] forceLog:@"LCOSGrid: page control stage"];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(layoutSettingsChanged) name:LCOSLayoutDidChangeNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(launcherGestureChanged:) name:@"LCOSLauncherGestureActive" object:nil];
        [[LCOSLogManager sharedManager] forceLog:@"LCOSGrid: init COMPLETE"];
    }
    return self;
}

- (void)setApps:(NSArray<LCOSAppModel *> *)apps {
    _allApps = [apps copy];
    for (UIView *page in self.pages) [page removeFromSuperview];
    [self.pages removeAllObjects];
    [self.currentPageItems removeAllObjects];
    self.lastLayoutSize = CGSizeZero;
    self.lastLayoutValues = nil;

    if (apps.count == 0) {
        self.scrollView.contentSize = CGSizeZero;
        return;
    }

    NSInteger totalPages = (apps.count + self.itemsPerPage - 1) / self.itemsPerPage;
    for (NSInteger pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        UIView *pageView = [[UIView alloc] initWithFrame:CGRectZero];
        pageView.backgroundColor = [UIColor clearColor];
        [self.scrollView addSubview:pageView];
        [self.pages addObject:pageView];

        NSInteger start = pageIndex * self.itemsPerPage;
        NSInteger end = MIN(start + self.itemsPerPage, apps.count);
        NSMutableArray *pageItems = [NSMutableArray array];
        for (NSInteger index = start; index < end; index++) {
            LCOSAppModel *app = apps[index];
            LCOSAppIconView *iconView = [[LCOSAppIconView alloc] initWithAppModel:app];
            [pageView addSubview:iconView];
            iconView.translatesAutoresizingMaskIntoConstraints = YES;
            [pageItems addObject:app];
        }
        [self.currentPageItems addObject:pageItems];
    }

    [self layoutPagesIfNeeded:YES];
    [self scrollToPage:0 animated:NO];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: loaded %lu apps in %ld pages", (unsigned long)apps.count, (long)totalPages]];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)launcherGestureChanged:(NSNotification *)notification {
    [self setLauncherGestureActive:[notification.object boolValue]];
}

- (void)layoutSettingsChanged {
    // Sliders can send dozens of updates per second. Coalesce them into one
    // layout pass and keep every existing icon/page view alive.
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(applyLayoutSettings)
                                               object:nil];
    [self performSelector:@selector(applyLayoutSettings) withObject:nil afterDelay:0.05];
}

- (void)applyLayoutSettings {
    if (self.pages.count == 0) return;
    self.lastLayoutValues = nil;
    [self layoutPagesIfNeeded:NO];
    for (UIView *page in self.pages) {
        for (UIView *icon in page.subviews) [icon setNeedsLayout];
    }
    [[LCOSLogManager sharedManager] forceLog:@"LCOSGrid: live layout applied without rebuilding icons"];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.bounds;
    [self layoutPagesIfNeeded:NO];
}

- (void)layoutPagesIfNeeded:(BOOL)force {
    if (CGRectIsEmpty(self.bounds) || self.pages.count == 0) return;
    NSDictionary<NSString *, NSNumber *> *layoutValues = [LCOSLayout values];
    if (!force && CGSizeEqualToSize(self.lastLayoutSize, self.bounds.size) &&
        [self.lastLayoutValues isEqualToDictionary:layoutValues]) return;
    self.lastLayoutSize = self.bounds.size;
    self.lastLayoutValues = layoutValues;

    CGFloat width = self.bounds.size.width;
    CGFloat height = MAX(1.0, self.bounds.size.height - [LCOSLayout value:@"bottomInset"]);
    CGFloat iconSize = [LCOSLayout value:@"iconSize"];
    CGFloat columnSpacing = [LCOSLayout value:@"columnSpacing"];
    CGFloat availableWidth = MAX(4.0, (width - 32.0 - (self.columns - 1) * columnSpacing) / self.columns);
    self.itemWidth = MAX(1.0, MIN(availableWidth, MAX(iconSize, 72.0)));
    self.itemHeight = MAX(1.0, iconSize + [LCOSLayout value:@"labelGap"] + 18.0);
    CGFloat rowSpacing = [LCOSLayout value:@"rowSpacing"];
    CGFloat topInset = [LCOSLayout value:@"topInset"];
    CGFloat gridWidth = self.columns * self.itemWidth + (self.columns - 1) * columnSpacing;
    CGFloat startX = (width - gridWidth) / 2.0;

    for (NSInteger pageIndex = 0; pageIndex < self.pages.count; pageIndex++) {
        UIView *pageView = self.pages[pageIndex];
        pageView.frame = CGRectMake(pageIndex * width, 0, width, height);
        NSArray<UIView *> *icons = pageView.subviews;
        for (NSInteger index = 0; index < icons.count; index++) {
            NSInteger column = index % self.columns;
            NSInteger row = index / self.columns;
            CGFloat x = startX + column * (self.itemWidth + columnSpacing);
            CGFloat y = topInset + row * (self.itemHeight + rowSpacing);
            // Only change frames. Never remove/recreate an icon during touch tracking.
            icons[index].frame = CGRectMake(x, y, self.itemWidth, self.itemHeight);
        }
    }
    CGFloat pageSize = [LCOSLayout value:@"pageSize"];
    self.pageControl.transform = CGAffineTransformMakeScale(pageSize / 8.0, pageSize / 8.0);
    self.pageControl.frame = CGRectMake(0, height - 24.0 + [LCOSLayout value:@"pageOffset"], width, 24.0);
    self.pageControl.numberOfPages = self.pages.count;
    self.pageControl.currentPage = self.currentPage;
    self.pageControl.currentPageIndicatorTintColor = UIColor.whiteColor;
    self.pageControl.pageIndicatorTintColor = [UIColor colorWithWhite:1.0 alpha:0.35];
    self.scrollView.contentSize = CGSizeMake(width * self.pages.count, height);
}

- (void)scrollToPage:(NSInteger)page animated:(BOOL)animated {
    if (page < 0 || page >= self.pages.count) return;
    self.currentPage = page;
    [self.scrollView setContentOffset:CGPointMake(page * self.bounds.size.width, 0) animated:animated];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.bounds.size.width <= 0 || self.pages.count == 0) return;
    NSInteger page = (NSInteger)floor(scrollView.contentOffset.x / scrollView.bounds.size.width + 0.5);
    self.currentPage = MAX(0, MIN(page, (NSInteger)self.pages.count - 1));
    self.pageControl.currentPage = self.currentPage;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self scrollViewDidScroll:scrollView];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    [self scrollViewDidEndDecelerating:scrollView];
}

- (void)setLauncherGestureActive:(BOOL)active {
    self.scrollView.scrollEnabled = !active;
    // Do not disable pan: changing enabled during recognition cancels an
    // active finger sequence. scrollEnabled alone prevents icon paging.
    // Keep pan enabled: disabling it cancels an active finger sequence.
    // scrollEnabled suppresses paging; the tap callback checks this state
    // before launching an icon instead of cancelling an in-flight recognizer.
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return gestureRecognizer == self.scrollView.panGestureRecognizer || otherGestureRecognizer == self.scrollView.panGestureRecognizer;
}

- (void)gridTapGestureRecognized:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || !self.scrollView.isScrollEnabled) return;
    CGPoint location = [gesture locationInView:self.scrollView];
    // scrollView's location is in its content coordinate system (includes
    // contentOffset). Walk the icon frames directly; convertPoint is not
    // needed because pageView and icons are all scrollView descendants.
    for (NSInteger pageIndex = 0; pageIndex < self.pages.count; pageIndex++) {
        UIView *pageView = self.pages[pageIndex];
        if (!CGRectContainsPoint(pageView.frame, location)) continue;
        CGPoint pagePoint = CGPointMake(location.x - pageView.frame.origin.x,
                                        location.y - pageView.frame.origin.y);
        for (NSInteger index = 0; index < pageView.subviews.count; index++) {
            UIView *iconView = pageView.subviews[index];
            if (!CGRectContainsPoint(iconView.frame, pagePoint)) continue;
            NSInteger globalIndex = pageIndex * self.itemsPerPage + index;
            if (globalIndex >= self.allApps.count) return;
            LCOSAppModel *app = self.allApps[globalIndex];
            [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: icon tap - %@", app.displayName]];
            if (self.onAppTapped) self.onAppTapped(app);
            return;
        }
    }
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: tap on empty area at %@", NSStringFromCGPoint(location)]];
}

@end
