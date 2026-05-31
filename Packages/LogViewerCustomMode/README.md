# LogViewerCustomMode

`LogViewerCustomMode` 是一个独立的 Swift Package，用来把 iOS App 内的日志和网络摘要通过 **MultipeerConnectivity** 发送到 `logViewer` 的 macOS 端。

目前它主要提供两类能力：

- `IOSLogSender`：在 iOS 侧广播并发送数据
- 自定义协议模型与编解码：`LogPacket`、`LogMessagePayload`、`LogNetworkPayload`、`LogPacketEncoder`、`LogPacketDecoder`

## Requirements

- iOS 15+
- macOS 12+
- Swift 6

## Add the package

### As a local package

如果你的工程和本仓库在同一个 workspace 或本地目录里，可以直接引用本地 package：

1. Xcode -> **File** -> **Add Package Dependencies...**
2. 选择 **Add Local...**
3. 选中 `Packages/LogViewerCustomMode`

### As a copied package

如果你准备把这个 package 拷贝到别的项目里，保持目录结构不变即可，然后在目标工程里按本地 package 的方式添加。

## Basic usage

### 1. Import the package

```swift
import LogViewerCustomMode
```

### 2. Create a sender

`IOSLogSender` 会在初始化后自动开始广播，并自动接受来自 macOS 接收端的连接邀请。

```swift
import LogViewerCustomMode

@MainActor
final class DebugLogBridge {
    let sender = IOSLogSender()
}
```

也可以显式指定显示名称：

```swift
let sender = IOSLogSender(displayName: "My iPhone 16 Pro")
```

### 3. Send a log message

```swift
try sender.sendLogMessage(
    message: "User tapped checkout button",
    level: .info,
    category: "checkout"
)
```

支持的日志级别：

- `.debug`
- `.info`
- `.error`

### 4. Send a network summary

```swift
let body = Data("{\"ok\":true}".utf8)

try sender.sendNetworkSummary(
    url: URL(string: "https://api.example.com/orders")!,
    method: "POST",
    requestHeaders: [
        "Content-Type": "application/json",
        "Authorization": "Bearer <token>"
    ],
    responseHeaders: [
        "Content-Type": "application/json"
    ],
    statusCode: 200,
    responseBody: body
)
```

这适合把你自己埋点采集到的请求摘要发到 `logViewer` 中统一查看。

## Recommended wrapper

通常不建议在业务代码里到处直接调用 `IOSLogSender`，更适合包一层自己的桥接对象：

```swift
import LogViewerCustomMode

@MainActor
final class LogViewerBridge {
    private let sender = IOSLogSender()

    func log(_ message: String, category: String = "app") {
        do {
            try sender.sendLogMessage(
                message: message,
                level: .info,
                category: category
            )
        } catch {
            print("logViewer send failed:", error.localizedDescription)
        }
    }
}
```

## Connection state

你可以通过这两个只读属性了解当前状态：

- `sender.isAdvertising`
- `sender.connectedPeerDisplayNames`

例如：

```swift
if sender.connectedPeerDisplayNames.isEmpty {
    print("No Mac receiver connected yet.")
}
```

## Error handling

当前最常见的错误是：

- `IOSLogSenderError.noConnectedReceiver`

这表示当前还没有连上 macOS 接收端。

```swift
do {
    try sender.sendLogMessage(
        message: "App started",
        level: .info,
        category: "lifecycle"
    )
} catch {
    print(error.localizedDescription)
}
```

## App permissions and environment

由于底层使用的是 `MultipeerConnectivity`，建议注意下面几点：

1. iPhone 和 Mac 需要在同一局域网环境下。
2. 真机调试比模拟器更可靠。
3. 初次连接时，系统可能会触发本地网络相关权限提示。
4. 如果你的 App 对后台、企业网络、VPN、隔离 Wi-Fi 有特殊限制，连通性可能会受影响。

## Public types

除了 `IOSLogSender`，下面这些类型也可以单独使用：

- `LogPacketType`
- `LogMessageLevel`
- `LogPacket`
- `LogMessagePayload`
- `LogNetworkPayload`
- `DecodedLogPacket`
- `LogPacketEncoder`
- `LogPacketDecoder`

如果你之后想自己接入别的传输层，也可以直接复用这套协议模型和编解码。

## Notes

- 当前 package 里的发送入口主要面向 **iOS 发送到 macOS**。
- macOS 端接收能力也在 package 内，但主要给 `logViewer` 主工程使用。
- `sendNetworkSummary` 发送的是**请求摘要**，不是完整抓包代理能力。

## Related files

- Package root: `Packages/LogViewerCustomMode`
- Main app integration doc: `docs/custom-mode.md`
