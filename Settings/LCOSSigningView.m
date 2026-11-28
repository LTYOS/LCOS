#import "LCOSSigningView.h"
#import "LCOSUpdateManager.h"
#import "LCOSLogManager.h"

@interface LCOSSigningView ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *signButton;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, assign) BOOL signing;
@property (nonatomic, assign) BOOL signed;
@end

@implementation LCOSSigningView

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.title = @"插件更新";
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    UILabel *title = [[UILabel alloc] init];
    title.text = @"下载成功";
    title.font = [UIFont boldSystemFontOfSize:24];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.text = @"已覆盖 LCOS.dylib，并仅保留更新前一份带版本号的备份。\n\n请先调用 LiveContainer 签名，成功后点击完成返回设置，再重启 LiveContainer。";
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.signButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.signButton.configuration = [UIButtonConfiguration filledButtonConfiguration];
    self.signButton.configuration.title = @"签名";
    [self.signButton addTarget:self action:@selector(signTapped) forControlEvents:UIControlEventTouchUpInside];
    self.signButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.doneButton.configuration = [UIButtonConfiguration grayButtonConfiguration];
    self.doneButton.configuration.title = @"完成";
    [self.doneButton addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    self.doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    for (UIView *view in @[title, self.statusLabel, self.signButton, self.doneButton]) [self.view addSubview:view];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:28],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [self.statusLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16],
        [self.signButton.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.signButton.trailingAnchor constraintEqualToAnchor:self.statusLabel.trailingAnchor],
        [self.signButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:30],
        [self.signButton.heightAnchor constraintEqualToConstant:48],
        [self.doneButton.leadingAnchor constraintEqualToAnchor:self.signButton.leadingAnchor],
        [self.doneButton.trailingAnchor constraintEqualToAnchor:self.signButton.trailingAnchor],
        [self.doneButton.topAnchor constraintEqualToAnchor:self.signButton.bottomAnchor constant:12],
        [self.doneButton.heightAnchor constraintEqualToConstant:48],
    ]];
}

- (void)signTapped {
    if (self.signing || self.signed) return;
    self.signing = YES;
    self.signButton.enabled = NO;
    self.signButton.configuration.title = @"正在签名…";
    self.statusLabel.text = @"正在调用 LiveContainer 签名接口，请保持此页面打开。";
    __weak typeof(self) weakSelf = self;
    [LCOSUpdateManager.shared signInstalledPluginWithCompletion:^(NSError *error) {
        LCOSSigningView *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.signing = NO;
        if (error) {
            strongSelf.signButton.enabled = YES;
            strongSelf.signButton.configuration.title = @"重试签名";
            strongSelf.statusLabel.text = [NSString stringWithFormat:@"签名失败：%@\n请重试，或点击完成返回设置。", error.localizedDescription];
            return;
        }
        strongSelf.signed = YES;
        strongSelf.signButton.configuration.title = @"已签名";
        strongSelf.signButton.enabled = NO;
        strongSelf.statusLabel.text = @"签名成功。请点击完成返回设置，然后重启 LiveContainer。";
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Settings: signing panel confirmed success"];
    }];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
