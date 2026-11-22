//
//  LCOSSettingsView.m
//  LCOS.dylib
//

#import "LCOSSettingsView.h"
#import "LCOSLogManager.h"

@implementation LCOSSettingsView

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 60, self.view.frame.size.width, 40)];
    titleLabel.text = @"LCOS 设置";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [self.view addSubview:titleLabel];
    
    // Settings items placeholder
    // 1. 手势灵敏度调整
    // 2. Dock 配置
    // 3. 日志开关
    // 4. 应用图标布局
    
    [self logSettingsAccess];
}

- (void)logSettingsAccess {
    [[LCOSLogManager sharedManager] logMessage:@"用户进入 LCOS 设置页面" level:@"INFO"];
}

@end