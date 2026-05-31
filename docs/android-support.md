# Android 支持方案

本文档说明 `logViewer` 后续如果要支持 **Android 日志与网络请求远程接入**，推荐采用什么架构、为什么这样设计，以及第一阶段该如何落地。

先说结论：

- **不要让 Android 依赖 Chucker 来“导出”数据给 logViewer**
- **让 Chucker 继续负责 Android 本地查看**
- **另外增加一条 Android -> macOS 的远程上报链路**

也就是说，Chucker 是本地调试工具，`logViewer` 是远程聚合查看工具，这两者应该**并存**，而不是互相替代。

## 1. 目标

Android 支持完成后，理想体验应该是：

1. Android App 启动后，能自动发现同一局域网内的 `logViewer`
2. `logViewer` 中能看到 Android 设备在线
3. Android 普通日志能实时进入 `logViewer`
4. Android 网络请求能进入现有 Network 列表和 Inspector
5. 继续复用现有的：
   - Copy URL
   - Copy Query Parameters
   - Copy Headers
   - Copy Body
   - Copy cURL
   - Send Again

## 2. 为什么不能直接把 Chucker 当远程协议

Chucker 非常适合 Android 本地抓包，但它的职责主要是：

- 拦截 OkHttp 请求
- 在设备本地展示请求详情
- 把记录保存在本地数据库中供 App 内查看

它**并不是远程日志协议**，也不负责：

- 发现局域网里的 `logViewer`
- 跟 macOS 建立稳定连接
- 向远端实时推送日志或网络事件
- 维护跨平台可演进的数据协议

所以如果只是“接入 Chucker”，你能得到的是 **Android 本地可看**，但并不能天然得到 **Mac 上的 logViewer 可看**。

## 3. 推荐架构

推荐把 Android 支持拆成 6 层：

| 层 | 推荐方案 |
|---|---|
| Android 网络采集 | `ChuckerInterceptor` + 自定义 `LogViewerOkHttpInterceptor` |
| Android 日志采集 | `LogViewerLogger` / Timber Tree / Logcat bridge |
| 服务发现 | Android `NsdManager` 发现 Bonjour 服务 |
| 传输层 | TCP 或 WebSocket 长连接 |
| 数据协议 | 自定义跨平台协议，建议 JSON / CBOR / protobuf |
| macOS 接收端 | 新增 `AndroidRemoteLoggerServer`，并接入 `ConnectionManager` |

这里最关键的一点是：

- **Chucker 继续负责本地抓包**
- **LogViewer Android SDK 负责远程发送**

## 4. Android 侧如何和 Chucker 共存

正确方式不是去读 Chucker 的数据库，而是在同一个 `OkHttpClient` 上同时挂两个 interceptor：

```kotlin
val client = OkHttpClient.Builder()
    .addInterceptor(LogViewerOkHttpInterceptor(logViewerClient))
    .addInterceptor(ChuckerInterceptor(context))
    .build()
```

这样职责会很清晰：

- `ChuckerInterceptor`
  - 负责 Android 设备本地调试
  - 负责本地 UI 和本地历史

- `LogViewerOkHttpInterceptor`
  - 负责把请求摘要上报给 `logViewer`
  - 负责格式化成远程协议包
  - 负责传输失败重试、丢弃、限流等策略

为什么不建议“读 Chucker 数据库后再转发”：

1. 链路变复杂
2. 时效性差
3. 耦合 Chucker 内部实现
4. 以后切别的拦截器方案会更难迁移

## 5. logViewer 如何发现 Android

发现关系应该反过来：不是 `logViewer` 去扫描 Android，而是 **Android 主动发现 `logViewer`**。

推荐方式：

1. macOS 上的 `logViewer` 启动一个新服务，例如：
   - Bonjour service: `_logviewer._tcp`
2. Android 用 `NsdManager` 在局域网扫描这个服务
3. 发现后建立 TCP 或 WebSocket 长连接
4. 建立连接后先发一个 `hello` 包

`hello` 包建议带这些字段：

- `platform = "android"`
- `deviceId`
- `deviceName`
- `appId`
- `appVersion`
- `osVersion`
- `sdkVersion`

这样 `ConnectionManager` 就能把 Android 设备纳入统一的设备管理与在线状态视图。

## 6. 传输层建议

### 6.1 不推荐继续复用 MultipeerConnectivity

当前自定义模式用的是 `MultipeerConnectivity`，这对 Apple 生态非常方便，但 Android 无法直接参与。

所以 Android 支持不能沿用现在这条 Apple-only transport。

### 6.2 推荐 TCP 或 WebSocket

推荐优先级如下：

1. **TCP 长连接**
   - 更接近现有 Pulse 模式思路
   - 控制权高
   - 自定义 framing 简单直接

2. **WebSocket**
   - 调试更方便
   - Android 侧接入容易
   - 后续如果想扩展到别的平台也更通用

如果只考虑你当前这类局域网调试工具，**TCP 长连接**会更贴近现在工程结构。

## 7. 协议层建议

### 7.1 不要继续用 binary PropertyList 作为跨平台协议

现在 iOS 自定义模式 package 里的协议是：

- `LogPacket`
- `LogMessagePayload`
- `LogNetworkPayload`
- binary PropertyList 编解码

这套协议适合 Apple-to-Apple，但不适合 Android 跨平台扩展。

### 7.2 推荐新建跨平台协议层

建议把协议抽成独立的一层，例如：

- `LogViewerProtocol`

里面只保留跨平台 packet 定义，不绑定 Apple transport。

推荐编码格式：

- **JSON**
  - 最容易调试
  - 最适合先快速打通 MVP

- **CBOR**
  - 比 JSON 更紧凑
  - 仍然容易跨平台实现

- **protobuf**
  - 长期演进更稳
  - 字段升级最规范
  - 但第一阶段接入成本更高

如果你现在以“先做出来”为目标，建议：

- **MVP 用 JSON**
- 稳定后再升级到 protobuf 或 CBOR

## 8. 推荐的数据模型

第一阶段只需要两类事件就够用：

### 8.1 `message`

字段建议：

- `timestamp`
- `level`
- `category`
- `message`
- `tag`
- `thread`

### 8.2 `networkCompleted`

MVP 建议只上报“完成态”，字段至少包含：

- `id`
- `timestamp`
- `url`
- `method`
- `requestHeaders`
- `requestBody`
- `responseHeaders`
- `responseBody`
- `statusCode`
- `error`
- `durationMs`

为什么先做完成态：

1. Android 侧最容易实现
2. 最快进入现有 Inspector 工作流
3. 足够支撑 Bruno / cURL / Send Again

等第一版跑稳了，再考虑扩展：

- `networkStarted`
- `networkProgress`
- `redirect`
- `metrics`

## 9. macOS 侧该怎么接

推荐新增一条新的服务端链路：

- `AndroidRemoteLoggerServer`

职责：

1. 监听 `_logviewer._tcp`
2. 接收 Android 客户端连接
3. 解析跨平台协议包
4. 把连接状态和数据转交给 `ConnectionManager`

然后沿用现有结构：

1. `ConnectionManager`
   - 更新设备在线状态
   - 统一管理 Android / iOS / Pulse 来源

2. `PulseStoreInjector`
   - 把 `message` 写成现有消息记录
   - 把 `networkCompleted` 适配成现有 request 记录

这样 UI 层可以完全复用，不需要为 Android 重新写一套 console 或 inspector。

## 10. 推荐的代码分层

如果后面真的开始做，建议从当前“自定义模式 package”继续往下拆成 3 层：

### 10.1 `LogViewerProtocol`

只负责：

- packet type
- payload model
- encoder / decoder

要求：

- 完全跨平台
- 不依赖 Apple SDK
- Android / iOS / macOS 都能实现

### 10.2 `LogViewerAppleTransport`

只负责：

- iOS / macOS 的 MultipeerConnectivity 方案

这层保留当前 Apple-only 的优势，适合继续服务 iOS -> macOS 的轻量链路。

### 10.3 `LogViewerAndroid`

只负责：

- `NsdManager` 发现 `logViewer`
- TCP / WebSocket 连接
- Android 日志桥接
- OkHttp 拦截与上报

这样以后不同平台的边界会很清晰，不会把 Android 特殊逻辑硬塞进当前的 Apple package。

## 11. MVP 路线

最务实的第一阶段建议如下：

1. macOS 新增 `_logviewer._tcp` 服务端
2. Android SDK 实现 `NsdManager` 发现
3. Android 建立 TCP 长连接
4. Android 先发送 `hello`
5. Android 发送普通日志 `message`
6. Android 发送请求完成态 `networkCompleted`
7. macOS 把这两类事件适配进现有 Pulse store

这样你最先获得的价值就是：

- Android 设备能被 `logViewer` 自动发现
- Android 日志能统一查看
- Android 网络请求能进入 Inspector
- 复制到 Bruno / cURL / Send Again 这些工作流仍然可用

## 12. 为什么这是最稳的路线

这条路线的好处有 4 个：

1. **不破坏现有 iOS 自定义模式**
   - iOS 继续走 `MultipeerConnectivity`
   - 不需要为了 Android 先重写现有链路

2. **不绑死 Chucker**
   - Android 以后就算不用 Chucker，也仍然能上报到 `logViewer`

3. **UI 层复用最大**
   - Network 列表和 Inspector 可以继续用现有能力

4. **协议演进空间大**
   - 后续要补 request body、metrics、error、timeline 都有空间

## 13. 一句话结论

如果要支持 Android，推荐方案是：

- **Chucker 负责本地抓包**
- **Android SDK 负责发现 logViewer 并远程发送日志/网络**
- **macOS 新增 Android 接收服务端**
- **协议改成跨平台格式，不再依赖 Apple-only 的 binary PropertyList**

## 14. 相关文档

- 自定义模式：`docs/custom-mode.md`
- Pulse 模式：`docs/pulse-mode.md`
- 模式对比：`docs/modes-comparison.md`
- 当前 Apple 自定义 package：`Packages/LogViewerCustomMode`
