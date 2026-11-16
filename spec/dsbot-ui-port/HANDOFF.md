# DS Bot HarmonyOS 移植 — 执行交接文档

> **✅ 已全部完成（2026-11-15）**：批次 2–5 与 Phase 5 验证全部通过，tasks.md T001–T047 共 47 项全部勾选。
> 构建产物 `entry/build/default/outputs/default/entry-default-signed.hap` 已在模拟器（Mate 90 Pro）安装启动，devecocli run Smoke: PASS。
> 构建命令实际为 `DEVECO_CLI_STUDIO_PATH="C:\Users\13775\AppData\Local\Programs\DevEco Studio" /c/Users/13775/.cache/deveco/bin/devecocli.cmd check arkts --fix` / `... build` / `... run --skip-build`。
> 以下章节保留为实施记录。

## 1. 项目与环境

- **项目根**：`E:\DSHBot\DSHBot-Harmony`（HarmonyOS ArkTS，可构建）
- **原项目（移植保真基准）**：https://github.com/Fei2411/DS-Bot 的 `mobile/`（Expo/React Native 安卓/iOS App）
- **本地参照克隆（已就绪，直接用）**：
  - `C:\Users\13775\AppData\Local\Temp\deveco\dsbot-ref\mobile\` — 原移动端全部源码（sparse checkout）
  - `C:\Users\13775\AppData\Local\Temp\deveco\dsbot-ref\ds-bot\src\client\` — 桌面端权威表（characters.js / i18n.js / themes.js / inks.js 等）
  - 若该临时目录被清空：`git clone --depth 1 --filter=blob:none --sparse https://github.com/Fei2411/DS-Bot.git` 后 `git sparse-checkout set mobile ds-bot/src/client`
- **规格文档**：`spec/dsbot-ui-port/`（spec.md / plan.md / tasks.md，任务 T001–T047）
- **常用命令**（在项目根执行）：
  - 静态检查：`devecocli check arkts --fix`
  - 构建：`devecocli build`
  - 部署运行：`devecocli run --skip-build`（有设备时）
- **写 .ets 前必加载 skill**：`hmos-arkui-develop-skill`

## 2. 当前进度

### 已完成（构建通过，BUILD SUCCESSFUL）

- **T001–T024**（详见 tasks.md，均已勾选）：存量修复、link 协议栈（Noise IK/ChaCha20/X25519 手写实现）、AppStore、通用组件（Theme/Sheet/Marks/Icon/FormControls/Banner）、Pair 配对屏、TeamList 抽屉、导航宿主 Index.ets、聊天子组件（MarkdownText/DeepView/ChatRows/ChatCards/MessageList/ChatInput）。
- **T025**：`screens/Chat.ets` 已创建并嵌入 `pages/Index.ets` 的 chatBase（轮询/分页缓存/流式气泡/Dock/横幅联动/markSeen/停止按钮/长按复制已接线）。
- **对照审计发现的 12 项缺陷已修复并逐一验证**：
  1. ✅ DeepView 实时 inputs 随答案回传（`screens/chat/DeepView.ets`，对照 REF `chat/view.tsx:40-41`）
  2. ✅ 前台探测接线（`EntryAbility.ets` onForeground/onBackground → `appStore.link.onForeground/onBackground`）
  3. ✅ 主题响应式（`AppStore.ets`：controller.onChange → applyTheme，218/227 行）
  4. ✅ 调用错误本地化（`team-link.ts` errorText 过 t()，280/334/399 行）
  5. ✅ 热深链不残留 pendingLink（`platform-hooks.ts:34-42`：有 handler 直接投递并 return，不写 pending 槽）
  6. ✅ `computers.adding` 接线（`Index.ets:139/147/159` 置位/复位，配对覆盖层期间停链）
  7. ❌ **未做**：`common/ui/i18n-zh-desktop.ts` 补 `'Writing a file'` 中文词条（权威译文查 `ds-bot/src/client/i18n.js` 同名 key）→ **并入批次 2**
  8. ❌ **未做**：`common/ui/characters-table.ts` 补 `'berry'` 形状（路径数据从 `ds-bot/src/client/characters.js` 的 berry 移植：body/paints/shade/light/eyes）；`PICKER_SHAPES` 改为 REF `manage.tsx:24` 的 10 形状 `['acorn','berry','bunny','gem','gumdrop','kitty','moon','peanut','star','wave']`（whale 留给主 Bot 不进选择器）→ **并入批次 2**
  9. ✅ SHADOW_COLORS 修正（`Theme.ets:23`：`[0, 0x47000000, 0x59000000, 0x66000000, 0x80000000]`）
  10. ✅ via 标签 imPlatform 映射（`ChatRows.ets:564` `imPlatformName`）
  11. ✅ workPhrase `(said || note)` 语义（`phrases.ts:26`）
  12. ✅ TeamList 搜索 autoFocus（`defaultFocus(true)`，185 行）+ 磁贴/行按压反馈（tilePressed/pressed）

### 未完成（本文档剩余部分即执行计划）

- **批次 2**：T026–T030（NeedsYou / ModelMenu / BotDetails / BotEdit / NewChat）+ 遗留修复 7/8
- **批次 3**：T031–T036（GroupDetails / GroupSettings / Memory / Schedules / Folder / Usage）
- **批次 4**：T037–T040（Side / BotBrowser / Settings / SettingsPages）
- **批次 5**：T041–T045（Polish）
- **Phase 5 验证**：T046 构建 + T047 部署（build-only 范围）

## 3. 架构与硬约束（每批都必须遵守）

### 路由机制（关键）

- 唯一 `@Entry`：`pages/Index.ets`（Navigation + NavPathStack），**不得新增 @Entry**。
- `module.json5` 已声明 `"routerMap": "$profile:router_map"` → **只允许系统路由表**，禁止挂 `.navDestination()` builder。
- 每个目的地页面文件：导出 `@Builder export function XxxBuilder()`；`build()` 根节点必须是 `NavDestination`。
- 路由表 `entry/src/main/resources/base/profile/router_map.json` 每条：
  ```json
  { "name": "路由名", "buildMethod": "XxxBuilder", "pageSourceFile": "src/main/ets/screens/Xxx.ets" }
  ```
  **当前为空** `{"routerMap": []}`，各批次创建屏幕时同步注册本批路由。
- 取栈/参数：`NavDestination().onReady((ctx: NavDestinationContext) => { this.navPathStack = ctx.pathStack; })`，参数 `ctx.pathInfo.param`（先归一化校验类型，禁止对未知结构裸 `as`）。
- Index.ets / TeamList.ets / Chat.ets 中已在 push 的路由名（以代码实际为准）：`needs`、`botDetails`、`botEdit`、`newBot`、`newGroup`、`side`、`settings`、`groupDetails`。

### ArkTS 规则（高频雷区）

- 无 `any`/`unknown` 注解、无解构声明、对象字面量必须 typed、`Record<K,V>` 替代索引签名。
- 状态体系统一 V2：`@ComponentV2` + `@Local/@Param/@Event/@Monitor/@Computed`，类状态用 `@ObservedV2`+`@Trace`；**禁止混用 V1 装饰器**（@State/@Prop 等）。
- `build()` 内只放 UI 组件语法；if/switch/三元放 Builder 外或用条件渲染；不得在 build 内声明局部变量。
- 生命周期钩子（aboutToAppear 等）不得 `private`。
- `@Require @Event` 组合在 `@ComponentV2` 中非法（DeepView 曾因此报错，改用带默认值的 `@Event`）。
- 错误文案一律过 `t()`（i18n）；RPC 经 `AppStore.link`（team-link）通道。

### 现有可复用资产

- **组件**（`components/`）：`FormControls.ets`（FormRow/FormField/SwitchRow/Segmented/FormSection/SectionDivider/BackRow/DangerRow/PickGrid）、`Sheet.ets`（SheetView/SheetHeader/ConfirmDanger 内联二次确认）、`Marks.ets`（Avatar/RoomAvatar）、`Icon.ets`（17 图标）、`Theme.ets`（shadowOf/type/palette）、`Banner.ets`（NoticeBanner 渲染，门控逻辑在宿主）。
- **状态**：`appstate/AppStore.ets`（appStore 单例：link/computers/prefs/theme/currentChat/openChat/restoreChat/applyTheme）。
- **团队协议**：`common/team/`（team-link call/callBot、state-utils、optimistic、chat-state、store-core、types）。
- **i18n**：`common/ui/i18n.ts`（t()）、`i18n-zh-desktop.ts`（桌面词典）、`phrases.ts`。
- **字符表**：`common/ui/characters.ts` + `characters-table.ts`（形状/颜色/绘制）。

## 4. 批次 2：T026–T030 + 遗留修复（下一步执行）

参照：`mobile/src/screens/NeedsYou.tsx`、`manage.tsx`（BotDetails/BotEdit/NewBot 都在此文件）、`model-menu.tsx`。

### 遗留修复（先做）

- **A**：`i18n-zh-desktop.ts` 补 `'Writing a file'` 词条（译文查 `ds-bot/src/client/i18n.js`）。
- **B**：`characters-table.ts` 补 `berry` 形状 + `PICKER_SHAPES` 改 10 形状集合（见上文第 2 节第 8 条）。

### T026 NeedsYou 屏（`screens/NeedsYou.ets`，路由 `needs`）

对照 REF NeedsYou.tsx：
- 分组列表：Questions(?)、Approvals(!)、Secret requests、Browser handoffs、Cards(views)，空组隐藏
- 每行：头像（Bot/房间）+ 名称 + 单行摘要；点击跳对应聊天（有 roomId → room，否则 bot；`appStore.openChat` + pathStack.pop）
- 分组头徽标 + 标题；空态 "Nothing needs you"（过 t()）

### T027 ModelMenu 组件（`screens/ModelMenu.ets`，组件非路由页）

对照 REF model-menu.tsx：
- groupModels 按 provider 分组；modelOf（bot.model 优先，否则 appliedModel）
- efforts 接口缓存；EffortBar 滑杆选思考档位（有 defaultEffort 不加 Default 档，否则补），当前档名 + 重置按钮
- ModelMenu 触发按钮（模型名 + provider · 档位）→ 底部弹层（ModelGroups 打勾/Default 标记 + EffortBar + "Models and providers…" 行）；ModelPicker（无 Bot 时用）
- 选择调 `update-bot {model}` / `{effort}`

### T028 BotDetails 屏（`screens/BotDetails.ets`，路由 `botDetails`，param `{botId: string}`）

对照 REF manage.tsx BotDetails：
- 返回 + 齿轮进 BotEdit（push `botEdit`）；中央大头像（Main Bot 星标）+ 名称 + 角色标签
- Tabs：Details / Browser（Browser 仅做跳 `botBrowser` 的按钮占位，该路由批次 4 注册；或本批隐藏 tab 留注释）
- ModelMenu 接入 + "Manage" 行（push `settings`）
- 权限 PermissionPicker 分段（read-only / workspace / danger-full-access），即选即存 update-bot
- 工作目录行（点击 push `folder`）；指令前 5 行；Memory 摘要行（memory-view 条目数，push `memory`）；Usage 摘要行（run-stats，push `usage`）；Schedules 摘要行（最多 3 条）
- Duplicate（duplicate-bot 后打开新 Bot 聊天）、发消息

### T029 BotEdit 屏（`screens/BotEdit.ets`，路由 `botEdit`，param `{botId: string}`）

对照 REF manage.tsx BotEdit：
- 名称/标签即时保存；形状网格（10 形状含 berry）+ 颜色 12 色网格 + 实时预览 Avatar
- 照片：相册选（1:1 裁剪 base64）/移除
- ModelMenu 内嵌；Instructions 多行
- Private 开关；非私有才有 Main Bot 开关（set-main）
- Capabilities 开关列表（bot-capability attach/detach）
- Duplicate；DangerRow 删除（ConfirmDanger，delete-bot 后回聊天列表）

### T030 新建屏（`screens/NewChat.ets`，两条路由）

- `newBot`（Sheet 弹层）：SheetHeader 取消/创建（重名或忙时禁用）、实时预览、名称输入（重名 "Another Bot has this name."）、形状/颜色网格、ModelPicker；create-bot 成功后等 team.bots 出现该 Bot（useOpenWhenListed 语义）自动打开聊天
- `newGroup`（Sheet 弹层）：取消/创建（需 admin + ≥2 成员）、单列勾选成员、首个选中默认 lead 可换（Make admin）、Admin 徽标；create-room 成功自动打开群聊

### 批次 2 验收

- 本批注册路由：`needs`、`botDetails`、`botEdit`、`newBot`、`newGroup`（后续批次的路由名不要注册）
- `devecocli check arkts --fix` 至 0 错误；`devecocli build` 至 BUILD SUCCESSFUL
- 勾选 tasks.md 中 T026–T030

## 5. 批次 3：T031–T036

参照：`mobile/src/screens/manage.tsx`（GroupDetails/GroupSettings/Memory/Schedules/Folder/Usage 都在此文件）。

| 任务 | 文件/路由 | param | 要点 |
|---|---|---|---|
| T031 GroupDetails | `screens/GroupDetails.ets`，路由 `groupDetails` | `{roomId: string}` | 返回+齿轮进 GroupSettings；RoomAvatar+群名+"N members · Admin X"；公告；成员列表（Admin 徽标，点击进 BotDetails）；Who answers 显示；Memory 入口（group=true） |
| T032 GroupSettings | `screens/GroupSettings.ets`，路由 `groupSettings` | `{roomId: string}` | 名称/公告（共享指令）；Who answers Segmented（admin/everyone）；成员勾选增删、设/撤 Admin；DangerRow Delete group（delete-room 后回列表） |
| T033 Memory | `screens/Memory.ets`，路由 `memory` | `{botId?: string, roomId?: string}` | memorySummaryText 摘要 + 询问框（memory-ask，显示回答）；条目列表（主题/正文/时间/来源），点击编辑弹层，× 删除（memory-forget 确认）；Add 新增（Topic/Text，memory-add/memory-edit）；空态 "Nothing saved yet" |
| T034 Schedules | `screens/Schedules.ets`，路由 `schedules` | `{botId: string}` | 任务列表（标题+whenText 人性化描述：一次/每天/每周几/每 N 分钟/cron），× 删除；新建（标题/Prompt/When 分段：Once 日期+时间 / Every day / Every week 星期按钮组 / Repeat 数量+单位）；schedule-create/delete |
| T035 Folder | `screens/Folder.ets`，路由 `folder` | `{pick: 'bot'|'team'|'room', botId?, roomId?}` | 最近文件夹区（folders 列表）；folder-list 逐级浏览 + Up one level；"Use this folder" 按 pick 目标写 update-bot workDir / team-workspace / update-room workDir |
| T036 Usage | `screens/Usage.ets`，路由 `usage` | `{botId?: string}` | Day/Week/Month token 合计（usage-summary，input+cacheRead+cacheWrite+output）；各模型合计；Runs 区（Turns/Steps/Context used，run-stats） |

验收：注册 `groupDetails`、`groupSettings`、`memory`、`schedules`、`folder`、`usage`；arkts 0 错误；构建通过；勾选 T031–T036。

## 6. 批次 4：T037–T040

参照：`mobile/src/screens/side.tsx`、`manage.tsx`（BotBrowser）、`Settings.tsx`、`settings-pages.tsx`。

| 任务 | 文件/路由 | 要点 |
|---|---|---|
| T037 Side 旁聊 | `screens/Side.ets`，路由 `side`，param `{botId, sessionId}` | 头部 Bot 头像+名+"Side chat"+×（side-close）；历史侧聊卡片列表（最后一问为标题+"N questions"），空态 "Ask about the work so far"；会话态问答气泡（回答 Markdown 渲染）；answering 显示 "Answering…"+Cancel（side-cancel）；首次发送先 side-new 建 chatId 再 side-ask（recent:true）；流式期间每 1.5s 轮询 state（since:-1）；底部说明 "Answered from progress so far; nothing was run" |
| T038 BotBrowser | `screens/BotBrowser.ets`，路由 `botBrowser`，param `{botId: string}` | 每 2 秒轮询 browser-frame（仅聚焦时），base64 解码 PixelMap 等比渲染（aspectRatio 0.62）；页面标题+URL；bot/not-found → "This Bot has no open browser"；browserHolds hold 备注；操作：hold 有 callId → Done/Skip（browser-give-back outcome done/skip）；hold.by==='user' → Give back；否则 Take over（browser-takeover）；任何时候 Stop（browser-stop）；team.browser===false 时隐藏操作组；操作后立即刷帧 |
| T039 Settings 面板 | `screens/Settings.ets`，路由 `settings` | Phone 区：Computers 行（当前电脑名）、Appearance 三段（System/Light/Dark，写 prefs.theme 并 applyTheme）、Language 三段（跟随系统/简体中文/English，立即 setLang）、In-app banners 开关（prefs.banners）；Team 区入口列表：Models→Providers、Connectors、Capabilities、Usage→TeamUsage、Secrets、Location、Updates & diagnostics、About DS Bot |
| T040 设置子页 | `screens/SettingsPages.ets`，按需拆分文件，子路由各自注册 | Providers（列表/密钥状态/添加 known 或 custom + Find models/移除）；Connectors（状态/Connect token/Disconnect/Try again）；Capabilities（状态/Approve/Delete/新增 MCP stdio 或 streamable-http/Skill/Pack）；TeamUsage（Tokens in/out，按 owner/model 汇总）；Computers（在线状态/Switch/Forget 二次确认/Add a computer 触发配对）；Secrets（列表/新增/删除，secret-set/delete）；Location（Team workspace→Folder pick 'team'；dataPath 只读）；Updates & diagnostics（update-check/update-install/dsh-update-install/诊断日志查看+Copy all/Clear）；About（版本/许可证外链）；高权限操作经 ensureUnlock（已在 team-link GATED 实现），未设屏幕锁提示 |

验收：注册 `side`、`botBrowser`、`settings` 及设置子页路由；勾选 T037–T040；arkts 0 错误；构建通过。

## 7. 批次 5：T041–T045 Polish

- **T041**：主题联动收口——确认深浅色/团队主题/强调色/语言切换全部即时生效且持久化（批次 1 已修复响应式，本项做全屏验证与遗漏补齐）。
- **T042**：全局体验收口——中英文日期时间格式（"11月15日" 等，i18n.ts 已有 helper）、发送成功/危险操作触感（Platform haptics）、长按消息复制（ChatRows 已有，确认覆盖全部消息类型）、等待/错误态全屏反馈、全部文案经 t() 无硬编码英文。
- **T043**：核对路由表与屏幕一致——router_map.json 全量注册、单 @Entry、各屏 NavDestination 为根、$r 资源引用有效。
- **T044**：确认 Demo 入口不可达（DemoLink/DemoTeam 保留但 UI 无入口），清理未用导出与死代码。
- **T045**：全项目 `devecocli check arkts` 迭代至清零。

验收：勾选 T041–T045。

## 8. Phase 5 验证（T046–T047，build-only）

- **T046**：`devecocli build` 迭代修复至成功产出 HAP。
- **T047**：`devecocli run --skip-build` 部署到设备/模拟器；无设备时记录说明并保留构建产物验证结论。
- 验证范围 build-only（tasks.md 中标记 `<!-- verification_scope: build-only -->`），无 UI 验证任务。
- 完成后勾选 T046–T047。

## 9. 已知非阻塞构建警告（可顺带优化，非必须）

- `platform/Platform.ets`：89/104/189/194/309 行 SDK 调用可能抛异常（建议补 try/catch）；194 行 `READ_PASTEBOARD` 需权限 API 12
- `screens/Pair.ets:51`：`getContext` 已废弃
- `components/Marks.ets:47`：`@Monitor` 监听的变量不是状态变量

## 10. 对照审计中已知但未处理的偏差（有意保留或低优先）

- 危险确认用内联"再点一次"（跟随桌面端模式，非 REF 的系统 Alert）——有意设计
- 相机扫码用系统 ScanKit 单次扫码（非内嵌 CameraView）——有意设计
- 自定义团队主题不支持（仅 4 个硬编码预设：deepseek/mono/paper/moonlight）——低优先
- demo 模式入口（REF `EXPO_PUBLIC_DSB_DEMO=1`）未接线，`attachDemo/seedComputers` 为保留代码——T044 确认不可达即可
- demo 播种两台演示计算机（seedDemoComputers）未实现——低优先

## 11. 执行顺序与勾选规则

1. 按批次 2 → 3 → 4 → 5 → Phase 5 顺序执行；每批完成后运行 arkts 检查 + 构建验收。
2. 每批完成后用 edit 工具勾选 tasks.md 对应任务（`[ ]` → `[x]`）。
3. 不修改 spec.md/plan.md 的需求语义；不改 pages/Index.ets 现有结构（除非接路由参数必需的最小改动）。
4. 全部完成后最终构建 + 部署，报告结果。
