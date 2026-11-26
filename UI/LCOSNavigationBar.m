#import "LCOSNavigationBar.h"

@interface LCOSNavigationBar ()
@property (nonatomic, strong) UIView *solidPill;
@end

@implementation LCOSNavigationBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;
        self.accessibilityIgnoresInvertColors = YES;
        self.accessibilityLabel = @"导航条";
        self.accessibilityHint = @"向左滑动返回桌面，停住进入后台";
        self.solidPill = [[UIView alloc] init];
        self.solidPill.backgroundColor = UIColor.whiteColor;
        self.solidPill.userInteractionEnabled = NO;
        self.solidPill.accessibilityIgnoresInvertColors = YES;
        self.solidPill.layer.cornerRadius = 2.5;
        self.solidPill.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:self.solidPill];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = 5.0;
    CGFloat height = MIN(134.0, self.bounds.size.height);
    self.solidPill.frame = CGRectMake(self.bounds.size.width - width - 6.0,
        (self.bounds.size.height - height) / 2.0, width, height);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds, -8, -16), point);
}

@end
