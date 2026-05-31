# Pulse 模式说明

本文档说明本项目对 **Pulse RemoteLogger** 的接收、解析、适配和展示方式。  
相对于自定义模式，Pulse 模式的重点不是“自定义协议可控”，而是**尽可能保留 Pulse 原生的日志与网络事件能力**。

## 1. Pulse 模式是什么

Pulse 模式允许已经接入 **Pulse / RemoteLogger** 的客户端，把远程日志和网络事件直接发送给 macOS 版 `logViewer`。

项目内相关代码：

- 协议定义：`logViewer/Networking/PulseRemoteLoggerProtocol.swift`
- 服务端：`logViewer/Networking/PulseRemoteLoggerServer.swift`
- 统一落库：`logViewer/Adapters/PulseStoreInjector.swift`
- 运行时绑定：`logViewer/Managers/ConnectionManager.swift`

从架构上看，Pulse 模式是本项目的第二条采集入口：

- 自定义模式：`MacLogReceiver` 接收 `LogPacket`
- Pulse 模式：`PulseRemoteLoggerServer` 接收 RemoteLogger wire packet

两条链路最终都进入 `PulseStoreInjector`，所以 UI 层仍然复用同一套：

- Messages 列表
- Network 列表
- Inspector
- Response 渲染
- Copy / Send Again / Blacklist 等交互

## 2. Pulse 模式的数据流

### 2.1 服务端启动

`PulseRemoteLoggerServer` 在初始化时就会启动 `NWListener`：

- 传输层：TCP
- Bonjour service：`_pulse._tcp`
- 默认 service name：优先取 app 名，否则取当前主机名

这意味着 macOS 端会在局域网内暴露一个标准的 Pulse RemoteLogger 服务，供客户端自动发现或连接。

### 2.2 客户端连接

每个入站连接都会被包装成 `PulseRemoteLoggerClientConnection`，内部负责：

1. 启动 `NWConnection`
2. 持续 `receive`
3. 累积 buffer
4. 从 buffer 中按协议拆包
5. 识别握手、ping、store event 等消息

握手完成后，会提取客户端身份信息：

- `deviceId`
- `deviceInfo.name`
- `appInfo.name`
- `appInfo.bundleIdentifier`

并组装成 `PulseRemoteLoggerClientIdentity`。

稳定设备 ID 规则：

- 如果有 bundle identifier：`deviceID|bundleIdentifier`
- 否则仅用 `deviceID`

### 2.3 事件进入运行时

`ConnectionManager.bindRemoteLoggerServer()` 会监听两类回调：

- `onPeerStateChange`
- `onEventReceived`

收到 peer 状态变化后：

- 更新设备在线状态
- 记录连接历史
- 刷新 sidebar 中的设备列表和传输速率

收到事件后：

- 更新 `latestReceivedPayload`
- 更新传输速率
- 调用 `pulseInjector.injectRemoteLoggerEvent(...)`

## 3. Pulse RemoteLogger 协议结构

定义在 `PulseRemoteLoggerProtocol.swift`。

### 3.1 外层 wire packet

每个包的外层格式是：

1. `code: UInt8`
2. `contentSize: UInt32`
3. `compressedBody: Data`

其中：

- `contentSize` 为压缩后 body 的长度
- body 使用 **LZFSE** 压缩
- 长度字段是 **big-endian**

接收时先读取 5 字节头，再按长度继续取 body，最后解压。

### 3.2 packet code

当前项目内识别的 code 包括：

- `clientHello = 0`
- `serverHello = 1`
- `pause = 2`
- `resume = 3`
- `ping = 6`
- `storeEventMessageStored = 7`
- `storeEventNetworkTaskCreated = 8`
- `storeEventNetworkTaskProgressUpdated = 9`
- `storeEventNetworkTaskCompleted = 10`
- `message = 13`

对 `logViewer` 来说，真正重要的是：

- `clientHello`
- `storeEventMessageStored`
- `storeEventNetworkTaskCreated`
- `storeEventNetworkTaskProgressUpdated`
- `storeEventNetworkTaskCompleted`

### 3.3 上层 message envelope

除简单 packet 外，Pulse 还定义了一层 `PulseRemoteLoggerMessage`：

- `id`
- `options`
- `pathSize`
- `dataSize`
- `path`
- `data`

其中 `path` 是 JSON 编码的 `PulseRemoteLoggerPath`，当前声明了：

- `updateMocks`
- `getMockedResponse(mockID:)`
- `openMessageDetails`
- `openTaskDetails`

当前 `logViewer` 主要关注 store event 接收，不涉及 mock 管理 UI。

## 4. Pulse 模式下支持的事件

`PulseRemoteLoggerStoreEvent` 在本项目里映射成四类：

- `message(LoggerStore.Event.MessageCreated)`
- `networkTaskCreated(LoggerStore.Event.NetworkTaskCreated)`
- `networkTaskProgressUpdated(LoggerStore.Event.NetworkTaskProgressUpdated)`
- `networkTaskCompleted(LoggerStore.Event.NetworkTaskCompleted)`

但在当前 `PulseStoreInjector` 里，真正落库的是：

- `message`
- `networkTaskCompleted`

而以下两类暂时只会参与运行时接收，不会单独持久化成可见记录：

- `networkTaskCreated`
- `networkTaskProgressUpdated`

也就是说，Pulse 模式目前对 UI 的主要价值仍然是：

- 完整日志消息
- 完整完成态网络请求

## 5. Pulse 模式如何落到 UI

核心仍然是 `PulseStoreInjector.injectRemoteLoggerEvent(...)`。

### 5.1 Message 事件

`LoggerStore.Event.MessageCreated` 会被写入：

```swift
store.storeMessage(...)
```

保留的信息包括：

- `createdAt`
- `label`
- `level`
- `message`
- `metadata`
- `file`
- `function`
- `line`

这里比自定义模式保留的信息更多，因为它直接复用了 Pulse 的原始 message 事件。

### 5.2 NetworkTaskCompleted 事件

`LoggerStore.Event.NetworkTaskCompleted` 会被适配成：

- `URLRequest`
- `HTTPURLResponse`
- `NSError?`
- `requestBody`
- `responseBody`

然后调用：

```swift
store.storeRequest(...)
```

保留下来的关键信息比自定义模式更完整：

- `originalRequest`
- `currentRequest`
- request headers
- request body
- response headers
- response body
- response error
- response status
- request network options
- 原始 task description

最终 UI 中看到的 network entry，本质上是一个“基于 Pulse 完成态事件重建出的 Pulse store 记录”。

## 6. 为什么 Pulse 模式更完整

和自定义模式相比，Pulse 模式有两个核心优势。

### 6.1 网络事件来自 Pulse 原生模型

自定义模式的网络负载是项目自己定义的 `LogNetworkPayload`，字段是“摘要型”的。  
Pulse 模式直接消费 `LoggerStore.Event.NetworkTaskCompleted`，所以能带来：

- request body
- current request
- richer error
- 更多 request option
- 更完整的 task 描述

### 6.2 日志消息保留更多上下文

自定义模式里的 message 只有：

- message
- level
- category

Pulse 模式里的 message 还保留：

- metadata
- file
- function
- line

因此在 Inspector 或后续导出能力上，Pulse 模式会更有信息密度。

## 7. 当前实现边界

基于当前代码，Pulse 模式也有几个值得明确的边界。

### 7.1 只持久化“完成态”网络事件

虽然协议层支持：

- `networkTaskCreated`
- `networkTaskProgressUpdated`
- `networkTaskCompleted`

但当前 UI 只真正写入了：

- `networkTaskCompleted`

这意味着目前不会在界面上看到“进行中请求”的细粒度进度视图。

### 7.2 metrics 没有继续往下传

虽然 `NetworkTaskCompleted` 自身带 `metrics`，但当前调用 `store.storeRequest(...)` 时传的是：

```swift
metrics: nil
```

所以后续如果你想把耗时拆得更细，例如：

- DNS
- TCP connect
- TLS
- request transfer
- response transfer

还需要继续扩展适配层。

### 7.3 依赖客户端已接入 Pulse

Pulse 模式的前提是客户端侧已经使用了 Pulse / RemoteLogger 对应能力。  
对于未接入 Pulse 的项目，自定义模式仍然是更轻量的接入方式。

## 8. 什么时候优先用 Pulse 模式

以下场景更适合：

- 客户端本身已经接入 Pulse
- 你希望保留更多 message metadata
- 你需要 request body / richer response error
- 你后续想做更完整的网络分析能力
- 你不想自己维护一套网络采集协议

## 9. 后续扩展建议

如果后续要继续增强 Pulse 模式，最值得优先补的是：

1. 把 `networkTaskProgressUpdated` 也映射到 UI
2. 把 `metrics` 继续往下适配到可视化层
3. 区分 `originalRequest` 与 `currentRequest` 的展示
4. 在 Inspector 中显式展示 Pulse metadata / file / function / line
5. 在列表里对 Pulse 来源做更明显标记

## 10. 相关代码索引

- Pulse 服务端：`logViewer/Networking/PulseRemoteLoggerServer.swift`
- Pulse 协议：`logViewer/Networking/PulseRemoteLoggerProtocol.swift`
- 运行时绑定：`logViewer/Managers/ConnectionManager.swift`
- Pulse 适配层：`logViewer/Adapters/PulseStoreInjector.swift`
- UI 展示：`logViewer/Views/Logs/PulseConsoleFormatting.swift`
- Inspector：`logViewer/Views/Detail/LogDetailView.swift`
