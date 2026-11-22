//
//  LCOSFolder.m
//  LCOS.dylib
//

#import "LCOSFolder.h"
#import "LCOSLogManager.h"

@implementation LCOSFolder

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 60, self.view.frame.size.width, 40)];
    titleLabel.text = self.folderName ?: @"文件夹";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];
    
    [[LCOSLogManager sharedManager] logMessage:[NSString stringWithFormat:@"LCOS folder opened: %@", self.folderName ?: @"Unknown"] level:@"INFO"];
}

@end