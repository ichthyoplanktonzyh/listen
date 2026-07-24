# #70 Phase 2 · 前端拆刀清单

> 五页设计稿已全部出稿+拍板(Phase 1),本文件把拍板落成**可逐刀转交新会话**的实现清单。
> 每刀自包含:依赖 / 涉及文件 / 范围 / 验收。新会话接手一刀时,先读本节 + 对应设计稿即可,
> 无需本设计会话的上下文。

## 铁律(每刀都继承,不再重复)

- **呈现≠语义**:所有后端判定(筛选/评估/建议/调度/卡片生成/四通道)零改动,前端只呈现。
- **每 commit 同步 CHANGELOG**;`flutter analyze` 零告警;全量测试绿(基线 636)。
- **独立分支 + 独立 worktree**(共享 checkout 撞过 HEAD 竞态)。
- 动效走 `ListenMotion`,禁 bounce,`prefers-reduced-motion` / `MediaQuery.disableAnimationsOf` 全降级。
- 图形一律用 `widgets/common/capability_viz.dart` 家族的语言,raw 枚举/UUID 直出一律死刑。
- **CI 当前停摆([#75](../../issues/75)),合并靠本地 `flutter test` + `flutter analyze` 兜底。**

## 设计稿索引(每刀的规格来源)

| 页 | 稿 | 拍板方向 |
| --- | --- | --- |
| 对话 | `listen-live-conversation.html` | B 回声水面 |
| 词汇本 | `listen-vocabulary-redesign.html` | A 工作台 |
| 教练 | `listen-coach-redesign.html` | A 画像即导航 |
| 复习 | `listen-review-redesign.html` | anki 完全接入 |
| 我的表达 | `listen-expression-redesign.html` | A 写作台 |
| 宪章 | `listen-design-charter.md` | 舞台态节 + 月白/月蓝色表 |

---

## ✅ 两个前置决策(owner 已定 2026-07-24)

1. **内容列宽 token 归属**(审计 C4)= **归 `ListenBreakpoints`**。列宽阈值与 `vocabularyTwoPane`
   断点同家,不新建文件——S0 在 `theme/breakpoints.dart` 建列宽 token,替换五页硬编码宽度。
2. **CustomPaint 光源清单**= **改「光源家族」不带硬数字**。宪章原则 2 已改为
   「`CustomPaint` 只用于内容发光的光源家族(词级高亮/连读带/节奏带/能力画像/对话回声水面…)」。
   S7 落地回声水面时**无需再改这句**(已一次性改到位),只需确认新光源画的是内容而非点缀。

---

## 波次 A · 基建(前置,多刀依赖,先做)

### S0 · 主题加色 + 列宽 token
- **依赖**:前置决策 1、2 已定(见上)。无后端依赖。
- **范围**:
  - `theme/listen_theme.dart`:加**月白 `#c7d4cf`**(对方的声音)、**月蓝 `#6db3ff`**(复习 new 态);
    进 `theme_palette_discipline_test` + 对比度校验(暗底 AA)。
  - `theme/breakpoints.dart`:内容列宽 token(**归 `ListenBreakpoints`**,前置决策 1),
    替换五页硬编码宽度(C4)。
  - `theme/breakpoints.dart`:加 `vocabularyTwoPane` 断点(词汇本双栏/单列切换阈值)。
- **验收**:palette 纪律测试含两新色;至少一页接上列宽 token 作示范;analyze 零告警。
- **为何先做**:S3(词汇本双栏需断点)、S7(回声水面需月白)、S11(复习需月蓝)都依赖它。

---

## 波次 B · 纯前端页面(不依赖后端,可并行/任意序)

> realtime 与既有后端都在;这四刀现在就能落。跨刀依赖只有一条:S2 的环心跳转目标依赖 S3。

### S1 · 我的表达写作台
- **依赖**:S0(可选,列宽 token)。无后端。稿:`listen-expression-redesign.html`。
- **范围**(`screens/personal_expression_screen.dart` 608 行):
  - **弹窗死刑**:`_write` 的 AlertDialog(:360-503)→ 页内写作台。
  - **梯子**:四阶 assistance(`template_visible`/`slot_hints`/`keywords`/`no_text`)从 Dropdown
    变成可见梯子,月白→青光迁移(与对话页 B 同宗),当前档高亮 + 「用过 N 次/还没试过」
    (既有 attempts **前端聚合**,不新增后端语义;历史空则只显当前档不编造)。
  - **降档轻提示**:上次某档得「表达自然」→ 提示试更少帮助,**只提一次、可忽略、绝不自动降**。
  - **E1** 删除确认(明说牵连 N 版本 + M 使用记录,:594);**E3** 模板文本升主角 + 最近一次
    你写的句子以青出现(:297-310);**E5** 导出成功/失败反馈(:75-86);**E4** 历史行梯子微条替枚举。
- **验收**:梯子四阶光比例单调;删除有确认;导出有反馈;attempt 仍走 `recordPersonalExpressionAttempt(channel=writing)`。

### S2 · 教练画像即导航
- **依赖**:**S3(环心 gap 跳转目标=词汇本差距面路由需先存在)**。无后端。稿:`listen-coach-redesign.html`。
- **范围**(`widgets/coach/coach_dashboard_screen.dart` 436 行):
  - **画像三热区**(K4):罗盘象限→页内通道证据段联动;**环心 gap 数→词汇本差距面**
    (走既有 `cross_modal_review` destination);回声条→缺口来源高亮。
  - **证据行**(K2):快照原文主体 + 相对时间 + 来源可用性人话,**UUID 死刑**;下钻**行内展开**
    (弹窗死刑);指标卡套娃拍扁为对齐行(K3,:398-436)。
  - **起步清单**(K1):`radio_button_unchecked`(:134)→ **状态行**(已就绪=青点,未就绪=压暗+入口按钮)。
  - 章节定序=画像→下一步→通道证据→素材架;建议卡改「动词开头一句话+去」(:121 三值拼接死刑);
    `features` 段降入工具/关于层级;趋势微条**仅当后端有按日序列才做**,无则只留读数(不造数)。
- **验收**:三热区可点且不离页(除环心跳页);无 UUID 上屏;起步不再用 radio 图标撒谎。

### S3 · 词汇本工作台(刀1:差距面+外壳+筛选)
- **依赖**:S0(`vocabularyTwoPane` 断点 + 列宽 token)。无后端。稿:`listen-vocabulary-redesign.html`。
- **范围**(`screens/vocabulary_screen.dart` 1705 行 + `widgets/vocabulary/*`):
  - **双栏工作台**:左=列表+透镜,右=活动面;**差距仪表间=右面默认页**(进门第一眼=gap-(c));
    窄窗(低于 `vocabularyTwoPane`)退化单列(B 形态)。
  - **差距面**:跨通道候选 + 产出差距**合并一张清单**(两后端来源并排,语义不动);
    候选行=词条名+**微型回声条**(raw 四通道字符串死刑,复用 `capability_viz`)。
  - **外壳收纳**(C3/V5):AppBar 只留搜索/狩猎/工具溢出菜单;**语义搜索并入主搜索框**
    (可用时出「语义」开关)、索引管理归工具菜单;AppBar 永不变身。
  - **筛选修正**(V1):通道 chip **永远生效**(选通道即换词条环视角;评估档未选时查询仍不加
    capability 过滤——呈现层修控件撒谎);评估三档用三态色点作前缀。
- **验收**:进入即见差距面;点词条右面变详情列表不消失 AppBar 不变;通道 chip 点了永远有回应;
  提供 `cross_modal_review` 可落地的差距面路由(供 S2 跳转)。

### S4 · 词汇本详情分段(刀2)
- **依赖**:S3(详情面存在)。无后端。稿同上。
- **范围**:词条详情按**身份卡 + 锚点段落导航**重排(证据/切片/我的输出/义项/笔记,V4);
  身份卡先渲染,装饰数据(建议/词典音频/产出)**分段各自 loading**(V6 串行等待死刑)。
  切片播放器/键盘导航原样继承。
- **验收**:五段可跳(锚点非 tab);身份卡不被任一慢数据阻塞。

### S5 · 复习卡面呈现修复(不依赖后端的部分)
- **依赖**:S0(可选)。**无后端**(4 档评分是纯前端:`ReviewRating` 后端本已 4 档,前端只暴露 3)。
  稿:`listen-review-redesign.html`。
- **范围**(`screens/review_queue_screen.dart` 593 行):
  - **R1 音频解绑主播放器**(本页最重):`_canPlay`(:125-129)不再要求 `currentMediaId==entry.source.mediaId`;
    用词汇本已示范的**第二解码器**方案播切片(无媒体进复习不再整队 clip unavailable)。
  - **4 档评分**:三档(:missed/fuzzy/got)→ **四档**(Again/Hard/Good/Easy,后端已支持)。
  - **R3** delayed_retelling 卡面塌陷(prompt 区 `SizedBox.shrink()` :367)修复。
  - **R4** 进度可见(:56-69 只有剩余数 → 本轮第几张/完成比)。
  - **R2** 卡面接图形语言:kind 库存图标 → 该卡训练哪个通道 + 词条三态处境(`capability_viz`)。
- **验收**:不载媒体直接进复习,切片可播;四档评分;delayed_retelling 卡面不塌;进度有读数。
- **注**:四态色(new 月蓝)/间隔预览/牌组/导入导出**不在本刀**——那些依赖后端(见波次 D)。

---

## 波次 C · 对话页(realtime 后端已在;内部有依赖链)

> 稿:`listen-live-conversation.html`。controller 状态机
> (idle/connecting/live/draining/postProcessing × listening/learnerSpeaking/thinking/assistantSpeaking)
> **全量复用**;PopScope 丢弃确认、「provider caption=guidance / 本地 Whisper=learner output」
> 诚实分层**必须保留**。

### S6 · 舞台态 shell
- **依赖**:S0(月白)。稿舞台态节 + 宪章舞台态。
- **范围**:全屏暗场容器(外壳全退,底色压 `ground2`);**门厅→舞台两段进场**
  (话题/自由对话选择留门厅,provider 管理迁走见 S10);退出=Esc 丢弃确认 + 结束熄灯;
  **不联动 macOS 系统全屏**(F 仍归播放器,#25 边界不动);进出动线替 `MaterialPageRoute`(main.dart:948)。
- **验收**:进入是舞台不是表单(修 D1);退出确认在;窗口内舞台,不抢系统全屏。

### S7 · 回声水面可视化
- **依赖**:S0(月白)、S6(shell)。宪章光源清单已改「光源家族」(前置决策 2,无需再动宪章)。
- **范围**:屏幕中线水面;四态形变(listening 微澜/learnerSpeaking 青波升起/thinking 涟漪/
  assistantSpeaking 月白落下);**打断**=你开口月白被水面吸走(≤90ms 响应)。
  新 CustomPaint,归 `capability_viz` 家族语言。修 D2(状态=一枚 Chip)、D5(打断零可供性)。
- **验收**:四态视觉可辨;打断有即时退让反馈;reduce-motion 降级。

### S8 · 余音字幕 + 诚实分层
- **依赖**:S6。
- **范围**:live 中**单行余音字幕**(对方当前句 provider caption,说完 2.6s 淡出,不留历史不滚动);
  **你的话 live 中完全不上屏**(本地 Whisper 只在结束页);**字幕默认关** + 门厅开关记住选择。
  修 D3(全文气泡堆积 + guidance/最终转写同权重)。
- **验收**:live 中无历史气泡流;字幕默认关;你的实时转写不上屏。

### S9 · 对话结束页回流(闭环的「回」)
- **依赖**:S6;复用 `CapabilityEchoBars`。
- **范围**:结束页三段(本地转写主体 / **琥珀靶子**卡壳处 / 回流读数);水面收窄成静态回声条
  (说通道列);`postProcessing` 转写未完如实显示进度不假装完成。修 D6(回流只有一行小字)。
- **验收**:对话结束有回流呈现;靶子可一键进词汇本/表达;转写中如实报进度。

### S10 · provider 迁设置域
- **依赖**:无(可早做,服务 S6 门厅)。
- **范围**:API key/workspace/region 表单(realtime_conversation_panel.dart:385-572)**迁出到设置域**;
  对话门厅只留「用哪个声音说话」选择。修 D4。
- **验收**:对话面板不再长配置表单;设置域可管 provider;门厅选择生效。

---

## 波次 D · 复习 anki 能力(阻塞于后端,后端交付后启动)

> **前置**:[#72](../../issues/72) FSRS(地基)→ [#73](../../issues/73) .apkg 互通 / [#74](../../issues/74) 查询能力。
> 后端未交付前**不启动本波次**。稿:`listen-review-redesign.html` ④ 节 + 牌组双轨。

### S11 · 卡状态四态 + 间隔预览
- **依赖**:S0(月蓝)、S5(卡面)、**#72 FSRS + #74 state 字段/预览接口**。
- **范围**:卡片四态(new 月蓝/learning-relearning 琥珀/review 青/suspended 压暗)着色与计数;
  **间隔预览**(4 档各自下次间隔)——**接口未就位则隐藏预览**(4 档照常),绝不前端估算。
- **验收**:四态色正确;预览接口在则显、不在则隐;无前端估算。

### S12 · 牌组总览双轨
- **依赖**:**#74 牌组计数**。
- **范围**:总览分两区——**智能牌组**(listen 原生卡按四通道自动分面,#47 罗盘/环)+
  **导入牌组**(anki 原 deck 树,中性图标+due 计数,外来卡不套 #47);通道可作跨两区过滤视图。
- **验收**:两类牌组分区呈现;通道过滤跨两区生效;归组只呈现后端结果。

### S13 · anki 导入导出前端
- **依赖**:**#73 .apkg 双向**。
- **范围**:导入/导出入口;**外来卡呈现**(卡头 badge「来自 anki·无听力增强」,无切片播放器/
  不能影子跟读/不进四通道画像);**导出前保真提示对话框**(明说视频转音频、跳转/影子跟读/
  画像回流不带走,P4)。
- **验收**:导入 anki 卡可复习并标外来;导出弹保真提示;外来卡不假装有 listen 增强能力。

### S14 · custom study + 每日上限
- **依赖**:**#74 临时队列查询 + 上限**。
- **范围**:custom study **四张动词卡**(多学新卡/提前复习/只练某通道/重练遗忘;「按媒体」列 v2)
  每张只触发一次临时队列不改正常调度;每日上限**全局**(v1),达上限措辞按「保护非 KPI」。
- **验收**:四种临时队列各自可用不污染正常调度;上限提示不制造 KPI 焦虑。

---

## 编排建议

- **可立刻开工(后端无关)**:S0 → 然后 S1/S3/S5 并行(教练 S2 待 S3 的差距面路由;S4 待 S3);
  对话 S6→S7/S8/S9,S10 可任意时候。
- **阻塞后端**:S11–S14 等 #72/#73/#74;其中 #72 是 #73/#74 的地基,后端也有内部顺序。
- **owner 定串行还是并行**:Phase 1 是串行(一页一页过设计);Phase 2 实现波次 B 内多刀无强依赖,
  是否仍串行、还是允许并行落代码,请 owner 指示(默认沿用串行=一刀一会话)。

## 刀数小结

| 波次 | 刀 | 阻塞 |
| --- | --- | --- |
| A 基建 | S0 | 前置决策 1/2 |
| B 纯前端 | S1 S2 S3 S4 S5 | 无(S2←S3, S4←S3) |
| C 对话 | S6 S7 S8 S9 S10 | 无(S7/S8/S9←S6) |
| D 复习 anki | S11 S12 S13 S14 | #72/#73/#74 |

共 **15 刀**。波次 A+B+C(11 刀)现在就能推进;波次 D(4 刀)等后端。
