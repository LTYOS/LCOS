## 本次更新（v1.0.93）

- 针对 Dock 上滑后 `LCOSLauncherView` 初始化返回 nil、导致无法进入桌面的问题，调整桌面控制器初始化路径。
- 移除子控制器初始化阶段不必要的 `modalPresentationStyle` 设置，避免在对象尚未完成创建时改变模态呈现策略。
- 使用标准 `initWithNibName:nil bundle:nil` 创建桌面控制器，移除重复的 `init` 包装，保留统一指定初始化流程。
- 增加指定初始化入口、父类初始化返回与最终出口日志，区分“开始初始化”和“成功返回对象”。
- Core 分开记录控制器 `alloc` 与 `init` 结果，保留 nil、类型及父子控制器校验，不强行挂载无效对象。
- 保持现有 Dock 手势、后台门禁、真实后台卡片和返回逻辑不变。

> 更新后请在 LiveContainer 的模块页面确认签名，然后重启 LiveContainer。
