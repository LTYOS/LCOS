#import "LCOSLayoutSettingsView.h"
#import "LCOSLayout.h"
#import "LCOSLogManager.h"

@interface LCOSLayoutSettingsView ()
@property (nonatomic, strong) NSArray<NSString *> *keys;
@property (nonatomic, strong) NSArray<NSString *> *names;
@property (nonatomic, strong) NSArray<NSNumber *> *mins;
@property (nonatomic, strong) NSArray<NSNumber *> *maxs;
@property (nonatomic, strong) NSMutableArray<UILabel *> *valueLabels;
@property (nonatomic, strong) NSMutableArray<UISlider *> *sliders;
@end

@implementation LCOSLayoutSettingsView

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.keys = @[@"iconSize", @"cornerRadius", @"labelGap", @"topInset", @"bottomInset",
                  @"rowSpacing", @"columnSpacing", @"pageSize", @"pageOffset"];
    self.names = @[@"图标大小", @"图标四个角弧度", @"图标名字上下距离", @"图标最上面距离", @"图标最下面距离",
                   @"图标上下间距", @"图标左右间距", @"页面指示器大小", @"指示器上下位置"];
    self.mins = @[@40, @0, @0, @0, @0, @0, @0, @4, @-60];
    self.maxs = @[@100, @30, @24, @200, @120, @60, @60, @16, @60];
    self.valueLabels = [NSMutableArray array];
    self.sliders = [NSMutableArray array];

    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 24;
    card.clipsToBounds = YES;
    [self.view addSubview:card];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"桌面布局";
    title.font = [UIFont boldSystemFontOfSize:20];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:title];

    UILabel *hint = [[UILabel alloc] init];
    hint.text = @"拖动滑块，桌面实时预览并自动保存";
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = UIColor.secondaryLabelColor;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:hint];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"完成" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [done addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:done];

    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    [copy setTitle:@"复制参数" forState:UIControlStateNormal];
    [copy addTarget:self action:@selector(copyTapped) forControlEvents:UIControlEventTouchUpInside];
    copy.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:copy];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"恢复默认" forState:UIControlStateNormal];
    [reset setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    reset.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:reset];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [card.contentView addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    for (NSInteger i = 0; i < self.keys.count; i++) {
        UILabel *label = [[UILabel alloc] init];
        label.font = [UIFont systemFontOfSize:14];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.valueLabels addObject:label];

        UISlider *slider = [[UISlider alloc] init];
        slider.tag = i;
        slider.minimumValue = self.mins[i].floatValue;
        slider.maximumValue = self.maxs[i].floatValue;
        slider.value = [LCOSLayout value:self.keys[i]];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self.sliders addObject:slider];

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, slider]];
        row.axis = UILayoutConstraintAxisVertical;
        row.spacing = 2;
        [stack addArrangedSubview:row];
        [self updateLabelAt:i];
    }

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10],
        [card.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.62],

        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [hint.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],

        [done.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [done.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],

        [scroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [scroll.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:12],
        [scroll.bottomAnchor constraintEqualToAnchor:copy.topAnchor constant:-10],

        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],

        [copy.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [copy.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [reset.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [reset.centerYAnchor constraintEqualToAnchor:copy.centerYAnchor],
    ]];
}

- (void)updateLabelAt:(NSInteger)i {
    self.valueLabels[i].text = [NSString stringWithFormat:@"%@：%.1f", self.names[i], [LCOSLayout value:self.keys[i]]];
}

- (void)sliderChanged:(UISlider *)slider {
    NSInteger i = slider.tag;
    if (i < 0 || i >= (NSInteger)self.keys.count) return;
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:
        @"LCOS Layout: slider %@ = %.1f", self.keys[i], slider.value]];
    [LCOSLayout setValue:slider.value forKey:self.keys[i]];
    [self updateLabelAt:i];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)copyTapped {
    UIPasteboard.generalPasteboard.string = [LCOSLayout summary];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Layout copied: %@", [LCOSLayout summary]]];
}

- (void)resetTapped {
    [LCOSLayout reset];
    for (NSInteger i = 0; i < self.keys.count; i++) {
        self.sliders[i].value = [LCOSLayout value:self.keys[i]];
        [self updateLabelAt:i];
    }
}

@end
