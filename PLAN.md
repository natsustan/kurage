# Kurage 会话功能

## 当前状态

- 设备码登录、账号恢复、退出登录和工作区列表已经接入 Lody；发送使用当前账号的用户 ID 标记 turn。
- 工作区选择和下拉刷新已接入真实会话列表；所有会话操作都明确携带工作区 ID。
- 会话列表默认按项目分组，项目按最近会话排序；右上角菜单可切换到按时间排序，也包含退出登录。项目名称优先从机器 Flock 文档读取。
- `HTTPLodyClient.streamsAccess(workspaceID:)` 按 Lody 的 `/api/loro-streams/token` 协议取得短期令牌，不会把 Streams 令牌写入 Keychain。
- `SessionSyncBridge` 使用与 Lody 相同版本的 LoroRepo、Flock 和 Streams 库，在本地 WebKit 页面中同步目录与会话文档。原生层通过 URLSession 代理 Streams 请求。
- 真实客户端已支持只读会话正文和实时更新：当前详情页通过 `joinRoom()` 订阅 Session 文档与 workspace metadata，持续显示正文和运行状态。只投影用户和 Agent 的普通文本，工具记录等结构化内容暂不显示。
- 原生网络桥用 `URLSession.bytes(for:)` 将响应头与数据块交给 JS `ReadableStream`，包含背压和 AbortSignal 取消；写请求的请求体也由原生代理发送。Streams 库继续负责 SSE、long-poll 回退与重连。鉴权回调按需续期，401/403 强制重新获取令牌。
- JS 合并 80ms 内的变化并按 turn ID 发送正文补丁；Swift 在桥内先还原完整快照，再通过仅保留最新值的异步流交给界面，避免丢弃中间补丁导致正文缺失。
- 页面离开或进入后台释放订阅，回到前台重新同步；工作区和账号切换丢弃迟到更新。底部阅读时跟随同一条回复增长，上翻阅读时停止自动跟随。
- 真实客户端现可向空闲会话发送普通文本：独立的短生命周期 Streams 副本先确认正文同步，再写入 `latestUserMsgId` 并确认 metadata 同步。每个会话仅当前待确认文本的重试沿用 turn ID；改发其他文本会废弃旧重试 ID。权限响应仍只在 fixture 中可用。
- 会话底部输入区使用悬浮的 Liquid Glass 胶囊；点按发送后立即清空草稿并保持键盘，若发送未确认则恢复原文供重试。
- 聊天区域由 UIKit 容器协调：`keyboardLayoutGuide` 同步调整消息列表与输入区，通过几何测量将整个输入区的实际高度同步给 UIKit 约束并设置列表 inset；SwiftUI 保留消息样式和输入控件。消息按 turn ID 在原生列表中复用和更新，布局与正文高度变化时仅在跟随模式下贴底；上翻阅读时保存消息 ID 与其可视位置，回到底部或发送新消息恢复跟随。短会话仍贴近输入区。

## 验证与后续

1. 发送功能阶段已记录通过 19 项 JS 测试与 36 项 iOS 模拟器 Swift 测试（参数化共 38 次运行），包括正文同步后派发、同 ID 重试、写请求体代理、分块 UTF-8 和原生 WebKit POST。会话发送与长会话 UI 用例已在 iOS 27 模拟器通过；截图确认第二次打开键盘时最新消息仍贴近输入区，测试也确认上滑后打开键盘不会跳回底部。
2. 真实账号的只读会话已由用户实测，反馈可用；持续输出、断网恢复和后台返回各场景的结果尚未逐项记录。当前 JS 在正文变化时仍按节流周期投影完整 history；超长会话的窗口化读取是后续性能工作。
3. 文本发送已按 Lody 桌面端的用户 turn 与 `latestUserMsgId` 协议接入。用户已用真机上的 Kurage 向真实会话发送消息，且消息抵达当前会话，验证了一次正常网络下的发送与派发；网络中断时的确认、重启后的重试仍未验证。运行中 steer、排队消息和权限响应有各自协议，本阶段只允许空闲会话直接派发。下一步再将匹配 `requestId` 的权限响应写入对应 `tool_call`，最后考虑通知和 Diff。

4. 本轮 UIKit 键盘布局改动通过 iOS 27 模拟器的 2 项布局回归测试与 3 项聊天 UI 测试，覆盖正文增长/删除、阅读消息锚点保持、发送恢复贴底、键盘反复开合和五行输入区完整避让。同一多行 UI 用例也在深色模式与系统 XXXL 字号下通过；截图已确认输入区整体随多行文字增高，发送后恢复单行，文字和发送按钮未被键盘遮挡。真机动画手感与真实账号持续输出尚未在本轮验证。

## 之后的增量

权限操作在 fixture 中使用系统确认对话框；真实写入路径仍待接入。文本发送的重试 ID 当前只保存在进程内；重启后若先前请求结果未知，需检查真实会话后再重新发送。

## 协议核对入口

- Lody `packages/shared/src/loro-streams-auth.ts`：工作区 Streams 令牌请求及刷新。
- Lody `packages/shared/src/index.ts`：工作区目录与 Session 流 ID。
- Lody `packages/shared/src/schema.ts`：工作区目录、Session 元数据和会话文档结构。
- Lody `packages/components/src/providers/create-workspace-runtime.ts`：现有客户端的流传输接线。
- Lody `packages/components/src/hooks/use-session-actions.ts` 与 `packages/components/src/components/sessions/session-chat-interface.tsx`：用户 turn 写入及派发流程。
- Lody `packages/components/src/hooks/use-permission-response.ts` 与 `packages/shared/src/history-writer.ts`：权限响应的写入路径。

## 聊天键盘布局参考

- 参考 FlowDown `a2fd55911720bfa0d11c1d4e354359d4801d9387` 的 `MainController+Content.swift`、`ChatView.swift` 和 `MessageListView.swift` 中键盘布局、输入区 inset、手动滚动暂停跟随的机制；Kurage 使用系统 UITableView 与 UIHostingConfiguration 实现，不引入其依赖。
