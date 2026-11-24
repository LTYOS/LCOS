#pragma once

#import <UIKit/UIKit.h>

@class LCOSAppModel;

NS_ASSUME_NONNULL_BEGIN

/// iOS 26 风格的单个应用图标：圆角图标 + 下方名称标签
@interface LCOSAppIconView : UIView

@property (nonatomic, strong, readonly) LCOSAppModel *appModel;
@property (nonatomic, copy, nullable) void (^onTap)(LCOSAppModel *appModel);

- (instancetype)initWithAppModel:(LCOSAppModel *)appModel NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
