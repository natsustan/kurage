# Settings 与 Workspace 切换规划

2026-10-05。第一步已实施：头像入口、Settings、账号摘要、Workspace 二级页面、About 和退出确认。第二步已加入 Appearance（System / Day / Night、Black / Blue）和 Haptics；List View 与第三步 Workspace 资源仍是后续方案。

## 推荐方案

头像打开一个固定为参考图约 85% 高度的 Settings sheet，不提供上拉展开或拖动指示器；辅助字号在同一高度内滚动。Settings 自带导航栈，Workspace、Appearance、Haptics、Notifications 和 About 都在其中推进二级页面。Workspace 放在顶部账号卡片的第二行；选择完成后回到 Settings，更新工作区名称，关闭 Settings 后看到新工作区的会话列表。

采用参考图的圆角分组、克制的灰色背景和较宽松的行间距，设置行只显示标题、当前值和导航箭头。沿用原生导航、sheet、Toggle 和确认对话框；Appearance 用卡片选择外观与强调色。

## 规划时核实的现状

| 范围 | 当前代码 | 对规划的影响 |
| --- | --- | --- |
| 头像入口 | `SessionSidebarView` 中的 Menu；账号邮箱、多个 workspace 时的子菜单、Sign out | 改为打开 Settings 的 Button，保留头像外观与入口标识 |
| 账号 | `Account` 有 email、可选 id/name/image | 可立即做账号摘要；缺少资料编辑接口，首版作为信息卡片 |
| Workspace | `WorkspaceSummary` 有 id/name/slug；HTTP 读取 `api/auth/organization/list` | 可立即做列表和切换；头像先用首字母，副标题使用工作区地址 |
| 切换与缓存 | `AppModel.selectWorkspace` 先更新选中 ID 和缓存，再刷新 sessions | 选择已生效与 sessions 拉取成功是两个状态，失败文案不能混淆 |
| 导航生命周期 | `RootView` 为 `SessionListView` 设置 `.id(model.workspaceGeneration)` | Settings 的呈现状态与宿主必须在该重建边界之外 |
| 其它现有入口 | 右侧菜单包含 By Project / By Time 与 Archived sessions | 归档保留在会话列表；列表偏好可在下一阶段加入 Settings，并保留快捷入口 |
| 本机偏好 | 列表模式使用 `@AppStorage("sessionListMode")`；触觉已存在，但没有统一开关 | 后续统一偏好访问，沿用已有存储值，避免迁移丢失选择 |
| 已读回执 | `ConversationContent` 已有 `isReading`，但 tab 容器当前传入 true | Settings 覆盖会话时应传入 false，尤其是 iPad 侧栏打开设置的场景 |
| 草稿 | `ConversationDraftStore` 由会话界面持有，按 workspace generation 隔离 | 保持 Settings 不应顺带上移或混用旧工作区草稿；跨工作区草稿恢复属于独立功能 |
| Fixture | 默认只有 Demo 一个 workspace | 需增加明确隔离的多 workspace 与失败场景，才能验证切换流程 |

## 页面与信息结构

当前首页只呈现已经接通的内容：

```text
Settings                           Close

┌ Account ──────────────────────────────┐
│ [Avatar] Display name                 │
│          Email                        │
├───────────────────────────────────────┤
│ Workspace             Current name  › │
└───────────────────────────────────────┘

┌───────────────────────────────────────┐
│ Appearance                    System › │
├───────────────────────────────────────┤
│ Haptics                           On › │
└───────────────────────────────────────┘

┌───────────────────────────────────────┐
│ About Kurage                        › │
└───────────────────────────────────────┘

┌───────────────────────────────────────┐
│ Sign out                              │
└───────────────────────────────────────┘
```

- 账号卡片复用头像加载与首字母回退。名称为空时显示邮箱用户名，完整邮箱作为副标题；首版没有账号详情跳转箭头，避免引导到只有重复信息的页面。
- Workspace 行始终存在，包括只有一个工作区的账号。右侧显示当前名称，名称过长时允许布局降为两行。
- Appearance 推进二级页面：第一组为 System / Day / Night 三列，第二组为 Black / Blue 两列；选中项用灰色实心卡片，未选项用细边框。辅助字号改为纵向排列，页面可滚动。沿用 `appTheme` 的 system / light / dark 存储值，不丢旧选择；强调色用 `appAccent`，默认 Black，深色下单色控件按语义变为浅色。
- Appearance 与 Haptics 位于同一个圆角分组内，以分隔线区分两行；Haptics 位于 Appearance 下方，进入同类二级页面控制 Haptics Feedback，默认开启；`hapticsEnabled` 保存本机偏好，并控制现有 reasoning 拨盘与 Advanced 配置选择的触觉。
- Workspace、Appearance、Haptics、Notifications 与 About 设置行移除前置装饰图标。
- About Kurage 展示从 Bundle 读取的版本与构建号，并说明 Kurage 是独立的第三方 Lody 客户端。页面扩展时可加入开源许可等信息。
- Sign out 单独分组，红色文字，点击后用原生 confirmationDialog 确认，再调用已有 `model.signOut()`；不增加新的鉴权实现。
- 首版不渲染空的 Preferences 或 Workspace Resources 分组。下一阶段的已完成功能插入账号卡片之后、About 之前。

后续首页组织：

| 分组 | 入口 | 层级规则 |
| --- | --- | --- |
| Account | 账号摘要、Workspace | 最上方，作为账号与工作区上下文 |
| Preferences | Appearance 与 Haptics（已实施）、List View | 统一推进二级页面，在页面内完成选择或开关 |
| Workspace Resources | Machines、Agents、MCP Servers、Skills | 首页展示摘要，进入资源列表，再进入详情；完成协议接入后逐项出现 |
| About | About Kurage | 版本、客户端身份和许可等信息 |
| Session | Sign out | 页面底部独立操作组 |

会话内的 provider/model/reasoning 仍属于该会话下一轮输入配置；新会话的首次配置保留在创建流程。以后如增加 Agent 默认配置编辑，应作为远程配置功能单独说明作用范围。

## Workspace 二级页面

```text
Back                         Workspace

[D] Demo                                  ✓
    lody.ai/demo

[S] Studio
    lody.ai/studio
```

- 从 Settings 的 Workspace 行推进同一个导航栈，使用原生返回按钮和返回手势。
- 行内放约 40 pt 的圆形首字母头像、主标题、副标题和尾部勾号。颜色按工作区 ID 稳定生成，勾号同时有 VoiceOver 的选中语义，避免只靠颜色。
- 副标题来自 `slug` 与 `LodyEndpoints.webOrigin`。它是工作区地址说明，不承担另一个跳转动作；slug 缺失时省略副标题，不显示内部 ID。
- 短列表直接排列，多个工作区和辅助字号可滚动；长名称允许自然增高，最后一项保留底部安全区域。内容宽度最多 600 pt，与其它 Settings 页面一致。
- 显示已有列表后再后台刷新，刷新期间保留选择和可用行，不先清空整页，也不插入刷新文字或加载行。用户手动刷新使用原生 List 的下拉刷新指示器；仅没有数据的初次加载显示居中转圈。不要因为视图重算而重复拉取。
- 选当前项：只关闭选择器，不发 sessions 刷新，不增加 workspace generation。
- 选其它项：通过 `AppModel` 提交，确认 `selectedWorkspaceID` 已更新后关闭选择器，Settings 保持打开并显示新名称；会话界面继续按已有 generation 机制重建，详情返回未选择状态。
- 不等待 sessions 拉取结束才关闭选择器。新工作区加载失败时仍是已选中工作区，列表展示缓存或失败重试；不能误报“workspace 切换失败”或自动跳回旧工作区。
- 二级页面返回只取消它自己拥有的 workspace 列表刷新，已经提交的切换及其会话刷新由 `AppModel` 管理，避免随页面销毁被取消。

参考图的 Add an account 不纳入首版：当前安全存储与 `LodyClient` 都按一个账号设计，多账号切换需要完整的凭据、缓存、outbox 和订阅隔离。创建工作区、接受邀请或成员管理也应在相应协议接通后加入，不能用灰色占位项伪装能力。

## 加载、错误与生命周期

| 状态 | 页面行为 |
| --- | --- |
| 已有 workspace 数据 | 立即展示列表，后台刷新；选中项稳定 |
| 首次加载且无数据 | 原生 ProgressView，保留标题与关闭动作 |
| 列表为空 | 显示 No workspaces；提供刷新，明确不等同于未登录 |
| 首次加载失败 | 二级页面内显示失败与 Retry；可以返回 Settings |
| 有缓存但刷新失败 | 保留缓存列表，显示非阻塞错误和 Retry |
| 会话拉取失败 | 由切换后的会话列表显示错误；工作区选择保持一致 |
| 选中工作区在刷新结果中消失 | 按已有模型规则选择有效工作区或无选择，清理旧工作区数据；Settings 同步反映结果 |
| 会话持续输出时打开 Settings | 前台同步沿用现有机制，暂停被遮挡会话的已读判定；关闭后重新核对同步与底部条件 |
| 退出、认证失效 | 关闭 Settings 并清理其导航与敏感 UI，回到欢迎页；旧异步结果不能恢复已退出内容 |
| 应用进入后台 | 沿用现有订阅清理与取消机制；恢复后重新验证账号和 workspace，取消不显示为网络错误 |

workspace 加载状态需要独立于 session `statusNote`。新 picker 可能与启动或下拉刷新并发，因此要给 `refreshWorkspaces` 增加加载／错误表达，并用操作 generation 或共享在途请求防止旧结果覆盖新结果；在 await 前后保留取消与认证检查。

## 视觉与平台适配

- Settings 在 iPhone 使用单一 `.fraction(0.95)` 系统可用区域高度，以实际显示的约 85% 屏幕高度对齐参考图，普通与辅助字号一致；隐藏系统拖动指示器，内容手势用于滚动，不能上拉切换高度。左侧圆形 Close、居中 Settings 标题，关闭按钮点击区域至少 44 pt。分组水平边距约 16 pt、内部边距约 16 pt、组间距约 24 pt，作为普通字号初始设计值。
- 浅色页面使用 #FCFCFC、分组使用中性的 #F2F2F2、分隔线使用 #E0E0E0，对齐参考图的灰度，避免系统灰的蓝紫色偏；深色继续使用系统语义背景与分隔线。分组约 20 pt 圆角，分隔线跟随文字边缘；一级 label 采用 body，副标题采用 subheadline、secondary。不复制参考图上方过大的空白，首屏优先展示账号和 workspace。
- 玻璃主要用于系统导航和现有头像按钮外层；设置正文使用稳定的分组表面，避免文字叠在动态会话背景上。
- 使用 Dynamic Type 与语义颜色。长文本换行、值字段迁到下一行、开关不压缩正文；在深色与辅助大字号下检查对比度和可滚动性。
- iPad 使用系统居中的设置 sheet，二级页面沿用同一个导航栈并限制可读内容宽度。验证横竖屏和较窄窗口，使用窗口而非全局屏幕尺寸。
- 打开／关闭 Settings 不重建原会话，不丢同一 workspace 的草稿或阅读位置；切换工作区时按现有代际边界重置导航。

## 实现边界与文件分工

| 位置 | 第一步职责 |
| --- | --- |
| `App/RootView.swift` | 在会话重建边界之外持有 Settings 的局部呈现状态和 `.sheet`；把打开动作传给会话列表；认证结束时收起弹层；从本机偏好应用根视图主题 |
| `App/AppTheme.swift` | 外观存储值与显示名称、窗口外观映射，强调色定义以及触觉偏好 key |
| `Features/Sessions/SessionListView.swift` | 头像 Menu 改为 Button；通过小范围参数传递打开设置和会话可读状态，避免建立全局路由框架 |
| `Features/Settings/SettingsView.swift` | Settings 导航栈、账号卡片、统一二级页面入口、About 与退出确认 |
| `Features/Settings/WorkspacePickerView.swift` | 稳定 ID 列表、选中语义、独立加载／错误／重试、二级页面返回 |
| `Features/Settings/AppearanceSettingsView.swift` | 外观与强调色卡片选择、选中语义和辅助字号布局 |
| `Features/Settings/HapticsSettingsView.swift` | 本机 Haptics Feedback 开关 |
| `Features/Settings/AboutView.swift` | 版本、构建号、第三方客户端说明 |
| 共用头像组件 | 将现有私有 `AccountAvatar` 提取为可复用小视图，不扩大成通用设计系统 |
| `App/AppModel.swift` | workspace 加载状态和并发保护；复用切换、退出与缓存行为；必要时提供选择提交与异步刷新分离的窄入口 |
| 会话相关视图 | 透传 Settings 覆盖状态到现有 `isReading`，不把打开设置模拟成进入后台 |
| `Client/FixtureLodyClient.swift` | 添加隔离的多 workspace 与延迟／失败测试数据，默认 fixture 保持简单 |
| `KurageTests` / `KurageUITests` | 覆盖切换、旧结果隔离、退出和弹层交互，更新受影响的原有断言 |

继续保留 `account-menu` 作为头像入口的 accessibility identifier，并更新其 label 为 Open settings；保留 `sign-out-button`，新增 `settings-close`、`workspace-picker`、`workspace-option-<id>` 等稳定标识。退出新增确认后，受影响的欢迎页与 shell UI 用例必须同步调整。

Settings 首版不需要修改 Swift/JavaScript 消息契约。新增源文件按 `project.yml` 的目录规则纳入工程并运行 `xcodegen generate`。Theme 使用 `AppTheme` 定义持久化值，通过 `@AppStorage` 的 `appTheme` key 在稳定根视图和 Settings 共享；账户和工作区远程数据仍只通过 `AppModel` / `LodyClient` 访问。

## 实施顺序与验收

### 第一步：页面入口与 Workspace（已实施）

完成头像入口、Settings、账号摘要、Workspace picker、About、Sign out 和生命周期处理。

- Settings 开关不会重置会话列表、iPad 详情或当前草稿；工作区切换仅关闭 picker，Settings 不被 generation 重建移除。
- 切换后关闭 Settings，显示正确工作区列表，旧详情／旧更新不混入；点击当前 workspace 不触发刷新。
- 断网能继续显示已有 workspace 数据并重试；无缓存、空列表、认证失效都有明确状态。
- 退出确认、取消及重新登录正常；关闭后不残留上个账号的信息。
- 设置遮挡期间到达的新消息不被自动标记已读，关闭后恢复原有阅读判定。
- 原有 UI 测试适配新入口，并补充多 workspace、picker 关闭与 Settings 保持的回归。

### 第二步：本机偏好

已加入 Appearance（System / Day / Night、Black / Blue）与 Haptics 二级页面；List View（By Project / By Time）待实施。

- List View 沿用 `sessionListMode` 的 key 与 raw values，Settings 与右侧快捷菜单即时同步。
- 外观默认 System，通过根视图中与当前窗口关联的小型 UIKit 视图设置窗口外观，System 明确恢复 `.unspecified`；Settings、Workspace 和 About 继承外观，不通过改变视图 ID 应用主题，保留导航和草稿。强调色默认 Black；根视图 tint 固定为系统语义单色，导航、工具栏与停止按钮保持单色。Blue 用于发送按钮背景、Haptics／Notifications 开关、附件数量徽标、问题选中标记、dial 指针／中心圆点和 reasoning 条已选填充；dial 刻度和 reasoning 条未选轨道保持中性色。Blue 用户消息气泡使用实心 #006CEB 蓝底，正文与提及图标／标签为白色；Black 保留中性灰底与语义文字色。
- Haptics Feedback 默认开启，仅控制现有 Advanced 配置选择与 reasoning 拨盘的触觉；关闭不改变请求或操作结果。发送／steer 和本地首轮受理的触觉仍存在，不受当前 Haptics 开关控制。
- 本机偏好按安装持久化，重新登录保留；不宣称跨设备同步，不替代远程 Agent 配置。
- 暂不增加单独字体倍率、应用语言或缓存清理入口。字号继续跟随系统；独立 Notifications 页面及接入代码已保留，但在官方托管 Cloud 接入确认前隐藏入口并暂停 SDK 初始化，只有通知 fixture 显式启用。普通推送的接入及外部配置见 `NOTIFICATIONS.md`，缓存清理需先定义与 outbox／附件的边界。

### 第三步：Workspace 资源

按真实协议逐个接入 Machines、Agents、MCP Servers、Skills，优先只读列表与详情，再做编辑。

- Machines 需明确 online / offline / unknown 与机器版本支持；Agents 需明确所属机器和可用能力。
- MCP Servers 区分工作区目录、会话选择和实际加载状态；不把“已选择”显示成“已连接”，不在摘要中暴露凭据。
- Skills 保留项目／机器／Agent 的真实作用域；已有 composer `$` 候选不等于完整的 workspace 技能管理接口。
- 资源读取及写入显式携带 workspace 和实际资源作用域，取消及重试遵循现有桥接规则，完成后一起更新 live、fixture、能力和协议测试。
- 首页在功能完成后出现对应入口；每次新增功能按其风险选择验证，不把首次 UI 工作扩大为后台服务开发。

用量、账单、Auto-review、时区、软件更新提示另行核实。尤其不能把 Lody 的 ReviewPolicy 当成图中风险操作审批开关：本机参考实现的 ReviewPolicy 是 workspace Flock 配置，并包含机器 reviewer 配置，语义和权限必须继续核对。Kurage 的通知仍依赖尚未确认的第三方投递链路；版本号可本地展示，但更新徽标需要可靠的版本发现来源。

## 验证安排

- 模型：workspace 刷新并发、取消、错误、选当前项、跨 workspace 缓存、旧账号结果丢弃与退出清理；使用注入客户端与独立临时数据。
- UI：头像 → Settings → picker → 切换 → Settings 更新 → 关闭看到新列表；选当前项、退出取消／确认、重登、加载失败重试、iPad 遮挡期间的已读回执。
- 布局：iPhone 竖屏，iPad 横竖屏与窄窗口；浅色／深色、标准／辅助大字号、长账号与工作区名称、较多工作区、VoiceOver 和底部安全区域。
- 第一步运行相关 `KurageTests`、受影响的 SignIn / Shell UI 测试和新增 Settings UI 测试；用截图核对布局。第二步补充偏好恢复与同步检查，触觉手感用真机验证。
- 只有后续修改同步桥或消息契约时，才运行 frozen-lockfile 安装、`pnpm test`、`pnpm build` 和对应原生契约验证。
- 真实账号需验证多 workspace、断网恢复、持续输出、后台返回与跨端变动；fixture 结果与真实服务结果分开报告。

实施结果与本轮验证见 `PLAN.md` 的 Settings 与 Workspace 页面条目；真实账号回归尚未执行。

## 参考依据

- Kurage：`RootView.swift`、`SessionListView.swift`、`AppModel.swift`、`LodyClient.swift`、`LodyModels.swift`、`HTTPLodyClient.swift`、`ConversationTabsView.swift`、`ConversationView.swift` 和现有 SignIn / Shell UI 测试。
- 本机 Lody 只读参考：`/Users/spike/projects/lody/packages/components/src/components/mobile/mobile-workspace-switcher-sheet.tsx`，确认 workspace 选择器及可选能力入口的结构。
- 本机 Lody 只读参考：`packages/components/src/components/mobile/mobile-settings-layout.tsx`、`mobile-account-settings.tsx`、`mobile-general-settings.tsx`、`components/settings/review-policy-setting.tsx` 与 `atoms/review-policy.ts`；用于理解作用域和能力，未验证 Kurage 当前部署全部支持这些功能。
- Apple：[sheet(item:onDismiss:content:)](https://developer.apple.com/documentation/swiftui/view/sheet(item:ondismiss:content:))、[presentationDetents](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)) 和 [presentationSizing](https://developer.apple.com/documentation/swiftui/view/presentationsizing(_:))。原生 sheet 支持多个高度停靠点；短内容的实际高度与 iPad 适配仍需实施时检查，不假设 fitted 在所有窗口模式下都产生期望的 iPhone 高度。
