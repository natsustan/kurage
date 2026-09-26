# Kurage 会话功能

## 当前状态

- 设备码登录、账号恢复、退出登录和工作区列表已经接入 Lody；发送使用当前账号的用户 ID 标记 turn。
- 工作区选择和下拉刷新已接入真实会话列表；所有会话操作都明确携带工作区 ID。
- 会话列表默认按项目分组，项目按最近会话排序；点击项目名称行可折叠/展开该项目下的会话，折叠显示闭合文件夹图标、展开显示开口文件夹图标（MGC cute light 系列，已做成 template 资产）。右上角菜单可切换到按时间排序，打开 Archived sessions，也包含退出登录。项目名称优先从机器 Flock 文档读取。
- 会话列表的原生 UITableView 接入下拉刷新，空状态也保留可刷新的滚动容器。底部浮着一条 Liquid Glass 搜索胶囊，列表滚到它下面。匹配会话标题，以及用户和 Agent 的普通文本正文；命中正文且标题不命中时，在标题下显示那一行。列表元数据没有正文，开始搜索后逐个读取会话文档，结果只留在内存里，列表刷新后重新读取。一次性正文读取在成功、失败或取消后卸载 CRDT 文档；正在订阅或等待订阅的同一会话保留文档。详情实时更新只标记缓存正文待索引，搜索恢复时再生成文本。打开会话或进入后台时取消正在进行的正文同步并暂停索引，取消经 operation ID / AbortSignal 传到同步桥；返回前台且无详情订阅时恢复。工具记录等未投影内容不参与搜索。真实账号上大量会话的搜索耗时尚未验证。
- 会话行可向左滑出 Archive。确认后按 Lody 的归档协议处理：目标会话及其子会话写入 `isArchived` 和 idle 状态，同步并核对 metadata 后确认成功。机器观察归档状态后释放运行时；不再写入或等待已废弃的 `archiveSession` 命令和 `needToArchiveSessions` 队列。列表仍只显示未归档的根会话。机器侧是否真正清理工作区尚未用真实账号验证。
- Archived sessions 以非全屏弹窗列出已归档且没有 `parentSessionId` 的根会话，按 `lastMessageAt`（没有则用 `createdAt`）倒序。行尾仅提供无底色的 Restore；永久删除入口暂不显示，交互待定。Restore 把该会话和它的直接子 tab 的 `isArchived` 写回 false，并只给被点的会话清掉 `isTabClosed`；由它打开的其它会话仍留在归档里。本地项目若已从机器 Flock 移除或有待删除命令，则拒绝恢复。底层 Delete 实现会先删子 tab 再 `deleteDoc` 根会话，机器通过文档删除标记回收运行时。归档列表刷新成功后清除加载错误，保留独立的恢复操作提示。真实账号的恢复和永久删除尚未验证。
- `HTTPLodyClient.streamsAccess(workspaceID:)` 按 Lody 的 `/api/loro-streams/token` 协议取得短期令牌，不会把 Streams 令牌写入 Keychain。
- `SessionSyncBridge` 使用与 Lody 相同版本的 LoroRepo、Flock 和 Streams 库，在本地 WebKit 页面中同步目录与会话文档。原生层通过 URLSession 代理 Streams 请求。
- 真实客户端已支持只读会话正文和实时更新：当前详情页通过 `joinRoom()` 订阅 Session 文档与 workspace metadata，持续显示正文和运行状态。投影用户和 Agent 的普通文本，以及 history 里的 `image` / `image_group`（也保留没有 `mimeType` 的图片引用）。图片用当前账号的 Bearer 令牌从 `https://api.lody.ai/api/workspaces/{workspace}/session-images/{session}/{imageId}` 下载；fork 复制的图片用 `storageSessionId` 作为 blob 所在 session。详情里单张图走 `thumbnail?width=768&fit=scale-down&quality=85`，多张图走 320 正方形 cover，失败时回退原图，点按后看原图。工具记录等其他结构化内容暂不显示。相同图片请求共享下载，取消单个等待者不影响其它等待者，最后一个等待者退出时取消网络请求。下载先检查响应长度，并在流式累计超过 5 MiB 时中止；多图布局按聊天区域可用宽度缩小方形缩略图。真实账号的图片下载尚未实测。
- 原生网络桥用 `URLSession.bytes(for:)` 将响应头与数据块交给 JS `ReadableStream`，包含背压和 AbortSignal 取消；写请求的请求体也由原生代理发送。Streams 库继续负责 SSE、long-poll 回退与重连。鉴权回调按需续期，401/403 强制重新获取令牌。
- JS 合并 80ms 内的变化并按 turn ID 发送正文补丁；Swift 在桥内先还原完整快照，再通过仅保留最新值的异步流交给界面，避免丢弃中间补丁导致正文缺失。
- 页面离开或进入后台释放订阅，回到前台重新同步；工作区和账号切换丢弃迟到更新。底部阅读时跟随同一条回复增长，上翻阅读时停止自动跟随。
- 真实客户端现可向空闲会话发送普通文本：独立的短生命周期 Streams 副本先确认正文同步，再写入 `latestUserMsgId` 并确认 metadata 同步。写前重新同步并检查派发指针，写后确认指针仍指向本次 turn；现有 LoroRepo metadata 写入没有 CAS，跨客户端同时写入时仍不能保证绝对互斥。未确认的发送保留 turn ID；改发文本前须先重试旧消息，防止留下未派发的历史记录。旧 turn 已被较新的派发取代时会废弃旧重试 ID。发送成功后会话列表立即更新最近排序，并从服务端刷新。权限响应仍只在 fixture 中可用。
- 运行中的会话在输入区显示停止按钮，保留未发送草稿；具备 `supportsTextSendingWhileRunning` 的客户端（目前仅 fixture）同时保留发送按钮，真实客户端仍只显示停止操作；点按后从已同步的原始 history 找出最新未完成的 assistant turn，将其 ID 写入 `lastCanceledTurn` 并确认 metadata 同步。若 turn 尚未出现或已经结束，会提示重试。真实机器的停止响应仍待实测。
- 会话内 model/reasoning：输入区第一行输入文字，第二行放置操作按钮；带刻度的仪表盘图标随 reasoning 档位变化。点击后打开无箭头浮层，model/reasoning 标签位于玻璃刻度胶囊外；离散 reasoning 刻度支持点选、拖动及 VoiceOver 调整，点击模型进入 Advanced 表单。浮层打开时使用仅内存中的页面快照做渐变模糊，关闭即释放，系统键盘保留清晰显示。新建会话的 provider/model/reasoning 共用此入口，选项仍遵循代理能力；Fast 暂不可用，尚未接入真实协议。观察器从机器 Flock 文档 `${workspace}:mf:${machineId}` 的 `['acpCapability', agentConfigId]` 读取能力（cliType/agentType 须与会话一致），当前值依次取与最新用户 turn 对应的 `acpRuntimeConfig`、该 turn 的 `inputConfig`、能力的 `currentValue`。能力含 reasoning 选项（`reasoning_effort` 或 `thought_level` 类别）时只允许改 reasoning（若有 `modelReasoningEfforts` 则按当前模型过滤），以免中途换模型破坏上下文缓存；否则允许改 model（builtin 写 `modelId`，registry/custom 写对应 config option）。无能力记录时只读显示。界面和新 turn 发送共用与最新用户 turn 匹配的运行时配置基线，运行时 configOptionValues 作为完整快照替换旧值。选择仅作用于下一条新 turn，页面离开即丢弃；未确认发送的重试沿用首次发送时的选择；发送层返回实际沿用的选择，界面仅清除已发送的选择，重试时新选的配置保留给下一轮，包括明确选回原基线的值；普通发送与“Retry earlier message”入口均更新实际配置基线。运行中可预选。尚未用真实账号验证 CLI 对切换值的实际应用。
- 新建会话：按项目分组时，本地项目行右侧有新建按钮（未分组与 GitHub 项目不显示），进入独立页面后以第一条消息创建会话。机器、Agent 配置和本地项目取自该项目最近的根会话（模板），项目引用只保留 `localProjectId` / `githubRepoFullName`，不带 worktree 和分支，即直接在项目目录工作。第一条 turn 继承模板最新用户 turn 的有效配置中的 `modeId`、`modelId`、`configOptionValues`、`mcpServerIds`（不继承 Agent Role 与 `resume`），model 与 reasoning 都可在页面上选择：选项来自机器 Flock 的 `acpCapability`，reasoning 按所选模型的 `modelReasoningEfforts` 过滤，切到不支持当前 reasoning 的模型时不写 reasoning，由 Agent 默认值决定；桥在写入时重新投影并拒绝未提供的选项。写入使用独立短生命周期副本，只有它开启 `createStreamIfMissing` 以创建新 Session 文档流（对应 Lody 的 `ensureDocStream`）：先同步第一条 turn，再一次写入 metadata（`status: idle`、`title` 取前 50 字且 `titleSource: 'draft'`、`latestUserMsgId`）并确认同步，因此机器看到会话时正文已就绪。未确认时按项目在进程内保留会话 ID 与 turn ID，重试沿用首次的选择；改了文本须先重发原文。成功后替换为会话详情页，列表乐观插入后在后台刷新。Lody 桌面端创建会话前会在客户端检查免费会话额度，Kurage 没有这一步，需在 issue 中跟进。真实账号的新建、机器派发与首轮 model/reasoning 生效尚未验证。
- 新建会话配置在页面内预取并缓存各 provider 的选项，共享同一 provider 的在途请求；已缓存 provider 切换及 model/reasoning 选择立即更新本地状态，往返切换保留各自选择。尚未加载的 provider 立即显示新名称和加载状态，不展示旧模型，不允许发送；迟到结果不会覆盖新选择，页面离开或进入后台取消请求。缓存随页面释放，写入时仍由桥重新校验能力。真实账号首次加载耗时尚未测量。
- 会话底部输入区使用悬浮的 Liquid Glass 胶囊；点按发送后立即清空草稿并保持键盘，若发送未确认则恢复原文供重试。
- 聊天区域由 UIKit 容器协调：`keyboardLayoutGuide` 同步调整消息列表与输入区，通过几何测量将整个输入区的实际高度同步给 UIKit 约束并设置列表 inset；SwiftUI 保留消息样式和输入控件。消息按 turn ID 在原生列表中复用和更新，布局与正文高度变化时仅在跟随模式下贴底；上翻阅读时保存消息 ID 与其可视位置，回到底部或发送新消息恢复跟随。短会话仍贴近输入区。

## 验证与后续

1. 发送功能阶段已记录通过 19 项 JS 测试与 36 项 iOS 模拟器 Swift 测试（参数化共 38 次运行），包括正文同步后派发、同 ID 重试、写请求体代理、分块 UTF-8 和原生 WebKit POST。会话发送与长会话 UI 用例已在 iOS 27 模拟器通过；截图确认第二次打开键盘时最新消息仍贴近输入区，测试也确认上滑后打开键盘不会跳回底部。
2. 真实账号的只读会话已由用户实测，反馈可用；持续输出、断网恢复和后台返回各场景的结果尚未逐项记录。当前 JS 在正文变化时仍按节流周期投影完整 history；超长会话的窗口化读取是后续性能工作。
3. 文本发送已按 Lody 桌面端的用户 turn 与 `latestUserMsgId` 协议接入。用户已用真机上的 Kurage 向真实会话发送消息，且消息抵达当前会话，验证了一次正常网络下的发送与派发；网络中断时的确认、重启后的重试仍未验证。运行中 steer、排队消息和权限响应有各自协议，本阶段只允许空闲会话直接派发。下一步再将匹配 `requestId` 的权限响应写入对应 `tool_call`，最后考虑通知和 Diff。

4. 本轮 UIKit 键盘布局改动通过 iOS 27 模拟器的 2 项布局回归测试与 3 项聊天 UI 测试，覆盖正文增长/删除、阅读消息锚点保持、发送恢复贴底、键盘反复开合和五行输入区完整避让。同一多行 UI 用例也在深色模式与系统 XXXL 字号下通过；截图已确认输入区整体随多行文字增高，发送后恢复单行，文字和发送按钮未被键盘遮挡。真机动画手感与真实账号持续输出尚未在本轮验证。

5. 本轮分支审查修复通过 56 项 JS 测试、69 项 Swift 测试，以及列表/空列表两种下拉刷新宿主集成用例；4 项 fixture UI 测试通过，覆盖列表切换、搜索、归档确认和图片预览；扩展搜索用例另在暗色和最大辅助字号下通过，截图确认无结果空态与搜索框可读，并覆盖空态/列表下拉。取消回归覆盖正文读取释放同步队列、后台暂停/前台恢复、共享图片下载的单个与最后一个等待者取消。归档测试覆盖机器命令不可用及旧队列被清理后的成功确认。真实服务弱网和机器清理行为仍待验证。

6. 本轮分支审查的六项修复通过 61 项 JS 测试与 73 项 Swift 测试（包含参数化运行）。新增回归覆盖运行时配置基线与重试不改写、搜索文档在成功/失败/取消后的释放、观察中的文档保留、实时正文延迟索引、归档加载错误清理，以及有无 Content-Length 的图片超限提前中止。桥接 bundle 已重新生成。4 项 fixture UI 场景通过，覆盖搜索、配置菜单、归档恢复和三图边界/预览；图片用例另在 iPhone 17e 的深色模式与最大辅助字号下通过，截图确认三图方形、边距和预览比例正常。预览页固定深色外观，保持黑底上的导航标题可读。真实账号下的运行时模型切换、大量会话内存占用及图片弱网仍待验证。

## 之后的增量

权限操作在 fixture 中使用系统确认对话框；真实写入路径仍待接入。文本发送的重试 ID 当前只保存在进程内；重启后若先前请求结果未知，需检查真实会话后再重新发送。

## 协议核对入口

- Lody `packages/shared/src/loro-streams-auth.ts`：工作区 Streams 令牌请求及刷新。
- Lody `packages/shared/src/index.ts`：工作区目录与 Session 流 ID。
- Lody `packages/shared/src/schema.ts`：工作区目录、Session 元数据和会话文档结构。
- Lody `packages/components/src/providers/create-workspace-runtime.ts`：现有客户端的流传输接线。
- Lody `packages/components/src/hooks/use-session-actions.ts` 与 `packages/components/src/components/sessions/session-chat-interface.tsx`：用户 turn 写入及派发流程。
- Lody `packages/components/src/hooks/use-session-actions.ts` 与 `packages/shared/src/schema.ts`：会话停止使用 assistant turn ID 和 `lastCanceledTurn` metadata。
- Lody `packages/components/src/hooks/use-session-actions.ts` 的 `archiveSession`、`packages/components/src/lib/session-lifecycle.ts` 与 `apps/cli/src/lib/message-handler.ts`：归档级联子会话，以会话 `isArchived` 为完整请求；机器观察状态回收运行时，启动时清理旧归档命令和队列。
- Lody `packages/components/src/hooks/use-session-actions.ts` 的 `restoreSession` / `deleteArchivedSession`、`packages/shared/src/session-operation-targets.ts` 与 `apps/cli/src/lib/message-handler.ts` 的 session lifecycle watcher：恢复只清 `isArchived`，删除以 `deleteDoc` 为信号；直接子 tab 跟随根会话，打开出来的会话各自独立。
- Lody `packages/shared/src/acp-run-config.ts`、`packages/components/src/components/shared/acp-selector-options.ts` 与 `packages/shared/src/machine-flock.ts`：model/reasoning 选项解析、能力缓存位置；`packages/shared/src/schema.ts` 的 `SessionAcpRuntimeConfigSnapshot`。
- Lody `packages/shared/src/ai.ts` 的 `SessionImagePayload`、`packages/shared/src/session-image.ts`，以及 `packages/components/src/lib/session-image-gallery.ts`：会话图片 metadata、下载路径和 `storageSessionId`。
- lody-ios `apps/mobile/modules/lody-kit/ios/Cloud/SessionAttachments.swift` 和 `ios/Chat/ChatImageCell.swift`：图片下载使用 `api.lody.ai`，缩略图失败后回退原图；`data-runtime/project.ts` 的图片投影也保留缺少 `mimeType` 的 `image_group` 成员。
- Lody `packages/components/src/hooks/use-session-actions.ts` 的 `buildSessionCreateResult` / `startSession` / `requestSessionDispatch`、`components/onboarding/screens/first-task-screen.tsx` 与 `providers/create-workspace-runtime.ts` 的 `ensureDocStream`：新建会话的 metadata 字段、第一条 turn 与派发指针、新文档流创建；免费额度检查在 `assertSessionCreateAllowed`。
- Lody `packages/components/src/hooks/use-permission-response.ts` 与 `packages/shared/src/history-writer.ts`：权限响应的写入路径。

## 聊天键盘布局参考

- 参考 FlowDown `a2fd55911720bfa0d11c1d4e354359d4801d9387` 的 `MainController+Content.swift`、`ChatView.swift` 和 `MessageListView.swift` 中键盘布局、输入区 inset、手动滚动暂停跟随的机制；Kurage 使用系统 UITableView 与 UIHostingConfiguration 实现，不引入其依赖。

- PR #9 弱网一致性修复：归档确认返回完整生命周期的文档会话 ID，本地立即移除所有受影响行及正文/搜索缓存，不依赖后续列表刷新成功。搜索正文读取失败会清除旧索引并显示可重试的不完整状态；成功重试后清除提示。列表使用稳定容器保留搜索框，结果与空状态切换时不丢失输入焦点。真实账号下的断网与级联归档仍待实测。

- PR #9 工作区隔离修复：详情页以工作区切换 generation 和会话 ID 重建状态所有者，清空旧配置/草稿，重连和前后台切换不重置选择。Restore/Delete 在途操作按工作区与操作 UUID 隔离；切换后旧结果不更新当前 UI，返回原工作区仍保留在途锁以阻止重复写入。

- PR #9 最新审查修复：逐模型 reasoning 映射明确为空时保持只读，不回退全局选项；能力包含 reasoning 选项但无可用值时也不开放模型切换。活动列表归档在 AppModel 中按工作区和操作 UUID 保留在途锁，以认证和工作区 generation 隔离旧结果与错误；返回原工作区时阻止重复归档，切换工作区清除旧警告。本轮 63 项 JS 测试、84 项 Swift 测试及 2 项 fixture UI 测试（归档确认、reasoning 选择）通过，bundle 已重新生成；新增延迟请求回归覆盖 A→B、A→B→A 和旧请求成功/失败。真实账号弱网行为仍待实测。

- 本轮输入区配置样式：完成档位按钮、reasoning 点选/拖动刻度和 Advanced 表单；Advanced 出现时清除输入焦点，避免弹层关闭恢复的键盘遮住配置；Fast 依用户决定暂不可用。通过 19 项 fixture Swift 测试、浅色的会话配置/新建会话 2 项 UI 测试，以及 iPhone 17e 深色 XXXL 的刻度交互/多行键盘 2 项 UI 测试。iPhone 17 首轮多行发送后键盘即时命中断言失败，断言改为最多等待 5 秒后，在 iPhone 17e 复验通过；真机键盘动画、VoiceOver 操作与真实账号配置生效仍待验证。

- 本轮配置样式细化：将操作按钮移至输入区第二行，增加随 reasoning 变化的仪表刻度，模型标签移到无箭头刻度胶囊外，Advanced 选择直接更新显示。通过 19 项 fixture Swift 测试和 4 项配置状态测试，覆盖 provider 预取、共享请求、失败重试、选择保留及旧响应隔离；浅色 3 项 UI 场景覆盖配置、新建会话和多行键盘，深色 XXXL 下配置与新建会话 2 项 UI 场景通过。Fast 仍暂不可用；真实账号切换延迟与真机动画待验证。

- Reasoning 档位修正：展示层按已知强度由低到高排列 provider 返回的选项，协议 value 不变，未知选项保留原位置；刻度、Advanced 和仪表使用同一顺序。没有可用 reasoning 刻度时仪表默认满档。设置打开期间保留原指针，关闭浮层或 Advanced 完全消失后再平滑转到新档位；开启 Reduce Motion 时直接更新。本轮 22 项 Swift 测试与配置 UI 回归通过，包含乱序强度、别名/未知值保留和无 reasoning 满档。最终模拟器录屏确认 Advanced 收起后，指针从 High 经中间角度转到 Low，亮刻度同步减少；真机手感待验证。

- 推理仪表盘为无推理保留零基准，Low 等非零档位不指向零位；滑条只展示实际可选档位，从 Low 等最低有效档开始，不增加虚拟 None 刻度。Advanced 左侧标签与右侧选项使用相同的自适应中性色，仅右侧选项可点击。


- 新建会话分支审查修复：导航使用带页面实例 ID 的类型化路由，迟到的创建结果只替换对应的新建页，返回列表或另开页面后不再修改导航。切换模型时桥会清除不受新模型支持的继承 reasoning，保留其它配置。创建返回 `rejected` 仅限已同步确认新文档没有首轮、且模板/配置准备失败的情况；原生层释放该项目的待重试配置并刷新页面选项，已写入首轮或结果未知时继续保留原 ID 与配置。选项加载通过 operation ID 将取消传到 metadata、机器 Flock 和历史同步；每次加载使用仅内存的认证别名关联 fetch 的 AbortSignal，原生代理仍以真实 Streams token 发请求，退出时销毁临时副本并清除别名。该关联补足底层 Streams 库关闭副本时不取消一次性 fetch 的行为。真实账号弱网与机器派发仍待验证。

  本轮验证通过 78 项 JS 测试、97 项 Swift 测试及 1 项新建会话 fixture UI 测试，桥接 bundle 已重建。新增原生取消集成用例最初暴露一次性 fetch 未取消，补齐操作级 fetch 信号后通过；最后清理冗余状态后，3 项原生网络桥测试再次通过。回归覆盖迟到导航、跨模型 reasoning、拒绝后重建、已写入首轮的重试保护，以及配置读取取消与请求隔离。

- PR #10 最新审查修复：新建会话按账号、工作区和项目持有在途锁，页面重开后的重复提交在旧请求结束前返回未确认提示，不再启动第二个写入副本；请求失败或取消后释放锁，保留原来的重试 ID 和配置。退出登录清除锁，旧操作只可释放自己的 UUID，获取 Streams 访问权限后再次检查认证 generation。没有 `agentConfigId` 的旧版模板直接读取所选模板文档的有效配置，并沿用继承字段白名单，不按空 ID 搜索其它旧会话。
  本轮通过 79 项 JS 测试和 98 项 Swift 测试（新增参数化用例分别覆盖失败与取消），bundle 已重建；回归覆盖同项目并发阻止、跨项目/工作区独立、失败与取消后的重试，以及旧模板配置继承和非继承字段排除。真实账号弱网创建与机器派发仍待验证。

- PR #10 再审修复：同账号、工作区和项目的相同文本创建请求共享在途操作及其最终会话 ID，不再向第二个页面返回需要重试的未确认提示。单个等待者取消只移除自己的等待，所有等待者离开后仍保留正在执行的写入，供重新进入的页面接续；退出登录取消共享任务并通知所有等待者，operation UUID 与认证 generation 阻止旧操作影响重新登录后的创建。未确认失败继续保留首次 ID 和配置。通过可注入的窄范围 SessionStarting 接口验证真实 HTTP 客户端的创建协调逻辑，无需访问真实会话。
  本轮完整 98 项 Swift 测试通过；补充唯一等待者取消后重新加入的场景后，22 项 HTTP 客户端测试再次通过，共享创建参数化用例覆盖成功、未确认、单等待者取消、全部等待者暂时离开和重新登录五种情形，并检查跨项目/工作区隔离。未修改 JS 桥代码，未重跑 JS 测试；真实账号弱网与机器派发仍待验证。

- PR #10 provider 再审修复：先构建完整的 provider 列表，再解析当前选择；模板 agent 缺少 ID 或已从机器 Flock 列表移除时，仍始终保留为可继承选项，切换到其它 provider 后可直接切回。正常 provider 不重复添加，未知的显式选择仍被拒绝。新增 JS 回归覆盖旧模板、已移除配置及正常配置的往返选择和继承创建；82 项 JS 测试通过，bundle 已重建。真实账号 provider 配置变化仍待验证。
  本轮新建会话 fixture UI 回归 `testProjectRowStartsNewSessionWithChosenModel` 通过，覆盖 provider 往返切换、模型选择和创建导航；该 UI 用例使用 fixture，旧模板列表问题由上述 JS 回归直接验证。
