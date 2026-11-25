//
//  LCOSAppIconView.m
//  LCOS.dylib
//

#import "LCOSAppIconView.h"
#import "LCOSAppModel.h"
#import "LCOSLogManager.h"

@interface LCOSAppIconView ()

@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIView *highlightView;

@end

@implementation LCOSAppIconView

- (instancetype)initWithAppModel:(LCOSAppModel *)appModel {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _appModel = appModel;
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = NO;
        self.userInteractionEnabled = YES;
        
        // Icon image view
        self.iconImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.iconImageView.image = appModel.icon;
        self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        self.iconImageView.clipsToBounds = YES;
        self.iconImageView.layer.cornerRadius = 20;
        self.iconImageView.layer.cornerCurve = kCACornerCurveContinuous;
        self.iconImageView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.iconImageView.layer.shadowOpacity = 0.25;
        self.iconImageView.layer.shadowRadius = 8;
        self.iconImageView.layer.shadowOffset = CGSizeMake(0, 4);
        self.iconImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.iconImageView];
        
        // Name label (iOS 26 style - below icon, tight spacing)
        self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.nameLabel.text = appModel.displayName;
        self.nameLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        self.nameLabel.textColor = [UIColor whiteColor];
        self.nameLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.65];
        self.nameLabel.shadowOffset = CGSizeMake(0, 1);
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.nameLabel.numberOfLines = 1;
        self.nameLabel.backgroundColor = [UIColor clearColor];
        self.nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.nameLabel];
        
        }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    
    CGFloat iconSize = MIN(60.0, MIN(w, h - 20.0));
    self.iconImageView.autoresizingMask = UIViewAutoresizingNone;
    self.nameLabel.autoresizingMask = UIViewAutoresizingNone;
    self.iconImageView.frame = CGRectMake((w - iconSize) / 2.0, 0, iconSize, iconSize);
    self.nameLabel.frame = CGRectMake(0, iconSize + 3.0, w, 16.0);
}

@end
