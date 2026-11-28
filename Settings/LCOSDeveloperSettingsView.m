#import "LCOSDeveloperSettingsView.h"
#import "LCOSLayoutSettingsView.h"
#import "LCOSLayout.h"
#import "LCOSLogManager.h"

@interface LCOSDeveloperSettingsView ()
@property (nonatomic, strong) UISwitch *autoRestoreSwitch;
@property (nonatomic, strong) UISlider *sheetRadiusSlider;
@property (nonatomic, strong) UILabel *sheetRadiusValueLabel;
@end

@implementation LCOSDeveloperSettingsView

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"开发者功能";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 1 ? 2 : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"开启后，若上次在桌面退出，下次打开自动进入桌面。" : @"调整桌面进入与退出时的顶部圆角，实时保存。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"启动时恢复桌面";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        self.autoRestoreSwitch = [[UISwitch alloc] init];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        self.autoRestoreSwitch.on = [defaults objectForKey:@"LCOSAutoRestoreDesktop"] == nil || [defaults boolForKey:@"LCOSAutoRestoreDesktop"];
        [self.autoRestoreSwitch addTarget:self action:@selector(autoRestoreChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.autoRestoreSwitch;
        return cell;
    }
    if (indexPath.row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"桌面布局";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *label = [[UILabel alloc] init];
    label.text = @"桌面滑动顶部弧度";
    label.translatesAutoresizingMaskIntoConstraints = NO;
    self.sheetRadiusValueLabel = [[UILabel alloc] init];
    self.sheetRadiusValueLabel.textColor = UIColor.secondaryLabelColor;
    self.sheetRadiusValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.sheetRadiusSlider = [[UISlider alloc] init];
    self.sheetRadiusSlider.minimumValue = 0;
    self.sheetRadiusSlider.maximumValue = 60;
    self.sheetRadiusSlider.value = [LCOSLayout value:@"sheetRadius"];
    self.sheetRadiusSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sheetRadiusSlider addTarget:self action:@selector(sheetRadiusChanged:) forControlEvents:UIControlEventValueChanged];
    [cell.contentView addSubview:label];
    [cell.contentView addSubview:self.sheetRadiusValueLabel];
    [cell.contentView addSubview:self.sheetRadiusSlider];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [label.topAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.topAnchor],
        [self.sheetRadiusValueLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        [self.sheetRadiusValueLabel.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
        [self.sheetRadiusSlider.leadingAnchor constraintEqualToAnchor:label.leadingAnchor],
        [self.sheetRadiusSlider.trailingAnchor constraintEqualToAnchor:self.sheetRadiusValueLabel.trailingAnchor],
        [self.sheetRadiusSlider.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8],
        [self.sheetRadiusSlider.bottomAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.bottomAnchor],
    ]];
    [self updateRadiusLabel];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1 || indexPath.row != 0) return;
    LCOSLayoutSettingsView *controller = [[LCOSLayoutSettingsView alloc] init];
    controller.modalPresentationStyle = UIModalPresentationOverFullScreen;
    controller.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)autoRestoreChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:@"LCOSAutoRestoreDesktop"];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Settings: auto-restore desktop = %@", sender.isOn ? @"ON" : @"OFF"]];
}

- (void)updateRadiusLabel {
    self.sheetRadiusValueLabel.text = [NSString stringWithFormat:@"%.1f pt", [LCOSLayout value:@"sheetRadius"]];
}

- (void)sheetRadiusChanged:(UISlider *)slider {
    [LCOSLayout setValue:slider.value forKey:@"sheetRadius"];
    [self updateRadiusLabel];
}

@end
