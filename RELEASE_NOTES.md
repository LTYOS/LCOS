## 本次更新（v1.0.94）

- 修复 `LCOSLauncherView` 已初始化成功、但 Core 读取仍为 nil 导致无法进入 LCOS 桌面的问题。
- 修正 `setLauncherView:`：由 Core 的 strong 属性真实持有桌面控制器，不再只转发对象而不保存。
- LCOSShell 继续接收桌面控制器对应的 UIView，区分控制器所有权与视图引用，不改变现有导航逻辑。
- 保留桌面初始化诊断、nil 与类型校验以及失败回滚，避免无效控制器进入 UIKit 挂载流程。
- 保持现有 Dock 手势、后台门禁、真实后台卡片和返回逻辑不变。

> 更新后请在 LiveContainer 的模块页面确认签名，然后重启 LiveContainer。
