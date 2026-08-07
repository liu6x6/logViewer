# Session 改动总结 · 2026-07-30

> 本文档汇总本次 session 的所有改动，供后续 AI 继续开发时快速恢复上下文。
> 配套的整体架构说明见 [`docs/architecture.md`](./architecture.md)。
>
> **状态**：以下改动均已完成并通过 `xcodebuild` 编译验证（`** BUILD SUCCEEDED **`），尚未 git commit。

---

## 0. 总览

本次 session 在已有架构（详见 `architecture.md`）基础上，围绕 **设备管理、Inspector 体验、列表性能、Messages 功能** 做了 9 项改进。所有改动均为增量式，未破坏三种数据接入模式（iOS Custom / Pulse Remote / Android）的核心链路。

涉及文件（`git diff --stat`）：

```
Packages/.../LogViewerMultipeerConfiguration.swift   |  50 ++-   (设备信息广播)
Packages/.../MacLogReceiver.swift                    |   6 +     (缓存 discoveryInfo)
logViewer/Adapters/PulseStoreInjector.swift          |  63 ++    (按设备清理)
logViewer/ContentView.swift                          |  66 ++-   (Inspector 折叠 + 布局重构)
logViewer/Managers/ConnectionManager.swift           |  47 ++    (删除设备 / 按设备清理 / details 路由)
logViewer/Models/DeviceModel.swift                   |  76 ++    (DeviceDetails + 展示派生属性)
logViewer/Networking/AndroidRemoteLoggerServer.swift |  15 +     (Android 设备信息)
logViewer/Networking/PulseRemoteLoggerServer.swift   |  18 +     (Pulse 设备信息)
logViewer/Views/Detail/LogDetailView.swift           | 138 ++-   (Message 详情页 / tab 记忆 / 分段控件)
logViewer/Views/Logs/LogPanelView.swift              |  36 +-    (按设备清理按钮 / tab 顺序)
logViewer/Views/Logs/PulseConsoleFormatting.swift    | 188 ++-   (网络列表去重用 / Messages 控制台重写)
logViewer/Views/Logs/PulseNetworkConsoleSupport.swift| 124 ++    (Messages 查询控制器 + 过滤模型)
logViewer/Views/Sidebar/DeviceSidebarView.swift      |  38 +     (设备右键菜单 + 详细信息展示)
```

---

## 1. 设备右键删除（Delete Device）

**需求**：左侧设备列表支持右键删除某设备；若设备仍在线，会自动重新连回。

**实现**：
- `ConnectionManager.removeDevice(id:)`：从 `devices` 移除条目、清理 `lastPacketDateByDeviceID`、刷新在线名单。**不断开底层传输连接**——因此只要 peer 仍在广播/发数据，下一次状态事件或数据包到达时，`ensureDevice(...)` 会自动重建设备。
- `DeviceSidebarView`：每行 `.contextMenu` 增加 `Delete Device`（destructive）；若删的是当前选中项，同时清空 `selectedDeviceID`。

**关键点**：删除是「软删除列表条目」，三种接入方式的 handler 都通过 `ensureDevice` 自动重建设备，天然支持自动重连。

---

## 2. 设备详细信息（型号 / 系统 / App）

**需求**：设备卡片显示更丰富的信息（设备型号、系统版本、App 名等）。

**实现**：
- 新增统一模型 `DeviceDetails`（`Models/DeviceModel.swift`）：`model / systemName / systemVersion / appName / appVersion`，全可选。
- `DeviceModel` 增加 `details: DeviceDetails` 字段 + 派生展示属性：
  - `modelSummary`（型号，缺失时回退到 systemSummary）
  - `systemSummary`（如 "iOS 17.4" / "Android 14"）
  - `appSummary`（如 "MyApp 1.2.0"）
  - `mergeDetails(_:)`：用非空字段增量覆盖（断连事件传 nil 不会清空已有信息）
- `ensureDevice(...)` 增加 `details:` 参数，三种来源都接入：
  - **Pulse Remote**：`PulseRemoteLoggerClientIdentity.deviceDetails` 取自 hello 的 `deviceInfo`（localizedModel/model/systemName/systemVersion）+ `appInfo`（name/version）。事件结构 `PulseRemoteLoggerPeerStateEvent` 增加 `details`。
  - **Android**：`AndroidRemoteLoggerClientIdentity.deviceDetails`（systemName="Android"、systemVersion=osVersion、appName/appVersion）。`AndroidRemoteLoggerPeerStateEvent` 增加 `details`，Server 与 Browser 四处构造点都已传入。
  - **iOS Custom Mode**：Package 侧新增公开结构 `LogViewerDeviceDetails`（避免跨模块引用主工程的 `DeviceDetails`）。`IOSLogSender` 的 `discoveryInfo` 增加 `model/systemName/systemVersion`（来自 `UIDevice`）；`MacLogReceiver` 用 `discoveryInfoByPeerName` 缓存每个 peer 的 discoveryInfo（因为 `session(didChange:)` 拿不到），并在构造 `LogViewerPeerStateEvent` 时附带。`ConnectionManager.handlePeerStateChange` 把 package 的 `LogViewerDeviceDetails` 转成主工程 `DeviceDetails`。
- `DeviceSidebarView` 行内新增型号行（`modelSummary`）和 App 行（`appSummary`，带 `app` 图标）。

**注意**：iOS Custom Mode 的型号信息依赖 discoveryInfo，仅在 `foundPeer` 时拿到；设备删除后若直接收数据（未经 foundPeer）可能暂缺型号，属预期。

---

## 3. Inspector Tab 记忆

**需求**：切换不同网络请求时，右侧 Inspector 记住上次停留的 Tab（如停在 Response 就继续显示 Response），而非每次重置回 Request。

**实现**：删除 `LogDetailView` 中的 `.onChange(of: selectedConsoleSelection) { selectedTab = .request }`。`selectedTab` 是 `@State`，切换选中项时视图实例不重建，自然保留。

---

## 4. 网络列表「卡片重用」问题修复

**需求**：短时间内大量网络请求时，中间网络卡片出现内容重复（重用错乱），需折叠再展开才恢复。

**根因**：网络面板原用 SwiftUI `List`（macOS 底层行重用池）。卡片是完全自定义样式（`.listRowBackground(Color.clear)` + 自绘圆角/阴影），与 `List` 重用机制冲突，高频刷新时行内容来不及重配 → 串台。

**实现**（`PulseConsoleFormatting.swift`）：把网络列表从 `List` 换成 `ScrollView + LazyVStack`（按 identity 懒加载，无行池重用）：
- 分组从 `Section{}/header:` 改为手动渲染 `groupHeader` + 内容，折叠/展开逻辑（`expandedSections`）不变。
- `networkRow` 去掉 `listRowInsets/listRowBackground`，改用 `.padding` + `.contentShape(Rectangle())`，并加稳定 `.id(task.objectID)`。
- 仅网络面板改动，Messages 不受影响。

---

## 5. 按设备清理（Clear Network / Clear Messages）

**需求**：把原来的全局「Clear Records」拆成 **Clear Network** 和 **Clear Messages** 两个按钮，只作用于当前选中设备；未选中设备时按钮禁用。同时左侧设备卡片右键菜单也加这两项。

**实现**：
- `PulseStoreInjector` 新增：
  - `clearNetworkRecords(for:)`：用 `networkPredicate`（`taskDescription CONTAINS [logviewer-device:peerID]`）fetch 该设备 `NetworkTaskEntity`，连同 request/response body 删除。
  - `clearMessageRecords(for:)`：用 `messagePredicate`（按设备名 label）+ `task == NULL` fetch 该设备独立消息删除。
  - 均 `context.performAndWait` + `safeSave()`。非 Pulse fallback stub 也补了空实现。
- `ConnectionManager` 新增 `clearNetworkRecords(for:)` / `clearMessageRecords(for:)`（`device == nil` 直接返回）。
- `LogPanelView`：删掉单个 Clear Records 按钮及其全量确认弹窗，新增两个按钮，均 `.disabled(device == nil)`。
- `DeviceSidebarView` 右键菜单在 Delete Device 前加 Clear Network / Clear Messages（`Divider` 分隔）。
- 清理后若右侧选中的正是被删记录，中栏已有的 `onChange` 会自动清空选中态。

**遗留**：旧的全量方法 `ConnectionManager.clearStoredRecords()` 现在无人调用，暂保留（含重置连接历史逻辑），可按需移除。

---

## 6. Network / Messages Tab 顺序调换

**需求**：Network 使用更频繁，调到前面。

**实现**：
- `LogPanelView` TabView 顺序改为 **Network → Messages**。
- `ContentView` 默认 `selectedCategory` 从 `.messages` 改为 `.network`。

---

## 7. Messages 功能增强

**需求**：
1. 选中 message 时右侧不显示 Request/Response/Metrics，改为 Message 详情 + 复制；
2. message 卡片右键菜单：Copy Message + Delete；
3. message 支持按类型（debug/info/error）和关键字过滤。

**实现**：

**(1) Message 详情页**（`LogDetailView.swift`）：
- `inspectorBody` 按 `selectedPayload` 分流：`.message` → `messageDetailPane`；否则 → `inspectorTabs`。
- `messageDetailPane`：顶部 Copy Message + Share 按钮；概览卡片（Label/Level/时间）；Message 正文卡片（等宽、可选中、右键复制）；Metadata 卡片（有才显示）；Source 卡片（file/function/line/session）。

**(2) 卡片右键菜单**（`PulseConsoleFormatting.swift`）：`PulseMessageRowView` 增加 `actionCoordinator` + `deleteAction`，contextMenu 提供 Copy Message / Delete Message。

**(3) 过滤**：Messages 控制台从 `@FetchRequest` 重写为**控制器 + 工具栏**模式（对齐 Network 面板）：
- 工具栏：关键字搜索框（匹配 text / label，`CONTAINS[cd]`）+ Level 多选菜单（Debug/Info/Error）+ 条目计数。
- `PulseNetworkConsoleSupport.swift` 新增：
  - `PulseMessageLevelFilter`（debug/info/error → `LoggerStore.Level`）
  - `PulseMessagesConsoleQuery`（searchText + levelFilters）
  - `PulseMessagesQueryController`（`NSFetchedResultsController<LoggerMessageEntity>`，组合谓词 = `task == NULL` + 设备隔离 + 关键字 + level；提供 `delete(messageWithID:)`）。
- `PulseConsoleHostView` 给 Messages 视图传入 `context` 与 `actionCoordinator`。

---

## 8. Inspector 折叠按钮

**需求**：给右侧属性页加折叠/展开按钮。

**实现**（`ContentView.swift`）：
- 把 Inspector 从 `NavigationSplitView` 的 detail 列移到外层 `HStack`，用 `@State isInspectorCollapsed` 控制显隐（`NavigationSplitView` 的 `columnVisibility` 无法精准只收起右栏）。
- 左设备栏 + 中 Console 保留在**双列** `NavigationSplitView`（注意：双列版第二列标签是 `detail:`，不是 `content:`）。
- 折叠时 Inspector 带 `.move(edge:.trailing)+.opacity` 过渡 + `.easeInOut(0.22)` 动画滑出，中栏自动扩展。
- 工具栏 `.primaryAction` 加切换按钮（`sidebar.trailing` 图标），Label/help 随状态切换 Hide/Show Inspector。
- Inspector 宽度 `min 420 / ideal 540 / max 640`；原选中态同步、`onChange` 逻辑不变。

---

## 9. Inspector Tab 位置修复（TabView → 分段控件）

**需求/问题**：第 8 项把 `LogDetailView` 移出 `NavigationSplitView` 后，macOS 把 `TabView` 标签栏**自动提升进窗口工具栏**，Request/Response/Metrics 跑到了上方。期望放回属性页顶部。

**实现**（`LogDetailView.swift`）：`inspectorTabs` 由 `TabView` 改为内联**分段控件**：

```swift
VStack(spacing: 12) {
    Picker("Inspector Tab", selection: $selectedTab) {
        ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
    }
    .pickerStyle(.segmented)
    .labelsHidden()

    switch selectedTab {
    case .request:  requestDetailPane
    case .response: responseDetailPane
    case .metrics:  detailPane(text: metricsTabText)
    }
}
```

分段控件稳定渲染在面板内容区顶部，不会再被提升到窗口工具栏。三个 pane 内容与功能不变。

> **经验教训（供后续 AI 注意）**：在 macOS 上，`TabView` 处于较高视图层级且窗口带 `.toolbar` 时，其标签栏会被系统提升进工具栏。若需内联 tab，应使用分段控件或自定义 tab 条，避免直接用 `TabView`。

---

## A. 给后续 AI 的快速指引

- **整体架构 / 协议 / 文件定位**：先读 `docs/architecture.md`（含「文件修改指引」速查表）。
- **本 session 行为变更**：以本文为准。
- **构建验证命令**：
  ```bash
  xcodebuild -project logViewer.xcodeproj -scheme logViewer \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build
  ```
- **设备隔离机制**（多处复用）：Messages 靠 `label` 前缀匹配；Network 靠 `taskDescription` 中 `[logviewer-device:peerID]` 标记。见 `PulseStoreInjector.messagePredicate/networkPredicate`。
- **设备自动重建**：所有来源 handler 都走 `ensureDevice(...)`，删除设备后在线会自动重连。

## B. 建议的回归测试清单

1. 右键设备 → Delete Device；设备在线时应自动重新出现。
2. 设备卡片显示型号 / 系统 / App（Pulse、Android 来源信息最全）。
3. 切换网络请求时 Inspector 记住 Response/Metrics Tab。
4. 短时间灌入大量请求，滚动网络列表无重复卡片。
5. 选中设备 → Clear Network / Clear Messages 仅清该设备；未选中时按钮灰色；设备右键菜单同两项可用。
6. 默认进入 Network Tab；Tab 顺序为 Network → Messages。
7. 选中 message → 右侧显示 Message 详情（含 Copy）；卡片右键 Copy/Delete 可用。
8. Messages 工具栏：关键字搜索 + Level 过滤实时生效，计数正确。
9. 工具栏右上角按钮可折叠/展开 Inspector，动画顺滑，折叠后中栏扩展。
10. Inspector 顶部 Request/Response/Metrics 分段控件在面板内（不在窗口工具栏），可切换。

## C. 已知遗留 / 可优化项

- `ConnectionManager.clearStoredRecords()` 现为死代码（保留备用）。
- `Models/LogEntry.swift` 仅含静态 samples，实际展示完全走 Pulse CoreData，可考虑移除。
- iOS Custom Mode 设备型号依赖 discoveryInfo，删除后未经 `foundPeer` 直连时可能暂缺。
- Inspector 折叠后无独立快捷键（如需可在全局 Commands 补一个）。
