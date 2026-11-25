#import "LCOSNavigationBar.h"

@interface LCOSNavigationBar ()
@property (nonatomic, strong) UIVisualEffectView *glassView;
@end

@implementation LCOSNavigationBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;
        self.accessibilityLabel = @"对谨条";
        self.accessibilityHint = @"测迅边端滞动以当当打开同可或返回桌面";
        if (@available(iOS 26.0, *)) {
            self.glassView = [[UIVisualEffectView alloc] initWithEffect:[UIGlassEffect effect]];
        } else {
            self.glassView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        }
        self.glassView.userInteractionEnabled = NO;
        self.glassView.layer.cornerRadius = 3.0;
        self.glassView.layer.cornerCurve = kCACornerCurveContinuous;
        self.glassView.layer.borderWidth = 0.0;
        self.glassView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.42].CGColor;
        self.glassView.clipsToBounds = YES;
        if (@available(iOS 26.0, *)) {
            self.glassView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.68];
        } else {
            self.glassView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.55];
        }
        [self addSubview:self.glassView];
        UIView *highlight = [[UIView alloc] init];
        highlight.userInteractionEnabled = NO;
        highlight.backgroundColor = [UIColor colorWithWhite:1 alpha:0.42];
        highlight.layer.cornerRadius = 0.5;
        highlight.tag = 21;
        [self addSubview:highlight];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = 5.0;
    CGFloat height = MIN(134.0, self.bounds.size.height);
    CGRect pill = CGRectMake((self.bounds.size.width - width) / 2.0,
                             (self.bounds.size.height - height) / 2.0, width, height);
    self.glassView.frame = pill;
    UIView *highlight = [self viewWithTag:21];
    highlight.frame = CGRectMake(CGRectGetMidX(pill) - 0.5, CGRectGetMinY(pill) + 5,
                                 1.0, MAX(0, height - 10));
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds, -8, -16), point);
}

@end