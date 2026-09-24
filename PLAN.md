# Kurage 会话功能

## 当前状态

- 设备码登录、账号恢复、退出登录和工作区列表已经接入 Lody。
- 工作区选择和下拉刷新已接入真实会话列表；所有会话操作都明确携带工作区 ID。
- 会话列表默认按项目分组，项目按最近会话排序；右上角菜单可切换到按时间排序，也包含退出登录。项目名称优先从机器 Flock 文档读取。
- `HTTPLodyClient.streamsAccess(workspaceID:)` 按 Lody 的 `/api/loro-streams/token` 协议取得短期令牌，不会把 Streams 令牌写入 Keychain。
- `SessionSyncBridge` 使用与 Lody 相同版本的 LoroRepo、Flock 和 Streams 库，在本地 WebKit 页面中读取目录与会话文档。原生层通过 URLSession 代理只读 Streams 请求。
- 真实客户端已支持只读会话正文和实时更新：当前详情页通过 `joinRoom()` 订阅 Session 文档与 workspace metadata，持续显示正文和运行状态。只投影用户和 Agent 的普通文本，工具记录等结构化内容暂不显示。
- 原生网络桥用 `URLSession.bytes(for:)` 将响应头与数据块交给 JS `ReadableStream`，包含背压和 AbortSignal 取消；Streams 库继续负责 SSE、long-poll 回退与重连。鉴权回调按需续期，401/403 强制重新获取令牌。
- JS 合并 80ms 内的变化并按 turn ID 发送正文补丁；Swift 在桥内先还原完整快照，再通过仅保留最新值的异步流交给界面，避免丢弃中间补丁导致正文缺失。
- 页面离开或进入后台释放订阅，回到前台重新同步；工作区和账号切换丢弃迟到更新。底部阅读时跟随同一条回复增长，上翻阅读时停止自动跟随。
- `send`、`respond` 尚未接入真实客户端，真实账号显示只读状态；fixture 中的对话和权限操作用于预览与 UI 测试。

## 验证与后续

1. 实时链路已通过 8 项 JS 测试与 26 项 iOS 模拟器 Swift 测试。覆盖消息增长/删除、订阅取消、工作区隔离、分块 UTF-8 和背压；原生 WebKit 集成测试确认 SSE 未结束时可收到数据，并能取消底层请求。现有 3 项 UI 测试（长会话底部定位、列表模式、详情权限/发送）通过。
2. 仍需真机连接正在运行的真实 Lody 会话，验证持续输出、断网恢复和后台返回。当前 JS 在正文变化时仍按节流周期投影完整 history；超长会话的窗口化读取是后续性能工作。
3. 在只读路径稳定后，确认 Lody 的请求 ID、重试和去重语义，再接入发送、权限响应、通知和 Diff。

## 之后的增量

权限操作在 fixture 中使用系统确认对话框；真实写入路径仍待接入。

## 协议核对入口

- Lody `packages/shared/src/loro-streams-auth.ts`：工作区 Streams 令牌请求及刷新。
- Lody `packages/shared/src/index.ts`：工作区目录与 Session 流 ID。
- Lody `packages/shared/src/schema.ts`：工作区目录、Session 元数据和会话文档结构。
- Lody `packages/components/src/providers/create-workspace-runtime.ts`：现有客户端的流传输接线。
