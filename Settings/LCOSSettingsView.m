#import "LCOSSettingsView.h"
#import "LCOSLogManager.h"
#import "LCOSWallpaper.h"
#import "LCOSUpdateManager.h"
#import "LCOSDeveloperSettingsView.h"
#import "LCOSSigningView.h"
#import "LCOSCore.h"

@interface LCOSCore (LCOSSettingsInteraction)
- (void)updateInteractionState;
@end

static NSString *const kLCOSNativeNavigationKey = @"LCOSNativeNavigationEnabled";

@interface LCOSSettingsView () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UISwitch *nativeNavigationSwitch;
@property (nonatomic, strong) UIImageView *wallpaperPreview;
@property (nonatomic, strong) UIButton *updateButton;
@property (nonatomic, strong) UILabel *updateStatusLabel;
@property (nonatomic, assign) BOOL updateInProgress;
@end

@implementation LCOSSettingsView

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"LCOS 设置";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStyleDone target:self action:@selector(closeTapped:)];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.updateStatusLabel = [[UILabel alloc] init];
    self.updateStatusLabel.text = [NSString stringWithFormat:@"当前版本：%@", LCOSUpdateManager.shared.currentVersion];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Settings viewDidLoad"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 2 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"关闭后同时关闭原生导航条、右缘手势和原生后台入口；Dock 栏上滑进入 LCOS 不受影响。";
    if (section == 1) return @"选择相册图片作为 LCOS 桌面壁纸。";
    return self.updateStatusLabel.text.length ? self.updateStatusLabel.text : [NSString stringWithFormat:@"当前版本：%@", LCOSUpdateManager.shared.currentVersion];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"LiveContainer 原生界面导航条";
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        self.nativeNavigationSwitch = [[UISwitch alloc] init];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        self.nativeNavigationSwitch.on = [defaults objectForKey:kLCOSNativeNavigationKey] == nil || [defaults boolForKey:kLCOSNativeNavigationKey];
        [self.nativeNavigationSwitch addTarget:self action:@selector(nativeNavigationChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.nativeNavigationSwitch;
        return cell;
    }
    if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        self.wallpaperPreview = [[UIImageView alloc] init];
        self.wallpaperPreview.contentMode = UIViewContentModeScaleAspectFill;
        self.wallpaperPreview.clipsToBounds = YES;
        self.wallpaperPreview.layer.cornerRadius = 10;
        self.wallpaperPreview.backgroundColor = UIColor.tertiarySystemFillColor;
        self.wallpaperPreview.image = [[LCOSWallpaper shared] currentWallpaper];
        self.wallpaperPreview.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:self.wallpaperPreview];
        UILabel *label = [[UILabel alloc] init];
        label.text = @"桌面壁纸";
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [self.wallpaperPreview.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [self.wallpaperPreview.topAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.topAnchor],
            [self.wallpaperPreview.bottomAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.bottomAnchor],
            [self.wallpaperPreview.widthAnchor constraintEqualToConstant:54],
            [self.wallpaperPreview.heightAnchor constraintEqualToConstant:88],
            [label.leadingAnchor constraintEqualToAnchor:self.wallpaperPreview.trailingAnchor constant:16],
            [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        ]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (indexPath.row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"开发者功能";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = @"插件更新";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"当前版本：%@", LCOSUpdateManager.shared.currentVersion];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    self.updateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.updateButton setTitle:@"检查更新" forState:UIControlStateNormal];
    [self.updateButton addTarget:self action:@selector(checkForUpdates) forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = self.updateButton;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self presentWallpaperActions];
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        [self.navigationController pushViewController:[[LCOSDeveloperSettingsView alloc] init] animated:YES];
    }
}

- (void)nativeNavigationChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:kLCOSNativeNavigationKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    // Only NativeShell reads this key; LCOS desktop navigation is independent.
    [LCOSCore.sharedInstance updateInteractionState];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Settings: native navigation = %@", sender.isOn ? @"ON" : @"OFF"]];
}

- (void)presentWallpaperActions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"桌面壁纸" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"从相册选择" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self chooseWallpaper]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[LCOSWallpaper shared] clearWallpaper];
        self.wallpaperPreview.image = nil;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseWallpaper {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.allowsEditing = NO;
    [self presentViewController:picker animated:YES completion:nil];
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

- (void)updateStatus:(NSString *)text {
    self.updateStatusLabel.text = text;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)checkForUpdates {
    if (self.updateInProgress) return;
    self.updateInProgress = YES;
    self.updateButton.enabled = NO;
    self.updateStatusLabel.text = @"正在检查官方线路，超时将自动尝试加速线路…";
    __weak typeof(self) weakSelf = self;
    [LCOSUpdateManager.shared checkForUpdatesWithCompletion:^(NSDictionary *release, NSError *error) {
        LCOSSettingsView *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.updateInProgress = NO;
        strongSelf.updateButton.enabled = YES;
        if (error) { strongSelf.updateStatusLabel.text = error.localizedDescription; return; }
        if (!release) {
            strongSelf.updateStatusLabel.text = @"当前已是最新版本，或你已忽略该版本。";
            NSString *ignored = [NSUserDefaults.standardUserDefaults stringForKey:@"LCOSIgnoredReleaseVersion"];
            if (ignored.length) {
                [strongSelf presentAlert:@"已忽略更新" message:[NSString stringWithFormat:@"版本 %@ 已被忽略。\n点击“恢复检查”后，下次会重新提示该版本。", ignored] actionTitle:@"恢复检查" handler:^{
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"LCOSIgnoredReleaseVersion"];
                }];
            }
            return;
        }
        NSString *message = [NSString stringWithFormat:@"当前：%@\n新版：%@\n\n%@", LCOSUpdateManager.shared.currentVersion, release[@"version"], release[@"body"]];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"发现新版本" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"立即下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [strongSelf downloadRelease:release]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"忽略此版本" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [LCOSUpdateManager.shared ignoreRelease:release];
            strongSelf.updateStatusLabel.text = [NSString stringWithFormat:@"已忽略版本 %@", release[@"version"]];
        }]];
        [strongSelf presentViewController:alert animated:YES completion:nil];
    }];
}

- (void)downloadRelease:(NSDictionary *)release {
    self.updateInProgress = YES;
    self.updateButton.enabled = NO;
    self.updateStatusLabel.text = @"正在下载、校验并覆盖模块…";
    __weak typeof(self) weakSelf = self;
    [LCOSUpdateManager.shared downloadAndInstallRelease:release completion:^(NSError *error) {
        LCOSSettingsView *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.updateInProgress = NO;
        strongSelf.updateButton.enabled = YES;
        if (error) {
            strongSelf.updateStatusLabel.text = error.localizedDescription;
            [strongSelf presentAlert:@"更新未完成" message:error.localizedDescription];
            return;
        }
        strongSelf.updateStatusLabel.text = @"下载成功，请签名后重启 LiveContainer。";
        [strongSelf presentViewController:[[LCOSSigningView alloc] init] animated:YES completion:nil];
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

- (void)closeTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
