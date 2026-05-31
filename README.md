# logViewer

`logViewer` 是一个面向本地调试场景的 macOS 日志与网络请求查看器，当前主要覆盖两类接入方式：

- **iOS Custom Mode**
  - iOS App 通过 `MultipeerConnectivity` 主动广播并把日志 / 网络摘要发送到 macOS
- **Android Remote Mode**
  - Android App 通过 **mDNS/NSD + TCP + JSON 协议** 与 macOS `logViewer` 自动发现、自动连接或手动连接

## 当前能力

- 按设备查看日志与网络请求
- Request Inspector 中支持复制请求关键信息并重新发送请求
- Android 设备在侧边栏中以独立平台类型显示
- Android / iOS 多设备数据在中间面板按设备隔离展示
- Android 支持：
  - 真机自动发现 / 自动连接
  - 模拟器自动回退 `10.0.2.2:52888`
  - 保留手动连接

## 文档导航

| 文档 | 说明 |
| --- | --- |
| `docs/android-support.md` | Android 支持的现状、架构、发现机制、排障说明 |
| `docs/custom-mode.md` | iOS Custom Mode 集成说明 |
| `docs/pulse-mode.md` | Pulse 模式说明 |
| `docs/modes-comparison.md` | 不同模式的对比 |
| `快捷方式.md` | Request 复制 / Send Again / 右键菜单 / 快捷键设计说明 |
| `Packages/LogViewerCustomMode/README.md` | iOS Custom Mode Swift Package 的使用方式 |
| `../logViewerAndroid/README.md` | Android SDK 与 Demo 的使用方式 |

## Android 拓扑概览

当前 Android 支持同时保留了两条自动连接路径：

1. **Android 主动发现 macOS `logViewer`**
   - macOS 广播 `_logviewer._tcp`
   - Android 用 `NsdManager` 发现后主动连入

2. **macOS 主动发现 Android 设备**
   - Android 广播 `_logviewer-android._tcp`
   - macOS 浏览该服务后自动建立 TCP 连接

如果 Android 运行在模拟器里，还会额外尝试：

- `10.0.2.2:52888`

这样即使模拟器环境下 mDNS 不稳定，仍然可以完成连接。

## 开发与验证

### macOS

```bash
xcodebuild -project logViewer.xcodeproj \
  -scheme logViewer \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Android

```bash
cd ../logViewerAndroid
./gradlew :logviewer-android:assemble
./gradlew :app:assembleDebug
```

## 说明

- 旧的 Android 网络记录如果是在“按设备打标”能力接入之前写入的，无法被准确回溯到具体设备。
- Android 模拟器的 mDNS 能力依赖宿主机 / 模拟器网络环境，自动回退到 `10.0.2.2:52888` 是保底路径。
