#pragma once

#import <UIKit/UIKit.h>

@class LCOSAppModel;

NS_ASSUME_NONNULL_BEGIN

/// iOS 26 顾式的应用图标网格，支持分顶翻顾
@interface LCOSGrid : UIView

@property (nonatomic, strong) NSMutableArray *pages;
@property (nonatomic, strong) NSMutableArray *currentPageItems;

/** 设置要显示的应用模型数组（会自动分顶） */
- (void)setApps:(NSArray<LCOSAppModel *> *)apps;

/** 点况图标回调 */
@property (nonatomic, copy, nullable) void (^onAppTapped)(LCOSAppModel *appModel);

/** Suspends paging while another full-screen gesture owns the touch. */
- (void)setLauncherGestureActive:(BOOL)active;

@end

NS_ASSUME_NONNULL_END