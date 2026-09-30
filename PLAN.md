# Kurage 会话功能

## 消息即时发送与原地重试（2026-10-01）

- 点击发送立即将完整文字、图片和文件放入同一条本地消息，清空输入框与附件，并保持输入框可编辑。上传和同步期间显示在消息下方的轻量发送状态；600 ms 内完成的发送不显示进度提示。
- 待发送内容由 `AppModel` 按账号与工作区／会话保存，跨 tab 和详情重新打开仍保留。新草稿与待发送消息相互独立；发送完成或重试不会清除后来输入的文字、引用或附件。每个会话在旧消息确认前仍只提交一条消息，未扩展 live running-session 发送能力。
- 未确认发送保留气泡及原 turn ID、配置和附件，允许原地 Retry；仅看到 history 中相同 ID 不代表 metadata 派发已确认。明确拒绝的发送显示失败，可重试或在输入框为空时主动 Edit 恢复原始草稿及引用；不会自动撤销气泡或覆盖草稿。
- 图片立即显示已导入的本地缩略图，并支持上传期间预览原图。上传成功后将预览和原图按凭证／工作区／会话／图片引用写入现有内存缓存；同步回传及后续 patches 复用本地缩略图。图片字节、发送状态与本地预览关联均不进入 Codable 协议或磁盘缓存，退出登录后失效。
- 本次验证：Simulator 构建通过；80 项定向 Swift 测试通过，最终版本再次通过 8 项发送状态测试及 7 项 fixture UI 测试。UI 覆盖实际 Photos 选图、图文即时显示、上传期间原图预览、确认后新草稿保留、原地重试去重、失败后恢复引用草稿、跨 tab 状态与详情重开；已检查截图和无障碍层级。真实账号的上传、超时恢复及回到前台仍需验证；待发送记录仅保留在当前进程内，不提供应用被终止后的离线发件箱。

## 输入与消息引用、紧凑 HUD（2026-10-01）

- 详情底部 diff／subagent 胶囊改用 caption 字号、更小图标和内边距；玻璃背景包围紧凑内容，外部保留至少 44 pt 点击区域，辅助字号仍随系统缩放。
- 已选择的 skill／session 引用在输入框中使用蓝色名称与类型图标，替代 `$`／`@`；普通输入触发字符仍显示原样。使用原生 UITextView 保留多行、选区与 IME，图标替换恰好一个 UTF-16 字符，草稿与发送绑定的路径／会话 ID 不变。删除触及引用仍整段移除，完整复制保留原始文本。
- 我方气泡识别 Lody 的 `use /token [Skill Path](path)` 和 `[@Title](session://id)` 两种明确引用格式，显示图标与可换行名称，隐藏协议包装；普通 Markdown 链接和未绑定的 `@`／`$` 词不转换。气泡完整 Copy／全选复制保留原文及引用目标，继续提供原生文字选择。
- 候选在聚焦时并行预读 skills／当前项目会话，搜索与 `@`／`$` 切换使用当前来源的内存结果；后台取消、来源切换丢弃旧结果、provider 变更后的 skill 校验保持。bridge 读取复用同工作区已同步 metadata，减少重复目录同步；机器 skill scan 仍经现有 RPC，不跨账号／工作区保存结果。加载、空结果、错误和正常列表共用输入区宽度；常规字号保持三行视口，辅助字号使用单行可滚动视口，避免长引用使候选被导航栏裁掉，候选图标宽度随正文缩放。
- 协议／表现参考：本机 Lody `components/src/components/mentions/mention-chips.tsx`、`message-text-chips.tsx`、`mention-skill-source.tsx` 与 `mention-session-source.ts`。本次没有扩展其它引用类别或修改发送协议。
- 本轮已按 frozen lockfile 安装并重建 bridge，当前工作树 251 项 JS 测试通过（含目录复用、工作区隔离和取消）；Simulator 构建及 13 项 ComposerMentions Swift 测试通过。iOS 27 Simulator 的 12 个相关浅色 fixture UI 场景均有本轮通过结果，覆盖引用发送、整段删除、loading 同宽、长列表、provider 刷新／重试、子 agent 返回草稿和文字复制／选择；深色 accessibility-extra-large 的 5 个相关场景通过。截图发现并修复候选顶部裁切后，引用发送、loading、长列表与新建引用 4 项已重新通过；候选图标缩放修正后，引用发送单项再次通过并完成截图检查。真实账号的机器扫描延迟、真机拼音输入及弱网／后台恢复尚未实测。

## 未登录欢迎页与应用内授权（2026-09-30）

- 首次安装、没有有效账号和退出登录后进入 “Welcome to Kurage” 欢迎页，使用现有 App Icon、点阵背景和底部 “Get Started” 按钮。账号恢复期间继续使用现有启动封面；已恢复账号直接进入会话列表。
- 按钮下方始终保留 Cancel 的布局空间，仅在连接时显示并允许交互；未连接时从无障碍树隐藏。开始或取消连接时，主按钮和欢迎内容不再因 Cancel 出现／消失而上下移动。
- 点击按钮沿用 Lody 的设备码授权协议，在原生 `SFSafariViewController` 中打开服务端返回并验证过的授权 URL。原生轮询确认账号后关闭浏览器并进入列表；手动关闭或下拉关闭会取消本次授权，回到欢迎页，可重新开始。拒绝、过期或网络错误返回欢迎页并显示现有错误提示。
- 取消和退出登录立即清除授权展示状态，并按认证 generation 隔离旧任务的 URL、错误和清理，防止旧请求影响新的登录。凭证仍由现有 Keychain 存储；fixtures 默认直接登录，专用 browser 参数仅用模拟授权延迟覆盖浏览器展示和关闭路径。
- 本次验证：Simulator 构建通过；30 项定向 Swift 登录／HTTP 测试和 4 项 fixture UI 测试全部通过，覆盖授权完成自动关闭浏览器、手动关闭后重新开始、退出登录返回欢迎页及既有会话交互。模拟器截图检查浅色默认字号、深色默认字号与深色最大辅助字号，图标、标题和底部按钮完整，无重叠；浅色最大辅助字号因另一项测试接管模拟器未完成。`git diff --check` 通过。UI 测试使用模拟授权延迟，真实账号的网页登录与授权完成、真机和后台切换仍待实测。
- Cancel 位置修订验证：本轮 Simulator 构建通过，关闭后重试与退出后重新登录两项 UI 回归通过；授权完成项首次因立即检查浏览器不存在而遇到关闭动画，改成等待浏览器消失后定向重跑通过。浅色默认与深色最大辅助字号截图确认 Cancel 未连接时不可见，按钮下保留空间，内容无重叠；浅色 Get Started 与用户提供的 Connecting 静态截图按钮位置一致，未测量连接瞬间几何。`git diff --check` 通过。未重跑 Swift／HTTP 测试；真实账号和真机仍待实测。

## 我方消息气泡复制与选择（2026-09-30）

- 长按我方文字气泡显示原生 Copy / Select 菜单。Copy 复制当前气泡的完整原文，保留换行和 Unicode；Select 在菜单收起后直接全选气泡文字并呈现系统完整编辑菜单（Copy、Look Up、Translate 等），使用系统选区手柄调整范围并复制部分文字。
- 气泡使用只读 `UITextView`，保持原有内边距、圆角、系统文字颜色与辅助字号；选择不允许修改消息。选区清除、焦点转回输入框或视图移除后恢复初始菜单。VoiceOver 提供 Copy / Select 操作。
- 本次修订验证：Simulator 构建通过；浅色标准字号下 3 项新增 fixture UI 测试和既有多行输入／键盘布局回归通过，确认 Select 立即显示系统 Copy、Look Up、Translate、Share 菜单、全选复制和拖动手柄后的部分复制；深色辅助大字号下全选与缩短选区 2 项回归通过。`git diff --check` 通过。尚未在真机或真实账号验证。

## 已有会话附件与键盘避让修复（2026-09-30）

- 同一模拟器的当前分支与 `main` 均复现：已有会话选取照片后输入框底边下移 49 pt，发送按钮被键盘候选栏遮挡，重新聚焦或关闭大图预览后仍持续。键盘布局位置和输入区高度测量正确；隐藏的空会话占位视图仍向 Auto Layout 提供最小内容高度，导致较低优先级的输入区底边约束退让。
- 空会话占位内容改为按实际可用视口布局并裁切，其底边约束优先级低于键盘避让，避免最小尺寸挤压输入区。输入区使用原生滚动视口，高度限于键盘上方的剩余安全区；普通字号按内容高度向上扩展，辅助大字号下内容超高时保留发送操作在底部，并允许向上滚动查看附件和状态栏。预览关闭后的键盘高度过渡在子视口最终布局时补齐底部滚动，避免停留在中间高度对应的位置；正文底部留白按输入区的实际视口计算。
- 新增紧凑视口下空会话／已有正文的高输入区布局回归、父子视口分阶段缩小后的底部滚动回归，以及已有会话选图、关闭大图、发送的 fixture UI 回归。UI 回归要求实际可见的软件键盘，按包含候选栏的 `inputView` 当前顶边验证输入框完整位于键盘上方，并检查发送按钮可点击；不单凭 AX Keyboard 的按键区域边界判断，也允许重新聚焦后键盘高度变化。未修复版本的新增 UI 回归已失败并捕获遮挡。
- 本次验证：iOS 27 模拟器的 8 项 `ConversationLayoutTests` 全部通过；浅色普通字号、深色最大辅助字号各 1 次上述 fixture UI 回归通过，覆盖选图、预览关闭后重新聚焦、发送，以及超高内容滚动访问状态栏。验证期间工作区并行登录改动出现编译错误，最终验证使用排除该组改动的独立快照；本次布局与回归测试源文件和工作区内容完全一致。真机与拼音键盘尚未验证。

## 启动封面（2026-09-30）

- 系统 Launch Screen 与账号恢复阶段共用 64 pt 的灰色水母／细圆环标识，浅色白底、深色黑底，居中于安全区；不显示文字或进度条。
- `RootView` 每次冷启动至少展示同款封面 0.8 秒，然后以 0.2 秒淡出；启用 Reduce Motion 时直接切换。账号恢复和内容加载同时进行，有缓存账号也展示封面；尚未确定账号时继续保留封面，结束后进入登录页或会话列表。后台返回不重放，封面展示期间屏蔽下层交互及无障碍焦点。
- 本次验证：Simulator 构建通过；暂停 App 于 main 执行前截图核对系统 Launch Screen 浅色／深色，另以仓库中的同一 `LaunchCoverView` 与编译后的资源在临时模拟器验证壳中核对 SwiftUI 封面，两者位置与配色一致；正常 fixture 启动可进入登录页，`ShellFlowTests/testSignInOpenSessionAllowAndSend` 通过（1 项／0 失败）。真机冷启动、真实账号恢复及后台返回仍待实测。
- 最短展示时间修订验证：重新 Simulator 构建通过，`ShellFlowTests/testSignInOpenSessionAllowAndSend` 再次通过（1 项／0 失败）；正常 fixture 冷启动录像确认封面持续显示、随后可进入登录。模拟器启动延迟较大，本次未能从系统启动时间中单独测量 0.8 秒停留与 0.2 秒淡出；真机时长与真实账号恢复仍待实测。

## 会话顶部运行指示调整（2026-09-30）

- 移除会话详情右上角胶囊内由 `isRunning` 控制的持续转圈。该指示表示 Agent 运行状态；连接／重连提示位于标题旁。
- 本次 Simulator 构建成功，fixture 运行会话截图确认胶囊仅有「＋」与「···」，正文 Working 计时正常刷新。`ShellFlowTests/testWorkingTimerTicks` 最后「暂停后计时文案消失」断言失败，整项测试未通过，原因尚未定位；未验证真机、真实账号或深色／大字号。

## 已有会话误显示空正文修复（2026-09-30）

- 根因：共享读取仓库没有正文持久化存储，搜索等单次读取会在结束后 `unloadDoc`。固定版本 `loro-repo` 的释放会保留 Streams 读取游标；重新打开产生空副本，却从历史末尾继续读取，随后以 `live` 状态发布空正文并覆盖原生缓存。该状态不是云端历史删除。
- 修复：成功释放共享正文副本后调用对应 transport 的 `forgetDoc`，清除该文档的本地会话和游标，再次打开重新恢复历史。正在观察或等待建立观察的会话仍保留正文和游标；不修改远端文档、元数据或依赖版本。
- 验证：使用真实云端会话和当前固定版本依赖复现「正常 4 条 → 释放正文后 0 条」，加入游标清理后重新观察恢复 4 条。另在 Node 中加载修改前后的完整 bridge 源码，连续两次读取同一真实会话：修改前为 4/0，修改后为 4/4（网络使用原生 fetch，未经过 WebKit）。新增重复读取与活跃观察保护回归，237 项 JS 测试通过；已按 frozen lockfile 安装依赖并重建应用 bundle。Swift/JS 消息契约未变，本轮未运行 iOS 测试；修复尚未安装到真机，WebKit、后台恢复和弱网场景仍待设备验证。

## 通知规划（尚未实现）

- 已核实 Lody 机器端通过 Cloud 发送完成／权限事件。Innei/lody-ios 的实现和文档提供第三方接入路径：独立 OneSignal App，由 SDK 注册设备并关联 Lody 用户，Cloud 的 `ONE_SIGNAL_APPS` 清单增加发送目标，无需新建 token 接口。该云端配置机制尚未在 Kurage 所用部署核实，也未验证向 Kurage Bundle ID 的投递。优先确认配置并验证真实事件链路，再接入授权、账号绑定、点击路由和前台展示；保持项目仅开发客户端的范围。本次仅更新规划文档。

## Session 多 tab（2026-09-29）

- 交互修订：只有多个打开的会话时，详情标题下才显示横向 tab 栏；单会话不常驻 Main 占位。顶部「···」左侧 chat 图标进入 New Tab 页面，复用 New Session 的底部输入框、附件、提及和 model/reasoning 菜单；机器和项目仅显示继承信息，不提供项目切换。Provider 与 New Session 一样可切换（2026-09-29 修订）：菜单列出父会话机器上的全部 Agent，选中的 provider 决定首轮 model/reasoning 与写入的 `agentConfigId`；沿用父 Agent 时保持继承父会话的精确首轮配置。创建成功返回同一详情并切到新 tab。
- 各 tab 的文字、提及、附件草稿和下一轮配置在本次详情访问期间独立保留；切换重新定位到所选会话的最新消息，仅当前正文订阅保持活动。列表仍只显示根 Session。材质修订（2026-09-30）：选中 tab 使用不透明的系统浅灰胶囊底色和主色文字，未选中 tab 使用次要色文字；去掉玻璃效果、强调色染色及运行／未读视觉指示，状态仍保留在 VoiceOver 描述中。系统语义颜色适配深色模式，点击区域至少 44 pt。
- tab 材质修订验证（2026-09-30）：Simulator 构建通过；现有 `SessionTabsFlowTests/testCreateSwitchCloseReopenKeepsIndependentDrafts` 在浅色标准字号、深色 accessibility-extra-large 下各通过一次。已核对选中胶囊、未选中文字、无状态点／spinner、键盘显示、长标题截断和返回详情后的选中项可见；模拟器恢复原浅色／large 设置。此轮使用 fixture，真实账号、持续输出、网络恢复和后台恢复未实测。
- 新建沿用主会话的机器、Agent 和完整 project/worktree 上下文，第一轮默认取主会话有效配置，model/reasoning 选项来自同一 Agent 的机器能力；页面选择与写入验证共用投影，支持每模型的 reasoning 约束。不复制历史、不恢复主会话的 provider session。附件沿用现有上传链路；先同步新 Session 正文，再发布 `parentSessionId` / `latestUserMsgId` metadata；只有创建副本可创建 Streams 流。未确认请求在进程内保留会话／turn ID、原文、附件与首次配置，Retry 继续原请求；离开创建页取消调用者，阻止迟到导航。
- 关闭与重开：长按子 tab 的 Close tab 写 `isTabClosed`，不归档、不删除、不停止；当前 tab 关闭后回主会话，仅剩一个 tab 时收起药丸栏。「··· → Closed tabs」可重新打开。其它端的新增、关闭和状态变化经现有 metadata room 更新；剔除归档、删除、`childSessionPlacement: side-panel` 及仅有 opened-by 关系的会话。关闭未发草稿在本次详情内保留，退出详情后释放。
- 选中 tab 记忆（2026-09-29 修订）：上次停留的 tab 由 `AppModel` 按工作区／根会话记住，重新进入详情直接恢复该 tab（原先记在详情的 `@State`，每次从列表进入都回落到 Main），与桌面端 `?tab` 的 last-active 恢复一致。记忆只保留在进程内，退出登录清空；投影证明该 tab 已关闭或不存在时回落到根会话，关闭当前 tab 仍回主会话。药丸栏出现时滚动到当前 tab，恢复的 tab 不会停在可视范围外。fixture 的 tab 顺序改为创建顺序（原先按随机 id 排序，每次运行药丸次序不同），与 live 投影的 `createdAt` 排序一致。
- 原生状态：tab metadata 随完整 conversation update 传递，只有 metadata 变化才扫描目录，正文增长不重复扫描；缓存信息随之后的正文更新继续携带，防止 `bufferingNewest` 丢失状态。按账号／工作区隔离，退出登录清空；新建页面显示期间暂停详情已读回执。发送、停止和问答使用当前 tab 的独立 Session ID，保留原有空闲发送与重试限制。
- 协议参考：本机 Lody `packages/shared/src/schema.ts` 的 `parentSessionId` / `childSessionPlacement`，`components/src/hooks/use-session-actions.ts` 的创建和 `setSessionTabClosed`，`components/src/components/sessions/session-detail.tsx` 的 tab 分组，以及 `apps/cli/src/session/session-manager.ts` 的共享父会话工作目录解析。subagent 的投影、模型和面板不变。
- 此次交互修订验证进行中：208 项 JS 测试通过，frozen lockfile 安装及 bundle 重建完成，Simulator 构建通过；Swift 和更新后的浅色／深色大字号 UI 回归正在运行。之前布局的验证不作为此次结果。真实账号的首轮 model/reasoning 生效、同目录派发、跨端 tab 更新、网络恢复与后台恢复仍待实测。
- Provider 切换修订验证（2026-09-29）：frozen lockfile 安装、209 项 JS 测试（含 3 项新的 tab provider 用例）与 bundle 重建通过；164 项 KurageTests 通过（含新增 provider 切换与 retry 保留用例）。未验证：真实账号上 tab 切换 provider 的首轮生效、另一 Agent 的 baseline 取自最近会话的实际值、UI 浅色／深色与大字号回归、网络与后台恢复。
- 选项加载性能修订（2026-09-29）：New Session／New Tab 的选项读取原先每次都新建仅内存临时副本，从云端冷启动同步整份 workspace metadata、模板会话完整文档和机器 Flock 后销毁，进入页面和切换 provider 都重复整套网络往返。现改为复用会话列表／详情页共享的 workspace 副本（meta 已同步、父会话文档已 live 同步、Flock 已被列表刷新打开），重复加载基本本地完成；写入路径（startSession）保持独立副本并在写入时重新验证模板与选项，陈旧选项最多被拒后提示刷新。取消语义保留：一次性读取在共享副本的执行段内注册认证作用域（按 operation ID 的别名 token 绑定本次 AbortSignal，队列内完成即释放），取消仍中止进行中的原生请求，后续操作不会继承绑定。bridge 测试更新为 213 项（共享副本复用、取消保留作用域、tab 转发不销毁共享副本），Swift 164 项含 StreamFetchHandler 取消用例全部通过；真实账号上首次冷缓存与弱网取消仍待实测。
- 选中 tab 记忆验证（2026-09-29）：Simulator 构建通过；166 项 KurageTests 通过（含新增的按工作区／根会话记忆与退出登录清空用例）；`SessionTabsFlowTests` 通过（新增「返回列表后重新进入仍停在子 tab、显示其正文、且药丸完整落在窗口内」断言，去掉药丸栏滚动后该断言按预期失败于 `503.0 > 402.0`，即红绿双向验证）；4 项涉及详情进入／退出的 ShellFlowTests 通过。未验证：真实账号上跨端关闭当前 tab 后重进详情的回落、后台恢复，以及跨启动恢复（记忆只在进程内）。

## Markdown 渲染（2026-09-29）

- 会话正文仍用 `MarkdownView`。围栏代码块字号通过公开的 `.font(.system(.footnote, design: .monospaced), for: .codeBlock)` 调小，不改库。行内代码底色没有公开样式，上游在 `MarkdownViewRenderer` 和 `MarkdownTextConverter` 里写死 10% 背景。
- 依赖改为 [natsustan/MarkdownView](https://github.com/natsustan/MarkdownView) 的 `feat/plain-inline-code`，钉在 `f7ba69da43c1eee1f5494d5857103d3cfe04bfd9`（基于上游 3.0.0 / `6f452b5`，只去掉这两处背景）。MIT 版权保留，模块名不变。RichText 及其他依赖仍指向上游。
- 未改围栏代码块的底色、圆角和描边。行内代码字号仍跟正文。真实会话里的行内代码和代码块字号尚未在模拟器核对。

## 当前状态

- 已读／未读：列表接入 Lody `lastMessageAt` / `lastReadAt`，空闲未读会话显示蓝点，运行中保留 spinner，VoiceOver 同时读出运行与阅读状态。详情仅在前台可见、实时同步完成、未被图片／变更／子任务面板遮挡，且对应正文完成布局并实际到达底部时写回执；用户上滚时暂停，回到底部后恢复。搜索预加载不写回执。
- 回执同步：metadata 与正文独立到达；成功拉取正文且同步前后消息时间稳定后，向原生发布可确认时间。时间变化时最多重新拉取五次，失败／取消走已有重试或重连路径。不要求正文再次变化，也不依赖可选的完成／派发字段；缓存正文、仅 metadata 活动、结束时间戳晚到均可在原生可见且到底部后写回。观察与搜索共享按仓库、工作区、会话和 Loro 版本隔离的成功同步证据，搜索自身不写回执。每会话仅保留紧凑版本和时间，不持久化正文证据或跨账号复用。
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
- 工作区选择和下拉刷新已接入真实会话列表；所有会话操作都明确携带工作区 ID。列表导航栏固定显示 Kurage 和当前工作区名称，滚动会话时保持可见。
- 会话列表默认按项目分组，项目按最近会话排序；点击项目名称行可折叠/展开该项目下的会话，折叠显示闭合文件夹图标、展开显示开口文件夹图标（MGC cute light 系列，已做成 template 资产）。右上角菜单可切换到按时间排序，打开 Archived sessions，也包含退出登录。项目名称优先从机器 Flock 文档读取；详情标题下显示项目名称与 workspace metadata 中的机器名称，缺失字段不显示。连接状态延迟 1 秒后在标题旁的固定位置显示小图标，持续 5 秒时在输入区上方显示文字，不再给导航栏增加第三行。
- 会话列表的原生 UITableView 接入下拉刷新，空状态也保留可刷新的滚动容器。底部浮着一条 Liquid Glass 搜索胶囊，列表滚到它下面。匹配会话标题，以及用户和 Agent 的普通文本正文；命中正文且标题不命中时，在标题下显示那一行。列表元数据没有正文，开始搜索后逐个读取会话文档，结果只留在内存里，列表刷新后重新读取。一次性正文读取在成功、失败或取消后卸载 CRDT 文档；正在订阅或等待订阅的同一会话保留文档。详情实时更新只标记缓存正文待索引，搜索恢复时再生成文本。打开会话或进入后台时取消正在进行的正文同步并暂停索引，取消经 operation ID / AbortSignal 传到同步桥；返回前台且无详情订阅时恢复。工具记录等未投影内容不参与搜索。真实账号上大量会话的搜索耗时尚未验证。
- 会话行可向左滑出 Archive。确认后按 Lody 的归档协议处理：目标会话及其子会话写入 `isArchived` 和 idle 状态，同步并核对 metadata 后确认成功。机器观察归档状态后释放运行时；不再写入或等待已废弃的 `archiveSession` 命令和 `needToArchiveSessions` 队列。列表仍只显示未归档的根会话。机器侧是否真正清理工作区尚未用真实账号验证。
- Archived sessions 以非全屏弹窗列出已归档且没有 `parentSessionId` 的根会话，按 `lastMessageAt`（没有则用 `createdAt`）倒序。行尾仅提供无底色的 Restore；永久删除入口暂不显示，交互待定。Restore 把该会话和它的直接子 tab 的 `isArchived` 写回 false，并只给被点的会话清掉 `isTabClosed`；由它打开的其它会话仍留在归档里。本地项目若已从机器 Flock 移除或有待删除命令，则拒绝恢复。底层 Delete 实现会先删子 tab 再 `deleteDoc` 根会话，机器通过文档删除标记回收运行时。归档列表刷新成功后清除加载错误，保留独立的恢复操作提示。真实账号的恢复和永久删除尚未验证。
- `HTTPLodyClient.streamsAccess(workspaceID:)` 按 Lody 的 `/api/loro-streams/token` 协议取得短期令牌，不会把 Streams 令牌写入 Keychain。
- `SessionSyncBridge` 使用与 Lody 相同版本的 LoroRepo、Flock 和 Streams 库，在本地 WebKit 页面中同步目录与会话文档。原生层通过 URLSession 代理 Streams 请求。
- 详情加载与实时更新：空状态以是否已取得会话快照为准，首次连接失败/重试继续显示加载占位，已有正文在重连期间保留。同步桥分开记录成功拉取的消息时间戳与可确认已读的时间戳；同一时间戳已拉取成功、但正文尚未变化时，后续流式/配置/状态更新不再重复等待 cloud sync，新时间戳仍需同步验证。已读以稳定时间戳下的成功正文同步为依据，并保留底部布局要求。本轮 160 项 JavaScript 测试、bundle 重建、138 项 Swift 测试通过；iPhone 17 / iOS 27 的首次失败重试不闪空状态与打开详情清除未读两项 UI 回归通过，重试用例追加 fixture 加载延迟后再次通过。真实账号弱网、持续输出的端到端延迟尚未实测。
- 真实客户端已支持只读会话正文和实时更新：当前详情页通过 `joinRoom()` 订阅 Session 文档与 workspace metadata，持续显示正文和运行状态。投影用户和 Agent 的普通文本，以及 history 里的 `image` / `image_group`（也保留没有 `mimeType` 的图片引用）。图片用当前账号的 Bearer 令牌从 `https://api.lody.ai/api/workspaces/{workspace}/session-images/{session}/{imageId}` 下载；fork 复制的图片用 `storageSessionId` 作为 blob 所在 session。详情里单张图走 `thumbnail?width=768&fit=scale-down&quality=85`，多张图走 320 正方形 cover，失败时回退原图，点按后看原图。工具记录等其他结构化内容不作为消息正文显示；文件修改摘要与可用 diff 在 HUD 详情中单独展示。相同图片请求共享下载，取消单个等待者不影响其它等待者，最后一个等待者退出时取消网络请求。下载先检查响应长度，并在流式累计超过 5 MiB 时中止；多图布局按聊天区域可用宽度缩小方形缩略图。真实账号的图片下载尚未实测。
- 会话单图外框按实际缩略图比例贴合，最大边 220pt，不放大小图；缺失尺寸时使用 160pt 方形占位，加载后修正尺寸。加载成功后去除灰底和描边，多图继续使用紧凑方形网格。 本次图片 fixture UI 测试在浅色默认字号、深色辅助大字号下均通过，覆盖缺少尺寸的竖图加载后 165×220pt、右对齐、多图方形和预览；真实账号图片尚未复测。
- 原生网络桥用 `URLSession.bytes(for:)` 将响应头与数据块交给 JS `ReadableStream`，包含背压和 AbortSignal 取消；写请求的请求体也由原生代理发送。Streams 库继续负责 SSE、long-poll 回退与重连。鉴权回调按需续期，401/403 强制重新获取令牌。
- JS 合并 80ms 内的变化并按 turn ID 发送正文补丁；Swift 在桥内先还原完整快照，再通过仅保留最新值的异步流交给界面，避免丢弃中间补丁导致正文缺失。
- 页面离开或进入后台释放订阅，回到前台重新同步；工作区和账号切换丢弃迟到更新。底部阅读时跟随同一条回复增长，上翻阅读时停止自动跟随。
- 真实客户端现可向空闲会话发送普通文本：独立的短生命周期 Streams 副本先确认正文同步，再写入 `latestUserMsgId` 并确认 metadata 同步。写前重新同步并检查派发指针，写后确认指针仍指向本次 turn；现有 LoroRepo metadata 写入没有 CAS，跨客户端同时写入时仍不能保证绝对互斥。未确认的发送保留 turn ID；改发文本前须先重试旧消息，防止留下未派发的历史记录。旧 turn 已被较新的派发取代时会废弃旧重试 ID。发送成功后会话列表立即更新最近排序，并从服务端刷新。普通工具权限响应仍只在 fixture 中可用；问答请求已单独接入真实写入链路（见问答支持）。
- 运行中的会话在输入区显示停止按钮，保留未发送草稿；具备 `supportsTextSendingWhileRunning` 的客户端（目前仅 fixture）同时保留发送按钮，真实客户端仍只显示停止操作；点按后从已同步的原始 history 找出最新未完成的 assistant turn，将其 ID 写入 `lastCanceledTurn` 并确认 metadata 同步。若 turn 尚未出现或已经结束，会提示重试。真实机器的停止响应仍待实测。
- 会话内 model/reasoning：输入区第一行输入文字，第二行放置操作按钮；带刻度的仪表盘图标随 reasoning 档位变化。点击后打开无箭头浮层，model/reasoning 标签位于玻璃刻度胶囊外；离散 reasoning 刻度支持点选、拖动及 VoiceOver 调整，点击模型进入 Advanced 表单。浮层打开时使用仅内存中的页面快照做渐变模糊，关闭即释放，系统键盘保留清晰显示。新建会话的 provider/model/reasoning 共用此入口，选项仍遵循代理能力；Fast 暂不可用，尚未接入真实协议。观察器从机器 Flock 文档 `${workspace}:mf:${machineId}` 的 `['acpCapability', agentConfigId]` 读取能力（cliType/agentType 须与会话一致），当前值依次取与最新用户 turn 对应的 `acpRuntimeConfig`、该 turn 的 `inputConfig`、能力的 `currentValue`。能力含 reasoning 选项（`reasoning_effort` 或 `thought_level` 类别）时只允许改 reasoning（若有 `modelReasoningEfforts` 则按当前模型过滤），以免中途换模型破坏上下文缓存；否则允许改 model（builtin 写 `modelId`，registry/custom 写对应 config option）。无能力记录时只读显示。界面和新 turn 发送共用与最新用户 turn 匹配的运行时配置基线，运行时 configOptionValues 作为完整快照替换旧值。选择仅作用于下一条新 turn，页面离开即丢弃；未确认发送的重试沿用首次发送时的选择；发送层返回实际沿用的选择，界面仅清除已发送的选择，重试时新选的配置保留给下一轮，包括明确选回原基线的值；普通发送与“Retry earlier message”入口均更新实际配置基线。运行中可预选。尚未用真实账号验证 CLI 对切换值的实际应用。
- 新建会话：列表底部搜索框右侧提供 New chat，本地项目行右侧也保留新建按钮（未分组与 GitHub 项目不显示），进入独立页面后以第一条消息创建会话。机器与默认 Agent 取自本地根会话模板；项目可切换为同机器的已登记项目，或浏览机器目录并选择其它本地文件夹，项目引用只保留 `localProjectId` / `githubRepoFullName`，不带 worktree 和分支，即直接在项目目录工作。第一条 turn 继承同工作区、同机器和同 Agent 配置最近活动的未归档根会话（跨项目）最新用户 turn 的有效配置中的 `modeId`、`modelId`、`configOptionValues`、`mcpServerIds`（不继承 Agent Role 与 `resume`），model 与 reasoning 都可在页面上选择：选项来自机器 Flock 的 `acpCapability`，reasoning 按所选模型的 `modelReasoningEfforts` 过滤，切到不支持当前 reasoning 的模型时不写 reasoning，由 Agent 默认值决定；桥在写入时重新投影并拒绝未提供的选项。写入使用独立短生命周期副本，只有它开启 `createStreamIfMissing` 以创建新 Session 文档流（对应 Lody 的 `ensureDocStream`）：先同步第一条 turn，再一次写入 metadata（`status: idle`、`title` 取前 50 字且 `titleSource: 'draft'`、`latestUserMsgId`）并确认同步，因此机器看到会话时正文已就绪。未确认时按项目在进程内保留会话 ID 与 turn ID，重试沿用首次的选择；改了文本须先重发原文。成功后替换为会话详情页，列表乐观插入后在后台刷新。Lody 桌面端创建会话前会在客户端检查免费会话额度，Kurage 没有这一步，需在 issue 中跟进。真实账号的新建、机器派发与首轮 model/reasoning 生效尚未验证。
- 新建会话配置在页面内预取并缓存各 provider 的选项，共享同一 provider 的在途请求；已缓存 provider 切换及 model/reasoning 选择立即更新本地状态，往返切换保留各自选择。尚未加载的 provider 立即显示新名称和加载状态，不展示旧模型，不允许发送；迟到结果不会覆盖新选择，页面离开或进入后台取消请求。缓存随页面释放，写入时仍由桥重新校验能力。真实账号首次加载耗时尚未测量。
- 输入区提及：已有会话与新建会话输入 `$` 显示当前 Agent 可用的本地项目、全局和系统 skills，输入 `@` 同时显示这些 skills 与当前项目的会话（含子会话，排除自身和已归档）；候选位于输入框上方，滚动视口最多展示三行。选择后保留短 token，退格或选区删除触及 token 时整段删除并移除绑定，发送时按 Lody 规则展开为 `use /token [Skill Path](path)` 或 `[@Title](session://id)`，插入或替换 token 内文字会移除绑定，失败恢复保留绑定。技能列表经当前工作区机器的 `local-project/list-skills`、`local-project/list-global-skills` RPC 获取，使用所选 provider 的目录过滤；请求可取消，不持久化令牌。GitHub 项目当前仅有机器全局/系统 skills，尚未接入 Lody 的 GitHub skill 扫描。本次 168 项 JS 测试、bundle 重建、5 项 Swift 提及单元测试、已有会话浅色/深色 fixture UI 用例及新建会话浅色 fixture UI 用例通过。真实账号的机器技能发现、跨端会话提及解析和弱网取消仍待验证。

- 2026-09-29 PR #19 技能过滤修复：旧会话缺少 `agentType` 时回退到 `cliType`，显式代理类型保持优先；无法映射的代理返回空技能候选，避免混入其它代理目录。新增旧版 CLI、显式代理优先和未知代理回归。本次 182 项 JS 测试通过，已按 frozen lockfile 安装依赖并重建 bundle；未修改 Swift/JavaScript 消息契约，未进行真实账号机器扫描验证。

- 2026-09-29 提及后台取消修复：输入区离开 active 时更换加载任务标识，通过已有桥接取消链停止未完成请求；回到前台恢复未完成加载，已加载候选保留。取消即使表现为网络错误，也不会显示失败或继续启动技能请求。新增挂载真实 SessionComposer 的 `@` / `$` 生命周期回归，覆盖 inactive 取消、background 不继续请求及 active 恢复；本次 10 项 Swift 提及测试（生命周期测试含两个参数用例）、已有会话和新建会话两项 fixture UI 提及回归通过，`git diff --check` 通过。未改桥接协议；真实账号的后台网络取消仍待实测。
- 会话底部输入区使用悬浮的 Liquid Glass 胶囊；点按发送后立即清空草稿并保持键盘，同时用同一个 turn ID 在对话列表插入用户气泡，不显示单独的发送进度提示。同步到对应 turn 时原位接管而不重复显示；若发送未确认则移除临时气泡并恢复原文供同 ID 重试。
- 已有会话与新建会话共用的多行输入框使用系统默认换行键，键盘右下角回车用于插入换行；发送通过输入区发送按钮完成。此次当前工作区快照构建成功；定向多行 UI 测试在模拟器启动应用阶段卡住，未完成键盘外观与交互验证，真机拼音键盘亦未验证。
- 已有会话的输入区在 model/reasoning 按钮左侧显示 Context window 用量环，不显示数字百分比；点按可查看已用/总 token。数据来自 Session metadata 的 `contextWindowUsage`，随订阅更新；无有效用量时不显示，新建会话尚无用量。真实账号的持续更新和真机浮层布局尚未验证。
- 聊天区域由 UIKit 容器协调：`keyboardLayoutGuide` 同步调整消息列表与输入区，通过几何测量将整个输入区的实际高度同步给 UIKit 约束并设置列表 inset；SwiftUI 保留消息样式和输入控件。消息按 turn ID 在原生列表中复用和更新，布局与正文高度变化时仅在跟随模式下贴底；上翻阅读时保存消息 ID 与其可视位置，回到底部或发送新消息恢复跟随。短会话仍贴近输入区。

- 每轮文件修改卡片：在对应 Agent 回复正文下方展示 files changed、该条记录的增删统计及前三个路径；支持折叠，超过三个文件时显示 View N more files，点击路径或更多入口打开对应轮次的 This turn 抽屉。底部 HUD 保留会话汇总。文件数据独立增长或删除时会重新配置对应消息行，沿用现有滚动跟随及阅读位置机制。 本轮通用模拟器构建、4 项 ConversationLayoutTests（含文件变更独立刷新/移除）及定向文件变更 UI 测试已通过；新增卡片折叠/展开和 This turn 范围断言。浅色截图及深色 + accessibility-extra-large 组合 UI 复测通过，验证后恢复模拟器显示设置；真实账号中的新卡片尚未设备实测。 折叠动画与 Worked for、工具组共用 0.25 秒 ease-in-out 正文淡入淡出及箭头旋转；隔离助手消息容器几何动画，阅读位置立即补偿，尊重 Reduce Motion。此次验证结果见下方 Worked for 条目。
- 会话文件修改：输入框上方的 Liquid Glass HUD 显示去重后的文件数及已知的累计增删行数，点击打开默认大屏、支持下拉缩小的详情 sheet；默认查看 Last turn，顶部菜单可切到 All turns，增删统计跟随当前范围。抽屉使用浅色白底/深色深灰底，文件头为紧凑的浅灰/深灰条目、小圆角，点击无箭头的文件头展开代码；右上角是中性的 Liquid Glass 缩放/关闭按钮组，不再使用系统导航栏的蓝色确认按钮。按会话轮次列出文件名、路径和计数。数据来自 assistant history 的 `fileDiff`；仅已完成 `tool_call.content` 中显式的 `diff` 块作为可选代码预览，不从工具标题、locations 或 shell 文本猜测文件修改。代码按行显示红删绿增和上下文，行号以工具提供的文本为准（可能只是片段）。同一轮 `fileDiff` 中同一路径的多条记录按 Lody 的 `buildSessionDiffSummary` 累加增删行数，不能让后面的零值覆盖先前计数；同一路径多轮修改保留各轮记录，汇总是历史累计，不是当前 Git 净差异；没有完整计数时 HUD 不显示对应总数，没有正文时说明代码预览不可用。空记录隐藏 HUD，删除/替换记录会清除旧结果；完整文件记录随正文缓存按账号/工作区/会话隔离。桥仅在文件记录变化时发送替换补丁，Swift 先恢复完整快照再发布；差异正文限制总传输预算和单文件大小，原生比较在后台执行并限制行数。当前没有接入机器文件 RPC，因此不提供 Unstaged、Staged、All Files 或远端完整文件浏览。真实账号返回的摘要/差异正文覆盖率和持续更新仍待实测。
- Worked for 折叠：与 Lody 一致，Agent 回复中连续的 tool call 与 thought 合成活动组（“Ran 3 commands · Read 2 files”，读/改文件按路径去重），点开列出工具标题（最多 100 条、每条 200 字，不显示输出）；thought 正文不投影，只含 thought 的组不显示。回复 `finished` 且折叠后仍有可显示的答案时，最后一段连续文本（及其后的图片/文件等不折叠项）保持可见，之前的文本和活动组收进答案上方的 “Worked for 1m 27s”，时长为 `endedAt - timestamp - permissionWaitMs`（格式 `12s` / `1m 05s` / `1h 02m 03s`），缺失时显示 “Finished working”。流式中、被中断无答案、或无可折叠工作的回复保持展开并逐步显示活动组。展开状态按 turn 与活动组保存在转录控制器里，行复用和流式重配置不会串行或丢失；统一使用 0.25 秒 ease-in-out 展开/收起，滚动锚点立即补偿，尊重 Reduce Motion。被折叠的文本仍参与搜索。运行中在本轮回复正文及工具活动上方显示 `Working… 35s`，下方以分隔线与内容分开（本次 `testWorkingTimerTicks` 已验证标签位于正文上方、计时刷新及停止后移除）：桥接投影最新未结束 assistant turn 的开始时间和已记录权限等待时长，包括尚无可见内容的 turn；原生标签每秒刷新，离开前台暂停，只在会话运行且为最后一条回复时显示，结束/停止移除。与 Lody 一样，权限等待若到结束才写入，最终数字会扣除等待时间。Worked for、工具组及文件变更卡片统一使用正文淡入淡出；消息行由显式 hosting controller 承载，隔离助手消息容器几何动画，标题不参与位移动画，箭头只旋转；展开和收起都保持当前 turn 的阅读锚点，短对话保留底部空间以避免标题跳动，折叠标题保持完整高度，活动图标槽宽随辅助字号缩放。暂未实现：plan 审批把一轮拆成多段（Lody 的 segment），以及 thought 正文展示。 当前计时与动画修改：frozen lockfile 安装、152 项 JS 测试与 bundle 重建通过；135 项 Swift 单元测试通过；Worked for 与文件变更 UI 测试在浅色默认字号下通过，Worked for 和实时计时（含停止后移除）在深色 accessibility-extra-large 下通过。上述为此前验证。此次标题位移修复：6 项 ConversationLayoutTests 及辅助大字号下 Worked for、文件变更、Working 计时 3 项 UI 测试通过；收敛动画隔离条件后再跑 6 项布局测试与大字号 Worked for 测试通过；默认字号已检查图片与长会话布局。另一个发送后键盘保持用例失败，未修改版本同样复现；尚未修复该既有问题。真实账号中的计时、折叠和流式活动组尚未实测。

- PR #16 附件顺序修复：可折叠工作之间夹有图片、图片组或文件等可见内容时，整轮保持展开，避免单个 Worked for 插入点重排内容；附件仅在工作前后时仍正常折叠。暂不扩展为多段折叠协议。此次 frozen lockfile 安装、159 项 JavaScript 测试及 bundle 重建通过，新增三项交错附件回归测试；未运行 iOS 测试或真实账号验证。

## 验证与后续

- 提及菜单键盘遮挡修复：候选区在加载提示和结果列表之间保持同一个三行滚动视口（随字号缩放），避免异步加载时先缩短再增高、使 UIKit footer 的测量与内容高度不同步；候选内容在视口内滚动和裁切；footer 高度测量变化后立即刷新 UIKit 布局和消息列表底部留白。fixture 增加长列表场景，覆盖首次展开及滚动首尾。 本轮 iPhone 18 Pro / iOS 27 模拟器验证：浅色已有会话测试通过；深色 XXXL 字号下已有会话与新建会话两条 UI 测试通过，覆盖 `$`、`@`、点选及键盘上方布局。使用英文预测键盘；真机拼音键盘尚未复测。
- 提及交互本轮调整：候选采用随字号缩放的等高三行视口，保留列表滚动；输入区高度变化后立即同步 UIKit 布局。已绑定 chat/skill 的退格和选区删除按整体处理，仍保留其它引用的 UTF-16 偏移及发送展开；光标落在已绑定 token 上不重新弹候选。本轮 9 项提及单元测试通过；最终深色 XXXL 定向 UI 回归为 3 项通过、1 项环境跳过、0 失败。模拟器截图确认普通字号/浅色和 XXXL/深色的列表均在输入框上方，最多三行；软件键盘实际位于屏幕外，已有 `exists`/边界断言不代表键盘避让验证。多行用例在完成输入区与最新消息位置检查后，对软件键盘不可见的环境明确跳过；真机拼音键盘仍待复测。

- 输入框左下新增「＋」菜单，已有会话与新建会话共用 Files、Camera、Photos。Files 使用系统文档选择器并在安全作用域内读取；Photos 使用 PhotosPicker，仅读取选择项目，不请求相册访问权限；Camera 按需申请相机权限，不写入相册。选择中阻止发送，附件可预览和移除，最多 8 项；HEIC/过大照片转换成最长边 2048px JPEG，图片上限 5 MiB，普通文件暂限 16 MiB（Lody 单次上传上限，尚未接分片上传）。草稿字节仅留内存，不落入会话磁盘缓存。
- 图片使用 cloud API 的 session-images/upload multipart（sessionId + file），文件使用 session-files/upload 原始字节与 x-session-id/x-file-* metadata、SHA-256。发送前完成上传，将返回的显式 image/file block 同时写入 history 和 inputConfig.inputBlocks，允许只有附件的消息，也支持新建首轮；保持正文先同步、metadata 后派发。上传引用按账号代次/工作区/会话/附件 ID 复用；未确认发送保留原始附件与 turn ID，重试不可替换附件。对话显示图片和文件名/大小卡片；文件下载/预览尚未提供。真实账号附件上传、机器读取附件、真机拍照和 iCloud 文件选择尚未验证。
- 附件输入区改为 120pt 圆角图片预览和紧凑横向文件标签；加号使用自适应中性色，选取后的加载占位和发送中的进度显示在附件内，保留 44pt 删除点击区域。 本次构建及附件来源 UI 测试通过；修复图片无障碍标签覆盖删除按钮后，照片预览/删除/发送测试在浅色及深色 + 辅助大字号下通过。真实服务上传与慢速照片加载仍待实测。
- 输入框中的已添加图片支持点按打开全屏大图：已有会话与新建首轮共用，直接读取内存中的待发送图片数据，复用对话图片的黑底等比预览页；关闭后保留草稿和附件，删除按钮保持独立。加载中的占位图片不可预览；大图预览不展示图片名称，保留关闭按钮和无障碍图片名称。此次 Simulator 构建通过，两项 fixture UI 测试通过，覆盖新会话/已有会话的大图打开与关闭、附件保留、删除与发送，以及既有对话图片预览。真机、深色、辅助字号与横屏尚未验证。
- 附件协议参考：Lody `packages/components/src/lib/session-image-upload.ts`、`session-file-upload.ts` 与 `packages/shared/src/session-image.ts`、`session-file.ts`、`ai.ts`；Photos 使用 Apple 的系统 PhotosPicker。
- PR #13 review 修复：附件上传将任务取消及 `URLError.cancelled` 统一转换为 `CancellationError`，其他网络错误原样传播，避免取消被界面误报为上传失败。本轮 28 项 HTTP Swift 测试通过，新增覆盖图片/文件在途取消、网络层取消、超时与连接中断；真实账号上传取消尚未验证。
- PR #13 二轮 review 修复：上传重定向 delegate 使用锁保护拒绝状态；任务真正取消时仍返回 `CancellationError`，否则被拒绝的重定向返回普通连接错误，使发送界面恢复正文并提示失败。307/308 回归覆盖同主机 HTTPS、跨主机及 HTTP 降级的错误分类，并保留在途取消及普通网络错误测试。本轮 HTTP 与图片相关 Swift 测试通过；真实服务器重定向及界面端到端恢复未实测。
- 本轮附件验证：frozen lockfile 安装、112 项 JS 测试及 bundle 重建通过；113 项 Swift 测试全量通过，最后的账号代次隔离调整后再次通过 24 项 HTTP 测试。两项新增 fixture UI 测试在最终代码通过，覆盖三种来源打开/取消、照片预览/删除/无文字新建发送；既有新建配置回归通过。检查了浅色、深色和最大辅助字号。修复底部 interactive glass 拦截重叠菜单点击、加载状态切换导致＋消失，以及大字删除图标裁切；删除按钮保留 44pt 点击区域。Files 的实际文件导入、真实服务上传和真机拍摄结果尚未验证。iPhone 17 的既有“发送后软键盘隐藏”回归仍失败；同设备原始 HEAD 对照也在同一断言失败，未将其计为通过，亦未把它归因于本次附件功能。

- 分支审查修正：代码预览按 LF/CRLF 分行，保留末尾空行并对 CRLF 同样执行行数上限；无文本差异时提前返回，跳过上下文构造。失败发送 fixture 保留首次 turn ID 与配置（包括未选择配置），与 live 重试语义一致。状态更新复用文件变更/子任务快照时，补丁跳过同一引用的重复 JSON 比较。本轮 frozen lockfile 安装、109 项 JS 测试及 bundle 重建通过；110 项 Swift 测试与 4 项定向 fixture UI 回归通过（文件详情、失败重试草稿、乐观发送去重、只读子任务返回），未验证真实账号弱网同步。后续性能项：工作区任意 metadata 变化仍会触发子任务目录扫描，需结合文档事件及父子关系做精确失效，不能只监听现有子会话而漏掉新增任务。

- 历史 UI 验证更正：此前“子代理”胶囊、浮层与只读正文抽屉验证使用的是 `parentSessionId` 子 tab fixture，不能证明真实 subagent 功能。2026-09-28 改为 history 任务投影与任务详情，验证结果见下方记录。

- 子代理任务（2026-09-28 纠正）：agents 胶囊与状态分组浮层保留，数据源改为当前会话 assistant history 的 `subagent_task`，按 `taskId` 保持首次出现顺序并采用最新记录，过滤 `skipTranscript`，状态为 Pending / Running / Completed / Failed。只读半屏详情显示任务描述、执行者、摘要、错误及可用工具/model/token 统计，跟随主会话快照更新；任务移除后显示不可用，不打开子 Session 或提供发送/停止操作，关闭保留主会话草稿。任务增删与结果增长走现有正文订阅及替换补丁，保留账号/工作区隔离与取消机制。`parentSessionId` 表示共享目录的子 tab，已退出 agents 入口；多 tab 的切换、草稿与关闭交互尚待单独实现。此前 metadata 子会话验证不能作为真实 subagent 验证。

- 2026-09-27 review 与重复发送排查：普通发送失败恢复的原文，在专用重试成功后仅当草稿仍与原文相同时清空，用户改写的草稿保留。文件抽屉的 Last turn 改用原始 history 的最新用户轮次编号（随 snapshot/patch 传输），最新轮次没有修改时显示空态；保留仅含文件修改的 Agent 行，让卡片在原始顺序与 ID 下显示，修改删除后空行随投影移除。新增跨全新 CRDT 副本的创建重试回归，覆盖正文已持久化、metadata 确认丢失及同一数据重复导入，保持唯一首轮。用户补充会话列表截图后已定位所谓五条重复：主会话创建于本地时间 09:14:36，09:15:41 通过一次 `session_create_many` 操作生成四个不同审查职责的子会话；metadata 的 `parentSessionId` 均指向主会话，每个子会话各一条任务消息。四个标题与截图完全对应，来自 review 技能要求的并行审查，并非 Kurage 重复提交首消息。Kurage 列表只展示根会话，而截图中的其它客户端也展示了这些子会话，造成数量不同。 本轮 106 项 JS 测试、106 项 Swift 测试与 4 项 fixture UI 测试通过；补充无正文参数后，4 项原生布局测试（含有/无正文文件卡片）再次通过。已按 frozen lockfile 安装依赖并重建桥接 bundle，本次截图对应事件已通过本机编排记录及 metadata 确认；合成测试不代表所有真实弱网情形均已验证。 本轮浅色默认字号截图确认最新空态、内联卡片、HUD 和抽屉正常；未重新验证深色、大字号及软件键盘弹出布局。

- 2026-09-27 文件计数修复：发现每轮 `fileDiff` 按路径建 Map 时会用后一条覆盖前一条，已改为累加，与 Lody `packages/components/src/components/sessions/session-diff-summary.ts` 的 `buildSessionDiffSummary` 一致。新增回归覆盖非零被后续零值覆盖、双向累计、路径归一化、不重复计算代码预览、未知/溢出计数和快照替换后计数减少。104 项 JS 测试通过，已按 frozen lockfile 安装依赖并重建 bundle；Swift/JS 消息格式未变，本轮未重跑 iOS 测试。后续核查截图对应的本机 Lody diff-store：同一轮的 8 个文件及计数与截图完全吻合，其中 AppModel.swift 与 HTTPLodyClient.swift 持久化计数均为 0/0，且各自 old/new snapshot ID 相同，因此本次零值并非投影覆盖导致。当前 Git 工作区中两文件分别为 +5/-0、+7/-0，与参考图一致，但 Git 工作区差异不能直接替代历史轮次数据。尚未确认上游采集为何记录相同快照；现有记录不足以恢复这两文件的历史修改前内容。此次核查未修改后端数据或伪造客户端计数。

- 2026-09-27 抽屉样式对齐：iOS Simulator 构建通过；扩展后的 fixture HUD UI 用例在浅色与深色最大辅助字号下通过，覆盖 Last turn / All turns、半屏/大屏切换、无箭头文件头展开及关闭保留草稿。截图确认白/深灰抽屉、灰色紧凑文件头、中性玻璃按钮；最大字号下窗口图标固定 20pt，避免挤出 44pt 高的按钮区域。本轮只修改 UI，未重跑 JS/模型测试。

- 2026-09-26 文件修改功能：100 项 JS 测试通过，已用 frozen lockfile 安装依赖并重新生成桥接 bundle；104 项 Swift 测试通过，补丁改为仅变更时替换后另通过 15 项定向 Swift 测试。回归覆盖摘要独立于正文、结构化证据筛选、记录更新/删除、重复路径、缺失计数、旧快照兼容和差异大小限制。iPhone 17 / iOS 27 的新 HUD 详情用例、长会话打开/阅读用例通过；最后一次重新编译的 HUD 与多行键盘回归两项均通过，确认展开差异、关闭保留草稿、输入区增长/发送及键盘可交互。旧滚动测试改为测量消息与最上方 HUD 的距离（没有 HUD 时仍用输入框），保持原间距上限并等待布局稳定。新详情用例也在深色模式和最大辅助字号下通过，截图确认单列行号、路径和增删背景可读，长代码可横向滚动。真实账号文件摘要/正文覆盖率、持续同步、真机键盘动画尚未验证。

1. 发送功能阶段已记录通过 19 项 JS 测试与 36 项 iOS 模拟器 Swift 测试（参数化共 38 次运行），包括正文同步后派发、同 ID 重试、写请求体代理、分块 UTF-8 和原生 WebKit POST。会话发送与长会话 UI 用例已在 iOS 27 模拟器通过；截图确认第二次打开键盘时最新消息仍贴近输入区，测试也确认上滑后打开键盘不会跳回底部。
2. 真实账号的只读会话已由用户实测，反馈可用；持续输出、断网恢复和后台返回各场景的结果尚未逐项记录。当前 JS 在正文变化时仍按节流周期投影完整 history；超长会话的窗口化读取是后续性能工作。
3. 文本发送已按 Lody 桌面端的用户 turn 与 `latestUserMsgId` 协议接入。用户已用真机上的 Kurage 向真实会话发送消息，且消息抵达当前会话，验证了一次正常网络下的发送与派发；网络中断时的确认、重启后的重试仍未验证。运行中 steer、排队消息和权限响应有各自协议，本阶段只允许空闲会话直接派发。问答请求现已按匹配 turn ID 和 `requestId` 写入对应 `tool_call`；普通工具权限审批仍待接入。

4. 本轮 UIKit 键盘布局改动通过 iOS 27 模拟器的 2 项布局回归测试与 3 项聊天 UI 测试，覆盖正文增长/删除、阅读消息锚点保持、发送恢复贴底、键盘反复开合和五行输入区完整避让。同一多行 UI 用例也在深色模式与系统 XXXL 字号下通过；截图已确认输入区整体随多行文字增高，发送后恢复单行，文字和发送按钮未被键盘遮挡。真机动画手感与真实账号持续输出尚未在本轮验证。

5. 本轮分支审查修复通过 56 项 JS 测试、69 项 Swift 测试，以及列表/空列表两种下拉刷新宿主集成用例；4 项 fixture UI 测试通过，覆盖列表切换、搜索、归档确认和图片预览；扩展搜索用例另在暗色和最大辅助字号下通过，截图确认无结果空态与搜索框可读，并覆盖空态/列表下拉。取消回归覆盖正文读取释放同步队列、后台暂停/前台恢复、共享图片下载的单个与最后一个等待者取消。归档测试覆盖机器命令不可用及旧队列被清理后的成功确认。真实服务弱网和机器清理行为仍待验证。

6. 本轮分支审查的六项修复通过 61 项 JS 测试与 73 项 Swift 测试（包含参数化运行）。新增回归覆盖运行时配置基线与重试不改写、搜索文档在成功/失败/取消后的释放、观察中的文档保留、实时正文延迟索引、归档加载错误清理，以及有无 Content-Length 的图片超限提前中止。桥接 bundle 已重新生成。4 项 fixture UI 场景通过，覆盖搜索、配置菜单、归档恢复和三图边界/预览；图片用例另在 iPhone 17e 的深色模式与最大辅助字号下通过，截图确认三图方形、边距和预览比例正常。预览页固定深色外观，保持黑底上的导航标题可读。真实账号下的运行时模型切换、大量会话内存占用及图片弱网仍待验证。

- 2026-09-28 对比 main 的分支审查：活动组与无 toolCallId 的步骤使用原始 history 索引，避免前置重试记录完成后被隐藏而改变 ID、丢失展开状态；运行状态变化只重配旧／新末尾消息行，只有读写工具扫描文件路径。新增稳定 ID 回归，153 项 JS 测试通过，已按 frozen lockfile 安装并重建 bundle；24 项 Swift 模型／布局测试和 4 项 fixture UI 测试通过，覆盖长会话阅读、文件卡片、Worked for 展开保持及运行计时停止。未复测深色／大字号或真实账号，已有动画衔接限制仍待后续优化。

## 之后的增量

普通工具权限操作在 fixture 中使用系统确认对话框；其真实写入路径仍待接入。问答使用独立卡片和 capability，已接入真实响应链路。文本发送的重试 ID 当前只保存在进程内；重启后若先前请求结果未知，需检查真实会话后再重新发送。

## 协议核对入口

- Lody `packages/shared/src/loro-streams-auth.ts`：工作区 Streams 令牌请求及刷新。
- Lody `packages/shared/src/index.ts`：工作区目录与 Session 流 ID。
- Lody `packages/shared/src/schema.ts`：工作区目录、Session 元数据和会话文档结构。
- Lody `packages/components/src/providers/create-workspace-runtime.ts`：现有客户端的流传输接线。
- Lody `packages/components/src/hooks/use-session-actions.ts` 与 `packages/components/src/components/sessions/session-chat-interface.tsx`：用户 turn 写入及派发流程。
- Lody `packages/components/src/components/mentions/mention-skill-source.tsx`、`mention-session-source.ts`、`packages/components/src/lib/local-project-skills-provider.ts`、`packages/shared/src/acp/skills.ts` 与 `packages/loro-streams-rpc/src/rpc.ts`：提及 token 展开、当前项目会话过滤、技能目录、机器 RPC。
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
- Lody `packages/acp-extension-codex/src/CodexToolCallMapper.ts` 的 `createSubAgentActivityUpdate` / `formatSubAgentActivityTitle` 与 `packages/shared/src/acp/claude-subagent-task.ts` 的 `parseLodyTaskMeta`：子代理活动经 `_meta.lody.task` 落库为 `subagent_task`，`taskId` 是活动 id、`actor` 是子代理名；`packages/shared/src/acp/history-apply.ts` 按 `taskId` 合并。

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
- 审查修复：刷新错误发布前同时检查调用任务和共享请求的取消状态，避免桥接取消以非 `CancellationError` 返回时误报刷新失败；加入同一请求的手动等待者也不会发布该取消错误。本次 `AppModelSessionRefreshTests` 10 项测试通过，新增参数化回归覆盖取消时静默、未取消时保留失败提示。真实账号的 WebKit 取消路径本轮未实测。

### 详情已读回执修复

- Lody `session-execution-service.ts` 在最终正文 `waitUntilSynced` 后才调用 `setLastMessageAt`；原先要求正文再次变化，导致晚到的结束时间戳无法生成回执。首轮修复以最新已结束回复和派发 ID 匹配作为补充条件，但这仍依赖可选字段，未覆盖重复打开不再变化的缓存正文。
- 后续修复删除上述正文变化／完成字段门槛，使用已有的稳定时间戳正文同步结果；原生前台可见、同步连接、底部布局条件保持不变。Lody 的时间戳没有绑定正文版本，因此不能通过“本次正文变了没有”证明消息对应关系，也不能承诺跨文档原子快照。同步失败、取消、时间戳持续变化仍不会发布回执；新时间戳需要新的成功同步。
- 本轮缓存正文回归先复现失败再通过；163 项 JavaScript 测试通过，已按 frozen lockfile 安装依赖并重建 bundle。补充覆盖无可选派发字段、metadata-only 活动、预加载及重新打开，并验证同步证据的仓库／工作区／会话／版本隔离。本轮另通过 5 项 Swift metadata 测试及 2 项 fixture UI 测试（打开详情清除未读、长会话定位与上滚保持）。真机截图中的会话尚未安装本轮代码验证。

## 2026-09-28 子代理语义纠正

- 协议参考：Lody `packages/shared/src/ai.ts` 的 `SubagentTaskPayload`、`acp/history-apply.ts` 的任务合并、`acp/codex-collab-agent-task.ts` 的 Codex 生命周期转换，以及 `packages/components/src/components/ai-gui/subagent-task-panel.tsx`。`schema.ts` 明确将 `parentSessionId` 定义为 child tab。
- 本轮验证：frozen lockfile 安装、164 项 JS 测试和 bundle 重建通过；141 项 Swift 测试通过，补充摘要/token/tool 字段断言后 8 项 ConversationChangesTests 再次通过。iPhone 17 浅色默认字号子代理 UI 用例通过，4 张截图检查通过。深色辅助大字号使用本轮先前通过的构建执行 test-without-building：子代理流程断言通过，但末轮文件变更卡片 isHittable 断言失败，整条用例不计通过。测试结束后的自动诊断长时间未完成，已中止诊断收尾；深色 4 张截图已核验：子代理胶囊/浮层/详情可读、草稿保留；父会话正文区域空白，与文件卡片断言失败吻合，该布局问题尚未修复。补充构建被同时进行的输入框修改阻断（ComposerMentionState 尚未被当前 Xcode 项目识别），未覆盖或回退该修改。真实账号的任务持续更新、后台恢复及网络恢复尚未实测。


### 子代理按 subagent 归并（2026-09-29）

- 问题：Codex 的子代理生命周期活动（`Start / Interact / Complete subagent <name>`）在 history 中各自是一条 `subagent_task`，`taskId` 是活动 id；此前按 taskId 逐条展示，一个子代理在胶囊与浮层里显示为 21 个 agents。
- 投影改为按子代理归并：标题点出自身 actor 的活动（描述含 `subagent` 且以 actor 结尾，对应 Lody `CodexToolCallMapper.createSubAgentActivityUpdate`）以 actor 为身份，其余任务仍按 `taskId` 各自一行（Claude/Devin 与 collab 任务的身份本来就是稳定 id）。每个子代理保留 `steps`（活动顺序、状态、摘要/错误），整体状态取最后一条活动，摘要/用量等字段沿用「后到者覆盖、缺省保留」。胶囊计数即子代理数量，单数显示 `1 agent`。
- UI：胶囊图标改用 MingCute `robot_cute_re` 资源（template 渲染），浮层每行显示子代理名称，名称与执行者相同时不再重复副标题；只读详情在摘要与用量下方列出 Steps，仅在多步时显示，单步任务不出现该区块。
- 已知边界：payload 中没有子代理 thread id，同一会话内同名的多个子代理会合并为一行；`skipTranscript` 仍按 taskId 移除对应步骤，步骤清空后该子代理随之消失。
- 本轮验证：frozen lockfile 安装、213 项 JS 测试与 bundle 重建通过；164 项 Swift 测试通过，1 项 fixture UI 测试（胶囊计数与图标、浮层、详情 Steps、草稿保留）通过并检查截图。同一用例在保留旧 App 容器的模拟器上会停在既有的正文空白／文件卡片 `isHittable` 断言，卸载 App 清除容器后同一设备通过，未归因于本次改动。真实账号下的活动持续更新、同名子代理与网络恢复尚未实测。

## 问答支持（2026-09-29）

- 协议参考本机 Lody `ea3d599e`：`shared/src/acp/ask-user-question.ts`、`shared/src/history-writer.ts`、`components/src/hooks/use-permission-response.ts` 和 `components/src/components/sessions/floating-permission-request.tsx`。兼容 Lody elicitation v1、Claude AskUserQuestion、Codex requestUserInput 元数据，按来源写回答案命名空间；不是普通聊天发送，也未开启一般工具权限审批。
- 底部 Question 玻璃卡片支持自由输入、单选、多选、多题翻页、附加备注和私密字段。草稿按请求身份保留，所有问题完成后显式 Send；Skip 和右上关闭均采用桌面端的跳过选项。过期显示 Continuing 并禁用操作；会话停止或同步中的请求 outcome 到达后撤下卡片。可同时出现多个请求，逐个处理。
- 问答 snapshot/patch 显式携带请求列表和删除。写入使用独立、可取消的已有 Streams 副本，工作区/会话/turn/request 四层定位，读取后重新核对元数据、结束状态、截止时间和已有 outcome。保留原有 CRDT 容器与无关字段，只修改匹配请求的 outcome；已存在相同答案视为重试成功，不覆盖不同答案。原生阻止同账号/工作区/请求的并发写入，成功需确认正文同步。
- 卡片提交后保留同一答案供失败/取消重试，不产生新 turn；草稿与未确认答案只在当前页面内存中保留。跨端同时写入没有 CAS 保证；已同步的 outcome 会阻止后来的覆盖，但不能承诺绝对互斥。离开页面或进程退出会丢失未确认答案，重新进入先以服务端请求状态为准。
- 本轮 frozen lockfile 安装、180 项 JavaScript 测试和 bundle 重建通过；151 项 Swift 测试通过，包含问答解码、patch 删除、工作区隔离和真实 WebKit→原生网络取消回归。问答 fixture 使用独立 `--fixture-questions` 参数，不改变默认列表数据。浅色默认字号和深色 accessibility-large 各 2 项问答 UI 用例已通过，最终一轮构建、151 项 Swift 与 2 项问答 UI 测试全部通过。截图已核对卡片、输入草稿、翻页与提交/跳过结果；大字号下选项区域可滚动，页脚保持可见。模拟器始终未显示软件键盘，重启/键盘偏好设置无效，CUA 按名称和路径访问 Simulator 均返回 Invalid app，因此软件键盘避让尚未验证；已恢复模拟器原偏好。真实账号问答、跨端同时回答、断网与后台恢复仍待实测。

## 新建会话目标选择（2026-09-29）

- Session 列表底部搜索框右侧新增 New chat 入口，沿用项目行新建入口与首条消息编辑页。点击项目名称显示锚定在该行的原生菜单，底部 Add new folder 直接打开目录 sheet；项目菜单读取所用机器的已同步项目目录，包含尚无历史会话的项目；切换保留输入草稿与附件，重新加载目标对应的 provider/model/reasoning，提及会话与技能也使用所选项目。
- Choose Folder 使用机器 `local-project/browse-dir`，支持返回上层、目录分页、空目录、半屏／全屏 sheet 与失败重试。确认通过 `local-project/prepare-add` 校验并规范化路径，再在当前工作区的机器 Flock 中仅在记录不存在时登记项目、等待同步；不会覆盖已有项目自定义名称。参照 Lody `packages/shared/src/message.ts`、`packages/components/src/lib/local-project-import.ts`、`providers/workspace-writer-impl.ts` 和 CLI `message-handler.ts`。本功能选择已有目录，不创建磁盘目录。
- 创建请求显式携带目标项目，在读取配置和首轮写入时核对机器、项目存在性及待删除状态。模板只提供同机器的 agent 配置；创建仍直接使用项目目录，不创建 worktree 或切换分支。原有待处理记录的项目 key 传至写入桥，重试保留首次目标、模板、首轮与会话 ID。目录请求和校验支持取消、后台暂停与账号／工作区过期结果隔离。
- 当前入口仍需至少一条可用本地根会话提供机器及 agent 模板，完全没有本地会话的工作区尚不能从零创建；机器选择沿用入口模板，本轮不新增跨机器切换。真实账号目录权限、远端机器离线、跨端同时登记与实际派发尚待验证。
- 本轮验证：frozen lockfile 安装、205 项 JavaScript 测试及 bundle 重建通过。最终使用独立 DerivedData 完整构建并通过 161 项 Swift 测试（包括项目读取／选择的 WebKit→原生网络取消、未确认创建原目标重试）和 2 项 fixture UI 测试；新流程另用同一最终构建在深色 accessibility-extra-large 下复测通过。浅色与深色截图已核对项目切换、目录层级、确认、草稿保留及创建后导航，未发现遮挡。初轮共享增量缓存的链接错误通过独立构建消除；真实服务与真机键盘手感未验证。


### 新建会话项目菜单与目录点击修正（2026-09-29）

- 按参考交互移除独立 Choose Project 页面，Project 行直接打开原生菜单，显示 Projects、当前项目勾选和 Add new folder；后者直接呈现半屏／全屏 Choose Folder，无额外导航层。目录使用中性色 plain 列表，整行内容区域可点击，确认和取消固定在系统导航栏；加载／选择进度显示在面板中央，避免长列表把反馈推到屏幕外。
- 修复同路径导航没有改变 task identity、却已进入 loading 状态导致停留加载的问题：每次进入目录都使用新的请求身份。核对 Lody browseDirectory 返回的是 realpath，文件夹与符号链接可能共享 absolutePath；目录行身份改为名称与 canonical path 组合，分页合并也保留不同别名，不再发生重复行身份与别名被丢弃。
- 原有选定路径、工作区隔离、取消、注册及未确认创建重试语义保留。本轮未改 JavaScript 协议或 bundle。
- 本轮 29 项相关 Swift 测试通过；fixture UI 已验证原有项目入口，以及新菜单、目录行尾点击、同路径连续进入、共享 canonical path 的两个别名、返回上层、确认后保留草稿与发送。软件键盘未在模拟器截图中显示，键盘布局不计验证通过；真实账号远端目录交互仍待实测。
- 新流程浅色默认字号与深色 accessibility-extra-large 回归通过；大字号截图发现目录图标放大而占位宽度固定，已改为随字号缩放，重建后深色完整流程再次通过。

### 新建会话视觉精简（2026-09-29）

- 新建页选择项目后仅显示项目名称，移除额外的本地路径行。目录面板加载／确认仅显示居中转圈，移除材质底色及可见说明文字，保留辅助功能标签。
- 目录行使用明确的上下 4pt 内边距，默认行高约 52pt；图标与文字间距缩为 12pt，保持整行可点击和大字号自适应。

## 审查修复轮（2026-09-29）

- 桥接鉴权作用域隔离：页面级 `activeWorkspaceOperation` 改为只由共享工作区副本读取（`createWorkspaceRepo` 的 `usesActiveOperation`），写副本与独立副本始终使用自身作用域。此前与一次性读取并发时，发送／取消／归档／问答等副本会借用读取的 operationID 与取消信号，读取结束即被 `endOperation` 与 abort 波及。项目菜单的 catalog／browse 改为复用共享副本（select 仍用独立写副本），`describe` 改为单趟遍历建立 localProjectId→最近会话映射。
- 会话观察的 metadata watcher 恢复按文档过滤：只有本会话、其根会话与根的子 tab 会触发重投影，`doc-existence-changed` 与携带 `parentSessionId`／`childSessionPlacement`／`isArchived` 的补丁始终放行。此前工作区任意会话的状态、用量与标题变化都会重扫目录并重新发布本会话快照。
- 子代理状态：Codex 只产生 `started`／`interacted`／`interrupted` 三种活动，没有完成活动，`Complete subagent` 前缀分支为死代码已删除。子代理在被中断时为 failed，否则随所在 turn 结束（`finished`／`endedAt`）变为 completed，turn 运行期间保持 running，turn 结束后的子代理不再永远显示运行中。
- 发送／取消／问答恢复对子会话的限制，并收窄为「非 tab 的子会话」（side-panel 与嵌套孙会话），与 tab 定义（`isSessionTab`）一致。当前 UI 无法到达这些会话，属防御性一致性。
- 提及：切换项目不再清空绑定。输入区在草稿含技能提及时，即使未打开候选菜单也会按新来源重新加载技能并解析：同 token 的技能指向新项目路径，新来源没有的技能连同草稿 token 一起移除（会话提及是绝对链接，保持不变）。代价是含技能提及的草稿在来源变化时多一次技能 RPC。
- 原生：tab 投影为空时不再覆盖已缓存列表（根会话在其它端被归档时曾清空 tab 栏并把用户弹回 Main）；`markSessionRead` 去重覆盖 tab；`startSession` 的模板／项目配对改为按当前会话列表判断（模板属于该项目，或该项目尚无任何会话），不再依赖目录读取缓存，修复目录刷新后与操作无关的 notConnected；`sessionSummary`／`sessionTabs` 改查 `sessions` 索引；运行状态统一为 `observedActivity ?? session.activity`；`attemptedTabWrites` 按账号／工作区／会话登记；`newSessionTabOptions` 合并进 `newSessionOptions(isTab:)`，fixture 复用同一选项读取与 run-config 应用逻辑。
- 已知未修：`ConversationTabsView` 的 `.id(activeID)` 仍随切 tab 重建会话子树（移除需要逐项重置约 18 项会话语义状态，需单独验证）；被旧版客户端「关闭并归档」的 tab 仍不能在 Closed tabs 中重开（Lody `reopenSessionTab` 会先 restoreSession）；live 客户端「上传失败且从未写入」分支仍无测试覆盖。
- 本轮验证：frozen lockfile 安装、213 项 JS 测试与 bundle 重建通过；165 项 KurageTests 通过（含新增的技能提及重解析用例，首轮因 fixture 与 AppModel 的配对校验口径不一致失败一条，改为按会话列表判断后全通过）；4 项相关 fixture UI 测试通过（tab 创建/切换/关闭/重开与草稿独立、技能与当前项目会话提及、新建页项目提及、提及整体删除）。真实账号上的并发取消、跨端 tab 状态与根会话归档路径仍未实测。

## 相对 main 的审查修复（2026-09-30）

- 取消隔离：移除共享副本的动态 `activeWorkspaceOperation`。新建选项、项目目录与目录浏览的一次性网络读取使用自己的鉴权与取消作用域，完成或取消均先 abort 再销毁短期副本，避免终止共享会话的实时 SSE；鉴权返回后再次核对取消，阻止已经取消的请求继续启动。
- 配置读取：继续复用同工作区的已同步元数据；机器 Flock 始终独立刷新。只有仍在观察、正文版本及 `lastMessageAt` 同步证明一致的历史可复用，返回前再核对，若期间变化则在独立副本重读。其它 provider 的完整历史只在短期副本中加载并释放；清理共享历史时保留活跃及等待建立的观察。
- 标签发送：发送、取消、乐观消息、错误提示和未确认重试状态与草稿一起按 tab 保存，不随 `.id(activeID)` 重建丢失。发送中禁用该 tab 的输入框，其它 tab 仍可编辑；切回后从模型缓存接收已完成发送的正文。保留现有会话子树重建方式，让滚动、面板和读取状态继续按会话重置。
- 标签回退：原生观察显式传递根会话 ID。已记住的 tab 被关闭、归档或删除时，桥先发布根会话的权威标签列表，再释放观察，模型切回 Main；同时覆盖正文同步期间删除和缓存元数据过期后无法打开文档的情况。根会话无法解析所产生的空投影仍不清除缓存。
- 技能提及：来源切换后，在新来源技能加载并重新解析完成前禁用发送；失败时保留草稿并显示 Retry，即使候选菜单已经关闭也可恢复。发送失败恢复的技能草稿也会重新触发解析，避免切换 tab 后停在禁用状态。项目目录选择模板复用 `activityTime`，让没有 `lastMessageAt` 的新根会话按 `createdAt` 正确排序。
- 本轮验证：frozen lockfile 安装、233 项 JavaScript 测试和 bundle 重建通过；167 项 Swift 测试（含 WebKit→原生请求取消）及 7 项相关 fixture UI 用例通过。最后补齐技能草稿恢复触发后，4 项提及／发送失败 UI 再次通过；技能刷新失败与重试另在深色 accessibility-extra-large 下通过。已核对浅色和深色截图中的输入、键盘避让、禁用发送与重试入口，并恢复模拟器原设置。真实账号下的持续输出、跨端关闭／归档／删除、网络恢复与后台返回仍未实测。

## PR #20 审查修复（2026-09-30）

- 项目目录认证回调从原生桥的 `{ token }` 回复中提取令牌字符串。原先返回对象，固定版本的 StreamsClient 在令牌规范化时调用 `trim()` 失败，导致真实客户端的文件夹浏览与选择无法发送机器 RPC。
- 新增浏览和选择两项回归测试，通过实际 StreamsClient 与原生 fetch 适配器核对认证令牌、工作区及操作作用域；修复前均失败，修复后通过。
- 本轮验证：frozen lockfile 安装、235 项 JavaScript 测试及 bundle 重建通过。未改动原生消息契约；本轮未运行 iOS 测试，真实账号远端目录交互仍待实测。

## New Session 选项读取性能（2026-10-01）

- New Session／New Tab 复用列表已确认同步的机器配置投影，缓存仅包含 Agent、ACP capability、本地项目和项目删除命令；默认配置仅保留 mode/model/configOptionValues/MCP 选择，不保留其它 provider 的完整历史或网络副本。缓存随共享工作区副本释放，按机器／来源会话定位，最多保存 16 台机器和 64 份配置。
- 同一空闲来源会话在消息时间、派发指针和 Agent 身份未变化时可直接读取默认配置；运行中、等待派发、缺少消息时间及活跃观察中的来源继续走原有正文同步／版本证明。读取前后 metadata 变化不记录缓存，读取失败或取消不保存未确认的默认配置。
- 30 秒内的缓存直接返回；较旧但来源未变化的缓存先显示，原生随后发起独立、可取消的刷新，并按新的能力表保留仍可用的 model/reasoning 选择。刷新失败保留已展示快照；配置来源变化时先读取新的来源。机器名称直接取现有会话摘要，不再等全部选项读取完成才显示。
- 写入仍使用独立副本重新验证机器、目标项目、Agent 和选项；创建被拒／未确认以及目录注册后清理选项缓存，让重载可读取服务端更新。缓存中的删除命令或 Agent 表导致选项读取失败时，清理缓存并独立刷新一次再判定不可用。取消作用域不借用共享实时 SSE；缓存不持久化，也不包含 Streams token。
- 本轮验证：frozen lockfile 安装、251 项 JavaScript 测试和 bundle 重建通过，包括列表机器快照复用、重复打开 0 次网络同步、陈旧缓存先返回、刷新取消、工作区／gateway 隔离、缓存容量以及写入验证。44 项 Swift 定向测试通过；浅色的项目／目录选择和项目行创建两个 fixture UI 用例通过，项目行创建在深色 accessibility-medium 下再次通过。最终用仅包含本次 Swift 改动和最新 bundle 的隔离副本重跑 44 项 Swift 测试及 tab 创建／切换／关闭／重开用例，全部通过，并检查截图中的机器名称、键盘避让和 model/reasoning 选择。
- 共享工作区的最后一轮构建被并行图片加载闭包的 Sendable 编译错误阻挡；共享工作区的 tab UI 尝试在进入新建页前被并行 MentionEditor 聚焦递归阻挡，主线程 sample 已确认该路径，隔离副本未出现。深色辅助字号下既有 Advanced 底部提示贴近 home indicator；这些并行／已有问题未在本次修改中处理。真实账号冷启动、弱网耗时与真机尚未测量。
