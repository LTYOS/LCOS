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
        self.scrollView.delegate = self;
        [self addSubview:self.scrollView];
        
        self.pages = [NSMutableArray array];
        self.currentPageItems = [NSMutableArray array];
        self.currentPage = 0;
        
        // iOS 26 grid defaults: 4 columns x 6 rows per page on iPhone
        self.columns = 4;
        self.rows = 6;
        self.itemsPerPage = self.columns * self.rows;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.bounds;
    
    // Recalculate layout based on current size
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    
    // iOS 26 layout: larger icons, name close below, grid shifted down
    CGFloat sideMargin = 16.0;
    CGFloat availableWidth = w - sideMargin * 2;
    self.itemWidth = availableWidth / self.columns;
    self.itemHeight = self.itemWidth * 1.25; // icon + name space
    
    // Re-layout existing pages
    [self relayoutCurrentPage];
}

- (void)setApps:(NSArray<LCOSAppModel *> *)apps {
    _allApps = [apps copy];
    
    // Remove existing page views
    for (UIView *page in self.pages) {
        [page removeFromSuperview];
    }
    [self.pages removeAllObjects];
    [self.currentPageItems removeAllObjects];
    
    if (_allApps.count == 0) {
        self.scrollView.contentSize = CGSizeZero;
        return;
    }
    
    // Create pages
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
    
    // Show first page
    [self scrollToPage:0 animated:NO];
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: loaded %lu apps in %ld pages", (unsigned long)_allApps.count, (long)totalPages]];
}

- (void)layoutPage:(UIView *)pageView items:(NSMutableArray *)items pageIndex:(NSInteger)pageIndex {
    [pageView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat sideMargin = 16.0;
    CGFloat itemW = self.itemWidth;
    CGFloat itemH = self.itemHeight;
    
    // Calculate grid origin to center horizontally
    CGFloat totalGridWidth = self.columns * itemW;
    CGFloat startX = (w - totalGridWidth) / 2;
    if (startX < sideMargin) startX = sideMargin;
    
    // iOS 26: grid shifted down to avoid status bar & Dynamic Island
    CGFloat topInset = 70.0;
    CGFloat rowSpacing = 20.0;
    CGFloat colSpacing = (w - sideMargin * 2 - totalGridWidth) / (self.columns - 1);
    if (colSpacing < 0) colSpacing = 8.0;
    
    for (NSInteger i = 0; i < items.count; i++) {
        LCOSAppModel *app = items[i];
        NSInteger col = i % self.columns;
        NSInteger row = i / self.columns;
        
        CGFloat x = startX + col * (itemW + colSpacing);
        CGFloat y = topInset + row * (itemH + rowSpacing);
        
        LCOSAppIconView *iconView = [[LCOSAppIconView alloc] initWithAppModel:app];
        iconView.frame = CGRectMake(x, y, itemW, itemH);
        iconView.onTap = ^(LCOSAppModel *tappedApp) {
            if (self.onAppTapped) {
                self.onAppTapped(tappedApp);
            }
        };
        [pageView addSubview:iconView];
    }
    
    // Add page to scroll view
    pageView.frame = CGRectMake((CGFloat)pageIndex * w, 0, w, h);
    [self.scrollView addSubview:pageView];
}

- (void)relayoutCurrentPage {
    // Re-layout all pages when size changes
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

// UIScrollViewDelegate
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    NSInteger page = round(scrollView.contentOffset.x / scrollView.bounds.size.width);
    self.currentPage = MAX(0, MIN(page, self.pages.count - 1));
}

@end
