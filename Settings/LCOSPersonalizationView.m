#import "LCOSPersonalizationView.h"
#import "LCOSWallpaper.h"

@interface LCOSPersonalizationView () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIImageView *preview;
@end

@implementation LCOSPersonalizationView
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"个性化桌面";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"选择相册图片作为 LCOS 桌面壁纸。"; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 116; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @"桌面壁纸";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    self.preview = [[UIImageView alloc] initWithImage:[[LCOSWallpaper shared] currentWallpaper]];
    self.preview.contentMode = UIViewContentModeScaleAspectFill;
    self.preview.clipsToBounds = YES;
    self.preview.layer.cornerRadius = 10;
    self.preview.backgroundColor = UIColor.tertiarySystemFillColor;
    self.preview.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:self.preview];
    [NSLayoutConstraint activateConstraints:@[
        [self.preview.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor constant:-20],
        [self.preview.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [self.preview.widthAnchor constraintEqualToConstant:54],
        [self.preview.heightAnchor constraintEqualToConstant:88],
    ]];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"桌面壁纸" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"从相册选择" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[LCOSWallpaper shared] clearWallpaper];
        self.preview.image = nil;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (image) {
        [[LCOSWallpaper shared] setWallpaper:image];
        self.preview.image = image;
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
@end
