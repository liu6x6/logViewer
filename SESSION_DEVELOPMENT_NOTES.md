# logViewer Session Development Notes

本文档总结了本次 session 中完成的设计、代码实现、关键决策、限制和后续建议，方便后续继续开发时快速恢复上下文。

## 1. 本次 session 的目标与结果

本次工作围绕 `logViewer` 的核心链路展开，已经完成以下四个阶段：

1. 搭建 macOS 端 SwiftUI 三栏式基础 UI，整体结构参考 Pulse Pro。
2. 建立 iPhone -> Mac 的 `MultipeerConnectivity` 自动发现与自动连接链路。
3. 设计并实现高频实时传输使用的紧凑数据包协议。
4. 将 Mac 端收到的数据注入 Pulse `LoggerStore`，并在中栏切换到 `PulseUI.ConsoleView(store:)`。

当前结果不是 demo 级拼接，而是已经形成一条可继续扩展的主干架构：

`iPhone Sender -> LogPacket 编码 -> MultipeerConnectivity -> Mac Receiver -> 解包 -> PulseStoreInjector -> Pulse LoggerStore -> PulseUI.ConsoleView`

---

## 2. 当前工程结构与关键文件

### App 与 UI

- `logViewer/logViewer/logViewerApp.swift`
- `logViewer/logViewer/ContentView.swift`
- `logViewer/logViewer/Views/Sidebar/DeviceSidebarView.swift`
- `logViewer/logViewer/Views/Logs/LogPanelView.swift`
- `logViewer/logViewer/Views/Logs/PulseConsoleHostView.swift`
- `logViewer/logViewer/Views/Detail/LogDetailView.swift`

### 状态与模型

- `logViewer/logViewer/Managers/ConnectionManager.swift`
- `logViewer/logViewer/Models/DeviceModel.swift`
- `logViewer/logViewer/Models/LogEntry.swift`

### 通信与协议

- `logViewer/logViewer/Networking/LogViewerMultipeerConfiguration.swift`
- `logViewer/logViewer/Networking/MacLogReceiver.swift`
- `logViewer/logViewer/Networking/IOSLogSender.swift`
- `logViewer/logViewer/Networking/LogPacketProtocol.swift`
- `logViewer/logViewer/Networking/LogPacketCodec.swift`

### Pulse 适配层

- `logViewer/logViewer/Adapters/PulseStoreInjector.swift`

---

## 3. 第一阶段：macOS 端基础 UI

### 3.1 目标

构建一个接近 Pulse Pro 风格的三栏式 macOS 原生界面，并为后续实时日志显示预留稳定骨架。

### 3.2 已实现内容

使用 `NavigationSplitView` 完成三栏布局：

- **左栏 Sidebar**
  - 展示设备列表
  - 设备名称
  - 连接状态（已连接 / 未连接）
  - 实时传输速率
  - 连接历史
  - 使用 `.ultraThinMaterial` 营造毛玻璃质感

- **中栏 Panel**
  - 初始版本是占位 `List`
  - 后续已替换为 Pulse Console 容器
  - 保留 `Messages / Network` 两个 Tab

- **右栏 Detail**
  - 仍保留自定义 inspector 占位结构
  - 使用 `Request / Response / Metrics` 三个 Tab
  - 当前用于显示最新包体预览与设备状态说明

### 3.3 关键状态对象

`DeviceModel` 负责表示设备状态：

- `id`
- `name`
- `status`
- `transferRateKBps`
- `connectionHistory`

`ConnectionManager` 负责：

- 发布设备列表
- 跟踪连接状态
- 跟踪最后一条收到的数据
- 在 macOS 上持有 `MacLogReceiver`
- 在 macOS 上持有 `PulseStoreInjector`

---

## 4. 第二阶段：MultipeerConnectivity 自动发现与连接

### 4.1 共同配置

统一服务类型：

```swift
LogViewerMultipeerConfiguration.serviceType = "logviewer-pipe"
```

Bonjour 服务名：

```swift
"_logviewer-pipe._tcp"
```

### 4.2 Mac 端接收器

文件：`Networking/MacLogReceiver.swift`

#### 能力

- 实现 `MCNearbyServiceBrowserDelegate`
- 实现 `MCSessionDelegate`
- 启动后自动 `startBrowsingForPeers()`
- 发现 discovery info 中标记为 sender 的 iPhone 后，自动 `invitePeer`
- 连接状态变化后同步到 `ConnectionManager`
- 收到 `Data` 后在后台线程打印
- 同时将 packet 回调给业务层继续注入 Pulse

#### 设计说明

Mac 端是主动方：

- 浏览局域网 sender
- 自动发起邀请
- 自动接收数据

这样 iPhone 端实现更简单，只需要负责广播和发送。

### 4.3 iOS 端发送器

文件：`Networking/IOSLogSender.swift`

#### 能力

- 实现 `MCNearbyServiceAdvertiserDelegate`
- App 启动时自动 `startAdvertisingPeer()`
- 自动接受来自 Mac 的连接邀请
- 对外暴露：

```swift
func sendPacket(data: Data) throws
func sendLogMessage(...)
func sendNetworkSummary(...)
```

#### 当前状态

当前工程主 target 是 macOS，iOS 发送器已用条件编译写好。  
后续新增 iOS target 时，只需把 `Networking` 下对应文件加入 iOS target，并在 iOS App 入口初始化 `IOSLogSender()` 即可。

---

## 5. 第三阶段：实时传输协议设计

### 5.1 设计目标

因为要高频发送日志和网络摘要，所以协议需要：

- 比 JSON 更紧凑
- 避免 `Data` 做 base64 膨胀
- 保持 Swift 侧实现简单
- 能明确区分不同 packet 类型

### 5.2 最终方案

使用：

- `Codable`
- `PropertyListEncoder`
- `PropertyListDecoder`
- `binary` 输出格式

而不是 JSON。

### 5.3 外壳协议 `LogPacket`

文件：`Networking/LogPacketProtocol.swift`

```swift
struct LogPacket {
    let version: String
    let timestamp: TimeInterval
    let packetType: Int
    let payload: Data
}
```

#### `packetType`

- `1` = 普通日志
- `2` = 网络请求摘要

### 5.4 普通日志 Payload

```swift
struct LogMessagePayload {
    let message: String
    let level: LogMessageLevel
    let category: String
}
```

### 5.5 网络摘要 Payload

```swift
struct LogNetworkPayload {
    let url: String
    let method: String
    let requestHeaders: [String: String]
    let responseHeaders: [String: String]
    let statusCode: Int
    let responseBody: Data
}
```

### 5.6 编解码器

文件：`Networking/LogPacketCodec.swift`

已实现：

- `LogPacketEncoder`
- `LogPacketDecoder`

支持：

- 编码普通日志
- 编码网络摘要
- 先解 envelope 再解 payload
- 自动根据 `packetType` 返回强类型枚举 `DecodedLogPacket`

### 5.7 性能考虑

为减小包体，`CodingKeys` 采用短 key：

- 外壳：`v / ts / pt / pl`
- 普通日志：`m / l / c`
- 网络摘要：`u / m / qh / sh / sc / rb`

这样可以尽量降低高频发送时的字节开销。

---

## 6. 第四阶段：Pulse / PulseUI 注入

### 6.1 目标

不自己重写一套日志浏览器，而是直接使用：

```swift
PulseUI.ConsoleView(store: store)
```

来渲染日志和网络请求。

### 6.2 当前实现

文件：`Adapters/PulseStoreInjector.swift`

#### `PulseStoreInjector` 的职责

- 初始化独立的 `LoggerStore`
- 接收解码后的远端 packet
- 将普通日志写入 Pulse store
- 将网络摘要写入 Pulse store
- 供 SwiftUI 中栏直接读取

### 6.3 LoggerStore 初始化

当前支持两种模式：

- `temporarySandbox`
- `inMemory`

默认使用：

```swift
LoggerStore(storeURL: temporaryURL, options: [.create, .synchronous])
```

这样有两个好处：

1. 生命周期只属于当前运行会话
2. PulseUI 可以直接读取到完整结构化数据

### 6.4 普通日志注入

采用 Pulse 公开 API：

```swift
store.storeMessage(
    createdAt: Date(timeIntervalSince1970: envelope.timestamp),
    label: "...",
    level: ...,
    message: payload.message,
    metadata: nil,
    file: "RemoteLogPacket",
    function: "MultipeerConnectivity",
    line: 0
)
```

#### 结论

普通日志可以走**完全官方支持路径**，并且能保留远端时间戳。

### 6.5 网络请求注入

采用 Pulse 公开 API：

```swift
store.storeRequest(
    request,
    response: response,
    error: nil,
    data: payload.responseBody,
    metrics: nil,
    label: peerDisplayName,
    taskDescription: ...
)
```

其中会构造：

- `URLRequest`
- `HTTPURLResponse`
- `responseBody`

#### 为什么这样可行

Pulse 会根据这些公开对象在内部构建：

- `NetworkTaskEntity`
- `NetworkRequestEntity`
- `NetworkResponseEntity`
- body blob 存储

只要 `responseHeaders` 中带有正确的 `Content-Type`，PulseUI 网络详情视图就能解析：

- Response Headers
- 状态码
- Response Body 文本 / JSON

### 6.6 当前 UI 接入方式

文件：`Views/Logs/PulseConsoleHostView.swift`

中栏已改为：

```swift
ConsoleView(store: injector.store, mode: ...)
```

根据 Tab 切换：

- `.logs`
- `.network`

### 6.7 为什么没有直接写 Pulse Core Data

虽然理论上可以通过 `NSManagedObjectContext` 直接写 Pulse 的底层数据库，但不建议这么做。

原因：

- Pulse 内部 schema 不是稳定 public API
- 除了表结构外，还有 blob、header 编码、元数据预处理等内部逻辑
- 版本升级后容易失效

### 6.8 更强的方案：Fork Pulse 暴露事件注入

如果后续要求：

- 完整保留远端真实时间线
- 写入更精确的 request/response 时间
- 写入 metrics / redirect / transaction metrics

推荐方案是：

1. fork `Pulse`
2. 将内部 `handleExternalEvent` 包装成 public 方法
3. 从业务层直接构造 `LoggerStore.Event.NetworkTaskCompleted`

这比直接写 Core Data 稳定得多，也更接近 Pulse 自身的数据流。

---

## 7. 当前数据流

当前 macOS 侧真实数据流如下：

1. iPhone 将普通日志或网络摘要编码成 `LogPacket`
2. `IOSLogSender` 使用 `sendPacket(data:)` 发送
3. `MacLogReceiver` 收到原始 `Data`
4. `ConnectionManager` 更新设备状态与速率
5. `PulseStoreInjector` 解包并注入 Pulse store
6. `PulseUI.ConsoleView(store:)` 自动展示结果

右侧 detail 目前仍是辅助 inspector，不负责主日志展示。

---

## 8. Info.plist 与网络权限要求

本次 session 中已明确要求手动配置 `Info.plist`，防止 Bonjour / 本地网络权限被系统静默拦截。

### iOS / macOS 共用配置

```xml
<key>NSBonjourServices</key>
<array>
    <string>_logviewer-pipe._tcp</string>
</array>
<key>NSLocalNetworkUsageDescription</key>
<string>用于在同一 Wi‑Fi 下自动发现并连接 logViewer 设备，实时传输日志。</string>
```

### 注意点

- `NSBonjourServices` 必须写 `"_logviewer-pipe._tcp"`
- 不能只写 `"logviewer-pipe"`

### macOS 额外注意

如果启用了 App Sandbox，还需要保证：

- Incoming Connections (Server)
- Outgoing Connections (Client)

---

## 9. 当前可用能力

当前代码主干已经具备以下能力：

- Mac 端自动发现局域网 iPhone sender
- Mac 端自动发起连接邀请
- iPhone 端自动接受连接
- 发送普通日志 packet
- 发送网络摘要 packet
- Mac 端解码 packet
- Mac 端把解码后的数据写入 Pulse `LoggerStore`
- 中栏通过 PulseUI 展示 Logs / Network

---

## 10. 当前限制

### 10.1 iOS target 尚未正式接入

虽然 `IOSLogSender` 已实现，但当前主工程仍以 macOS target 为主。  
后续需要新增或接通 iOS target，并把发送器真正放到 iPhone App 生命周期里。

### 10.2 网络摘要还不是完整 URLSession metrics 级别

当前网络 packet 只传：

- URL
- Method
- Request Headers
- Response Headers
- StatusCode
- Response Body

还没有传：

- DNS / TLS / redirect 明细
- request body
- task interval
- per-transaction metrics

如果未来需要更接近 Pulse 原生网络面板，就要扩展协议，或采用 fork Pulse 的 external event 路线。

### 10.3 `storeRequest(...)` 的时间不是完全远端原始时间

普通日志可精确写入远端 `createdAt`。  
网络请求若走 `storeRequest(...)`，更接近“注入时刻”。  
若要完整保留远端网络时间线，推荐 fork Pulse。

---

## 11. 推荐的下一步开发顺序

### 第一优先级

把 iOS target 真正接起来，并在 iPhone 侧把真实日志源接入：

- 普通业务日志 -> `sendLogMessage(...)`
- 网络拦截结果 -> `sendNetworkSummary(...)`

### 第二优先级

在 iOS 侧增加真实日志捕获层，例如：

- 自定义 logger sink
- URLSession / Alamofire / Moya 拦截器

### 第三优先级

扩展网络协议，补齐：

- request body
- duration
- cache hit
- failure reason
- metrics

### 第四优先级

如果你需要与 Pulse 原生网络事务完全一致：

- fork Pulse
- 暴露 external event 注入入口
- 直接写 `LoggerStore.Event.NetworkTaskCompleted`

---

## 12. 本次 session 的关键决策总结

### 决策 1：UI 不自己造轮子，直接对接 PulseUI

原因：

- 节省大量列表、筛选、详情页、网络 body 展示的重复工作
- 直接复用成熟的 Pulse 数据模型和 UI

### 决策 2：局域网通信使用 MultipeerConnectivity

原因：

- 同一 Wi‑Fi 下零配置发现
- 不需要手动输入 IP
- Apple 平台原生能力，接入成本低

### 决策 3：传输协议使用 binary plist，而不是 JSON

原因：

- 更紧凑
- 对 `Data` 更友好
- 减少 Response Body 体积膨胀

### 决策 4：网络注入优先走 Pulse 公共 API

原因：

- 维护成本低
- 升级兼容性更好
- 不依赖 Pulse 内部 Core Data schema

### 决策 5：如需更强精度，走 fork Pulse，而不是直接黑写数据库

原因：

- 官方内部事件流更稳定
- 数据结构更完整
- 风险低于直接操作底层实体

---

## 13. 当前你需要知道的最重要结论

如果现在继续往下做，最短路径是：

1. 新增或接通 iOS target
2. 在 iPhone 端初始化 `IOSLogSender`
3. 把真实日志和网络请求转成 `LogMessagePayload` / `LogNetworkPayload`
4. 发给 Mac
5. Mac 端已经能通过 Pulse Console 直接看到结果

如果你要的是**尽快可用**，现有架构已经足够继续做。  
如果你要的是**接近 Pulse 原生抓包精度**，下一步重点应放在扩展协议和 fork Pulse 的 external event 注入。
