#import "LCOSSettingsView.h"
#import "LCOSLogManager.h"
#import "LCOSUpdateManager.h"
#import "LCOSDeveloperSettingsView.h"
#import "LCOSPersonalizationView.h"
#import "LCOSSigningView.h"
#import "LCOSLaunchBridge.h"
#import "LCOSCore.h"

@interface LCOSCore (LCOSSettingsInteraction)
- (void)updateInteractionState;
@end

@interface LCOSSettingsView ()
@property (nonatomic, strong) UISwitch *nativeInteractionSwitch;
@property (nonatomic, strong) UILabel *updateStatusLabel;
@property (nonatomic, assign) BOOL updateInProgress;
@end

@implementation LCOSSettingsView

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"LCOS 设置";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.updateStatusLabel = [[UILabel alloc] init];
    self.updateStatusLabel.text = [NSString stringWithFormat:@"当前版本：%@", LCOSUpdateManager.shared.currentVersion];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Settings viewDidLoad"];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 2 ? 2 : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"关闭后停用 LiveContainer 原生导航、右缘手势和后台入口；Dock 栏上滑进入 LCOS 不受影响。";
    if (section == 2) return self.updateStatusLabel.text;
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.numberOfLines = 0;
    if (indexPath.section == 0) {
        cell.textLabel.text = @"LiveContainer 交互";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        self.nativeInteractionSwitch = [[UISwitch alloc] init];
        self.nativeInteractionSwitch.on = LCOSNativeInteractionEnabled();
        [self.nativeInteractionSwitch addTarget:self action:@selector(nativeInteractionChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.nativeInteractionSwitch;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @"个性化桌面";
        cell.imageView.image = [UIImage systemImageNamed:@"paintpalette"];
    } else if (indexPath.row == 0) {
        cell.textLabel.text = @"开发者功能";
        cell.imageView.image = [UIImage systemImageNamed:@"hammer"];
    } else {
        cell.textLabel.text = @"检查更新";
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
        cell.accessoryType = self.updateInProgress ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self.navigationController pushViewController:[[LCOSPersonalizationView alloc] init] animated:YES];
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        [self.navigationController pushViewController:[[LCOSDeveloperSettingsView alloc] init] animated:YES];
    } else if (indexPath.section == 2) {
        [self checkForUpdates];
    }
}
- (void)nativeInteractionChanged:(UISwitch *)sender {
    LCOSSetNativeInteractionEnabled(sender.isOn);
    [LCOSCore.sharedInstance updateInteractionState];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Settings: native interaction = %@", sender.isOn ? @"ON" : @"OFF"]];
}
- (void)updateStatus:(NSString *)text {
    self.updateStatusLabel.text = text;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)checkForUpdates {
    if (self.updateInProgress) return;
    self.updateInProgress = YES;
    [self updateStatus:@"正在检查官方线路，超时将自动尝试加速线路…"];
    __weak typeof(self) weakSelf = self;
    [LCOSUpdateManager.shared checkForUpdatesWithCompletion:^(NSDictionary *release, NSError *error) {
        LCOSSettingsView *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.updateInProgress = NO;
        if (error) { [strongSelf updateStatus:error.localizedDescription]; return; }
        if (!release) {
            [strongSelf updateStatus:[NSString stringWithFormat:@"当前版本：%@，已是最新版本。", LCOSUpdateManager.shared.currentVersion]];
            NSString *ignored = [NSUserDefaults.standardUserDefaults stringForKey:@"LCOSIgnoredReleaseVersion"];
            if (ignored.length) {
                [strongSelf presentAlert:@"已忽略更新" message:[NSString stringWithFormat:@"版本 %@ 已被忽略。\n点击“恢复检查”后，下次会重新提示该版本。", ignored] actionTitle:@"恢复检查" handler:^{
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"LCOSIgnoredReleaseVersion"];
                }];
            }
            return;
        }
        [strongSelf updateStatus:[NSString stringWithFormat:@"发现新版本：%@", release[@"version"]]];
        NSString *message = [NSString stringWithFormat:@"当前：%@\n新版：%@\n\n%@", LCOSUpdateManager.shared.currentVersion, release[@"version"], release[@"body"]];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"发现新版本" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"立即下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [strongSelf downloadRelease:release]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"忽略此版本" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [LCOSUpdateManager.shared ignoreRelease:release];
            [strongSelf updateStatus:[NSString stringWithFormat:@"已忽略版本 %@", release[@"version"]]];
        }]];
        [strongSelf presentViewController:alert animated:YES completion:nil];
    }];
}
- (void)downloadRelease:(NSDictionary *)release {
    self.updateInProgress = YES;
    [self updateStatus:@"正在下载、校验并覆盖模块…"];
    __weak typeof(self) weakSelf = self;
    [LCOSUpdateManager.shared downloadAndInstallRelease:release completion:^(NSError *error) {
        LCOSSettingsView *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.updateInProgress = NO;
        if (error) {
            [strongSelf updateStatus:error.localizedDescription];
            [strongSelf presentAlert:@"更新未完成" message:error.localizedDescription];
            return;
        }
        [strongSelf updateStatus:@"下载成功，请签名后重启 LiveContainer。"];
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
@end
