# logViewer 架构文档

> 本文档面向 AI 辅助开发，提供完整的项目结构、模块职责、数据流、协议规范和扩展指引。

---

## 1. 项目定位

`logViewer` 是一个 **macOS 原生日志与网络请求查看器**，面向本地调试场景。它接收来自 iOS / Android 设备的实时日志和网络请求数据，注入 [Pulse](https://github.com/kean/Pulse) 的 `LoggerStore`，并以类 Pulse Pro 的三栏式 UI 呈现。

**核心价值**：让开发者在 Mac 上实时查看手机端的 `print` 日志和 HTTP 请求/响应详情，无需 USB 连接 Xcode。

---

## 2. 技术栈

| 层面 | 技术 |
|---|---|
| 平台 | macOS 14+（主工程），iOS 15+（SDK Package） |
| UI | SwiftUI · NavigationSplitView 三栏布局 |
| 日志存储与展示 | Pulse（LoggerStore + PulseUI）· CoreData |
| iOS 通信 | MultipeerConnectivity（Wi-Fi 局域网自动发现） |
| Android 通信 | Network.framework（NWListener / NWBrowser）+ Bonjour/mDNS + TCP + JSON |
| Pulse 兼容通信 | Network.framework + Bonjour（`_pulse._tcp`）+ 自定义二进制协议 + LZFSE 压缩 |
| 数据编码 | Binary PropertyList（iOS Custom Mode）· JSON（Android）· 自定义二进制帧（Pulse Remote） |
| 语言 | Swift 6（strict concurrency） |
| 构建 | Xcode 16 · Swift Package Manager（本地 Package） |

---

## 3. 工程结构

```
logViewer/
├── logViewer.xcodeproj              # Xcode 工程
├── logViewer/                        # macOS 主工程源码
│   ├── logViewerApp.swift            # App 入口，创建 ConnectionManager + ActionCoordinator
│   ├── ContentView.swift             # 三栏 NavigationSplitView 骨架
│   │
│   ├── Models/                       # 数据模型
│   │   ├── DeviceModel.swift         # 设备模型（平台、状态、速率、连接历史）
│   │   ├── LogEntry.swift            # 日志条目模型（目前仅含 samples 静态数据）
│   │   └── NetworkRequestBlocklist.swift  # 网络请求黑名单（host/URL 级别过滤 + UserDefaults 持久化）
│   │
│   ├── Managers/                     # 核心管理器
│   │   ├── ConnectionManager.swift   # 中枢：绑定所有通信服务器，维护设备列表，路由数据到 PulseStoreInjector
│   │   └── NetworkRequestActionCoordinator.swift  # 请求操作协调器：Copy/Send Again + 全局 Commands 菜单
│   │
│   ├── Networking/                   # 通信层（全部 macOS only）
│   │   ├── PulseRemoteLoggerProtocol.swift   # Pulse RemoteLogger 二进制协议定义（帧格式 + LZFSE 压缩）
│   │   ├── PulseRemoteLoggerServer.swift     # Pulse RemoteLogger TCP 服务端（NWListener + Bonjour）
│   │   ├── AndroidRemoteLoggerProtocol.swift # Android JSON 协议定义（Envelope + 事件类型）
│   │   ├── AndroidRemoteLoggerServer.swift   # Android TCP 服务端 + Browser（双向自动发现）
│   │   └── NetworkResponseBodyNormalizer.swift  # 响应体去重/规范化（处理重复 JSON 等异常数据）
│   │
│   ├── Adapters/                     # Pulse 适配层
│   │   └── PulseStoreInjector.swift  # 核心：将三种来源的数据统一转换为 Pulse LoggerStore 记录
│   │
│   └── Views/                        # UI 视图层
│       ├── Sidebar/
│       │   └── DeviceSidebarView.swift       # 左栏：设备列表（平台图标、状态、速率、历史）
│       ├── Logs/
│       │   ├── PulseConsoleHostView.swift    # 占位（实际实现在 PulseConsoleFormatting.swift）
│       │   ├── PulseConsoleFormatting.swift  # 中栏：Messages 列表 + Network 列表（含工具栏/筛选/分组）
│       │   ├── PulseConsoleEntityFormatting.swift  # NetworkTaskEntity / LoggerMessageEntity 的展示扩展
│       │   ├── PulseConsoleSelection.swift   # 选中状态枚举（message / network）
│       │   ├── PulseNetworkConsoleSupport.swift  # Network 查询控制器 + 筛选/排序/分组模型
│       │   └── NetworkBlacklistSheet.swift   # 黑名单管理弹窗
│       └── Detail/
│           ├── LogDetailView.swift           # 右栏：Inspector（Request/Response/Metrics 三 Tab）
│           └── NetworkResponsePresentation.swift  # 响应体展示（JSON 高亮/图片预览/HTML→Safari/导出）
│
├── Packages/
│   └── LogViewerCustomMode/          # iOS SDK Swift Package（供 iOS App 集成）
│       ├── Package.swift
│       └── Sources/LogViewerCustomMode/
│           ├── LogViewerMultipeerConfiguration.swift  # MultipeerConnectivity 配置（serviceType、角色、发现信息）
│           ├── LogPacketProtocol.swift     # 数据包协议定义（LogPacket 信封 + Message/Network 载荷）
│           ├── LogPacketCodec.swift        # 编解码器（Binary PropertyList）
│           ├── IOSLogSender.swift          # iOS 端：广播 + 发送日志/网络摘要（#if os(iOS)）
│           └── MacLogReceiver.swift        # macOS 端：浏览 + 自动邀请 iPhone（#if os(macOS)）
│
├── docs/                             # 文档
│   ├── architecture.md               # 本文件
│   ├── android-support.md
│   ├── custom-mode.md
│   ├── pulse-mode.md
│   └── modes-comparison.md
│
├── 快捷方式.md                        # Request 复制 / Send Again / 快捷键设计文档
├── SESSION_DEVELOPMENT_NOTES.md       # 开发过程记录
└── .github/
    └── copilot-instructions.md
```

---

## 4. 三种数据接入模式

### 4.1 iOS Custom Mode（MultipeerConnectivity）

```
iOS App
  └─ IOSLogSender（MCNearbyServiceAdvertiser 广播）
       │  编码: LogPacketEncoder → Binary PropertyList
       ▼
macOS
  └─ MacLogReceiver（MCNearbyServiceBrowser 自动发现 + 邀请）
       │  回调: onPeerStateChange / onPacketReceived
       ▼
  ConnectionManager.handleReceivedPacket()
       ▼
  PulseStoreInjector.injectReceivedPacket()
       │  LogPacketDecoder 解码 → 区分 message / networkSummary
       ▼
  Pulse LoggerStore.storeMessage() / storeRequest()
```

**协议格式**：
- 信封 `LogPacket`：`{v, ts, pt, pl}` — Binary PropertyList
- 载荷 `LogMessagePayload`：`{m, l, c}` — message / level / category
- 载荷 `LogNetworkPayload`：`{u, m, qh, sh, sc, rb}` — url / method / requestHeaders / responseHeaders / statusCode / responseBody
- 使用短 key 减少传输体积

**服务发现**：
- serviceType: `logviewer-pipe`
- discoveryInfo: `{role: "sender"/"receiver", platform: "ios"/"macos"}`
- Mac 只邀请 role=sender 的 peer

### 4.2 Pulse RemoteLogger Mode（二进制协议）

```
iOS App（集成 Pulse SDK）
  └─ Pulse RemoteLogger（_pulse._tcp Bonjour）
       │  编码: 自定义二进制帧 + LZFSE 压缩
       ▼
macOS
  └─ PulseRemoteLoggerServer（NWListener + Bonjour _pulse._tcp）
       │  每连接: PulseRemoteLoggerClientConnection
       │  帧格式: [code:1B][contentSize:4B BE][compressedBody]
       ▼
  ConnectionManager.handleRemoteLoggerEvent()
       ▼
  PulseStoreInjector.injectRemoteLoggerEvent()
       │  区分: message / networkTaskCreated / networkTaskProgressUpdated / networkTaskCompleted
       ▼
  Pulse LoggerStore
```

**二进制帧格式**：
```
┌──────────┬──────────────────┬─────────────────────────┐
│ code (1B)│ contentSize (4B) │ LZFSE compressed body   │
│  UInt8   │  UInt32 BE       │  (decompressed → JSON)  │
└──────────┴──────────────────┴─────────────────────────┘
```

**Packet Codes**：

| Code | 名称 | 方向 |
|---|---|---|
| 0 | clientHello | Client → Server |
| 1 | serverHello | Server → Client |
| 2 | pause | Server → Client |
| 3 | resume | Server → Client |
| 6 | ping | Server → Client（每 2s） |
| 7 | storeEventMessageStored | Client → Server |
| 8 | storeEventNetworkTaskCreated | Client → Server |
| 9 | storeEventNetworkTaskProgressUpdated | Client → Server |
| 10 | storeEventNetworkTaskCompleted | Client → Server |
| 13 | message（控制消息） | 双向 |

**握手流程**：ClientHello → ServerHello + Resume → Ping 循环（2s）

**NetworkTaskCompleted 载荷**（Manifest 格式）：
```
┌────────────────┬───────────────────┬────────────────────┬────────────────────┐
│ messageSize(4B)│ requestBodySize(4B)│ responseBodySize(4B)│ ...payloads...     │
└────────────────┴───────────────────┴────────────────────┴────────────────────┘
```

### 4.3 Android Remote Mode（JSON over TCP）

```
Android App（集成 logviewer-android SDK）
  │
  ├─ 路径 A：Android 发现 macOS
  │   macOS 广播 _logviewer._tcp（NetService）
  │   Android NsdManager 发现 → TCP 连入
  │   └─ AndroidRemoteLoggerServer（NWListener, port 52888）
  │
  └─ 路径 B：macOS 发现 Android
      Android 广播 _logviewer-android._tcp
      └─ AndroidRemoteLoggerBrowser（NWBrowser）→ 自动 TCP 连接
          断线后 2s 自动重连

  模拟器额外回退: 10.0.2.2:52888
```

**JSON 协议（换行分隔）**：

每行一个 JSON 对象（`\n` 分隔）：

```json
// 握手
{"type":"hello","sentAt":1717000000000,"hello":{"platform":"android","deviceId":"...","deviceName":"...","appId":"...","appVersion":"...","osVersion":"...","sdkVersion":"..."}}

// 日志消息
{"type":"message","sentAt":...,"message":{"timestamp":...,"level":"info","category":"...","message":"...","tag":"...","thread":"..."}}

// 网络请求完成
{"type":"networkCompleted","sentAt":...,"networkCompleted":{"id":"...","timestamp":...,"url":"...","method":"GET","requestHeaders":{},"requestBody":null,"responseHeaders":{},"responseBody":null,"statusCode":200,"error":null,"durationMs":123}}
```

---

## 5. 核心模块详解

### 5.1 ConnectionManager（中枢管理器）

**文件**：`Managers/ConnectionManager.swift`

**职责**：
- 创建并持有所有通信服务器实例（MacLogReceiver、PulseRemoteLoggerServer、AndroidRemoteLoggerServer、AndroidRemoteLoggerBrowser）
- 绑定各服务器的回调，统一处理 peer 状态变化和数据接收
- 维护 `devices: [DeviceModel]` 列表（自动创建/更新设备）
- 计算传输速率
- 将接收到的数据路由到 `PulseStoreInjector`

**关键方法**：

| 方法 | 来源 | 作用 |
|---|---|---|
| `handlePeerStateChange(_:)` | MacLogReceiver | iOS Custom Mode 连接状态 |
| `handleReceivedPacket(_:)` | MacLogReceiver | iOS Custom Mode 数据 → pulseInjector |
| `handleRemoteLoggerPeerStateChange(_:)` | PulseRemoteLoggerServer | Pulse Remote 连接状态 |
| `handleRemoteLoggerEvent(_:)` | PulseRemoteLoggerServer | Pulse Remote 数据 → pulseInjector |
| `handleAndroidRemoteLoggerPeerStateChange(_:)` | AndroidRemoteLoggerServer/Browser | Android 连接状态 |
| `handleAndroidRemoteLoggerEvent(_:)` | AndroidRemoteLoggerServer/Browser | Android 数据 → pulseInjector |
| `ensureDevice(id:displayName:platform:)` | 内部 | 设备不存在时创建，存在时更新名称 |
| `clearStoredRecords()` | UI 触发 | 清空所有 Pulse 记录和设备历史 |

**数据流**：所有回调都在 `@MainActor` 上执行，确保 UI 安全。

### 5.2 PulseStoreInjector（Pulse 适配层）

**文件**：`Adapters/PulseStoreInjector.swift`

**职责**：
- 持有 Pulse `LoggerStore` 实例（临时沙盒目录 `.pulse`）
- 将三种来源的数据统一转换为 Pulse 存储格式
- 设备隔离：通过 `label`（message）和 `taskDescription` 中的 `[logviewer-device:peerID]` 标记（network）
- 黑名单过滤：写入前检查 `NetworkRequestBlocklist`
- 提供 Send Again（重放请求）功能
- 响应体规范化（通过 `NetworkResponseBodyNormalizer`）

**设备隔离机制**：
- Messages：`label` 格式为 `"设备名 · 分类"`，查询时用 `label == deviceName OR label BEGINSWITH "deviceName ·"`
- Network：`taskDescription` 中嵌入 `[logviewer-device:peerID]`，查询时用 `CONTAINS`

**Store 位置**：
- `.temporarySandbox`（默认）：`FileManager.temporaryDirectory/logviewer-live-UUID.pulse`
- `.inMemory`：`/dev/null/UUID`

**条件编译**：当 Pulse 未链接时，提供空实现的 fallback 类。

### 5.3 NetworkRequestActionCoordinator（请求操作协调器）

**文件**：`Managers/NetworkRequestActionCoordinator.swift`

**职责**：
- 持有当前选中的 `PulseConsoleSelection`，解析出 `NetworkTaskEntity`
- 提供 Copy（剪贴板）和 Send Again（URLSession 重放）操作
- 注册全局 `RequestCommands` 菜单栏（含快捷键 ⌘⇧U/P/H/B/C/R）

### 5.4 NetworkRequestBlocklist（黑名单）

**文件**：`Models/NetworkRequestBlocklist.swift`

**职责**：
- 管理被屏蔽的 host 和 URL 列表
- UserDefaults 持久化
- 提供 `NetworkRequestBlocklistSnapshot`（不可变快照）供查询层使用
- 生成 `NSPredicate` 排除匹配记录
- 规范化 host/URL 输入

---

## 6. UI 架构

### 6.1 三栏布局（ContentView）

```
┌─────────────┬──────────────────────┬─────────────────────┐
│  Sidebar     │  Content             │  Detail             │
│  280-360px   │  420-620px           │  420-540px          │
│              │                      │                     │
│  设备列表     │  TabView:            │  TabView:           │
│  - 平台图标   │  - Messages          │  - Request          │
│  - 状态      │    (FetchRequest)    │    (Overview/       │
│  - 速率      │  - Network           │     Headers/Body/   │
│  - 历史      │    (QueryController) │     cURL)           │
│              │    工具栏:            │  - Response         │
│              │    搜索/筛选/分组/排序  │    (Headers/Body/   │
│              │                      │     JSON高亮/图片)   │
│              │                      │  - Metrics          │
└─────────────┴──────────────────────┴─────────────────────┘
```

### 6.2 状态管理

```
logViewerApp
  ├─ @StateObject ConnectionManager      → .environmentObject 注入
  └─ @StateObject NetworkRequestActionCoordinator → 参数传递

ContentView
  ├─ @State selectedDeviceID: DeviceModel.ID?
  ├─ @State selectedCategory: LogCategory (.messages / .network)
  └─ @State selectedConsoleSelection: PulseConsoleSelection?
       │
       ├─ → LogPanelView（中栏，控制 Tab 切换和清除/黑名单操作）
       │    ├─ PulseMessagesConsoleView（@FetchRequest 直接查 CoreData）
       │    └─ PulseNetworkConsoleView（PulseNetworkQueryController 管理查询）
       │
       └─ → LogDetailView（右栏 Inspector）
            └─ 通过 injector.messageEntity/networkTaskEntity 获取实体
```

### 6.3 Network 查询系统（PulseNetworkQueryController）

**文件**：`Views/Logs/PulseNetworkConsoleSupport.swift`

- 基于 `NSFetchedResultsController` 实时响应 CoreData 变更
- 支持多维筛选：搜索文本、状态码（2xx/3xx/4xx/5xx）、HTTP 方法、Host、耗时、大小、错误状态
- 支持分组：None / Host / Status / Method
- 支持排序：Date / Duration / Size × Ascending / Descending
- 自动提取 facets（可用 Host / Method 列表）
- 组合 predicate：用户筛选 + 黑名单排除 + 设备隔离

---

## 7. 数据模型

### 7.1 DeviceModel

```swift
struct DeviceModel: Identifiable, Hashable {
    let id: String                    // peer 标识（MCPeerID.displayName / deviceId|appId）
    var name: String                  // 显示名
    var platform: DevicePlatform      // .ios / .android
    var status: DeviceConnectionStatus  // .connected / .disconnected
    var transferRateKBps: Double      // 实时传输速率
    var connectionHistory: [ConnectionRecord]  // 连接历史
}
```

### 7.2 PulseConsoleSelection

```swift
enum PulseConsoleSelection: Hashable {
    case message(NSManagedObjectID)   // 选中的日志消息
    case network(NSManagedObjectID)   // 选中的网络请求
}
```

### 7.3 LogCategory

```swift
enum LogCategory: String, CaseIterable {
    case messages = "Messages"
    case network = "Network"
}
```

---

## 8. 通信服务器对比

| 特性 | MacLogReceiver | PulseRemoteLoggerServer | AndroidRemoteLoggerServer | AndroidRemoteLoggerBrowser |
|---|---|---|---|---|
| 平台 | iOS Custom | iOS（Pulse SDK） | Android | Android |
| 传输 | MultipeerConnectivity | NWListener (TCP) | NWListener (TCP:52888) | NWBrowser → NWConnection |
| 发现 | MCNearbyServiceBrowser | Bonjour `_pulse._tcp` | Bonjour `_logviewer._tcp` | Bonjour `_logviewer-android._tcp` |
| 协议 | Binary PropertyList | 自定义二进制帧 + LZFSE | JSON（换行分隔） | JSON（换行分隔） |
| 连接管理 | MCSession 自动 | 每连接一个 ClientConnection | 每连接一个 ClientConnection | 自动重连（2s） |
| 数据格式 | LogPacket 信封 | Pulse LoggerStore.Event | AndroidRemoteLoggerEnvelope | AndroidRemoteLoggerEnvelope |

---

## 9. 关键设计决策

### 9.1 统一注入 Pulse LoggerStore

所有来源的数据最终都通过 `PulseStoreInjector` 写入同一个 `LoggerStore`，利用 Pulse 的 CoreData 模型和 PulseUI 组件展示。这避免了自建 UI 渲染层，但要求所有数据都能映射到 Pulse 的 `storeMessage()` / `storeRequest()` API。

### 9.2 设备隔离

- Messages 通过 `label` 前缀匹配
- Network 通过 `taskDescription` 中的 `[logviewer-device:peerID]` 标记
- 这允许在同一个 Store 中按设备筛选，而无需维护多个 Store

### 9.3 条件编译策略

- `#if os(macOS) && canImport(Pulse)`：主要功能代码
- `#if os(macOS)`（无 Pulse）：提供空实现 fallback
- `#if os(iOS)`：IOSLogSender 仅在 iOS 编译
- Package `LogViewerCustomMode` 同时支持 iOS 和 macOS target

### 9.4 响应体规范化

`NetworkResponseBodyNormalizer` 处理部分 SDK 可能发送重复 JSON body 的问题：
- 精确对半去重（前半 == 后半）
- 正则匹配重复 JSON 文本
- 仅在 Content-Type 为 JSON 或内容以 `{`/`[` 开头时检查

### 9.5 Send Again（请求重放）

- 从 `NetworkTaskEntity` 重建 `URLRequest`
- 剥离 hop-by-hop headers（connection, content-length, host, proxy-connection, transfer-encoding）
- 通过 `URLSession.shared.data(for:)` 发送
- 结果重新写入 Pulse Store（label: "Inspector Replay"）
- 受黑名单约束

---

## 10. 构建与验证

### macOS 主工程

```bash
xcodebuild -project logViewer.xcodeproj \
  -scheme logViewer \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### iOS SDK Package

```bash
cd Packages/LogViewerCustomMode
swift build
```

---

## 11. 文件修改指引

> 当需要修改特定功能时，以下是推荐的文件定位：

| 需求 | 主要修改文件 |
|---|---|
| 添加新的数据接入协议 | `Networking/` 新建 Server + Protocol 文件，`ConnectionManager` 添加绑定 |
| 修改设备列表展示 | `Views/Sidebar/DeviceSidebarView.swift` + `Models/DeviceModel.swift` |
| 修改 Network 列表筛选/排序 | `Views/Logs/PulseNetworkConsoleSupport.swift`（查询模型）+ `PulseConsoleFormatting.swift`（UI） |
| 修改 Request Inspector 详情 | `Views/Detail/LogDetailView.swift` |
| 添加新的 Copy 动作 | `Views/Logs/PulseConsoleEntityFormatting.swift`（NetworkRequestCopyAction + Entity 扩展） |
| 修改响应体展示（JSON 高亮/图片/HTML） | `Views/Detail/NetworkResponsePresentation.swift` |
| 修改黑名单逻辑 | `Models/NetworkRequestBlocklist.swift` + `Views/Logs/NetworkBlacklistSheet.swift` |
| 修改 Pulse 数据写入逻辑 | `Adapters/PulseStoreInjector.swift` |
| 修改 iOS SDK 协议/编码 | `Packages/LogViewerCustomMode/Sources/` |
| 添加全局快捷键/菜单 | `Managers/NetworkRequestActionCoordinator.swift`（RequestCommands） |
| 修改 Android JSON 协议 | `Networking/AndroidRemoteLoggerProtocol.swift`（结构体定义） |

---

## 12. 已知限制与改进方向

### 当前限制

1. **LogEntry 模型未实际使用**：`Models/LogEntry.swift` 仅包含静态 samples 数据，实际日志展示完全依赖 Pulse CoreData 实体。可考虑移除或重新定位。
2. **单 Store 架构**：所有设备共享一个 LoggerStore，设备隔离依赖字符串匹配（label/taskDescription），大量设备时可能有性能瓶颈。
3. **无历史持久化**：Store 在临时目录，App 重启后数据丢失。
4. **Android 协议无加密/认证**：TCP 明文 JSON，仅适用于本地调试。
5. **Pulse 强依赖**：核心展示逻辑与 Pulse CoreData schema 紧耦合（NSManagedObjectID、FetchRequest、NSPredicate）。
6. **PulseConsoleHostView.swift 为空文件**：实际实现放在 PulseConsoleFormatting.swift，命名有误导性。

### 可能的改进方向

- 支持导出 `.pulse` 文件 / 导入历史 session
- 支持 WebSocket / gRPC 等新协议接入
- Network 列表支持列式布局（表格模式）
- 日志搜索支持正则表达式
- 设备间日志对比
- 请求重放支持自定义 header 编辑
- 支持 Android 模拟器 mDNS 更稳定的发现机制

---

## 13. 依赖关系图

```
logViewerApp
  │
  ├── ConnectionManager ──────────────────────────────────────┐
  │     ├── MacLogReceiver (LogViewerCustomMode)              │
  │     ├── PulseRemoteLoggerServer (Network + Pulse)         │
  │     ├── AndroidRemoteLoggerServer (Network)               │
  │     ├── AndroidRemoteLoggerBrowser (Network)              │
  │     ├── NetworkRequestBlocklist (UserDefaults)            │
  │     └── PulseStoreInjector ──────────────────────────┐    │
  │           ├── Pulse LoggerStore (CoreData)           │    │
  │           ├── LogPacketDecoder (LogViewerCustomMode) │    │
  │           └── NetworkResponseBodyNormalizer          │    │
  │                                                      │    │
  ├── NetworkRequestActionCoordinator ───────────────────┤    │
  │     └── PulseStoreInjector (weak ref)                │    │
  │                                                      │    │
  └── ContentView                                        │    │
        ├── DeviceSidebarView ← ConnectionManager        │    │
        ├── LogPanelView ← ConnectionManager             │    │
        │     ├── PulseMessagesConsoleView ← LoggerStore │    │
        │     └── PulseNetworkConsoleView                │    │
        │           └── PulseNetworkQueryController ←────┘    │
        └── LogDetailView ← PulseStoreInjector                │
              └── NetworkResponseBodyPresentation              │
                                                              │
External Dependencies:                                        │
  - Pulse (SPM) ──────────────────────────────────────────────┘
  - LogViewerCustomMode (local package)
```
