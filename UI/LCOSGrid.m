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

@end

@implementation LCOSGrid

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;
        
        self.scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.scrollView.showsHorizontalScrollIndicator = NO;
        self.scrollView.showsVerticalScrollIndicator = NO;
        self.scrollView.pagingEnabled = YES;
        self.scrollView.bounces = YES;
        self.scrollView.delaysContentTouches = NO;
        self.scrollView.canCancelContentTouches = NO;
        self.scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
        self.scrollView.delegate = self;
        [self addSubview:self.scrollView];
        
        // Ensure touches pass through to subviews (buttons/icons)
        self.scrollView.exclusiveTouch = NO;
        
        self.pages = [NSMutableArray array];
        self.currentPageItems = [NSMutableArray array];
        self.currentPage = 0;
        
        // iOS 26 grid: 4 columns x 6 rows per page
        self.columns = 4;
        self.rows = 6;
        self.itemsPerPage = self.columns * self.rows;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.bounds;
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    
    // iOS 26 layout params (17 Pro Max 440pt wide canvas):
    // Icon size 60x60 pt, column spacing ~28pt, row spacing ~20pt
    // topInset clears status bar & Dynamic Island (safe area top ~62pt)
    CGFloat sideMargin = 28.0;
    CGFloat iconSize = 60.0;
    CGFloat colSpacing = 28.0;
    CGFloat totalGridWidth = self.columns * iconSize + (self.columns - 1) * colSpacing;
    CGFloat startX = (w - totalGridWidth) / 2;
    if (startX < sideMargin) startX = sideMargin;
    
    self.itemWidth = iconSize;
    self.itemHeight = iconSize + 34; // icon + name label space
    
    [self relayoutCurrentPage];
}

- (void)setApps:(NSArray<LCOSAppModel *> *)apps {
    _allApps = [apps copy];
    
    for (UIView *page in self.pages) {
        [page removeFromSuperview];
    }
    [self.pages removeAllObjects];
    [self.currentPageItems removeAllObjects];
    
    if (_allApps.count == 0) {
        self.scrollView.contentSize = CGSizeZero;
        return;
    }
    
    NSInteger totalPages = (_allApps.count + self.itemsPerPage - 1) / self.itemsPerPage;
    for (NSInteger p = 0; p < totalPages; p++) {
        UIView *pageView = [[UIView alloc] initWithFrame:CGRectZero];
        pageView.backgroundColor = [UIColor clearColor];
        [self.pages addObject:pageView];
        
        NSInteger start = p * self.itemsPerPage;
        NSInteger end = MIN(start + self.itemsPerPage, _allApps.count);
        NSMutableArray *pageItems = [NSMutableArray array];
        for (NSInteger i = start; i < end; i++) {
            [pageItems addObject:_allApps[i]];
        }
        [self.currentPageItems addObject:pageItems];
        
        [self layoutPage:pageView items:pageItems pageIndex:p];
    }
    
    self.scrollView.contentSize = CGSizeMake(self.bounds.size.width * totalPages, self.bounds.size.height);
    [self scrollToPage:0 animated:NO];
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: loaded %lu apps in %ld pages", (unsigned long)_allApps.count, (long)totalPages]];
}

- (void)layoutPage:(UIView *)pageView items:(NSMutableArray *)items pageIndex:(NSInteger)pageIndex {
    [pageView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat sideMargin = 28.0;
    CGFloat iconSize = self.itemWidth;
    CGFloat colSpacing = 28.0;
    CGFloat totalGridWidth = self.columns * iconSize + (self.columns - 1) * colSpacing;
    CGFloat startX = (w - totalGridWidth) / 2;
    if (startX < sideMargin) startX = sideMargin;
    
    // iOS 26: topInset clears status bar & Dynamic Island (safe area top ~62pt)
    // Push first row down by ~1/3 icon height (~20pt) from safe area top
    CGFloat topInset = 100.0;
    CGFloat rowSpacing = 20.0;
    
    for (NSInteger i = 0; i < items.count; i++) {
        LCOSAppModel *app = items[i];
        NSInteger col = i % self.columns;
        NSInteger row = i / self.columns;
        
        CGFloat x = startX + col * (iconSize + colSpacing);
        CGFloat y = topInset + row * (self.itemHeight + rowSpacing);
        
        LCOSAppIconView *iconView = [[LCOSAppIconView alloc] initWithAppModel:app];
        iconView.frame = CGRectMake(x, y, iconSize, self.itemHeight);
        iconView.onTap = ^(LCOSAppModel *tappedApp) {
            if (self.onAppTapped) {
                self.onAppTapped(tappedApp);
            }
        };
        [pageView addSubview:iconView];
        
        // Transparent button over the icon to guarantee tap delivery
        // (bypasses UIScrollView paging touch interception)
        UIButton *tapButton = [UIButton buttonWithType:UIButtonTypeCustom];
        tapButton.frame = iconView.bounds;
        tapButton.backgroundColor = [UIColor clearColor];
        [tapButton addTarget:self action:@selector(iconButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        tapButton.tag = i + pageIndex * self.itemsPerPage; // unique index across pages
        [iconView addSubview:tapButton];
    }
    
    pageView.frame = CGRectMake((CGFloat)pageIndex * w, 0, w, h);
    [self.scrollView addSubview:pageView];
}

- (void)relayoutCurrentPage {
    for (NSInteger p = 0; p < self.pages.count; p++) {
        UIView *pageView = self.pages[p];
        NSMutableArray *items = self.currentPageItems[p];
        [self layoutPage:pageView items:items pageIndex:p];
    }
    self.scrollView.contentSize = CGSizeMake(self.bounds.size.width * self.pages.count, self.bounds.size.height);
}

- (void)scrollToPage:(NSInteger)page animated:(BOOL)animated {
    if (page < 0 || page >= self.pages.count) return;
    self.currentPage = page;
    CGPoint offset = CGPointMake((CGFloat)page * self.bounds.size.width, 0);
    [self.scrollView setContentOffset:offset animated:animated];
}

// Button tap handler - finds app model by unique tag
- (void)iconButtonTapped:(UIButton *)button {
    NSInteger index = button.tag;
    if (index < 0 || index >= self.allApps.count) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: button tag %ld out of range", (long)index]];
        return;
    }
    LCOSAppModel *app = self.allApps[index];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: button tapped - %@", app.displayName]];
    if (self.onAppTapped) {
        self.onAppTapped(app);
    }
}

// UIScrollViewDelegate
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    NSInteger page = round(scrollView.contentOffset.x / scrollView.bounds.size.width);
    self.currentPage = MAX(0, MIN(page, self.pages.count - 1));
}

@end
