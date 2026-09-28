# Kurage 会话功能

## 当前状态

- 已读／未读：列表接入 Lody `lastMessageAt` / `lastReadAt`，空闲未读会话显示蓝点，运行中保留 spinner，VoiceOver 同时读出运行与阅读状态。详情仅在前台可见、实时同步完成、未被图片／变更／子任务面板遮挡，且对应正文完成布局并实际到达底部时写回执；用户上滚时暂停，回到底部后恢复。搜索预加载不写回执。
- 回执同步：metadata 与正文独立到达；同步前后复核消息时间，变化时保留正文比较基线重新拉取，最多五次，失败／取消走已有重试或重连路径。观察与搜索共享按仓库、工作区、会话和 Loro 版本隔离的同步证据，可跨文档卸载复用；未知且没有可见变化的缓存仍保守保留未读。每会话仅保留紧凑版本和时间，不持久化正文证据或跨账号复用。
- 列表与缓存：流式更新只接受更大的有限消息时间，列表刷新保留已知的较新消息时间，更新后按活动时间重排并保存缓存；无消息时间时使用创建时间排序。已读回执若中断正在进行的列表刷新，会启动替代刷新；无刷新时不额外请求。保留工作区隔离、旧请求结果丢弃和旧缓存兼容性。
- 协议参考：Lody `use-session-actions.ts` 的 `markSessionRead` / `buildSessionActivityPatch`、`lib/session-read-receipt.ts`。当前协议没有将活动时间绑定到正文版本，子会话活动也可能更新父会话时间。

### PR #15 验证历史（按代码版本）

以下是各提交对应工作树在提交前执行或记录的验证，不表示对之后版本重新运行。当前文档修订仅检查文档差异及 `git diff --check`，未重新运行应用测试或构建。

| 代码提交 | 变更 | 对应版本的验证记录 |
| --- | --- | --- |
| `5f88351` | 初始已读／未读 | 该提交历史文档记录：128 项 JS、126 项 Swift、23 项 fixture 单元复跑、bundle 重建，以及浅色／深色大字号已读 UI 检查通过。这些记录本次未重新验证。 |
| `c258b32` | 先同步正文再发布回执时间 | 该提交历史文档记录：133 项 JS、bundle 重建和 Simulator 构建通过。本次未重新验证。 |
| `bf52cdb` | 首次正文比较基线 | 137 项 JS、frozen lockfile 安装和 bundle 重建通过；该次未运行 iOS 测试。 |
| `e539a7c` | 列表重排及恢复被中断的刷新 | 138 项 JS、128 项 Swift、bundle 重建通过；补强排序断言后相关测试复跑通过。 |
| `88bd763` | 跨文档卸载保留预加载证据 | 142 项 JS、128 项 Swift、bundle 重建通过。 |
| `fc4fec6` | 同步期间时间变化与列表时间倒退 | 146 项 JS、129 项 Swift、bundle 重建通过；补强断言后相关 5 项 Swift 测试复跑通过。 |
| `fafad3a` | 回执要求正文布局完成并实际到达底部 | 131 项 Swift 单元测试复跑通过；已读切换和长会话首次定位／上滚保持两项 fixture UI 用例通过，截图检查正文／输入布局正常。该版本未重新运行 JS 测试或桥接重建，桥接代码和 bundle 沿用 `fc4fec6`。 |

`fafad3a` 验证限制：多行键盘用例在发送后 `keyboard.isHittable` 断言失败，修改前 `fc4fec6` 在独立 worktree、相同模拟器设置下也失败于同一断言，未发现由该布局修复引入的键盘回归。基线测试收尾异常，结果包未封口；基线失败位置有日志记录，不能声称整个 UI 测试集通过。该版本未重测深色或大字体；真实账号的持续输出、跨端乱序、网络恢复和后台切换仍未验证。

### 其它功能状态

- 会话管理：列表长按与详情页右上角 ··· 提供 Pin/Unpin、Rename session、Copy Session URL 和红色 Archive。Pinned 单独置顶分组，项目/时间列表不重复显示；项目全部置顶时仍保留本地项目的新建入口。详情页置顶、取消置顶和重命名后留在会话，归档成功后返回。Pin 使用 Lody `isPinned`，重命名写入 `title` 与 `titleSource: user`，独立副本同步并核对 metadata 后更新缓存；复制 `https://lody.ai/{workspaceSlug}/sessions/{sessionID}`，不创建公开分享。旧磁盘缓存缺少置顶字段仍可读取。协议参考 `use-session-actions.ts` 的 `setSessionPinned` / `updateSessionTitle` 与 `loro-app-sidebar.tsx` 的 `copySessionUrl`。本轮 119 项 JavaScript 测试、bundle 重建与 123 项 Swift 测试通过；新增两项 fixture UI 测试在浅色默认字号、深色辅助大字号通过，覆盖两处菜单、项目/时间模式的 Pinned、重命名标题更新、URL 粘贴与归档返回，原有左滑归档回归通过。截图核对菜单红色 Archive 与大字号换行正常。真实账号跨端同步尚未验证。

- 设备码登录、账号恢复、退出登录和工作区列表已经接入 Lody；发送使用当前账号的用户 ID 标记 turn。
- 工作区选择和下拉刷新已接入真实会话列表；所有会话操作都明确携带工作区 ID。
- 会话列表默认按项目分组，项目按最近会话排序；点击项目名称行可折叠/展开该项目下的会话，折叠显示闭合文件夹图标、展开显示开口文件夹图标（MGC cute light 系列，已做成 template 资产）。右上角菜单可切换到按时间排序，打开 Archived sessions，也包含退出登录。项目名称优先从机器 Flock 文档读取；详情标题下显示项目名称与 workspace metadata 中的机器名称，缺失字段不显示。连接状态延迟 1 秒后在标题旁的固定位置显示小图标，持续 5 秒时在输入区上方显示文字，不再给导航栏增加第三行。
- 会话列表的原生 UITableView 接入下拉刷新，空状态也保留可刷新的滚动容器。底部浮着一条 Liquid Glass 搜索胶囊，列表滚到它下面。匹配会话标题，以及用户和 Agent 的普通文本正文；命中正文且标题不命中时，在标题下显示那一行。列表元数据没有正文，开始搜索后逐个读取会话文档，结果只留在内存里，列表刷新后重新读取。一次性正文读取在成功、失败或取消后卸载 CRDT 文档；正在订阅或等待订阅的同一会话保留文档。详情实时更新只标记缓存正文待索引，搜索恢复时再生成文本。打开会话或进入后台时取消正在进行的正文同步并暂停索引，取消经 operation ID / AbortSignal 传到同步桥；返回前台且无详情订阅时恢复。工具记录等未投影内容不参与搜索。真实账号上大量会话的搜索耗时尚未验证。
- 会话行可向左滑出 Archive。确认后按 Lody 的归档协议处理：目标会话及其子会话写入 `isArchived` 和 idle 状态，同步并核对 metadata 后确认成功。机器观察归档状态后释放运行时；不再写入或等待已废弃的 `archiveSession` 命令和 `needToArchiveSessions` 队列。列表仍只显示未归档的根会话。机器侧是否真正清理工作区尚未用真实账号验证。
- Archived sessions 以非全屏弹窗列出已归档且没有 `parentSessionId` 的根会话，按 `lastMessageAt`（没有则用 `createdAt`）倒序。行尾仅提供无底色的 Restore；永久删除入口暂不显示，交互待定。Restore 把该会话和它的直接子 tab 的 `isArchived` 写回 false，并只给被点的会话清掉 `isTabClosed`；由它打开的其它会话仍留在归档里。本地项目若已从机器 Flock 移除或有待删除命令，则拒绝恢复。底层 Delete 实现会先删子 tab 再 `deleteDoc` 根会话，机器通过文档删除标记回收运行时。归档列表刷新成功后清除加载错误，保留独立的恢复操作提示。真实账号的恢复和永久删除尚未验证。
- `HTTPLodyClient.streamsAccess(workspaceID:)` 按 Lody 的 `/api/loro-streams/token` 协议取得短期令牌，不会把 Streams 令牌写入 Keychain。
- `SessionSyncBridge` 使用与 Lody 相同版本的 LoroRepo、Flock 和 Streams 库，在本地 WebKit 页面中同步目录与会话文档。原生层通过 URLSession 代理 Streams 请求。
- 详情加载与实时更新：空状态以是否已取得会话快照为准，首次连接失败/重试继续显示加载占位，已有正文在重连期间保留。同步桥分开记录成功拉取的消息时间戳与可确认已读的时间戳；同一时间戳已拉取成功、但正文尚未变化时，后续流式/配置/状态更新不再重复等待 cloud sync，新时间戳仍需同步验证。已读仍要求可见内容变化与底部布局证据。本轮 160 项 JavaScript 测试、bundle 重建、138 项 Swift 测试通过；iPhone 17 / iOS 27 的首次失败重试不闪空状态与打开详情清除未读两项 UI 回归通过，重试用例追加 fixture 加载延迟后再次通过。真实账号弱网、持续输出的端到端延迟尚未实测。
- 真实客户端已支持只读会话正文和实时更新：当前详情页通过 `joinRoom()` 订阅 Session 文档与 workspace metadata，持续显示正文和运行状态。投影用户和 Agent 的普通文本，以及 history 里的 `image` / `image_group`（也保留没有 `mimeType` 的图片引用）。图片用当前账号的 Bearer 令牌从 `https://api.lody.ai/api/workspaces/{workspace}/session-images/{session}/{imageId}` 下载；fork 复制的图片用 `storageSessionId` 作为 blob 所在 session。详情里单张图走 `thumbnail?width=768&fit=scale-down&quality=85`，多张图走 320 正方形 cover，失败时回退原图，点按后看原图。工具记录等其他结构化内容不作为消息正文显示；文件修改摘要与可用 diff 在 HUD 详情中单独展示。相同图片请求共享下载，取消单个等待者不影响其它等待者，最后一个等待者退出时取消网络请求。下载先检查响应长度，并在流式累计超过 5 MiB 时中止；多图布局按聊天区域可用宽度缩小方形缩略图。真实账号的图片下载尚未实测。
- 会话单图外框按实际缩略图比例贴合，最大边 220pt，不放大小图；缺失尺寸时使用 160pt 方形占位，加载后修正尺寸。加载成功后去除灰底和描边，多图继续使用紧凑方形网格。 本次图片 fixture UI 测试在浅色默认字号、深色辅助大字号下均通过，覆盖缺少尺寸的竖图加载后 165×220pt、右对齐、多图方形和预览；真实账号图片尚未复测。
- 原生网络桥用 `URLSession.bytes(for:)` 将响应头与数据块交给 JS `ReadableStream`，包含背压和 AbortSignal 取消；写请求的请求体也由原生代理发送。Streams 库继续负责 SSE、long-poll 回退与重连。鉴权回调按需续期，401/403 强制重新获取令牌。
- JS 合并 80ms 内的变化并按 turn ID 发送正文补丁；Swift 在桥内先还原完整快照，再通过仅保留最新值的异步流交给界面，避免丢弃中间补丁导致正文缺失。
- 页面离开或进入后台释放订阅，回到前台重新同步；工作区和账号切换丢弃迟到更新。底部阅读时跟随同一条回复增长，上翻阅读时停止自动跟随。
- 真实客户端现可向空闲会话发送普通文本：独立的短生命周期 Streams 副本先确认正文同步，再写入 `latestUserMsgId` 并确认 metadata 同步。写前重新同步并检查派发指针，写后确认指针仍指向本次 turn；现有 LoroRepo metadata 写入没有 CAS，跨客户端同时写入时仍不能保证绝对互斥。未确认的发送保留 turn ID；改发文本前须先重试旧消息，防止留下未派发的历史记录。旧 turn 已被较新的派发取代时会废弃旧重试 ID。发送成功后会话列表立即更新最近排序，并从服务端刷新。权限响应仍只在 fixture 中可用。
- 运行中的会话在输入区显示停止按钮，保留未发送草稿；具备 `supportsTextSendingWhileRunning` 的客户端（目前仅 fixture）同时保留发送按钮，真实客户端仍只显示停止操作；点按后从已同步的原始 history 找出最新未完成的 assistant turn，将其 ID 写入 `lastCanceledTurn` 并确认 metadata 同步。若 turn 尚未出现或已经结束，会提示重试。真实机器的停止响应仍待实测。
- 会话内 model/reasoning：输入区第一行输入文字，第二行放置操作按钮；带刻度的仪表盘图标随 reasoning 档位变化。点击后打开无箭头浮层，model/reasoning 标签位于玻璃刻度胶囊外；离散 reasoning 刻度支持点选、拖动及 VoiceOver 调整，点击模型进入 Advanced 表单。浮层打开时使用仅内存中的页面快照做渐变模糊，关闭即释放，系统键盘保留清晰显示。新建会话的 provider/model/reasoning 共用此入口，选项仍遵循代理能力；Fast 暂不可用，尚未接入真实协议。观察器从机器 Flock 文档 `${workspace}:mf:${machineId}` 的 `['acpCapability', agentConfigId]` 读取能力（cliType/agentType 须与会话一致），当前值依次取与最新用户 turn 对应的 `acpRuntimeConfig`、该 turn 的 `inputConfig`、能力的 `currentValue`。能力含 reasoning 选项（`reasoning_effort` 或 `thought_level` 类别）时只允许改 reasoning（若有 `modelReasoningEfforts` 则按当前模型过滤），以免中途换模型破坏上下文缓存；否则允许改 model（builtin 写 `modelId`，registry/custom 写对应 config option）。无能力记录时只读显示。界面和新 turn 发送共用与最新用户 turn 匹配的运行时配置基线，运行时 configOptionValues 作为完整快照替换旧值。选择仅作用于下一条新 turn，页面离开即丢弃；未确认发送的重试沿用首次发送时的选择；发送层返回实际沿用的选择，界面仅清除已发送的选择，重试时新选的配置保留给下一轮，包括明确选回原基线的值；普通发送与“Retry earlier message”入口均更新实际配置基线。运行中可预选。尚未用真实账号验证 CLI 对切换值的实际应用。
- 新建会话：按项目分组时，本地项目行右侧有新建按钮（未分组与 GitHub 项目不显示），进入独立页面后以第一条消息创建会话。机器、Agent 配置和本地项目取自该项目最近的根会话（模板），项目引用只保留 `localProjectId` / `githubRepoFullName`，不带 worktree 和分支，即直接在项目目录工作。第一条 turn 继承同工作区、同机器和同 Agent 配置最近活动的未归档根会话（跨项目）最新用户 turn 的有效配置中的 `modeId`、`modelId`、`configOptionValues`、`mcpServerIds`（不继承 Agent Role 与 `resume`），model 与 reasoning 都可在页面上选择：选项来自机器 Flock 的 `acpCapability`，reasoning 按所选模型的 `modelReasoningEfforts` 过滤，切到不支持当前 reasoning 的模型时不写 reasoning，由 Agent 默认值决定；桥在写入时重新投影并拒绝未提供的选项。写入使用独立短生命周期副本，只有它开启 `createStreamIfMissing` 以创建新 Session 文档流（对应 Lody 的 `ensureDocStream`）：先同步第一条 turn，再一次写入 metadata（`status: idle`、`title` 取前 50 字且 `titleSource: 'draft'`、`latestUserMsgId`）并确认同步，因此机器看到会话时正文已就绪。未确认时按项目在进程内保留会话 ID 与 turn ID，重试沿用首次的选择；改了文本须先重发原文。成功后替换为会话详情页，列表乐观插入后在后台刷新。Lody 桌面端创建会话前会在客户端检查免费会话额度，Kurage 没有这一步，需在 issue 中跟进。真实账号的新建、机器派发与首轮 model/reasoning 生效尚未验证。
- 新建会话配置在页面内预取并缓存各 provider 的选项，共享同一 provider 的在途请求；已缓存 provider 切换及 model/reasoning 选择立即更新本地状态，往返切换保留各自选择。尚未加载的 provider 立即显示新名称和加载状态，不展示旧模型，不允许发送；迟到结果不会覆盖新选择，页面离开或进入后台取消请求。缓存随页面释放，写入时仍由桥重新校验能力。真实账号首次加载耗时尚未测量。
- 会话底部输入区使用悬浮的 Liquid Glass 胶囊；点按发送后立即清空草稿并保持键盘，同时用同一个 turn ID 在对话列表插入用户气泡，不显示单独的发送进度提示。同步到对应 turn 时原位接管而不重复显示；若发送未确认则移除临时气泡并恢复原文供同 ID 重试。
- 已有会话的输入区在 model/reasoning 按钮左侧显示 Context window 用量环，不显示数字百分比；点按可查看已用/总 token。数据来自 Session metadata 的 `contextWindowUsage`，随订阅更新；无有效用量时不显示，新建会话尚无用量。真实账号的持续更新和真机浮层布局尚未验证。
- 聊天区域由 UIKit 容器协调：`keyboardLayoutGuide` 同步调整消息列表与输入区，通过几何测量将整个输入区的实际高度同步给 UIKit 约束并设置列表 inset；SwiftUI 保留消息样式和输入控件。消息按 turn ID 在原生列表中复用和更新，布局与正文高度变化时仅在跟随模式下贴底；上翻阅读时保存消息 ID 与其可视位置，回到底部或发送新消息恢复跟随。短会话仍贴近输入区。

- 每轮文件修改卡片：在对应 Agent 回复正文下方展示 files changed、该条记录的增删统计及前三个路径；支持折叠，超过三个文件时显示 View N more files，点击路径或更多入口打开对应轮次的 This turn 抽屉。底部 HUD 保留会话汇总。文件数据独立增长或删除时会重新配置对应消息行，沿用现有滚动跟随及阅读位置机制。 本轮通用模拟器构建、4 项 ConversationLayoutTests（含文件变更独立刷新/移除）及定向文件变更 UI 测试已通过；新增卡片折叠/展开和 This turn 范围断言。浅色截图及深色 + accessibility-extra-large 组合 UI 复测通过，验证后恢复模拟器显示设置；真实账号中的新卡片尚未设备实测。 折叠动画与 Worked for、工具组共用 0.25 秒 ease-in-out 正文淡入淡出及箭头旋转；隔离助手消息容器几何动画，阅读位置立即补偿，尊重 Reduce Motion。此次验证结果见下方 Worked for 条目。
- 会话文件修改：输入框上方的 Liquid Glass HUD 显示去重后的文件数及已知的累计增删行数，点击打开默认大屏、支持下拉缩小的详情 sheet；默认查看 Last turn，顶部菜单可切到 All turns，增删统计跟随当前范围。抽屉使用浅色白底/深色深灰底，文件头为紧凑的浅灰/深灰条目、小圆角，点击无箭头的文件头展开代码；右上角是中性的 Liquid Glass 缩放/关闭按钮组，不再使用系统导航栏的蓝色确认按钮。按会话轮次列出文件名、路径和计数。数据来自 assistant history 的 `fileDiff`；仅已完成 `tool_call.content` 中显式的 `diff` 块作为可选代码预览，不从工具标题、locations 或 shell 文本猜测文件修改。代码按行显示红删绿增和上下文，行号以工具提供的文本为准（可能只是片段）。同一轮 `fileDiff` 中同一路径的多条记录按 Lody 的 `buildSessionDiffSummary` 累加增删行数，不能让后面的零值覆盖先前计数；同一路径多轮修改保留各轮记录，汇总是历史累计，不是当前 Git 净差异；没有完整计数时 HUD 不显示对应总数，没有正文时说明代码预览不可用。空记录隐藏 HUD，删除/替换记录会清除旧结果；完整文件记录随正文缓存按账号/工作区/会话隔离。桥仅在文件记录变化时发送替换补丁，Swift 先恢复完整快照再发布；差异正文限制总传输预算和单文件大小，原生比较在后台执行并限制行数。当前没有接入机器文件 RPC，因此不提供 Unstaged、Staged、All Files 或远端完整文件浏览。真实账号返回的摘要/差异正文覆盖率和持续更新仍待实测。
- Worked for 折叠：与 Lody 一致，Agent 回复中连续的 tool call 与 thought 合成活动组（“Ran 3 commands · Read 2 files”，读/改文件按路径去重），点开列出工具标题（最多 100 条、每条 200 字，不显示输出）；thought 正文不投影，只含 thought 的组不显示。回复 `finished` 且折叠后仍有可显示的答案时，最后一段连续文本（及其后的图片/文件等不折叠项）保持可见，之前的文本和活动组收进答案上方的 “Worked for 1m 27s”，时长为 `endedAt - timestamp - permissionWaitMs`（格式 `12s` / `1m 05s` / `1h 02m 03s`），缺失时显示 “Finished working”。流式中、被中断无答案、或无可折叠工作的回复保持展开并逐步显示活动组。展开状态按 turn 与活动组保存在转录控制器里，行复用和流式重配置不会串行或丢失；统一使用 0.25 秒 ease-in-out 展开/收起，滚动锚点立即补偿，尊重 Reduce Motion。被折叠的文本仍参与搜索。运行中在本轮回复正文及工具活动上方显示 `Working… 35s`，下方以分隔线与内容分开（本次 `testWorkingTimerTicks` 已验证标签位于正文上方、计时刷新及停止后移除）：桥接投影最新未结束 assistant turn 的开始时间和已记录权限等待时长，包括尚无可见内容的 turn；原生标签每秒刷新，离开前台暂停，只在会话运行且为最后一条回复时显示，结束/停止移除。与 Lody 一样，权限等待若到结束才写入，最终数字会扣除等待时间。Worked for、工具组及文件变更卡片统一使用正文淡入淡出；消息行由显式 hosting controller 承载，隔离助手消息容器几何动画，标题不参与位移动画，箭头只旋转；展开和收起都保持当前 turn 的阅读锚点，短对话保留底部空间以避免标题跳动，折叠标题保持完整高度，活动图标槽宽随辅助字号缩放。暂未实现：plan 审批把一轮拆成多段（Lody 的 segment），以及 thought 正文展示。 当前计时与动画修改：frozen lockfile 安装、152 项 JS 测试与 bundle 重建通过；135 项 Swift 单元测试通过；Worked for 与文件变更 UI 测试在浅色默认字号下通过，Worked for 和实时计时（含停止后移除）在深色 accessibility-extra-large 下通过。上述为此前验证。此次标题位移修复：6 项 ConversationLayoutTests 及辅助大字号下 Worked for、文件变更、Working 计时 3 项 UI 测试通过；收敛动画隔离条件后再跑 6 项布局测试与大字号 Worked for 测试通过；默认字号已检查图片与长会话布局。另一个发送后键盘保持用例失败，未修改版本同样复现；尚未修复该既有问题。真实账号中的计时、折叠和流式活动组尚未实测。

- PR #16 附件顺序修复：可折叠工作之间夹有图片、图片组或文件等可见内容时，整轮保持展开，避免单个 Worked for 插入点重排内容；附件仅在工作前后时仍正常折叠。暂不扩展为多段折叠协议。此次 frozen lockfile 安装、159 项 JavaScript 测试及 bundle 重建通过，新增三项交错附件回归测试；未运行 iOS 测试或真实账号验证。

## 验证与后续

- 输入框左下新增「＋」菜单，已有会话与新建会话共用 Files、Camera、Photos。Files 使用系统文档选择器并在安全作用域内读取；Photos 使用 PhotosPicker，仅读取选择项目，不请求相册访问权限；Camera 按需申请相机权限，不写入相册。选择中阻止发送，附件可预览和移除，最多 8 项；HEIC/过大照片转换成最长边 2048px JPEG，图片上限 5 MiB，普通文件暂限 16 MiB（Lody 单次上传上限，尚未接分片上传）。草稿字节仅留内存，不落入会话磁盘缓存。
- 图片使用 cloud API 的 session-images/upload multipart（sessionId + file），文件使用 session-files/upload 原始字节与 x-session-id/x-file-* metadata、SHA-256。发送前完成上传，将返回的显式 image/file block 同时写入 history 和 inputConfig.inputBlocks，允许只有附件的消息，也支持新建首轮；保持正文先同步、metadata 后派发。上传引用按账号代次/工作区/会话/附件 ID 复用；未确认发送保留原始附件与 turn ID，重试不可替换附件。对话显示图片和文件名/大小卡片；文件下载/预览尚未提供。真实账号附件上传、机器读取附件、真机拍照和 iCloud 文件选择尚未验证。
- 附件输入区改为 120pt 圆角图片预览和紧凑横向文件标签；加号使用自适应中性色，选取后的加载占位和发送中的进度显示在附件内，保留 44pt 删除点击区域。 本次构建及附件来源 UI 测试通过；修复图片无障碍标签覆盖删除按钮后，照片预览/删除/发送测试在浅色及深色 + 辅助大字号下通过。真实服务上传与慢速照片加载仍待实测。
- 附件协议参考：Lody `packages/components/src/lib/session-image-upload.ts`、`session-file-upload.ts` 与 `packages/shared/src/session-image.ts`、`session-file.ts`、`ai.ts`；Photos 使用 Apple 的系统 PhotosPicker。
- PR #13 review 修复：附件上传将任务取消及 `URLError.cancelled` 统一转换为 `CancellationError`，其他网络错误原样传播，避免取消被界面误报为上传失败。本轮 28 项 HTTP Swift 测试通过，新增覆盖图片/文件在途取消、网络层取消、超时与连接中断；真实账号上传取消尚未验证。
- PR #13 二轮 review 修复：上传重定向 delegate 使用锁保护拒绝状态；任务真正取消时仍返回 `CancellationError`，否则被拒绝的重定向返回普通连接错误，使发送界面恢复正文并提示失败。307/308 回归覆盖同主机 HTTPS、跨主机及 HTTP 降级的错误分类，并保留在途取消及普通网络错误测试。本轮 HTTP 与图片相关 Swift 测试通过；真实服务器重定向及界面端到端恢复未实测。
- 本轮附件验证：frozen lockfile 安装、112 项 JS 测试及 bundle 重建通过；113 项 Swift 测试全量通过，最后的账号代次隔离调整后再次通过 24 项 HTTP 测试。两项新增 fixture UI 测试在最终代码通过，覆盖三种来源打开/取消、照片预览/删除/无文字新建发送；既有新建配置回归通过。检查了浅色、深色和最大辅助字号。修复底部 interactive glass 拦截重叠菜单点击、加载状态切换导致＋消失，以及大字删除图标裁切；删除按钮保留 44pt 点击区域。Files 的实际文件导入、真实服务上传和真机拍摄结果尚未验证。iPhone 17 的既有“发送后软键盘隐藏”回归仍失败；同设备原始 HEAD 对照也在同一断言失败，未将其计为通过，亦未把它归因于本次附件功能。

- 分支审查修正：代码预览按 LF/CRLF 分行，保留末尾空行并对 CRLF 同样执行行数上限；无文本差异时提前返回，跳过上下文构造。失败发送 fixture 保留首次 turn ID 与配置（包括未选择配置），与 live 重试语义一致。状态更新复用文件变更/子任务快照时，补丁跳过同一引用的重复 JSON 比较。本轮 frozen lockfile 安装、109 项 JS 测试及 bundle 重建通过；110 项 Swift 测试与 4 项定向 fixture UI 回归通过（文件详情、失败重试草稿、乐观发送去重、只读子任务返回），未验证真实账号弱网同步。后续性能项：工作区任意 metadata 变化仍会触发子任务目录扫描，需结合文档事件及父子关系做精确失效，不能只监听现有子会话而漏掉新增任务。

- 子代理 UI 验证：浅色默认字号与深色辅助大字号的胶囊、分组浮层、半屏详情、只读操作限制和关闭保留草稿均通过 fixture 测试及截图检查。大字号核验发现列表自动测高/贴底后 cell 已移动但 hosting 内容仍停在旧位置，已在非动画滚动校正后刷新可见 cell 布局；4 项布局回归及新增末轮卡片可点击断言通过，截图确认正文恢复。子任务抽屉改为系统实色背景，避免底层输入区透出。长会话打开与上翻后键盘不强制贴底的 UI 回归通过；多行输入测试改按整条消息行（含文件卡片）测量与 HUD 的间距；小屏空间不足以容纳整行时检查行底部可见，空间足够时仍要求正文可见。修正后 iPhone 17e 的五行输入、键盘开合及发送后保持键盘 UI 回归通过。iPhone 17 曾出现发送后键盘退出屏幕的失败，尚未确定原因，不计为该设备通过；真机键盘行为仍待验证。

- 子代理任务：主列表继续只展示根会话；主会话在输入框上方以 agents 胶囊显示直接子会话数量，与文件修改 HUD 并排，宽度不足时改为上下排列。点开为按真实状态分组的紧凑浮层，高度贴合内容，超高时滚动；选择任务后先关闭浮层，再打开可从半屏拉高的只读正文抽屉，关闭保留主会话草稿。状态依据 metadata 展示 Starting / Running / Waiting for input / Idle / Archived，不将 idle 推断成成功。同工作区通过 `parentSessionId` 匹配直接子会话；归档任务保留可读入口，已删除文档移除。订阅接收子会话新建、状态、关系和删除变化，正文流式增长不重新扫描子任务；补丁只在列表变化时替换。取消、后台与账号/工作区隔离沿用现有订阅，正文、图片和文件修改共用现有读取链路，不开放子任务发送、停止或权限操作。109 项 JS 与 108 项 Swift 测试通过，bundle 已重建、Xcode 项目已重新生成；父子隔离、metadata 更新/清除、补丁保留正文和取消有回归覆盖。本机真实审查 metadata 只读投影得到四个唯一子任务。真实账号下的新入口和弱网更新尚未设备实测。

- 2026-09-27 review 与重复发送排查：普通发送失败恢复的原文，在专用重试成功后仅当草稿仍与原文相同时清空，用户改写的草稿保留。文件抽屉的 Last turn 改用原始 history 的最新用户轮次编号（随 snapshot/patch 传输），最新轮次没有修改时显示空态；保留仅含文件修改的 Agent 行，让卡片在原始顺序与 ID 下显示，修改删除后空行随投影移除。新增跨全新 CRDT 副本的创建重试回归，覆盖正文已持久化、metadata 确认丢失及同一数据重复导入，保持唯一首轮。用户补充会话列表截图后已定位所谓五条重复：主会话创建于本地时间 09:14:36，09:15:41 通过一次 `session_create_many` 操作生成四个不同审查职责的子会话；metadata 的 `parentSessionId` 均指向主会话，每个子会话各一条任务消息。四个标题与截图完全对应，来自 review 技能要求的并行审查，并非 Kurage 重复提交首消息。Kurage 列表只展示根会话，而截图中的其它客户端也展示了这些子会话，造成数量不同。 本轮 106 项 JS 测试、106 项 Swift 测试与 4 项 fixture UI 测试通过；补充无正文参数后，4 项原生布局测试（含有/无正文文件卡片）再次通过。已按 frozen lockfile 安装依赖并重建桥接 bundle，本次截图对应事件已通过本机编排记录及 metadata 确认；合成测试不代表所有真实弱网情形均已验证。 本轮浅色默认字号截图确认最新空态、内联卡片、HUD 和抽屉正常；未重新验证深色、大字号及软件键盘弹出布局。

- 2026-09-27 文件计数修复：发现每轮 `fileDiff` 按路径建 Map 时会用后一条覆盖前一条，已改为累加，与 Lody `packages/components/src/components/sessions/session-diff-summary.ts` 的 `buildSessionDiffSummary` 一致。新增回归覆盖非零被后续零值覆盖、双向累计、路径归一化、不重复计算代码预览、未知/溢出计数和快照替换后计数减少。104 项 JS 测试通过，已按 frozen lockfile 安装依赖并重建 bundle；Swift/JS 消息格式未变，本轮未重跑 iOS 测试。后续核查截图对应的本机 Lody diff-store：同一轮的 8 个文件及计数与截图完全吻合，其中 AppModel.swift 与 HTTPLodyClient.swift 持久化计数均为 0/0，且各自 old/new snapshot ID 相同，因此本次零值并非投影覆盖导致。当前 Git 工作区中两文件分别为 +5/-0、+7/-0，与参考图一致，但 Git 工作区差异不能直接替代历史轮次数据。尚未确认上游采集为何记录相同快照；现有记录不足以恢复这两文件的历史修改前内容。此次核查未修改后端数据或伪造客户端计数。

- 2026-09-27 抽屉样式对齐：iOS Simulator 构建通过；扩展后的 fixture HUD UI 用例在浅色与深色最大辅助字号下通过，覆盖 Last turn / All turns、半屏/大屏切换、无箭头文件头展开及关闭保留草稿。截图确认白/深灰抽屉、灰色紧凑文件头、中性玻璃按钮；最大字号下窗口图标固定 20pt，避免挤出 44pt 高的按钮区域。本轮只修改 UI，未重跑 JS/模型测试。

- 2026-09-26 文件修改功能：100 项 JS 测试通过，已用 frozen lockfile 安装依赖并重新生成桥接 bundle；104 项 Swift 测试通过，补丁改为仅变更时替换后另通过 15 项定向 Swift 测试。回归覆盖摘要独立于正文、结构化证据筛选、记录更新/删除、重复路径、缺失计数、旧快照兼容和差异大小限制。iPhone 17 / iOS 27 的新 HUD 详情用例、长会话打开/阅读用例通过；最后一次重新编译的 HUD 与多行键盘回归两项均通过，确认展开差异、关闭保留草稿、输入区增长/发送及键盘可交互。旧滚动测试改为测量消息与最上方 HUD 的距离（没有 HUD 时仍用输入框），保持原间距上限并等待布局稳定。新详情用例也在深色模式和最大辅助字号下通过，截图确认单列行号、路径和增删背景可读，长代码可横向滚动。真实账号文件摘要/正文覆盖率、持续同步、真机键盘动画尚未验证。

1. 发送功能阶段已记录通过 19 项 JS 测试与 36 项 iOS 模拟器 Swift 测试（参数化共 38 次运行），包括正文同步后派发、同 ID 重试、写请求体代理、分块 UTF-8 和原生 WebKit POST。会话发送与长会话 UI 用例已在 iOS 27 模拟器通过；截图确认第二次打开键盘时最新消息仍贴近输入区，测试也确认上滑后打开键盘不会跳回底部。
2. 真实账号的只读会话已由用户实测，反馈可用；持续输出、断网恢复和后台返回各场景的结果尚未逐项记录。当前 JS 在正文变化时仍按节流周期投影完整 history；超长会话的窗口化读取是后续性能工作。
3. 文本发送已按 Lody 桌面端的用户 turn 与 `latestUserMsgId` 协议接入。用户已用真机上的 Kurage 向真实会话发送消息，且消息抵达当前会话，验证了一次正常网络下的发送与派发；网络中断时的确认、重启后的重试仍未验证。运行中 steer、排队消息和权限响应有各自协议，本阶段只允许空闲会话直接派发。下一步再将匹配 `requestId` 的权限响应写入对应 `tool_call`，之后考虑通知及机器端 Git Diff/文件浏览。

4. 本轮 UIKit 键盘布局改动通过 iOS 27 模拟器的 2 项布局回归测试与 3 项聊天 UI 测试，覆盖正文增长/删除、阅读消息锚点保持、发送恢复贴底、键盘反复开合和五行输入区完整避让。同一多行 UI 用例也在深色模式与系统 XXXL 字号下通过；截图已确认输入区整体随多行文字增高，发送后恢复单行，文字和发送按钮未被键盘遮挡。真机动画手感与真实账号持续输出尚未在本轮验证。

5. 本轮分支审查修复通过 56 项 JS 测试、69 项 Swift 测试，以及列表/空列表两种下拉刷新宿主集成用例；4 项 fixture UI 测试通过，覆盖列表切换、搜索、归档确认和图片预览；扩展搜索用例另在暗色和最大辅助字号下通过，截图确认无结果空态与搜索框可读，并覆盖空态/列表下拉。取消回归覆盖正文读取释放同步队列、后台暂停/前台恢复、共享图片下载的单个与最后一个等待者取消。归档测试覆盖机器命令不可用及旧队列被清理后的成功确认。真实服务弱网和机器清理行为仍待验证。

6. 本轮分支审查的六项修复通过 61 项 JS 测试与 73 项 Swift 测试（包含参数化运行）。新增回归覆盖运行时配置基线与重试不改写、搜索文档在成功/失败/取消后的释放、观察中的文档保留、实时正文延迟索引、归档加载错误清理，以及有无 Content-Length 的图片超限提前中止。桥接 bundle 已重新生成。4 项 fixture UI 场景通过，覆盖搜索、配置菜单、归档恢复和三图边界/预览；图片用例另在 iPhone 17e 的深色模式与最大辅助字号下通过，截图确认三图方形、边距和预览比例正常。预览页固定深色外观，保持黑底上的导航标题可读。真实账号下的运行时模型切换、大量会话内存占用及图片弱网仍待验证。

- 2026-09-28 对比 main 的分支审查：活动组与无 toolCallId 的步骤使用原始 history 索引，避免前置重试记录完成后被隐藏而改变 ID、丢失展开状态；运行状态变化只重配旧／新末尾消息行，只有读写工具扫描文件路径。新增稳定 ID 回归，153 项 JS 测试通过，已按 frozen lockfile 安装并重建 bundle；24 项 Swift 模型／布局测试和 4 项 fixture UI 测试通过，覆盖长会话阅读、文件卡片、Worked for 展开保持及运行计时停止。未复测深色／大字号或真实账号，已有动画衔接限制仍待后续优化。

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
- Lody `packages/shared/src/schema.ts` 的 `SessionMeta.contextWindowUsage`、`apps/cli/src/lib/loro/doc.ts` 的 metadata 写入及 `packages/components/src/lib/session-usage.ts` 的百分比计算：Context window 用量来源。
- Lody `packages/shared/src/ai.ts` 的 `SessionImagePayload`、`packages/shared/src/session-image.ts`，以及 `packages/components/src/lib/session-image-gallery.ts`：会话图片 metadata、下载路径和 `storageSessionId`。
- lody-ios `apps/mobile/modules/lody-kit/ios/Cloud/SessionAttachments.swift` 和 `ios/Chat/ChatImageCell.swift`：图片下载使用 `api.lody.ai`，缩略图失败后回退原图；`data-runtime/project.ts` 的图片投影也保留缺少 `mimeType` 的 `image_group` 成员。
- Lody `packages/components/src/hooks/use-session-actions.ts` 的 `buildSessionCreateResult` / `startSession` / `requestSessionDispatch`、`components/onboarding/screens/first-task-screen.tsx` 与 `providers/create-workspace-runtime.ts` 的 `ensureDocStream`：新建会话的 metadata 字段、第一条 turn 与派发指针、新文档流创建；免费额度检查在 `assertSessionCreateAllowed`。
- Lody `packages/components/src/hooks/use-permission-response.ts` 与 `packages/shared/src/history-writer.ts`：权限响应的写入路径。
- Lody `packages/components/src/components/ai-gui/assistant-turn-render-blocks.ts`、`message-copy.ts` 的 `shouldCollapseAssistantMessageItem`、`view.tsx` 的 `WorkedGroupHeader` / `ActivityGroupHeader`，以及 `packages/components/src/lib/session-history-duration.ts`、`format-duration.ts`：Worked for 折叠规则、活动组统计和时长；`packages/shared/src/schema.ts` 的 history `timestamp` / `endedAt` / `permissionWaitMs` / `finished`。

- Lody `packages/shared/src/schema.ts` 的 `normalizeFileDiff`、history `fileDiff`，`packages/shared/src/ai.ts` 的 `tool_call` / `DiffBlock`：会话文件摘要和可选文本证据。`packages/components/src/components/sessions/use-session-conversation-diff-data.ts` 与 `use-session-all-changes-diff-data.ts`：完整会话/Git 差异依赖机器文件 provider，不能用 history 摘要或 `SessionMeta.diffStats` 替代。

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

- PR #10 模板与项目可用性再审修复：`PendingStart` 同时保存首次模板 ID，未确认后的重试即使页面改用更新根会话，也仍从原模板恢复，避免首轮配置与派发 agent 不一致。选项加载及新建写入共用已同步机器 Flock 的项目可用性检查，复用归档恢复规则，拒绝已删除项目及待处理删除命令；保留旧版 machine metadata 项目记录和未知状态的兼容行为。已写首轮后发现项目不可用时保留未确认状态及原 ID，不将它视为可安全丢弃的新请求。
  本轮通过 88 项 JS 测试与完整 98 项 Swift 测试，bundle 已重建。新增/扩展回归覆盖模板变化后的原模板重试、项目删除/待删除的读取和写入拒绝、旧版项目与未知状态兼容，以及已写首轮后的重试保护；真实账号项目删除竞态与机器派发仍待验证。

- PR #10 归档模板重试修复：只有新会话文档已同步且存在通过用户身份和正文校验的首轮时，才允许从已归档的原模板继续发布 metadata；普通新建和选项读取仍排除归档模板，删除模板及项目删除/待删除检查保持有效。重试保留原首轮与配置，不重复写入。
  本轮通过 92 项 JS 测试，bundle 已重建；回归覆盖正文同步未确认、metadata 写入失败后模板归档、身份/正文不匹配及删除边界。未修改 Swift/JavaScript 消息契约，未重跑 iOS 测试；真实账号弱网与跨端归档仍待验证。

- PR #10 待处理创建入口修复：客户端提供按账号和工作区隔离的待处理创建摘要及专用重试方法，以已有会话 ID 恢复首次文本、模板、agent 和配置，过期 ID 不会创建新会话。AppModel 按工作区保存仅内存的展示状态，退出登录清空，旧认证结果不得写回。创建页在待处理状态收起普通输入区和键盘，提供独立的 “Retry earlier start” 按钮，不依赖 options 加载或活动模板；列表工具栏保留待处理入口，即使项目的全部模板已归档也可返回原请求。普通创建仍要求有效配置及活动模板。
  本轮完整 100 项 Swift 测试通过，正常新建及归档模板后恢复两项 fixture UI 场景通过；恢复场景另在深色最大辅助字号下通过，并在收起待处理输入区后再次复验。回归覆盖 options 失败、活动模板移出列表、后台返回、列表待处理入口、原 ID 与首轮保留、过期重试拒绝、工作区隔离和退出登录清理。最终深色最大辅助字号截图确认原任务与重试入口默认完整可见。本轮未修改 JS 桥或消息契约，未重跑 JS 测试；真实账号弱网及跨端归档仍待验证。

- PR #12 待重试发送恢复：会话页首次开始观察时，从客户端按当前账号、工作区和会话保存的待发送记录恢复原文、重试入口及未确认提示；只读会话不恢复发送状态，后台返回和刷新不覆盖正在编辑的草稿。重试继续沿用客户端保留的原 turn ID 和配置，不新增持久化。
  本轮 44 项相关 Swift 测试与 3 项 fixture UI 回归通过，覆盖重开会话恢复、其他会话隔离、后台返回保留编辑、重试确认后清理及只读子会话。新增用例在修复前复现重试入口和草稿丢失；修复后调整测试对光标位置的假设，最终复验通过。未修改 JS 桥或协议；真实账号弱网与跨工作区往返仍待实测。

- 附件分支审查修复：上传失败且尚未进入 turn 写入时释放待发送/待创建记录，允许修改或移除附件；已尝试写入的请求继续保留原附件与 ID。已有会话按并发准备次数延后释放，避免一个失败请求清除另一在途请求；界面同步清除不再需要的重试入口。上传复用同主机 HTTPS 重定向限制。文件读取与图片转换改为可继承取消的 `@concurrent` 异步函数，并以导入 ID 隔离旧任务的清理与错误回写。
  本轮最终通过 116 项 Swift 测试与 2 项附件 fixture UI 测试；新增回归覆盖 413/415/500 上传失败后的修改与重新创建、已上传首轮未确认后的附件及 ID 保留，以及 307/308 的同主机放行、跨主机和 HTTP 降级拒绝。未修改 JavaScript，未重跑 JS 测试。真实账号上传、实际服务器重定向及慢速 iCloud 文件导入中途退出仍待实测。
- 附件分支后续审查修复：文件历史投影将长文件名截短为最多 200 字符，缺失名称使用 `File`，不再因展示名称丢弃文件块或整条纯附件消息。相机回调不再同步编码原图；图片通过可取消的后台任务按最长边 2048px 缩放、保留方向后编码，再生成缩略图。本轮 frozen lockfile 安装、113 项 JavaScript 测试及 bundle 重建通过；14 项图片相关 Swift 测试通过，包含新增的相机图片尺寸/方向及取消回归；2 项附件 fixture UI 回归通过。真机拍照延迟及真实服务长文件名上传尚未验证。

- 新建会话默认配置修复：移除同项目优先排序，按同机器、同 provider 的根会话活动时间选取有效运行配置，避免旧项目配置覆盖最近在其它项目使用的模型。机器与目标项目仍取项目模板；缺少 agentConfigId 的旧模板仍只继承自身。网页版参考 `components/chat/chat-landing.tsx` 和 `lib/local-storage-cache.ts`：`agentDefaultsCache` 是浏览器 localStorage 偏好，无法直接跨端读取；Kurage 使用已同步会话恢复最近配置，并非同步网页未发送的选择。frozen lockfile 安装、114 项 JS 测试和 bundle 重建通过，新增回归覆盖跨项目优先级、运行时模型/reasoning、页面与首轮写入一致，以及子会话/归档/机器/provider 隔离。未修改原生契约或 UI，未跑 iOS 测试；真实账号默认模型仍待验证。

- PR #14 取消链路修复：置顶和改名通过 operation ID 将 Swift Task 取消传入临时仓库、metadata 同步及原生网络代理；读取后写入前检查取消，退出时销毁副本并清理认证别名。取消会停止尚未完成的工作，不能撤回服务端已接收的写入；真实账号弱网场景仍待验证。
  本轮 frozen lockfile 安装、125 项 JavaScript 测试及 bundle 重建通过；7 项 iOS 定向测试通过（StreamFetchHandlerTests、SessionMetadataTests），包含实际 WebKit 桥接取消原生网络请求的回归。

- Worked for 审查修复：桥接投影记录折叠组在可见内容中的插入位置，原生按该位置显示前置附件、工作组与后续正文，避免展开后将前置图片/文件移到工作过程之后。旧缓存缺少位置时默认从开头显示；新增桥接回归覆盖前置图片、文件和多图组，原生覆盖解码与缓存往返，fixture UI 检查文件在折叠和展开时均位于工作组上方。
  本轮 frozen lockfile 安装、156 项 JavaScript 测试及 bundle 重建通过；25 项图片/布局 Swift 测试和 1 项 Worked for fixture UI 测试通过。已核对 iPhone 17 浅色默认字号下折叠与展开截图，前置文件位置正确、标题锚点稳定。真实账号、深色及辅助大字号本轮未复验。

## Session 列表刷新优化（2026-09-28）

- 已有工作区选择时，账号恢复与下拉刷新并行请求工作区和会话列表，列表结果就绪即发布；首次无工作区时仍先发现工作区。发现工作区失效后加载替代工作区，继续使用账号/工作区 generation 拒绝旧结果。
- 列表只在行内容或顺序改变时提交 diffable snapshot，仅重新配置内容变化的保留行，移除无条件的第二次可见行动画；拖动、惯性滚动和下拉刷新期间不叠加差异动画。
- 对照本机 FlowDown `a2fd55911720bfa0d11c1d4e354359d4801d9387` 的 `ConversationSelectionView.swift`：其数据订阅合并密集通知，列表使用稳定 ID 的 diffable 更新。Kurage 保留现有原生刷新控件和同步协议，不引入 FlowDown 依赖。
- 剩余限制：会话列表仍等待 bridge 的 metadata 与机器项目名称文档同步；本轮没有改变后端协议或引入列表实时订阅，真实账号弱网刷新耗时尚未测量。
- 本轮验证：138 项 Swift 测试、2 项 fixture UI 测试通过，覆盖慢工作区发现不阻塞会话发布、失效工作区替换、搜索空态下拉、列表下拉及左滑归档。未运行 JS 测试（桥接代码未改动）。
- 已核对本轮 UI 测试截图：刷新后列表、空搜索、标题和正文命中布局正常，底部搜索框未遮挡内容。截图不能验证连续动画手感；归档仅由 UI 断言验证。

## Session 列表自动刷新补齐（2026-09-28）

- 纠正上一轮遗漏：此前列表没有持续自动更新，回到前台仅恢复搜索索引。现由列表的 SwiftUI task 管理刷新循环：前台进入列表、从详情返回、关闭归档页、切换工作区时立即请求，之后每轮完成后间隔 10 秒静默刷新。
- 进入详情/新建页、打开归档页或离开前台时取消自动任务；自动任务创建的在途请求随之取消，若只是加入已有手动请求则不取消其底层请求。被取消的结果不再发布，重新进入时不复用已取消的请求。
- 搜索期间暂停定时刷新，避免重复清空索引新鲜度；手动下拉仍可刷新。使用现有请求合并与工作区/账号隔离，不建立新的后端协议或实时订阅。
- 本轮最终代码验证：140 项 Swift 测试、1 项 fixture 搜索/下拉 UI 测试通过；新增回归覆盖重复自动刷新、取消后拒绝旧结果、重新进入时加载以及手动请求隔离。真实账号跨端变化、弱网及前后台切换仍未实测，定时刷新不是实时推送。
