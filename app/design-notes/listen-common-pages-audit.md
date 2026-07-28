# listen · 五常用页现状审计(#70 Phase 0)

> 母 issue:[#70](https://github.com/ichthyoplanktonzyh/LLPlayerNext/issues/70)。
> 判据只有两个:宪章五原则(`listen-design-charter.md`,记 P1–P5)与产品核心论点
> (输入/输出四通道闭环 + gap-(c) 跨端差异分析,记 T)。
> 写法要求:每条痛点**可指认**(file:line)、**可证伪**(给出复现/反驳路径)。
> 不做审美点评;「看起来不够好看」不算痛点,「控件撒谎 / 核心论点无家 / 违反某原则」才算。
>
> 审计基线:main @ `94c8357b`(#47 画像已合并)。

## 0 · 判据速记

| 记号 | 内容 |
| --- | --- |
| P1 | 暗,但不是黑 |
| P2 | 退后,让内容发光(外壳安静;发光的必须是内容) |
| P3 | 在场,但不催促 |
| P4 | 诚实的仪器,不是讨好的玩具(精确、描述性、从不作假——也意味着**不是 debug 输出**) |
| P5 | 永远做减法(降低疲劳、一次只讲一件事) |
| T | 四通道闭环 + gap-(c) 是产品命脉,UI 要让它可见、可达 |

## 1 · 横切痛点(五页共有,子刀里逐页收)

### C1 · AlertDialog 承载核心动线 【P2 / P5 / T】

产品最核心的仪表全部塞在模态弹窗里,而弹窗在这套设计语言里应该只配承载「确认/输入一件小事」:

- 语义搜索:620×520 弹窗([vocabulary_screen.dart:261](apps/desktop/lib/screens/vocabulary_screen.dart:261))
- **产出差距(gap-(c) 半边天)**:弹窗([vocabulary_screen.dart:640](apps/desktop/lib/screens/vocabulary_screen.dart:640))
- **跨通道复习(gap-(c) 另半边)**:弹窗([vocabulary_screen.dart:743](apps/desktop/lib/screens/vocabulary_screen.dart:743))
- 投影审计:弹窗([vocabulary_screen.dart:797](apps/desktop/lib/screens/vocabulary_screen.dart:797))
- **写句练习(写通道的全部练习动线)**:弹窗([personal_expression_screen.dart:368](apps/desktop/lib/screens/personal_expression_screen.dart:368))
- 教练证据下钻:弹窗([coach_dashboard_screen.dart:301](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:301))

证伪路径:若认为弹窗承载没问题,请回答——为什么词汇本的详情页(同为下钻)是页内 master→detail,而比它更核心的 gap-(c) 反而是弹窗?现状没有一致的层级规则。

### C2 · 原始枚举 / 内部值直出 【P4】

「诚实的仪器」被实现成了 debug 输出。可指认清单:

- `value.status · N sources · 模型指纹前 8 位`([vocabulary_screen.dart:288-290](apps/desktop/lib/screens/vocabulary_screen.dart:288))
- 相似度 `0.xxx` 三位小数裸数([vocabulary_screen.dart:368](apps/desktop/lib/screens/vocabulary_screen.dart:368))
- 跨通道候选四通道结论以 raw 字符串中点拼接([vocabulary_screen.dart:758-762](apps/desktop/lib/screens/vocabulary_screen.dart:758))——**这是产品核心论点的数据,呈现规格却是最低的**
- `attempt.assistance · attempt.selfAssessment` raw 枚举([personal_expression_screen.dart:579](apps/desktop/lib/screens/personal_expression_screen.dart:579))
- `item.sourceKind · item.id` 内部 UUID 给用户看([coach_dashboard_screen.dart:318-320](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:318))
- `session.status` raw([realtime_conversation_panel.dart:599](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:599))
- 时间戳 `toString().substring(0, 16)`([coach_dashboard_screen.dart:80-85](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:80)、[:322-326](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:322))

### C3 · 外壳不安静:AppBar 图标堆 【P2 / P5】

词汇本首页 AppBar 并列 6 个动作([vocabulary_screen.dart:1407-1481](apps/desktop/lib/screens/vocabulary_screen.dart:1407)):狩猎、语义搜索、产出差距、跨通道复习、**重建索引**、导入导出。核心动线(gap-(c))与维护工具(reindex)平级、全部纯图标。可证伪:让一个没读过代码的用户指出哪个图标是「跨通道复习」(`Icons.hub_outlined`),做不到即成立。

### C4 · 内容列宽各自为政,断点 token 零使用 【P5(呼吸感无标准)】

`ListenBreakpoints` 已存在(#47 落库),但**五页屏幕无一引用**(grep 验证:引用者只有布局层与 capability_viz)。各页硬编码:词条详情 780([vocabulary_screen.dart:1490](apps/desktop/lib/screens/vocabulary_screen.dart:1490))、复习卡 680([review_queue_screen.dart:197](apps/desktop/lib/screens/review_queue_screen.dart:197))、对话 760([realtime_conversation_panel.dart:118](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:118))、表达弹窗 600/640、教练全宽无上限([coach_dashboard_screen.dart:69](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:69)——超宽窗口下指标卡 Wrap 会摊成一整行)。

### C5 · 文案三套制度(记录在案,处置归 #21,不动)

我的表达全页硬编码中文;对话面板全页硬编码英文;其余三页走 `l.text()`。i18n 本身 Out(#21 暂缓),但**同一 app 三种制度**是 Phase 1 设计稿排版时必须知道的事实(文案长度不可预估)。

### C6 · #47 图形语言止步于画像,未下沉到动线 【T / P2】

罗盘/回声条/三态环(`capability_viz.dart`)只活在教练画像区和词条环。而最该用它的地方全部还是文字:跨通道候选(C2 第三条)、复习卡的「哪个通道在被训练」(下 R2)、对话 Live 态(下 D2)。一套图形语言若只当封面插图,等于没有图形语言。

## 2 · 逐页审计

### 2.1 词汇本(1705 行 + 详情视图 1863 行)

**先说立得住的**:第二解码器切片播放(音频焦点独占,[vocabulary_screen.dart:419](apps/desktop/lib/screens/vocabulary_screen.dart:419))、切片键盘导航(空格/左右,[listening_dictionary_entry_view.dart:545-570](apps/desktop/lib/widgets/vocabulary/listening_dictionary_entry_view.dart:545))、语速排序不作假(测不出的沉底而非编造,[listening_dictionary_entry_view.dart:316](apps/desktop/lib/widgets/vocabulary/listening_dictionary_entry_view.dart:316))、#47 词条环已换装。这些是资产,重设计要继承。

- **V1 · 能力筛选静默失效 【P4,最可证伪的一条】**
  通道 chip(reading/listening/speaking/writing)在「全部」评估档下点击**只换高亮、不换列表**:
  [vocabulary_screen.dart:1589-1597](apps/desktop/lib/screens/vocabulary_screen.dart:1589) 的 onSelected 只在
  `assessment != null` 时 `_load()`,且 [:484](apps/desktop/lib/screens/vocabulary_screen.dart:484) 在
  assessment==null 时把 capability 传 null。复现:开词汇本(默认「全部」),点「speaking」——列表纹丝不动。
  代码注释说这是有意设计,但 UI 上是一个**长得像筛选器、半数时间不筛选**的控件。
- **V2 · gap-(c) 无常驻面 【T,本页最重】**
  产品核心论点的两个仪表(产出差距、跨通道复习)= 两个无名图标 → 两个弹窗(C1/C3 已指认)。
  用户「看见自己的跨端差异」的动线是:进词汇本 → 猜中 6 图标之一 → 读 raw 字符串弹窗。
- **V3 · 语义搜索弹窗混装管理员操作 【P5】**
  install/rebuild/disable/uninstall 与搜索框同一弹窗([vocabulary_screen.dart:293-329](apps/desktop/lib/screens/vocabulary_screen.dart:293))。「用」与「装」是两个用户时刻。
- **V4 · 详情页一根 ListView 串 8 段 【P5】**
  建议横幅 → 能力编辑 → 证据历史 → 内容编辑 → 义项夹 → 我的输出 → 切片区 → 图书馆搜索,
  单列平铺([listening_dictionary_entry_view.dart:371-](apps/desktop/lib/widgets/vocabulary/listening_dictionary_entry_view.dart:371)),无段落导航;「一次只讲一件事」在这页是「一次全讲」。
- **V5 · master/detail 同 Scaffold 变身 【P2】**
  详情打开时 AppBar 原地换标题、换按钮组([vocabulary_screen.dart:1400-1483](apps/desktop/lib/screens/vocabulary_screen.dart:1400)),外壳不安静——每次进出详情,顶栏 6 个控件集体跳变。
- **V6 · 详情打开串行 4 个请求 【体感】**
  details → suggestions → 词典音频 → 产出语料,顺序 await([vocabulary_screen.dart:496-551](apps/desktop/lib/screens/vocabulary_screen.dart:496)),无骨架屏。后三者互不依赖,却要排队。

### 2.2 我的表达(608 行)

- **E1 · 删除无确认 【P4,一行可证伪】**
  详情页底部「删除这个表达」直接 `deleteSentencePattern`([personal_expression_screen.dart:594-604](apps/desktop/lib/screens/personal_expression_screen.dart:594)),连版本历史一起消失,无任何确认。全仓其他破坏性动作(如教练毕业)都有确认弹窗,唯独这里没有。
- **E2 · 写通道的核心练习动线是一个表单弹窗 【T / P5】**
  「写自己的句子」= AlertDialog + 响应文本框 + 两个 Dropdown([personal_expression_screen.dart:360-503](apps/desktop/lib/screens/personal_expression_screen.dart:360))。
  辅助梯度(看完整模板→只看槽位→只看关键词→隐藏模板)是**支架渐撤**教学法,是这页最有产品价值的概念,却被实现为一个默认停在最高辅助档的下拉框——系统从不建议降档,梯度沦为元数据标注。
- **E3 · 用户自己的语言不发光 【P2】**
  列表卡把用户的模板文本当 subtitle 三行截断([personal_expression_screen.dart:297-310](apps/desktop/lib/screens/personal_expression_screen.dart:297));宪章明言发光的该是「用户自己的语言」,这页反着做。
- **E4 · 使用历史 raw 枚举直出**(C2 已指认)。
- **E5 · 导出成功零反馈 【P4 小项】**
  [personal_expression_screen.dart:75-86](apps/desktop/lib/screens/personal_expression_screen.dart:75) 写完文件即结束,无成功/失败提示。

### 2.3 复习(593 行)

**先说立得住的**:单卡居中、一次一事,是五页里最贴 P5 的骨架;三档评分文案(missed/fuzzy/got)描述性、不愧疚,贴 P3/P4。呈现层重设计应保骨架、换血肉。

- **R1 · 音频可用性绑死主播放器 【T,本页最重】**
  `_canPlay` 要求 `currentMediaId == entry.source.mediaId`([review_queue_screen.dart:125-129](apps/desktop/lib/screens/review_queue_screen.dart:125))——复习卡的切片只有在「主播放器恰好载着同一媒体」时才能放。复现:不载媒体直接进复习,所有卡显示「clip unavailable」,听力复习队列的核心可供性整队死亡。而词汇本早已示范第二解码器方案(V 页资产)。呈现层修复,不碰 #10/#11 语义。
- **R2 · 卡面与图形语言零血缘 【C6 实例】**
  卡是通用 Material Card,kind 图标是库存 Material 图标([review_queue_screen.dart:476-483](apps/desktop/lib/screens/review_queue_screen.dart:476));这张卡在训练哪个通道、该词条的三态处境,画像语言(环/回声条)一概缺席。
- **R3 · delayed_retelling 卡面塌陷 【可证伪】**
  该卡型 prompt 区是 `SizedBox.shrink()`([review_queue_screen.dart:367](apps/desktop/lib/screens/review_queue_screen.dart:367)),卡面只剩两个按钮悬空。复现:队列里放一张延迟复述卡即见。
- **R4 · 进度不可见 【P4 弱项】**
  AppBar 只有剩余数([review_queue_screen.dart:56-69](apps/desktop/lib/screens/review_queue_screen.dart:56));本轮进行到第几张、完成比,仪器没读数。

### 2.4 对话(面板 672 行 + 控制器 1204 行)——owner 已定:完全重designs

owner 定位是「完全复刻 GPT Live 的全屏沉浸实时语音」。现状与目标的差距不是量变:

- **D1 · 一屏三职 【P2 / P5】**
  配置(provider 下拉 + Add provider 按钮)、对话(气泡流)、历史(会话列表)同一根滚动列([realtime_conversation_panel.dart:113-296](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:113))。进入「对话」第一眼看到的是表单。
- **D2 · 说/听状态 = 一枚 Chip 【C6 极端实例】**
  live 全部状态可视化是 icon+文本 Chip([realtime_conversation_panel.dart:176-187](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:176)、[:342-359](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:342))。GPT Live 的灵魂是大形动效——听/想/说三态的形变;现状无形、无动、与 wordmark/画像图形无血缘。
- **D3 · live 中全文气泡堆积 【P5 反例】**
  实时对话过程中完整聊天气泡持续追加滚动([realtime_conversation_panel.dart:200-203](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:200)),逼用户边说边读;且 provider caption(只是 guidance)与最终本地转写在主体文本上同视觉权重,仅靠 labelSmall 脚注区分([:607-672](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:607))。宪章「降低疲劳」在最需要它的场景缺席。
- **D4 · API key/workspace/region 表单长在对话面板里 【P2】**
  [realtime_conversation_panel.dart:385-572](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:385)。设置域的东西,应迁走。
- **D5 · 打断零可供性**:全 672 行没有任何 barge-in 的 UI 反馈或提示;用户不知道能不能插话。
- **D6 · 闭环的「回」不可见 【T】**
  对话后处理(本地转写 → 词汇画像回流)只有一行小字「N learner turn(s) are being transcribed locally」([realtime_conversation_panel.dart:204-208](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:204));对话结束后没有任何「这场对话给你的画像带来了什么」的呈现。这是四通道闭环在说通道上的断口。
- **D7 · 进出动线通用路由**:`MaterialPageRoute`([main.dart:948-972](apps/desktop/lib/main.dart:948)),与 #25 沉浸态无衔接。
- **可继承的资产**:controller 的 phase/activity 状态机语义完备(idle/connecting/live/draining/postProcessing/done/failed × listening/learnerSpeaking/thinking/assistantSpeaking),重设计可全量复用;PopScope 丢弃确认动线([realtime_conversation_panel.dart:302-335](apps/desktop/lib/widgets/panels/realtime_conversation_panel.dart:302))是对的;「provider caption 只是 guidance、本地 Whisper 才是 learner output」的诚实分层(P4)必须保留。

### 2.5 学习教练(436 行)

**先说立得住的**:#47 画像区;通道卡只在有证据时渲染([coach_dashboard_screen.dart:102-104](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:102))是好的克制。

- **K1 · 起步清单不可勾 【P4,一眼可证伪】**
  `radio_button_unchecked` 图标暗示可勾选,实为纯展示 ListTile([coach_dashboard_screen.dart:134-141](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:134))。长得像 checklist 的东西不能 check,是控件撒谎。
- **K2 · 证据弹窗直出内部 UUID**(C2 已指认)。
- **K3 · drill-down 区是三层卡片套娃 【P5】**
  指标卡(210px 定宽 Card)套在通道 Card 里套在 ListView 里([coach_dashboard_screen.dart:398-436](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:398));建议卡 subtitle 三值拼接([:121](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:121))。
- **K4 · 画像与下钻是两个世界 【T】**
  画像展示 gapCount 但不可点;从「画像上看到 N 个跨通道缺口」到「看这些缺口是什么」没有动线——跨通道复习入口只在建议卡恰好出现时存在([coach_dashboard_screen.dart:211-235](apps/desktop/lib/widgets/coach/coach_dashboard_screen.dart:211))。仪表读数与仪表下钻断连。

## 3 · 核心论点对照:闭环在 UI 上的地图

把四通道闭环 + gap-(c) 落到现状页面上,得到的地图是:

| 环节 | 现状位置 | 规格 |
| --- | --- | --- |
| 输入证据(听/读) | 词条详情证据历史、教练指标卡 | 页内区块 |
| 输出证据(说/写) | 我的表达、对话、词条详情「我的输出」段 | 页内区块/弹窗 |
| **gap-(c) 分析** | 产出差距弹窗 + 跨通道复习弹窗 + 教练建议卡(时有时无) | **弹窗 + raw 字符串** |
| 闭环回流(对话→画像) | 一行小字 | 几乎不可见 |

结论:**闭环的每一环都存在,但「环」本身没有在任何一页被画出来;gap-(c) 作为产品最大差异化,呈现规格反而全场最低。** #47 画像是总览摘要,不是动线;五页重设计的共同任务是给 gap-(c) 一个常驻的家,并让各页动线能指回它。

## 4 · 宪章修订点(单列,交 owner 裁决,本审计不动宪章)

1. **P2 的 CustomPaint 光源清单已过时**:「全仓仅有的 3 处」在 #47 后已不成立(`capability_viz.dart` 的罗盘/回声条/三态环即是新光源),对话 Live 大形还会再加。建议改为宪章维护一份「光源清单 + 准入标准(必须是内容才能发光)」,而非写死数量。
2. **宪章没有「舞台态」规则**:全屏沉浸 Live(对话页目标形态,亦涉 #25)下,「安静的房间」如何退成「只剩一个发光大形的暗场」、实时字幕如何克制,P1–P5 都没有直接答案。对话页设计稿会先给一版操作性定义,是否升格进宪章由 owner 裁决。
3. **内容列宽 token 缺席**:`ListenBreakpoints` 只管断点不管列宽,五页各自硬编码(C4)。标准内容列宽(阅读列/卡片列)归 #26/#32 的 token 体系还是本 issue 顺手立,请 owner 裁决。

## 5 · 严重度排序(Phase 1 排产依据)

| 序 | 痛点 | 页 | 理由 |
| --- | --- | --- | --- |
| 1 | D1–D7 整页 | 对话 | owner 已定完全重设计;闭环说通道断口 |
| 2 | V2 + C1/C3 | 词汇本 | gap-(c) 无家,核心论点呈现规格全场最低 |
| 3 | K4 + K1/K3 | 教练 | 画像→下钻断连,画像语言止步封面 |
| 4 | R1 + R2/R3 | 复习 | 核心可供性大面积死亡(呈现层可修,不碰 #10/#11) |
| 5 | E1–E3 | 我的表达 | 体量小,痛点清楚,可能一稿微调即够 |

Phase 1 按此顺序出探索稿:**对话页单独成稿(2–3 方向)先行**,其余四页按痛点轻重出方向(复习/表达预计各一稿微调,词汇本/教练各 1–2 方向)。
