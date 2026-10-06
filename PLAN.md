# Kurage 会话功能

## 撤回 Sheet 底部外部留白（2026-10-07）

- 按用户要求取消独立浮动面板方案，删除 `FloatingSheet`，设置、归档会话、机器文件夹、Advanced、错误详情、文件修改及子代理详情恢复原来的系统 `.sheet`、detents、背景、圆角与拖动条。移除该方案引入的留白和自定义拖动测试断言，相关测试恢复到改动前。
- 保留同一提交中的缓存统计、Quick Actions 配置／图标／工具栏顺序及其他功能改动；当前未提交的 Quick Actions 加载修改不包含在本次撤销提交中。工程已重新生成。
- 本轮在独立检出目录验证，iPhone 16 Pro／iOS 27 Simulator 构建与设置、错误详情、Advanced 三项 fixture UI 回归最终通过；截图及 AX 层级确认恢复系统面板、原高度和拖动条，工作区导航、复制／关闭／重开、配置修改和返回 composer 正常。Advanced 首轮发送步骤因键盘动画期间测试使用旧坐标而误点键盘，源码与测试均未修改，唯一一次原样重试通过。`git diff --check` 通过；本轮未复测真机、iOS 26、iPad、深色大字号或真实账号，未改同步协议或 bridge。

## Quick Actions 分支图标（2026-10-06）

- 会话右上角 Quick Actions 使用用户提供的 `git-branch.svg` 替换 SF Symbol 闪电。保留 SVG 的分支结构、圆形节点、圆角端点和线宽，24pt 原生尺寸与相邻加号一致；资源使用矢量与 template 渲染，继承工具栏前景色，随系统浅／深色外观变化。沿用 Quick Actions 的菜单、加载状态和辅助功能标识。
- 按用户要求将 New tab 加号与 Quick Actions 对调，工具栏从左到右为加号、分支图标、会话选项省略号。
- 本轮 iPhone 17／iOS 27 Simulator 编译及 3 项 fixture UI 验证通过（浅色默认字号 2 项、系统深色 accessibility-medium 1 项），覆盖 Quick Actions 菜单、PR 子菜单、任务创建，以及新位置加号的 New Tab／切换／关闭／重开与独立草稿。浅／深色截图和 AX 层级确认图标清晰、颜色正确、三个按钮对齐且顺序一致，辅助功能标识保留；SVG 几何逐项与用户附件核对一致，`git diff --check` 通过。初轮构建遇到并发更新的浮层工程引用及 UI 测试编译问题，现行文件更新后重新构建并完成验证。专属模拟器已关闭并删除；真机、iOS 26、iPad、最大辅助字号与 VoiceOver 实操本次未验证。

## Quick Actions 样式与独立 Review 配置（2026-10-06）

- Settings → Quick Actions 使用与其他设置页一致的背景、灰色 20pt 圆角卡片、16pt 页边距、18pt 行内留白和细分隔线，替换系统 Form。机器仅保留一行选择；菜单值使用次级颜色，长名称或辅助字号放不下时改为纵向排列。
- 配置分为 Review 与 Git Actions。Review Changes 使用独立的 Agent／Model／Reasoning；创建分支、提交、推送和两种 PR 共用 Git Actions 配置。执行时按动作选择对应配置，仅影响新任务 tab 的首轮输入，不改变主会话。按用户要求不提供 Use Session Defaults 按钮，包括错误 alert。
- 保存范围仍为本机的账号／工作区／机器。旧共享配置在读取时作为两组初始值，首次更新保存为独立组；修改其中一组保留另一组。失效配置只阻止对应动作组，界面提示到 Settings 更新。已保存的 Agent 被移除时，设置页刷新当前可用 Agent 目录并让用户重新选择，不静默改用另一 Agent 执行。保留能力校验、取消、工作区隔离和命名 tab 的既有协议。
- 本轮 Simulator 编译、26 项 QuickAction／SessionTabs Swift 定向测试、3 项 fixture UI 验证通过（浅色默认字号 2 项，系统深色 accessibility-medium 1 项）。回归覆盖八种动作的首轮配置路由、旧配置迁移、持久化、失效配置组隔离、已移除 Agent 的设置恢复逻辑、两组独立修改、重启保存、命名任务 tab 与主草稿保留。截图及 AX 层级确认三行卡片、无默认按钮／尾线、辅助字号换行、滚动和底部菜单正常；没有新增 Swift 并发警告。`git diff --check` 通过，专属模拟器已关闭并删除。未修改 JavaScript bridge，未运行 JavaScript 测试；真实账号执行、真实长主机名、移除 Agent 的恢复 UI、真机、iOS 26、iPad、最大辅助字号与 VoiceOver 实操尚未验证。

## Markdown 链接圆点加粗（2026-10-06）

- 按参考截图将链接圆点直径从 `max(0.7, 行高 / 24)` 调整为 `max(1.3, 行高 / 13)`，常规字号直径约增加 85%；中心间距从直径的 2.8 倍改为 2.4 倍，使粗细与疏密更接近参考。圆点随正文与辅助字号缩放，保留语义灰色、每行位置与末尾单色箭头。改动位于现有 MarkdownView fork 的圆点绘制器，客户端依赖固定到 `39166ee72f79d61c00065544bf3b4938f084cef6`，XcodeGen 已重新生成工程。
- 本轮最终 19 项既有 Markdown 库定向测试、客户端远程固定版本的 Simulator 构建与 6 项 fixture UI 检查通过。iPhone 18 Pro／iOS 27 的浅色、系统深色与 Accessibility XL 截图及 AX 层级确认 PR 链接圆点更清晰，换行、粗体／行内代码、列表、表格与下伸字母正常；原生链接点击精确打开完整目标、文字选择与长会话最新位置／向上阅读回归通过。验证 harness 仅在临时副本，专属模拟器已关闭并删除。初轮加粗 50% 仍略细，最终按参考继续调整直径与间距后复测；临时 harness 的字符串缩进及 Safari 首次启动定位问题已修正，最终断言保持完整目标验证。`git diff --check` 通过。未修改模型、同步协议或 JavaScript bridge，未运行 JavaScript 测试；真机、iOS 26、iPad、VoiceOver 实操和真实账号本轮未验证。

## 暂停按钮配色修复（2026-10-06）

- 输入区暂停按钮的圆形底色改为显式系统 `label` 色，避免 `Color.primary` 在玻璃输入区内受图标前景色影响而呈灰色。启用时浅色为黑底白色方块，深色为浅底深色方块；继续使用中性配色，禁用时保留低透明度。
- 本轮 iPhone／iOS 27 Simulator 构建与 3 项 fixture UI 验证通过（2 项现有配色／steer／停止回归，1 项仅位于临时验证副本的外观检查）；逐张核对 Day／Night × Blue／Black 的收起／聚焦共 8 张暂停截图，确认黑白底色与方块对比正确，按钮可用。`git diff --check` 通过，专用模拟器已关闭；未修改发送／停止协议与状态逻辑，未复测 iOS 26、真机、真实账号或辅助大字号。

## Agent 错误展示（2026-10-06）

- 接入 Lody `system_notice / chat_failed`，支持机器写入的独立 `system` turn 与 assistant turn 内的失败事件。错误使用独立内容类型，保留历史顺序、turn ID 和完整 `reason`／`code`／`message`；只有错误的 turn 也可见，assistant 内的错误不会被收入 “Worked for …” 折叠。其它 system 文字与未知 notice 仍不作为聊天正文显示。
- 会话内按 iPhone 参考图展示单一错误消息块：body 字号的橙色完整原文、灰暖色 1pt 细边框、浅暖底色、18pt 圆角和四边 12pt 留白，不再增加图标、标题分区、正文缩进或常驻操作栏。浅色颜色从参考图转换至 sRGB 后采样，深色模式单独调整边框与底色透明度。点击整块消息打开详情，沿用 subagent 的不透明系统背景色、默认半屏、可上拉展开和可见拖动条；长报告可滚动查看。长按菜单或详情页工具栏复制完整错误报告；原因、诊断码和未截断原文仍保留。无原文时显示失败标题，AX 提供失败类型与完整原文；不增加认证、重试或普通工具权限服务能力。
- 协议参考：本机 Lody `packages/shared/src/ai.ts` 的 `ChatFailedMeta`，CLI `apps/cli/src/lib/message-handler.ts` 的 `recordChatFailure`（写入 `role: system`），以及 `packages/components/src/components/ai-gui/view.tsx`／`chat-failed-error-report.ts` 的标题与可读消息提取规则。
- 初次接入的验证（样式优化前）：frozen lockfile 安装、346 项 JavaScript 测试、bundle 重建、Simulator 构建和 37 项 Swift 定向测试通过，工程已用 XcodeGen 重新生成。iPhone 17／iOS 27 的浅色默认字号、系统深色 accessibility-medium 各通过 1 项 fixture UI 流程；截图与 AX 层级确认标题／正文换行、按钮自适应纵向排列、详情关闭和重开会话正常，系统剪贴板核对了完整原文。首轮发现父卡片标识覆盖按钮标识，已通过独立 AX 容器修复并复验；首轮 Xcode 自动诊断收集被安全终止，成功轮保留了截图和 hierarchy。专属模拟器已关闭并删除，`git diff --check` 通过。真实账号的失败同步、连续输出、弱网／后台恢复、其它长标题枚举、iOS 26、iPad、最大辅助字号、VoiceOver 实际操作与真机尚未验证。
- 上一轮无边框行内样式的 Simulator 构建及浅色默认字号／系统深色 accessibility-medium 两轮 fixture UI 验证通过（各 1 项）。截图与 AX 层级核对了图标基线、正文／详情缩进、自然换行、44pt 点击区域、独立按钮标识、完整详情、复制反馈和重开会话；系统剪贴板确认两轮均保留完整错误报告。仅修改 SwiftUI 展示，该轮未重跑 JavaScript 或 Swift 单元测试；真实账号、iOS 26、iPad、最大辅助字号和 VoiceOver 实际操作仍未验证。
- 上一轮保留通知卡片结构、恢复边框后的 iPhone 17／iOS 27 Simulator 构建通过，浅色默认字号与系统深色 accessibility-medium 各通过 1 项 fixture UI 测试。截图与 AX 层级核对了边框、圆角、浅底、内边距、自然换行和 44pt 操作区域；详情、复制反馈及重开会话正常，系统剪贴板保留完整错误报告。该轮只调整 SwiftUI 样式，未重跑 JavaScript 或 Swift 单元测试；随后按用户反馈改为上面的单一消息块结构。
- 上一轮单一消息块的 iPhone 17／iOS 27 Simulator 构建通过，更新后的 fixture UI 流程在浅色默认字号与系统深色 accessibility-medium 各通过 1 项，覆盖整块点击详情、详情页复制反馈、长按菜单复制和重开会话。逐张对照参考图核查了无图标／标题／操作栏的结构、等距留白、细边框与完整原文；浅色截图的文字／底色／边框与参考转换至 sRGB 后的三组像素值一致。深色大字号下卡片四边及 status:400 结尾完整可见，AX 核对无截断或安全区遮挡；两轮剪贴板保留完整原因和原文。该轮未改模型或同步协议，未重跑 JavaScript 或 Swift 单元测试；真实账号、iOS 26、iPad、最大辅助字号、VoiceOver 实际操作与真机尚未验证。
- 上一轮详情默认半屏的 Simulator 构建及浅色默认字号／深色 accessibility-medium 各 1 项现有 fixture UI 测试通过；两轮截图与 AX 均确认 Sheet Grabber 为 Half screen（iPhone 17／iOS 27，451pt sheet／874pt 屏幕）。常规字号报告完整可见，大字号报告保留全文并提供滚动区域，复制、关闭、长按菜单与重开会话正常。未实操拖动展开或手势滚动，未复测真机；未改同步协议或模型，也未重跑 JavaScript／Swift 单元测试。
- 本轮补齐与 ConversationSubtaskSheet 相同的 `presentationBackground(Color(uiColor: .systemBackground))`，Simulator 构建及 1 项浅色默认字号 fixture UI 测试通过。截图确认整张 sheet 为不透明白色，空白区域采样为 RGB 255/255/255，无下层橙色透入；AX 仍为 Half screen，复制、关闭、长按菜单与重开会话正常。只补一项背景设置，本轮未复测深色、真机或展开手势，未重跑 JavaScript／Swift 单元测试。

## Quick Actions 零行数分支变更修复（2026-10-06）

- `diffStats.allChange` 是行数统计，`0/0` 无法排除二进制、文件权限或空文件变更。桥接仅在工作树干净且行数非零时确认 `hasBranchChanges: true`；零值保留未知。已核实的工作分支在差异未知时仍提供 Review，且仓库匹配、PR 状态提示为无开放 PR 时提供 Regular／Draft PR；执行 agent 按现有 prompt 再核实实际 diff、基线、认证和重复 PR。
- 默认分支、非 Git、冲突、目录不匹配、Git 读取失败及已有 PR 的限制继续生效；未推送标记独立判断，零行数不会自动启用 Push。协议字段及后端 API 不变，新增 JavaScript 投影、Swift 菜单／执行前重查及 fixture UI 回归。
- 协议参考：Lody `apps/cli/src/lib/git/git-diff-stats.ts` 的 `parseGitNumstat`／`sumLineChange` 与 `getGitDiffStats`，二进制 numstat 的 `-` 会被汇总为零行数。
- 本轮 frozen lockfile 安装、340 项 JavaScript 测试、bundle 重建及 `git diff --check` 通过。iPhone 17／iOS 27 Simulator 构建、17 项 QuickAction／ProjectGit Swift 测试与 2 项 fixture UI 回归通过，覆盖零行数保留 Review／两种 PR、执行前重查后创建命名任务 tab、已有 PR 隐藏及 Git 读取失败重试。本次未在真实账号执行 Review、Push 或创建 PR；真机、iOS 26 和真实网络／metadata 更新延迟尚未验证。

## Quick Actions 发布状态识别与刷新修复（2026-10-06）

- Lody 的本地分支列表通常直接返回普通分支名，仅在引用需要消歧时返回 `lody:branch:local:` selector。旧投影只接受后一种格式，普通工作分支的未推送、相对基线统计和 PR 提示全部被丢弃，干净工作树因此一直显示 Publishing status unavailable。投影现在兼容两种格式；普通名称中的百分号保持原样，仅解码带前缀的 selector，仍检查项目、仓库和分支匹配。
- 每次读取 Git 状态先用独立副本同步最新 workspace metadata 和机器项目目录，再释放 metadata 锁并读取机器实时状态。Refresh Actions、进入详情、前台恢复及执行前重新检查都能读到更新后的发布提示，不再沿用会话列表的旧缓存；同步失败保持可重试，取消不启动后续机器请求、不影响共享会话订阅。
- 协议参考：Lody `packages/shared/src/node/local-project.cjs` 的 `listLocalProjectBranchesAtRootPath`，以及现有 `LocalProjectGitStateSchema` 和目录所有者 metadata。未增加后端 API，Swift／JavaScript 消息字段不变；未推送、基线和 PR 提示仍取决于机器发布的 metadata。
- 本轮 frozen lockfile 安装、339 项 JavaScript 测试和 bundle 重建通过，新增普通／编码分支、百分号保留、最新发布提示、同步失败重试和 metadata 取消回归；测试用例收尾后 72 项 bridge 测试复验通过。iPhone 17／iOS 27 Simulator 编译、16 项 QuickAction／ProjectGit Swift 测试、1 项原生桥接取消测试的 9 个操作参数（含 project-git），以及 1 项已有 PR／Git 读取失败重试 fixture UI 回归通过。只读核对本机真实分支返回普通名称，并用现有目录所有者 metadata 重放客户端投影，确认发布提示不再因格式被丢弃。`git diff --check` 通过，专属验证模拟器已关闭并删除。真机新版本安装后的云端刷新与实际 Push／PR 尚未验证。

## Quick Actions 按 Git 状态精简（2026-10-06）

- 快捷菜单根据实际工作树和当前／默认分支展示下一步，主要动作最多三项。默认分支干净时显示 Create Branch，有改动时显示 Review Changes 与 Create Branch & Commit；工作分支有改动时显示 Review Changes 与 Commit…，子菜单选择 Commit only／Commit & Push。干净工作分支按状态显示 Review、Push 和 Create PR…；Regular PR／Draft PR 收入同一子菜单，已有开放或草稿 PR 时隐藏创建入口。工作分支的单独 Create Branch 与 Refresh Actions 放入 More Actions。
- 增加 Push／Commit & Push 的独立命名任务 tab，沿用原有首轮派发及按机器保存的执行配置。推送只授权当前动作，要求执行 agent 核实远端、认证和非默认分支；禁止 force push、自动 pull／rebase／merge 或以后每轮自动推送。普通 Commit 保持仅本地提交。
- 项目运行／新建未确认时只展示按需原因入口；非 Git、目录无法核实、冲突、读取失败及无下一步分别显示状态，读取失败可重试。进入详情、恢复前台、项目活动变化及手动刷新重新读取；提交任务前再读取和检查，仓库状态变化不会通过旧菜单创建不适用的任务。
- 扩展现有 `local-project/git-state` 的客户端投影，保留工作树、默认分支和 GitHub 仓库。未推送标记与相对基线统计读取目录所有者的 `workspaceUnpushed`／`diffStats.allChange`，开放 PR 来自同机器、同项目、同分支的根会话 `pullRequests`；项目、分支或仓库不匹配时不借用这些提示。只有实时工作树干净时才用统计提示已提交的分支变更。RPC 读取的是注册项目目录，因此 worktree 会话不展示可能作用于另一目录的动作。没有增加后端 API 或 GitHub 查询；同步 metadata 缺失／落后时可能暂不展示 Push／PR，agent 执行时仍核实真实状态和重复 PR。远端领先、分叉、认证及未记录的 PR 由 agent 在执行前检查。
- 协议参考：Lody `packages/shared/src/message-schemas.ts` 的 `LocalProjectGitStateSchema`、`schema.ts` 的 Git／PR metadata，CLI `turn-post-processing-service.ts` 的目录所有者分支与未推送更新，以及 `components/src/lib/session-github-state.ts` 的基线统计与未推送标记分离。
- 本轮 frozen lockfile 安装、336 项 JavaScript 测试及 bundle 重建通过；Simulator 编译、29 项 QuickAction／ProjectGit／SessionTabs Swift 测试通过，含八种动作的独立 task、同 ID 重试、状态筛选、旧选项重新检查，以及读取期间后台／取消／账号／工作区／项目变化不创建任务。另通过 1 项原生桥接取消测试的 9 个操作参数（包含 project-git）。浅色 5 项 QuickActionsFlowTests 与 1 项普通新 tab 首条消息／后续草稿隔离回归通过；scope／状态提示／alert 收尾后，最终源码在系统深色 accessibility-medium 下的 Commit／More Actions、Review／Push／PR 和运行项目状态共 3 项 UI 定向回归也通过。截图与 AX 层级确认两个子菜单、长名称、原因提示、任务切换、草稿与配置保留正常；两台专属模拟器已关闭并删除，`git diff --check` 通过。本次没有在真实账号执行 Git、push 或创建 PR；同步 metadata 的真实更新延迟、认证、远端领先／分叉、弱网／后台恢复、worktree、iOS 26、iPad、真机、最大辅助字号和 VoiceOver 实际操作尚未验证。

## 新建 tab 首次实时订阅竞态（2026-10-06）

- Quick Action 与手动新建 tab 共用写入和实时订阅协议。新会话由独立短生命周期副本写入后，共享阅读副本的 workspace metadata 可能尚未出现它；旧 observer 会把缺失的 tab 当作已移除的旧 tab，发布空正文并释放订阅，原生端继续停在首条本地指令，直到重新进入页面。
- observer 在首次读不到会话 metadata 时先执行可取消的云端 metadata 同步，再判断是否确实不可用并加入实时房间。同步失败保留现有重连路径；已确认被移除、归档或关闭的 tab 仍按原规则处理。原生消息合约与新建配置不变。
- 新增 3 项 JavaScript 回归覆盖阅读副本落后时不重开页面也能接收同一回答的连续增长、metadata 同步失败保持可重试，以及取消同步后不发布旧快照或加入房间。本轮 frozen lockfile 安装、332 项 JavaScript 测试、bundle 重建、iPhone 17／iOS 27 Simulator 构建及 4 项 fixture UI 回归通过；截图与 AX 层级确认命名任务 tab 自动选中、首条指令、无键盘阅读、Main 草稿与独立配置重启保留，普通新 tab 首条消息／下一草稿同步正常。专属模拟器已关闭并删除，`git diff --check` 通过。本次 fixture UI 未验证 live metadata 竞态；真实账号的持续输出、弱网和后台恢复尚未复验。

## Quick Actions 按钮菜单与 Review／PR（2026-10-06）

- 闪电按钮改为原生 Menu，移除 Quick Actions sheet。菜单提供 Review Changes、Create Branch、Commit、Create Branch & Commit、Create PR 和 Create Draft PR；只有名称与图标，没有目录、执行选择或逐项注释。选择后才加载 Settings 中按账号／工作区／机器保存的配置，按钮显示加载状态并禁用重复触发；选择任务时收起键盘，创建后切换到命名子 tab，保留主会话草稿和原配置。
- 同项目运行／未确认新建时禁用动作，菜单内按需打开原因提示。加载或创建失败以 alert 提供 Retry；保存的设置失效时也可恢复会话默认值。后台、工作区变化或离开详情取消准备中的请求，旧请求不能创建任务或覆盖新范围的状态；提交后的传输继续由 model outbox 持有。
- Review Changes 是只读 agent 任务，优先检查暂存、未暂存和相关未跟踪源码；工作树无改动时检查当前分支相对已核实基线的变更，返回具体发现，不自动修改或发布评论。Create PR／Create Draft PR 也是 agent 任务，只发布当前已提交分支，保留未提交改动，不隐式提交、切分支、force push、合并或添加以后每轮自动提交推送的规则；查询已有 PR 避免重复，并核对 PR head。GitHub 工具、认证、目标或分支不满足条件时由任务说明原因。
- 沿用现有子 tab／首轮 `inputConfig` 协议，没有新增 GitHub RPC、自动 review 引擎或后台服务能力。参考本机 Lody `packages/components/src/components/sessions/session-chat-interface.tsx` 的 `handleCreatePr`／`handleCreateDraftPr` 和 `packages/shared/src/review-prompts.ts`，仅核对 agent prompt 派发方式；Kurage 使用当前共享目录和单次动作范围，不继承 Lody 的持续 PR upkeep 指令。普通工具权限响应仍未接入 live。
- 本次最终 Simulator 构建、6 项 QuickActionTests（其中命名／首轮配置用例参数化覆盖六种动作）和浅色 3 项 QuickActionsFlowTests 通过；系统深色 accessibility-medium 的禁用菜单／原因提示回归另通过 1 项。截图与 AX 层级确认按钮直接展开菜单、六种动作与长名称完整显示、键盘状态及主草稿保留、Settings 配置重启恢复、新增 Review／PR 的任务创建和切换、禁用状态与按需原因提示。首轮 UI 查询沿用 sheet 行标识失败；原生 Menu 不传递 ForEach 行标识，改为在菜单容器内按动作名称定位后全部复测通过，行为断言保持。首轮 Xcode 卡在失败日志收集，已终止该测试进程；最终成功结果 bundle 和截图正常导出。专属模拟器已关闭并删除，`git diff --check` 通过。本次没有在真实仓库执行 review、push 或创建 PR；机器 GitHub 工具／认证、真实账号、弱网／后台恢复、iOS 26、iPad、真机、最大辅助字号和 VoiceOver 实际操作未验证。未改 JavaScript bridge，未运行 JavaScript 测试。

## Quick Actions 任务 tab（2026-10-05）

- 本地项目的会话详情右上角新增 Quick Actions（闪电）入口，提供 Create Branch、Commit 和 Create Branch & Commit。每次动作在根会话下创建命名子 tab，提交独立首轮指令并切换过去；继承根会话的工作目录与当前分支，保留主会话的历史、草稿和原模型配置。打开面板收起编辑焦点，快捷任务不自动弹出键盘。
- 辅助字号下 tab 标题允许最多三行、扩大文字宽度并增加竖向留白，避免 Create Branch & Commit 被截成 Create Branch…，与单独创建分支的任务混淆；普通字号保持原单行尺寸。
- Settings → Quick Actions 可按机器设置 Agent、Model 和 Reasoning。动作面板仅展示三个动作的图标与名称，移除目录信息、执行选择、逐项说明和底部注释；普通字号默认半屏并可上拉展开，辅助字号默认全屏。执行时自动加载 Settings 保存的配置，设置保存在本机，按账号／工作区／机器隔离，重启后恢复；Use Session Defaults 清除该组设置。通过现有新会话能力投影加载选项，保存的模型或推理档位失效时阻止执行，并可在面板恢复会话默认值；没有模型能力的 agent 继承只读配置。后台取消加载，工作区变化关闭面板，旧请求不能写回新工作区。
- 本次面板精简验证：iPhone 17／iOS 27 Simulator 构建、6 项 QuickActionTests 和浅色的 2 项 QuickActionsFlowTests 通过；系统深色 accessibility-medium 的运行项目禁用回归另通过 1 项。截图与 AX 层级确认普通字号半屏展示完整的三个动作，辅助字号展开后长名称完整换行、禁用原因可见；Settings 配置、重启恢复、任务创建与主草稿保留通过。未改协议或 JavaScript bridge，未运行 JavaScript 测试；未在真实账号或项目中执行 Git 动作，iOS 26、iPad、真机、最大辅助字号与 VoiceOver 实际操作本次未验证。专属测试模拟器已删除。
- 使用现有 `parentSessionId` 子 tab、共享目录及新 turn `inputConfig` 协议，无新增后端。`SessionTabStart` 将可选标题传给原生 bridge，首轮发布 metadata 时同时写 `title`／`titleSource: user`，避免自动标题覆盖任务名；普通新建仍从 prompt 生成 draft 标题。outbox 保留 session ID、turn ID、标题和首轮配置，未确认的重试不重复创建，用户随后重命名也不被重试覆盖。协议参考沿用 Lody `use-session-actions.ts`、`schema.ts` 与 CLI `session-manager.ts`。
- 同一项目已知有运行中的根／子会话或未确认的新建时禁用动作，并在按钮前解释原因；这是客户端已观察状态的检查，不是机器侧 Git 锁。指令要求先检查 diff，优先只提交已暂存文件，排除 secrets／构建产物／无关文件，保留工作内容，禁止 push／PR／amend／reset／丢弃更改，并遵循 agent 现有权限配置。实际执行结果显示在任务 tab 中；普通工具权限审批仍未接入 live。
- 本轮 frozen lockfile 安装、329 项 JavaScript 测试及 bundle 重建通过，XcodeGen 已重新生成工程；Simulator 构建和 42 项 Swift 定向测试通过，覆盖首轮独立模型、命名、原历史保留、同 ID 重试、工作区隔离、设置持久化／能力失效校验和原生 bridge 的标题／配置请求编码。Swift 测试在 tab 大字换行调整后再次通过；最后只调整 SwiftUI 多行标签的尺寸测量，未修改模型或 bridge。
- iPhone 17／iOS 27 的浅色主流程、运行项目禁用与普通新 tab 首轮／下一草稿同步回归通过；系统深色 accessibility-medium 的两项 Quick Actions 回归也通过。截图与 AX 层级确认独立模型及重启设置、主草稿、无键盘任务阅读与禁用原因。大字截图发现标题截断后调整 tab 换行；初次换行后胶囊仍按单行高度测量，最终给横向滚动中的多行标签明确宽度并复验主流程通过，任务胶囊增至 77pt、完整包住两行标题和留白，Main 仍为 46pt 并垂直居中。普通字号在换行调整后已复测，保持单行外观。测试初轮修正了缺少目标工作区的 fixture、Picker 的 AX label 断言和按需滚动显露元素，没有放宽行为断言。
- 两台本轮专属模拟器已恢复浅色／默认字号后关闭并删除，`git diff --check` 通过。本轮仅用 fixture 验证客户端流程，没有在真实项目执行 Git 动作。真实账号下的创建／执行、普通工具权限交互、弱网和后台恢复，以及 iOS 26、iPad、最大辅助字号与 VoiceOver 实际操作仍未验证。

## Markdown 超链接标记（2026-10-05）

- 回复中的文字链接保留语义正文色，以次要文字色的圆点下划线与末尾小号单色 `↗︎` 标记区分；不随 Blue／Black 强调色变化。标记和链接共用目标，以不换行空格贴住末词，正文、列表、表格与子任务复用相同渲染入口。
- MarkdownView fork 增加可配置下划线模式与行内 attributed suffix。保留链接在原有 AttributedString 中，以支持自然换行、粗体／行内代码、点击和文字选择；iOS 18+ 的 MarkdownView 文字路径用 TextRenderer 按每行实际布局绘制圆点，避免系统 `.dot` 显示成短矩形划线。普通无链接段落直接保留原 Text，未改自定义 URL renderer、图片链接或复制整条消息的原文。
- 依赖固定到 `7d7127ec6f516c41ca7b6101fd97139d1e4591a3`，工程已用 XcodeGen 重新生成；其它依赖不变。新增的库回归覆盖链接仍处于同一段落、目的地址／标记和内联样式保留、普通文本与代码不被装饰。
- 本轮库的 19 项定向测试通过，覆盖文本转换、链接装饰和 Markdown 异步缓存状态；原项目按远程固定版本完成 iOS Simulator 构建，`git diff --check` 通过。独立验证副本使用同一最终提交，在 iPhone 18 Pro／iOS 27 上完成 6 项 fixture UI 检查：浅色、真实系统深色、Accessibility XL、打开完整链接目标、原生文字选择和已有长会话最新位置／向上阅读回归均通过。已核对截图与 hierarchy，圆点随字号缩放、每行位置统一且不压到下伸字形，标记不下划线并贴住末词；连续正文、粗体／代码、列表与表格排版正常。临时模拟器已关闭并删除。
- 首轮系统 `.dot` 视觉呈短矩形划线，随后改为圆点绘制并重新构建、复验；最初深色启动参数未真正改变系统外观，最终通过切换模拟器系统外观并检查黑底白字截图验证。未新增客户端测试或修改同步协议，未运行模型／JavaScript 测试；iOS 26、iPad、真机、VoiceOver 实际操作与真实账号本轮尚未验证。

## Settings 固定高度与实心 Blue 气泡（2026-10-05）

- Settings 按新参考图固定在实际屏幕约 85% 高度，使用单一 `.fraction(0.95)` 系统可用区域高度，隐藏拖动指示器，取消 medium／large 切换；普通与辅助字号都在同一高度内滚动，二级页面沿用同一个 sheet 与导航栈。此项取代上一轮默认半屏、上拉展开的方案。
- Blue 用户文本气泡改为不透明蓝底与白色正文，参考图 Display P3 转为 sRGB 后使用 #006CEB；会话／skill 提及的标签与图标同步使用白色。Black 继续使用中性背景与语义文字色。更新消息渲染时比较强调色，切换 Blue／Black 会重绘已有正文和提及图标；显示标签与复制原始引用的规则沿用现有实现。
- 调整既有 UI 回归以检查固定高度、无拖动条、上滑与重开同高，并提高 Blue 气泡实心填充的像素门槛；保留已有缓存刷新、浅／深色强调色范围和发送前后尺寸／去重检查。
- 本轮 iPhone 17／iOS 27 Simulator 最终测试构建通过，20 项 ComposerMentions 测试通过；浅／深色 × Blue／Black 四组合气泡、发送尺寸／去重、最终固定高度、深色 accessibility-medium 固定高度共 4 次定向 UI 执行通过，另有 1 项仓库外白色提及／Settings 手势检查通过。Settings 与 Workspace 实测为 84.92% 全屏高度，无拖动条，上滑、返回与重开同高；已复核全屏截图与辅助功能树，蓝底正文及两类提及图标／标签为白色，三行辅助字号气泡完整，Black 保持中性，设置项可触达。
- 初轮 `.fraction(0.85)` 实际仅占 76% 全屏，几何回归失败后校正系统可用区域比例并重新构建、通过定向高度回归；没有放宽断言。发送首轮 runner 初始化失败，外部 harness 首轮元素查询错误，分别修正验证环境／脚本后单项复验通过。气泡源码在高度校准后未改动，四组合与发送不重复执行。临时模拟器已关闭并删除，`git diff --check` 通过；iOS 26、iPad、真机与 VoiceOver 实际操作本轮未验证。未改模型或同步协议，未运行 JavaScript 测试。

## Settings 打开高度与 Workspace 刷新（2026-10-05）

- Settings 支持原生 medium／large 两个高度，普通字号每次打开默认 medium，辅助字号使用 large；显示拖动指示器，内容优先滚动，保留上拉展开和同一个二级导航栈。半屏内容仍可滚动访问 About／Sign out 等条目。
- Workspace 使用原生 plain List 与 `refreshable`：进入页面立即展示已有行并后台刷新，不再在列表下插入 “Refreshing workspaces…” 和转圈；手动下拉使用系统顶部刷新指示器，只有无数据初次加载显示居中转圈。刷新失败继续保留原行与 Retry，空列表提供 Refresh，切换与取消仍复用 `AppModel`。
- 更新 UI 用例的 Workspace 容器查询并适配半屏 Settings 滚动；增加打开／重开高度、缓存刷新无页脚、下拉后保留行和选中项的回归。独立慢刷新 fixture 仅延迟后续工作区请求，不延迟首次账号工作区加载。
- 本轮 iOS 27 Simulator 测试构建、9 项 WorkspaceSelection 测试、6 项 Settings／Workspace fixture UI 回归通过，覆盖默认与重开高度、下拉刷新、切换隔离、失败重试、空列表、长列表与退出确认；深色 accessibility-medium 下的工作区切换回归另通过 1 项。独立手势检查确认拖动指示器可展开，关闭再打开回到 medium；首轮外部 harness 使用错误的系统辅助功能值，改为实际的 “Expanded” 后复验通过，应用代码不变。已复核浅／深色全屏截图与辅助功能树：缓存刷新没有页脚或加载遮挡，手动下拉显示系统顶部指示器且保留行，半屏可滚动访问 About／Sign out，辅助字号默认展开且文字无新增裁切。真实账号网络刷新、iOS 26、iPad、真机与 VoiceOver 实际操作本轮未验证；未改模型或同步协议，未运行 JavaScript 测试。
- 本轮临时模拟器已关闭并删除，`git diff --check` 通过。

## 推理设置浮层细节（2026-10-05）

- 对照参考截图减轻推理浮层的视觉重量：轨道由 56pt 改为 48pt，保留 40pt 滑块与 48pt 操作区域；取消独立灰色底轨，使用单层 regular material 和 0.5pt 细边框，标题与滑条间距由 22pt 改为 14pt。独立窗口继续使用可见的 material 背景，避免已有玻璃渲染问题；截图检查后保留 regular material，减弱底层发送按钮的颜色透入。
- 刻度由 7pt 改为 12pt，中心与滑块及拖动选档位置一致；已选刻度使用强调色的前景色，未选刻度使用语义浅灰。Blue 滑条的大面积填充使用柔和靛蓝，深色 Blue 保留白色滑块，Black 随系统语义颜色适配；继续沿用强调色偏好、触觉开关、离散选档和辅助功能调整动作。
- 新会话与既有会话的配置摘要、Advanced 选项及辅助功能说明将熟悉的 `XHigh` / `ExtraHigh` 显示别名统一为 `Extra High`，保留原 provider 选项值与未知标签，不改变发送协议。
- 本轮构建通过；4 项既有推理展示规则测试和配置编辑／新会话创建 2 项 fixture UI 回归通过。截图发现 Spacer 布局使首尾刻度偏离滑块，随后改为使用同一套几何中心定位并重新构建；最终版在独立 iPhone 17／iOS 27 Simulator 的 Light Blue、Dark Blue、Dark Black + accessibility-medium 三种场景各通过 1 项外部 XCTest 检查，覆盖 Low／Medium 点击、拖动 High、浮层关闭、Advanced 与键盘／草稿保留，已复核全屏截图和辅助功能树。浅／深色刻度与滑块清楚，辅助字号无新增裁切、重叠或越过键盘；专用模拟器已关闭并删除，`git diff --check` 通过。fixture 仅提供三个 effort，未截图复核真实账号的六档 `Extra High` 状态；iOS 26、iPad、真机触觉与 VoiceOver 实际操作尚未验证。本次未改桥接或发送协议，未运行 JavaScript 测试。

## Settings 二级交互与 Appearance / Haptics（2026-10-05）

- Workspace 与 Appearance 统一在 Settings 的原生导航栈内进入二级页面；Workspace 不再新开短 sheet，选择后返回 Settings，切换与刷新仍复用 `AppModel`。设置行移除前置装饰图标，保留标题、当前值和导航箭头。
- Appearance 按参考图提供 System / Day / Night 三列外观卡片及 Black / Blue 两列强调色卡片，选中用灰色实心背景、未选用细边框。保留原 `appTheme` 存储值，强调色以 `appAccent` 保存；默认 System / Black，Black 的单色控件在深色下使用语义浅色。辅助字号改为纵向排列，所有选项可以滚动访问。
- 强调色范围修正：根视图保持系统语义单色 tint，导航、工具栏、附件菜单和停止按钮不随 Blue 变色；发送按钮底色、Haptics／Notifications 开关、附件数量徽标和问题选中标记单独读取强调色。用户消息气泡在 Blue 下使用淡蓝底，Black 保留原中性灰底；正文保持语义文字色，实心按钮／徽标使用对应的对比文字色，适配 Day 与 Night。
- Reasoning 细节跟随强调色：输入区小 dial 的指针与中心圆点、reasoning 选择条的已选填充使用 Blue／Black；刻度与未选轨道沿用中性色，保持原有档位、拖动与指针动画。
- Reasoning 配色增量测试构建通过；iPhone 17 / iOS 27 的既有 reasoning 交互 UI 用例在 Day／Blue、Night／Blue、Night／Black 三种场景最终均通过，已复核指针及 Low／High 已选条截图，颜色清楚、无新增布局问题。Night／Black 首次最后的发送断言失败：自动化触点使用键盘展开前的旧位置，草稿保留；源码和用例不变的单次重跑通过，初次失败截图、自动 hierarchy 与重跑结果均保留。成功运行未导出完整 hierarchy，保留截图与元素查询记录；本次未新增测试，未验证真机或 iOS 26。
- 强调色范围修正后的 generic iOS Simulator 测试构建通过；iPhone 17 / iOS 27 的三项 fixture UI 回归全部通过，覆盖强调色／触觉重启恢复、Day／Night × Blue／Black 的发送按钮、用户气泡及导航／工具栏像素检查，以及发送前后气泡尺寸和去重；Stop 的像素检查仅执行 Day／Blue 场景，其余组合已有草稿而显示发送按钮。已复核四张聊天配色截图、Blue Haptics 截图及辅助功能树，发送箭头和气泡文字清晰，导航／工具栏保持单色，无新增重叠或裁切。专用模拟器已关闭并删除，`git diff --check` 通过。本次未验证真机、iOS 26 或 iPad。
- Appearance 与 Haptics 合并为同一个圆角偏好分组，中间以分隔线区分两行。Appearance 下方加入 Haptics 二级页面，以 Haptics Feedback 开关控制现有 reasoning 拨盘与 Advanced 配置选择的触觉；默认开启，`hapticsEnabled` 保存本机偏好。外观与触觉偏好按安装保留，不参与远程同步。
- 同组布局修正后的增量测试构建、iPhone / iOS 27 的一项工作区切换 fixture UI 回归通过；本次截图确认两行共用一个背景、分隔线清楚，辅助功能树保留两个独立导航按钮，无重叠或裁切。专用模拟器已关闭并删除，`git diff --check` 通过。
- UI 回归更新为原生二级页面返回与卡片选择，新增强调色／触觉重启恢复检查，并保存截图与 UI hierarchy；新增文件已用 XcodeGen 纳入工程。首轮发现额外辅助功能分组将卡片的 identifier 与 Selected 状态放到 Other 包装层，原生 Button 没有对应标识；已去掉包装，装饰符号单独隐藏，按钮直接提供名称、选中状态和标识。
- 本轮 generic iOS Simulator 测试构建通过；iPhone / iOS 27 的外观切换与恢复、强调色／触觉恢复、工作区切换／刷新重试／空列表／长列表、退出确认和通知开关验证通过。深色最大辅助字号下的外观与强调色／触觉两项回归，以及 iPad / iOS 27 的已读基线／草稿与外观切换后草稿两项回归均通过；已检查 iPhone 的 Settings、Workspace、Appearance 浅／深色截图和辅助功能树，Haptics On 截图确认 Blue 与 Black 实际应用到原生开关。iPad 横屏 XCTest 截图有采集黑边／裁切，仅确认功能与辅助功能树，完整横屏视觉未复核。真机触觉手感、VoiceOver 实际操作、iOS 26 与真实账号多工作区尚未验证。本轮未修改模型、协议或桥接，未运行模型或 JavaScript 测试。

## 分支审查修复（2026-10-05）

- 子代理正文补丁改为稳定 ID 的 `subtaskOrder` / `changedSubtasks`：初次订阅仍发送完整快照，后续仅传发生变化的 run；Swift 按每个补丁的顺序重建完整列表并移除已删除任务，校验重复／缺失 ID，兼容已有完整替换字段。一个 run 增长不再重传其它已完成任务的正文；thought 与原始工具输出的过滤规则沿用既有投影。
- 通知路由自身提交工作区选择与用户手动切换分开；手动切换立即撤销待处理点击，阻止工作区发现阶段的旧请求切回。工作区与会话刷新明确返回是否成功提交，瞬时失败或工作区请求被后续刷新取代时保留点击和 Retry，不再根据空缓存误报永久不可用。Retry 通过同一个 SwiftUI `.task(id:)` 重启，随后台、账号或新点击变化取消；路由自己拥有的会话刷新也传递取消，仍不取消其他调用者拥有的共享请求。
- 会话宿主持有输入区的 `ComposerPresentation`，统一配置浮层、Advanced sheet、附件预览与 Photos／Files／Camera 呈现状态；覆盖正文时暂停通知可见性和已读判定，同一会话通知打开后清理这些弹层而保留草稿。相机授权完成时检查关闭代次，避免已被通知关闭的流程重新呈现。新会话仍使用输入区自己的局部状态。
- 移除 iPad UI 用例对固定 3 秒加载延迟的依赖，UI 保留已读基线／草稿与 workspace picker 的交互检查；新增受控原生视图回归，在覆盖 Settings 已实际呈现后才释放正文，检查关闭后恢复已读与可见性，并检查输入区覆盖页面上的同会话通知关闭及草稿保留。增加通知早期工作区切换、会话刷新失败重试、路由取消以及子代理增量排序／增长／删除回归。
- 本轮 frozen-lockfile 安装、328 项 JavaScript 测试与 bundle 重建通过；iOS 27 Simulator 构建、93 项原生定向测试、10 项会话刷新测试通过，最终共享弹层版本的 Advanced／附件预览／Photos／Files 四种受控视图回归也通过。iPhone 的冷通知、子 tab、通知开关、配置编辑和子代理详情 5 项 UI 用例通过，iPad 的 Settings 已读基线／草稿与主题切换 2 项通过，最终附件选择与配置编辑复测 2 项通过，共 9 次 UI 执行、0 失败。截图检查确认输入区、子代理正文及 Settings 显示正常；iPad 横屏 XCTest attachment 有黑区和裁切，同轮 simctl 画面完整。专用模拟器已恢复原显示配置并关闭。通知 Cloud 开关仍关闭，未进行真实账号、APNs、iOS 26、真机相机授权或其他真机验证。

## 子代理列表状态与配色（2026-10-04）

- agents 浮层每行副标题始终显示任务状态：完成为 Done，其余为 Running、Pending、Failed、Cancelled 或 Status unknown；Running 保留已提供的进展或最新工具，辅助字号下将进展放到下一行，结束后不再用旧工具名／执行者替代状态。辅助功能值同步使用行状态，失败文字为红色。
- 圆点标识子代理，按稳定任务 ID 在当前会话视图内一次分配蓝、绿、橙、紫等八色；状态分组变化、正文增长、任务移除和浮层关闭重开不改变其他子代理的已有颜色。状态含义由文字表达，详情中的状态颜色仍独立保留。
- 新增专用四任务 fixture 与列表 UI 回归，覆盖两个 Done、Running 的进展、Failed、打开正确详情及重开列表；原来的两任务 fixture 保持原数据。此项只涉及列表 UI、fixtures 和 UI 测试，未改同步投影或协议。
- 本轮 iPhone 17／iOS 27 Simulator 构建及三个浅色定向 UI 用例通过，覆盖列表状态、完整正文展开、旧摘要详情和返回父草稿。浅色初次／重开截图确认 running 的橙色、failed 的紫色、两个 completed 的蓝／绿色保持一致，Done／Running／Failed 清楚可见；深色 accessibility-medium 的列表用例也通过，但截图发现进展截断、底部 quality 行需滚动后才能看到，随后改为辅助字号上下排列，并加强截图滚动到最后一行的断言。
- 最后换行修正后的浅／深色 UI 复测未执行：共享工程新增的 OneSignal 依赖拉取遇到 early EOF，后续解析在等待 GUI Xcode 持有的 SwiftPM 缓存锁；只结束本轮专属测试进程，未动 GUI Xcode 或共享锁。当前 `ConversationSubtasksView.swift` 以之前成功构建的 Kurage 模块完成独立 Swift 6 类型检查，这不是最终完整工程构建或截图验证。专属模拟器已恢复浅色与默认 large 字号并关闭，`git diff --check` 通过。此项没有运行 JavaScript 或模型测试；iOS 26、iPad、真机与真实账号状态流转尚未复测。

## 子代理完整正文（2026-10-04）

- 对齐 Lody 官方 main `3963a1d4` 的 `shared/src/ai.ts`、`acp/history-apply.ts` 与 `components/src/components/ai-gui/subagent-task-panel.tsx`／`view.tsx`：从父会话 history 中的 `subagent_task.run.items` 读取规范化运行正文，不把 ACP root／run ID 当作可单独打开的 Lody Session。
- 新版 run 以 ACP root ID 与 task ID 作为身份，名称相同的不同 run 不再合并；状态以 snapshot 为准，明确区分 pending、running、completed、failed、cancelled 与 unknown，不用父 turn 结束推断新版 run 已完成。旧版 Codex 活动仍沿用按 actor 归并的兼容路径。
- 子代理详情默认打开半屏只读面板，可拖到大尺寸；关闭按钮旁左对齐真实任务名及父会话的项目／机器信息，状态与 model／token／工具次数收到信息浮层。复用主对话的 Markdown、工具活动标题与 “Worked for …” 折叠组件，但从正文开头打开，短内容紧贴标题栏；已在底部时跟随增长，上滑阅读后保留位置。过滤与 run 名称完全匹配的 “Delegated task for …” 自动占位说明，保留实际任务提示；缺少 snapshot 时间时使用任务记录时间或 progress.durationMs 显示已记录的用时，不编造时长。展示结果、最新进展和明确类型的当前计划，保持 thought 与工具原始 input／output 不投影。关闭后保留父会话草稿，打开时收起父输入键盘，面板内没有发送或停止父会话的操作。
- 新版正文增长、删除和结束状态继续经现有父会话 snapshot／patch 推送到已打开面板，复用原有工作区、账号和后台取消作用域；下拉刷新使用父会话刷新入口。无正文、provider 不提供可展示步骤、输出不完整和状态未知分别提示；缺少 run 的历史记录保留原摘要／步骤，不能补回服务端未保存的正文。
- 首次实现的 frozen lockfile 安装、320 项 JavaScript 测试与 bundle 重建、28 项原生定向测试通过。共享工作区 UI 重建曾被并行 Settings 修改中未收录的 `AccountAvatar.swift` 阻断，随后用隔离副本完成浅色默认字号两项 subtask UI 与深色 accessibility-medium 一项验证；这些结果未覆盖后续截图反馈中的标题与顶部留白问题。
- 截图反馈后的修正：本轮 frozen lockfile 安装、322 项 JavaScript 测试及 bundle 重建通过；共享工作区构建与 31 项原生定向测试通过，新增短 run 顶部对齐及增长跟随、多行 run 保持开头、单条长回答不被估算高度拉到底部的回归。UI 实测发现标题容器覆盖子元素的辅助功能标识，已改为独立包含子元素；原生 Menu 将只读信息显示为低对比的禁用文字，已换为原生 popover。最终浮层版本的浅色默认字号与深色 accessibility-medium 各一项新版正文 UI 用例通过，8 张截图确认半屏、标题／副标题、顶部内容位置、绿色状态和用量可读、工作／工具展开及关闭保留父草稿正常；旧摘要路径的关闭回归也已在本轮修正标题容器后通过。模拟器已恢复浅色与默认 large 字号并关闭，`git diff --check` 通过。iOS 26、iPad、真机以及真实账号的新版机器输出、跨端持续更新、断网与后台恢复尚未实测。

## iPad 侧栏图标替换（2026-10-04）

- iPad 侧栏开关的 `sidebar` 模板资源改为提供的 `list.svg` 三横线图标；保留矢量表示、24×24 pt 显示尺寸与原有辅助功能标识。
- 本轮 generic iOS Simulator 构建与 `git diff --check` 通过。侧栏 fixture UI 回归在重新编译时被工作区的 `SessionListView.swift` 中 `AccountAvatar` 缺失阻止，测试未执行；已构建应用在独立 iPad 模拟器启动到欢迎页，尚未验证侧栏图标的实际显示与开关交互。真机与 iOS 26 本轮未验证。

## Settings Theme 与图标（2026-10-04）

- Settings 新增 Theme 卡片与原生选择菜单，提供 System、Light、Dark，默认 System。`AppTheme` 定义三个持久化值，`@AppStorage("appTheme")` 保存本机选择；稳定根视图中的小型 UIKit 视图仅为它所在的窗口设置 `overrideUserInterfaceStyle`，System 明确恢复 `.unspecified`，Settings、Workspace picker 与 About 继承外观。切换直接更新颜色，不改变视图 ID，重新登录及重启保留偏好；Theme 行在大字号或空间不足时改为上下排列，避免选项名称拆字。
- Theme、About 与 Workspace 分别导入本机 MingCute Icon System Pro v1.50 / SVG / cute regular 的 `palette_cute_re.svg`、`information_cute_re.svg` 与 `briefcase_cute_re.svg`。资源保留矢量和 template 渲染，24 pt 起随字号缩放并限制最大尺寸，继承行前景色，装饰图标不参与辅助功能朗读。
- 新增主题选择／弹层／重启恢复 UI 回归，截图背景亮度断言覆盖显式浅／深色及恢复 System，另以独立 iPad 用例覆盖 Dark → Light → System 切换后草稿保留；工程已重新生成。首轮视觉检查发现 `preferredColorScheme(nil)` 在系统深色下从 Light 返回 System 后仍保留浅色，以及最大字号 Theme 行拆字；已改为上述窗口外观应用和自适应布局。
- 本轮主题版本的 iOS 27 Simulator 测试构建，以及独立 Swift 6 严格并发 UI 测试 bundle 构建通过。修复后 iPhone 17 普通字号主题回归 1 项、系统深色最大辅助字号主题回归 1 项、iPad Pro 13-inch (M5) 独立主题／草稿回归 1 项均通过。真实背景亮度断言验证显式浅／深色、重启后的 Light，以及恢复 System；截图核对 Settings、Workspace picker、About 和会话列表的外观及三个图标。
- 原 iPad 已读／草稿组合用例的两处已读时序断言未通过：自动化从会话点击到 Settings 打开耗时超过 fixture 的 3 秒加载延迟，检查前会话已被读到；其后的主题和草稿断言没有失败。保留原时序断言，独立主题／草稿用例复验通过。新模拟器首轮 runner 在加载辅助功能 bundle 时 stall 并退出，使用已初始化设备后恢复运行。
- 验证期间共享工作区并行加入通知依赖；剩余 UI 回归通过独立 `.xctestrun` 使用本轮已构建的主题版本与更新后的 UI 测试执行，跳过无关的包解析。并行通知改动后的完整工程、iOS 26、真机和 VoiceOver 实际操作未纳入本轮验证；未修改同步协议或运行桥接／模型测试。
- 已检查最大字号标题与选项完整显示、System 返回真实深色及 iPad 原生横屏画面；横屏无黑边或裁切，之前 XCTest attachment 的方向黑区属于采集画布问题。本轮创建的三台模拟器已关闭并删除，原有设备未修改；`git diff --check` 通过。

## Settings 中性色调整（2026-10-04）

- 根据参考截图调整浅色配色：页面 #FCFCFC、卡片 #F2F2F2、账号分隔线 #E0E0E0，消除系统灰在卡片上的蓝紫色偏并减淡分隔线。Settings、Workspace picker 与 About 共用页面／卡片颜色；深色仍按系统语义背景与分隔线解析，文字与原生控件颜色保持系统行为。
- 本轮 iOS 27 Simulator 测试构建通过；iPhone 17 两项浅色 Settings／Workspace／Retry／About 回归、一项深色工作区切换回归通过。浅色截图像素核对为背景 RGB(252,252,252)、卡片 RGB(242,242,242)、账号分隔线 RGB(224,224,224)，已去除原卡片 RGB(242,242,246) 的蓝紫色偏；深色截图仍是系统 elevated 背景与分组色。`git diff --check` 通过，专用模拟器已关闭并删除。此次为配色修改，未新增测试或运行模型／桥接测试；iPad、iOS 26 与真机配色本轮未验证。

## Settings 与 Workspace 页面（2026-10-04）

- 头像改为打开大尺寸原生 Settings sheet；圆角分组承接账号摘要、Workspace、About 与退出确认。Workspace 使用带首字母头像、名称、地址和选中勾号的短选择器，较多条目可以滚动与展开；单工作区也保留入口，无数据和刷新失败可重试。
- Settings 宿主位于 `workspaceGeneration` 的会话重建边界之外。切换先提交工作区，只关闭选择器，Settings 更新名称；新工作区的会话刷新继续由模型管理。选择当前项只关闭选择器，同工作区开关 Settings 保留草稿与导航；被遮挡会话暂停已读回执，继续沿用原有订阅与后台清理规则。
- 模型独立表达 workspace 加载／错误，以请求代际、认证代际和取消检查丢弃旧结果；刷新失败保留已有列表。Fixture 增加隔离的多工作区、空列表、长列表及一次刷新失败场景，其他工作区不会返回 Demo 会话。新增相关模型与 UI 回归，并更新原有退出用例；已重新生成 Xcode 工程。
- 本轮 iOS 27 Simulator 测试构建与 38 项 WorkspaceSelection／SignIn／FixtureLodyClient 模型测试通过。iPhone 17 浅色定向 UI 回归最终 7 项通过（iPad 专用用例按设计跳过），深色最大辅助字号的长列表与切换 2 项通过；iPad Pro 13-inch (M5) 常规 Settings 回归 6 项、深色最大辅助字号 2 项、横屏已读／草稿复核 1 项全部通过。
- 首轮退出与重试 UI 断言失败，原因是同名按钮匹配到了底层退出行、原生 popover 没有独立 Cancel 行，以及短暂加载状态被轮询错过；测试改为精确定位确认、适配点外取消和核对重试最终状态后，3 项复跑通过，应用业务逻辑未因此修改。已检查手机与 iPad 的 Settings、短选择器、长名称、错误和确认截图；XCTest 横屏 attachment 有黑区与裁切，原生 simctl 对照确认实际 Settings 视口完整。`git diff --check` 通过，本轮专用模拟器已关闭并删除。
- iOS 26、真机、真实账号多工作区、网络恢复、持续输出与后台返回、iPad 窄窗口和 VoiceOver 实际操作尚未验证；fixture 结果不替代真实服务验证。
- 详细方案见 [SETTINGS_PLAN.md](SETTINGS_PLAN.md)。本机 Theme 已加入，列表／触觉偏好与机器、Agent、MCP、Skills 仍按后续阶段推进；归档继续属于会话列表，运行配置继续属于会话输入。多账号、用量、更新、Auto-review、时区与通知需分别核实能力和语义。本轮没有修改同步协议。

## 提及浮层审查修复与 iPhone 方向（2026-10-04）

- iPhone 仅支持竖屏，iPad 保留四个方向；修改 `project.yml` 并重新生成 Xcode 工程。此项取代此前 iPhone 支持横屏的配置，窗口尺寸变化仍由现有自适应导航处理。
- @／$ 候选浮层按输入区上方到窗口安全区域顶边的可用空间限制高度；候选行保留原字号与高度，剩余项仍可滚动，加载和结果共用实际视口。没有可用空间时隐藏面板，继续跟踪布局以便空间恢复后显示。
- 输入或候选来源更新时生成一次候选内容；键盘避让、底部滚动和窗口变化的位置跟踪复用宿主已有内容，不再逐帧解析查询、筛选会话或匹配技能。
- 补充多行草稿下候选保持在屏幕内、滚动选择末项的 fixture UI 回归，并更新旋转草稿用例以断言 iPhone 保持竖屏。
- 本轮测试构建、XcodeGen 生成及 `git diff --check` 通过；构建产物确认 iPhone 仅竖屏、iPad 四方向。iPhone 17／iOS 27 的 6 项浅色默认字号 UI 回归，以及深色 XXXL 下的 1 项多行候选回归通过；iPad Pro 13-inch (M5)／iOS 27 的 2 项 UI 回归通过，覆盖横屏侧栏与键盘、双药丸位置及候选覆盖和选择。检查测试截图，确认多行大字号时视口收缩、候选仍可滚动选择；模拟器已恢复原浅色与字号，关闭本轮启动的设备。本轮未修改桥接或协议，未运行 JavaScript 或 Swift 模型测试。iOS 26、真实账号、真机、iPhone Duo 和自由窗口缩放尚未验证。

## @ 面板覆盖会话药丸（2026-10-04）

- 输入框的 @／$ 候选面板改为同一场景的非 key 浮窗，位于 diff 与 subagent 药丸上层；候选加载、过滤与显示不再增加底部布局高度或推动药丸、正文位置。
- 浮窗只接收面板区域内的触摸，保留输入框与键盘焦点，独立玻璃容器与背景遮挡下层文字。显示期间跟踪键盘避让与底部滚动造成的锚点移动，仅在位置变化时更新布局；在候选关闭、进入后台或输入框宿主移除时停止跟踪并清理。继续复用原有候选列表、滚动与大字号单行视口，新会话输入框也使用同一浮层。
- 新增 fixture UI 回归，检查两个药丸在面板前后的位置、面板覆盖范围、候选选择与关闭后的可点击性。本轮 iPhone 18 Pro／iOS 27 Simulator 构建通过，浅色普通字号 5 项相关用例与深色 accessibility-large 3 项用例均通过，覆盖加载、过滤、候选点击与滚动、双药丸位置和新会话。深色新会话首次因主机合盖休眠导致事件合成超时，重启专用模拟器后单独复跑通过。截图确认面板位于正文和药丸上层、药丸文字被遮挡，键盘正常；`git diff --check` 通过。iOS 26、iPad 与真机尚未验证。

## iPad 唤起键盘卡死修复（2026-10-04）

- 真机 iPad（外接键盘）0.4.2 (10) 与 0.3.2 (6) 的 watchdog 日志均卡在 `MentionEditor.updateUIView` 内同步调用 `becomeFirstResponder`：宿主视图在 SwiftUI 更新中途重读 responder 图，主线程持续占满 CPU 直至被系统终止。与侧栏键盘布局改动无关。
- 输入框的成为／放弃第一响应者改为在本次更新结束后的主线程任务中执行，执行前按最新的聚焦与可编辑状态重新判断，同一时刻只排队一次；文本、选区与提及处理不变。
- 本轮 iPad Pro 13-inch 模拟器 `AdaptiveLayoutFlowTests` 8 项执行、0 失败（1 项按设计跳过）；iPhone 17 上 ShellFlowTests 中与输入聚焦、发送、steer、提及相关的用例单独复跑通过。全量 ShellFlowTests 因主机负载过高出现大量超时，未能完整跑完；三项提及按钮用例仍断言 44pt（按钮已统一为 36pt），`testUnconfirmedBubbleSurvivesReopeningAndPreservesNewDraft` 在修改前的 HEAD 上同样失败，均与本修复无关。
- 模拟器无法复现外接键盘场景；修复需在真机 iPad 上确认。
## Session 列表项目新建图标缩小（2026-10-04）

- 项目标题右侧的新建 Session 图标由资源的原始 24 pt 改为独立的 20×20 pt 模板图像视图，与左侧文件夹图标同尺寸；继续使用 secondaryLabel 并在项目标题内居中。
- 原有 44 pt 宽、覆盖整行高度的点击范围、新建入口条件与辅助功能标识保持不变。
- 本轮 iOS 27 Simulator 构建通过；独立 iPad Pro 13-inch 横屏、深色 accessibility-large 下，现有 `testIPadNewSessionKeyboardKeepsSidebarPosition` fixture UI 用例通过（1 项、0 失败）。已检查浅色普通字号及深色大字号截图，图标居中、与文件夹比例协调且无裁切，新建入口可打开会话，键盘出现后侧栏位置稳定；临时模拟器已关闭并删除。
- 首轮共享 iPad 上的 `testProjectHeadersStayPinnedAndKeepTheirActions` 在返回后折叠／列表定位断言失败（2 处）；期间另一任务同时使用该模拟器，无法排除交互干扰，也不能将该失败归因于图标调整。真机、iOS 26、真实账号与 iPhone 本轮尚未验证。

## Pinned 箭头动态字号审查修复（2026-10-04）

- 降低 Pinned SVG 箭头的水平 hugging／compression resistance，让动态宽度约束覆盖资源的 24 pt 固有宽度；宽度约束继续使用非 required 优先级，兼容隐藏时的归零布局。
- 本轮 iPhone 17e／iOS 27 Simulator 测试构建通过；现有 Pinned 折叠 fixture UI 用例在浅色 large、深色 accessibility-large 下串行执行各一次，全部通过，无失败或跳过。已核对两组展开、折叠、列表模式切换和搜索截图，箭头随大字号放大、紧邻标题且无重叠或裁切。`git diff --check` 通过；临时模拟器已关闭并删除。
- 真机、iOS 26、iPad、真实账号及应用运行期间切换字号本轮未验证。

## 输入区上下留白收紧（2026-10-03）

- 单行保留 4 pt 垂直外边距、普通字号下 44 pt 高度；展开恢复 8 pt 垂直外边距及 10 pt 文字顶部内边距。按钮行仍预留 40 pt，图标、点击区域与中心距沿用既有尺寸。
- 单行额外向两侧各收进 12 pt，总宽比展开状态缩小 24 pt；聚焦后恢复完整宽度，横向留白采用 0.25 秒 smooth 过渡，遵循系统减少动态效果设置。编辑器与附件导入器继续由同一视图持有，保留草稿、光标及配置浮层期间的展开状态。
- 本轮 iOS 27 Simulator 构建通过，浅色的多行输入与运行配置 2 项现有 fixture UI 用例、深色 accessibility-large 的多行用例均通过，共 3 次执行，无失败。截图确认单行更窄、展开恢复原留白，草稿恢复与配置浮层期间的展开状态正常，按钮无重叠且位于键盘上方；聚焦录屏的 20 fps 抽帧包含横向留白的中间状态，按钮随容器移动。`git diff --check` 通过；多行视口边缘的文字轻微裁切观察仍存在，减少动态效果实际切换、iOS 26 与真机尚未验证。

## 输入区按钮尺寸统一（2026-10-03）

- 共用输入区的加号、提及、上下文用量与推理仪表统一使用 20 pt 图标尺寸与 36×36 pt 点击区域；上下文圆环的描边收在图标边界内。发送／停止使用 28 pt 圆形背景、14 pt 符号及同样的 36×36 pt 点击区域。组内相邻中心距离为 36 pt，推理到发送／停止的中心距离为 40 pt；左右组之间保留弹性留白。
- 收起输入区两侧各预留 40 pt，按钮在输入行内垂直居中；展开编辑区的按钮行预留由 48 pt 缩为 40 pt。沿用现有按钮行为、禁用条件及辅助功能标识。
- 本轮 36 pt 点击区域版本在 iOS 27 Simulator 构建通过，浅色运行配置与多行收起／展开的 2 项现有 fixture UI 用例通过。深色 accessibility-large 多行用例首次出现 4 条正文定位／键盘收起断言失败，测试结果文件生成也未正常结束；单独重跑同一版本后通过。首轮失败原因未确定，不能据重跑通过认定没有偶发问题。截图确认收起／展开按钮无重叠、位于键盘上方，上下文、推理与发送点击正常；模拟器已恢复浅色／large，`git diff --check` 通过。停止状态、iOS 26 与真机未单独验证。
- 多行编辑区截图另观察到视口边缘的文字轻微裁切，本轮未修改编辑器布局，裁切原因尚未单独验证。

## 账号头像圆形外观与菜单过渡（2026-10-03）

- 账号菜单在固定 44×44 的 ZStack 中使用独立的圆形 regular Liquid Glass 背景；背景不响应点击，且不启用 interactive，不作为菜单标签或按钮样式参与按压／预览动画。前景保留 plain 原生菜单、34×34 圆形头像及 44×44 的点击区域；ToolbarItem 隐藏共享背景，保留账号菜单与辅助功能标识。
- 上一版原生 glass 按钮消除了上下平切，但关闭时仍拉宽成胶囊，未满足持续圆形的要求。本轮最终版本在 iPhone 18 Pro Max／iOS 27 Simulator 构建及 1 项现有 fixture UI 回归通过，覆盖头像菜单、退出和再次登录。浅色默认字号两次、深色 accessibility-large 一次完整开关的录像按 20 fps 抽帧，确认独立 44 pt 外框始终为正圆，菜单消失后没有拉宽或上下缺弧；前景头像保留菜单快照的短暂位移动画。`git diff --check` 通过；真实账号的图片头像、iOS 26、iPad 与真机本轮尚未验证。

## 收起输入区的附件预览审查修复（2026-10-03）

- 图片预览状态和全屏呈现移到始终存在的 `SessionComposer`，附件条只传递预览请求；在发起全屏呈现前释放输入焦点，附件条收起后不会移除呈现宿主，也避免在呈现动画中改变输入区布局。收起状态的附件导入进度同时通过辅助功能值表达。
- 扩展已有照片 fixture UI 回归，覆盖未聚焦时导入、附件数量摘要、带附件／文字草稿收起与重新展开，以及预览主动失焦后的持续呈现、关闭、删除和发送；新建会话与后续会话的照片用例显式聚焦后检查附件。
- 本轮最终代码在 iOS 27 Simulator 编译通过，3 项相关 fixture UI 回归全部通过，无跳过，覆盖已有会话照片输入、新建／后续会话照片预览与删除发送、运行配置及上下文浮层。已核对 4 张收起导入、草稿保留、全屏预览和关闭后键盘恢复截图；`git diff --check` 通过。慢速导入进度、深色／辅助大字号、iOS 26、iPad、真机和真实账号本轮尚未验证。

## 输入区聚焦展开（2026-10-03）

- 共用输入区在未聚焦时收为单行，加号、输入预览与发送／停止按钮位于同一行；聚焦后恢复多行编辑、附件预览、提及、上下文用量与运行配置。编辑视口普通字号最多五行、辅助大字号最多三行，其余内容可在编辑器中滚动，避免挤占正文空间。设置浮层或 Advanced 打开期间保持展开，关闭后按输入焦点恢复；新建 Session／Tab 沿用进入时自动聚焦。
- 收起时原生编辑器使用单行截断布局，保留完整草稿、提及与光标；展开后恢复多行滚动。加号在收起时显示附件数量或导入进度，附件导入器不会随布局切换被移除。
- 本轮 iOS 27 Simulator 构建通过，浅色默认字号的 6 项相关 fixture UI 回归通过，覆盖配置、提及、新建 Session 与运行中停止／steer。修正长草稿单行文字溢出后，浅色多行回归再次通过；辅助大字号三行视口与实际可见正文滑动适配后，深色 accessibility-large 的多行与提及回归、20 项 ComposerMentions Swift 测试通过。最后一轮多行回归检查完整草稿恢复、键盘避让及发送后文字区域可见性，通过且未跳过。
- 已核对浅色与深色大字号的收起／展开截图，长草稿收起时没有相邻行残片，按钮与输入文字居中。`git diff --check` 通过；iOS 26、iPad、真机与真实账号本轮未验证。

## 回复 Markdown 表格字号（2026-10-03）

- 表格正文与表头均使用 subheadline（默认 15 pt），表头使用半粗体；随系统文字大小设置调整。
- 本轮 iOS Simulator 构建与 `git diff --check` 通过；尚未检查表格的 Simulator 外观、辅助大字号与真机显示。

## 回复 Markdown 标题字号（2026-10-03）

- 回复标题采用紧凑的系统文字样式：H1 使用 title2 半粗体（默认 22 pt），H2 使用 title3 半粗体（20 pt），H3–H6 使用 17 pt 的 headline／body，通过字重区分层级；随系统文字大小设置调整。正文与代码块字体沿用现有设置。
- 本轮 iOS Simulator 构建与 `git diff --check` 通过；尚未验证 Simulator 外观、较大文字大小及真机显示。

## PR #32 重命名测试键盘兼容性（2026-10-03）

- 重命名回归等待标题文本框可交互，保存时等待 Save 可用且位置稳定；软件键盘可见时才检查其位置，键盘出现或消失会重新计算稳定时间。保留按按钮当前中心、扣除窗口原点后的坐标点击，以及保存后弹窗关闭和标题更新断言。
- 本轮独立 iPhone 17e／iOS 27 Simulator 测试构建通过，列表与详情菜单的 2 项 fixture UI 回归全部通过，无失败或跳过；重命名弹窗截图确认软件键盘未显示时仍能编辑并保存标题。`git diff --check` 通过；软件键盘显示时的位置稳定分支、iOS 26 与真机外接键盘本轮未单独验证。

## Pinned 分组折叠（2026-10-03）

- Pinned 标题支持整行点击收起／展开，默认展开，紧邻标题的 MingCute Cute Regular `right_cute_re.svg` 箭头和 VoiceOver 的 Expanded／Collapsed 表示当前状态；箭头展开时旋转向下，随动态字号缩放，继续作为普通列表行显示。
- By Project 与 By Time 共用当前页面的折叠状态，折叠后置顶会话不回流到项目或时间列表；项目的新建入口仍可用。搜索时自动展开匹配的置顶会话并暂停折叠，清空搜索后恢复此前状态。状态只保留在页面内，未持久化或同步到 Lody。
- 本轮 Simulator 构建通过；新增 fixture 折叠用例在浅色默认字号与深色 accessibility-large 下均通过，覆盖折叠、模式切换、搜索与键盘，以及清空搜索后的恢复。截图已核对标题、箭头与键盘，无重叠或裁切；真实账号、iOS 26 与真机尚未验证。
- 两项现有列表／详情菜单回归在浅色通过，详情用例在深色 accessibility-large 下也通过，保留置顶、取消置顶、重命名、复制与归档覆盖，并按固定标识查询原生 Cell 类型的 Pinned 标题。早期重命名失败经录像定位为键盘推动弹窗移动时 XCTest 点击旧位置；测试现等待键盘可交互及按钮／键盘位置稳定，再按当前按钮中心点击并断言弹窗关闭，应用保存逻辑未改。深色详情运行出现 6 次 XCTest 动画通知等待超时后继续，全部断言通过，无跳过；专用模拟器已恢复浅色／large 并关闭，`git diff --check` 通过。

## 分支审查修复（2026-10-03）

- Pinned 折叠 UI 用例在操作前通过菜单显式选择 By Project，避免持久化的 By Time 偏好导致项目新建入口断言失败或遗漏模式切换覆盖。
- 重命名回归按保存按钮当前屏幕位置点击时，先扣除应用窗口原点，避免窗口不在屏幕原点时重复叠加偏移；继续等待键盘及按钮位置稳定。
- 上述两项测试修复本轮在独立 iPhone 17e／iOS 27 Simulator 完成构建，3 项 fixture UI 回归全部通过，无失败或跳过，覆盖 Pinned 折叠、列表菜单重命名／复制／归档和详情菜单操作。测试前在应用容器预设 By Time，运行中确认该偏好仍存在，折叠用例随后自行切换至 By Project 并通过全部断言。`git diff --check` 通过；iPad 窗口原点非零场景和 iOS 26 尚未实测。
- `@` 快捷入口按光标／选区替换文本时，直接更新引用范围和草稿，避免替换已有会话引用时被原生整段删除逻辑误判，导致新插入的 `@` 消失。保留原有编辑限制、UTF-16 光标定位和普通退格的整段引用删除行为。
- 新 tab 首轮连接提示通过独立的 `scenePhase` 变化在离开前台时结束隐藏；即使首轮仍未确认、订阅任务的组合 key 没有变化，回到前台也能正常显示连接提示。
- 新增两项 fixture UI 回归，覆盖选中会话引用后插入 `@`、重新选择并发送，以及首轮未确认时进入后台后恢复连接提示并完成同步。
- 本轮 iPhone 17／iOS 27 Simulator 构建、33 项 ComposerMentions／SessionTabs Swift 测试与 7 项 fixture UI 回归通过，无跳过；UI 同时覆盖已有会话、New Session、New Tab 的 `@` 按钮以及普通新建会话／tab 的首条气泡与后续草稿。已检查两项新增回归的 5 张截图，候选、输入框和键盘没有相互遮挡，返回前台后的导航连接指示器可见；`git diff --check` 通过。真实账号、iOS 26 和真机尚未验证。

## iPhone 返回会话列表的键盘布局修复（2026-10-03）

- 列表在搜索框未聚焦时保持完整高度，覆盖 iPhone 紧凑导航与 iPad 分栏；避免详情键盘影响返回转场中的列表视口，造成下方会话短暂消失后恢复。列表搜索框聚焦时仍正常避让键盘。
- 新增长列表 fixture UI 回归，覆盖带键盘通过返回按钮／边缘滑动返回、可见行位置与输入草稿保留，以及返回后搜索框避让自身键盘。
- 本轮 Simulator 构建、浅色默认字号的 2 项 fixture UI 回归及深色 accessibility-large 的 1 项返回回归通过，均未跳过；新增返回回归要求实际可见的软件键盘。录屏确认按钮返回、慢速滑动返回及停留期间，详情键盘仍可见时，列表下方会话持续显示；返回后的行位置、草稿及搜索键盘避让均通过断言。已检查截图并恢复模拟器外观和字号；`git diff --check` 通过。真实账号、iOS 26 与真机转场尚未验证。

## 新建 tab 首轮连接提示（2026-10-03）

- 新建 tab 显示本地首条消息后，首次订阅期间不展示连接 spinner 和 Connecting／Reconnecting 文案；首次 live 更新后恢复正常连接提示。首次订阅报错或回到后台时结束隐藏，后续重连继续显示。
- 只调整当前页面的提示可见性，保留真实同步状态与已读回执门槛；已有 tab、Main 和普通新建 Session 保持原有连接提示。
- 本轮 Simulator 构建与 2 项现有首轮 fixture UI 回归通过，覆盖新 tab／普通新建 Session 的首条气泡、下一条草稿及切 tab 后的保留；新 tab 用例遇到 XCTest 动画 idle 等待超时后继续执行并通过。fixture 未模拟 live room 的连接状态变化，真实账号首次同步与断线恢复尚未实测。

## New Session 分支读取延迟优化（2026-10-02）

- 分支读取复用当前工作区／gateway 的已同步 metadata，以及现有选项缓存中 30 秒内的机器项目目录快照；通常从会话列表进入时可直接发起 Git-state RPC，省去重新创建副本及 metadata／Flock 两段同步。目录缓存过期或缺失时，仍用可取消的独立副本同步，并更新目录缓存。
- 每次继续向机器读取实时 Git 状态，不缓存分支结果；保留模板机器匹配、项目登记与待删除检查、响应归属验证、独立鉴权及令牌刷新。协议参数与 Swift/JavaScript 消息契约未变，Git-state 请求仍在 metadata 读取锁外执行。
- 新增 4 项桥接回归覆盖有效目录缓存无额外同步且分支实时变化、30 秒过期刷新与待删除检查、工作区／gateway 隔离，以及取消后不污染缓存或销毁共享副本。本轮 frozen lockfile 安装、315 项 JavaScript 测试、bundle 重建、iOS Simulator 构建及 `git diff --check` 通过；未运行 Swift 单元测试与 fixture UI。真实账号加载耗时与机器端 Git-state 延迟尚未实测；Lody 当前 RPC 会检查完整 Git 状态，未提供只读分支的轻量参数。

## 外接键盘发送快捷键（2026-10-02）

- 共用 `SessionComposer` 的发送按钮默认绑定 Command+Enter，覆盖已有会话、New Session 与 New Tab；沿用按钮的发送能力与禁用条件，普通 Enter 保持换行。
- 本轮 iOS Simulator 构建通过；外接键盘实际按键、fixture UI 与真机尚未验证。

## Session 列表吸顶标题外观修正（2026-10-02）

- 可复用项目分组标题通过动态颜色提供器将 `systemBackground` 解析为具体颜色分量，避免 UIKit 将语义背景转换成吸顶模糊材质后出现灰色横条；标题背景继续与列表保持一致，并随浅色、深色与系统对比度设置更新。
- 标题上下留白由 18／8 pt 改为 13／13 pt，保持原有总高度，使文件夹图标、项目名称与新建按钮在标题栏内垂直居中。项目名称与会话标题继续共用 44 pt 起始位置，收起／展开与新建按钮的点击范围保持原有行为。
- 本轮已移除临时视图诊断代码后，在 iOS 27 Simulator 通过浅色 3 项、深色 accessibility-large 2 项 fixture UI 回归，覆盖跨项目吸顶、新建会话、收起／展开、无新建能力标题的全宽点击与标题／正文搜索。正式截图确认浅色标题、列表及导航背景均为 RGB 255，深色均为 RGB 0，图标、名称和按钮居中且无重叠；模拟器外观与字号已恢复，`git diff --check` 通过。真实账号、iOS 26 及真机尚未验证。

## Session 列表项目标题吸顶（2026-10-02）

- By Project 将项目标题改为原生 plain table 的分组标题；滚动到项目内时，标题固定在导航栏下方，下一项目进入时替换。标题使用系统背景，保留文件夹图标、收起／展开和右侧新建会话入口。
- Pinned、列表提示与 By Time 保持普通行；搜索仍按匹配会话分组，项目和会话使用稳定 ID，刷新继续仅提交变化的 diffable snapshot。
- 标题区域按标题按钮／新建按钮的顺序显式暴露辅助功能元素，避免吸顶时控件重复出现；保留原有 accessibility identifier，并为标题按钮加入 header 语义。
- 审查修正：不支持新建的项目标题在隐藏按钮时切换右侧约束，收回 52 pt 占位并恢复右侧的收起／展开点击范围，辅助功能列表仅保留可见控件；更新标题时复用已有项目行字典判断分组是否保留，避免逐项目扫描旧 snapshot。
- 新增长列表 fixture 与 UI 回归，覆盖连续滚动吸顶、跨项目切换、吸顶后新建会话、收起／展开及辅助功能元素唯一性。收起缩短内容后，继续使用原生列表的滚动位置调整。
- 新增独立会话 fixture 与无新建能力标题的 UI 回归，检查标题按钮延伸至右侧边距，并验证原隐藏按钮区域可以收起／展开会话。
- 审查修正后的本轮验证：Simulator 构建与浅色 3 项 fixture UI 回归通过；无新建能力标题与吸顶交互在深色 accessibility-large 下复验 2 项通过。已检查两种外观共 12 张截图，标题、图标及按钮无重叠或异常裁切；模拟器已恢复原外观与字号。`git diff --check` 通过。本轮未修改 JavaScript 或消息契约，未重跑桥接测试；真实账号、真机及 VoiceOver 实际操作尚未验证。

## PR #25 按 turn 保留拒绝结果（2026-10-02）

- 将本机观察到的永久拒绝按工作区／会话／turn ID 记入现有 `SessionCache`，复用账号与凭据关联校验、磁盘保护和退出登录清理。只保存 ID，不缓存正文或新增 Lody history 状态；记录仅在本机生效，不跨设备同步，也不能恢复本机从未观察到且已被后续 marker 覆盖的拒绝。
- `AppModel` 从正文快照和明确的发送拒绝结果记住对应 ID；原生发布快照及恢复显示时，已知拒绝优先于后续缺失／已送达投影。`lastMissingHistoryUserMsgId` 推进到另一条消息、刷新、重启及 Edit 恢复草稿后，旧气泡仍显示 “Not delivered”。归档保留记录，删除对应会话、失去工作区访问或退出登录时清理；旧版缓存缺少新字段时按空记录恢复。
- 新增 4 项 Swift 回归覆盖连续拒绝、旧确认覆盖、重启、旧快照显示、明确 RPC 拒绝后的编辑、工作区／会话／账号隔离和旧版缓存兼容。现有磁盘缓存回归同时验证拒绝记录落盘、不同凭据隔离及退出登录删除。3 项行为复现用例在修复前失败，修复后通过。
- 本次 222 项 Swift 单元测试和 1 项拒绝／编辑重发 fixture UI 回归通过，`git diff --check` 通过。未改 JavaScript、bundle 或 Swift/JavaScript 消息契约，本次未重跑 JavaScript 测试；真实账号连续拒绝、弱网与真机尚未验证。

## PR #25 永久拒绝前保留正文（2026-10-02）

- 修复首次 steer 正文上传失败后，`lastMissingHistoryUserMsgId` 导致同 ID 重试过早返回永久拒绝的问题。仍有原始 authored CRDT 增量时，先导入同一增量并确认正文同步，再返回 `rejected`，避免原生清理待发送记录和 Edit 恢复草稿后丢失旧的 “Not delivered” 气泡。
- 补传保留原 turn ID、时间戳、配置与附件，不再次发起 steer RPC 或写普通派发指针；补传失败／异常仍返回未确认，取消继续抛出取消错误，均保留增量供下次恢复。没有可恢复增量的已拒绝 ID 不创建新的正文。
- 新增 5 项回归覆盖 applied、delivery-unknown、RPC 超时后的跨副本拒绝补传，补传失败／异常／取消后的恢复，以及没有增量时禁止重建原 ID。4 项复现用例在修复前失败，修复后全部通过；另 1 项保护既有的禁止复活行为。
- 本次 frozen lockfile 安装、309 项 JavaScript 测试、bundle 重建通过。未修改 Swift/JavaScript 消息契约或原生 UI，本次未重跑 iOS 单元测试和 fixture UI；真实账号的永久拒绝补传、弱网与真机尚未验证。

## 消息投递恢复审查修复（2026-10-02）

- steer 明确返回 `delivery-unknown` 且首次正文上传失败后，重试仍补传原始 authored CRDT 增量，成功后才清除增量。保持原 turn ID、时间戳与配置，不重复发起 RPC 或写普通派发指针；补传失败仍保留增量供下次恢复。
- 原生收到同步确认或永久拒绝并结束待发送记录时，通过 `SessionSyncBridge` 精确清理对应工作区／会话／turn 的桥接重试状态。清理不取消仍在上传的副本；旧写入的迟到完成也不会删除后来创建的重试状态。
- 新增回归覆盖未知投递后的跨副本补传、补传再次失败、原配置与 CRDT 身份保留、清理键隔离以及活动上传与迟到完成。
- 本轮 3 项新增回归确认修复前失败、修复后通过；frozen lockfile 安装、304 项 JavaScript 测试、bundle 重建、49 项发送状态／HTTP Swift 测试及 2 项原生桥接取消测试（11 个参数场景）通过，`git diff --check` 通过。未重跑 fixture UI；真实账号的未知投递补传、延迟确认、弱网及真机尚未验证。

## steer 协议继续对齐（2026-10-02）

- 以 Lody 官方 main `c687e45a` 的 `session-send-delivery.ts`、`session-submission.ts`、`session-execution-service.ts` 和 `session-dispatch-logic.ts` 为参考。运行中输入在本地提交 `pending_apply` 后立即发起 `session/steer`，与正文上传并行；临时写入副本等上传结束才释放，RPC 保留 5 秒时限。明确 applied 时标记 `processing`、已读及 `_lodyDeliveryKind: steer`。
- 失败／取消后的重试在进程内保留首次 authored CRDT 增量、用户 turn ID、assistant 目标、时间戳与配置；新副本导入同一增量，避免同一领域 ID 被重复插入。已 applied 的请求不再次发 RPC；明确 `delivery-unknown` 仅等待同步确认，不重新投递。取消后的迟到响应不再修改正文或激活后续消息。
- `lastMissingHistoryUserMsgId` 是对应 ID 的永久拒绝，优先于 history 状态、处理确认和派发指针。桥接明确返回／投影拒绝，原生按账号／工作区／会话／turn 清理待发送记录，显示 “Not delivered”，禁用原 ID 的 Retry，允许 Edit 恢复草稿并用新 ID 发送；旧气泡继续保留拒绝标记。metadata 单独变化也会投影拒绝补丁。
- `recoveryOwned` 仍由机器负责恢复，客户端不写普通派发指针；兼容旧机器明确 `no-active-turn`／`promotion-failed` 时，已有 `pending_apply`、`pending` 或 `seen` 的同一 turn 可以立即作为后续消息修复，同时检查并保留更新发送者的指针。
- 本轮 frozen lockfile 安装、301 项 JavaScript 测试、bundle 重建、76 项定向 Swift 测试及浅色默认字号 2 项 fixture UI 回归通过，覆盖拒绝优先级、RPC 与上传并行、跨副本重试去重、旧机器恢复、取消、工作区隔离、编辑重发及下一条草稿保留。拒绝／编辑重发用例在深色 accessibility-extra-large 下另通过 1 次，两种外观截图确认旧 Retry 禁用、Edit 可用，重发后旧气泡保留拒绝图标，新气泡正常显示，大字号无重叠或异常裁切。专用设备交互工具不可用，本轮设备检查使用 XCTest、simctl 和截图；`git diff --check` 通过。真实账号的 steer 应用、机器恢复、弱网、后台取消与真机尚未实测。

## steer 超时后的投递确认（2026-10-01）

- 气泡左侧圆形箭头是未确认消息的 Retry。此前 steer RPC 超时后，即使机器稍后接收消息，正文订阅也不会更新本地 outbox，按钮会一直保留。
- 保留与 Lody 一致的 5 秒 RPC 时限；桥接从同一用户 turn 的 history 状态、`lastHandledUserMsgId` 或 `steerTurnStatuses` 投影明确接收确认，metadata 单独变化也产生正文补丁。`pending_apply`／普通 history 回显不算确认，`delivery_unknown` 保留未确认状态，不自动重发；missing-history 拒绝已在 2026-10-02 对齐为原 ID 永久失败，编辑后使用新 ID。
- 原生重建补丁后按工作区／会话／turn ID 清理已确认的 outbox 与 live client 待发送记录，避免 Retry 残留或阻止下一条发送；RPC 尚在结束时到达的确认同样生效。新建会话仍等待独立创建确认。
- 本轮 frozen lockfile 安装、291 项 JS 测试、bundle 重建、47 项定向 Swift 测试及 1 项 fixture UI 回归通过；UI 覆盖未确认时重试、确认后按钮消失、下一条草稿保留及气泡不重复。`git diff --check` 通过。真实账号的延迟确认、弱网与真机尚待复测。

## 本地项目当前分支只读（2026-10-01）

- New Session 的 Project 行下显示项目目录的当前分支，点击该行刷新，返回前台自动刷新。读取失败显示具体原因并可点击重试；非 Git、detached HEAD、无权限及旧机器不支持有明确状态。保留英文文案、动态字号与草稿，读取状态不阻止发送或选择项目。New Tab 继承原会话目录，不展示项目分支行。
- 读取经 `AppModel` → `LodyClient` → `SessionSyncBridge` 调用 `local-project/git-state`。按工作区／机器／项目验证目录登记、待删除状态及响应归属；机器请求在 metadata 读取锁外进行，沿用独立鉴权、令牌刷新与取消作用域。页面只保留当前分支，不缓存到磁盘或会话 metadata。
- 审查确认 Lody `ea3d599e` 的本地 daemon control 支持 checkout，但 Streams RPC 的 `dispatchLocalProjectControlViaRpc`／`precheckLocalProjectHistoryRequest` 不接受 `local-project/checkout-branch`。客户端已移除切换入口、checkout RPC、busy／dirty 检查、切换未确认状态及对应 fixture；当前功能仅为读取，不支持创建或切换分支。新会话仍直接使用项目目录，不创建 worktree 或固定分支。
- 协议参考：Lody `packages/loro-streams-rpc/src/rpc.ts` 的 Git-state 请求／响应，`packages/shared/src/node/local-project.cjs` 的分支 selector，`apps/cli/src/lib/message-handler.ts` 的 Git-state 访问校验及远端 control 路由，`apps/cli/src/lib/local-project-history-precheck.ts` 的远端请求白名单。selector 仅在显示名称时解码。
- 本轮 `pnpm install --frozen-lockfile`、289 项桥接测试、bundle 重建、XcodeGen、iOS Simulator 编译、6 项 ProjectGit Swift 测试及 `git diff --check` 通过。原生桥接的取消与代理 4 项测试通过（含 project-git 取消）；扩大运行套件时，现有压缩 Unicode／加密预览用例因模拟器 file 页面缺少 `crypto.subtle` 失败，未修改该用例或相关实现。
- 本轮 fixture UI 在浅色默认字号下 3 项、深色 accessibility-extra-large 下 2 项通过，覆盖刷新、前后台恢复、失败重试、草稿保持、发送及项目／目录选择；截图确认分支行与错误原因未重叠或裁切。深色大字号切换项目后，输入框截图偶尔仅显示草稿末尾，测试确认完整草稿仍保留，输入框滚动位置待后续排查。截图未绘出软件键盘，键盘存在与输入框避让的自动断言通过。真实账号与真机读取尚未验证。

## PR #23 后台代码比较审查修复（2026-10-01）

- 代码差异计算任务同时以文件内容和场景活跃状态为标识；离开 active 时通过现有取消处理器停止 detached 比较，返回前台只恢复未完成计算。已完成结果按原始 edit 保留，后台期间内容变化时不显示旧结果，回到前台重新计算；完整历史预览和备用工具片段共用此行为。
- 新增挂载真实差异视图的生命周期回归，通过可控 detached 比较确认后台不启动、inactive 取消、background 不重启、active 恢复、完成结果保留及后台内容变化后失效。临时恢复原来的任务标识后，新用例如预期失败，恢复修复后通过。
- 本轮 iOS Simulator 构建、17 项代码预览 Swift 测试、2 项 fixture UI 回归及 `git diff --check` 通过；UI 覆盖首次失败后重试、后台返回保留完整预览，以及比较超限时显示备用工具片段。真实账号与真机上的大文件比较及后台恢复尚未实测。

## 历史代码预览审查修复（2026-10-01）

- 成功加载按文件及已完成的重试编号复用；Retry 成功后回到前台保留结果，不再清空预览和重复请求。未完成的加载仍可取消并在前台恢复。
- 完整历史快照触发客户端行数或计算限制时，保留限制说明并回退到已有工具片段，继续标注相对行号和片段截断提示。
- 删除行按确定的显示方案继续在行号栏使用“−”；辅助功能仍读出原文件行号。
- 本轮 Simulator 构建、16 项代码预览 Swift 回归及 2 项 fixture UI 回归通过，覆盖首次失败后重试成功、后台恢复不再进入加载态，以及计算超限后仍可阅读工具片段。已检查深色默认字号截图中的限制说明、相对行号与代码片段，`git diff --check` 通过；浅色、大字号、真实账号与真机尚未验证。

## 历史代码预览（2026-10-01）

- 文件抽屉展开时通过 `AppModel` → `LodyClient` → `SessionSyncBridge` 读取 Lody `code-collab/open-turn-diff`，用会话、assistant turn ID 和文件路径定位历史快照，不用当前 Git 工作区替代历史修改。机器与所属会话从工作区 metadata 解析；tab 使用父会话作为加密 envelope 的 owner。请求和响应遵循 Lody Code Collab v2 的 AES-GCM、SHA-256 派生、AAD 和 base64url 格式，校验响应 owner、版本、轮次及相对文件路径。机器读取在 metadata 锁外进行，不阻塞正文订阅或列表刷新。
- 代码使用原生单列预览：真实文件行号、红删绿增、自动换行、三行上下文及可折叠代码段，代码段显示自己的增删数；文件头和 HUD 仍使用历史累计摘要。只有工具片段时继续标注相对行号，不作为完整文件快照。打开抽屉收起输入键盘，关闭后保留草稿。
- 代码段标题使用固定占位的同一个 chevron，展开／折叠仅旋转 90°，不改变标题行高及 Lines 文字位置；保留动态字号并遵循 Reduce Motion。每段标题和代码共用细边框，补齐左右边线。
- 标题布局修订验证：本轮 Simulator 构建及文件预览 fixture UI 用例通过，浅色默认字号、深色 accessibility-large 各 1 次；用例比较展开／折叠／再次展开的标题行尺寸和 Lines 文字偏移，两种外观截图均已检查，`git diff --check` 通过。该布局修订未做真机验证。
- 加载可取消，关闭文件、退出抽屉及离开 active 时停止请求；回到前台恢复未完成加载。结果按账号、工作区 generation 和原始文件记录校验；内存缓存仅复用已完成且有明确 checkpoint 身份的记录，限制 16 项及合计 32 MiB 文本，变更／删除和退出登录会清除对应数据；没有 checkpoint 身份时每次重新展开都读取。结束标记随文件 patches 投影，避免运行轮次结束时相同计数留下旧预览。
- 接受 plain 和 gzip-base64 UTF-8 快照，检查声明与实际字节数并限制解压增长；按 Lody 协议每份快照最多 10 MiB 原始文本、1 MiB 压缩数据，加密响应最多 3 MiB，移除两份完整文件合计 128 KiB／2,000 行的旧拒绝条件。缺失快照、无文本差异、二进制、机器限制、客户端字节／行数／计算限制、权限限制、机器离线与旧机器协议分别说明；网络失败、机器离线及可能恢复的权限／轮次缺失保留 Retry，确定的大小限制不显示 Retry。已有工具片段作为备用预览。fixture 单独支持大文件的小修改、首次失败重试与机器超限，不代表真实服务可用性。
- 原生比较先跳过相同前后缀，使用可取消且有预算的 Myers 行差异，保留绝对行号、三行上下文及分段。输入合计最多 200,000 行，比较与 frontier 工作最多 1,000,000 次、编辑距离最多 2,000；展示最多 2,000 行及约 512 KiB 文本，超长行截为 1,000 个字符／4,000 字节内的 UTF-8 完整片段。超出展示预算仍展示已有部分并注明文件总计包含全部修改；大范围重写超过计算预算时给出明确说明。
- 大文件修订验证：本轮 frozen lockfile 安装、283 项 JavaScript 测试、bundle 重建、最终 Simulator 构建及 `git diff --check` 通过，16 项代码预览 Swift 回归及 1 项实际 bundled file:// WebKit 加密／gzip 专项通过。覆盖 12,000 行文件的远距离小修改、重复／重排行的最小编辑数、CRLF／中文、部分展示、超长组合字符、计算预算、输入限制与取消。浅色默认字号 3 项 fixture UI、深色 accessibility-large 2 项 fixture UI 通过，两种外观截图已检查大文件的小修改、暂时失败重试及机器超限不显示 Retry。真实账号的大快照读取及真机仍待验证。
- 协议参考本机 Lody `ea3d599e` 的 `shared/src/code-collab.ts`、`loro-streams-rpc/src/rpc.ts`／`machine-rpc-server.ts`、`components/src/lib/code-collab-session-file-provider.ts` 和 CLI `code-collab-v2-service.ts`／`code-collab-v2-diff-store.ts`。本轮不包含 All Files、当前 Git 差异、完整文件打开或语法高亮。真实账号快照覆盖率、运行机器版本兼容、断网恢复和真机仍待验证。
- 首版验证：frozen lockfile 安装、282 项 JavaScript 测试及 bundle 重建通过，项目已用 XcodeGen 重新生成。最终应用构建、200 项 Swift 测试与浅色默认字号 3 项 fixture UI 回归通过；深色 accessibility-large 的 30 项定向 Swift 测试和 2 项 UI 回归通过。追加的 WebKit 专项套件 5 项测试通过，其中新增用例在实际 bundled file:// 页面验证 SHA-256、AES-GCM、gzip 解压与中文／CRLF。截图已检查真实行号、增删与分段、失败重试、抽屉缩放、软件键盘收起和草稿保留。首次 UI 检查发现容器标识覆盖代码段按钮，以及大字号下键盘占用阅读空间；修正辅助功能分组、焦点关闭和测试滚动目标后复跑通过。`git diff --check` 通过；上述 fixture／WebKit 测试不代表真实账号历史 RPC 已实测。

## 输入区 @ 快捷入口（2026-10-03）

- 已有会话、New Session 与 New Tab 的共用输入框在附件加号右侧显示 MingCute Cute Regular `at_cute_re.svg` 图标，替换 Full access 标记及其说明浮层；图标为 24pt，点击区域为 44pt，颜色随系统外观变化。
- 点击在当前光标／选区处插入 `@`，前一个字符不是空白时先补一个空格；空草稿、行首或已有空白不重复补空格。随后将光标放在 `@` 后并聚焦输入框，复用现有会话／技能建议面板、引用绑定与加载逻辑。发送时沿用输入框的编辑限制，VoiceOver 名称为 Mention。
- 本轮 Simulator 构建、浅色默认字号 5 项 fixture UI 与深色 accessibility-extra-large 3 项按钮 UI 用例通过，覆盖已有会话、New Session、New Tab、空输入、文字／emoji 后补空格、已有空白／换行及已选技能引用保留；浅色另覆盖技能／会话引用选择与发送。深色早期测试误点单行候选面板外的技能，滚动修订也越过目标，最终改为输入关键词使目标候选可见后复跑通过；没有因此修改产品逻辑。浅色 14 张、深色 9 张成功截图已检查，图标随外观呈黑／白色，候选面板、输入和操作行无重叠并位于键盘上方；`git diff --check` 通过。真机和 VoiceOver 实际朗读仍待验证。

## 分支审查修复（2026-10-01）

- 已确认图片的本地预览由独立缓存保存，最多 24 项、合计 8 MiB；会话缓存不再持有图片字节。显示时按工作区／存储会话／图片 ID 注入仍可用的预览，淘汰后从既有图片加载路径读取。退出登录、工作区移除及归档会清理对应缓存；未确认消息仍保留原附件以供重试。
- 共用输入框把本地化占位文案同步为原生 UITextView 的无障碍名称，保留文字 value 与测试 identifier。
- 删除 AppModel 中只供测试调用的旧发送／创建／tab／重试入口，以及旧路径专用状态；对应模型测试使用与生产 UI 相同的 stage／deliver 和原地 retry 流程。
- steer 目标只保留到发送确认或被替代；超时／异常及未确认结果仍保留原目标，避免重试改变投递身份。已重建桥接 bundle。
- 验证：本轮 frozen lockfile 安装、271 项 JavaScript 测试、bundle 重建、Simulator 编译及 3 项 fixture UI 回归通过。最终代码的 Swift 全量测试中 195／196 项通过；原有 POST 代理用例因 WebKit `SecurityError` 失败，重启本轮测试模拟器后单项复跑通过。代理测试套件另一次复跑在原生取消用例的 `send` 参数处超过 60 秒时限，该次不计通过。新增缓存／无障碍测试及迁移后的发送、创建、tab、搜索测试均通过。真实账号、真机及 VoiceOver 实际朗读尚未验证。

## 运行中输入直接 steer（2026-10-01）

- 运行中的空草稿显示暂停按钮；输入有效文字、添加附件或正在导入附件时切为 Send，清空后恢复暂停。发送期间保留禁用的 Sending 按钮，发送确认且草稿为空后回到暂停。直接提交 steer，不显示 queue 选择或确认。
- Live 发送在本地提交状态为 `pending_apply` 的用户 turn 后，通过工作区／机器隔离的 `session/steer` RPC 提交给原 assistant turn，正文上传与 RPC 并行；空闲会话继续先同步正文再发布派发指针。机器不支持 steer 或目标结束时，按 Lody 的已确认恢复协议处理为后续消息，无需用户确认；投递结果不明时保留原用户 ID、目标 ID、时间戳和配置，避免重投或覆盖另一发送者的派发指针。目标 ID 与既有重试 ID 一样仅保存在进程内。
- RPC 使用独立响应流并匹配请求 ID，支持令牌刷新、5 秒超时和原生取消；响应读取结束后释放网络请求。Fixture App 开启持续状态推送，使发送后与暂停后的按钮依据最新会话状态更新；模型测试默认仍可使用单次快照。
- 本轮 frozen lockfile 安装、268 项 JS 测试与 bundle 重建通过；72 项定向 Swift 测试通过，fixture 取消检查调整后又通过 27 项 fixture 测试。Simulator 构建、浅色完整交互用例和深色最大辅助字号专用用例均通过（UI 各 1 项），已检查输入、发送后与停止后的截图。深色综合用例未通过，其首条消息断言依赖可见区域；专用用例在 XCTest 点击未聚焦时改点输入框中心，并按实际残留文字完成清空。真实账号的 steer 应用、机器自动恢复、弱网／后台取消及真机尚未实测。
- 协议参考：本机 Lody `packages/shared/src/message.ts`、`schema.ts`、`packages/loro-streams-rpc/src/rpc.ts`、`packages/components/src/hooks/use-session-actions.ts` 的 `requestSessionSteer`、`apps/cli/src/session/session-execution-service.ts` 的 `steerSession`／`requeueUndeliveredSteer`。


## 子 tab 运行状态在列表中汇总（2026-10-01）

- 会话列表保留 Main 自身的 `activity`，新增只供列表显示的 `hasRunningTabs`；任意直接 tab 运行时显示 spinner，VoiceOver 也读出 Running。已关闭但未归档的运行 tab 仍计入；侧边面板、嵌套子会话、归档、删除及评论文档不计入。
- 列表刷新直接从同工作区 metadata 汇总，首次进入列表无需先打开详情。详情收到权威 tab 投影时更新根会话自身状态与汇总，并同步列表缓存；运行结束后恢复空闲／未读标记。每个 tab 的发送、停止与配置继续使用自身状态。旧缓存缺少新字段时仍可读取。
- 协议／表现参考：本机 Lody `components/src/components/sessions/session-list-rows.ts` 的 `buildChildSessionsByParent` / `getEffectiveSessionActivitySummary`；Kurage 仍沿用已有 metadata 状态投影，未增加 Lody 新版 presence 订阅协议。
- 本轮 frozen lockfile 安装、253 项 JS 测试与 bundle 重建通过；Simulator 构建、16 项定向 Swift 测试及 1 项 fixture UI 回归通过，覆盖子 tab 运行时根行标记、Main 保持空闲、停止后根行恢复 Idle、观察子 tab 时刷新 Main 状态及旧缓存兼容。UI 首轮额外要求停止按钮消失，但 fixture 观察仅返回一次快照；移除该不属于列表行为的断言后复跑通过。原有完整 tab 创建／切换／关闭／重开用例因多次等待动画结束而主动中止，不计通过。真实账号跨端 tab 的连续状态更新、真机、弱网和后台恢复尚未实测。

## 发送中气泡宽度与指示器间距（2026-10-01）

- 发送中的 loading 指示器改为覆盖在消息左侧留白，不再参与气泡横向尺寸计算，避免 loading 出现或结束时改变气泡宽度与文字换行。
- 指示器保留随字号变化的固有宽度，与气泡间距为 4 pt；失败／待确认消息继续使用原有 Retry／Edit 操作布局。
- 现有即时发送 UI 用例改用长消息，检查发送中与确认后气泡宽高一致，以及 loading 与气泡间距。
- 本轮最终布局 Simulator 构建成功；长消息发送用例在浅色、深色和深色最大辅助字号均通过，发送前后宽高一致且 loading 位于气泡外侧。默认字号截图已检查；最大辅助字号时 fixture 权限卡片占满可见区域，气泡位置由 UI 层级几何断言验证。拒绝消息编辑和待确认重试两项 fixture 用例也通过。未验证真机、真实账号或图片加文字的发送场景。
- 默认字号的最终补跑复用本轮成功构建（`test-without-building`）；后续整体重建曾被同时进行的其他改动阻断，`FixtureLodyClientTests` 引用了不存在的 `Conversation.isRunning`，未改动这些测试。

## 深色模式消息气泡对比度（2026-10-01）

- 我方文字气泡在深色模式使用不透明的系统 `systemGray5`，提升黑色会话背景上的可辨识度；浅色模式保持原有 6% 透明度的 label 色。动态颜色随系统外观自动切换。
- 浅色恢复修订的 Simulator 构建通过；现有多行 Unicode 消息复制 UI 用例在浅色／深色模式各通过一次。截图确认浅色气泡恢复原有淡灰，深色气泡与修订前一致。使用 fixture，未验证真机或真实账号。

## 发送与暂停按钮胶囊形试用（2026-10-01）

- 已有会话与 New Session／New Tab 共用的发送按钮改为胶囊形，按试用反馈从 46×36 pt 缩至 40×30 pt，箭头由 17 pt 缩至 15 pt；暂停按钮同步使用同一尺寸与形状。保持现有启用／禁用颜色，点击区域为 48×44 pt。
- 缩小并统一后的本轮 Simulator 构建通过；浅色默认字号截图确认发送／暂停按钮尺寸一致，完整显示在键盘上方。fixture 场景实际完成发送、暂停与再次发送；整项 UI 测试未通过，唯一失败为空草稿的无障碍 value 与预期占位文案不一致。未重跑深色／大字号场景，未验证真机。

## 首条消息即时创建与连续会话（2026-10-01）

- New Session／New Tab 点击发送时先预留 session ID 和 turn ID，立即显示文字、图片和文件气泡并清空首条草稿，后台执行上传和创建。首条消息沿用现有发送状态和原地 Retry／Edit，下一条草稿可继续编辑，确认与同步回传不会覆盖它。
- New Session 在原导航目标内进入会话；New Tab 在当前详情中创建并选中本地 tab。创建完成不再替换导航路径或执行页面返回，首次订阅期间保留本地气泡和图片预览，回传以同一 turn ID 接管。
- 待创建 tab 参与本地 tab 列表，旧同步投影不会把它移除或将用户跳回 Main；服务端投影追上后恢复正常关闭／删除行为。待创建摘要、附件和发送状态按账号／工作区隔离，未确认摘要不写入磁盘 session cache。
- 未确认首条消息保留原创建请求及附件；恢复和重试无需重新加载 agent 设置，也不依赖仍活跃的模板会话。明确拒绝时可主动 Edit 回到首条配置页刷新设置。创建未确认前暂停该会话的读取订阅与元数据操作，未扩展 live running-session 发送能力。
- 本次验证：Simulator 构建及 74 项定向 Swift 测试通过；9 项 fixture UI 回归通过，深色模式和辅助大字体另通过 2 项首次发送 UI 测试并检查截图。覆盖 8 秒创建延迟与 3 秒首次订阅延迟下的即时气泡、固定行 ID、键盘及下一条草稿保留、tab 切换／关闭／重开、原地重试和后台返回后恢复；真实账号的上传与创建延迟、弱网及前后台恢复仍需验证。

## 消息即时发送与原地重试（2026-10-01）

- 点击发送立即将完整文字、图片和文件放入同一条本地消息，清空输入框与附件，并保持输入框可编辑。上传和同步期间显示在消息下方的轻量发送状态；600 ms 内完成的发送不显示进度提示。
- 待发送内容由 `AppModel` 按账号与工作区／会话保存，跨 tab 和详情重新打开仍保留。新草稿与待发送消息相互独立；发送完成或重试不会清除后来输入的文字、引用或附件。每个会话在旧消息确认前仍只提交一条消息，未扩展 live running-session 发送能力。
- 未确认发送保留气泡及原 turn ID、配置和附件，允许原地 Retry；仅看到 history 中相同 ID 不代表 metadata 派发已确认。明确拒绝的发送显示失败，可重试或在输入框为空时主动 Edit 恢复原始草稿及引用；不会自动撤销气泡或覆盖草稿。
- 图片立即显示已导入的本地缩略图，并支持上传期间预览原图。上传成功后将预览和原图按凭证／工作区／会话／图片引用写入现有内存缓存；同步回传及后续 patches 复用本地缩略图。图片字节、发送状态与本地预览关联均不进入 Codable 协议或磁盘缓存，退出登录后失效。
- 本次验证：Simulator 构建通过；80 项定向 Swift 测试通过，最终版本再次通过 8 项发送状态测试及 7 项 fixture UI 测试。UI 覆盖实际 Photos 选图、图文即时显示、上传期间原图预览、确认后新草稿保留、原地重试去重、失败后恢复引用草稿、跨 tab 状态与详情重开；已检查截图和无障碍层级。真实账号的上传、超时恢复及回到前台仍需验证；待发送记录仅保留在当前进程内，不提供应用被终止后的离线发件箱。

## 输入与消息引用、紧凑 HUD（2026-10-01）

- 输入区图标尺寸协调：context 圆环路径从 25 pt 缩至 22 pt（含描边约 24.5 pt）；reasoning 仪表盘半径增至画布宽高较小值的 46%（含描边约 25 pt），按可见圆弧上下边界垂直居中。两者点击区域仍为 44 pt。本次 Simulator 构建通过；模拟器视觉检查及真机观感尚未验证。
- 详情底部 diff／subagent 胶囊改用 caption 字号、更小图标和内边距；玻璃背景包围紧凑内容，外部保留至少 44 pt 点击区域，辅助字号仍随系统缩放。
- 已选择的 skill／session 引用在输入框中使用蓝色名称与类型图标，替代 `$`／`@`；输入和气泡中的引用字重与正文一致，不额外加粗。普通输入触发字符仍显示原样。使用原生 UITextView 保留多行、选区与 IME，图标替换恰好一个 UTF-16 字符，草稿与发送绑定的路径／会话 ID 不变。删除触及引用仍整段移除，完整复制保留原始文本。
- 我方气泡识别 Lody 的 `use /token [Skill Path](path)` 和 `[@Title](session://id)` 两种明确引用格式，显示图标与可换行名称，隐藏协议包装；普通 Markdown 链接和未绑定的 `@`／`$` 词不转换。气泡完整 Copy／全选复制保留原文及引用目标，继续提供原生文字选择。
- 候选在聚焦时并行预读 skills／当前项目会话，搜索与 `@`／`$` 切换使用当前来源的内存结果；后台取消、来源切换丢弃旧结果、provider 变更后的 skill 校验保持。bridge 读取复用同工作区已同步 metadata，减少重复目录同步；机器 skill scan 仍经现有 RPC，不跨账号／工作区保存结果。加载、空结果、错误和正常列表共用输入区宽度；常规字号保持三行视口，辅助字号使用单行可滚动视口，避免长引用使候选被导航栏裁掉，候选图标宽度随正文缩放。
- 2026-10-03 skill 搜索修复：`$`／`@` 的技能候选只匹配名称和调用 token，移除描述全文匹配，避免 `$review` 命中仅在说明中提到 review 的无关技能。完全匹配优先于前缀匹配和包含匹配，同级保持来源顺序，排序后再取最多 25 项；空查询保持原有列表。参考本机 Lody `selectSkillMentionCandidates` 的名称／token 前缀优先规则；本客户端不搜索路径，避免机器绝对路径中的项目名误命中。本轮 Simulator 构建、20 项 ComposerMentions Swift 测试与 2 项 fixture UI 测试通过，覆盖名称／token 排序、描述误命中、候选数量限制、大小写／重音符号及已有／新建会话选择和发送。真实账号尚未复测。
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

## iOS 普通通知（2026-10-04 客户端接入；Cloud 目标与真实投递待确认）

- 官方 Lody main `4ccb2fe7` 的 `apps/cli/src/lib/notifications/notification-service.ts`、`message-handler.ts` 和 `session/session-execution-service.ts` 确认机器经 Cloud 提交完成／工具权限／问答事件；完成使用 turn ID 作为 `occurrenceId`，手动取消或没有输出时跳过完成通知。普通工具权限优先发送 Live Activity 提醒，成功且活动未结束时跳过普通推送；问答直接发普通推送。公开仓库不包含托管后端、移动端工程和部署配置，MCP 工具也没有读取通知部署配置的能力。
- [Innei/lody-ios `cebe0b97` 的接入文档](https://github.com/Innei/lody-ios/blob/cebe0b9794a9ac1e99cf500aec9bc4758be5c79b/apps/mobile/PUSH_NOTIFICATIONS.md#enable-native-ios-on-the-existing-backend) 描述该项目的第三方接入方式：独立 OneSignal App，由 SDK 注册设备并绑定 Better Auth 用户 ID，Cloud 的完整 `ONE_SIGNAL_APPS` JSON 数组追加发送目标。文档称该后端路径使用现有接口；这是第三方实现／文档证据，未获得官方公开来源确认，尚未读取 Kurage 所用部署的实际配置，也未验证向 `com.spike.kurage` 投递。
- 首阶段只接普通通知。拟追加项如下；`appId` 由 Kurage 自己的 OneSignal App 提供，`apiKeyEnv` 指向由服务方保存在 Cloud 环境中的 REST API key。维护完整清单并保留既有目标；APNs 配置属于该 OneSignal App 的 iOS 平台，客户端只携带公开 App ID。

```json
{
  "name": "kurage-ios",
  "appId": "199f71a9-c5a2-42c9-ac88-4b8b7593b06f",
  "apiKeyEnv": "ONE_SIGNAL_KURAGE_IOS_API_KEY",
  "push": true,
  "liveActivities": false
}
```

- 已接入固定版本 OneSignal iOS SDK 5.5.1、Notification Service Extension、Push／App Group entitlements 和显式 Info.plist。公开 App ID 通过 `KURAGE_ONESIGNAL_APP_ID` build setting 注入；2026-10-04 已设置 Kurage 的公开 App ID，并在 OneSignal 控制台确认 `com.spike.kurage` 的 Apple iOS 平台为 Active、使用 `.p8` APNs 认证。当前 Cloud 可用性开关关闭，或没有有效 App ID 时，构建不初始化 SDK并隐藏通知入口。App 与扩展版本保持一致；fixture 和原生单元测试不注册真实设备。配置步骤见 [NOTIFICATIONS.md](NOTIFICATIONS.md)。
- Settings → Notifications 由用户主动开启时请求授权，安装内偏好持久化，回前台刷新系统权限与注册状态。账号恢复／登录后以 `Account.id` 绑定；退出 opt-out／logout，清通知、badge、待处理点击与可见会话。冷启动点击等待账号，recipient 不匹配或重复点击丢弃；旧 SDK payload 没有 recipient 时只使用启动时捕获的 external ID。启动身份未知、退出或切到其它账号后，本次启动内拒绝无 recipient 的点击与前台展示，切回原账号也不恢复兜底。
- 点击通过 `AppModel` 核对当前工作区 catalog，再用 `LodyClient`／桥接层读取新同步的 metadata 解析根会话或直接子 tab，不读取正文或创建 Streams 流。关闭的 tab 重新打开；归档、删除、side-panel 或无权限会话不给导航；断网保留 Retry，取消及账号／工作区变化阻止迟到跳转。正在前台显示且已连接目标会话时抑制重复展示，设置或详情 modal 遮挡时正常展示。点击权限通知只打开会话，普通工具审批能力不变。
- 本轮验证：JS 327 项通过，按 frozen lockfile 安装并重建 bundle；Simulator App／扩展最终构建通过，原生整套 263 项通过，最终通知模型／路由专项 16 项通过，另补的 notification destination WebKit／原生代理取消回归单项通过。通知 fixture UI 五项分别验证通过：开启／关闭、冷启动等待登录、直接子 tab、不同账号丢弃、未配置禁用；首次开关测试点到 SwiftUI 暴露为 Switch 的整行空白，改点实际右侧控件后重跑通过。已核验 iPhone 17／iOS 27 标准字号截图；dark + accessibility-extra-large 的开关单项及截图也通过，文字换行、safe area 与控件正常，测试后恢复设备原设置。不把 fixture 当成真实投递验证。
- 公开 App ID 与 OneSignal APNs 平台配置已完成；后续 2026-10-04 检查已在登录的 Safari 私密窗口中确认一台真机订阅为 `Subscribed`，其关联用户有 external ID；用户已在本机开启通知。该检查未独立核对 external ID 与原生恢复账号的 ID，也未发送测试推送。仍需服务方确认的 Cloud 发送目标，以及签名真机上的 OneSignal 测试推送和真实 Lody 完成／问答事件验证，覆盖前台、锁屏、冷启动及退出／切账号。尚未修改 Cloud 部署或发送真实推送。Live Activity 的原生类型和远程 start 协议仍需另行核实。
- 本次 App ID 配置验证（2026-10-04）：重新生成 Xcode 工程，`generic/platform=iOS` 签名构建通过；检查产物确认公开 App ID、`aps-environment: development` 与 `group.com.spike.kurage.onesignal` 生效，`git diff --check` 通过。本次未修改通知逻辑或运行 fixture 测试，真机订阅与投递仍待验证。
- 同次签名构建已通过 `devicectl` 更新安装到配对 iPhone；Device Hub 镜像当前停在系统解锁页，启动命令 30 秒超时。尚未观察 App 内通知状态或确认 OneSignal 设备注册，不能将安装成功视为推送投递验证。
- Cloud 发送目标探索（2026-10-04）：重新核对官方 Lody `ea3d599e` 的 `notification-service.ts` 与 `cloud-api/src/index.ts`，机器 action 只携带 CLI 凭据、用户／工作区／会话及事件，不携带 OneSignal App ID 或 key；普通通知 action 返回 `null`，没有 provider message ID／recipient count，且 CLI 捕获失败。Innei `cebe0b97` 文档中的 `ONE_SIGNAL_APPS` 是部署级完整清单，并会取代 legacy fallback；追加 Kurage 时需保留既有清单和 fallback 目标。MCP 无通知部署配置工具；Convex 控制台当前需登录，未读取实际 Cloud 配置。已在 `NOTIFICATIONS.md` 补充 App 目标／用户 external ID 的区别、证据边界及「单设备测试 → external ID 测试 → 真实完成事件」验证顺序。本轮只更新文档，未运行 App／bridge 测试。
- 官方方案核对（2026-10-04）：读取官方 main `e73d3109`，`components/src/lib/onesignal.ts` 确认 Web／原生 Cordova 由 `VITE_ONESIGNAL_APP_ID` 初始化，`routes/$workspaceName/_auth.tsx` 用 `currentUser.id` 登录 OneSignal；机器通知 action 的公开参数不包含 App ID／API key／第三方目标。官方完整 Git tree 不含 Cloud sender 或 Convex 后端实现，官方通知指南只说明官方客户端开关，未找到 `ONE_SIGNAL_APPS` 或第三方目标登记的官方公开协议。`NOTIFICATIONS.md` 已将官方已验证链路与 lody-ios 的候选配置分开；后者必须获得服务方兼容性确认，不能据此声称官方托管 Cloud 支持 Kurage。此次只修正文档，未修改客户端或 Cloud 配置。
- 通知暂时隐藏（2026-10-04）：按用户要求，官方托管 Cloud 的 Kurage 发送目标确认前隐藏 Settings → Notifications；`OneSignalNotificationService.isCloudDeliveryEnabled` 暂置 `false`，正常启动不初始化 SDK，既有开启偏好不会自动恢复注册。现有实现、配置与偏好保留；`--fixture --fixture-notifications` 继续覆盖通知流程，普通 fixture 检查入口隐藏且 Theme／About 可用。本轮 iPhone 17／iOS 27 Simulator 测试构建、通知模型／路由 16 项原生测试及通知／Theme／工作区切换 7 项 UI 回归通过；浅／深色设置页截图确认通知入口隐藏且其余布局正常，`git diff --check` 通过。未修改 Cloud 配置，尚未更新真机安装或验证真实 APNs 投递；已有 provider 订阅不因隐藏入口而被删除。
- PR #38 审查修复（2026-10-05）：通知归属与 generation 校验集中在 SDK 回调共用的值类型中；旧格式通知只保留启动时捕获的身份，未知身份、退出或账号切换后不再从新账号补写兜底，前台展示采用相同规则。带明确 recipient 的通知继续核对当前账号；同账号冷启动恢复允许最初已捕获的点击，其它跨 generation 点击丢弃。新增 7 项身份策略测试（8 个用例），覆盖直接切账号、退出再登录、切回原账号、冷启动恢复与延迟回调。此次 iPhone 17／iOS 27 Simulator 构建及身份／通知模型／路由三个 suite 共 26 项原生测试通过，`git diff --check` 通过；未修改 bridge 或 UI，未运行 JS／UI 测试，真实 SDK 回调时序与 APNs 投递仍待真机验证。
- PR #38 工作区刷新审查修复（2026-10-05）：`refreshWorkspaces` 只在当前账号／请求实际提交目录后返回成功；失败、取消或被更新请求取代均返回失败。通知路由检查此结果，未提交时保留点击和 Retry，避免从空／旧目录推断无权访问；已有手动切工作区、账号变化和后台取消检查保留。新增可独立释放两个工作区请求的回归，以空缓存／仅缓存旧工作区及后续刷新成功／失败形成四种组合，检查旧请求先返回时仍保留点击，再用同一点击重试成功；工作区测试补查提交结果。修复前四种组合均复现错误清除，基线 xcodebuild 在记录断言失败后日志收尾停滞，仅结束本轮专属基线测试进程。修复后 iPhone 17／iOS 27 Simulator 构建、四个 suite 共 36 项原生专项测试及冷通知／子 tab／工作区刷新重试 3 项 fixture UI 测试完整通过，`git diff --check` 通过。未修改或复测 bridge；真实账号、SDK 回调时序与 APNs 投递仍待真机验证。

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
- 依赖使用 [natsustan/MarkdownView](https://github.com/natsustan/MarkdownView) 的 `feat/neutral-link-decoration`，钉在 `39166ee72f79d61c00065544bf3b4938f084cef6`。它保留原 `feat/plain-inline-code` 的无行内代码底色与 `.code` 等宽 presentation intent（原提交 `b30f9bb`，基于上游 3.0.0 / `6f452b5`），并加入本页所述的文字链接装饰。MIT 版权保留，模块名不变。RichText 及其他依赖仍指向上游。
- 未改围栏代码块的底色、圆角和描边。行内代码使用等宽字体，字号仍跟正文。真实会话里的行内代码和代码块字号尚未在模拟器核对。
- 行内代码等宽字体修订（2026-10-01）：MarkdownView 的 14 项文本转换测试通过，客户端 Simulator 构建通过；尚未在模拟器或真实账号核对视觉效果。

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

- 会话管理：列表长按与详情页右上角 ··· 提供 Pin/Unpin、Rename session、Copy Session URL 和红色 Archive（详情菜单的图标使用原色系统红，避免被菜单 tint 覆盖）。Pinned 单独置顶分组，项目/时间列表不重复显示；项目全部置顶时仍保留本地项目的新建入口。详情页置顶、取消置顶和重命名后留在会话，归档成功后返回。Pin 使用 Lody `isPinned`，重命名写入 `title` 与 `titleSource: user`，独立副本同步并核对 metadata 后更新缓存；复制 `https://lody.ai/{workspaceSlug}/sessions/{sessionID}`，不创建公开分享。旧磁盘缓存缺少置顶字段仍可读取。协议参考 `use-session-actions.ts` 的 `setSessionPinned` / `updateSessionTitle` 与 `loro-app-sidebar.tsx` 的 `copySessionUrl`。本轮 119 项 JavaScript 测试、bundle 重建与 123 项 Swift 测试通过；新增两项 fixture UI 测试在浅色默认字号、深色辅助大字号通过，覆盖两处菜单、项目/时间模式的 Pinned、重命名标题更新、URL 粘贴与归档返回，原有左滑归档回归通过。截图核对菜单红色 Archive 与大字号换行正常。真实账号跨端同步尚未验证。

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
- 运行中的会话在输入区以空草稿显示停止按钮，有有效文字或附件时切为 Send，清空后恢复停止；live 与 fixture 均支持，live 默认按 `session/steer` 发送，不弹出 queue 确认。停止仍从已同步的原始 history 找出最新未完成的 assistant turn，将其 ID 写入 `lastCanceledTurn` 并确认 metadata 同步；若 turn 尚未出现或已经结束，会提示重试。真实机器的 steer 与停止响应仍待实测。
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
- 会话文件修改：输入框上方的 Liquid Glass HUD 显示去重后的文件数及已知的累计增删行数，点击打开默认大屏、支持下拉缩小的详情 sheet；默认查看 Last turn，顶部菜单可切到 All turns，增删统计跟随当前范围。抽屉使用浅色白底/深色深灰底，文件头为紧凑的浅灰/深灰条目、小圆角，点击无箭头的文件头展开代码；右上角是中性的 Liquid Glass 缩放/关闭按钮组，不再使用系统导航栏的蓝色确认按钮。按会话轮次列出文件名、路径和计数。数据来自 assistant history 的 `fileDiff`；代码预览优先按轮次读取机器历史快照，已完成 `tool_call.content` 中显式的 `diff` 块作为备用片段，不从工具标题、locations 或 shell 文本猜测文件修改。代码按行显示红删绿增和上下文，历史快照使用完整文件行号，工具片段单独标注相对行号。同一轮 `fileDiff` 中同一路径的多条记录按 Lody 的 `buildSessionDiffSummary` 累加增删行数，不能让后面的零值覆盖先前计数；同一路径多轮修改保留各轮记录，汇总是历史累计，不是当前 Git 净差异；没有完整计数时 HUD 不显示对应总数，没有可用历史快照或工具片段时说明不可用原因并提供重试。空记录隐藏 HUD，删除/替换记录会清除旧结果；完整文件记录随正文缓存按账号/工作区/会话隔离。桥仅在文件记录变化时发送替换补丁，Swift 先恢复完整快照再发布；差异正文限制总传输预算和单文件大小，原生比较在后台执行并限制行数。历史轮次预览已接入只读机器 RPC；当前仍不提供 Unstaged、Staged、All Files 或远端完整文件浏览。真实账号返回的摘要/差异正文覆盖率和持续更新仍待实测。
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
3. 文本发送已按 Lody 桌面端的用户 turn 与 `latestUserMsgId` 协议接入。用户已用真机上的 Kurage 向真实会话发送消息，且消息抵达当前会话，验证了一次正常网络下的空闲发送与派发；网络中断时的确认、重启后的重试仍未验证。运行中输入现按独立 `session/steer` 协议提交，真实账号尚未实测；未接入客户端 queue 管理。问答请求已按匹配 turn ID 和 `requestId` 写入对应 `tool_call`；普通工具权限审批仍待接入。

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

## Session 列表图标与搜索字重（2026-10-01）

- 项目行的新建按钮使用与底部 New chat 相同的 `square.and.pencil` 图标，保留原有项目创建行为与辅助功能标识（2026-10-03 改用用户提供的 MingCute Cute Regular `edit_cute_re.svg` 编辑图标，见后文）。
- 搜索框文字从 regular 提高一级至 medium，包含占位文字和输入内容。
- 本轮浅色项目创建与搜索两项 fixture UI 测试通过；深色 accessibility-large 下搜索测试通过。仅涉及列表样式，未修改同步协议。

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

## 消息发送状态布局（2026-10-01）

- 发送状态移到我方消息内容左侧，与内容底部对齐；发送中显示延迟出现的进度图标，未确认显示重试图标，失败显示重试／编辑图标，失败原因可通过长按菜单或辅助功能描述读取。保留重试／编辑和发送状态的 accessibility identifier。
- 已发送与没有本地发送状态的历史消息不生成状态栏，移除原本气泡下方额外的 44pt 最小高度及 8pt 纵向间距。状态跟随整组我方正文／附件，避免给每个内容块重复添加状态。
- 本轮最终代码通过 3 项 fixture UI 用例（发送、未确认重试、失败后编辑），并检查浅色默认字号截图中的侧边图标、消息间距和键盘避让。未验证深色、大字号、VoiceOver 实际朗读或真实账号网络恢复。

## TestFlight 发布（2026-10-01）

- App Store Connect 应用名称为 Kurage for Lody，Bundle ID 为 `com.spike.kurage`；设备上的显示名称仍为 Kurage。
- 在应用目标显式设置 `TARGETED_DEVICE_FAMILY: "1"` 并重新生成工程，防止 XcodeGen 的目标默认值覆盖项目级 iPhone 设置。原归档被 Apple 以 iPad 多任务方向配置不完整拒绝；修正后的归档已确认 `UIDeviceFamily` 为 `[1]`。
- 本轮 Release 归档和 App Store Connect 上传成功，版本为 0.1.0（1），Apple 正在处理。TestFlight 审核登录信息已保存；凭据不记录在仓库中。本轮未运行单元／UI 测试或真实账号回归。

## TestFlight 0.2.0 发布（2026-10-02）

- 将应用版本更新为 0.2.0，构建号更新为 2，并通过 XcodeGen 重新生成工程。
- 本轮 Release 归档及 App Store Connect 上传成功，上传日志确认 `Upload succeeded`；Apple 已开始处理 0.2.0（2），尚未确认 TestFlight 可安装状态。归档确认 Bundle ID 为 `com.spike.kurage`、`UIDeviceFamily` 为 `[1]`、最低 iOS 为 26.0。
- 归档有一条 `ConversationView.swift` 非 Sendable 函数转为 `@MainActor @Sendable` 的并发警告。本轮未运行单元／UI 测试或真实账号回归。

## TestFlight 0.2.1 发布（2026-10-02）

- 将应用版本更新为 0.2.1，构建号更新为 3，并通过 XcodeGen 重新生成工程。
- 本轮 Release 归档及 App Store Connect 上传成功，上传日志确认 `Upload succeeded`；Apple 已开始处理 0.2.1（3），尚未确认 TestFlight 可安装状态。归档确认 Bundle ID 为 `com.spike.kurage`、`UIDeviceFamily` 为 `[1]`。
- 归档仍有 `ConversationView.swift` 非 Sendable 函数转为 `@MainActor @Sendable` 的并发警告。本轮未运行单元／UI 测试或真实账号回归。

## 历史文件预览回调并发警告修复（2026-10-02）

- 将历史文件预览闭包先声明为 `FilePreviewLoader`，再按能力决定传入该回调或 `nil`，让闭包创建时具备目标 `@MainActor`／`@Sendable` 类型；保留 workspace 校验和取消处理。
- 本轮 Xcode 27 Release 模拟器构建通过，arm64／x86_64 均重新编译且无并发警告；仍有未依赖 AppIntents.framework 的元数据提取提示。本轮未运行单元／UI 测试、设备归档或真实账号回归。

## iPad 与窗口自适应（2026-10-02）

- 应用启用 iPhone/iPad 通用设备族；iPhone 支持竖屏与双向横屏，iPad 支持四个方向。更新 `project.yml` 并重新生成 Xcode 工程，保留 0.2.1（3）版本配置。
- 会话入口统一使用 `NavigationSplitView`：宽窗口并排显示会话侧栏与详情，窄窗口由系统折叠为单列；侧栏保留项目分组、搜索、新建及会话操作，突出显示当前会话。空详情显示选择提示，归档或删除当前根会话后清空选择。窗口尺寸变化不切换不同的导航树，也不改变会话或 tab 的领域 ID。
- 聊天正文、输入区与标签栏使用最高 800pt 的内容宽度；新建页使用同一宽度限制。继续使用已有 UIKit 键盘避让、消息更新、底部跟随与历史阅读锚点，保持窄窗口下的可用宽度。
- 草稿、附件、提及、发送提示与配置选择由窗口内的 `ConversationDraftStore` 按工作区代次和会话保存，侧栏切换或返回后仍可编辑。切换工作区重建会话界面并释放旧草稿，退出账号也释放该状态。独立打开的归档详情和新建 tab 仍有自己的本地草稿作用域。
- 列表定期刷新按侧栏实际可见性启动；两栏下打开详情继续刷新列表，窄窗口进入详情停止列表定期刷新。现有实时会话订阅与后台取消逻辑继续沿用。
- 修复设备回归中发现的快速输入丢字／乱序：UIKit 在 SwiftUI 更新中重入的输入回调延后合并发布，已经由原生编辑器渲染的文字不逐键重写。原生光标只向状态发布，提及插入／整词删除通过独立请求定位光标，避免旧选择回放。
- 本轮 Simulator 构建与最终测试构建通过，生成的 Info.plist 已确认设备族为 `[1, 2]` 与上述方向；38 项聊天布局／tab／提及编辑 Swift 定向测试通过。iPhone 17／iOS 27 的 6 项 fixture UI 回归通过，覆盖旋转、独立草稿、归档、新建 session/tab 的完整输入与同步去重、提及选择和整词删除。
- iPad Pro 13-inch (M5)／iOS 27 的 3 项适配 UI、2 项新建 session/tab UI 及 1 项深色 accessibility-medium 侧栏／键盘 UI 均通过。检查了系统截图与 AX 层级：横屏窗口 1376×1032pt，侧栏 320pt，聊天内容 800pt、左右各留 128pt，发送按钮位于键盘上方。首轮创建用例因转场瞬时不可点击及过晚读取 Sending 中间态失败；等待可点击并把状态检查移到点击后立即执行，窄复测两项通过。横屏证据改用 XCUIScreen，避免 app.screenshot 的捕获范围裁切。模拟器已恢复原外观、字号、方向，并关闭本轮启动的 iPad。
- 仍有原有文件预览闭包的 Sendable 转换警告。本轮没有修改桥接、协议或依赖，未重跑 JavaScript 测试。深色大字时侧栏末行在初始滚动位置部分经过已有浮动搜索框后方；列表已预留滚动间距，未独立验证滚动露出。
- 此轮实现单窗口适配；独立多窗口、详情侧栏和键盘快捷键留待后续。没有针对未经确认的折叠设备型号或屏幕尺寸添加判断。真实账号、实际折叠设备、自由窗口缩放、浮动／外接键盘的实际交互尚未验证。

### 对 main 审查后的修复（2026-10-02）

- 新建根会话的首轮发送失败后选择 Edit，会在恢复正文、提及和附件时清除父导航的暂存会话 ID，避免随后列表重排或侧栏归档另一会话时关闭恢复编辑页；同时释放该失败根会话的窗口草稿。
- 两栏下打开会话详情仍可索引其它会话的正文。新订阅先取消排队的搜索读取，收到首个更新后恢复活跃搜索；一次性正文读取复用已有隔离读取机制，独立注册原生鉴权／取消作用域，完成或取消不会停止实时 SSE，也不保留临时文档副本。
- 窗口草稿按工作区代次和根会话归组。列表确认移除根会话时释放该根及其所有 tab 的正文、附件和编辑状态；普通切换、列表重排与关闭 tab 继续保留草稿。
- 本轮 frozen lockfile 安装、311 项 JavaScript 测试和 bundle 重建通过。最终代码重新构建并通过 37 项 Swift 定向测试，覆盖搜索与订阅并存、首次更新恢复索引、后台取消、根／tab 草稿清理及 WebKit→原生正文读取取消。未修改依赖或 Swift／JavaScript 消息契约。
- iPad Pro 13-inch (M5)／iOS 27 的 3 项 fixture UI 回归通过：打开详情时搜索其它会话正文、失败首轮恢复后侧栏归档仍保留草稿、归档当前会话后清空详情并打开另一会话。恢复草稿用例初轮遇到确认弹窗暴露重复 AX 节点，沿用现有 `firstMatch` 定位后重建并复测通过；截图与层级使用测试附件核查。真实账号、iOS 26 和真机未验证。

## 触觉反馈（2026-10-02）

- 已有会话发送／运行中 steer、New Session 和 New Tab 的首轮提交，在正文与附件成功进入本地 outbox 后给予一次轻量 impact（light，intensity 0.6），表示操作已受理；准备失败或按钮不可用时不触发。共用输入区通过绑定当前视图的 UIKit generator 即时反馈，避免新建 tab 转场移除视图而丢失 SwiftUI 状态触发。
- Advanced 中 provider／model／reasoning 的主动改值给予 selection 反馈；推理拨盘的点选、拖动与 VoiceOver 调整也只在用户改值时反馈。重复选择、同步配置刷新和能力加载不触发，原拨盘反馈不叠加。重复选择仍保留原有配置意图语义。
- 本轮 Simulator 构建、最终测试构建和 iPhone 17／iOS 27 的 5 项 fixture UI 回归通过，覆盖普通发送、推理选择、带模型选择的新建及首轮 session／tab 提交。两处输入框测试替身已适配发送回调的受理结果。构建仍有原有文件预览闭包的 Sendable 转换警告。模拟器无法验证实际触觉强度与转场手感，需真机体验；iOS 26 与真实账号尚未验证。
- 额外扩大到整个原生网络桥接测试套件的尝试出现文件页面 `crypto.subtle` 不可用、既有 send 取消用例超时，且与并行 UI 运行共用默认测试结果目录；该轮未作为通过结果，随后改用独立结果目录串行验证本次改动。文件预览加密、发送取消及真实账号实时输出、网络恢复和后台返回仍待进一步验证。

### iPad 侧栏细化（2026-10-02）

- 会话详情栏隐藏系统导航栏背景，移除标题与正文之间的显性横向分隔线。本轮构建与 1 项 iPad 布局 fixture UI 测试通过，iPad Pro 13-inch／iOS 27 横屏截图确认标题下横线消失；iOS 26、深色模式与真机未验证。

- 侧栏理想宽度调整为 360pt，最小 280pt、最大 400pt；实际宽度由系统根据窗口空间调整。此次宽度调整尚未在模拟器验证。

- 两栏下详情输入的键盘只顶起右侧详情栏：侧栏整体（列表视口与底部浮动搜索栏）忽略键盘、保持原位，软件键盘可能遮住侧栏底部。侧栏搜索获得焦点时与窄窗口仍沿用 SwiftUI 键盘避让。（2026-10-03 起取代此前列表视口经 `keyboardLayoutGuide` 收缩、搜索栏独立避让的做法，该做法会在外接键盘快捷栏出现时把侧栏底部顶起并露出灰底。）iPad Pro 13-inch (M5) 模拟器横屏下 3 项相关 fixture UI 回归通过，断言新建页／聊天页输入时侧栏列表顶部、底部与搜索栏位置不变；真机外接键盘快捷栏、深色与大字号未复测。侧栏背景改为显式忽略全部安全区（含键盘区域）的 `systemBackground`，避免外接键盘快捷栏下方露出分栏默认的灰色底；模拟器无法呈现外接键盘快捷栏，该视觉效果待真机确认。
- 侧栏与详情之间增加随系统外观变化的一像素分隔线，延伸到上下安全区。宽屏侧栏折叠按钮统一放在会话详情标题栏左侧，展开与折叠时保持相对于详情区域的位置；辅助功能标签随状态切换 Hide sidebar／Show sidebar，保持同一导航与草稿状态。（2026-10-03 调整按钮位置。）
- 折叠按钮统一改用用户提供的 MingCute Cute Regular `layout_4_cute_re.svg`，展开和折叠时使用同一图标；保持 24pt、矢量与 template 渲染，随系统外观变化。辅助功能标签仍随实际动作切换 Show sidebar／Hide sidebar。（2026-10-03 取代此前左右箭头图标。） 本次 Simulator 构建及 iPad Pro 13-inch (M5)／iOS 27 的一项浅色 fixture 折叠回归通过；截图确认两种状态的图标一致，标题间距保持一致，草稿保留。模拟器保持原浅色与字号；本次未复测深色、大字号、真机或 iOS 26。
- 宽屏会话详情使用系统 editor 工具栏布局，将标题及项目／机器副标题靠左放在折叠按钮右侧；新建会话／tab 的标题同步靠左。紧凑窗口沿用系统自动布局。（2026-10-03）本次构建、iPad Pro 13-inch (M5)／iOS 27 的两项浅色 fixture UI 回归与一项深色 accessibility-medium 折叠回归通过；截图与 AX 层级确认会话标题距按钮右缘恒为 16pt，折叠与恢复后间距一致，新建会话标题同样靠左，无重复标题或重叠。模拟器恢复原浅色与字号；真机、iOS 26、紧凑窗口与自由缩放本次未复测。
- 当前会话使用左右留白的灰色胶囊背景，关闭表格行的默认焦点效果；保留选中状态的辅助功能语义、稳定行 ID、滑动归档和长按菜单。
- 补充新建页／聊天页键盘开合时侧栏位置、折叠按钮位置及折叠恢复后的草稿回归；继续运行已有自适应导航、搜索和归档用例。
- 2026-10-03 折叠按钮位置调整：本次构建通过，iPad Pro 13-inch (M5)／iOS 27 的两项浅色 fixture UI 回归通过（新建页键盘布局、折叠恢复保留会话和草稿），折叠用例在深色 accessibility-medium 下也通过。截图与 AX 层级确认按钮展开／折叠时均距会话区域左缘 14pt，高度一致，无重叠或裁切。首轮位置断言误用覆盖整窗的导航栏 AX 边界，改为侧栏边界与窗口边界后复测通过。模拟器已恢复原浅色与字号；真机、iOS 26 与自由窗口缩放尚未验证。
- 本轮最终代码构建通过；iPad Pro 13-inch (M5)／iOS 27 的 4 项浅色 fixture UI 回归、1 项深色 accessibility-medium 键盘回归，以及 iPhone 17e 的 2 项单列导航／草稿回归通过。最后补充末行滚动与点击后，深色同一用例再次通过：末行可移到搜索框上方并打开对应会话。截图与 AX 层级确认侧栏顶部固定、列表视口与搜索在键盘上方、分隔线贯穿两栏、选中胶囊没有蓝色焦点框，隐藏／恢复侧栏保留选择和草稿。
- 初版整栏忽略键盘时，软件键盘遮住了搜索栏；修正为列表主体与搜索覆盖层独立避让后复测通过。模拟器外观、字号和方向已恢复，仅关闭本轮启动的设备。本轮未修改桥接、协议或依赖，未运行 JavaScript 或 Swift 模型测试；实际账号、真机、iOS 26 及浮动／外接键盘交互尚未验证。

## 新建页信息行间距（2026-10-02）

- New Session 的 machine／project／branch 使用相邻的 44pt 最小高度行，移除原有额外 14pt 纵向间距；New Tab 的继承项目行复用相同高度与图标布局。加载、错误和重试提示仍保留独立间距。
- 本轮构建与 iPhone 17／iOS 27 的 2 项浅色默认字号 fixture UI 回归通过，另 1 项深色 XXXL 回归通过；截图确认新建 session／tab 的信息行等距、图标文字对齐，深色大字没有重叠或裁剪。XCTest 在发送步骤出现动画等待超时后继续执行，最终均通过。模拟器外观与字号已恢复。截图未显示软件键盘，本轮未验证键盘弹出布局、真机、iPad 或 iOS 26。

## TestFlight 0.3.1 发布（2026-10-02）

- 将应用版本更新为 0.3.1，构建号更新为 5，并通过 XcodeGen 重新生成工程。
- 本轮 Release 归档及 App Store Connect 上传成功，上传日志确认 `Upload succeeded`；Apple 已开始处理 0.3.1（5），尚未确认 TestFlight 可安装状态。归档确认 Bundle ID 为 `com.spike.kurage`、`UIDeviceFamily` 为 `[1, 2]`。
- 补查上一轮 0.3.0（4）上传日志，确认其也已上传成功。
- 归档仍有 `ConversationView.swift` 非 Sendable 函数转为 `@MainActor @Sendable` 的并发警告。本轮未运行单元／UI 测试或真实账号回归。

## TestFlight 0.3.2 发布（2026-10-02）

- 将应用版本更新为 0.3.2，构建号更新为 6，并通过 XcodeGen 重新生成工程；包内包含工作区已有的文件预览加载闭包并发警告修复。
- 本轮 Release 归档及 App Store Connect 上传成功，上传日志确认 `Upload succeeded`；Apple 已开始处理 0.3.2（6），尚未确认 TestFlight 可安装状态。归档确认 Bundle ID 为 `com.spike.kurage`、`UIDeviceFamily` 为 `[1, 2]`。
- 本轮归档未再出现此前的 `ConversationView.swift` Sendable 转换警告；仅有未依赖 AppIntents.framework 的元数据提取跳过提示。本轮未运行单元／UI 测试或真实账号回归。

## MingCute 活动与编辑图标（2026-10-03）

- 新建会话的分支行使用用户提供的 `git_branch_cute_re.svg`（`git-branch` 资源），复用 `NewSessionIcon` 的字号缩放与对齐，保留 template 渲染、刷新行为及辅助功能标识。

- 从本机 MingCute Icon System Pro v1.50 的 SVG/cute regular 导入活动图标：命令使用 `terminal_box`，读取使用 `document_2`，编辑使用 `pencil`，搜索使用 `search`，网络获取使用 `earth`，其他工具使用 `tool`；活动摘要与展开步骤共用映射。活动组及 Worked for 展开箭头使用 `right`，保留旋转动画与减少动态效果设置。
- 消息失败后的 Edit 使用 MingCute pencil 资源；会话／子会话的 Rename session 菜单恢复原有 SF Symbol `pencil`，覆盖 SwiftUI 与 UIKit，与其他菜单项保持一致。列表底部 New chat 和项目 New Session 改用用户提供的 MingCute Cute Regular `edit_cute_re.svg`（`pencil-square` 资源）。terminal／pencil 与用户提供的 SVG 一致；资源保留矢量和 template 渲染，继承现有前景色。活动图标随字号缩放并设置文字基线对齐，固定点击区域内的编辑／新建图标限制最大尺寸，保留现有交互和 accessibility identifier。
- 本轮最终 iOS Simulator 构建通过；只有未依赖 AppIntents.framework 的元数据提取跳过提示。未运行单元／UI 测试。iPhone 17／iOS 27 可启动 fixture，但设备交互工具缺失且 CUA 无法打开 Simulator，停在欢迎页，未能检查活动区和菜单的实际图标、深色模式或大字号；真机与真实账号亦未验证。

- 方框铅笔修正本轮 iOS Simulator 构建通过；已核对原始图标样式，未运行 UI 测试或检查应用中的深色／大字号显示。

## TestFlight 0.4.0 发布（2026-10-03）

- 将应用版本更新为 0.4.0，构建号更新为 7，并通过 XcodeGen 重新生成工程。
- 本轮 Release 归档及 App Store Connect 上传成功，上传日志确认 `Upload succeeded`；Apple 已开始处理 0.4.0（7），尚未确认 TestFlight 可安装状态。归档确认 Bundle ID 为 `com.spike.kurage`、`UIDeviceFamily` 为 `[1, 2]`。
- 归档仅有未依赖 AppIntents.framework 的元数据提取跳过提示。本轮未运行单元／UI 测试或真实账号回归。

## TestFlight 0.4.1 发布（2026-10-03）

- 将应用版本更新为 0.4.1，构建号更新为 8，并通过 XcodeGen 重新生成工程。
- 本轮 Release 归档及 App Store Connect 上传成功，上传日志确认 `Upload succeeded`；Apple 已开始处理 0.4.1（8），尚未确认 TestFlight 可安装状态。归档确认 Bundle ID 为 `com.spike.kurage`、`UIDeviceFamily` 为 `[1, 2]`。
- 归档仅有未依赖 AppIntents.framework 的元数据提取跳过提示。本轮未运行单元／UI 测试或真实账号回归。

## TestFlight 0.4.2 发布（2026-10-03）

- 将应用版本更新为 0.4.2，构建号更新为 9，并通过 XcodeGen 重新生成工程。
- 本轮 Release 归档及 App Store Connect 上传成功，上传日志确认 `Upload succeeded`；Apple 已开始处理 0.4.2（9），尚未确认 TestFlight 可安装状态。归档确认 Bundle ID 为 `com.spike.kurage`、`UIDeviceFamily` 为 `[1, 2]`。
- 归档仅有未依赖 AppIntents.framework 的元数据提取跳过提示。本轮未运行单元／UI 测试或真实账号回归。

## TestFlight 0.4.2 再次发布（2026-10-04）

- 保持应用版本 0.4.2，将构建号更新为 10，并通过 XcodeGen 重新生成工程；上一轮构建号 9 已上传，本轮使用新构建号。
- 本轮 Release 归档及 App Store Connect 上传成功，上传日志确认 `Upload succeeded`；Apple 已开始处理 0.4.2（10），尚未确认 TestFlight 可安装状态。归档确认 Bundle ID 为 `com.spike.kurage`、`UIDeviceFamily` 为 `[1, 2]`。
- 归档仅有未依赖 AppIntents.framework 的元数据提取跳过提示。本轮未运行单元／UI 测试或真实账号回归。

- 2026-10-04 恢复账号访问后再次重试，现有 0.4.2（11）归档上传成功，日志确认 `Upload succeeded`。Apple 已开始处理，尚未确认 TestFlight 可安装状态；本次仅重试上传，未重新归档或运行测试。

## Context window 会话缓存用量（2026-10-07）

- Context window 浮层增加 Session cache，显示缓存命中率、读取 token、写入 token 和用量覆盖轮次；现有上下文窗口环及已用／总量保持原口径。命中率使用 `cacheReadInputTokens / (inputTokens + cacheReadInputTokens + cacheCreationInputTokens)`，没有输入 token 时显示未知，不把缺失用量当作零命中。普通字号保持紧凑浮层，辅助字号或键盘导致可用高度不足时改为可滚动内容。
- 桥从当前会话 history 的 assistant `tokenUsage` 汇总已记录轮次，包括没有可见正文的结束轮次；不叠加子代理任务中的用量或其它 tab／会话。校验五类 token 为安全非负整数，缺失／无效记录只计入覆盖范围。每次 history 更新重新投影；用量晚到、修正或删除，即使正文不变也会发送最新统计，原生快照替换该字段，沿用现有账号／工作区／会话缓存隔离和 Codable 兼容。
- 协议参考：官方 Lody main `72b118b5` 的 `packages/shared/src/session-data/token-usage.ts`、`apps/cli/src/lib/usage/turn-token-usage.ts` 与 `message-handler.ts`，以及固定 ACP Core `85ec3aba` 的 `ModelUsage` 互斥计数口径。当前界面展示已同步历史中的记录，不能补齐旧 daemon／不报告 delta 的 Agent 未写入的轮次，也不是云端账单汇总。
- 本轮 frozen lockfile 安装、349 项 JavaScript 测试与 bundle 重建、iOS Simulator 构建及 32 项 FixtureLodyClient／ConversationStreaming 原生测试通过，回归覆盖隐藏轮次、无效／缺失／零值、数值边界、正文不变时的迟到／清除、Codable 往返与工作区隔离。iPhone 17／iOS 27 浅色 large 的缓存浮层及既有 composer 配置两项 fixture UI 检查、深色 accessibility-extra-large 的缓存浮层一项检查通过；截图与层级确认普通浮层紧凑、辅助字号可滚动读取顶部与完整覆盖说明，关闭后草稿保留。测试对键盘完成布局后按实测坐标点击／滚动，避免 XCTest 使用旧点击坐标或空滚动区域。生成 bundle 与 app 内资源哈希一致，`git diff --check` 通过；真实账号、真机、iOS 26、iPad 与 VoiceOver 实操尚未验证。
