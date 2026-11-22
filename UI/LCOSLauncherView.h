#pragma once

#import <UIKit/UIKit.h>

@class LCOSGrid;
@class LCOSDock;

@interface LCOSLauncherView : UIViewController

@property (nonatomic, strong) LCOSGrid *grid;
@property (nonatomic, strong) LCOSDock *dock;

@end