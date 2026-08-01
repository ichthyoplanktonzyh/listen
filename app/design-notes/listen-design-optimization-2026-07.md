# listen 设计优化规格 · 2026-07-28

> 基线：`main @ aa90c43`，实测运行截图（暗色，约 1000pt 宽窗口）+ 源码定位。
> 判据仍是宪章五原则（P1–P5）与四通道闭环（T），见
> [`listen-design-charter.md`](./listen-design-charter.md)。
>
> **本文件与既有 design-notes 的关系**：`listen-*.html` 是气质稿（mood board），
> 回答"应该长什么气质"；本文件是**规格**（spec），回答"每个数值是多少、
> 哪条测试守它"。两者不冲突，但验收以本文件为准——因为 Phase 2 的落地偏差
> 恰恰来自"只有气质稿、没有规格"。

---

## 0 · 根因：为什么设计稿没落地

Phase 2 的页面重构（对话三段式、词条详情分段、复习卡、教练画像）**结构上都做对了**，
但视觉与信息设计明显低于气质稿。原因不是执行力，是三个结构性缺口：

| 缺口 | 后果 | 证据 |
| --- | --- | --- |
| **气质稿不可执行** | HTML 稿给的是氛围和色值，没给 padding/字号/图标尺寸/密度。实现时这些必须现编，于是每屏各编一套 | 全仓 143 处阶梯外 `EdgeInsets`；14 种图标尺寸 |
| **纪律测试只锁了 4 扇门** | 色/圆角/spacer/spinner 有测试且几乎零违规；padding/图标/排版 slot/列宽无测试且大面积漂移 | 见 §2 对照表 |
| **没有视觉回归网** | 改一处不知道另一处崩了；[#12](https://github.com/ichthyoplanktonzyh/listen-app/issues/12) Golden 基建一直挂着 | 教练回声条已退化成灰块，无人发现 |

**结论：先补规格与执法，再谈单屏优化。** 否则下一轮重构会用同样的方式漂移回去。

---

## 1 · 补齐缺失的 token 层

现有 token（`ListenColors` / `ListenType` / `ListenSpacing` / `ListenRadii` /
`ListenMotion` / `ListenBreakpoints`）覆盖了色、字号、间隙、圆角、动效、断点。
实测缺 **4 层**，全部是本轮偏差的直接来源。

### 1.1 `ListenIconSize`（新建，最急）

全仓图标尺寸有 **14 个不同值**（13/14/15/16/17/18/20/21/28/34/46/64/68/72），
外加 `iconSize:` 又 7 个。截图 6 的三态环小到看不见、截图 1 的 AppBar 图标大到抢戏，
是同一个病。

```dart
/// 图标尺寸（新增）。图标是与文字并排的第二套字形，必须与 ListenType 阶梯配对，
/// 否则同一行里图标和标签的视觉重量对不上。
abstract final class ListenIconSize {
  /// 内联于 caption/body 文本流中的状态点、三态环。与 11–12px 文字配对。
  static const inline = 14.0;

  /// 列表行、chip、次级动作。与 12–13px 文字配对。这是默认值。
  static const control = 18.0;

  /// AppBar / 工具栏主动作、tab 图标。与 14–16px 文字配对。
  static const chrome = 22.0;

  /// 空态、首启、大卡片的说明性图标。唯一允许的"大图标"。
  static const illustration = 48.0;
}
```

迁移映射：13/14/15 → `inline`；16/17/18/20/21 → `control`；22/24/28 → `chrome`；
34/46/64/68/72 → `illustration`（且每处需写明为什么是插画而不是控件）。

### 1.2 `ListenSpacing` 扩展到 padding

`ListenSpacing` 的阶梯（2·4·6·8·12·16·24·32）本身没问题，问题是
[spacing_discipline_test.dart:16](../test/spacing_discipline_test.dart) 只匹配无 child 的
`SizedBox`，而 **340 处 `EdgeInsets` 里 143 处在阶梯外**（10 出现 45 次、14 出现 18 次、
20 出现 17 次、18 出现 16 次…）。

不需要新 token，需要新增语义化的**组件内边距常量**，让"卡片该 padding 多少"不再每次现编：

```dart
/// 组件内边距（新增于 spacing.dart）。ListenSpacing 是"元素之间的间隙"，
/// 这一组是"容器内部的呼吸"，两者不同概念，混用是当前 10/14/18/20 泛滥的原因。
abstract final class ListenPadding {
  /// 密集控件内部：chip、小按钮、列表行的纵向。
  static const tight = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

  /// 列表行、面板行的标准内边距。
  static const row = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  /// 卡片 / 分区容器。
  static const card = EdgeInsets.all(16);

  /// 页面级内容边距（窄）。< homeSidebar 断点时用。
  static const pageCompact = EdgeInsets.symmetric(horizontal: 24, vertical: 24);

  /// 页面级内容边距（宽）。
  static const page = EdgeInsets.symmetric(horizontal: 32, vertical: 32);
}
```

首页现在是 `fromLTRB(24|48, 28|44, 24|48, 40)`——四个方向四个值，其中三个在阶梯外。
换成 `pageCompact` / `page` 后，首页与教练页、词汇本的页边距第一次会一致。

### 1.3 内容列宽收口

`ListenBreakpoints.contentColumnMax`(780) / `cardColumnMax`(680) 已存在，但仍有
**19 处硬编码 `maxWidth`**：首页 920、对话 620/520/560、reading_view 900、
speaking studio 760、writing studio 620…

补两档，然后全量迁移：

```dart
/// 密集表单 / 单栏设置的列宽（对话大厅、provider 表单）。比阅读列窄，
/// 因为表单行不是连续文本，长行会让 label↔control 的关联断掉。
static const formColumnMax = 560.0;

/// 双栏或含媒体的宽内容页（首页、媒体库）。
static const wideColumnMax = 960.0;
```

**截图 1 暴露的具体 bug**：我的表达页搜索框是**满窗宽**（约 950pt），下方内容列却
锁在 780。同一页两套测量基准，视觉上搜索框像属于另一个页面。搜索框必须与内容列同宽。

### 1.4 表面层级（surface elevation）语义

截图里卡片、面板、行的背景色差异极小（`darkSurface #141b19` vs
`darkFog #1b2422` vs `darkSidebar #202a27` 之间只差 1–2 档亮度），导致：
- 截图 2 的对话气泡与背景几乎同色，全靠 4px 左侧色条区分；
- 截图 5 的"建议下一步"卡与页面底色几乎不可分；
- 截图 6 右栏的 8 个 已掌握/未掌握 按钮与背景对比不足，读起来像一片文字。

暗色主题下靠亮度分层的空间本来就窄，宪章又要求"暗但不是黑"。**解法不是继续调亮度，
是改用边框 + 极轻底色的组合**，并把它固化成一条规则：

| 层 | 背景 | 边框 | 用途 |
| --- | --- | --- | --- |
| L0 页面 | `surfaceContainer` | 无 | scaffold |
| L1 分区 | 透明 | 无 | 只用标题与间距分区，不画容器 |
| L2 卡片 | `surface` | `outlineVariant` 1px | 可点击 / 可下钻的对象 |
| L3 浮层 | `surface` | `outlineVariant` 1px + shadow | 弹窗、菜单、popover |

**关键纪律：L1 不画容器。** 现在很多"分区"被画成了卡片（截图 5 的通道证据、
截图 6 的切片区），造成截图 5 那样的三层卡片套娃（审计 K3 至今未解）。
分区靠标题 + 32px 间距划分，只有**可点击的对象**才配拥有边框。

---

## 2 · 执法规则：从 4 条扩到 8 条

| 维度 | 现状测试 | 违规量 | 本轮动作 |
| --- | --- | --- | --- |
| 颜色 | `theme_palette_discipline_test` ✅ | 3 处 | 保持 |
| 圆角 | `radius_discipline_test` ✅ | 0 | 保持 |
| spacer | `spacing_discipline_test` ✅（仅 SizedBox） | 0 | **扩到 EdgeInsets** |
| 等待 | `loading_discipline_test` ✅ | 0 | 保持 |
| **图标尺寸** | 无 | 14 种值 | **新建 `icon_size_discipline_test`** |
| **排版 slot** | `typography_test` 只验映射过的 slot | 16 处用未映射的 `headline*` | **新建：禁止 `headline*`/`display*`** |
| **列宽** | 无 | 19 处硬编码 | **新建 `column_width_discipline_test`** |
| **i18n** | 无 | 3 个界面整块硬编码 | **新建：`lib/` 内禁止 CJK 字面量** |

排版那条尤其值得单列：`listen_theme.dart:421` 的注释写着 "nothing in the app uses
them yet"，但全仓 **16 处**在用 `headlineSmall`/`headlineMedium`，而且全是各页最大
的那行字（首页标题、复习卡的词、词条词头、教练页标题）。它们走 Material 默认几何
（24/28px w400），是阶梯外的两个字号。而真正的 `ListenType.hero` 全仓只用过一次，
还用在一个汉字上。**"唯一的 hero 字号"这条规则，实际执行率是 0。**

四条新测试各约 20–30 行，与现有四条同构，一天以内可以全部落地。

---

## 3 · 逐屏优化规格

### 3.1 对话大厅（截图 4）—— 本轮最该重做的一屏

owner 已指出这屏"没被考虑到"。属实：舞台态（截图 3）是全仓最好的一屏，
大厅是最差的一屏，落差刺眼。

**现状问题**
1. **一屏三种语言制度**：`Free conversation`（英）+ `用哪个声音跟你说话`（中）+
   `Show what the other person says`（英）+ `到设置里管理声音`（中）。同一屏内混排。
2. **进入"对话"第一眼是一张设置表单**——审计 D1 的结论在重做后**换了形式又回来了**：
   原来是 provider 表单，现在是 voice 下拉 + 开关 + 三行英文说明。
3. **历史列表吞掉整页**：会话标题取首句发言，于是列表长这样——
   `Hello` / `Hello! Yes, I can hear you loud and clear...` / `Hello` /
   `No conversation captured` / `Hello, can you hear me?`。**六条里五条叫 Hello。**
   标题不承载任何区分信息，而它占了这一屏 60% 的面积。
4. `· completed` / `· failed` 是 raw 枚举
   （[realtime_conversation_panel.dart:625](../lib/widgets/panels/realtime_conversation_panel.dart:625)）。

**规格**

大厅只做一件事：**让用户在 2 秒内开口**。结构自上而下：

```
[ ← 返回 ]

        （垂直居中偏上，formColumnMax 560）

        准备好了就说话                      ← hero，22px w600
        用 test · marin 的声音               ← body，muted，点击可改（不是下拉框）

        ┌─────────────────────────────┐
        │        ◉  开始对话            │     ← 唯一的主动作，56pt 高
        └─────────────────────────────┘

        对方说的话：不显示 ▸                 ← 一行文字开关，不是 Switch + 三行说明
                                              点开才展开说明

  ─────────────────────────────────────      ← 32px 间距 + 分隔线

        最近的对话                           ← title
        ▸ 7 月 28 日 14:43 · 3 分钟 · 12 轮
        ▸ 7 月 28 日 14:33 · 5 分钟 · 20 轮
        ▸ 7 月 28 日 14:31 · 未录到内容
                                             ← 最多 5 条，再多走"全部对话"
```

关键改动：
- **会话标题改为「时间 + 时长 + 轮数」**，首句发言降为 subtitle 或直接不显示。
  用户找一场对话靠的是"什么时候、聊了多久"，不是"第一句说了啥"（何况全是 Hello）。
  参考 Granola / Fathom 的会议列表：时间 + 时长 + 参与度，标题是事后生成的摘要而非首句。
- **`completed` / `failed` 改为描述性文案**：completed → 不显示（正常态无需标注）；
  failed → `未录到内容`。P4 要求诚实，不要求暴露枚举。
- **voice 从下拉框降级为一行可点文字**。下拉框是"你必须做个选择"的信号，
  但 99% 的会话不换声音。
- **"Show what the other person says" 那三行英文说明折叠**。它解释的是诚实分层
  （provider caption 只是 guidance），重要，但不该在每次开口前都读一遍。

### 3.2 舞台态（截图 3）—— 已经很好，两处收口

这屏基本兑现了宪章的"舞台态"定义，波形大形 + `Just speak to cut in`（D5 的
barge-in 可供性终于有了）。两个问题：

1. **底部那颗实心青色按钮是舞台上第二亮的东西**。宪章舞台态第 2 条写死"唯一光源"：
   屏上只有正在发生的内容大形发光。规格：`Finish and transcribe locally` 改为
   **outline 或纯文字按钮**，青色只留给波形。危险动作 `Cancel and discard` 保持文字态。
2. **全英文**。这屏是纯 `Text('...')` 硬编码。

另外构图上，波形中心在 40% 高度、文字在 66%，中间有 250pt 空白，下方 300pt 空白。
建议波形中心下移到 45%，文字紧随其下 48px，整组视觉重心居中——现在整个画面偏上。

### 3.3 对话记录（截图 2）—— 全仓最严重的 P4 违规

**把 HTTP 异常当成学习者的发言展示出来了**，而且连续三条：

> `Could not process learner turn: HttpException: {"code":"validation_error",`
> `"message":"recording metadata must not be empty","correlation_id":"api-853",`
> `"retryable":false}, uri = http://127.0.0.1:62645/v1/recordings`

这条字符串同时泄露了：内部错误码、correlation_id、localhost 端口、内部路由。
它出现在"You · local Whisper transcript"卡片里，位置上等同于用户自己说的话。

**规格**：转写失败是一个**已知的、有名字的状态**，不是异常文本的展示位。

```
┌ You                                        ← 不加 "· local Whisper transcript"
│  这一轮没能转写成功                          ← 描述性，一句话
│  [ 重试转写 ]                                ← 有 retryable 时才出现
└
```

- 异常详情（含 correlation_id）移入日志与"诊断"入口，**永不进主体文本流**。
- `retryable:false` 已经在 payload 里，UI 却没用它——这正是"有诚实的数据、
  却做了不诚实的呈现"。
- `Back to conversations` 英文硬编码。
- 附带产品问题：assistant 用中文回复（"你好呀，很高兴见到你"），
  而这是英语学习 app。AGENT.md 明写"UI 语言与学习语言分离"，这里破了——
  需要确认 provider 的 system prompt 是否绑定了学习语言。

### 3.4 学习教练（截图 5）—— 回声条已经退化成灰块

**这是本轮最值得修的可视化。** 截图里两个约 190×96pt 的大灰块，中间一根青色发丝
和一圈琥珀虚线框。它看起来像图片没加载出来。

**根因（已定位）**：
[capability_viz.dart:509](../lib/widgets/common/capability_viz.dart:509) 的刻度是

```dart
final unit = _quadrants.keys
    .map((channel) => _total(_counts(channel)))   // acquired + notAcquired + unassessed
    .fold(0, math.max);
```

即**刻度包含 unassessed**。用户词库里绝大多数词尚未评估，于是
`unassessed` 段占满 96pt 高的柱子，`acquired = 5` 只有约 2.4pt。
**图形的主要视觉体量，画的是"我们不知道"。**

P4 要求诚实，但"诚实"不等于"把无知画成主体"。规格：

```
现在                          改为
┌──────────┐  ← 灰块 90pt   ┌ ─ ─ ─ ─ ─┐  ← unassessed 变虚线底槽，不填色
│▓▓▓▓▓▓▓▓▓│                 │           │
│▓▓▓▓▓▓▓▓▓│                 │           │
│▓▓▓▓▓▓▓▓▓│                 │  ▓▓▓▓▓▓  │  ← acquired 按「已评估总数」缩放
├─────────┤  ← 青色 2pt      ├───────────┤
```

三条改动：
1. **刻度改为 `max(acquired + notAcquired)`**，即只按已评估的量缩放。
2. **unassessed 不再是填充色块**，改为虚线底槽（承载"还没测"的语义，不占墨）。
3. **"尚未评估 N"以文字补在柱子下方**——信息不丢失，但不再霸占画面。

配套：
- **"点象限看该通道证据，点回声条看这一对，点环心去差距清单。"这句话必须删掉。**
  需要说明书的图形就是失败的图形。可供性靠 hover 高亮 + cursor 变化传达，不靠句子。
- 罗盘环里四段弧几乎全空（因为同一个 unassessed 问题），同步修。
- "建议下一步"的实心青色「去」按钮 → 改 text button。截图里它是整页最亮的东西，
  而它是导航 chrome，不是内容（P2）。
- 通道证据的三层卡片套娃（审计 K3）→ 按 §1.4 的 L1 规则，中间层不画容器。

### 3.5 词汇本（截图 6）—— 结构对了，密度和层级没跟上

**先说做对的**：双栏 master/detail 稳住了，详情页有了分段 tab
（证据/切片/我的输出/义项/笔记）——审计 V4「一根 ListView 串 8 段」**已解决**。
V5「AppBar 原地变身」也解决了。这是本轮最成功的重构。

剩下的问题：

1. **筛选 chip 行横向溢出**：第二行 `全部/已掌握/未掌握/…` 被窗口右缘切断，
   右侧露出半个 chip。需要 `Wrap` 或横向滚动 + 渐隐，不能硬切。
2. **词头重复**：详情页顶部小字 `company`，正下方又是巨大的 `company`。删掉上面那个，
   或把它换成来源媒体名（那才是用户需要的上下文）。
3. **8 个同权重按钮**：四通道 × 已掌握/未掌握，全部 outline 同款。这是一个
   4×2 的表，但画成了 8 个按钮。规格：改为**每行一个分段控件**
   （`已掌握 | 未掌握` 二选一 segmented），未评估时两侧都不选中，右侧灰字"尚未评估"。
   视觉重量立刻降一半，且"这是一个二选一"的语义变清楚。
4. **三态环太小到不可读**：列表行左侧的环在 `inline` 尺寸下几乎是空心圆，
   四态（新/已掌握/未掌握/未评估）分不出来。规格：列表行改用 **3pt 宽的左侧色条**
   （颜色即状态），环只在详情页用——环适合"多维度占比"，不适合"单一状态"，
   而列表行需要的正是后者。这与月蓝（`new` 首见态）的引入也更配。
5. ~~**功能词占满列表**~~：`the` / `of` / `a` / `to` 作为学习词条出现。
   **owner 2026-07-28 判定：属早期设计、非前端问题，不予处理**（见 §6）。
   原先"呈现层加默认筛选"的建议一并撤销——采集口径的问题不该由呈现层兜底。

### 3.6 我的表达（截图 1）

1. **搜索框满窗宽、内容列 780**——同页两套测量（见 §1.3）。
2. **AppBar 两个纯图标**（下载、+）无标签，无 tooltip 可见。按 §1.1 收到 `chrome`
   尺寸，并补文字标签或 tooltip。
3. **文本卫生问题直接上屏**：`- I need to do something。` —— 前导 `- ` 是字幕格式残留，
   句末是**全角句号**。`来源: - I need to wear this, yes.` 同样带 `- `。
   规格：展示前统一清洗（去前导 dash/破折号、按学习语言规范化标点）。
   这条属于 P4——把脏数据原样上屏，是把"诚实"做成了"偷懒"。
4. **单卡 + 大片空白**：一条数据时整页 85% 是空的。规格：内容少于 3 条时，
   下方接**空态引导**（"从字幕里收藏一个句型" + 入口），而不是留白。
5. 用户自己的话已经用青色发光（`↳ 你上次写：`）——**审计 E3 已修，保持。**
6. 全文件 65 处中文字面量 + 21 处 `Text('`，只有 1 处 `l.text`（#6 第 1 项仍开）。

### 3.7 播放器主屏（截图 7）—— 产品核心屏，密度最需要治理

1. **标题是原始文件名**：`How a cell phone ban has transformed this Brooklyn
   middle school｜June 9, 2026 [9FFSOYLiFxc].mp4`——含日期、YouTube ID、扩展名。
   规格：展示时剥离 `[id]`、扩展名、尾部日期；完整文件名留在 tooltip。
2. **「回到当前句」浮动按钮压住了字幕正文**（截图里盖住了 `who've had...impact`）。
   规格：改为贴附在转写列表**底缘**的一条，或列表内联的插入行——浮层不得遮挡内容（P2）。
3. **四个问号按钮换行成 3+1**：`听懂了吗? / 测一下? / 跟一下?` 一行，`读一下?` 掉到第二行。
   规格：固定 2×2 网格，或统一为一行图标+标签的分段控件。另外四个都用问号结尾，
   语气一致但信息量低——`跟一下?` 与 `读一下?` 从字面看不出区别。建议改为
   动作名 + 一行说明的形式。
4. **视频上的字幕 token chip 有浅灰底**：亮色块盖在画面上，是"外壳发光"的典型。
   规格：底改为 `overlaySurfaceSoft`（已有 token，`#b8101715`），
   当前词才用 `overlaySignal` 发光。
5. **底部 `Timeline 资源已刷新`** 常驻占一行。规格：走 §3.8 的反馈分级，
   info 级用短暂 toast，不占布局。
6. 右栏 5 个 tab 全是无标签图标——同 C3 的问题换了地方。至少在
   `sidePanelTabLabels`(520) 以上显示文字。

### 3.8 横切：反馈分级（[#10](https://github.com/ichthyoplanktonzyh/listen-app/issues/10)）

现在 `setStatus` 是单通道，info / success / error 视觉上无差别（截图 7 底部那行、
截图 2 的红色异常都是它的产物）。规格：

| 级别 | 呈现 | 时长 |
| --- | --- | --- |
| info | 底部短暂 toast，muted 色 | 2.4s 自动消失 |
| success | 同上，青色图标 | 2.4s |
| error | 常驻条 + 可关闭 + 可展开详情 | 手动关闭 |

**异常详情只在 error 的"展开详情"里出现，绝不进主体内容流。**

---

## 4 · 参考产品与具体借鉴点

不是"抄界面"，是每条对应一个已经被验证的解法：

| 产品 | 借鉴点 | 用在哪 |
| --- | --- | --- |
| **ChatGPT Advanced Voice** | 大厅极简：一个大按钮 + 一行声音选择，设置全部藏在二级 | §3.1 对话大厅 |
| **Granola / Fathom** | 会话列表用「时间 + 时长 + 轮数」，标题是事后摘要不是首句；会后 debrief 是独立的一屏而非聊天记录尾巴 | §3.1、闭环回流（审计 D6） |
| **Linear** | 暗色下靠 1px 边框而非亮度分层；状态永远是描述性词不是枚举；键盘优先 | §1.4 表面层级、§3.8 |
| **Readwise Reader** | 高亮/生词的左侧色条状态语言（而非图标），列表行密度 | §3.5 三态环改色条 |
| **Anki / Mochi** | 复习卡单卡居中、评分档描述性；间隔预览就在按钮上 | 复习页（[#17](https://github.com/ichthyoplanktonzyh/listen-app/issues/17)） |
| **Language Reactor** | 视频上字幕 token 的克制处理：默认无底色，只有 hover/当前词才提亮 | §3.7 字幕 chip |
| **Things 3** | 外壳极静：工具栏图标细、无边框、悬停才显形 | §3.6 / §3.7 AppBar |
| **Apple 播客** | macOS 原生的库页密度与卡片节奏 | 首页媒体库 |

**明确不参考**：Duolingo 及一切连胜/徽章/庆祝动效——宪章 P3「在场，但不催促」
与 P4「不是讨好的玩具」已经把这条路封死。

---

## 5 · 切片排产

按「先立规矩，再改单屏」排。每片一个分支一个 PR。

| 片 | 内容 | 依据 | 规模 |
| --- | --- | --- | --- |
| **S1** | 四条新纪律测试 + `ListenIconSize` / `ListenPadding` token 落库（**只加 token 和测试，不改屏**，测试先标 `skip` 并列出违规清单） | §1.1/1.2、§2 | 小 |
| **S2** | 全量迁移：图标尺寸、EdgeInsets、列宽、`headline*` slot。逐文件机械替换，去掉 S1 的 skip | §1.1–1.3、§2 | 中，无设计决策 |
| **S3** | **教练回声条修复**（刻度改已评估、unassessed 改虚线槽、删说明句、去掉三层套娃） | §3.4 | 小，收益最大 |
| **S4** | **对话大厅重做** + 会话标题/状态文案 + 舞台按钮降权 | §3.1、§3.2 | 中 |
| **S5** | **转写失败态**（异常永不进内容流）+ 反馈分级 `setStatus` 拆分 | §3.3、§3.8 | 中 |
| **S6** | i18n 收口：`personal_expression_screen` / `realtime_conversation_panel` / `manual_timeline_review_dialog` 接入 `l.text`，加 CJK 字面量禁令测试；修 `listeningInbox` 中文值 | [#7](https://github.com/ichthyoplanktonzyh/listen-app/issues/7)、§2 | 中 |
| **S7** | 词汇本收口：chip 溢出、词头去重、8 按钮改分段控件、三态环改色条 | §3.5 | 中 |
| **S8** | 播放器：文件名清洗、浮动按钮不遮挡、四问号按钮网格、字幕 chip 底色、tab 标签 | §3.7 | 中 |
| **S9** | 我的表达：搜索框对齐、文本清洗、空态引导 | §3.6 | 小 |
| **S10** | Golden 视觉回归基建（[#12](https://github.com/ichthyoplanktonzyh/listen-app/issues/12)），给 S3–S9 的成果上网 | §0 | 中 |

**建议顺序：S1 → S3 → S4 → S5 → S2 → S6 → S10 → S7/S8/S9。**

理由：S1 立规矩但不动屏，风险为零；S3 收益最高且改动最小（一个刻度公式）；
S4/S5 是 owner 已经点名的两处；S2 是纯机械迁移，放在设计决策之后做，避免迁移完
又因设计改动重迁；S10 放在主要视觉改动落地后，golden 才有意义。

---

## 6 · owner 裁决记录

### 已裁决

1. **`Listening Inbox` 中文界面显示英文 = 漏译**（owner 2026-07-28）。
   [localization.dart:2477](../lib/localization.dart:2477) 的 zh 值被写成了英文原串，需修。
   归 S6。
   > 遗留：同类术语还有 `Timeline`、`provider`、`Whisper` 等。建议 S6 顺手立一份
   > 术语表，标明哪些是保持英文的产品专名——否则每次都要重新讨论。此项未裁决，
   > 但不阻塞 S6。

### 已判定为超出前端范围（owner 2026-07-28，不予处理）

2. ~~assistant 回复语言~~：截图 2 里 AI 用中文回复。owner 判定该部分尚处早期设计
   阶段，且不属前端职责。**本文件不再跟踪。**
3. ~~功能词入库~~（`the` / `of` / `a` / `to` 出现在词汇本）：同上，早期设计、
   非前端问题。**本文件不再跟踪。**
   > 注意：§3.5 第 5 条曾建议"呈现层加默认筛选"，据此裁决**撤销该建议**——
   > 采集口径的问题不应由呈现层兜底。
