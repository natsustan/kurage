# Kurage 下一阶段：只读对话

## 当前状态

- 设备码登录、账号恢复、退出登录和工作区列表已经接入 Lody。
- 工作区选择和下拉刷新已接入真实会话列表；所有会话操作都明确携带工作区 ID。
- 会话列表默认按项目分组，项目按最近会话排序；右上角菜单可切换到按时间排序，也包含退出登录。项目名称优先从机器 Flock 文档读取。
- `HTTPLodyClient.streamsAccess(workspaceID:)` 按 Lody 的 `/api/loro-streams/token` 协议取得短期令牌，不会把 Streams 令牌写入 Keychain。
- `SessionSyncBridge` 使用与 Lody 相同版本的 LoroRepo、Flock 和 Streams 库，在本地 WebKit 页面中解码工作区目录，只投影会话元数据。原生层通过 URLSession 代理只读 Streams 请求。
- 模拟器中的正式账号已成功同步目录，并显示了 15 个未归档的顶层会话。`conversation`、`send`、`respond` 尚未接入真实客户端；fixture 中的对话和权限操作只用于预览与 UI 测试。

## 下一次交付：只读对话

1. **投影对话。** 复用本地桥接层读取 `workspaceId:s:sessionId` 流，先显示用户文本、Agent 文本和运行状态。复杂工具记录不能被误显示为普通文本。
2. **状态与失效。** 核对令牌过期、断网重连、后台返回和工作区切换；确保失败时保留已显示的会话并给出清晰提示。
3. **验收。** 用模拟器已登录账号打开已有会话，并用合成数据覆盖文档投影、工作区隔离及失效路径。

## 之后的增量

只读路径稳定后，依次接入发送后续消息、权限请求、通知与 Diff。每项写操作都要先确认 Lody 的请求 ID、重试和去重语义。

## 协议核对入口

- Lody `packages/shared/src/loro-streams-auth.ts`：工作区 Streams 令牌请求及刷新。
- Lody `packages/shared/src/index.ts`：工作区目录与 Session 流 ID。
- Lody `packages/shared/src/schema.ts`：工作区目录、Session 元数据和会话文档结构。
- Lody `packages/components/src/providers/create-workspace-runtime.ts`：现有客户端的流传输接线。
