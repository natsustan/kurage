# Settings 与 Workspace 切换规划

2026-10-04。第一步已实施：头像入口、Settings、账号摘要、Workspace 选择器、About 和退出确认。第二步已加入 Theme（System / Light / Dark）；其余本机偏好与第三步 Workspace 资源仍是后续方案。

## 推荐方案

头像打开一个大尺寸 Settings sheet，Settings 自带导航栈，详情页在其中推进。Workspace 放在顶部账号卡片的第二行，点击后打开独立的短底部 sheet；选择完成后回到 Settings，更新工作区名称，关闭 Settings 后看到新工作区的会话列表。

采用参考图的圆角分组、克制的灰色背景、较宽松的行间距和底部选择器。沿用原生导航、sheet、Picker、Toggle 和确认对话框；首版先把账号与工作区入口做好，再加入本机偏好和远程资源管理。

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
│ Theme                         System ↕ │
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
- Theme 直接打开 System / Light / Dark 选择菜单，保存本机偏好并即时更新外观。Theme、About 和 Workspace 左侧使用 MingCute Cute Regular 图标。
- About Kurage 展示从 Bundle 读取的版本与构建号，并说明 Kurage 是独立的第三方 Lody 客户端。页面扩展时可加入开源许可等信息。
- Sign out 单独分组，红色文字，点击后用原生 confirmationDialog 确认，再调用已有 `model.signOut()`；不增加新的鉴权实现。
- 首版不渲染空的 Preferences 或 Workspace Resources 分组。下一阶段的已完成功能插入账号卡片之后、About 之前。

后续首页组织：

| 分组 | 入口 | 层级规则 |
| --- | --- | --- |
| Account | 账号摘要、Workspace | 最上方，作为账号与工作区上下文 |
| Preferences | Theme（已实施）、List View、Haptic Feedback | 简单选项直接 Picker / Toggle；复杂内容才推进详情页 |
| Workspace Resources | Machines、Agents、MCP Servers、Skills | 首页展示摘要，进入资源列表，再进入详情；完成协议接入后逐项出现 |
| About | About Kurage | 版本、客户端身份和许可等信息 |
| Session | Sign out | 页面底部独立操作组 |

会话内的 provider/model/reasoning 仍属于该会话下一轮输入配置；新会话的首次配置保留在创建流程。以后如增加 Agent 默认配置编辑，应作为远程配置功能单独说明作用范围。

## Workspace 底部选择器

```text
                 Drag indicator
Workspaces

[D] Demo                                  ✓
    lody.ai/demo

[S] Studio
    lody.ai/studio
```

- 从 Settings 的 Workspace 行打开，保留背后的 Settings，让用户清楚当前所在层级；最多一层子 sheet，资源详情使用 Settings 内导航。
- 行内放约 40 pt 的圆形首字母头像、主标题、副标题和尾部勾号。颜色按工作区 ID 稳定生成，勾号同时有 VoiceOver 的选中语义，避免只靠颜色。
- 副标题来自 `slug` 与 `LodyEndpoints.webOrigin`。它是工作区地址说明，不承担另一个跳转动作；slug 缺失时省略副标题，不显示内部 ID。
- 一至两个工作区时按内容高度呈现短 sheet，不固定为半屏；多个工作区或大字号时限制初始高度并允许滚动与上拉展开。高度依据实际内容与当前窗口可用区域计算，先验证 iOS 26/27 原生 detent 表现。
- 有 drag indicator，可下滑关闭；辅助功能与外接键盘也必须有可用的关闭动作。长名称和辅助字号允许自然增高，最后一项保留底部安全区域。
- 显示已有列表后再刷新，刷新期间保留选择和可用行，不先清空整页；不要因为返回列表或身体重算而重复拉取。
- 选当前项：只关闭选择器，不发 sessions 刷新，不增加 workspace generation。
- 选其它项：通过 `AppModel` 提交，确认 `selectedWorkspaceID` 已更新后关闭选择器，Settings 保持打开并显示新名称；会话界面继续按已有 generation 机制重建，详情返回未选择状态。
- 不等待 sessions 拉取结束才关闭选择器。新工作区加载失败时仍是已选中工作区，列表展示缓存或失败重试；不能误报“workspace 切换失败”或自动跳回旧工作区。
- 选择器关闭只取消它自己拥有的 workspace 列表刷新，已经提交的切换及其会话刷新由 `AppModel` 管理，避免随 sheet 销毁被取消。

参考图的 Add an account 不纳入首版：当前安全存储与 `LodyClient` 都按一个账号设计，多账号切换需要完整的凭据、缓存、outbox 和订阅隔离。创建工作区、接受邀请或成员管理也应在相应协议接通后加入，不能用灰色占位项伪装能力。

## 加载、错误与生命周期

| 状态 | 页面行为 |
| --- | --- |
| 已有 workspace 数据 | 立即展示列表，后台刷新；选中项稳定 |
| 首次加载且无数据 | 原生 ProgressView，保留标题与关闭动作 |
| 列表为空 | 显示 No workspaces；提供刷新，明确不等同于未登录 |
| 首次加载失败 | sheet 内显示失败与 Retry；Settings 可关闭 |
| 有缓存但刷新失败 | 保留缓存列表，显示非阻塞错误和 Retry |
| 会话拉取失败 | 由切换后的会话列表显示错误；工作区选择保持一致 |
| 选中工作区在刷新结果中消失 | 按已有模型规则选择有效工作区或无选择，清理旧工作区数据；Settings 同步反映结果 |
| 会话持续输出时打开 Settings | 前台同步沿用现有机制，暂停被遮挡会话的已读判定；关闭后重新核对同步与底部条件 |
| 退出、认证失效 | 关闭 Settings 及其子 sheet，清理导航与敏感 UI，回到欢迎页；旧异步结果不能恢复已退出内容 |
| 应用进入后台 | 沿用现有订阅清理与取消机制；恢复后重新验证账号和 workspace，取消不显示为网络错误 |

workspace 加载状态需要独立于 session `statusNote`。新 picker 可能与启动或下拉刷新并发，因此要给 `refreshWorkspaces` 增加加载／错误表达，并用操作 generation 或共享在途请求防止旧结果覆盖新结果；在 await 前后保留取消与认证检查。

## 视觉与平台适配

- Settings 在 iPhone 使用 `.large` sheet，左侧圆形 Close、居中 Settings 标题，关闭按钮点击区域至少 44 pt。分组水平边距约 16 pt、内部边距约 16 pt、组间距约 24 pt，作为普通字号初始设计值。
- 浅色页面使用 #FCFCFC、分组使用中性的 #F2F2F2、分隔线使用 #E0E0E0，对齐参考图的灰度，避免系统灰的蓝紫色偏；深色继续使用系统语义背景与分隔线。分组约 20 pt 圆角，分隔线跟随文字边缘；一级 label 采用 body，副标题采用 subheadline、secondary。不复制参考图上方过大的空白，首屏优先展示账号和 workspace。
- 玻璃主要用于系统导航和现有头像按钮外层；设置正文使用稳定的分组表面，避免文字叠在动态会话背景上。
- 使用 Dynamic Type 与语义颜色。长文本换行、值字段迁到下一行、开关不压缩正文；在深色与辅助大字号下检查对比度和可滚动性。
- iPad 使用系统居中的设置 sheet，限制可读内容宽度；选择器继续在设置之上呈现，由当前窗口尺寸决定高度。验证横竖屏和较窄窗口，使用窗口而非全局屏幕尺寸。
- 打开／关闭 Settings 不重建原会话，不丢同一 workspace 的草稿或阅读位置；切换工作区时按现有代际边界重置导航。

## 实现边界与文件分工

| 位置 | 第一步职责 |
| --- | --- |
| `App/RootView.swift` | 在会话重建边界之外持有 Settings 的局部呈现状态和 `.sheet`；把打开动作传给会话列表；认证结束时收起弹层；从本机偏好应用根视图主题 |
| `App/AppTheme.swift` | System / Light / Dark 的持久化值、显示名称、窗口外观映射与应用，统一 `appTheme` key |
| `Features/Sessions/SessionListView.swift` | 头像 Menu 改为 Button；通过小范围参数传递打开设置和会话可读状态，避免建立全局路由框架 |
| `Features/Settings/SettingsView.swift` | Settings 导航栈、账号卡片、Workspace 入口、Theme 选择、About 与退出确认；局部状态管理 workspace 子 sheet |
| `Features/Settings/WorkspacePickerView.swift` | 稳定 ID 列表、选中语义、独立加载／错误／重试、短 sheet 高度与关闭 |
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

已加入 Theme（System / Light / Dark）独立卡片；List View（By Project / By Time）与 Haptic Feedback 待实施。

- List View 沿用 `sessionListMode` 的 key 与 raw values，Settings 与右侧快捷菜单即时同步。
- Theme 默认 System，通过根视图中与当前窗口关联的小型 UIKit 视图设置窗口外观，System 明确恢复 `.unspecified`；Settings、Workspace picker 和 About 继承外观，不通过改变视图 ID 应用主题，保留导航和草稿。Theme 行空间不足时上下排列标题和选项。Theme、About 与 Workspace 行使用 MingCute Cute Regular 的 palette、information 与 briefcase 模板矢量图标。
- Haptic Feedback 默认开启，统一控制已有发送／steer、本地首轮受理、配置选择与 reasoning 拨盘的触觉；关闭不改变请求或操作结果。
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
