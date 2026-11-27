//
//  LCOSLauncherView.m
//  LCOS.dylib
//

#import "LCOSLauncherView.h"
#import "LCOSFolder.h"
#import "LCOSGrid.h"
#import "LCOSDock.h"
#import "LCOSAppModel.h"
#import "LCOSLogManager.h"
#import "LCOSCore.h"
#import "LCOSWallpaper.h"

@implementation LCOSLauncherView

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: designated init ENTRY"];
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
        @"LCOS Launcher: super init returned %@", self ? NSStringFromClass(self.class) : @"nil"]];
    if (!self) return nil;
    // This controller is embedded as a child, not presented modally. Avoid
    // changing presentation policy during its allocation-sensitive init path.
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: designated init EXIT"];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: viewDidLoad START"];
    
    // Stage logs identify the exact failing stage if a host API changes.
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: wallpaper stage"];
    self.wallpaperView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
    self.wallpaperView.clipsToBounds = YES;
    self.wallpaperView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.wallpaperView];
    [self reloadWallpaper];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadWallpaper) name:@"LCOSWallpaperDidChange" object:nil];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: grid allocation stage"];
    self.grid = [[LCOSGrid alloc] initWithFrame:self.view.bounds];
    self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.grid.onAppTapped = ^(LCOSAppModel *appModel) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher: app tapped - %@", appModel.displayName]];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"LCOSLauncherVisible"];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"LCOSLaunchFromDesktop"];
        [appModel launch];
    };    [self.view addSubview:self.grid];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: app enumeration stage"];
    NSArray<LCOSAppModel *> *installedApps = [LCOSAppModel allInstalledApps];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher: grid population stage, apps=%lu", (unsigned long)installedApps.count]];
    [self.grid setApps:installedApps];

    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: dock allocation stage"];
    self.dock = [[LCOSDock alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.dock];
    
    // The shared floating button remains above the launcher and acts as its
    // close button. Do not create a second button with a different position.

    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher UI loaded, view bounds: %@", NSStringFromCGRect(self.view.bounds)]];
}

- (void)reloadWallpaper {
    UIImage *img = [[LCOSWallpaper shared] currentWallpaper];
    self.wallpaperView.image = img;
    self.wallpaperView.backgroundColor = img ? nil : [UIColor systemBackgroundColor];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat bottomInset = self.view.safeAreaInsets.bottom;
    
    // iOS 26/27 dock: ~110pt tall, 16pt side insets, floats just above home indicator
    CGFloat dockHeight = 110.0;
    CGFloat dockSideInset = 16.0;
    CGFloat dockBottomGap = bottomInset > 0 ? bottomInset * 0.6 : 8.0;
    if (self.grid) {
        self.grid.frame = CGRectMake(0, 0, w, h - dockHeight - dockBottomGap);
    }
    if (self.dock) {
        self.dock.frame = CGRectMake(dockSideInset, h - dockHeight - dockBottomGap, w - dockSideInset * 2, dockHeight);
    }
    
    if (self.closeButton) {
        [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher: closeButton frame=%@", NSStringFromCGRect(self.closeButton.frame)]];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher viewDidAppear"];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher viewWillDisappear"];
}

@end
