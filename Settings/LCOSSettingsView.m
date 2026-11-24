//
//  LCOSSettingsView.m
//  LCOS.dylib
//

#import "LCOSSettingsView.h"
#import "LCOSLogManager.h"
#import "LCOSWallpaper.h"

static NSString *const kLCOSAutoRestoreKey = @"LCOSAutoRestoreDesktop";

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
    
    [[LCOSLogManager sharedManager] forceLog:@("LCOS Settings viewDidLoad")];
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