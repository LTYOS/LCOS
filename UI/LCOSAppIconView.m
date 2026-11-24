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
@property (nonatomic, assign) BOOL isPressed;

@end

@implementation LCOSAppIconView

- (instancetype)initWithAppModel:(LCOSAppModel *)appModel {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _appModel = appModel;
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = NO;
        self.userInteractionEnabled = YES;
        self.isPressed = NO;
        
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
        
        // Name label (iOS 26 style - below icon, close to it)
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
    
    // iOS 26 icon layout: icon at top, name below (close)
    CGFloat iconSize = MIN(w, h) * 0.72;
    CGFloat iconX = (w - iconSize) / 2;
    CGFloat iconY = 4;
    self.iconImageView.frame = CGRectMake(iconX, iconY, iconSize, iconSize);
    
    // Name label below icon (tight spacing)
    CGFloat labelY = iconY + iconSize + 2;
    CGFloat labelH = h - labelY - 2;
    self.nameLabel.frame = CGRectMake(0, labelY, w, labelH);
    
    // Highlight view matches bounds
    self.highlightView.frame = self.bounds;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    self.isPressed = YES;
    [UIView animateWithDuration:0.08 animations:^{
        self.highlightView.alpha = 0.35;
        self.iconImageView.transform = CGAffineTransformMakeScale(0.94, 0.94);
    }];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self];
    if (!CGRectContainsPoint(self.bounds, point)) {
        // Finger left the view, cancel press
        if (self.isPressed) {
            self.isPressed = NO;
            [UIView animateWithDuration:0.08 animations:^{
                self.highlightView.alpha = 0.0;
                self.iconImageView.transform = CGAffineTransformIdentity;
            }];
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    self.isPressed = NO;
    [UIView animateWithDuration:0.08 animations:^{
        self.highlightView.alpha = 0.0;
        self.iconImageView.transform = CGAffineTransformIdentity;
    }];
    
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self];
    if (CGRectContainsPoint(self.bounds, point) && self.onTap) {
        self.onTap(self.appModel);
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.isPressed = NO;
    [UIView animateWithDuration:0.08 animations:^{
        self.highlightView.alpha = 0.0;
        self.iconImageView.transform = CGAffineTransformIdentity;
    }];
}

@end
