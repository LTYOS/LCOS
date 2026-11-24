//
//  LCOSAppIconView.m
//  LCOS.dylib
//

#import "LCOSAppIconView.h"
#import "LCOSAppModel.h"

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
        
        // Highlight view (iOS 26 style - subtle background on press)
        self.highlightView = [[UIView alloc] initWithFrame:self.bounds];
        self.highlightView.backgroundColor = [UIColor whiteColor];
        self.highlightView.alpha = 0.0;
        self.highlightView.layer.cornerRadius = 14;
        self.highlightView.layer.cornerCurve = kCACornerCurveContinuous;
        self.highlightView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.highlightView];
        
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
        
        // Name label (iOS 26 style - below icon)
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
        
        // Tap gesture
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
        
        // Long press gesture (for future long-press interactions)
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.5;
        longPress.allowableMovement = 15;
        [self addGestureRecognizer:longPress];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    
    // iOS 26 icon layout: icon at top, name below
    CGFloat iconSize = MIN(w, h) * 0.62;
    CGFloat iconX = (w - iconSize) / 2;
    CGFloat iconY = 4;
    self.iconImageView.frame = CGRectMake(iconX, iconY, iconSize, iconSize);
    
    // Name label below icon
    CGFloat labelY = iconY + iconSize + 4;
    CGFloat labelH = h - labelY - 2;
    self.nameLabel.frame = CGRectMake(0, labelY, w, labelH);
}

- (void)setHighlighted:(BOOL)highlighted {
    [UIView animateWithDuration:0.1 animations:^{
        self.highlightView.alpha = highlighted ? 0.3 : 0.0;
        self.iconImageView.transform = highlighted ? CGAffineTransformMakeScale(0.92, 0.92) : CGAffineTransformIdentity;
    }];
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateEnded && self.onTap) {
        self.onTap(self.appModel);
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPress {
    // Placeholder for future long-press interactions (edit mode, etc.)
    if (longPress.state == UIGestureRecognizerStateBegan) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"LCOSAppIconLongPressed" object:self.appModel];
    }
}

@end
