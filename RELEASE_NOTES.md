## 本次更新（v1.0.95）

- 修复 `LCOSGrid` 将 UIScrollView 内置 pan 手势代理替换为自身，触发 `NSInvalidArgumentException` 并导致桌面黑屏、设置闪退的问题。
- 保留 `scrollView.delegate` 用于分页回调，不再改动 UIScrollView 必须自行持有的内置手势代理。
- Dock 桌面创建失败时清除半挂载状态和持久化“桌面可见”标记，恢复 LiveContainer 原生界面，避免下次启动重复恢复异常桌面。
- 启动自动恢复改为下一主队列执行，并加入异常回退，避免单个桌面异常阻止 LiveContainer 打开。
- 保持现有 Dock 手势、后台门禁、真实后台卡片和返回逻辑不变。

> 更新后请在 LiveContainer 的模块页面确认签名，然后重启 LiveContainer。
