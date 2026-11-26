# LCOS.dylib

面向 LiveContainer 的 iPhone 桌面与手势插件，让应用启动、桌面导航和任务切换更接近 iOS 的使用体验。

## 项目简介

LCOS 在 LiveContainer 中提供独立桌面、应用网格、Dock、导航条与设置界面。插件区分宿主和普通 Guest App，并支持 LiveContainer 多任务窗口中的真实任务预览。

项目仍在持续开发和真机验证中，具体行为以当前 Release 为准。

## 开发环境

- **开发设备**：iPhone
- **开发软件**：Fish Pocket
- **运行环境**：未越狱 iPhone，侧载安装并配置 LiveContainer
- **目标系统**：iOS 15.0 及以上，arm64

## 三个基础手势

| 手势 | 功能 |
|------|------|
| LiveContainer Dock 栏单指上滑 | 进入 LCOS 桌面 |
| LCOS 桌面三指下滑 | 退出 LCOS 桌面，返回 LiveContainer 原生界面 |
| LCOS 桌面三指长按 | 进入 LCOS 设置 |

## 编译与发布

- 使用 GitHub Actions macOS runner 和 clang++ 编译。
- Release 仅提供 `LCOS.dylib`，不包含 ZIP 或版本号后缀。
- 推送 `vMAJOR.MINOR.PATCH` Tag 后构建并发布，插件内版本号直接取自 Tag。
- 同一 Tag 重跑不改变版本号，也不自动递增。
- Release 使用 `RELEASE_NOTES.md` 中的中文更新说明。

## 安装与测试

1. 从 GitHub Release 下载 `LCOS.dylib`。
2. 将模块放入 LiveContainer 的全局模块目录。
3. 使用 LiveContainer 的证书为模块签名。
4. 重启 LiveContainer 后进行真机验证。

## License

MIT License
