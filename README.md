# LCOS.dylib

LiveContainer 插件：在 iPhone 上打造类似 iOS 系统的桌面启动器与手势交互。

## 项目简介

LCOS.dylib 是一个 LiveContainer 插件，旨在将 LiveContainer 的 UI 操作和逻辑靠向原生 iOS 系统桌面体验，让 LiveContainer 使用起来像第二个 iOS 系统。

本插件通过 **NSExtension + GuestHooks** 持住 PKHost 方法，使用 **XPC + Mach bootstrap** 通信注入 LiveContainer 进程，实现三大功能模块：

1. **启动器（LCOS Launcher）** - 类似 iOS 26/27 桌面界面，包含应用、源、模块、设置，可创建文件夹，支持左右滑动页面。
2. **手势交互（LCOS Gestures）** - 三指上滑进入 LCOS UI，三指下滑返回 LiveContainer 原生界面；三指长按进入设置；左侧边缘 iOS 风格交互。
3. **设置与日志（LCOS Settings & Logs）** - 三指长按进入设置，可修改 LCOS 功能，生成日志便于 Bug 定位。

## 使用前提

- 设备：iPhone（未越狱，侧载安装 LiveContainer）
- LiveContainer 已在沙箱内加载 ID 证书，可对 .dylib 进行签名
- 本插件**无需签名**，编译出 `.dylib` 即可，在手机上通过 LiveContainer 导入、签名后重启测试

## 仓库结构

```
LCOS/
├── .github/workflows/build.yml     # GitHub Actions 编译与发布工作流
├── Core/                           # 核心模块
│   ├── LCOSCore.h/m                # 插件核心入口、XPC 客户端
│   ├── LCOSXPC.h/m                 # XPC 通信封装
│   └── LCOSConfig.h/m              # 配置管理
├── UI/                             # 启动器界面
│   ├── LCOSLauncherView.h/m        # 主界面
│   ├── LCOSFolder.h/m              # 文件夹
│   ├── LCOSDock.h/m                # Dock 栏
│   └── LCOSGrid.h/m                # 图标网格
├── Gestures/                       # 手势交互
│   ├── LCOSGestureHandler.h/m      # 手势处理器
│   └── LCOSFloatingReturn.h/m      # 悬浮返回按钮（参考 LC-Floating-Return）
├── Settings/                       # 设置与日志
│   ├── LCOSSettingsView.h/m        # 设置界面
│   └── LCOSLogManager.h/m          # 日志管理器
└── Background/                     # 后台管理
    ├── LCOSBackground.h/m          # 后台进程
    └── LCOSAppContainer.h/m        # 应用容器管理
```

## 命令类型

| 命令 | 类型 | 描述 |
|------|------|------|
| `LCLivePlugInCommandLaunchConfiguration` | 1 | 启动配置 |
| `LCLivePlugInCommandError` | 2 | 错误上报 |
| `LCLivePlugInCommandConnect` | 3 | 建立连接 |

## 编译与发布

本项目使用 GitHub Actions 自动编译：

- **运行环境**：macOS-14，Xcode 15.4
- **编译器**：clang++
- **目标架构**：arm64（iPhone）
- **最低 iOS 版本**：iOS 15.0
- **输出**：`LCOS.dylib` + `LCOS.dylib.zip`

触发方式：
- 推送 `main` 分支 → 触发编译，上传 artifact
- 推送 `v*` 标签 → 触发编译并创建 GitHub Release

## 使用步骤

1. 在 GitHub Actions 页面下载最新的 `LCOS.dylib`（或 Release 下载 `LCOS1.0.x.dylib`）
2. 在 iPhone 上打开 LiveContainer
3. 导入 `LCOS.dylib`，使用已加载的 ID 证书进行签名
4. 重启 LiveContainer，插件自动生效

## 参考项目

- [LiveContainer](https://github.com/LiveContainer/LiveContainer) - 插件宿主项目
- [LC-Floating-Return](https://github.com/LinkPass888/LC-Floating-Return) - 悬浮返回按钮插件参考

## License

MIT License
