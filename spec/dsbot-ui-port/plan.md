# Implementation Plan: DS Bot HarmonyOS UI 层全量移植

**Input**: Feature specification from `spec/dsbot-ui-port/spec.md`

## Summary

把 RN 版 DS Bot 手机应用的完整 UI 层移植到 HarmonyOS ArkUI：接通已完成的业务层（`common/`）、平台层（`platform/Platform.ets`）与应用状态层（`appstate/AppStore.ets`），实现配对、抽屉导航、聊天、等你处理、Bot/群管理、记忆/日程/文件夹/用量、旁聊、Bot 浏览器与设置全套屏幕；同时修复存量约 85 处 ArkTS 编译错误，使 `devecocli build` 通过。技术路线：沿用现有工程架构，新建唯一 `@Entry` 导航宿主 `pages/Index.ets`，以 `Navigation + NavPathStack + 系统路由表` 承载全部屏幕；屏幕全部为 `@ComponentV2`，直接消费 AppStore（State Management V2）与 TeamLink RPC，不重复实现业务状态。

## Technical Context

**Language/Version**: ArkTS（ArkUI 声明式范式），HarmonyOS SDK 26.0.0（按工程现状）
**Primary Dependencies**: `@ohos/hvigor-ohos-plugin` 6.26.8（构建链已修复）；`@kit` 各系统能力由 common/platform 现有代码使用；不新增三方依赖
**State Management**: State Management V2（`@ObservedV2`/`@Trace`/`@ComponentV2`/`@Local`）——沿用项目现有 V2 体系（AppStore），禁止 V1/V2 混用
**Storage**: 现有 store-core（Preferences/Asset，经 Platform 门面）；本特性不新增持久化
**Testing**: `arkts_check` 静态检查 + `devecocli build` 构建验证；UI 验证范围由 Phase 3 验证选项门决定
**Target Platform**: HarmonyOS 手机（phone）为主、平板（tablet）兼容；深浅色主题；zh/en 双语
**Project Type**: 移动应用（HAP，entry 模块）
**Performance Goals**: 聊天列表 LazyForEach 按需渲染、滑动流畅；启动直进上次聊天；浏览器帧 2 秒/帧轮询不阻塞 UI 线程
**Constraints**: 聊天/团队数据全部在电脑端，手机不落库；卡片内容按固定格式渲染，深度与大小有上限，不执行脚本、不访问网络
**Scale/Scope**: ~20 个屏幕（镜像 RN），11 个用户故事；存量修复约 85 处编译错误

## Project Structure

### Documentation (this feature)

```text
spec/dsbot-ui-port/
├── spec.md              # Phase 1 规格（已完成）
├── plan.md              # 本文件
└── tasks.md             # Phase 3 任务清单
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── entryability/EntryAbility.ets          # [修复] Ability 常量/深链等编译错误
├── appstate/AppStore.ets                  # [修复] any/unknown、解构声明、导出缺失
├── platform/Platform.ets                  # [修复] util/userAuth/asset/webSocket API 误用
├── common/link/*.ts                       # [修复] noise/secure-transport/rpc-client/keys 等接口不匹配
├── common/team/*.ts                       # [修复] team-link/chat-state/store-core 等
├── common/demo/*.ts                       # [修复] .ets 扩展导入等
├── common/ui/*                            # 沿用：i18n 词典（zh）、characters、tokens、phrases
├── common/markdown/markdown.ts            # 沿用：markdown 解析
├── common/deepview/{views-core,formula}.ts # 沿用：deep view 解析与公式
├── pages/Index.ets                        # [新建] 唯一 @Entry 导航宿主（配对页 ↔ 主壳切换 + 全局覆盖层）
├── screens/                               # [新建] 屏幕级组件（@ComponentV2，NavDestination 为根）
│   ├── Pair.ets                           # 配对（指引/扫码/粘贴链接/错误反馈）
│   ├── TeamList.ets                       # 抽屉内容（搜索/新建菜单/团队列表/等你处理/设置入口）
│   ├── Chat.ets                           # 聊天基座（消息列表 + 输入区 + 停止）
│   ├── chat/
│   │   ├── MessageList.ets                # 消息列表（LazyForEach、上滑分页）
│   │   ├── ChatRows.ets                   # 事件行/步骤行/轮次分隔/图片消息行
│   │   ├── ChatCards.ets                  # 提问/批准/密钥/浏览器交接卡
│   │   ├── MarkdownText.ets               # markdown 气泡（粗体/列表/代码块/表格/公式）
│   │   ├── DeepView.ets                   # deep view 固定格式渲染（深度/大小上限）
│   │   └── ChatInput.ets                  # 输入区（文本/照片/乐观发送/失败重试/停止）
│   ├── NeedsYou.ets                       # 等你处理面板（分类聚合/就地作答/跳转）
│   ├── BotDetails.ets                     # Bot 详情（模型/权限/文件夹/记忆/用量/日程/浏览器）
│   ├── BotEdit.ets                        # Bot 编辑（资料/形象/照片/指令/隐私/能力/删除）
│   ├── GroupDetails.ets                   # 群详情（成员/公告/谁来回答）
│   ├── GroupSettings.ets                  # 群设置（成员勾选/管理员/公告/删除）
│   ├── NewChat.ets                        # 新建 Bot / 新建群聊（Sheet 形式）
│   ├── ModelMenu.ets                      # 模型菜单/模型选择器
│   ├── Memory.ets                         # 记忆（列表/问记忆/添加/编辑/移除）
│   ├── Schedules.ets                      # 日程（频率中文描述/新建/删除）
│   ├── Folder.ets                         # 文件夹选择（层级导航/路径输入/团队工作区）
│   ├── Usage.ets                          # 用量（日/周/月 Tokens 与运行次数）
│   ├── Side.ets                           # 旁聊（正在回答/取消/历史旁问）
│   ├── BotBrowser.ets                     # Bot 浏览器（截图轮询/接管/交还/停止）
│   ├── Settings.ets                       # 设置面板（入口列表 + Done 关闭）
│   └── SettingsPages.ets                  # 设置子页（外观/语言/电脑/密钥/服务商/连接器/能力/团队用量/位置/更新诊断/关于）
├── components/                            # [新建] 可复用通用 UI 组件
│   ├── Sheet.ets                          # Sheet/SheetHeader 封装 + confirmDanger「再点一次」
│   ├── Marks.ets                          # Avatar/RoomAvatar（shape/color/照片/主 Bot 标识）
│   ├── FormControls.ets                   # BackRow/Section/Row/Field/SwitchRow/Segmented/DangerRow/PickGrid
│   ├── Theme.ets                          # 主题 token（调色板/排版/圆角，对齐 tokens.ts + ThemeState）
│   └── Banner.ets                         # 顶部通知横幅（提问/批准提醒，可关闭，点击跳转）
entry/src/main/resources/base/profile/
├── main_pages.json                        # [已有] 注册 pages/Index
└── router_map.json                        # [新建] 系统路由表（全部 NavDestination 屏幕注册）
```

**Structure Decision**: 本计划**沿用现有工程架构**（existing project，不引入 MVVM 迁移）：业务/平台/状态层维持 `common/`、`platform/`、`appstate/` 现状；UI 落在工程预留的 `pages/`（唯一 `@Entry`）、`screens/`（屏幕级组件）、`components/`（可复用 UI）三个目录。屏幕数量由 11 个用户故事与 RN 对齐基准决定（~20 屏）：screens/ 按屏幕一文件，仅聊天渲染按子组件拆分以控制单文件复杂度；不新建 viewmodel/model/service/data 层——AppStore 与 TeamLink 已承担状态编排与数据职责，UI 直接消费（FR-013），避免重复业务状态。资源一律置于 `entry/src/main/resources/` 下。

## Complexity Tracking

无 Constitution 违规。文件数多于新工程 Light 档，原因：本特性为存量工程的全量 UI 移植（11 个用户故事、~20 屏），且沿用既有架构分层而非新建分层。

## Research & Decisions

1. **导航架构**
   - **Decision**: 唯一 `@Entry`（`pages/Index.ets`）作导航宿主：外层按「未配对 → Pair / 已配对 → 主壳」切换；主壳 = `Navigation`(Stack) + `NavPathStack` + 系统路由表 `router_map.json`，Home 内容为聊天基座，详情/表单类屏幕以参数化 push 进入 `NavDestination`；深链配对以全局覆盖层形式在任何屏幕之上拉起。
   - **Rationale**: 符合单 `@Entry` 与系统路由表规范；获得系统转场与返回键处理；参数化 push 支持动态屏幕（打开某个 Bot 的聊天）。App 记住上次的聊天（`dsbot.lastChat` 语义），启动直接进入。
   - **Alternatives considered**: 页内自维护屏幕栈（放弃：丢失系统转场与返回处理）；多 `@Entry` + router（放弃：违反 page-entry-count 单入口规范）。

2. **抽屉实现**
   - **Decision**: 主壳内以 `Stack` + 侧滑面板 + 手势/动画实现抽屉，抽屉内容为 `TeamList` 组件；不使用 Navigation 的 Drawer 模式。
   - **Rationale**: 手机单栏形态与 RN 版 drawer 交互对齐（左滑出、遮罩点击关闭）；Drawer 模式面向平板双栏，不适配「聊天为基座」布局。
   - **Alternatives considered**: Navigation Drawer 模式（放弃：形态不符）。

3. **Bot 浏览器画面**（解决 spec 开放问题 1，依据 RN `manage.tsx` BotBrowser 实现）
   - **Decision**: 沿用现有 RPC 通道轮询截图：`browser-frame`（页面可见时每 2 秒一帧）返回 `{mime, data(base64), url?, title?}`，base64 解码为 PixelMap 渲染；操作走 `browser-takeover` / `browser-give-back`（持锁来自 call 时带 outcome=done|skip + callId）/ `browser-stop`；持锁状态读 `TeamState.browserHolds[botId]`；`bot/not-found` 显示「这个 Bot 没有打开的浏览器」。
   - **Rationale**: 与 RN 版完全一致，无需新增传输通道；2 秒截图流满足「看画面 + 决策接管」而非实时操控的用途。
   - **Alternatives considered**: WebRTC/实时视频流（放弃：RN 版未实现，超出本次范围）。

4. **状态管理**
   - **Decision**: 全部屏幕 `@ComponentV2`，消费 AppStore（`@ObservedV2`/`@Trace`）；屏幕局部状态用 `@Local`；不使用任何 V1 装饰器。
   - **Rationale**: 沿用现有 V2 体系（FR-013），规避 V1/V2 混用这一最大错误类。
   - **Alternatives considered**: V1 `@Component`（放弃：与 AppStore 的 V2 观察模型不兼容）。

5. **聊天渲染**
   - **Decision**: 消息列表 `List` + `LazyForEach` 按需渲染，上滑分页加载更早消息；markdown/deep view 由 `common/markdown`、`common/deepview` 解析，UI 侧建 `MarkdownText`/`DeepView` 渲染组件按固定格式渲染并施加深度与大小上限；公式经 `formula.ts`。
   - **Rationale**: 复用现有解析器；不可信内容只做固定格式渲染（Edge Case 约束：不执行脚本、不访问网络）。
   - **Alternatives considered**: RichText/Web 组件渲染（放弃：不可信内容安全性不足）。

6. **存量编译错误修复策略**
   - **Decision**: 原地修复，不重设计业务 API。错误类别与目标文件：① AppStore.ets——any/unknown、`SavedComputer|undefined` vs null、解构声明、缺失 `setSystemIsZh` 导出；② demo/demo-link.ts——`.ets` 扩展导入；③ Platform.ets——util.createRandom/userAuth/asset/webSocket 等 API 误用（含已自动修复的 `AuthTrustLevel`）；④ EntryAbility.ets——不存在的 AbilityConstantLauncher；⑤ noise.ts——缺失 NoiseIkSessionOptions；⑥ secure-transport.ts——NoiseIkSession 接口不匹配；⑦ team-link.ts——HandshakeHello 不匹配、RpcClient 类型误作值；⑧ main_pages.json 注册的 pages/Index 本次新建补齐。
   - **Rationale**: FR-012；业务层是事实来源，只修不重构。
   - **Alternatives considered**: 重写业务层（放弃：违背 spec 假设与 FR-013）。

7. **i18n 与主题**
   - **Decision**: 全部用户可见文案经 `common/ui/i18n.ts` 的 t()（zh 词典已有，en 以键回退）；主题 token 对齐 `tokens.ts` + AppStore ThemeState（深浅色 + 团队强调色），`components/Theme.ets` 集中暴露颜色/圆角/排版常量供全部屏幕消费。
   - **Rationale**: SC-004 要求无硬编码文案、切换即时生效。
   - **Alternatives considered**: 各屏幕自带样式常量（放弃：主题切换无法全局生效）。

8. **模态与危险确认**
   - **Decision**: 表单类屏幕（新建 Bot/群、记忆编辑器）用 bindSheet/自定义覆盖层；危险操作统一 `confirmDanger`「再点一次」交互（components/Sheet.ets 提供）。
   - **Rationale**: 镜像 RN 的 Sheet/confirmDanger 交互（US-5、US-10 验收）。
   - **Alternatives considered**: 系统弹窗确认（放弃：与 RN 交互不一致）。

9. **配对深链**
   - **Decision**: EntryAbility onCreate/onNewWant 现有逻辑解析 `dsbot://pair` 并写入全局状态，宿主监听后在任何屏幕拉起配对流程覆盖层；取消回到原界面。
   - **Rationale**: US-1 验收 4（冷启动与热启动均覆盖）。
   - **Alternatives considered**: 仅配对页响应深链（放弃：不满足验收）。

10. **高权限解锁**
    - **Decision**: 密钥、服务商 key、连接器、能力、更新等高权限操作先经 Platform 生物识别门面（userAuth）解锁；`unlock/canceled` 静默不发；设备未设屏幕锁时提示「请先给这台手机设一个屏幕锁」。
    - **Rationale**: FR-010；Platform 已有 userAuth 绑定（修复误用后可用）。
    - **Alternatives considered**: 无解锁直通（放弃：违反 FR-010）。

## Data Model

沿用现有实体（本特性不新建持久化模型，只新增 UI 层视图模型）：

- **SavedComputer / PhoneIdentity**（store-core）：已配对电脑（主机设备 ID、名称、密钥）与本机身份。
- **TeamState**（types.ts，@ObservedV2）：bots、rooms、questions、views、secretRequests、connectors、capabilities、work/waiting、prefs、secrets、models、permissions、browserHolds、capabilityStatuses 等，按 revision 驱动同步。
- **Bot / Room**：成员（avatar{shape,image}、color、role、instructions、private、workDir、permission、capabilities、model）与群聊（members、admin、mode、notice、name/named）。
- **ChatItem**（chat-state.ts）：14 种 kind（bot/user/event/answer/view/divider/steps/closed/post/relay 等），乐观发送态 local/localImages、outbox 队列。
- **Question / Approval / SecretRequest / 浏览器交接卡**：「等你处理」的三类待办 + 浏览器交接。
- **Prefs**（AppStore）：theme、banners、lang，跨页即时生效。

新增 UI 层视图模型（screens 内部，非持久化）：

- **导航参数**：ChatParams{kind:'bot'|'room', id}、BotDetailsParams{botId}、GroupParams{roomId}、MemoryParams{id, name, group}、SchedulesParams{botId, name, sessionId}、UsageParams{botId, name, sessionId}、FolderParams{current, onPick, botId}、BrowserFrame{mime, data, url?, title?}。
- **屏幕局部草稿态**：表单草稿（新建/编辑/记忆编辑器）、抽屉开关与搜索关键字、横幅队列、危险确认待触发操作。

## Contracts & Interfaces

1. **AppStore（现有，修复后）**：attach(link: TeamLink|DemoLink)、computers、identity、prefs、theme、聊天会话访问、`setSystemIsZh` 导出。屏幕只读消费状态，写操作经其或 TeamLink 发起；UI 不直接触碰 link 层内部。
2. **TeamLink.call(name, body) → Promise\<value\>**（现有 RPC 契约，UI 调用端点对齐 RN）：send、update-bot、create-bot、duplicate-bot、delete-bot、set-main、bot-capability、create-room、update-room、delete-room、memory-view/add/edit/forget/ask、schedules、run-stats、browser-frame/takeover/give-back/stop、密钥/服务商/连接器/能力/诊断等 settings 端点。错误处理约定：`unlock/canceled` 静默返回，其余向屏幕展示 message（i18n 映射）。
3. **Platform 门面（现有，修复后）**：scanCode、photo pick + 压缩（长边 2048）、clipboard copy/paste、haptics（send 成功/danger 危险操作）、biometric unlock（含未设锁指引）、相册保存、深链参数读取。
4. **组件契约**：screens/* 各屏幕以 `NavDestination` 为根，从 `NavDestinationContext` 取 pathStack 与 param；components/* 为纯 UI（不发起业务调用）；`confirmDanger(label, confirmText, action)` 为统一二次确认入口；Banner 点击回调跳转对应聊天。
5. **路由表**：`router_map.json` 注册全部 NavDestination 屏幕（name → buildMethod → pageSourceFile），`module.json5` 引用；Pair 不入栈，由宿主条件渲染/覆盖层呈现。
