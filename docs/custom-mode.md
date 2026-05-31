# 自定义模式说明

本文档说明本项目里区别于 Pulse RemoteLogger 的另一条采集链路：**自定义模式**。  
它的目标是让 iOS 端在**不接入 Pulse SDK** 的前提下，仍然可以把日志和网络摘要实时发到 macOS 版 `logViewer`。

## 1. 自定义模式是什么

自定义模式现在已经被单独抽成一个本地 Swift Package，通过 **MultipeerConnectivity** 在局域网内把数据从 iOS 发送到 macOS。

- Swift Package：`Packages/LogViewerCustomMode`
- iOS 端发送器：`Packages/LogViewerCustomMode/Sources/LogViewerCustomMode/IOSLogSender.swift`
- macOS 端接收器：`Packages/LogViewerCustomMode/Sources/LogViewerCustomMode/MacLogReceiver.swift`
- 协议定义：`Packages/LogViewerCustomMode/Sources/LogViewerCustomMode/LogPacketProtocol.swift`
- 编解码：`Packages/LogViewerCustomMode/Sources/LogViewerCustomMode/LogPacketCodec.swift`
- 统一写入 Pulse store：`logViewer/Adapters/PulseStoreInjector.swift`

运行时入口在 `ConnectionManager.swift`：

- `MacLogReceiver` 负责接收自定义包
- `PulseRemoteLoggerServer` 负责接收 Pulse 模式事件
- 两条链路最后都写进同一个 `PulseStoreInjector`

所以从 UI 看，**两种模式最终都会进入同一套日志/网络列表和 Inspector**；区别只在于数据是怎么采集和传输过来的。

## 2. 自定义模式的数据流

### 2.1 发送端（iOS）

`IOSLogSender` 会：

1. 创建 `MCSession`
2. 通过 `MCNearbyServiceAdvertiser` 在局域网广播自己
3. 自动接受来自 Mac 的连接邀请
4. 把业务日志或网络摘要编码成 `LogPacket`
5. 用 `session.send(..., with: .reliable)` 发送给已连接的 Mac

当前暴露了两个发送入口：

- `sendLogMessage(...)`
- `sendNetworkSummary(...)`

这意味着自定义模式当前只覆盖两类数据：

- 普通消息日志
- 网络请求摘要

### 2.2 接收端（macOS）

`MacLogReceiver` 会：

1. 通过 `MCNearbyServiceBrowser` 自动发现附近 sender
2. 只邀请 `discoveryInfo["role"] == "sender"` 的设备
3. 在 `didReceive data` 时把原始包封装成 `LogViewerReceivedPacket`
4. 把数据交给 `ConnectionManager.handleReceivedPacket`

`ConnectionManager` 会同时做两件事：

- 更新设备在线状态、连接历史、传输速率
- 调用 `pulseInjector.injectReceivedPacket(packet)` 解析并落库

## 3. 自定义协议结构

### 3.1 外层包结构 `LogPacket`

定义在 package 内的 `LogPacketProtocol.swift`。

```swift
struct LogPacket {
    let version: String
    let timestamp: TimeInterval
    let packetType: Int
    let payload: Data
}
```

编码键是压缩过的短字段：

- `v`：协议版本
- `ts`：时间戳
- `pt`：包类型
- `pl`：负载

当前协议版本：

- `LogPacket.currentVersion == "1.0"`

当前包类型：

- `message = 1`
- `networkSummary = 2`

### 3.2 消息日志负载 `LogMessagePayload`

字段如下：

- `message`
- `level`
- `category`

其中 `level` 目前支持：

- `debug`
- `info`
- `error`

### 3.3 网络摘要负载 `LogNetworkPayload`

字段如下：

- `url`
- `method`
- `requestHeaders`
- `responseHeaders`
- `statusCode`
- `responseBody`

这条模型有一个很重要的特点：  
**它传的是“网络摘要”，不是完整 URLSession 生命周期事件。**

目前自定义模式里没有传：

- request body
- metrics / timing 明细
- upload / download 进度
- redirect 链
- task 创建 / 进行中 / 完成 三段状态
- 更完整的错误结构

因此自定义模式更像“轻量级网络镜像”，而不是 Pulse 那种完整网络观测。

## 4. 编解码方式

定义在 package 内的 `LogPacketCodec.swift`。

- 外层 envelope 使用 **binary PropertyList**
- 内层 payload 也使用 **binary PropertyList**

这样做的目的在代码里已经写得很明确：

- 包体更紧凑
- 能原样保留嵌套 `Data`
- 避免 JSON/Base64 带来的膨胀

接收端解析流程：

1. 先解出外层 `LogPacket`
2. 校验 `version`
3. 根据 `packetType` 选择 payload 类型
4. 产出 `DecodedLogPacket.message` 或 `DecodedLogPacket.network`

如果版本不匹配或类型不支持，会走 `injectTransportFailure(...)`，以错误消息的形式写进 store。

## 5. 自定义模式如何落到 UI

核心在 `PulseStoreInjector.swift`。

### 5.1 消息日志

收到 `LogMessagePayload` 后，会调用：

```swift
store.storeMessage(...)
```

并写入：

- 时间戳：来自包内 `timestamp`
- label：`category + peerDisplayName`
- level：从自定义 `LogMessageLevel` 映射到 Pulse 的 level
- file / function：固定写成远程来源标识

### 5.2 网络摘要

收到 `LogNetworkPayload` 后，会：

1. 把 `payload.url` 转成 `URL`
2. 用 `method + requestHeaders` 组装一个 `URLRequest`
3. 用 `statusCode + responseHeaders` 组装一个 `HTTPURLResponse`
4. 把 `responseBody` 作为响应数据写入
5. 调用 `store.storeRequest(...)`

也就是说，自定义模式虽然不是 Pulse 原生事件，但在 macOS 端会被**适配成 Pulse 的网络记录**，这样现有的：

- Network 列表
- Inspector
- Response 展示
- Copy cURL / Send Again / Copy URL 等操作

都可以复用，不需要为自定义模式单独写一套 UI。

## 6. 与 Pulse 模式的差异

| 维度 | 自定义模式 | Pulse 模式 |
|---|---|---|
| 传输层 | MultipeerConnectivity | `NWListener` + `_pulse._tcp` |
| 接入成本 | 低，只要调用 `IOSLogSender` | 需要客户端接入 Pulse RemoteLogger |
| 日志类型 | message / network summary | Pulse 的 message + 完整 network store event |
| 网络信息完整度 | 中等，偏摘要 | 高，接近原始网络事件 |
| request body | 当前不支持 | 支持 |
| response body | 支持 | 支持 |
| metrics / progress | 当前不支持 | 支持事件级信息 |
| 协议控制权 | 完全在本项目内 | 跟随 Pulse RemoteLogger 协议 |

可以这样理解：

- **Pulse 模式** 更完整，适合已经接入 Pulse 的 App
- **自定义模式** 更轻、更可控，适合先快速打通远程日志和网络抓取

## 7. 当前限制

基于当前代码，自定义模式有这些边界：

### 7.1 只有两种 packet type

当前协议仅支持：

- `message`
- `networkSummary`

如果后续想扩展：

- breadcrumb
- console log
- structured event
- request body
- response metadata
- performance metric

都需要新增 packet type 和对应 payload。

### 7.2 网络请求不是“完整重建”

当前 `LogNetworkPayload` 只带：

- URL
- method
- headers
- response body

因此在 macOS 端生成的网络记录，主要用于：

- 查看 URL / Header / Response
- 复制到 Bruno / cURL
- 在 Inspector 里快速排查

但它不能完全替代 Pulse 网络事件，因为缺少更细粒度的上下文。

### 7.3 传输仅使用 Data packet

`IOSLogSender` 和 `MacLogReceiver` 当前只用 `MCSession.send(data, ...)`。

没有使用：

- stream
- resource transfer

所以如果以后要传更大的 body、附件或二进制文件，可能需要考虑分片、压缩策略或改用其他传输方式。

## 8. 什么时候优先用自定义模式

以下场景更适合：

- 你的 iOS 端还没有接入 Pulse
- 你只想快速发消息日志和网络摘要
- 你希望协议完全由项目自己控制
- 你后续想按业务需要扩展包结构，而不是跟随第三方协议

## 9. 后续扩展建议

如果后面你要继续增强“自定义模式”，最值得优先补的是：

1. `requestBody`
2. `error` / failure payload
3. `metrics`（总耗时、DNS、TLS、upload、download）
4. 更明确的 `label` / `module` / `traceID`
5. 分片或压缩更大的响应体
6. 除 `networkSummary` 外再拆出 `networkCompleted` 等更细粒度类型

## 10. 相关代码索引

- 运行入口：`logViewer/Managers/ConnectionManager.swift`
- 自定义接收端：`logViewer/Networking/MacLogReceiver.swift`
- 自定义发送端：`logViewer/Networking/IOSLogSender.swift`
- 协议模型：`logViewer/Networking/LogPacketProtocol.swift`
- 编解码：`logViewer/Networking/LogPacketCodec.swift`
- Pulse 适配层：`logViewer/Adapters/PulseStoreInjector.swift`
- Pulse 协议服务端：`logViewer/Networking/PulseRemoteLoggerServer.swift`
- Pulse 协议定义：`logViewer/Networking/PulseRemoteLoggerProtocol.swift`
