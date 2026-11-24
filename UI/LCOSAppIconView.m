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
        self.nameLabel.textColor = [UIColor labelColor];
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.nameLabel.numberOfLines = 2;
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
    
    // iOS 26 icon layout: 60x60 icon at top, name below (tight)
    CGFloat iconSize = 60.0;
    CGFloat iconX = (w - iconSize) / 2;
    CGFloat iconY = 2;
    self.iconImageView.frame = CGRectMake(iconX, iconY, iconSize, iconSize);
    
    // Name label below icon (tight 2pt gap)
    CGFloat labelY = iconY + iconSize + 2;
    CGFloat labelH = h - labelY - 2;
    self.nameLabel.frame = CGRectMake(0, labelY, w, labelH);
}

@end
