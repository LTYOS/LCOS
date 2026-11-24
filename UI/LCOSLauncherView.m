//
//  LCOSLauncherView.m
//  LCOS.dylib
//

#import "LCOSLauncherView.h"
#import "LCOSFolder.h"
#import "LCOSGrid.h"
#import "LCOSDock.h"
#import "LCOSLogManager.h"
#import "LCOSCore.h"
#import "LCOSWallpaper.h"

@implementation LCOSLauncherView

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: init START"];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: init START"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [[LCOSLogManager sharedManager] forceLog:@"LCOS Launcher: viewDidLoad START"];
    
    // Wallpaper layer (bottom-most)
    self.wallpaperView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
    self.wallpaperView.clipsToBounds = YES;
    self.wallpaperView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.wallpaperView];
    [self reloadWallpaper];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadWallpaper) name:@"LCOSWallpaperDidChange" object:nil];
    
    // Setup grid (above wallpaper)
    self.grid = [[LCOSGrid alloc] initWithFrame:self.view.bounds];
    self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.grid];
    
    // Setup dock (floating capsule with side/bottom insets)
    self.dock = [[LCOSDock alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.dock];
    
    // Add close button (TOP LAYER - must be added last to be on top)
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.closeButton addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.closeButton];
    
    // Use view's layout guide for child VC compatibility
    UILayoutGuide *guide = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.closeButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20],
        [self.closeButton.topAnchor constraintEqualToAnchor:guide.topAnchor constant:20],
    ]];
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher: closeButton constraints set, guide.layoutFrame=%@", NSStringFromCGRect(guide.layoutFrame)]];
    
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher UI loaded, view bounds: %@", NSStringFromCGRect(self.view.bounds)]];
}

- (void)closeTapped:(UIButton *)sender {
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Launcher close tapped, sender=%@", sender]];
    [[LCOSCore sharedInstance] hideLauncher];
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
    
    // iOS 26/27 dock: ~98pt tall, 16pt side insets, floats above home indicator
    CGFloat dockHeight = 98.0;
    CGFloat dockSideInset = 16.0;
    CGFloat dockBottomGap = bottomInset > 0 ? bottomInset : 12.0;
    if (self.grid) {
        self.grid.frame = CGRectMake(0, 0, w, h - dockHeight - dockBottomGap - 12);
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