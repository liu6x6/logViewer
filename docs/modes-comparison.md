# Pulse 模式 vs 自定义模式

本文档把本项目的两条远程采集链路放在同一个视角里比较：

- **Pulse 模式**
- **自定义模式**

如果你要决定“新项目该接哪一种”，或者“后续该增强哪一条链路”，这份文档更适合直接做决策参考。

## 1. 先说结论

如果你的客户端**已经接入 Pulse**，优先用 **Pulse 模式**。  
如果你的客户端**还没有接入 Pulse，且希望以最低成本快速打通日志 + 网络摘要**，优先用 **自定义模式**。

可以把两者理解为：

- **Pulse 模式**：完整度优先
- **自定义模式**：接入成本和协议控制优先

## 2. 两条链路的整体结构

### 2.1 自定义模式

链路如下：

1. iOS 调用 `IOSLogSender`
2. 用 MultipeerConnectivity 广播并发送 `LogPacket`
3. macOS 侧 `MacLogReceiver` 收包
4. `ConnectionManager` 更新设备状态
5. `PulseStoreInjector` 解码并写入 Pulse store
6. UI 统一展示

### 2.2 Pulse 模式

链路如下：

1. 客户端接入 Pulse RemoteLogger
2. macOS 侧 `PulseRemoteLoggerServer` 用 `_pulse._tcp` 监听
3. 收到 RemoteLogger wire packet 后解压、拆包、解码
4. `ConnectionManager` 更新设备状态
5. `PulseStoreInjector` 适配 Pulse event 并写入 Pulse store
6. UI 统一展示

它们的共同点是：

- 最后都进入 `PulseStoreInjector`
- 最后都进入同一个 `LoggerStore`
- 最后都走同一套 Network / Messages / Inspector UI

## 3. 对比表

| 维度 | 自定义模式 | Pulse 模式 |
|---|---|---|
| 传输层 | MultipeerConnectivity | TCP + Bonjour (`_pulse._tcp`) |
| 协议定义 | 项目自定义 | Pulse RemoteLogger |
| 客户端接入成本 | 低 | 中 |
| 协议可控性 | 高 | 低到中 |
| message 信息量 | 中 | 高 |
| network 信息量 | 中 | 高 |
| request body | 当前无 | 有 |
| response body | 有 | 有 |
| metadata / file / line | 基本无 | 有 |
| metrics | 当前无 | 事件层有，但 UI 还没完全吃满 |
| 扩展新字段 | 容易 | 受 Pulse 协议限制 |
| 适合快速起步 | 是 | 一般 |
| 适合深度分析 | 一般 | 是 |

## 4. 两条模式最本质的差异

### 4.1 自定义模式是“摘要采集”

自定义模式的核心网络模型是 `LogNetworkPayload`。  
它只提供项目当前真正关心的少量字段，例如：

- url
- method
- request headers
- response headers
- status code
- response body

它的优点是：

- 发送端实现简单
- 包结构完全可控
- 你可以按自己业务节奏扩字段

它的缺点是：

- 一开始信息天然更少
- 如果后续想追平 Pulse，需要持续自己补协议

### 4.2 Pulse 模式是“原生事件转接”

Pulse 模式不是你自己重新定义一套网络模型，而是直接承接 Pulse 的事件。  
它的优点是：

- 现成的事件结构更完整
- message 和 network 都更接近真实调试需求
- 后续做深度分析的上限更高

它的缺点是：

- 客户端前置成本更高
- 协议控制权不在本项目手里

## 5. 对产品体验的影响

从当前 `logViewer` 的 UI 看，两条模式虽然都能进入同一套界面，但体验还是有差异。

### 5.1 在 Messages 上

- **自定义模式** 更像“远程 console message”
- **Pulse 模式** 更像“带上下文的结构化日志”

如果后面你要支持：

- 跳源码
- 按 metadata 过滤
- 更细粒度分类

Pulse 模式会更有优势。

### 5.2 在 Network 上

- **自定义模式** 更适合“看到请求、复制到 Bruno、看响应体”
- **Pulse 模式** 更适合“深查请求本身的上下文和还原度”

这也是为什么你刚才加的这些能力：

- Copy URL
- Copy Query Parameters
- Copy Headers
- Copy Body
- Copy cURL
- Send Again

两种模式都能用，但 **Pulse 模式通常能导出更完整的请求信息**。

## 6. 如果你只想尽快可用

优先选 **自定义模式**，因为：

1. 不依赖客户端已接入 Pulse
2. 只需要接 `IOSLogSender`
3. 先把日志和网络摘要打通就能开始用
4. 很适合拿来快速复制请求到 Bruno / cURL

## 7. 如果你想把它做成长期能力

优先把 **Pulse 模式** 做强，因为：

1. 数据完整度更高
2. 后续扩展高级 Inspector 更有基础
3. 做性能和错误分析更有空间
4. 不需要长期维护一套平行协议去追赶 Pulse

## 8. 一个务实的路线

如果按项目演进来规划，最现实的路线通常是：

1. **先靠自定义模式快速起量**
   - 先打通消息日志
   - 先支持网络摘要
   - 先把 Bruno / cURL 工作流做好

2. **对已接入 Pulse 的客户端启用 Pulse 模式**
   - 获取更完整的 message / network 信息
   - 逐步增强 Inspector 展示

3. **让 UI 层继续保持统一**
   - 不要为两种模式写两套 console
   - 尽量都适配到同一个 Pulse store 视图层

这正是当前代码已经在做的事情。

## 9. 后续增强建议

### 9.1 自定义模式优先补什么

1. request body
2. richer error
3. timing / metrics
4. 更细粒度 packet type
5. 大包传输策略

### 9.2 Pulse 模式优先补什么

1. progress event 展示
2. metrics 展示
3. metadata / source location 展示
4. originalRequest / currentRequest 差异展示

## 10. 相关文档

- 自定义模式：`docs/custom-mode.md`
- Pulse 模式：`docs/pulse-mode.md`
