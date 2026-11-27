#pragma once
#import <UIKit/UIKit.h>

@interface LCOSTaskRegistry : NSObject
+ (instancetype)shared;
- (BOOL)registerTask:(UIView *)view fromLCOS:(BOOL)fromLCOS;
- (void)unregisterTask:(UIView *)view;
- (void)unregisterTaskWithUUID:(NSString *)uuid;
- (BOOL)isTaskRunning:(UIView *)view;
- (NSArray<UIView *> *)runningTasksFromLCOS:(BOOL)fromLCOS;
- (UIView *)activeTaskFromLCOS:(BOOL)fromLCOS;
- (void)activateTask:(UIView *)view fromLCOS:(BOOL)fromLCOS;
- (BOOL)closeTask:(UIView *)view;
- (BOOL)hasRunningTasksFromLCOS:(BOOL)fromLCOS;
- (id)controllerForTask:(UIView *)view;
@end
