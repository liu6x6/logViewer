# Android 支持说明

本文档汇总 `logViewer` 当前 Android 支持的**实现状态、连接拓扑、接入方式与排障方法**。

## 当前结论

Android 支持已经不再停留在设计阶段，当前实现包含：

- Android 日志与网络请求远程接入 macOS `logViewer`
- Android 设备在 macOS 侧按 **Android** 平台显示
- 多设备日志 / 网络请求按设备隔离展示
- Android 真机自动发现 / 自动连接
- Android 模拟器手动连接与自动回退连接

## 架构原则

`logViewer` 的 Android 支持采用的是：

- **Chucker 负责本地抓包与本地调试**
- **logViewer Android SDK 负责远程发现、连接、上报**

这意味着：

- 不读取 Chucker 数据库
- 不把 Chucker 当成远程协议
- Android 与 macOS 之间使用单独的 TCP + JSON 协议

推荐共存方式：

```kotlin
val client = OkHttpClient.Builder()
    .addInterceptor(LogViewerOkHttpInterceptor(logViewerClient))
    .addInterceptor(ChuckerInterceptor(context))
    .build()
```

## 当前连接拓扑

为了兼容真机与模拟器，当前保留了两条自动链路和一条保底链路。

### 1. Android 主动发现 macOS `logViewer`

- macOS `logViewer` 广播：`_logviewer._tcp`
- Android 使用 `NsdManager` 发现该服务
- Android 主动发起 TCP 连接

这是 Android 真机最直接的自动连接路径。

### 2. macOS 主动发现 Android 设备

- Android 广播：`_logviewer-android._tcp`
- macOS 浏览 Android 服务并自动反连
- 建立连接后仍复用同一套 JSON 协议

这是为了满足“Android 被 `logViewer` 自动发现并自动连接”的体验要求。

### 3. Android 模拟器保底回退

Android 模拟器的 mDNS / NSD 在很多宿主机环境下并不稳定，因此当前额外支持：

- Host: `10.0.2.2`
- Port: `52888`

并且在自动模式下，如果识别到运行在模拟器中，会自动尝试该地址。

## 端口与服务类型

| 用途 | 值 |
| --- | --- |
| macOS Android 接收端口 | `52888` |
| macOS 广播 service type | `_logviewer._tcp` |
| Android 广播 service type | `_logviewer-android._tcp` |

如果你用 Bonjour / mDNS 扫描工具检查网络，需要注意：

- 扫描 `_logviewer._tcp` 看到的是 **macOS `logViewer`**
- 扫描 `_logviewer-android._tcp` 看到的是 **Android 设备**

## 数据协议

当前 Android 远程协议采用 **JSON**，首版重点覆盖三类事件：

1. `hello`
2. `message`
3. `networkCompleted`

其中：

- `hello` 用来完成设备识别与平台建模
- `message` 进入现有日志列表
- `networkCompleted` 进入现有 Network 列表和 Inspector

## macOS 侧落地

macOS 侧目前包含两部分：

1. **`AndroidRemoteLoggerServer`**
   - 监听固定端口 `52888`
   - 广播 `_logviewer._tcp`
   - 接收 Android 主动连入

2. **`AndroidRemoteLoggerBrowser`**
   - 浏览 `_logviewer-android._tcp`
   - 发现 Android 后主动建立 TCP 连接

这两条链路最终都会汇入：

- `ConnectionManager`
- `PulseStoreInjector`

因此 UI 层可以沿用现有的日志 / Network / Inspector 能力。

## 当前 UI 行为

### 设备平台显示

Android 设备在侧边栏中不再显示成 iPhone，而是使用独立的 Android 平台标识。

### 按设备隔离数据

当前日志与网络请求都按选中设备隔离显示。

实现方式：

- 日志记录按 `label` 过滤
- 网络记录按写入 `taskDescription` 的稳定设备标记过滤

网络任务写入时会带类似下面的标记：

```text
[logviewer-device:<peerID>]
```

### 历史数据限制

在这个设备标记机制接入之前写入的旧网络记录，并不带该标记，因此无法被准确回溯到具体设备。

## Android SDK 使用方式

### 自动模式

```kotlin
val client = LogViewerClient(context)
client.start()
```

`start()` 当前会同时做三件事：

1. 广播 Android 服务 `_logviewer-android._tcp`
2. 主动发现 macOS `_logviewer._tcp`
3. 若识别为模拟器，则自动尝试 `10.0.2.2:52888`

### 手动连接

```kotlin
client.connect(host = "10.0.2.2", port = 52888)
```

手动连接依然保留，适合：

- Android 模拟器
- mDNS 被企业网络 / VPN / AP 隔离的环境

## 常见问题

### 为什么 Android 扫描不到？

先确认你扫的是不是正确的 service type：

- 看 macOS `logViewer`：扫 `_logviewer._tcp`
- 看 Android 设备：扫 `_logviewer-android._tcp`

### 为什么模拟器仍然不稳定？

因为 Android 模拟器对宿主机 Bonjour / mDNS 的支持本来就不稳定，这不是 `logViewer` 独有问题。当前的正确兜底路径就是：

- 自动或手动连接 `10.0.2.2:52888`

### 为什么手动连接曾经失败？

之前的根因是：

- macOS TCP listener 启动与 Bonjour 发布耦合
- 一旦 Bonjour 配置或发布失败，`52888` 实际上并没有监听

当前已经修复为：

- TCP 监听先独立启动
- Bonjour 发布单独处理

## 后续可继续增强的方向

1. 心跳与重连退避
2. 更完整的日志桥接（Timber / Logcat）
3. 更完整的请求体 / 二进制体策略
4. 更强的请求导出与 Bruno 集成
