# Implementation Plan: 聊天页与全局移植一致性修复（chat-parity-fix）

**Input**: Feature specification from `spec/chat-parity-fix/spec.md`

## Summary

修复移植版与原版（RN `E:\Dshbot\DS-Bot\mobile\src`，IM/Schedules 参照桌面 `ds-bot/src/client`）全面对比审计出的 21 项移植 bug（5 HIGH + 16 MEDIUM，FR-001~FR-017）。核心技术方案：

1. **行内样式渲染（FR-001，用户报告的主 bug）**：RN 的 `<Text>` 可嵌套 `<Text>`，ArkUI 的 `Text` 只允许 Span/ImageSpan/ContainerSpan 子组件，移植版把 strong/em/link/del 译成嵌套 `Text()` 后静默不渲染。方案：将 InlineToken 树**扁平化为带样式标志的文本段序列**（纯函数，新文件 `common/markdown/markdown-run.ts`），渲染层用一系列 `Span`（Span 支持 fontWeight/fontStyle/fontColor/decoration/fontFamily/fontSize/onClick）一次绘出，样式与 RN 版逐项对齐（粗体 600、斜体、删除线、链接主题色+下划线+可点击）。
2. **词法器规则补齐（FR-002）**：列表标记打断段落、嵌套缩进列表保层级、松散列表空行续行、Setext 标题、`_` 不做词内强调。
3. **其余 15 项**均为局部修复（见 Research & Decisions 逐项决策），分布在 ChatRows/ChatInput/Banner/TeamPages/MessageList/Side/Im/CapabilityManager/Schedules/Platform/store-core/ChatCards/types。

## Technical Context

**Language/Version**: ArkTS（API 26，compatibleSdkVersion 26.0.0）
**Primary Dependencies**: ArkUI（Span/Swiper/overlay/hitTestBehavior/userAuth/userIAM）、现有工程结构（@ComponentV2 + @ObservedV2/@Trace 状态管理 V2）
**State Management**: 保留现有 V2（@ComponentV2/@Local/@Param/@Monitor/@Computed）；不引入 V1，不做 MVVM 迁移
**Storage**: 现有 preferences（store-core.ts）；不新增存储
**Testing**: `devecocli build`（SC-003）；UI 场景验证（SC-001/002，Phase 3 决定具体范围）；可选 node 词法器行为自检（工程已有 `E:\Dshbot\DSHBot-Harmony\test\node_modules\marked` 参照）
**Target Platform**: HarmonyOS 手机（本机模拟器 Mate 90 Pro / HarmonyOS 7.0 / API 26）
**Project Type**: 已有 HarmonyOS 应用（增量修复），非新工程
**Performance Goals**: 不回退现状——词法缓存（lexed Map）保留；扁平化在渲染前一次完成；Span 数量与 RN 叶节点数量同阶
**Constraints**: 有意差异项零回归（SC-004）；不动 RN 侧代码；宿主协议 ds-bot 0.3.10
**Scale/Scope**: 触及 16 个源文件 + 1 个新文件；单聊页渲染链路重写幅度最大

## Project Structure

### Documentation (this feature)

```text
E:\Dshbot\DSHBot-Harmony\spec\chat-parity-fix\
├── spec.md              # 已确认的需求规格（FR-001~FR-017, US1~US9）
├── plan.md              # 本文件
```

### Source Code (repository root: E:\Dshbot\DSHBot-Harmony)

```text
entry/src/main/ets/
├── common/markdown/
│   ├── markdown.ts                 # [改] FR-002 词法规则（列表打断段落/嵌套/松散续行/Setext/_词内限制）
│   ├── markdown-model.ts           # [改] FR-003 normalizeSoftBreaks 保留换行
│   └── markdown-run.ts             # [新] FR-001 InlineToken 树 → 样式段扁平化（纯函数 + StyledRun 模型）
├── common/team/
│   ├── types.ts                    # [改] FR-014 TeamState.imStatus + ImStatusEntry
│   └── store-core.ts               # [改] FR-012 readPrefs JSON 容错
├── common/demo/demo-link.ts        # [核对] FR-017 demo 数据 scheduledAt 为毫秒数值（与真实宿主 ISO 字符串并存，经归一化兼容）
├── screens/chat/
│   ├── MarkdownText.ets            # [改] FR-001 MarkdownInlines 重写为 Span 渲染；FR-004 hasBlockContent 对齐 RN
│   ├── ChatRows.ets                # [改] FR-004 气泡 wide 宽度；FR-005 PhotoViewer Swiper onChange
│   ├── MessageList.ets             # [改] FR-008 rowKeyOf 内容签名
│   ├── ChatInput.ets               # [改] FR-009 附件菜单改为 overlay 浮层
│   └── ChatCards.ets               # [改] FR-010 审批卡 copyOption
├── screens/
│   ├── Chat.ets                    # [核对] FR-008 行构造（rows @Computed，不改 key 生成，只改 rowKeyOf）
│   ├── Side.ets                    # [改] FR-011 answering 轮询启停
│   └── Schedules.ets               # [改] FR-017 scheduledAt 类型归一 + pausable/whenText 数值比较
├── screens/settings/
│   ├── TeamPages.ets               # [改] FR-007 forget 后 ensureLink
│   ├── Im.ets                      # [改] FR-014 imStatus 消费 + 重试；FR-015 引导链接可点
│   └── CapabilityManager.ets       # [改] FR-016 能力删除两步确认
├── components/Banner.ets           # [改] FR-006 横幅卡 BLOCK_HIERARCHY 命中
└── platform/Platform.ets           # [改] FR-013 门禁 PIN 探测回退
```

**Structure Decision**: 完全遵循现有工程架构（现有 screens/common/components/platform 分层 + 状态管理 V2）。本次为缺陷修复，不引入 MVVM 目录、不做状态管理迁移、不新建页面。唯一新增文件 `markdown-run.ts` 是纯函数模块，与既有 `markdown-model.ts`/`markdown-rules.ts` 同层同风格（common/markdown/ 下已是"纯逻辑与渲染分离"的约定），文件数增量最小且职责清晰。

## Complexity Tracking

无章程冲突项需要豁免（无新工程、无新目录层级、无第三方依赖引入）。

## Research & Decisions

### R1 — FR-001 行内样式的 ArkUI 渲染机制

- **Decision**: 不再用嵌套 `Text()` 渲染 strong/em/link/del。新增纯函数 `flattenInlineRuns(tokens, depth): StyledRun[]`（`common/markdown/markdown-run.ts`），把 InlineToken 树按先序遍历扁平化为样式段序列；`MarkdownInlines.runs` 改为对这些段生成 `Span`。样式映射（与 RN `markdown.tsx` Inline() 逐项对齐）：strong→fontWeight 600；em→FontStyle.Italic；del→decoration LineThrough；codespan→MONO 字族 + fontSize `max(12.5, fs-2.5)` + 两侧 CJK hair-space（`\u2006`，沿用现有 inlineLead/inlineTrail 逻辑）；link→accent 色 + Underline + onClick 打开（仅 http/https/mailto，其余降纯文本）；br→`'\n'` 段；image（不可提升场景）→alt 文本 tint 0.45 段。粗斜/加粗内链接等组合样式通过段的布尔标志叠加。深度上限沿用 INLINE_DEPTH=6，超限内容以纯文本完整输出（不丢字符）。
- **Rationale**: 官方约束 ArkUI `Text` 子组件仅 Span/ImageSpan/ContainerSpan；Span 明确支持 fontWeight/fontStyle/fontColor/decoration/fontSize/fontFamily 及 onClick（faqs-arkui-1437/1337），可完整承载 RN 嵌套 Text 的样式语义。扁平化把"树→段"与"段→Span"解耦，纯函数可独立自测，渲染层薄。
- **Alternatives considered**: ① 每个样式节点换成独立 `Text()` 兄弟节点拼在 Column——破坏段内换行/对齐（RN 的嵌套 Text 是行内连续排版），放弃；② ContainerSpan 包 Span 分层——ContainerSpan 主要服务背景/圆角分组，样式继承链不如扁平段直白，且组合样式（粗+斜+删除线）仍需叠加计算，放弃；③ 保留嵌套 Text 仅修渲染——不可能，ArkUI 无此能力。

### R2 — FR-002 词法器五条规则的具体语义（对齐 marked/RN 实际行为）

- **Decision**（`common/markdown/markdown.ts`）：
  1. **列表打断段落**：段落收集循环（lexBlocks 171-190）增加两条 break 条件——无序列表标记行（`[-*+] + 内容`）恒打断；有序列表标记行仅在起始数字为 1 时打断（CommonMark/marked 行为）。与既有 hr/heading/fence/quote/table 的 break 条件并列，注意与 hr（`* * *`）、表格分隔行的正则不冲突。
  2. **嵌套/缩进列表保层级**：列表项续行处理（131-148）区分两种行——a) 续行本身是列表标记行且缩进 ≥ 项内容列：只剥离"标记列"缩进（itemIndent），保留其相对缩进使其在 `lexBlocks(bodyLines, depth+1)` 递归中成为嵌套 list 子块；b) 普通文本续行：维持现状（剥离到内容列）。当前实现对所有续行一律剥到内容列，导致嵌套标记被压平成兄弟项。
  3. **松散列表空行续行**：列表项内空行（133-140）后若下一行是**缩进 ≥ 内容列的任意非空续行**（当前仅识别"同级列表标记行"），将空行并入项体继续收集（bodyLines.push('')），正文保留在列表项内。
  4. **Setext 标题**：段落收集循环中，若已收集 ≥1 行正文且当前行匹配 `^ {0,3}=+\s*$`（或 `^ {0,3}-{2,}\s*$`，注意与 hr/列表标记正则的互斥：hr 要求标记间有空格、列表要求标记后有内容），终止段落并输出 `heading`（depth 1/2，inline 走 lexInline），不输出字面下划线行。
  5. **`_` 词内限制**：`lexInline` 中 `_` 的 strong/em 分支增加 CommonMark 简化侧翼检查——开标记前一字符是字母/数字时不开启（`my_var_name` 不解析 em），闭标记后一字符是字母/数字时不闭合；`*` 保持现状（允许词内，CJK 锚点逻辑不变）。`__bold__`、`**加粗**` 行为不变。
- **Rationale**: 五条均为 RN（marked）实际渲染行为，spec 验收场景 1-6/US1 直接对应；实现全部收敛在 lexBlocks/lexInline 既有循环内，不新增解析阶段。
- **Alternatives considered**: 引入完整 CommonMark 参考实现——移植版自研 lexer 的意义就是可控子集，全面替换风险大、无必要，放弃。

### R3 — FR-003 软换行保留

- **Decision**: `normalizeSoftBreaks`（markdown-model.ts）从"折叠 `\n` 为空格"改为**原样保留换行**（ArkUI Text/Span 将 `\n` 渲染为换行）。保留函数与全部调用点（MarkdownText.ets 210/464/471），同步修正两处误导性注释（markdown.ts:292、markdown-rules.ts 头注、markdown-model.ts 头注中"soft break collapses"的表述）。`markdown-rules.ts` 的 `softBreakText` 当前无调用点，注释一并修正但不改签名。
- **Rationale**: 已核对 RN `markdown.tsx`：marked 的 text token 内软换行 `\n` 原样进入 RN `<Text>`，RN Text 渲染为真实换行（Inline() default 分支直接 String(token.text)）。spec US1 场景 4 以 RN 为准。
- **Alternatives considered**: 把软换行升格为 br token——改变 token 形态，牵连 hasBlockContent/splitParagraphImages 等下游，无收益，放弃。

### R4 — FR-004 气泡 wide 规则

- **Decision**: 
  - `hasBlockContent`（MarkdownText.ets）对齐 RN（markdown.tsx:25-27）：仅统计非 paragraph/text/space 块，**移除**"段落含被提升图片"分支（该分支为移植版自加，与 RN 不一致）。
  - 用户气泡（ChatRows userBubble）：`wide = hasBlockContent(text)`，wide 时气泡宽度取 `maxWidth`（占满），非 wide 维持现状 wrap-content；photosOnly 透明逻辑不变。RN 参照 items.tsx:230/235。
  - Bot 气泡（botBubbleRow）：`wide = bodyTexts.some(hasBlockContent) || hasImages`，wide 时外层取 `maxWidth`。RN 参照 items.tsx:304/318。
  - 群聊变体（botRow）：part 气泡（1293 行）alignSelf Stretch 条件补齐为 `hasBlockContent(partText) || (last && hasImages)`（RN items.tsx:284）。
  - ArkUI 条件宽度实现：@Builder 内 if/else 双分支（共享气泡内容子 @Builder，属性链在两分支重复），避免 `width(undefined)` 之类的非法传参。
- **Rationale**: spec US1 场景 7 明确要求按 RN wide 规则；代码块/表格在窄气泡中横向滚动体验受损是当前可见缺陷。hasBlockContent 的图片分支移除后行为由显式 hasImages 条件完整替代，无遗漏。
- **Alternatives considered**: 保留图片分支并给用户气泡加宽——会加宽 RN 不加宽的消息（图片-only 用户消息），产生新的不一致，放弃。

### R5 — FR-005 PhotoViewer 翻页

- **Decision**: Swiper（ChatRows.ets:330-344）补 `.onChange((index: number) => { this.at = index })`。`at` 已被页码指示（348 行）与 PhotoPage 的 active（原图加载触发）消费， onChange 接上后两个症状（页码冻结、原图不加载）同时修复。
- **Rationale**: RN 参照为 FlatList onViewableItemsChanged 等价物；ArkUI Swiper 的标准翻页回调即 onChange。`.index()` 仅设置初值，不驱动状态。
- **Alternatives considered**: 在 PhotoPage 内部监听可见性——把列表容器职责下放到子页，改动面大，放弃。

### R6 — FR-006 横幅点击（命中测试）

- **Decision**: Banner.ets 外层 Column 的 `hitTestBehavior(HitTestMode.None)` **保留**（保证横幅卡以外的覆盖区域触摸穿透到下方聊天），在内层横幅卡 Text（79-92 行，带 onClick 的节点）上补 `hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)`。
- **Rationale**: 官方 FAQ《HitTestMode 的不同应用场景》（faqs-arkui-1052 场景一）给出的正是此模式："给全屏蒙层设置 HitTestMode.None 使点击时事件可以传递蒙层下方组件，同时给蒙层的子组件设置 HitTestMode.BLOCK_HIERARCHY 阻止事件传递到蒙层下方组件"。审计实测 None 父节点下普通子节点点击不可达，与该 FAQ 指引一致。
- **Alternatives considered**: 去掉外层 None——横幅容器 height 100% 会拦截整个覆盖区域的触摸（RN pointerEvents='box-none' 语义即"容器穿透、内容可点"），去掉会引入更严重的新缺陷，放弃。

### R7 — FR-007 忘记当前电脑后断链

- **Decision**: TeamPages.ets `forget()`（363-366）在 `await appStore.computers.forget(...)` 与 `await this.load()` 之后补 `appStore.ensureLink()`，与 `switchTo`（331-334）对齐。
- **Rationale**: `ComputersState.forget` 已重解析 active（AppStore.ets:149-152：removeComputer 内部把 activeId 切到下一台并 loadComputer），但没有人重建链接。`ensureLink()` 的现有语义完整覆盖两个验收场景：active 变为另一台 → activeLinkHost 不同 → 关旧链建新链；active 变 null（最后一台）→ closeLink()，无残留。
- **Alternatives considered**: 在 ComputersState.forget 里直接调 ensureLink——store 层不应依赖 AppStore 单例（分层方向反了），页面侧调用与 switchTo 现有模式一致，放弃。

### R8 — FR-008 列表行 key 内容签名

- **Decision**: MessageList.ets `rowKeyOf`（50-57）在既有键缀基础上追加内容签名：`+f${(item.files ?? []).length}`、`+i${(item.imageRefs ?? []).length + (item.images ?? 0)}`、`+w${item.whole !== undefined ? 1 : 0}`、`+s${row.stamp}`、`+l${item.local ?? ''}`、`+x${(item.text ?? '').length}`。基础 key（keysOf 生成，Chat.ets rows @Computed）保持不变；openSteps/openTools 等 UI 态映射仍用基础 key，不受影响。
- **Rationale**: LazyForEach 仅在 key 变化时重建行；spec US5 场景（刷新后消息补充图片引用、戳更新）要求这些字段进 key。文本用长度签名与既有 streaming 行 `#${text.length}` 模式一致（内容更新必然伴随长度或引用数变化；纯等长替换文本不在验收范围）。
- **Alternatives considered**: 全文 hash 进 key——每帧全量哈希成本高，且等长不同文本场景本就依赖刷新重建基础数据，放弃。

### R9 — FR-009 附件菜单浮层化

- **Decision**: ChatInput.ets 附件菜单（422-455）从 Stack 子组件改为输入行 Row 的 `.overlay(菜单 Builder, { align: Alignment.BottomStart })` 浮层：菜单 Column 及其样式（140 宽、圆角、边框、阴影、两项 44 高行）整体迁入 @Builder；打开条件 `this.menuOpen && this.canPhoto && this.canFile` 在 Builder 内 if 控制；相对 BottomStart 锚点向上偏移（offset y 负值，视觉位置与现状一致）。Stack（360 行）保留，仅移除菜单子节点。菜单项点击行为（pickPhoto/pickFile/开合状态）不变。
- **Rationale**: 官方文档：overlay 浮层"定位基于当前组件进行计算、不通过组件树进行渲染"，不参与宿主尺寸测量——正是"浮层不撑大输入栏"的机制解；现状 offset 不改变 Stack 对子节点的测量，菜单高度直接计入输入栏卡片高度。
- **Alternatives considered**: ① bindContentCover/CustomPopup——模态遮罩/气泡语义与轻量菜单不符；② 外层再包固定高度容器并让菜单溢出——依赖 clip 行为、脆弱，均放弃。

### R10 — FR-010 审批卡可复制

- **Decision**: ChatCards.ets ApprovalCard 卡体三个 Text（approval.detail.text 769、reason 776、detail.code 785）补 `.copyOption(CopyOptions.LocalDevice)`。
- **Rationale**: RN 版所有卡体文本均 `selectable`；ArkUI 等价物是 copyOption，工程内 MarkdownText/代码块已用同一常量。
- **Alternatives considered**: 长按弹出复制菜单（工程 Actions 模式）——交互重，spec 仅要求长按/选择复制，copyOption 即满足。

### R11 — FR-011 侧边聊轮询启停

- **Decision**: Side.ets 把 `running()` 从普通方法改为 `@Computed`，新增 `@Monitor('running')` 调用 `this.setPolling(running)`；`aboutToDisappear` 已有 `setPolling(false)` 保留。setPolling 本体（114-128，1500ms interval、state {since:-1}）已实现且正确，仅缺触发。
- **Rationale**: RN side.tsx 参照：`useEffect(() => { if (!running) return; const timer = setInterval(() => void call('state', { since: -1 }), 1500); return () => clearInterval(timer) }, [running, call])`——启停完全由 running 驱动。V2 下 @Monitor 可观察 @Computed 变化，是工程既有模式。
- **Alternatives considered**: 在 send() 后手动开、在渲染里比对——分散且漏收口，放弃。

### R12 — FR-012 prefs 损坏容错

- **Decision**: store-core.ts `readPrefs`（166-171）对 `JSON.parse(text)` 包 try/catch：解析失败时置 `prefsCache = {}` 并返回，不再抛出（prefsCache 先赋值后解析，保证失败也落缓存不反复重试）。
- **Rationale**: AppStore.boot() 的 catch 会把启动异常写进 bootError 导致砖化页（spec US7 场景 4）；身份/电脑数据读取本就有守卫，prefs 属低价值可重建数据，默认值回退即可。`writePrefs` 经 readPrefs 展开，缓存重置后写入自然覆盖损坏数据。
- **Alternatives considered**: 在 boot() 外层再兜底——治标不治本，后续任何 readPrefs 调用（restoreChat 等）仍会炸，放弃。

### R13 — FR-013 门禁 PIN 回退

- **Decision**: Platform.ets `ensureUnlock`（324-360）：探测列表从 `[FACE, FINGERPRINT]` 扩为 `[FACE, FINGERPRINT, PIN]`（`userAuth.getAvailableStatus(type, ATL1)` 逐个 try/catch，通过的进入 enrolled 集合）；认证参数 `authType` 传 enrolled 集合（不再传固定二值数组）。全无 enrolled 时维持抛 `UnlockError('unlock/unavailable')`——此时"未设置锁屏"文案即为准确（设备确实没有任何凭据）。
- **Rationale**: 已查证 API 26 `@ohos.userIAM.userAuth` 对应用开放 PIN 认证类型（官方 API 文档示例即 `authType: [FACE, PIN]`；UserAuthType 枚举含 PIN=1），"仅锁屏密码设备被锁死"是移植时漏探测所致，属可修复项而非平台限制。widgetParam 标题、ATL1 信任级、结果回调处理全部维持现状。
- **Alternatives considered**: 保持现状仅在错误文案上打补丁——spec 明确要求探测平台凭据回退能力，纯文案降级不满足 FR-013 主句，放弃。

### R14 — FR-014 IM 状态消费与重试

- **Decision**: 
  - types.ts：`TeamState` 增 `imStatus?: Record<string, ImStatusEntry>`，`ImStatusEntry { state?: string; error?: string; at?: number }`（宿主 channel.js live 载荷已有该字段，随既有 state 合并链路下发，无需改 team-link）。
  - Im.ets：`connStatusLine(conn)`（794-804，列表行 761 与详情头 986 共用）按桌面 im-page.js `stateOf/stateText` 语义消费 `appStore.link.team?.imStatus?.[conn.id]`：off→Disabled、ready→Connected、retrying→Retrying…、error→Could not connect: {error}、缺省→Connecting…；enabled===false 恒 Disabled。详情页（detailBlock）当状态为 error 时在状态区旁提供「Try again」按钮，调用 `controller.call('im-retry', { id })`，成功后维持既有刷新链路（state 轮询/revision 推送）。
  - 状态条目缺失（旧宿主）时回退现有文案，不报错。
- **Rationale**: 桌面参照 `ds-bot/src/client/im-page.js`（stateOf 75-77 / stateText 80-85 / DetailView 282 行 Try again→actions.imRetry）与 `ds-bot/src/client/team-actions.js:192`（imRetry→call('im-retry',{id})）已逐一核对；宿主 `im-retry` 端点存在（host/im/index.js:947）。
- **Alternatives considered**: 列表行也放重试按钮——桌面仅详情页有，保持一致，放弃。

### R15 — FR-015 IM 引导链接可点

- **Decision**: Im.ets `addBlock`（833-869）在引导步骤下方渲染链接行：`GUIDES[platform].linkLabel` 文本，accent 色 + 下划线，onClick 经 `openExternalUrl`（MarkdownText.ets 已导出，限 http/https/mailto）打开 `GUIDES[platform].link`。link 为空时不渲染该行。
- **Rationale**: GUIDES 数据（94-159）已含 link/linkLabel（与桌面 im-page.js GUIDES 同源），当前是无消费的死数据；RN/桌面引导区链接均可点。
- **Alternatives considered**: 复制链接到剪贴板——多一步操作且与参照实现不一致，放弃。

### R16 — FR-016 能力删除两步确认

- **Decision**: CapabilityManager.ets 展开行 Delete 动作（468-475）改为两步：首拍将按钮文案切为确认态（如「Delete?」）并记录 armed id，3 秒内二拍执行 `capability-delete`，超时自动解除。实现采用工程既有内联确认模式（Schedules.confirmDelete 277-285 的 armedId+timer 写法；TeamPages.tapForget 同型），不引入新组件。
- **Rationale**: spec FR-016 要求"与移植版其他危险操作一致的两步确认"；工程内三处既有模式（FormControls ConfirmDanger/DangerRow 用于整行、Schedules/TeamPages 内联 armed+timer 用于行内动作），能力删除是展开行内的行内动作，取内联模式。桌面/移动端原生能力删除的防误删语义一致。
- **Alternatives considered**: AlertDialog 弹窗——spec 与既有约定（两步确认替代弹窗，见 spec Assumptions 有意差异项）相悖，放弃。

### R17 — FR-017 Schedules 时间归一化

- **Decision**: Schedules.ets：`ScheduleTaskFull.scheduledAt` 类型改为 `string | number`；新增私有归一化函数（毫秒数值：number 直取，string 走 Date.parse，NaN 返回 NaN 由调用点 Number.isFinite 判定）；`pausable()`（253-260）用归一化数值与 `Date.now()` 比较（`Number.isFinite(when) && when <= Date.now()` → 不可暂停），移除现行模板串 Date.parse 写法；`whenText`（112-118）经同一归一化喂给 `timeLabel`。demo-link 的毫秒数值与真实宿主 ISO 字符串（host 测试数据 `'2030-01-01T01:00:00.000Z'`）两条数据通路均被归一化覆盖。
- **Rationale**: 已核实宿主侧 scheduledAt 为 ISO 字符串（ds-bot test/schedules.test.js 全部 ISO；桌面 client Date.parse 直接解析），而移植版类型声明为 number 且 demo 喂数值——现行 `Date.parse(\`${number}\`)` 在 demo 通路恒 NaN、真实通路因类型误配存在隐患，两条通路都必须归一。spec US9 只要求过期一次性任务不可暂停/恢复，归一化后 demo 与真实数据判断均正确。
- **Alternatives considered**: 只修 pausable 不动类型——string/number 混型迟早再炸（whenText 同病），一次治全。

### R18 — FR-008 补充：US5 与既有 streaming 键的兼容

- **Decision**: 内容签名追加不改变既有行为——`streaming` 行的 `#${text.length}`、stepsOpen/expandedTool/+img 缀全部保留，签名只增不减；RowsSource.setRows 的按 key diff 通知逻辑不动。
- **Rationale**: 行重建粒度变细只会让"内容变化即时刷新"（US5）生效，不会破坏滚动位置保持（scrollOffsets 按基础 key 记忆）。

## Data Model

### 新增（FR-001）

```text
StyledRun（common/markdown/markdown-run.ts，纯数据接口）
  text: string          // 该段的字面文本（br 段为 '\n'，codespan 段含 hair-space 修饰）
  bold?: boolean        // strong 祖先链
  italic?: boolean      // em 祖先链
  strike?: boolean      // del 祖先链
  mono?: boolean        // codespan（内容为字面文本，不再下钻）
  href?: string         // link（安全 scheme 在渲染层判定）
  muted?: boolean       // 不可提升 image 的 alt 回退段（tint 0.45）
```

约束：深度超过 INLINE_DEPTH(6) 的子树以纯文本段完整吐出；同一文本不会被拆丢（先序遍历，段与段首尾相接）。

### 扩展（FR-014）

```text
ImStatusEntry（common/team/types.ts）
  state?: string        // 'ready' | 'error' | 'retrying' | 'connecting'（宿主 imStatusView）
  error?: string        // state==='error' 时的错误文案
  at?: number           // 状态时间戳
TeamState 增加: imStatus?: Record<string, ImStatusEntry>   // 键为 connection id
```

### 变更（FR-017）

```text
ScheduleTaskFull.scheduledAt: number → string | number
新增私有归一化: 毫秒时间戳 number，或 Date.parse(ISO string)；解析失败为 NaN
```

### 不变的既有模型

InlineToken/MdToken/MdListItem（markdown.ts）、MessageRow/rowKeyOf 输出（MessageList.ets，签名只追加片段）、Approval/ImConnection/ImView（types.ts）、prefsCache 结构（store-core.ts）。

## Contracts & Interfaces

### 模块契约（纯函数，common/markdown/markdown-run.ts）

- `flattenInlineRuns(tokens: InlineToken[], depth: number): StyledRun[]` — 先序扁平化；codespan 产 mono 段（含 CJK hair-space，需调用侧传入前后 token 以判定 lead/trail，签名允许带 neighbor 上下文，实现阶段可收敛为 `flattenInlineRuns(tokens, opts)`，opts 含 fs 用于 codespan 尺寸推导的输入只影响渲染层，数据层不存尺寸）。
- 渲染契约（MarkdownText.ets MarkdownInlines）：输入 StyledRun[]，输出单 `Text` 内的 Span 序列；Span 样式映射见 R1；链接段点击经 `openExternalUrl`（限 http/https/mailto）。

### 词法契约（common/markdown/markdown.ts）

- `lexer(text)` 输出 token 类型集合不变（heading/paragraph/code/list/blockquote/table/hr/space/text/html + InlineToken 五类行内）；变化仅在分块/行内判定规则（R2 五条），输出形态向后兼容（消费方 MarkdownText/markdown-model/markdown-rules 的接口签名不变）。

### 行 key 契约（screens/chat/MessageList.ets）

- `rowKeyOf(row: MessageRow): string` — `基础key [+open] [+t{n}] [#streaming长度] [+img] + 内容签名(f/i/w/s/l/x)`；RowsSource 仍按整串 diff。

### IM 契约（screens/settings/Im.ets）

- 状态文案函数与桌面 stateOf/stateText 语义一致（R14 五态映射）；重试动作 `call('im-retry', { id })`，错误态按钮仅在详情页出现。

### 门禁契约（platform/Platform.ets）

- `ensureUnlock(endpoint)`：GATED 端点不变；抛出的 UnlockError code 集合不变（unlock/unavailable、unlock/canceled）；变化仅在 enrolled 探测范围含 PIN 与 authType 传参。

### 存储契约（common/team/store-core.ts）

- `readPrefs()` 不再因损坏 JSON 抛异常，恒返回 `Record<string, string>`；`writePrefs/onPrefsChange` 签名与语义不变。

### 不受影响的接口

team-link 的 state 合并链路、DemoLink、AppStore.ensureLink/closeLink、ComputersState.forget/switchTo、FormControls.DangerRow/ConfirmDanger、i18n 词条体系（新增文案优先复用既有词条；确需新增的（如 Delete? 确认态、Try again 若无既有词条）在实现阶段加入 i18n.ts 并中英双语齐全）。
