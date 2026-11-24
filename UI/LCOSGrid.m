//
//  LCOSGrid.m
//  LCOS.dylib
//

#import "LCOSGrid.h"
#import "LCOSAppIconView.h"
#import "LCOSAppModel.h"
#import "LCOSLogManager.h"

@interface LCOSGrid () <UIGestureRecognizerDelegate, UIScrollViewDelegate>

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
        
        // Tap gesture on scrollView to catch icon taps (bypasses paging touch delays)
        UITapGestureRecognizer *gridTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleGridTap:)];
        gridTap.cancelsTouchesInView = NO;
        gridTap.delegate = self;
        [self.scrollView addGestureRecognizer:gridTap];
        
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
    // Icon size 60x60 pt, column spacing ~28pt, row spacing ~30pt
    // topInset clears status bar + Dynamic Island (safe area top ~62pt)
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

// Tap on grid - find which icon was tapped via hitTest
- (void)handleGridTap:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded) return;
    CGPoint point = [tap locationInView:self.scrollView];
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: tap at %@", NSStringFromCGPoint(point)]];
    
    // Find the page view containing the point
    NSInteger pageIndex = lround(point.x / self.scrollView.bounds.size.width);
    if (pageIndex < 0 || pageIndex >= self.pages.count) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: tap pageIndex %ld out of range", (long)pageIndex]];
        return;
    }
    
    UIView *pageView = self.pages[pageIndex];
    CGPoint pagePoint = CGPointMake(point.x - pageIndex * self.scrollView.bounds.size.width, point.y);
    
    // Hit test against icon views on this page
    for (UIView *subview in pageView.subviews) {
        if ([subview isKindOfClass:[LCOSAppIconView class]]) {
            CGPoint localPoint = [subview convertPoint:pagePoint fromView:self.scrollView];
            if (CGRectContainsPoint(subview.bounds, localPoint)) {
                LCOSAppIconView *iconView = (LCOSAppIconView *)subview;
                [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOSGrid: hit icon %@", iconView.appModel.displayName]];
                if (iconView.onTap) {
                    iconView.onTap(iconView.appModel);
                }
                return;
            }
        }
    }
    [[LCOSLogManager sharedManager] forceLog:@"LCOSGrid: tap hit no icon"];
}

// UIScrollViewDelegate
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    NSInteger page = round(scrollView.contentOffset.x / scrollView.bounds.size.width);
    self.currentPage = MAX(0, MIN(page, self.pages.count - 1));
}

// UIGestureRecognizerDelegate - allow tap to coexist with scroll
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}

@end
