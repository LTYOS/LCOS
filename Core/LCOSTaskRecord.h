#pragma once

#import <UIKit/UIKit.h>

@interface LCOSTaskRecord : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, strong) UIViewController *controller;
@property (nonatomic, assign) BOOL fromLCOS;
@property (nonatomic, copy) NSString *uuid;
@end
