//
//  LCOSSettingsView.m
//  LCOS.dylib
//

#import "LCOSSettingsView.h"
#import "LCOSLogManager.h"
#import "LCOSWallpaper.h"
#import "LCOSLayoutSettingsView.h"
#import "LCOSLayout.h"
#import "LCOSCore.h"
#import "LCOSUpdateManager.h"

static NSString *const kLCOSAutoRestoreKey = @"LCOSAutoRestoreDesktop";

@interface LCOSSettingsView () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UIButton *updateButton;
@property (nonatomic, strong) UILabel *updateStatusLabel;
@property (nonatomic, assign) BOOL updateInProgress;
@property (nonatomic, strong) UISwitch *autoRestoreSwitch;
@property (nonatomic, strong) UIImageView *wallpaperPreview;
@property (nonatomic, strong) UISlider *sheetRadiusSlider;
@property (nonatomic, strong) UILabel *sheetRadiusValueLabel;
@end

@implementation LCOSSettingsView

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];
    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
    ]];
    
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = @"LCOS 设置";
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.titleLabel];
    
    // Close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:closeButton];
    
    // Auto-restore row: label + switch
    UILabel *autoRestoreLabel = [[UILabel alloc] init];
    autoRestoreLabel.text = @"启动时恢复桌面";
    autoRestoreLabel.font = [UIFont systemFontOfSize:17];
    autoRestoreLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:autoRestoreLabel];
    
    self.autoRestoreSwitch = [[UISwitch alloc] init];
    self.autoRestoreSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults objectForKey:kLCOSAutoRestoreKey] == nil ? YES : [defaults boolForKey:kLCOSAutoRestoreKey];
    self.autoRestoreSwitch.on = enabled;
    [self.autoRestoreSwitch addTarget:self action:@selector(autoRestoreChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.autoRestoreSwitch];
    
    UILabel *autoRestoreHint = [[UILabel alloc] init];
    autoRestoreHint.text = @"开启后，若上次在桌面退出，下次打开自动进入桌面";
    autoRestoreHint.font = [UIFont systemFontOfSize:13];
    autoRestoreHint.textColor = [UIColor secondaryLabelColor];
    autoRestoreHint.numberOfLines = 0;
    autoRestoreHint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:autoRestoreHint];
    
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20],
        
        [closeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20],
        
        [autoRestoreLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [autoRestoreLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:40],
        
        [self.autoRestoreSwitch.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.autoRestoreSwitch.centerYAnchor constraintEqualToAnchor:autoRestoreLabel.centerYAnchor],
        [autoRestoreLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.autoRestoreSwitch.leadingAnchor constant:-12],
        
        [autoRestoreHint.leadingAnchor constraintEqualToAnchor:autoRestoreLabel.leadingAnchor],
        [autoRestoreHint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [autoRestoreHint.topAnchor constraintEqualToAnchor:autoRestoreLabel.bottomAnchor constant:8],
    ]];
    
    // Wallpaper section
    UILabel *wallpaperLabel = [[UILabel alloc] init];
    wallpaperLabel.text = @"桌面壁纸";
    wallpaperLabel.font = [UIFont systemFontOfSize:17];
    wallpaperLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:wallpaperLabel];
    
    self.wallpaperPreview = [[UIImageView alloc] init];
    self.wallpaperPreview.contentMode = UIViewContentModeScaleAspectFill;
    self.wallpaperPreview.clipsToBounds = YES;
    self.wallpaperPreview.layer.cornerRadius = 12;
    self.wallpaperPreview.backgroundColor = [UIColor tertiarySystemFillColor];
    self.wallpaperPreview.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.wallpaperPreview];
    self.wallpaperPreview.image = [[LCOSWallpaper shared] currentWallpaper];
    
    UIButton *chooseBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [chooseBtn setTitle:@"从相册选择" forState:UIControlStateNormal];
    chooseBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [chooseBtn addTarget:self action:@selector(chooseWallpaper) forControlEvents:UIControlEventTouchUpInside];
    chooseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:chooseBtn];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearBtn setTitle:@"恢复默认" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [clearBtn addTarget:self action:@selector(clearWallpaper) forControlEvents:UIControlEventTouchUpInside];
    clearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:clearBtn];
    
    [NSLayoutConstraint activateConstraints:@[
        [wallpaperLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [wallpaperLabel.topAnchor constraintEqualToAnchor:autoRestoreHint.bottomAnchor constant:32],
        
        [self.wallpaperPreview.leadingAnchor constraintEqualToAnchor:wallpaperLabel.leadingAnchor],
        [self.wallpaperPreview.topAnchor constraintEqualToAnchor:wallpaperLabel.bottomAnchor constant:12],
        [self.wallpaperPreview.widthAnchor constraintEqualToConstant:120],
        [self.wallpaperPreview.heightAnchor constraintEqualToConstant:200],
        
        [chooseBtn.leadingAnchor constraintEqualToAnchor:self.wallpaperPreview.trailingAnchor constant:20],
        [chooseBtn.topAnchor constraintEqualToAnchor:self.wallpaperPreview.topAnchor constant:20],
        
        [clearBtn.leadingAnchor constraintEqualToAnchor:chooseBtn.leadingAnchor],
        [clearBtn.topAnchor constraintEqualToAnchor:chooseBtn.bottomAnchor constant:16],
    ]];
    
    UILabel *developerLabel = [[UILabel alloc] init];
    developerLabel.text = @"开发者功能";
    developerLabel.font = [UIFont boldSystemFontOfSize:17];
    developerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:developerLabel];

    UIButton *layoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    layoutButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [layoutButton setTitle:@"桌面布局  ›" forState:UIControlStateNormal];
    layoutButton.titleLabel.font = [UIFont systemFontOfSize:17];
    [layoutButton addTarget:self action:@selector(openLayoutSettings) forControlEvents:UIControlEventTouchUpInside];
    layoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:layoutButton];
    [NSLayoutConstraint activateConstraints:@[
        [developerLabel.leadingAnchor constraintEqualToAnchor:wallpaperLabel.leadingAnchor],
        [developerLabel.topAnchor constraintEqualToAnchor:self.wallpaperPreview.bottomAnchor constant:28],
        [layoutButton.leadingAnchor constraintEqualToAnchor:developerLabel.leadingAnchor],
        [layoutButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [layoutButton.topAnchor constraintEqualToAnchor:developerLabel.bottomAnchor constant:12],
        [layoutButton.heightAnchor constraintEqualToConstant:44],
    ]];

    // Keep this frequently used developer control on the main settings page.
    UILabel *radiusLabel = [[UILabel alloc] init];
    radiusLabel.text = @"桌面滑动顶部弧度";
    radiusLabel.font = [UIFont systemFontOfSize:15];
    radiusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:radiusLabel];
    self.sheetRadiusValueLabel = [[UILabel alloc] init];
    self.sheetRadiusValueLabel.textAlignment = NSTextAlignmentRight;
    self.sheetRadiusValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.sheetRadiusValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.sheetRadiusValueLabel];
    self.sheetRadiusSlider = [[UISlider alloc] init];
    self.sheetRadiusSlider.minimumValue = 0;
    self.sheetRadiusSlider.maximumValue = 60;
    self.sheetRadiusSlider.value = [LCOSLayout value:@"sheetRadius"];
    self.sheetRadiusSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sheetRadiusSlider addTarget:self action:@selector(sheetRadiusChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.sheetRadiusSlider];
    [self updateSheetRadiusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [radiusLabel.leadingAnchor constraintEqualToAnchor:layoutButton.leadingAnchor],
        [radiusLabel.topAnchor constraintEqualToAnchor:layoutButton.bottomAnchor constant:14],
        [self.sheetRadiusValueLabel.trailingAnchor constraintEqualToAnchor:layoutButton.trailingAnchor],
        [self.sheetRadiusValueLabel.centerYAnchor constraintEqualToAnchor:radiusLabel.centerYAnchor],
        [self.sheetRadiusSlider.leadingAnchor constraintEqualToAnchor:radiusLabel.leadingAnchor],
        [self.sheetRadiusSlider.trailingAnchor constraintEqualToAnchor:layoutButton.trailingAnchor],
        [self.sheetRadiusSlider.topAnchor constraintEqualToAnchor:radiusLabel.bottomAnchor constant:4],
        [self.sheetRadiusSlider.heightAnchor constraintEqualToConstant:36],
    ]];

    UILabel *updateHeading = [[UILabel alloc] init];
    updateHeading.text = @"插件更新";
    updateHeading.font = [UIFont boldSystemFontOfSize:17];
    updateHeading.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:updateHeading];
    self.versionLabel = [[UILabel alloc] init];
    self.versionLabel.text = [NSString stringWithFormat:@"当前版本：%@", LCOSUpdateManager.shared.currentVersion];
    self.versionLabel.font = [UIFont systemFontOfSize:15];
    self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.versionLabel];
    self.updateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.updateButton setTitle:@"检查更新" forState:UIControlStateNormal];
    self.updateButton.backgroundColor = UIColor.systemBlueColor;
    [self.updateButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.updateButton.layer.cornerRadius = 12;
    self.updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.updateButton addTarget:self action:@selector(checkForUpdates) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.updateButton];
    self.updateStatusLabel = [[UILabel alloc] init];
    self.updateStatusLabel.font = [UIFont systemFontOfSize:13];
    self.updateStatusLabel.textColor = UIColor.secondaryLabelColor;
    self.updateStatusLabel.numberOfLines = 0;
    self.updateStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.updateStatusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [updateHeading.leadingAnchor constraintEqualToAnchor:radiusLabel.leadingAnchor],
        [updateHeading.topAnchor constraintEqualToAnchor:self.sheetRadiusSlider.bottomAnchor constant:30],
        [self.versionLabel.leadingAnchor constraintEqualToAnchor:updateHeading.leadingAnchor],
        [self.versionLabel.topAnchor constraintEqualToAnchor:updateHeading.bottomAnchor constant:12],
        [self.updateButton.leadingAnchor constraintEqualToAnchor:updateHeading.leadingAnchor],
        [self.updateButton.trailingAnchor constraintEqualToAnchor:self.sheetRadiusSlider.trailingAnchor],
        [self.updateButton.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor constant:16],
        [self.updateButton.heightAnchor constraintEqualToConstant:46],
        [self.updateStatusLabel.leadingAnchor constraintEqualToAnchor:updateHeading.leadingAnchor],
        [self.updateStatusLabel.trailingAnchor constraintEqualToAnchor:self.sheetRadiusSlider.trailingAnchor],
        [self.updateStatusLabel.topAnchor constraintEqualToAnchor:self.updateButton.bottomAnchor constant:12],
        [self.updateStatusLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-32],
    ]];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Settings viewDidLoad"];
}

- (void)checkForUpdates {
    if (self.updateInProgress) return;
    self.updateInProgress = YES;
    self.updateButton.enabled = NO;
    self.updateStatusLabel.text = @"正在检查 GitHub 最新发行版…";
    [LCOSUpdateManager.shared checkForUpdatesWithCompletion:^(NSDictionary *release, NSError *error) {
        self.updateInProgress = NO;
        self.updateButton.enabled = YES;
        if (error) { self.updateStatusLabel.text = error.localizedDescription; return; }
        if (!release) {
            self.updateStatusLabel.text = @"当前已是最新版本，或你已忽略该版本。";
            NSString *ignored = [NSUserDefaults.standardUserDefaults stringForKey:@"LCOSIgnoredReleaseVersion"];
            if (ignored.length) {
                [self presentAlert:@"已忽略更新" message:[NSString stringWithFormat:@"版本 %@ 已被忽略。\n点击“恢复检查”后，下次会重新提示该版本。", ignored] actionTitle:@"恢复检查" handler:^{
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"LCOSIgnoredReleaseVersion"];
                }];
            }
            return;
        }
        NSString *message = [NSString stringWithFormat:@"当前：%@\n新版：%@\n\n%@",
            LCOSUpdateManager.shared.currentVersion, release[@"version"], release[@"body"]];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"发现新版本" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"立即下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self downloadRelease:release];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"忽略此版本" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [LCOSUpdateManager.shared ignoreRelease:release];
            self.updateStatusLabel.text = [NSString stringWithFormat:@"已忽略版本 %@", release[@"version"]];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

- (void)downloadRelease:(NSDictionary *)release {
    self.updateInProgress = YES;
    self.updateButton.enabled = NO;
    self.updateStatusLabel.text = @"正在下载、校验并覆盖模块…";
    [LCOSUpdateManager.shared downloadAndInstallRelease:release completion:^(NSError *error) {
        self.updateInProgress = NO;
        self.updateButton.enabled = YES;
        if (error) {
            self.updateStatusLabel.text = error.localizedDescription;
            [self presentAlert:@"更新未完成" message:error.localizedDescription];
            return;
        }
        self.updateStatusLabel.text = @"下载成功，已覆盖模块。请先点击“签名”，完成后重启 LiveContainer。";
        __weak LCOSSettingsView *weakSelf = self;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"下载成功" message:@"已覆盖 LCOS.dylib，并仅保留更新前一份带版本号的备份。\n请先签名，再点击完成返回设置。" preferredStyle:UIAlertControllerStyleAlert];
        __block UIAlertAction *signAction = nil;
        signAction = [UIAlertAction actionWithTitle:@"签名" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            // UIAlertAction handlers normally dismiss their alert. Reinstate the
            // same controller to keep signing as an explicit, retryable step.
            void (^presentForSigning)(void) = ^{
                LCOSSettingsView *strongSelf = weakSelf;
                if (!strongSelf || strongSelf.presentedViewController) return;
                [strongSelf presentViewController:alert animated:NO completion:nil];
            };
            signAction.enabled = NO;
            self.updateStatusLabel.text = @"正在调用 LiveContainer 签名接口…";
            [LCOSUpdateManager.shared signInstalledPluginWithCompletion:^(NSError *error) {
                if (error) {
                    signAction.enabled = YES;
                    self.updateStatusLabel.text = error.localizedDescription;
                    alert.message = [NSString stringWithFormat:@"签名失败：%@\n请重试，或点击完成返回设置。", error.localizedDescription];
                    presentForSigning();
                    return;
                }
                [signAction setValue:@"已签名" forKey:@"title"];
                alert.title = @"已签名";
                alert.message = @"签名成功。请点击完成返回设置，然后重启 LiveContainer。";
                self.updateStatusLabel.text = @"已签名。请点击完成，然后重启 LiveContainer。";
                presentForSigning();
            }];
        }];
        [alert addAction:signAction];
        [alert addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

- (void)presentAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentAlert:(NSString *)title message:(NSString *)message actionTitle:(NSString *)actionTitle handler:(dispatch_block_t)handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { if (handler) handler(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateSheetRadiusLabel {
    self.sheetRadiusValueLabel.text = [NSString stringWithFormat:@"%.1f pt", [LCOSLayout value:@"sheetRadius"]];
}

- (void)sheetRadiusChanged:(UISlider *)slider {
    [LCOSLayout setValue:slider.value forKey:@"sheetRadius"];
    [self updateSheetRadiusLabel];
}

- (void)openLayoutSettings {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Layout: opening translucent desktop controls"];
    LCOSLayoutSettingsView *controller = [[LCOSLayoutSettingsView alloc] init];
    controller.modalPresentationStyle = UIModalPresentationOverFullScreen;
    controller.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    UIViewController *presenter = self.presentingViewController;
    if (!presenter) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Layout: no desktop presenter available"];
        return;
    }
    [self dismissViewControllerAnimated:NO completion:^{
        [presenter presentViewController:controller animated:YES completion:^{
            [[LCOSLogManager sharedManager] forceLog:@"LCOS Layout: controls presented over desktop"];
        }];
    }];
}

- (void)chooseWallpaper {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.allowsEditing = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)clearWallpaper {
    [[LCOSWallpaper shared] clearWallpaper];
    self.wallpaperPreview.image = nil;
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Settings: wallpaper cleared"];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (image) {
        [[LCOSWallpaper shared] setWallpaper:image];
        self.wallpaperPreview.image = image;
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)autoRestoreChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:kLCOSAutoRestoreKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Settings: auto-restore desktop = %@", sender.isOn ? @"ON" : @"OFF"]];
}

- (void)closeTapped:(UIButton *)sender {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Settings close tapped"];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Settings viewDidAppear"];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Settings viewWillDisappear"];
}

@end