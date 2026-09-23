# Kurage 会话功能

## 当前状态

- 设备码登录、账号恢复、退出登录和工作区列表已经接入 Lody。
- 工作区选择和下拉刷新已接入真实会话列表；所有会话操作都明确携带工作区 ID。
- 会话列表默认按项目分组，项目按最近会话排序；右上角菜单可切换到按时间排序，也包含退出登录。项目名称优先从机器 Flock 文档读取。
- `HTTPLodyClient.streamsAccess(workspaceID:)` 按 Lody 的 `/api/loro-streams/token` 协议取得短期令牌，不会把 Streams 令牌写入 Keychain。
- `SessionSyncBridge` 使用与 Lody 相同版本的 LoroRepo、Flock 和 Streams 库，在本地 WebKit 页面中读取目录与会话文档。原生层通过 URLSession 代理只读 Streams 请求。
- 真实客户端已支持只读会话正文；只投影用户和 Agent 的普通文本，工具记录等结构化内容暂不显示。会话支持下拉刷新、运行状态提示和 MarkdownView 渲染。
- `send`、`respond` 尚未接入真实客户端，真实账号显示只读状态；fixture 中的对话和权限操作用于预览与 UI 测试。

## 验证与后续

1. 已在真机打开真实会话并确认正文；继续用长会话验证首次底部定位和读取耗时。模拟器 UI 测试运行器目前未能完成启动。
2. 核对后台返回和工作区切换后的刷新行为，必要时接入增量订阅。
3. 在只读路径稳定后，确认 Lody 的请求 ID、重试和去重语义，再接入发送、权限响应、通知和 Diff。

## 之后的增量

权限操作在 fixture 中使用系统确认对话框；真实写入路径仍待接入。

## 协议核对入口

- Lody `packages/shared/src/loro-streams-auth.ts`：工作区 Streams 令牌请求及刷新。
- Lody `packages/shared/src/index.ts`：工作区目录与 Session 流 ID。
- Lody `packages/shared/src/schema.ts`：工作区目录、Session 元数据和会话文档结构。
- Lody `packages/components/src/providers/create-workspace-runtime.ts`：现有客户端的流传输接线。
