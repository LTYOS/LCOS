//
//  LCOSGrid.m
//  LCOS.dylib
//

#import "LCOSGrid.h"
#import "LCOSAppIconView.h"
#import "LCOSAppModel.h"
#import "LCOSLogManager.h"

@interface LCOSGrid () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, assign) NSInteger currentPage;
@property (nonatomic, assign) CGFloat itemWidth;
@property (nonatomic, assign) CGFloat itemHeight;
@property (nonatomic, assign) NSInteger columns;
@property (nonatomic, assign) NSInteger rows;
@property (nonatomic, assign) NSInteger itemsPerPage;
@property (nonatomic, strong) NSArray<LCOSAppModel *> *allApps;
@property (nonatomic, assign) CGSize lastLayoutSize;
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
        self.itemHeight = 94.0;
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

        // Add tap gesture to scrollView to bypass paging interception
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(gridTapGestureRecognized:)];
        tapGesture.cancelsTouchesInView = NO;
        tapGesture.delaysTouchesBegan = NO;
        tapGesture.delaysTouchesEnded = NO;
        tapGesture.numberOfTapsRequired = 1;
        tapGesture.numberOfTouchesRequired = 1;
        [self.scrollView addGestureRecognizer:tapGesture];

        // Pan gesture (scrolling/paging) requires tap to fail first
        [self.scrollView.panGestureRecognizer requireGestureRecognizerToFail:tapGesture];
    }
    return self;
}

- (void)setApps:(NSArray<LCOSAppModel *> *)apps {
    _allApps = [apps copy];
    for (UIView *page in self.pages) [page removeFromSuperview];
    [self.pages removeAllObjects];
    [self.currentPageItems removeAllObjects];
    self.lastLayoutSize = CGSizeZero;

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

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.bounds;
    [self layoutPagesIfNeeded:NO];
}

- (void)layoutPagesIfNeeded:(BOOL)force {
    if (CGRectIsEmpty(self.bounds) || self.pages.count == 0) return;
    if (!force && CGSizeEqualToSize(self.lastLayoutSize, self.bounds.size)) return;
    self.lastLayoutSize = self.bounds.size;

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    CGFloat iconSize = 60.0;
    CGFloat columnSpacing = 28.0;
    CGFloat rowSpacing = 20.0;
    CGFloat topInset = 100.0;
    CGFloat gridWidth = self.columns * iconSize + (self.columns - 1) * columnSpacing;
    CGFloat startX = MAX(28.0, (width - gridWidth) / 2.0);

    for (NSInteger pageIndex = 0; pageIndex < self.pages.count; pageIndex++) {
        UIView *pageView = self.pages[pageIndex];
        pageView.frame = CGRectMake(pageIndex * width, 0, width, height);
        NSArray<UIView *> *icons = pageView.subviews;
        for (NSInteger index = 0; index < icons.count; index++) {
            NSInteger column = index % self.columns;
            NSInteger row = index / self.columns;
            CGFloat x = startX + column * (iconSize + columnSpacing);
            CGFloat y = topInset + row * (self.itemHeight + rowSpacing);
            // Only change frames. Never remove/recreate an icon during touch tracking.
            icons[index].frame = CGRectMake(x, y, iconSize, self.itemHeight);
        }
    }
    self.scrollView.contentSize = CGSizeMake(width * self.pages.count, height);
}

- (void)scrollToPage:(NSInteger)page animated:(BOOL)animated {
    if (page < 0 || page >= self.pages.count) return;
    self.currentPage = page;
    [self.scrollView setContentOffset:CGPointMake(page * self.bounds.size.width, 0) animated:animated];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView.bounds.size.width <= 0) return;
    NSInteger page = round(scrollView.contentOffset.x / scrollView.bounds.size.width);
    self.currentPage = MAX(0, MIN(page, self.pages.count - 1));
}

- (void)gridTapGestureRecognized:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    CGPoint location = [gesture locationInView:self.scrollView];
    
    // Only check the currently visible page for hit testing
    NSInteger currentPage = self.currentPage;
    if (currentPage < 0 || currentPage >= self.pages.count) return;
    UIView *pageView = self.pages[currentPage];
    
    // Convert to pageView coordinates
    CGPoint pagePoint = [self.scrollView convertPoint:location toView:pageView];
    if (!CGRectContainsPoint(pageView.bounds, pagePoint)) return;
    
    // Find which icon was tapped
    NSArray<UIView *> *icons = pageView.subviews;
    for (NSInteger index = 0; index < icons.count; index++) {
        UIView *iconView = icons[index];
        CGPoint iconPoint = [pageView convertPoint:pagePoint toView:iconView];
        if (CGRectContainsPoint(iconView.bounds, iconPoint)) {
            NSInteger globalIndex = currentPage * self.itemsPerPage + index;
            if (globalIndex < self.allApps.count) {
                LCOSAppModel *app = self.allApps[globalIndex];
                [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: icon tap - %@", app.displayName]];
                if (self.onAppTapped) self.onAppTapped(app);
            }
            return;
        }
    }
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: tap on empty area at %@", NSStringFromCGPoint(location)]];
}

@end
