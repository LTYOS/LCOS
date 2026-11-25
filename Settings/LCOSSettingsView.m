//
//  LCOSSettingsView.m
//  LCOS.dylib
//

#import "LCOSSettingsView.h"
#import "LCOSLogManager.h"
#import "LCOSWallpaper.h"
#import "LCOSLayoutSettingsView.h"
#import "LCOSCore.h"

static NSString *const kLCOSAutoRestoreKey = @"LCOSAutoRestoreDesktop";
static NSString *const kLCOSUsesGestureLauncherKey = @"LCOSUsesGestureLauncher";

@interface LCOSSettingsView () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISwitch *autoRestoreSwitch;
@property (nonatomic, strong) UIImageView *wallpaperPreview;
@end

@implementation LCOSSettingsView

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = @"LCOS 设置";
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.titleLabel];
    
    // Close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];
    
    // Auto-restore row: label + switch
    UILabel *autoRestoreLabel = [[UILabel alloc] init];
    autoRestoreLabel.text = @"启动时恢复桌面";
    autoRestoreLabel.font = [UIFont systemFontOfSize:17];
    autoRestoreLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:autoRestoreLabel];
    
    self.autoRestoreSwitch = [[UISwitch alloc] init];
    self.autoRestoreSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults objectForKey:kLCOSAutoRestoreKey] == nil ? YES : [defaults boolForKey:kLCOSAutoRestoreKey];
    self.autoRestoreSwitch.on = enabled;
    [self.autoRestoreSwitch addTarget:self action:@selector(autoRestoreChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.autoRestoreSwitch];
    
    UILabel *autoRestoreHint = [[UILabel alloc] init];
    autoRestoreHint.text = @"开启后，若上次在桌面退出，下次打开自动进入桌面";
    autoRestoreHint.font = [UIFont systemFontOfSize:13];
    autoRestoreHint.textColor = [UIColor secondaryLabelColor];
    autoRestoreHint.numberOfLines = 0;
    autoRestoreHint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:autoRestoreHint];
    
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
    
    // Second item: choose the only desktop entry method.
    UIButton *entryModeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    entryModeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    entryModeButton.titleLabel.font = [UIFont systemFontOfSize:17];
    entryModeButton.tag = 1001;
    [entryModeButton addTarget:self action:@selector(openEntryModeMenu) forControlEvents:UIControlEventTouchUpInside];
    entryModeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:entryModeButton];
    [NSLayoutConstraint activateConstraints:@[
        [entryModeButton.leadingAnchor constraintEqualToAnchor:autoRestoreLabel.leadingAnchor],
        [entryModeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [entryModeButton.topAnchor constraintEqualToAnchor:autoRestoreHint.bottomAnchor constant:20],
        [entryModeButton.heightAnchor constraintEqualToConstant:44],
    ]];
    [self updateEntryModeButton];
    
    // Wallpaper section
    UILabel *wallpaperLabel = [[UILabel alloc] init];
    wallpaperLabel.text = @"桌面壁纸";
    wallpaperLabel.font = [UIFont systemFontOfSize:17];
    wallpaperLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:wallpaperLabel];
    
    self.wallpaperPreview = [[UIImageView alloc] init];
    self.wallpaperPreview.contentMode = UIViewContentModeScaleAspectFill;
    self.wallpaperPreview.clipsToBounds = YES;
    self.wallpaperPreview.layer.cornerRadius = 12;
    self.wallpaperPreview.backgroundColor = [UIColor tertiarySystemFillColor];
    self.wallpaperPreview.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.wallpaperPreview];
    self.wallpaperPreview.image = [[LCOSWallpaper shared] currentWallpaper];
    
    UIButton *chooseBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [chooseBtn setTitle:@"从相册选择" forState:UIControlStateNormal];
    chooseBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [chooseBtn addTarget:self action:@selector(chooseWallpaper) forControlEvents:UIControlEventTouchUpInside];
    chooseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:chooseBtn];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearBtn setTitle:@"恢复默认" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [clearBtn addTarget:self action:@selector(clearWallpaper) forControlEvents:UIControlEventTouchUpInside];
    clearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:clearBtn];
    
    [NSLayoutConstraint activateConstraints:@[
        [wallpaperLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [wallpaperLabel.topAnchor constraintEqualToAnchor:entryModeButton.bottomAnchor constant:20],
        
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
    [self.view addSubview:developerLabel];

    UIButton *layoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    layoutButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [layoutButton setTitle:@"桌面布局  ›" forState:UIControlStateNormal];
    layoutButton.titleLabel.font = [UIFont systemFontOfSize:17];
    [layoutButton addTarget:self action:@selector(openLayoutSettings) forControlEvents:UIControlEventTouchUpInside];
    layoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:layoutButton];
    [NSLayoutConstraint activateConstraints:@[
        [developerLabel.leadingAnchor constraintEqualToAnchor:wallpaperLabel.leadingAnchor],
        [developerLabel.topAnchor constraintEqualToAnchor:self.wallpaperPreview.bottomAnchor constant:28],
        [layoutButton.leadingAnchor constraintEqualToAnchor:developerLabel.leadingAnchor],
        [layoutButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [layoutButton.topAnchor constraintEqualToAnchor:developerLabel.bottomAnchor constant:12],
        [layoutButton.heightAnchor constraintEqualToConstant:44],
    ]];

    [[LCOSLogManager sharedManager] forceLog:@"LCOS Settings viewDidLoad"];
}

- (void)updateEntryModeButton {
    BOOL gestures = [NSUserDefaults.standardUserDefaults objectForKey:kLCOSUsesGestureLauncherKey] == nil ? YES :
        [NSUserDefaults.standardUserDefaults boolForKey:kLCOSUsesGestureLauncherKey];
    UIButton *button = [self.view viewWithTag:1001];
    [button setTitle:[NSString stringWithFormat:@"桌面打开方式：%@  ›", gestures ? @"手势" : @"悬浮按钮"]
            forState:UIControlStateNormal];
}

- (void)openEntryModeMenu {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"桌面打开方式"
                                                                  message:@"两种方式互斥，选择后立即生效"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    BOOL gestures = [NSUserDefaults.standardUserDefaults objectForKey:kLCOSUsesGestureLauncherKey] == nil ? YES :
        [NSUserDefaults.standardUserDefaults boolForKey:kLCOSUsesGestureLauncherKey];
    [menu addAction:[UIAlertAction actionWithTitle:gestures ? @"✓ 手势" : @"手势"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *action) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kLCOSUsesGestureLauncherKey];
        [[LCOSCore sharedInstance] setUsesGestureLauncher:YES];
        [self updateEntryModeButton];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:gestures ? @"悬浮按钮" : @"✓ 悬浮按钮"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *action) {
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:kLCOSUsesGestureLauncherKey];
        [[LCOSCore sharedInstance] setUsesGestureLauncher:NO];
        [self updateEntryModeButton];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = [self.view viewWithTag:1001];
    menu.popoverPresentationController.sourceRect = [self.view viewWithTag:1001].bounds;
    [self presentViewController:menu animated:YES completion:nil];
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
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Settings close tapped")];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Settings viewDidAppear")];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Settings viewWillDisappear")];
}

@end