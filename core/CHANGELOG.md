# Changelog

## Unreleased

- 2026-07-28 10:35 CST: S4 词汇本详情分段（refs #82）：词条详情从一根 8 段 ListView 重排为
  **身份卡 + 五段锚点导航**（证据/切片/我的输出/义项/笔记，V4）。锚点非 tab——五段始终同时构建、
  同处一个滚动区，点锚点只滚动不隐藏其他段；活动锚点随滚动反映阅读位置，reduce-motion 下
  滚动与着色降级为瞬时。加载诚实（V6）：`_openEntryById` 不再串行 await 建议/词典音频/产出，
  词条一到就渲染身份卡，三类装饰各自并发加载、各自报 loading，并用请求序号丢弃过期结果；
  发音控件上移进身份卡并有独立等待态。切片播放器与键盘导航（←/→/空格）原样继承。
  顺带把 `_SemanticSearchDialog` 抽到 `widgets/vocabulary/semantic_search_dialog.dart`
  （vocabulary_screen.dart 1942 → 1614 行）。新增 4 个测试（锚点五段、锚点跳转、
  段内状态跨父级重建不丢、慢装饰不阻塞身份卡）；`flutter analyze` 零告警，`flutter test` 654 全绿。

- 2026-07-28 10:20 CST: 实时对话的服务商配置迁入设置域（refs #87 · S10）。地址、区域、
  Workspace、模型与 API 密钥表单从对话面板移到「设置 › 实时语音」，可列出/添加/删除，
  删除需确认；密钥仍是只写、提交后即从输入框清除并由后端存入系统钥匙串，界面不回显。
  对话门厅只剩「用哪个声音跟你说话」一项选择（显示名 · 声音），未配置时给出指向设置的
  出口并在返回后重新读取声音列表。后端判定与 controller 状态机零改动；provider 字幕=
  引导、本地 Whisper=学习者产出的诚实分层保留并在设置页复述。表单控件仍由 State 持有
  并在 dispose 释放（#27），内联后不再有退场动画竞态。

- 2026-07-28 09:43 CST: 修正 issue #98 练习答案评估 baseline（PR #169）：
  以学习语言 profile tokenizer 和无可调阈值的全局 edit-distance 对齐替代位置比较，
  听写保持表层严格，其余现有 bounded practice 可通过带版本 provenance 的 lexical
  provider 接受单 token lemma 等价；provider 故障在写入 attempt/evidence 前显式失败。
  `equivalent` 同步 OpenAPI、Flutter 展示与 contract test，evaluation trace 记录版本、
  evidence class、语言、policy、provider 及等价匹配。移除未生效的 contraction/penalty
  声明，并将 PR 收窄为 `refs #98`，开放题 rubric/meaning-unit/LLM judgment 继续留在 issue。

- 2026-07-28 09:40 CST: 机械拆分词条详情面（AGENT.md「单文件 >1500 行先拆模块」）：
  `listening_dictionary_entry_view.dart` 1863 → 1034 行，证据段、建议横幅、切片卡、语料卡、
  义项弹窗、四通道编辑器迁入新的 `widgets/vocabulary/entry_detail_parts.dart`；`CorpusResultTile`
  经原文件 re-export 保持既有 import 路径。纯搬运，零行为改动（refs #82）。

- 2026-07-28 09:23 CST: 学习教练页改为「画像即导航」（refs #81 · S2）：三热区接线——象限
  和回声条在页内高亮并滚动到对应通道证据段（回声条另标出缺口来源那一侧），环心 gap 数走
  既有 `cross_modal_review` destination 跳词汇本差距面；指标卡套娃拍扁为通道段内的对齐行，
  证据改行内展开（弹窗死刑）并分页「更多」，证据行=快照原文 + 相对时间（悬停出绝对时间）
  + 人话来源，UUID 与 raw 表名不再上屏；起步清单由 radio 图标改为压暗状态点 + 入口按钮
  （后端只发「尚未观察到」的项，故如实只呈现未就绪态）；章节定序=画像→下一步→起步→通道
  证据→素材架，`features` 段降入「工具与状态」；素材轨迹改两点连线 + 人话读数。
  `coachEvidence` 客户端补 limit/offset（后端本已支持）。**趋势微条未做**：后端 CoachMetric
  只有单值、无按日序列，按拍板记录第 3 条不前端造数。后端判定零改动。

- 2026-07-28 09:12 CST: 能力画像（`capability_viz`）新增三热区可供性（refs #81 · S2）：罗盘
  象限、环心 gap 数、回声条各自可接回调，附纯函数 `compassHitTarget` 命中测试、悬停光晕
  （无动效，reduce-motion 无关）与回声条按钮语义。回调全部可选，未接线的调用点（词条环）
  仍是只读画像；后端判定零改动。

- 2026-07-27 11:59 CST: 补全 issue #96 LLM Sense Group 批处理验收：显式
  `batch_id` 状态/取消 API，排队与退避均可协作取消且取消批次不提交伪完整分析；账号作用域
  governor 可配置总 in-flight、启动速率和连接池空闲上限，不同 profile 默认隔离、同账号可
  显式共享。成功句 checkpoint 由 schema v50 持久化并在重启/重跑后只补缺失句；Retry-After
  支持 delta-seconds/HTTP-date 且服务端等待不受本地指数 cap 截短；指标按批次隔离。新增
  多批共享上限、排队取消、持久化恢复、千句并发容量及 Retry-After 回归，更新 OpenAPI 与架构
  说明；不改 Flutter、不运行付费模型测试。

- 2026-07-27 11:26 CST: 将初版账号级 request governor、退避、取消 token、句级 cache 与
  metrics 接入 LLM Sense Group 批处理和 `ApiState`（refs #96）；后续 11:59 条目修正审查发现的
  取消入口、持久恢复、profile 隔离、Retry-After 和验收测试缺口。

- 2026-07-27 11:25 CST: 新增初版 `application::batch_governor` 深模块，建立 semaphore、
  bounded backoff、协作取消、fingerprint cache 与原子指标组件（refs #96）；完整产品接线与
  审查修正见后续同日条目。

- 2026-07-27 10:31 CST: 完成 issue #94 Content Fit v3 后端与契约升级：保留
  meaning/sound 双维，新增词与短语能力、Sense Group、句法深度/依存跨度、
  WPM/停顿/弱读/压缩/chunk/字幕时序特征，输出归一化分数、逐信号贡献、完整
  feature snapshot 与明确 missing-feature coverage；不存在权威 media identity 的复播/
  查词保持 `null`，不再误用 DiagnosisViewed/ListeningCompleted。理解度与评分练习继续
  在线校准并可从新 API 导出为无标签泄漏样本；新增 deterministic threshold search、
  frozen-v2 holdout MAE 对照工具、ADR 0030、OpenAPI/Dart DTO 及 domain/application/
  persistence/HTTP/contract 回归。

- 2026-07-27 09:15 CST: 收紧 Git 与 PR 治理：在项目权威 `AGENT.md` 中统一分支、
  worktree、原子提交、验证、review、squash merge、CI 故障例外和安全清理规则；
  新增 PR 模板；CI 仅对 `main` push 与 PR 运行，并按分支取消过期 run，避免重复消耗
  Actions 额度；PR 的 Rust 严格检查只跑 Ubuntu，macOS/Windows 改为合并到 `main` 后运行。
  GitHub 仓库已开启合并后自动删源分支、关闭 merge commit/rebase merge，仅保留 squash
  merge；清理 13 条失效 worktree 注册和 27 个已合并且未被有效 worktree 占用的远端分支，
  并为 `AGENTS.md` 增加权威入口指针。

- 2026-07-26 18:35 CST: Phase 3.19.2 Backend Runtime Hardening & Interface
  Deepening 完成。全部 HTTP 路由经单一 `ApplicationExecutor` 把同步 repository work 移出
  Tokio async worker，current-thread heartbeat 回归覆盖 sync 与 mixed-async workflow；
  SSE 明确 lag/closed 并在 lag 后继续 retained event。SQLite 333 个 mutex-poison panic
  改为非 poisoning 序列化，保留单连接 transaction locality、5 秒 busy timeout 与默认
  journal/synchronous durability。根 composition 从 1216 行收缩到约 469 行，protected routes
  分成 media-analysis/learning/generative/provider-event 四组，`ApiState` 分成四个 lifecycle
  context。500 响应不再泄漏 SQL/路径/process/secret 细节，JSON completion/error/slow-op
  diagnostics 与 `x-correlation-id` 联结且不记录 token/body。新增 ADR 0029、route/SSE/blocking
  architecture guards、固定 `cargo-deny 0.19.7 --locked` CI；修复 ammonia/crossbeam RustSec，
  升级 jieba-rs 并移除 fxhash。最终 strict low-memory：Rust 709、Flutter 650、Clippy、
  analyze、contracts、cargo-deny 与 diff checks 全绿；`apps/desktop/**` 零编辑。

- 2026-07-26 17:36 CST: 建立 Phase 3.19.2 Backend Runtime Hardening & Interface
  Deepening，固定后端-only 范围与基线：SQLite/Tokio 阻塞执行、SSE lag 恢复、
  route/composition locality、内部错误脱敏、结构化观测、Rust 供应链门和严格收口；明确
  不编辑并行推进的 Flutter 前端、不改变学习权威或既有 HTTP wire contract。

- 2026-07-26 17:49 CST: Phase 3.19.2 首批运行时加固：恢复 Rust formatting 严格门；
  SSE 显式区分 lag/closed，慢消费者跳过丢失通知后继续接收 retained events；新增 concrete
  `ApplicationExecutor` 作为 async transport → sync application 的唯一 blocking seam，并迁移
  media/subtitle 16 条调用，single-worker Tokio heartbeat 回归通过。HTTP repository/
  secret-store/local-process 错误改为 public/internal 双消息，响应不再暴露路径/SQL 细节；
  后端启用 JSON tracing、request completion 与 slow application operation 诊断。api-http
  58 tests、Clippy、quick strict 基线全绿。

- 2026-07-25: 复习后端接入 FSRS-6 默认调度并补齐 Anki 数据通道与查询能力（refs #72
  #73 #74）：schedule 持久化 stability/difficulty/last-review/review-count，稳定派生
  new/learning/review/relearning 四态；旧 heuristic schedule 按原 interval/lapse 原地迁移，
  不清零进度。新增纯只读四档间隔预览、智能通道/导入 deck 树计数、全局每日新卡/复习上限
  与队列裁剪、more-new/review-ahead/channel/forgotten 四种一次性 custom-study 队列。
  `.apkg` 后端支持 schema11/anki21 导入导出、guid 去重、原 deck/字段/tag/revlog/FSRS card
  data (`s`/`d`/`lrt`) 保真、媒体清单落地及原生媒体切片经 ffmpeg 渲染 MP3；导入卡默认无
  Listen 四通道归属/切片增强，导出结果返回媒体与 Listen 独有能力的保真报告。HTTP 文件操作
  走 blocking worker，不占 Tokio 执行线程；卡片生成逻辑与 Flutter 前端均未改动。

- 2026-07-24: S1 我的表达写作台——支架渐撤变看得见的梯子(refs #78 · #70 Phase 2 · B波)。
  呈现≠语义:四档 assistance / 三档自评的后端取值、attempt 记录、版本/来源链路零改动,前端只
  呈现。**弹窗死刑**:`_write` 的 AlertDialog → 页内写作台 `_WritingDeskPage`(独立 route,梯子
  在上、模板区随档在场/退场、你的句子在下,保存仍走 `recordPersonalExpressionAttempt(channel=
  writing)`)。**梯子**:四阶 assistance 从 `DropdownButtonFormField` 变可见梯子,当前档高亮
  (secondary/amber 左框)+ **月白→青光迁移**(月白 `ListenColors.moonWhite`=模板/别人的语言,
  信号青 `colorScheme.primary`=你自己的语言;`moonFlex` 3→2→1→0 单调递减、`signalFlex` 1→2→3→4
  单调递增);「用过 N 次/还没试过」由既有 attempts **纯前端聚合**(仅 writing channel),历史
  为空则只标当前档「你在这」、其余档留白不编造。**降档轻提示**(P3 建议≠判定):最近一次
  writing 得「表达自然」且非最底档 → 一行提示试更少帮助(指向下一阶),**只提一次、可忽略、绝不
  自动降档**(无跨会话偏好存储,「只提一次」落在本写作台会话内,不新增后端)。**E1** 删除加确认
  对话框,明说牵连 N 个版本 + M 条使用记录;**E3** 列表卡重排:模板文本升主角(大字号)、名称
  降眉标、来源降脚注、最近一次你写的句子以信号青上屏;**E4** 使用历史行=梯子微条 + 人话(通道/
  档名/自评/相对时间)替 raw 枚举;**E5** 导出成功/失败 SnackBar 反馈。光比例条沿用回声水面
  月白→青光语义但因数据语义不同(脚手架撤除比例 vs 四通道能力)自建 `_LightMixBar`,未复用
  `CapabilityEchoBars`。动效走 `ListenMotion`(换档/模板切换 base + reduce-motion 归零),圆角
  用 `ListenRadii`、列宽接 `ListenBreakpoints.contentColumnMax`,无颜色/圆角字面量。新增 6 测试
  (页非弹窗+光比例单调+隐藏模板/前端聚合计数/历史空不编造/降档提示三性质/删除确认牵连/E3+E4
  呈现);`flutter analyze` 零告警,全量 645 绿(基线 640,替原 1 个写作弹窗测试为 6 个)。

- 2026-07-24: S3 词汇本工作台——差距面默认页 + 双栏外壳 + 筛选修正(refs #79 ·
  #70 Phase 2 · B波)。词汇本改「方向 A 工作台」,呈现≠语义(筛选/评估/差距来源/四通道
  判定零改动,前端只并排呈现)。**双栏外壳**:左=列表+透镜列(固定 340,元素几何非断点),
  右=活动面;宽窗(≥`ListenBreakpoints.vocabularyTwoPane`=900)双栏、窄窗退化单列(B 形态),
  同一套语义两个断点形态。**差距面=右面默认页**:进词汇本第一眼即 gap-(c);新 `VocabularyGapPanel`
  把两个后端来源(`crossModalReviewGaps` 跨通道候选 + `semanticProductionGapReview`/回退
  `productionGapReview` 产出差距)**并排合并成一张清单**,各自 best-effort 降级为行内提示,
  语义不动;候选行图形复用 `capability_viz` 家族的 **entry-scale `CapabilityRing`**(四通道
  字符串→三态四象限环,raw 字符串死刑)——按 capability_viz 既定分工(echo bars=聚合、mini
  ring=词条尺度),单候选词条正确图形是 mini ring,故未套聚合 echo bars(诚实取舍见 PR)。
  **AppBar 永不变身(C3/V5)**:标题固定、只留狩猎(徽标)+「工具」溢出菜单(导入/导出/重建
  索引/语义索引管理);详情动作(加复习/狩猎/投影审计)迁入详情面自带动作行,不再劫持顶栏;
  两个差距弹窗 + 跨通道弹窗全部替死为差距面;`_SemanticSearchDialog` 转为工具菜单里的语义
  索引管理入口(用/装分离)。语义搜索「用」并入主搜索框(能力可用时出「语义」开关,内联呈现
  hits)。**筛选修正(V1)**:通道 chip 通过 `CapabilityRing.focusChannel` 换词条环视角
  ——点了永远有视觉回应,但评估档未选时查询仍不加 capability 过滤(呈现层不修控件撒谎);
  评估三档保留三态色点前缀。**cross_modal_review 路由**:coach 环心跳转(`openCrossModalReviewOnStart`)
  不再弹窗,直接落到差距面并高亮候选段(供 S2 环心跳转)。窄窗顶置差距仪表条带缺口读数。
  新增 `vocabulary_workbench_test.dart` 5 测试(默认落差距面/点词条切详情不丢列表与 AppBar/
  通道 chip 有回应且不改查询语义/窄窗退化单列/cross_modal_review 落地不弹窗);列宽走 S0
  `contentColumnMax`。`flutter analyze` 零告警,全量 645 绿(基线 640)。
- 2026-07-24: S5 复习卡面呈现修复——切片解绑主播放器 + 四档评分 + 塌陷/进度(refs #80 ·
  #70 Phase 2 · B波)。复习页不依赖后端的呈现层修复,呈现≠语义(调度/卡片生成/rating
  提交零改动)。**R1(本页最重)**:`_canPlay` 不再要求 `currentMediaId==source.mediaId`;
  复习页自持第二解码器 `SlicePlayerController` + `OccurrenceMediaResolver`(走词汇本
  `_playCorpus` 同路径:`source.mediaId`→`readMedia` 取指纹→resolve 本地文件→独立播放),
  与主播放器彻底解耦——不载媒体也能复习整队,修掉整队 clip unavailable;解析失败在卡内
  诚实报错不灰整卡。**四档评分**:三档(again/hard/good)→ 四档,补 `easy`(后端 `ReviewRating`
  enum 本已四档,前端只暴露三档);提交仍是既有 rating 字符串,payload 与后端 snake_case
  一致。**R3**:`delayed_retelling` prompt 区从 `SizedBox.shrink()`(塌陷)改任务说明框
  (源句遮起)。**R4**:AppBar 加进度条 + 「本轮 N/M」读数(数据已有,呈现层)。**R2**:
  卡头 kind 库存图标 → 该卡训练哪个通道(kind→通道 呈现映射 + capability 图形语言);
  词条三态环因队列 entry 不带画像数据、需后端 fetch,诚实留给波次 D 不前端造。构造签名去
  `onPlayRange`/`onPausePlayback`/`currentMediaId`,加 `onPauseBackgroundPlayback`/`resolver`/
  `createSlicePlaybackAdapter`(后二为测试缝);flow 与 main.dart 接线同步。列宽 token 接
  `cardColumnMax`(680→S0 token)。新增 4 测试(切片独立解码播放/解析失败诚实报错/Easy 四档
  payload/塌陷改任务框);`flutter analyze` 零告警,全量 640 绿(基线 636)。

- 2026-07-24: S0 主题加色 + 列宽 token + 双栏断点(refs #77 · #70 Phase 2 · 基建)。Phase 2
  基建起点刀,解锁 B/C 波。①`theme/listen_theme.dart` 入宪章色表第 4/5 色:**月白
  `#c7d4cf`**(对方的声音/照进来的光)、**月蓝 `#6db3ff`**(复习 `new` 首见态),作光源家族
  内容色直读(不走 `ListenSchemeShades`,与 sound/phoneme 家族同宗),`theme_palette_
  discipline_test` 加暗底 AA 对比度门(取最亮暗面为最坏况,过则更暗面皆过)+ 第五色确为
  新 hue 校验。②`theme/breakpoints.dart` 建内容列宽 token `contentColumnMax`(780,阅读列
  测量,合并词条详情 780/对话 760 的偶然差)、`cardColumnMax`(680,复习卡列),归属依前置
  决策 1;类文档说明列宽 caps 为何与断点同家。③加 `vocabularyTwoPane`(900)断点供 S3 双栏。
  ④示范:词条详情 `_detailBody` 硬编码 780 → `ListenBreakpoints.contentColumnMax`(零视觉
  变化的纯 token 接入)。呈现≠语义,后端零改动。`flutter analyze` 零告警,全量测试绿。

- 2026-07-24: Phase 2 前 11 刀开 issue + 清单回填对照（refs #70 · Phase 2 · 设计轨）。波次
  A+B+C 共 11 刀开成自包含 GitHub issue（S0=#77／S1=#78 S2=#81 S3=#79 S4=#82 S5=#80／
  S6=#83 S7=#84 S8=#85 S9=#86 S10=#87），每个正文指向 `listen-phase2-frontend-slices.md`
  对应节 + 设计稿 + 宪章，标依赖/文件行号/范围/验收/铁律。owner 定实现节奏=**串行，
  一刀一会话**，S0(#77) 为起点。D 波 4 刀（S11-14）阻塞后端 #72/#73/#74，交付时再开。
  清单文档补「刀↔issue 对照表」+ 串行执行说明。纯文档，无代码改动。

- 2026-07-24: 两个前置决策拍板 + 宪章光源清单修订（refs #70 · Phase 2 · 设计轨）。owner 定：
  ①内容列宽 token（C4）**归 `ListenBreakpoints`**（与 vocabularyTwoPane 断点同家，不新建
  文件）；②宪章原则 2 的「全仓仅有的 3 处 CustomPaint」**改为「光源家族」不带硬数字**
  （`CustomPaint` 只用于内容发光的光源家族：词级高亮/连读带/节奏带/能力画像/对话回声
  水面…，新增光源须证明画的是内容而非点缀）——一次性改到位，S7 落地回声水面无需再动
  宪章。`listen-design-charter.md` 原则 2 已改，`listen-phase2-frontend-slices.md` 的两个
  前置决策从「待 owner」更新为「已定」并回填 S0/S7。纯文档，无代码改动。

- 2026-07-24: Phase 2 前端拆刀清单落库（refs #70 · Phase 2 · 设计轨）。新增
  `design-notes/listen-phase2-frontend-slices.md`：把五页拍板落成 15 把**自包含可逐刀
  转交新会话**的实现刀，按波次组织——A 基建（S0 主题加月白/月蓝+列宽 token+
  vocabularyTwoPane 断点）；B 纯前端不依赖后端（S1 表达写作台/S2 教练画像即导航/
  S3 词汇本工作台差距面/S4 词汇本详情分段/S5 复习卡面呈现修复，跨刀依赖仅 S2←S3、
  S4←S3）；C 对话页 realtime 已在（S6 舞台态 shell/S7 回声水面/S8 余音字幕诚实分层/
  S9 结束页回流/S10 provider 迁设置域，S7-9←S6）；D 复习 anki 能力阻塞后端 #72/#73/#74
  （S11 四态+间隔预览/S12 牌组双轨/S13 导入导出/S14 custom study+上限）。每刀标注
  依赖/涉及文件行号/范围/验收，铁律（呈现≠语义、CHANGELOG、analyze 零告警、独立
  worktree、CI 停摆靠本地兜底）统一前置不重复。**两个前置决策待 owner**：内容列宽
  token 归属、CustomPaint 光源清单修订表述。波次 A+B+C 共 11 刀现在可推进，D 波 4 刀
  等后端。纯文档，无代码改动。

- 2026-07-24: 我的表达重设计探索稿（refs #70 · Phase 1 · 设计轨 · 五页最后一页）。落库
  `design-notes/listen-expression-redesign.html`，对准审计 E1–E5。**核心主张**：支架渐撤
  （看完整模板→只看槽位→只看关键词→隐藏模板）是本页唯一的产品级概念，现状却是弹窗
  底部一个默认永远停在最高辅助档的下拉框——把它变成**看得见的梯子**。**梯子的光语义
  与对话页拍板的 B 回声水面同宗**：模板=别人给的语言（月白）、你写的=自己的语言
  （信号青），撤一阶脚手架则月白递减、青递增（四阶比例 3:1→2:2→1:3→0:4，已几何
  校验单调）；四阶=后端既有四取值（`template_visible`/`slot_hints`/`keywords`/`no_text`），
  不新增语义。**三处诚实修复**：E1 删除确认明说牵连（N 个版本+M 条使用记录）、E3 模板
  文本升为卡片主角+最近一次你写的句子以青出现、E5 导出成功/失败如实反馈、E4 使用历史
  用梯子微条+人话替 raw 枚举。**A 写作台（推荐）**：弹窗死刑改页内写作台，梯子标注
  「用过 N 次/还没试过」，降档只做**轻提示**（上次得「表达自然」→ 提一次可忽略，
  绝不自动降档、不做任务、不算分，P3 建议≠判定）；自我证伪=快速记一句成本变高
  （缓解：保存始终可达、梯子不挡路）+历史为空则不编造。**B 弹窗转页（保守案）**：
  E2 只修一半，支架仍是「选项」而非「梯子」，不推荐。**owner 同轮拍板**（记录已写入
  稿内）：方向=A 写作台；保留降档轻提示（只提一次、可忽略、绝不自动降档）；「用过
  N 次」基于既有 attempts 前端聚合不新增后端语义；删除确认明说牵连。至此 #70 Phase 1
  五页设计稿全部出稿并拍板完毕。纯设计稿，无代码改动。

- 2026-07-24: 复习后端能力拆三刀提 issue（refs #70 · Phase 1 · 设计轨）。按拍板点 6 的
  授权起草并提交：**#72 anki 兼容 FSRS 调度内核**（互通地基·第一优先；引用现状
  `crates/application/src/practice/review.rs:6,16-37,42-43`＝heuristic_proxy 硬编码间隔表、
  stability/difficulty 恒 None，论证「不换内核则导入卡语义打架、导出 anki 不认」，
  含存量迁移不丢进度）；**#73 .apkg 双向互通**（SQLite/media 解析、anki schema 生成、
  媒体切片渲染音频、外来卡来源标识+保留原 deck 树+默认无四通道归属、往返无损测试、
  v1 不含 colpkg/AnkiConnect/AnkiWeb）；**#74 复习查询能力**（四态字段、间隔预览
  只读接口「调用后调度未变」测试、牌组两类计数、每日上限全局、custom study 四种
  临时队列不污染正常调度）。三刀均写明依赖顺序（#72→#73/#74）与「呈现≠语义，不改
  卡片生成与四通道判定，前端归 #70 前端刀」。同步修正稿内笔误：ReviewCardKind 是
  **5 种**（认词/块填空/连读在场/源句回忆/延迟复述），非 6 种。

- 2026-07-24: 复习 owner 拍板落库 + 宪章加第 5 色（refs #70 · Phase 1 · 设计轨）。9 条
  拍板点按「全部按默认」采纳本稿推荐：牌组主维度=通道自动分面（与导入 anki deck 树
  双轨共存）；**第 2 条 owner 另有明确指令「加第五色」——月蓝 `#6db3ff` = new 新卡
  「首见」态**（推翻我改用中性灰空心的提议，已同步写入 `listen-design-charter.md`
  色表，实现时进 palette 纪律测试 + 对比度校验）；间隔预览接口就位前隐藏（绝不前端
  估算）；每日上限归全局、措辞按「保护非 KPI」；custom study v1 四张动词卡（多学新卡/
  提前复习/只练某通道/重练遗忘，「按媒体」列 v2）；授权起草后端 issue（anki 兼容 FSRS
  为第一优先·互通地基）；互通 v1=.apkg 双向（colpkg/AnkiConnect/AnkiWeb 列未来）；
  接受媒体保真有损但导出前对话框明说；外来卡不进四通道画像。纯文档，无代码改动。

- 2026-07-24: 复习稿再扩展——anki 数据双向互通（refs #70 · Phase 1 · 设计轨）。owner 补充
  定位从「anki 式体验」升级为「完全接入 anki 数据体系」：.apkg 卡包导入 listen 使用、
  listen 卡导出回 anki。`listen-review-redesign.html` 增补：**牌组改双轨**（listen 原生
  卡按四通道自动分面=智能牌组，导入 anki 卡保留其原 deck 树=导入牌组，总览分两区；
  通道可作跨两类的过滤视图，外来卡默认无四通道归属不瞎归）＋**新增④ anki 数据互通
  章节**：模型映射表（ReviewItem↔note、kind↔note type、schedule↔card FSRS 状态、
  ReviewAttempt↔revlog 无损；媒体切片→[sound:]音频有损、四通道→tag 降级、影子跟读/
  画像回流 listen 独有不导出）＋导入（anki 通用卡成「外来卡」：纯文本复习+FSRS 调度，
  但无切片/不能影子跟读/不进四通道画像，卡头 badge 诚实标注）＋导出（保真提示对话框
  明说有损，P4）＋外来卡会话 mock。**关键论点**：调度内核必须是 anki 兼容 FSRS——
  否则导入卡带 anki stability/difficulty 而 listen 用 heuristic_proxy 瞎算，两边语义
  打架、导出 anki 不认，故「真 FSRS」从「更好算法」升为「互通地基·后端第一优先」。
  分工表加 3 行（导入/导出/FSRS 互通前提）。拍板点增至 9 条（+导入格式深度 .apkg vs
  colpkg/AnkiConnect/AnkiWeb、媒体保真边界、外来卡不进画像）。纯设计稿，无代码改动。

- 2026-07-24: 复习重设计探索稿——就地重写纳入 anki 完整接入（refs #70 · Phase 1 · 设计轨）。
  owner 定调复习系统完整接入 anki 体系（牌组+4 档评分+间隔预览+每日上限+自定义学习），
  算法/后端由 issue 交付、本稿只管前端。**关键发现（挖后端）**：地基已铺好、前端没接——
  `ReviewRating` 后端已是 4 档 Again/Hard/Good/Easy（coach 已统计 Easy），`ReviewSchedule`
  已带 algorithm/due_at_ms/interval_days/stability/difficulty/lapse_count，现状前端只用
  lapse_count、只暴露 3 档；真算法仍是占位 `listen_review_v1_heuristic_proxy`（硬编码
  分段，stability/difficulty 恒 None）。`design-notes/listen-review-redesign.html` 整篇
  重写：**差距地图**（8 要素分纯前端补/后端 issue）＋**三层结构 deck→session→card**
  （牌组=通道自动分面而非用户手建文件夹，呼应四通道命脉+复用 #47 罗盘/环）＋**卡片四
  状态**（new 月蓝新增第 5 色/learning 琥珀/review 青/suspended 压暗）＋**4 档评分带间隔
  预览**（每档下 10m·1d·4d·9d，来自后端只读预测接口，未就位则隐藏不造数）。三个页面
  mock：①牌组总览（罗盘环心=今日待复习数，四通道行带 new/learning/due 三色计数，空
  牌组压暗）②复习会话（保骨架+R1 第二解码器解耦+状态徽标+R3 补塌陷+R4 进度带）
  ③自定义学习（动词卡：多学新卡/提前/只练某通道/重练遗忘/按媒体）＋每日上限（保护非
  KPI，达上限诚实态）。**前端/后端分工表**（9 行）：纯前端=4 档/间隔显示/第二解码器/
  R2-R4/牌组总览页/custom study 入口；后端新 issue=真 FSRS/间隔预览接口/显式 state 字段/
  牌组分组计数/每日上限配置/临时队列查询。呈现≠语义守门三条不变。拍板点 6 条待 owner
  （牌组维度+多归属/new 第 5 色/间隔预览降级/每日上限归属/custom study v1 取舍/授权起草
  后端 issue），拍板记录节留空。纯设计稿，无代码改动。

- 2026-07-24: 学习教练 owner 拍板落库（refs #70 · Phase 1 · 设计轨）。拍板记录写入
  `listen-coach-redesign.html`：**方向=A 画像即导航**；owner「按你的建议」一并授权
  2–5：环心 gap 数→词汇本差距面（走既有 cross_modal_review destination，语义不动）、
  趋势微条按后端有无按日序列取舍（无则只留读数，不造数）、章节定序=画像→下一步→
  通道证据→素材架（起步条件性插入）、features 段降入「工具/关于」层级。纯文档，
  无代码改动。

- 2026-07-23: 学习教练重设计探索稿（refs #70 · Phase 1 · 设计轨）。落库
  `design-notes/listen-coach-redesign.html`：主张「画像不是插图，画像是导航系统」，
  对准审计 K1–K4/C2。**共享语义**：画像三热区（罗盘象限→页内通道证据段联动、
  环心 gap 数→词汇本差距面（三层家「总览→清单」闭合跳，走既有 cross_modal_review
  destination）、回声条→缺口来源高亮）＋证据行规范（快照原文主体+相对时间+来源
  可用性人话，UUID 死刑，下钻=行内展开弹窗死刑，指标卡套娃拍扁为对齐行）＋起步
  清单=状态行非任务框（K1：radio 图标撒谎死刑，未就绪项带入口按钮，完成不庆祝
  只亮起）。**A 画像即导航（推荐）**：四章定序=画像→下一步→通道证据→素材架，
  建议卡改「动词开头一句话+去」（三值拼接死刑），素材轨迹改两点连线微图；自我
  证伪=画像语义超载风险（缓解：热区 affordance+点击不离页）+趋势微条以后端有无
  按日序列为准不造数。**B 一页三章（保守案）**：只修呈现规格不加画像交互；证伪=
  K4（T 级痛点）原样遗留，仅当 owner 要画像纯展示时选。拍板点 5 条待 owner
  （方向/环心跨页跳/趋势微条授权/章节定序/features 段去留），拍板记录节留空。
  纯设计稿，无代码改动。

- 2026-07-23: 词汇本 owner 拍板落库（refs #70 · Phase 1 · 设计轨）。拍板记录写入
  `listen-vocabulary-redesign.html`：**方向=A 工作台为主、B 为窄窗退化形**（断点常量
  `vocabularyTwoPane` 进 ListenBreakpoints）；差距仪表间=右面默认页（进门第一眼=
  gap-(c)）；跨通道候选+产出差距合并为一张「差距」清单（呈现并排，语义零改动）；
  语义搜索并入主搜索框、索引管理归工具菜单；详情分段=锚点段落导航（非 tab）；
  实现拆两刀（刀1=差距面+外壳收纳+筛选修正，刀2=详情分段+加载诚实）。
  纯文档，无代码改动。

- 2026-07-23: 词汇本重设计探索稿（refs #70 · Phase 1 · 设计轨）。落库
  `design-notes/listen-vocabulary-redesign.html`：2 方向对准审计 V1–V6/C1/C3/C6。
  **共享语义先钉死**：gap-(c) 三层家架构（总览=教练画像、清单=词汇本页内常驻
  「差距」面（跨通道候选+产出差距并排呈现，后端语义不动）、词条=词条环+详情，
  层层可点）＋筛选语义修正（通道 chip 永远生效——选通道即换词条环视角，评估档
  未选时查询仍不加 capability 过滤，呈现层修 V1 的控件撒谎）＋外壳收纳（AppBar
  只留搜索/狩猎/工具溢出菜单，语义搜索「用」并入主搜索框、「装」归工具菜单，
  AppBar 永不变身）。**A 工作台（推荐）**：双栏，左=书（列表+透镜），右=活动面，
  差距仪表间为右面默认页——进门第一眼=gap-(c)；跨通道候选行=词条名+微型回声条
  （raw 四通道字符串死刑）；词条详情按身份卡+分段导航重排（证据/切片/我的输出/
  义项/笔记），身份卡先渲染装饰数据分段 loading（串行等待死刑）；自我证伪=右面
  两用需清晰返回动线+实现刀最大（建议拆两刀）。**B 书页优先（保守案）**：单列+
  顶部常驻仪表条+差距 push 页；自我证伪=差距与词表不能并视、宽屏留白——更适合
  作 A 的窄窗退化形（断点常量 vocabularyTwoPane 进 ListenBreakpoints）。
  拍板点 6 条待 owner（方向/差距面默认页/两清单合并/语义搜索并入主搜/详情锚点 vs
  tab/实现拆两刀），拍板记录节留空。纯设计稿，无代码改动。

- 2026-07-23: 对话页 owner 拍板落库 + 宪章「舞台态」修订（refs #70 · Phase 1 · 设计轨）。
  拍板记录写入 `listen-live-conversation.html`：**方向=B 回声水面**（纯 B，结束页用
  水面收窄成静态回声条收尾）；月白 `#c7d4cf` 成为正式语义色（对方的声音，实现时进
  listen_theme + palette 纪律测试）；字幕默认关（门厅开关保留、记住选择）；你的话
  live 中完全不上屏（本地 Whisper 只在结束页出场）；舞台态不联动系统全屏（#25 边界
  不动）；provider 管理迁设置域（单独拆刀）。**宪章修订**（owner 拍板升格）：
  `listen-design-charter.md` 新增「舞台态 · stage mode」节（全暗场/唯一光源/色的角色/
  文字最小化/门厅两段进场五条，P2 的极限形）＋色表加月白行。审计提出的另两条宪章
  修订（CustomPaint 光源清单、列宽 token 归属）仍待 owner 裁决。纯文档，无代码改动。

- 2026-07-23: 对话页 GPT Live 化设计探索稿（refs #70 · Phase 1 · 设计轨）。落库
  `design-notes/listen-live-conversation.html`：三方向，每方向强制回答六道必答题
  （核心形血缘/四态可视化/打断/字幕/进出动线/结束页）。**共享语义先钉死**：舞台态
  （全暗场、唯一光源、门厅→舞台两段进场、不联动系统全屏）＋色的角色分配（你的声音=
  信号青、对方=月白 #c7d4cf 新语义色、琥珀只留靶子时刻）＋四态形变映射（controller
  activity 原样复用）＋字幕克制（live 中仅一行余音字幕 2.6s 淡出、你的话 live 中不上屏、
  全文对读归结束页）。**A 罗盘在呼吸**：#47 罗盘放大为舞台大形，上=接收/下=产出，
  你开口下半环信号青点亮，打断=月白 90ms 退成一线；自我证伪=画像/对话双语义误读风险
  （缓解：舞台环不带画像刻度）。**B 回声水面**：回声条实时化，屏幕中线为水面、月白从上
  落下、青波从下升起，上下不对称即 gap-(c) 的形；字幕贴水面说完沉底，结束页水面收窄成
  静态回声条——形自己讲闭环；自我证伪=注视锚点弱+波形噪声疲劳（缓解：仅 2–3 条低频
  包络线）。**C 光斑（对照组）**：GPT Live 原教旨纯光斑，证伪清单=无差异化/空间语义
  丢失/结束页断链，但为疲劳成本最低的诚实退路。结束页三段式共用骨架（本地转写主体/
  琥珀靶子/回流读数，postProcessing 如实显示）。拍板点 7 条待 owner（方向/月白新色/
  字幕默认/你的话不上屏/不联动全屏/provider 迁设置域/舞台态升不升宪章），拍板记录
  节留空。动效自检：呼吸 2.6s 对齐 ListenMotion.ambient，禁 bounce，
  prefers-reduced-motion 全降级。纯设计稿，无代码改动。

- 2026-07-23: 运行时异常修复——词汇本首帧不再触发 `setState() or markNeedsBuild()
  called during build`（refs #68）。根因：`showVocabularyFlow` 路由挂载
  `VocabularyScreen` 时，`initState` 同步调 `HuntingController.load` →
  `Store.update` 同步 `notifyListeners`，而 shell 的 `ListenableBuilder`
  （Navigator 的祖先）已订阅该共享 controller——祖先在路由子树 build 期被
  markNeedsBuild，框架抛异常。修复对齐仓库既有惯例（realtime_conversation_panel
  同一模式）：共享 controller 的 load 移入 `addPostFrameCallback`，首帧后再通知；
  不动 Store 通知语义。全仓排查 initState 同步调用共享可监听对象，仅此一处命中
  （coach_dashboard/review_queue 是本地 controller，initState 时无 listener，安全）。
  **测试 +1（共 627 绿）**：复刻 shell 形状（祖先 ListenableBuilder 订阅共享
  HuntingController + 路由 push）的首帧回归测试，修复前红、修复后绿。
  `flutter analyze` 零告警。

- 2026-07-23: 五常用页现状审计落库（refs #70 · Phase 0 · 设计轨）。新增
  `design-notes/listen-common-pages-audit.md`：五页（词汇本/我的表达/复习/对话/教练）
  逐页对照宪章五原则 + 核心论点（四通道闭环 + gap-(c)），每条痛点带 file:line 可指认、
  可证伪。**横切 6 条**：C1 弹窗承载核心动线（gap-(c) 两个仪表、写句练习全是
  AlertDialog）、C2 raw 枚举/内部 UUID 直出（诚实仪器≠debug 输出）、C3 词汇本 AppBar
  6 图标堆核心与维护平级、C4 五页内容列宽各自硬编码且 `ListenBreakpoints` 零使用
  （grep 验证）、C5 文案三制度（表达硬编码中文/对话硬编码英文/其余 l.text，处置归
  #21）、C6 #47 图形语言止步画像未下沉动线。**逐页最重**：词汇本 V1 能力 chip 在
  「全部」档静默失效 + V2 gap-(c) 无常驻家；表达 E1 删除无确认 + E2 支架渐撤教学法
  沦为下拉框；复习 R1 音频可用性绑死主播放器（无媒体进复习全队 clip unavailable，
  第二解码器先例在词汇本）+ R3 delayed_retelling 卡面塌陷；对话 D1 一屏三职到 D7
  通用路由（owner 已定 GPT Live 全屏重设计，controller 状态机与「本地 Whisper 才是
  learner output」诚实分层列为必继承资产）；教练 K1 起步清单不可勾 + K4 画像与下钻
  断连。**核心论点地图**：闭环每环都在但「环」没被画出来，gap-(c) 呈现规格全场最低。
  宪章修订 3 点单列交 owner（CustomPaint 光源清单过时、缺「舞台态」规则、内容列宽
  token 缺席）。附严重度排序：对话 → 词汇本 → 教练 → 复习 → 表达，作 Phase 1 排产
  依据。纯文档，无代码改动。

- 2026-07-23: 能力画像换装——拍板方向落地（refs #47 · 设计轨）。新增
  `widgets/common/capability_viz.dart` 作为画像图形语言的唯一家，dashboard 与词条
  快照从此同一套语言：**罗盘总览**（`CapabilityCompass`：四象限=2×2，左声右文、
  上收下产；每象限亮弧=已证实、琥珀=练习靶子、细暗弧=未评估存量在场；接收的光聚
  12 点、产出聚 6 点——上亮下暗即 gap-(c)，环心只在后端 cross-modal suggestion
  在场时直书其 evidence_count，绝不前端造数）＋**回声条**（`CapabilityEchoBars`：
  听/说、读/写两列镜像条共享一把尺=四通道最大总量，接收 acquired 高度镜像到产出侧
  成琥珀虚框「回声缺口」；缺口标注只并置既有计数「听得懂 46 · 说得出 12」不做减法）＋
  **词条三态环**（`CapabilityRing`：词条列表 16px 行内与词条详情 44px 同构，比例在
  词条尺度诚实归零只留三态；tooltip/Semantics 四通道全裸露）。coach dashboard 标题
  换「你的语言画像」，三态 Chip 堆叠退役，通道卡降为纯 metric 下钻（无证据即不渲染，
  evidence 弹窗行为不变）；词条快照的四个 Material 图标退役；`capabilityAssessmentColor`
  移入 capability_viz 并按拍板把 acquired 从 learningRecognized 绿改为
  colorScheme.primary 信号青（词汇本筛选 chips 同步）。截图自检后两处视觉校正：
  聚合尺度的未评估大面积段/弧压暗到 outlineVariant（hairline 级「在场不抢光」，
  词条环细弧保留 0.45 灰维持行内可辨），回声条限宽 200 不随面板拉伸。新增断点
  `ListenBreakpoints.capabilityPortraitSideBySide=640`（breakpoint 纪律测试逮到
  硬编码后补正）。l10n +4（画像标题/环心/两条缺口并置，en/zh），清死键
  coachFourChannels/coachUnassessed。**测试 +9（共 635 绿）**：罗盘分段纯函数 4 条
  （锚点聚光方向、零计数诚实 unassessed、零段跳过）、gap 数只认后端 join、三态色
  （青/琥珀/压暗 alpha<0.5）、词条环 tooltip 全通道、回声条 ghost 高度=接收比例+
  并置文案+悬停三态数、环心有无 gap 双态；词条书测试改断言 CapabilityRing。
  `flutter analyze` 零告警；`dart format` 已跑。呈现≠语义：分析数据与 evidence
  门控零改动（controller/api 层零 diff）。

- 2026-07-23: 能力画像设计探索 + owner 拍板（refs #47 · 设计轨）。落库
  `design-notes/listen-capability-viz.html`：给四通道闭环 + gap-(c)（产品命脉）出三个
  图形语言方向，每个方向都验 dashboard 聚合 → 词条详情 → 列表行内 16px 三个尺度。
  共享语义先钉死：四通道是 2×2（声音听↔说 × 文字读↔写，各有接收/产出端），gap-(c)
  住在同模态跨方向里；三态色 = 信号青（已证实=你的语言=光）/ 琥珀（练习靶子，不是
  失败红）/ 压暗在场（未评估，诚实展示存量）。**A 回声条**：基线上=照进来的光（听/读）
  下=你的回声（说/写），接收的光镜像到产出侧成琥珀虚框——「回声没跟上的部分」即缺口，
  gap 是图形固有属性；**B 语言罗盘**：四象限环（左声右文、上收下产），接收的光聚 12 点
  产出聚 6 点，上亮下暗即缺口，环心直书 gap-(c) 数；**C 风筝**：雷达四轴，诚实证伪后
  不推荐（通用 BI 仪表脸、unassessed 无处安放、早期词库塌缩、16px 崩坏）。
  **owner 拍板（2026-07-23，记录在稿内）**：B 总览 + A 通道细节，词条尺度（详情+行内）
  统一用 B 的三态小环（比四小方块立得住）；acquired 的光 = 信号青（colorScheme.primary
  映射）；unassessed = 压暗在场 + 悬停显数，gap 标注只并置既有计数不做前端减法。
  实现（dashboard/词条快照换装）为本 issue 下一刀。

- 2026-07-23: macOS 原生菜单栏（refs #23）。`PlatformMenuBar` 接管菜单栏（AppKit 原生
  渲染，零新增 Swift），模板脚手架的死项整体消失。**⌘, 复活**：App 菜单 Preferences…
  直通应用设置；About/Services/Hide/Quit 走 `PlatformProvidedMenuItem` 系统项。
  **File**：打开媒体 ⌘O、打开 URL ⇧⌘O、导入主/副/内嵌字幕、归档媒体。**Edit** 重建
  标准 6 项（撤销/重做/剪切/拷贝/粘贴/全选），经 text-editing intents 派发到当前焦点
  文本框，无焦点时安静无操作。**Playback/Help**：菜单项直接取自 #25 绑定表的
  labelKey + 同一份 actions map——一个 id 一个标签一个回调，菜单只是第二张脸；缺 id
  fail-fast。**Learning**：字幕资源/词汇本/复习/学习教练/转写中心/音素分析中心。
  **禁用判定单一来源**：全部走 `AppBarCapabilities`（与 AppBar #24 同一实例）——无媒体
  禁导入/归档/播放项，核心断连禁 Learning。**owner 拍板的键位策略：菜单键位仅 ⌘ 系列**
  （⌘, ⌘O ⇧⌘O + Edit 六键）——AppKit 在事件到达 Flutter 前截获菜单 key equivalent，
  裸键（Space/F/[ ]）挂菜单会吞文本框打字、⌥←/→ 会吞按词移光标；裸键继续由 ? 速查
  展示，且有不变量测试钉死「菜单键位必含 ⌘」。l10n 新增 15 键（en/zh）。
  **测试 +8（共 626 绿）**：双语标签无泄漏、⌘-only 不变量、⌘,/⌘O/⇧⌘O、播放项=表行
  （标签一致 + 无菜单键位 + 回调同源）、可用性镜像 AppBarCapabilities 两态、缺 id
  fail-fast、Edit intents 真选全文、无焦点静默。`flutter analyze` 零告警；macOS debug
  构建通过。菜单在真机的原生渲染建议 owner 顺手过目（widget 测试覆盖不了 AppKit 层）。

- 2026-07-23: 全屏沉浸态（refs #25 · 轨A A 部分，收官）。播放器终于有全屏：
  **F / 双击视频面 / 播放栏新按钮进入，Esc 退出**（F/Esc 走绑定表，速查自动收录，
  en/zh 双语）。全屏 = 显式 UI 状态而非仅系统窗口全屏——`ImmersiveModeController`
  持有沉浸态，进入时同步请求 NSWindow 真全屏（新增 `FullscreenBridge`，风格同现有
  两个 bridge：`setFullScreen` + 窗口进/出全屏通知回推），**窗口是事实源**：绿灯
  按钮/系统手势进出全屏时 Dart 侧镜像跟随（无媒体时全屏窗口只是大窗口，不进沉浸态；
  媒体关闭/归档时自动退出沉浸态防止困在无 chrome 屏）。沉浸布局：舞台满铺、AppBar/
  会话头/侧栏/分栏全部让位（天然绕开 `ListenBreakpoints` 窄屏降级路径），transport
  作为底部覆盖层由 ShellRecede/ShellFade 驱动——**暂停时鼠标静止也收 chrome**（播放器
  惯例），chrome 隐藏时光标同步隐藏。双击手势只挂在裸视频面（`player-stage-surface`），
  字幕浮层从 translucent 改 opaque 吞掉自己的命中，避免双击识别器进词点按的手势竞技场
  造成 ~300ms 延迟。播放栏全屏按钮仅在有全屏宿主时渲染（切片播放器等不显示）。
  **测试 +13（共 618 绿）**：沉浸态状态机 10 条（进/出/toggle/媒体门/幂等/绿灯双向
  镜像/确认通知去重/dispose 解绑）、播放栏按钮双面+隐藏 2 条、裸视频面双击 1 条；
  绑定表不变量测试补 F/Esc 键位与键帽断言。`flutter analyze` 零告警；macOS debug
  构建通过。

- 2026-07-23: 格式收口——补跑 `dart format`（refs #45 遗留）。PR #45 的三个 coordinator
  （media_session/resource_actions/vocabulary_actions）未经 format 提交，另有 8 个文件
  少量格式漂移（listen_empty_state/listen_error_state/media_workbench/shell_recede/
  content_settle_test/hunting_actions_coordinator_test/listening_home_test/
  realtime_conversation_panel_provider_dialog_test），共 11 个文件统一格式化，
  `lib/`+`test/` 全仓 format check 归零。format 把超长单行 `if (...) do();` 拉成多行后
  触发 curly_braces_in_flow_control_structures，12 处 if 补花括号（`dart fix` 自动修复）。
  纯格式/花括号改动，零语义变化。605 项测试绿；`flutter analyze` 零告警。
- 2026-07-23: 静默 return 清查补完——`lib/widgets/flows/` 用户流程入口一律诚实反馈
  （refs #24/#45 后续）。#45 扫完 `lib/controllers/` 后，本刀按同一判据（CONTEXT.md
  Unavailable State：说明原因 + 给出恢复动作）补扫 flows 层的 `== null) return;`——这层是
  「词汇本」「复习」等按钮的直接路径，核心断连时会无声吞掉点击（此前一次无法复现的
  「词汇本按钮无反应」报告与此症状完全吻合）。**改反馈的 17 处**（缺核心报
  `statusConnectLocalCoreFirst`、媒体+核心缺失报 `statusOpenMediaAndCoreFirst`，一律经
  `playerController.setStatus`，缺通道的 flow 补 `playerController` 参数并同步 main.dart
  九个调用点）：learning_flows 九处用户入口（学习资产/我的表达/学习资源/词组保存/词形修正
  api 缺失/词汇本/复习队列/教练面板/词表导入）；subtitle_resource_flows 五处（导出格式/
  转写中心/音素分析中心/冷启动标注/字幕资源屏），其中冷启动标注按前提逐项报因——新增文案键
  `statusActivateSubtitleFirst`（无主字幕）与 `statusSetSubtitleLanguageFirst`（字幕无语言，
  zh/en 双写）；manual_review_flow 两处——入口守卫按核心/主字幕分别报因，评审对话框内
  `saveDraft` 遇主字幕被切换从静默 return（会让对话框正常 pop、假装保存成功）改为 throw
  新键 `statusManualReviewTrackChanged` 走对话框错误行，且保存成功的确认不再因切轨被吞
  （enhancements 重载仍只在轨未变时执行）；media_import_flows 一处（OpenSubtitles 搜索
  入口）。**判为合法静默并注释的**：文件/目录选择器取消、对话框主动关闭（导出格式/词表
  预览/API key/在线来源）、词形修正无选中 token（按钮只在选中 token 的 inspector 内渲染，
  vocabulary_book_test 已有断言钉住）。reading/speaking/writing_flows 为纯模板构造器，
  无守卫可查。**测试**：listening_home_test 首次真实点击「词汇本」——宽布局 1200x800 走
  侧栏项、窄布局 640x900 走资产卡，均断言 onOpenVocabulary 触发；learning_flows_test 的
  null-api 用例从「断言无导航」升级为「断言诚实反馈」，并新增 vocabulary/review-queue 两条
  null-core 反馈断言（对齐 #45 的测试改法）；subtitle_resource_flows_test 导出用例同步
  升级。`flutter analyze` 零告警，Flutter 全量 568 项绿。

- 2026-07-23: 快捷键绑定表单一来源 + 速查面板 + 桌面播放器基本键位（refs #25 · 轨A B 部分）。
  ① 新增 `lib/player_shortcuts.dart`：19 条绑定的唯一事实来源（id/键位/分类/l10n 标签/
  mark-key 标记），`main.dart` 不再硬编码任何 `SingleActivator`（有源码级测试钉死）；
  该表同时是 #23 原生菜单栏的数据源。② owner 拍板的键位重分配落地：←/→ 归还 seek
  （±5s），句间导航改 ⌥←/⌥→；新增 M 静音、↑/↓ 音量、[ ] 倍速（0.5–2.0 与 transport
  预设同界）；F/Esc 全屏留给 #25-A。③ `?` 打开快捷键速查（`shortcut_cheat_sheet.dart`，
  纯表视图，en/zh 全本地化，macOS 风格键帽 ⌥ ← / ⇧ I）；设置对话框新增「快捷键」分区
  （第 8 个 rail 项）：裸数字 1/2/3 标记键开关（`markKeysEnabled`，默认开，持久化
  `mark_keys_enabled`）+ 查看全部入口。④ Space 语义漂移可视：practice draft 激活时
  transport 播放键旁出现安静键帽提示「空格控制练习切片」（`spaceTargetsPractice`
  经 PlaybackBar 传入，practiceController 进 rebuild 合并列表）。⑤ 键盘音量/倍速与
  transport 滑杆同一持久化路径；seek 经 `PlaybackActionsCoordinator.seekBy`（钳制
  [0, duration]）。测试 +11：表不变量（id/键位唯一、双语标签齐全、owner 键位断言、
  builder 全覆盖 + mark-key 裁剪 + 缺失动作 fail-fast、main.dart 无硬编码扫描、
  开关在 widget 层真拦截）、速查双语渲染全条目、设置往返。596 项测试绿；
  `flutter analyze` 零告警；macOS debug 构建通过。

- 2026-07-23: 修复 `_saveSettings` 静默重置未枚举设置字段的 bug。原实现从默认值全新构造
  `AppSettings(...)`，凡未逐一列出的字段——`themeMode`、续播状态（`lastMediaPath/Title/
  PositionMs/DurationMs/SubtitleCount`）、`pronunciationVisible`、`phonemeDisplay`、
  `precomputePronunciation`、`showExperimentalPhoneticResults`、`phonemeHighlightVisible`、
  `phoneticCachePolicy`、`familiarMaterialSuggestions`——每次保存都被写回默认（例：亮色
  主题下调个音量 → theme_mode 被写回 dark）。改为提炼顶层纯函数 `mergeLiveSettings`：
  只把活数据源在 player/subtitle 控制器的字段写入 `settings.copyWith(...)`，其余字段
  一律原样保留（与 `_setWorkbenchMediaFraction`、`recordRecentMedia` 的既有增量写法
  一致）；原先经 settingsController getter 读回的自镜像字段（language、颜色、转录配置
  等）随 copyWith 直接保留，不再重复枚举。新增 `save_settings_merge_test`（活字段取自
  控制器 + 非默认 themeMode/续播/发音等字段全数保留 2 例）。585 项测试绿；
  `flutter analyze` 零告警。
- 2026-07-23: 判定状态色达标 WCAG AA + palette discipline 补第二道门（closes #22 · 轨A）。
  ① `ColorScheme` 扩语义判定色：`ListenSchemeShades.verdictCovered/verdictPartial`
  （light `#27702b`/`#a04d00`，dark `#5cc389`/`#efa05c`，脚本计算非肉眼选色——对各自
  brightness 的 surface/fog/sidebar 全部 ≥4.5:1，新增逐对断言进 `listen_theme_test`；
  missing 继续读 `error` 槽位）。三处调用点（reading_task_sheet / llm_judgment_assist /
  reading_diff_panel）改读扩展，替换双主题都不达标的 `Colors.green.shade700` /
  `Colors.orange.shade800`。② discipline 第二道门：`theme_palette_discipline_test` 新增
  `Colors.<具名>`（transparent 豁免）与 `Color(0x…)` 拦截，豁免文件逐条写理由并**钉行数
  配额**（wordmark 品牌常量 2、player_stage 视频舞台家具 8、settings_dialog 字幕取色板 5）
  ——豁免文件里新增硬编码色也会红。③ 顺手收敛：练习迷你播放器离谱蓝 `#1D2430` →
  章程舞台词汇（`ListenColors.player`/`overlayText*`）；新增 `ListenColors.videoBackdrop`
  （视频 letterbox 纯黑，亮度无关），player_adapter/slice_playback/词典行内片段 4 处改读。
  边界：light `error` `#c95454` 白底实测 4.30:1 未达标（issue 以为达标），但改 error 牵动
  整个亮色主题，归 owner 已裁决暂缓的「亮色主题重校」，本刀保持读 scheme 的正确模式。
  两道门 + 配额门均红→绿证伪过。585 项测试绿；`flutter analyze` 零告警。

- 2026-07-23: 修复 Realtime provider 下拉选中项横向溢出。
  `RealtimeConversationPanel` 的 provider 选择器（`DropdownButtonFormField`）未设
  `isExpanded`，真实 profile（如 'Realtime provider · qwen3.5-omni-plus-realtime'）
  会让选中项 Row 溢出约 290px。改为 `isExpanded: true` + item 文本单行 ellipsis。
  补 widget 测试：注册长 displayName/modelId profile 后渲染面板，断言无溢出异常
  （去修复复现 `RenderFlex overflowed by 294 pixels`）。584 项测试绿；
  `flutter analyze` 零告警。
- 2026-07-23: provider 对话框重构为 StatefulWidget,controller 归 State 所有(refs #27 收尾)。
  #58 的「await showDialog 后逐个 dispose」与退场动画存在竞态:保存成功时 registerProfile
  触发面板刷新,pop 后 future 立即 resolve、dispose 先于退场动画结束执行,退场中的
  TextField 重建即触发「used after being disposed」(与 #61 的诚实反馈测试组合时暴露)。
  改为 issue #27 点名的第二种合法模式(settings_dialog 同款):六个 controller 由
  `_ProviderDialog` State 持有、`State.dispose` 释放(secret 先 clear)——路由完全移除后
  才触发,竞态从构造上消失;leak 回归测试维持零泄漏。585 项测试绿;analyze 零告警。
- 2026-07-23: 实时会话「Add provider」对话框补诚实反馈（refs #24/#45 静默清查遗漏，
  源自 e30d6ba0/#7）。Qwen 未填 Workspace ID 时点「Save securely」原是静默 return——
  用户零反馈；现按 #45 判据（说明原因 + 给出恢复动作）在 Workspace ID 字段内联
  errorText「Enter the Workspace ID to complete the endpoint.」，对话框保持打开，输入
  即清除；Workspace 字段不可见时（如手动把占位符粘进 endpoint）错误落到 endpoint 字段，
  保证守卫永不静默。新增 `realtime_conversation_panel_provider_dialog_test`（未填报错
  不关框不发请求 / 补填清错误、保存成功发注册请求）。584 项测试绿；`flutter analyze`
  零告警。文案暂用英文与该文件现状一致，i18n 归 #21。
- 2026-07-23: 修复 provider 对话框泄漏 6 个 TextEditingController（closes #27 · 轨A）。
  `realtime_conversation_panel.dart` `_showProviderDialog` 每次打开建 6 个 controller
  但全文件 0 处 dispose——含绑 API key 输入框的 `secret`，密钥明文随 controller 滞留堆里。
  修复对齐全仓既有写法（`personal_expression_screen.dart`）：`await showDialog` 返回后
  逐个 `dispose()`，`secret` 先 `clear()` 再释放——密钥交给 Keychain 后不再持有。
  新增 `realtime_conversation_panel_leak_test`：leak_tracker 全类跟踪下反复开关对话框
  3 轮 + 卸载整树，修复前精确抓到 18 个（6×3）未释放 controller、修复后零泄漏
  （红→绿双向验证过）；`leak_tracker_flutter_testing` 入 dev_dependencies（`any`，
  版本随 flutter_test 钉住）。584 项测试绿；`flutter analyze` 零告警。
- 2026-07-23: focus ring——键盘焦点的可见语言（refs #46 · design Slice 5 之六，收口）。
  信号青细描边（1.5，与输入框 focusedBorder 同宽同色=同一语言）落进主题层：一个共享
  resolver 挂上四个按钮族（Outlined/Text/Icon 描信号青；Filled 底就是青色、环会沉底，
  改描 onPrimary），焦点在环在、焦点走环走，light/dark 两主题一致；按钮之外的控件维持
  Material 自身焦点呈现。与「外壳退后」的焦点持有联动：Tab 进 transport 外壳不消失。
  新增 `focus_ring_test`（两主题四族环样式 + resting 无环 + 输入框同语言 + Tab 走查
  焦点落位）。583 项测试绿；`flutter analyze` 零告警。
- 2026-07-23: 签名动作「内容落定」+「节奏拍呼吸」落地（refs #46 · design Slice 5 之五）。
  ① 抽出共享 `widgets/common/ambient_breath.dart`：全 app 唯一的呼吸手势（0.72→1 ·
  2600ms 周期 · ease-in-out，reduce motion 停），`ListenLoading` 重构改用（顺带降为
  StatelessWidget）。② **内容落定**：新增 `widgets/common/content_settle.dart`
  （淡入 + 上移 8px 落定，`base`·`enter` 无过冲；`settleKey` 变化重跑进场），挂上
  MediaWorkbench 的频道面板（immersiveStage + learningPanel，key=selectedChannel）——
  切频道不再硬切。③ **节奏拍呼吸**：节奏带当前拍（active）包 `AmbientBreath`，透明度
  与柔光一同起伏——活着但不抢戏，不是跳高。测试：新增 `content_settle_test`（进场/
  换 key 重跑/reduce motion 即时）、rhythm 测试钉「恰好一拍在呼吸」；循环播放测试改
  有界 pump（环境呼吸按设计永不 settle）。580 项测试绿；`flutter analyze` 零告警。
- 2026-07-23: 签名动作「外壳退后」落地（refs #46 · design Slice 5 之四）。媒体在工作台
  播放且鼠标静止 3s → AppBar 与 transport 淡出（`base`·`exit`，房间随内容变暗）；指针
  任何活动 → 淡入（`base`·`enter`）；键盘焦点落在外壳内 → 常显不消失（对齐 motion spec
  demo 3 的 `:hover, :focus-within`）。新增 `widgets/layout/shell_recede.dart`：
  `ShellRecede`（顶层半透明 Listener 侦测指针活动 + 静止计时，暂停/回首页强制常显）+
  `ShellFade`/`ShellFadeAppBar`（呈现层：布局占位不塌缩、隐藏时 IgnorePointer——静止后
  第一次点击是唤醒不是盲按隐形按钮；appBar 槽位保 PreferredSizeWidget 接口）。reduce
  motion 下即时切换。新增 `shell_recede_test`（不活跃永不退/静止退+移动回/焦点持有/
  暂停复原 4 例）。577 项测试绿；`flutter analyze` 零告警。
- 2026-07-23: 错误态容器定形（refs #46 · design Slice 5 之三）。新增
  `widgets/common/listen_error_state.dart` 两种形态：**`ListenErrorState`**（面板主体
  加载失败——与空态同几何：error 角色图标 + 一句话 + 可选重试，空与败读作同胞）、
  **`ListenErrorNotice`**（流程内一步失败——`errorContainer` 安静内联面，小图标+消息，
  待在面板正常流里不劫持）。收敛 10 处：面板级 3（转录中心/音频分析中心带 retry、
  coach dashboard 带 reload）+ 行内裸红字 7（听力收件箱/阅读任务/个人表达/语义检索/
  句法能力设置×2/复习队列）。边界：破坏性按钮红字（删除任务等）是动作色不是错误消息、
  diff/chip 的语义判定色一概不动；错误色值本身服从 #22 判定色工作，本刀只定容器形态。
  新增 `listen_error_state_test`。573 项测试绿；`flutter analyze` 零告警。
- 2026-07-23: 统一空态语言（refs #46 · design Slice 5 之二）。新增
  `widgets/common/listen_empty_state.dart`：`ListenEmptyState` = 安静图标（28px ·
  onSurfaceVariant 55%）+ 一句话 + 可选恢复动作——空是状态不是道歉，空面板不许喊
  （宪章原则 5）。12 处裸 `Center(child: Text(...))` 空态收敛：转录任务/音频分析任务/
  个人表达/语义检索/听力收件箱/L1 难点/写作无发现/字幕资源（未开媒体+无资源）/词汇本
  两处/冷启动标注，词典 fallback 的「搜语料库」按钮接入 `action` 槽。边界：小节内的行内
  提示（`noDictionary`、`llmNoProviders`、timeline 候选三处）是节内文案不是面板空态，
  不在本刀；`Center(Text(error!))` 三处留给错误态容器一刀。新增
  `listen_empty_state_test`（图标+文案+muted 色、动作可点、无动作不渲染按钮）。571 项
  测试绿；`flutter analyze` 零告警。
- 2026-07-23: 统一加载语言——裸转圈清零（refs #46 · design Slice 5 之一）。宪章禁装饰
  转圈但一直没给替代，本次定案：**等待 = 双向波形 mark 的 ambient 呼吸**（motion spec
  已有的「wordmark 呼吸」词汇，透明度 0.72→1 走一个 2600ms 周期 ease-in-out，reduce
  motion 下呼吸停止、mark 常显）。新增 `widgets/common/listen_loading.dart`：
  `ListenLoading`（面板级，居中 mark + 可选一行说明）与 `ListenLoading.inline`（控件级
  16–22px，替按钮/状态格里的 strokeWidth:2 小转圈）；语义层带本地化 `loading` 标签
  （en/zh 新 key）。全 lib 25 处裸 `CircularProgressIndicator` 清零（14 处面板级 +
  11 处行内），新增 `loading_discipline_test` 源码级禁裸转圈（豁免表内置、今日为空）+
  `listen_loading_test`（呼吸活着、下限 0.72、reduce motion 静止）。568 项测试绿；
  `flutter analyze` 零告警。
- 2026-07-23: wordmark + 排版/间距/圆角/动效 token（refs #28, closes #32, closes #26 ·
  design Slice 4）。#28 气质的「语法层」，三个前置设计决定（logo B 双向波形 / Plex+Charis
  字体 / motion spec）已全部定案后整体落地。① **字体内嵌**：IBM Plex Sans（Reg/Med/SemiBold）
  + Plex Mono（Reg）+ Plex Sans SC（Reg/Med，woff2 官方 npm 包转 TTF）+ Charis SIL（Reg），
  共 ~18MB 入 `fonts/`，OFL 许可证随资产入库，`pubspec.yaml` 声明四族——跨机器渲染一致，
  不再依赖系统栈。② **排版 token**（`theme/typography.dart`）：`ListenFonts` 四族常量 +
  `ListenType` 语义阶梯（11 caption · 12 body · 13 reading · 14 emphasis · 16 title ·
  22 hero，行高按宪章表：UI 标签 1.2–1.4 / 正文 1.5–1.7 / 标题 1.1–1.3）；`_build()` 把
  阶梯镜像到 `textTheme` 槽位并 pin Plex + SC fallback；69 处 `fontSize` 字面量全部迁移
  （10→caption 归档）；进度条时间标签改 `timecode`（Plex Mono，HH:MM:SS 等宽不抖动）；
  音素带/发音参照的 IPA 文本改走 Charis SIL（`ListenType.ipa`）。③ **间距 token**
  （`theme/spacing.dart`）：25 个 spacer 散值收敛为一条阶梯 2·4·6·8·12·16·24·32（离档值
  就近向下归并，防溢出），443 处童子 `SizedBox` 全量迁移；几何尺寸（带 child）不属间距、
  天然豁免。④ **圆角 token**（`theme/radii.dart`）：13 个散值收敛为四档+胶囊（tight 4 ·
  control 8 · surface 12 · panel 16 · pill），按元素角色而非就近数值归并；主题内 7 vs 8
  分裂终结——控件/菜单 control，卡片/对话框提到 surface。⑤ **动效 token**
  （`theme/motion.dart`）：owner spec 直译（tap 90 / hover 160 / base 240 / slow 360 /
  ambient 2600 + enter/exit/move 三曲线），Slice 2/3 的字幕胶囊落定、节拍/音素同步强调
  改引 token；禁止清单（弹跳/庆祝/装饰转圈）写入文档。⑥ **wordmark**
  （`widgets/listen_wordmark.dart`）：B 双向波形 mark（上亮青=内容、下暗青=回声，品牌常量
  不随主题翻转）+ 小写 `listen` 字标（Plex SemiBold，-0.02em），替换 AppBar 的
  `graphic_eq` 占位，首页/启动后续复用同一 widget。⑦ **不变量**：新增
  `spacing_discipline_test` / `radius_discipline_test`（源码级禁裸字面量，童子 spacer 判据
  写入测试注释）、`typography_test`（textTheme 槽位=阶梯、族=Plex/SC/Mono/IPA）、
  `listen_wordmark_test`（品牌色不得接 colorScheme）。全量 557 项绿；`flutter analyze`
  零告警。#26 据此收口。

- 2026-07-22: 静默 return 全面清查——用户触发动作一律诚实反馈（refs #24 后续）。#24 修复了
  playback_actions_coordinator 的 4 处静默空点击后，本刀按同一判据（CONTEXT.md Unavailable
  State：说明原因 + 给出恢复动作）扫完 `lib/controllers/` 其余 coordinator/controller 的
  `== null) return;`，逐处裁决"用户触发必须反馈 / 后台被动合法静默"。改反馈的（核心未连时
  `statusConnectLocalCoreFirst`，媒体+核心缺失时 `statusOpenMediaAndCoreFirst`）：hunting 三动作
  （狩猎开关/重建索引/勾选回答）、词汇动作 coordinator 七个用户包装（openWord/标注/状态/能力/
  释义笔记/听辨观察/记录来源，经统一 `_requireApi()` 收口——反馈归 coordinator，
  LearningWorkflowController 保持纯 workflow 并注释归属）、字幕资源面板六个行动作
  （归档/恢复/删除/导出 SRT/导出 LLTimeline/改语言）+ 刷新路径两处假成功修正（资源刷新在
  core/media 缺失时不再静默清列表，timeline 刷新不再谎报 "refreshed"）、媒体库 triage 意图、
  说话页 L1 核对入口；`selectCurrentSegment` 无字幕/纯非语音时报 `channelNeedsTranscript`
  （复述与实时会话两条启动路径受益）。判为合法静默并注释的：home 摘要预取/媒体库后台刷新、
  词表后台加载、通道切换器已用 tooltip 禁用兜底的 reading/writing/speaking 打开守卫、
  语法能力轮询、文件选择器取消、练习 draft/录音 UI 门控守卫、task controller 状态机守卫。
  文案键 `statusConnectLocalCoreFirst`（zh/en）与 #24（已合并）逐字一致，rebase 后收敛为同一键。
  测试：hunting/vocabulary/speaking-channel 三处原"null API 静默无操作"断言改为断言诚实
  反馈；补 idle-api 假核心用例钉住"无选择静默"与"任务未加载静默"的边界仍然成立；
  media_library triage 与 resource-actions 行动作/刷新各新增 null-core 报告断言。
  `flutter analyze` 零告警，Flutter 全量绿。

- 2026-07-22: 语流/节奏带重设计——发光的节奏骨架（refs #28, closes #31 · design Slice 3）。
  产品独有的语流呈现按宪章气质重画，**只动呈现、不动分析与 evidence 门控**。
  ① **节奏骨架**（rhythm_frame_ribbon）：`_AudibleNode` 从胶囊 chip 改为节拍柱骨架——柱高
  即重音层级（核心最高 0.56h、anchor 0.42h、连读 0.30h、弱读近平 0.14h），柱底共线成节奏
  剪影；只有重音柱发光、当前拍最亮（+12% 高度、blur 12）；去掉胶囊底/描边（盒子让每一拍
  同样吵，违反原则 5）。**配色语义保留**（owner 裁决：核心粉/anchor 黄/弱读暗只重排明暗）；
  弱读仍显示可听声形（item.label）而非书面 caption——测试逼出的语义边界。
  ② **连读带**（connected_speech_reference_ribbon）：每个连读标记从两笔（上弧+下划线）减为
  一笔 undertie ‿，选中时青晕。③ **字幕行内 ‿**（token_line + player_stage，owner 裁决本刀做）：
  新增纯显示管线——TokenLine 接收 `connectedSpeechRefs`（复用带子已消费的 rhythm frame，
  无新分析路径），把连读引用的 token 区间投影到相邻词结点：单空格结点直接画成 ‿、紧邻词间
  插入 ‿、含标点的结点不标（连读跨标点是句面自相矛盾的宣称）；‿ 为绘制而非字形（不赌字体
  覆盖），tooltip 带规则提示，当前词进入连读区间时与词发光协同变亮；bounce/淡入尊重
  reduced-motion，AnimatedContainer/Opacity 时长归零。测试：新增 token_line_tie_test 3 项
  （空格替换为带 tooltip 的 ‿、无引用无 ‿、无 token 区间忽略）；phoneme_ribbon_test 全绿；
  全量 550 项绿；`flutter analyze` 零告警。

- 2026-07-22: 外壳退后、内容发光（refs #28, closes #30 · design Slice 2）。宪章原则 2 的强调层
  重排——外壳安静下沉，声音/词/画面成为唯一光源。① **信号青校准**：`darkPrimary`
  `#5cc6b8` → 设计稿 `#4db8a8`，WCAG AA 逐对断言保持绿灯。② **Transport 退后**：
  compact/full 两形态共用一份 `_progressSliderTheme`（3px 细轨、未播部分近乎隐入、把手
  实心青点带静态柔晕，高对比模式自动去晕）；prev/next/restart 与未选中 toggle/菜单 chip
  全部降到 variant 层，播放键是这条栏上唯一发光的控件；时间标签退为 muted。③ **Rail/侧栏
  退后**：首页 `_SidebarItem` 选中态从实心 `primaryContainer` 色块改为中性抬起面 + 淡青描边
  + `pressedPrimary` 前景（顺带修掉亮色主题下 primary-on-container 仅 4.1:1 的既有 AA 缺口）；
  未选中文字降到 variant；side_panel `_PanelTab` 去掉选中色块、只留青色下划线与字形。
  ④ **AppBar 退后**：菜单按钮图标/标签/箭头与设置图标降到 variant 层。⑤ **当前词发光**：
  `token_line` glow 样式当前词直接用信号青 + 柔晕；新增 `ListenColors.overlaySignal`
  （overlay 恒暗，信号青不得随亮色主题翻转成深青沉入墨底）；`wordHighlightStyle` 默认
  `background` → `glow`（三种显式选择均保留，未知值回退 glow）；reduced-motion 下 bounce
  静态化、发光本为静态不受影响。字幕带本身的重画归 Slice 3，尺寸/字号 token 归 Slice 4。
  测试：settings_test 词高亮默认/保留断言更新+新增；全量 547 项绿；`flutter analyze` 零告警。

- 2026-07-22: AppBar 菜单项按状态禁用 + 归档媒体不再静默空点击（refs #20, closes #24）。
  ① 新增 `AppBarCapabilities` 值对象（hasMedia/coreReady），组合根从
  `playerController.mediaId != null` 与 `api != null` 一处计算——#23 原生菜单栏必须复用同一份
  判定，不写第二套。② 归档媒体与 7 个字幕动作（导入/生成/搜索主副轨、导入内嵌）在无媒体时
  `enabled: false` 灰化，并在 subtitle 槽位显示原因（复用 `statusOpenMediaAndCoreFirst` 文案，
  对齐 `ContentChannelAvailability` 带 reason 的既有模式）；打开媒体/打开链接保持可用——它们
  本身就是恢复动作。③ `playback_actions_coordinator` 四处静默 `return`（归档、词汇导出/导入、
  语音发现反馈）改为诚实的 Unavailable 反馈（CONTEXT.md：说明原因 + 恢复动作），新增
  `statusConnectLocalCoreFirst` zh/en 键；其余 coordinator 的同类静默 return 已扫描、
  记为独立后续任务（用户触发 vs 后台被动需逐一判断，不在本刀发胖）。④ `player_app_bar_test`
  新增无媒体态断言：受限项 `enabled == false`、原因可见、点击不派发、恢复动作保持可用。

- 2026-07-22: 设计宪章落库 + 暗色为家（refs #28, closes #29 · design Slice 1）。
  ① 新增 `design-notes/listen-design-charter.md`——把 #28 的一句话气质（「一个正在专注倾听
  你的、安静的房间」）、五条可检验原则、墨绿炭底色定义与定调期关键裁决固化为仓库内唯一
  事实来源，后续 slice 与 agent 引用它而不是散落的 issue。② 暗色为默认：`AppSettings`
  构造默认与 `fromJson` 回退 `'system'` → `'dark'`，`appThemeMode` 初值
  `ThemeMode.system` → `ThemeMode.dark`（首帧即暗房间，避免亮闪）。persistence 边界：
  `toJson` 恒写 `theme_mode`，已显式保存过设置的用户不被翻转，只有全新安装/从未持久化者
  进暗色——不强制迁移用户的显式选择。信号青校准（`#5cc6b8` vs 设计稿 `#4db8a8`）按 issue
  预案留给 Slice 2。测试：`settings_test` 新增默认暗色与显式选择保留 2 项断言。

- 2026-07-22: Phase 3.19 彻底收口（owner closeout）。纯文档刀，不含代码：
  ① `3.19-RELEASE-ACCEPTANCE.md` 新增 §O 收口权威记录——纠偏 issue #1–#7 全部关闭的
  处置映射（#4 记为前提不成立而非修复）、Run 2 未整轮重跑的显式豁免口径（3.19.1 真机 QA +
  每刀 web review 替代）、遗留 P1 十三条 owner 书面例外逐条移交（设计/UX 重构轨、复习模块
  轨 #10/#11、ADR 0025 契约、D-319-18 独立技术项）；J3 结论标注被 3.19.1 owner QA 取代；
  D-319-09/12/17/20/22 状态更新带 issue/commit 引用，Run 1 记录保持原样不改写。
  ② `3.19-SUBTRACTION-AUDIT.md` 七个 `PROVE OR ...` 灰区全部由 owner 裁决为规则允许的
  终态（SIMPLIFY×1 / REMOVE×1 / DEFER RESEARCH×4 / UNAVAILABLE×1），逐行标注裁决日期与
  移交去向——裁决只定终态，不伪造验证结论。③ `3.19-PRODUCT-CORRECTION.md` 标 CLOSED。
  ④ 新增 `3.19-CLOSEOUT.md` 总记录。Release 判定如实维持 `DO NOT RELEASE YET`——发布门
  随后继轨道继续，不随 phase 关闭而消失。

- 2026-07-22: 词条详情新增「证据与历史」入口（closes #2）。能力状态和能力建议此前是词条详情里
  仅有的"结论层"，用户无法回访结论背后的真实学习记录（Phase 3.19 Owner Journey Q1.4 因此失败）。
  后端证据链其实早已存在——ADR 0017 的 append-only 通道化 `LearningObservation`（通道/任务/
  结果/辅助/surface form/来源/时间戳齐全），缺的只是读取面：新增 GET
  `/v1/lexical-entries/{id}/observations?capability=&limit=&offset=`（application 用例
  `learning_observation_history`，默认 50 条/上限 200，按时间倒序），**严格只读**——对齐 3.19.1
  的 authority 边界（review/evidence 是 corpus 与 observation 的只读消费者，不新增任何 writer）。
  OpenAPI 同步 path + `LearningObservation` schema（防漂移测试逼出来的，这个门真的在工作）。
  前端：`LearningObservationView` DTO + `learningObservationHistory` API；详情页在能力画像
  正下方新增「证据与历史」折叠区——**默认收起、点开才拉取**（宪章原则 3：系统对用户的了解
  等用户自己来看）；展开后按通道筛选（全部/听/读/说/写 chips）、逐行显示任务类型、结果、
  辅助边界（无辅助/部分文本/完整文本——这是单行证据能证明什么的诚实边界）、来源与时间，
  整页可分页加载更早证据。层级刻意与能力建议 banner 分开：建议说"接下来做什么"，
  证据说"实际发生过什么"。未知的未来 task/outcome 枚举降级为原样 snake_case 而非错误标签。
  颜色全走 `colorScheme`（palette discipline 绿）。测试：Rust 路由测试（reading marking 播种 →
  历史读回同一行、capability 过滤真在过滤、未知词条 404）、OpenAPI 防漂移 2 项、Dart 契约测试
  钉 wire shape、widget 测试（懒加载不提前请求、筛选、诚实空态）。zh/en 双语 29 个新键。
  `flutter analyze` 零告警，Flutter 全量 543 项绿，api-http/application 全量绿。

- 2026-07-22: 泛听完成摘要显示本次实际泛听时长（closes #3）。结束泛听的确认弹窗此前只问理解度
  和狩猎摘要，用户在提交当下无法确认这次听了多久。issue 明确要求**真实播放累计**——既不是媒体
  总时长，也不是 started→ended 墙钟差（中途暂停去查词的时间不该算听的时间）。实现为
  `ExtensiveListeningController` 内一只跟随播放状态的秒表：组合根把 `playerController` 的
  play/pause 转换喂给 `notePlaybackState`，只有「会话激活 && 正在播放」的墙钟段被累计；seek 不
  扰动它（播放中时间照常流逝）。累计量**刻意放在 Store 之外**——它连续前进，进 Store 会白白
  churn 监听者，读方按需采样 `playedDuration`（播放中含未闭合段，实时）。三个生命周期点：
  `startSession` 与 soft-interrupt 隐式建会话时清零（正在播放则立即起跳），`finishSession` 冻结。
  时钟可注入（`clock` 构造参数），新增 2 个测试用假时钟断言「暂停段不计入」「完成后冻结」
  「会话中途开始从会话起点计」「下一会话清零」。变异验证：废掉暂停 flush → 用例红；去掉
  开会话清零 → 用例红。弹窗在打开前快照时长，作为 completion 摘要首行（`HH:MM:SS`，复用
  `formatDuration`），zh/en 两 locale 均新增 `extensiveSessionPlayedDuration` 键，无单语硬编码
  （吸取 #21 教训）。时长暂不回传后端（issue 只要求提交前展示；持久化属于另一刀）。
  analyze 零告警。

- 2026-07-22: 完成 Phase 3.19.1 方案 B5 的恢复与关闭语义。Realtime route 在 active/connecting 时返回会
  先确认丢弃，显式 Cancel 会先 fence pending learner ASR 再关闭 route；draining/post-processing 期间
  不允许半途退出。provider drain timeout 可注入测试，超时时保留 partial assistant 为 interrupted，
  session 仍按正常 finish 完成。新增麦克风启动失败、provider 连接失败无脏状态重试、pending-ASR
  cancel、drain timeout 与 route close widget 回归。同步调研 Discute、AI Spanish Tutor、conversAI、
  Study Buddy、SuVi Player、Shadowing 与 upstream LLPlayer：提取 timeline、grounding、review 和跟读模式，
  明确不采用 provider item ID 领域身份，也不把固定目标复读重新包装为对话；详见
  `3.19.1-GITHUB-ANALOGS.md`。

- 2026-07-22: 完成 Phase 3.19.1 方案 B4。内容通道的「说」现在先明确选择复述、跟读或围绕内容
  对话；话题对话直接进入 Realtime route，不再先创建 Speaking task，也从 Speaking Studio、host 与
  coordinator 删除 Realtime 页面状态。Pattern Production 的两类事实改为显式关联：semantic attempt
  继续权威持有 prompt/录音/文稿，Personal Expression Use 只记录 pattern version 使用、辅助等级与
  learner self-assessment；新 speaking use 必须携带 `semantic_attempt_id`，writing 禁止携带，旧 JSON
  不伪造回填关系。补充审计 LiveKit Agents 当前 HEAD `c67c44e` 的分层事件、ordered ChatContext、
  drain/aclose 与 interrupted playout 测试方法，未引入运行时依赖。同步完成 B5 的状态分层子切片：
  Realtime session phase 与 learner speaking/thinking/assistant speaking activity 分开建模，timeline 仅在
  用户仍靠近 live edge 时自动跟随，手动回看不会被强制拉回底部。

- 2026-07-22: 推进 Phase 3.19.1 方案 B 的边界收敛。Realtime 新增本地 sequence 权威的纯 turn
  assembler，barge-in 会把未完成 assistant item 记为 interrupted，Cancel 会阻断待处理 learner
  turn 后续 finalize，Finish 会在 provider drain 后显式 flush 最后一条 assistant transcript；Realtime
  launch 改用自有显式 topic anchor，不再依赖 Speaking task prompt。Production Corpus 全量 rebuild
  现在以单事务同时重建 writing attempts 与 finalized local-authoritative realtime learner turns，
  assistant/failed/interrupted turns 继续不进入个人产出。方案 B 的保留能力、参考项目映射、后续入口
  取舍与测试切片记录于 `3.19.1-SCHEME-B.md`。

- 2026-07-22 15:10 CST: 完成 Speaking / Realtime 产品减法：删除把字幕下一句当预设回答的 Role
  Reply，不再保留三档文字辅助、Flutter 入口、controller 创建路径、领域枚举、LLM/Coach 分支或
  OpenAPI kind。schema v45 破坏性清理既有 Role Reply rubric、attempt、judgment/adjudication、延迟
  review、录音与音频文件、显式 speaking observation，以及可追踪到这些 observation 的 proposal；
  若被确认 proposal 仍是当前 speaking projection，则撤回 projection 但保留用户 override。L2
  Retelling、Shadowing、Personal Expression 与真正的 free/topic Realtime Conversation 保持独立。

- 2026-07-22: Realtime conversation baseline 从 OpenAI 调整为 Qwen
  `qwen3.5-omni-plus-realtime`，新 profile 默认北京 workspace endpoint 与 `Tina` 音色，并支持
  Singapore workspace endpoint。修正 provider 音频协商：Qwen capture/input 使用官方要求的
  16 kHz PCM，assistant output 保持 24 kHz；OpenAI 继续使用 24 kHz input/output 并作为可选参考实现。
  Qwen session contract 删除当前官方 schema 不包含的独立 ASR 配置，真实 smoke gate 固定单一 baseline
  model，并接受 `DASHSCOPE_API_KEY`、`QWEN_WORKSPACE_ID` 与可选 `QWEN_REGION=cn|sg`。

- 2026-07-22 12:34 CST: GPT Live-like macOS audio baseline 启用 Apple voice-processing I/O。
  `RealtimeAudioBridge` 在读取硬件 input format 与安装 capture tap 之前调用
  `setVoiceProcessingEnabled(true)`，使 capture/playback 进入系统 AEC/NS/AGC 路径，并在 cleanup
  关闭；这降低 assistant 播放泄漏被误判为 learner turn 的结构性风险。新增调用顺序/关闭回归测试，
  `flutter build macos --debug` 通过；真实扬声器/麦克风的 echo、首尾音素和不同设备质量仍待人工测量。

- 2026-07-22 12:31 CST: OpenAI realtime baseline 提升为 `gpt-realtime-2.1`。新增 profile 的 UI 默认
  使用该 model，切换 Qwen/OpenAI 时同步恢复各自明确默认；既有持久 profile 不做静默迁移。OpenAI
  codec 按当前 GA contract 把旧 `pcm16` shape 更新为 `audio/pcm` 24 kHz，显式锁定 audio output，
  并启用 `gpt-4o-mini-transcribe` 作为仅供 live guidance 的 provider caption（本地 Whisper 继续是
  learner authority）。新增精确 session-shape contract 与需要 `OPENAI_API_KEY` 的真实
  `session.created` + `session.updated` smoke gate；本机无凭据，因此真实 gate 保持 ignored，没有冒充
  provider/device 验收完成。

- 2026-07-22 12:22 CST: Phase 3.19.1 开始推进 GPT Live-like 基础设施。新增 realtime provider
  capability contract v2，把 transport、输入/输出音频、VAD/manual turn、双方 transcript、response
  cancel、output clear、conversation truncate、function calling、image input 与 session resume 明确为
  **adapter 已实现能力**，避免从模型厂商宣传反推当前代码可用；OpenAI/Qwen 当前诚实报告共同的
  WebSocket + 24 kHz PCM + transcript + cancel 子集，contract test 9 项通过。新增 Live foundation
  调研与交付顺序，确认豆包端到端实时语音属于原生 S2S 候选，但豆包语音直连和火山 RTC 编排层是
  不同接入面；未固定 endpoint/auth/event schema 前不伪装成 OpenAI-compatible model，也不调整默认。

- 2026-07-22 11:33 CST: Phase 3.19.1 Realtime Conversation Product Correction 完成第一轮实现与
  自动门。Flutter controller 从整场三个字符串重构为本地 sequence 排序的 typed learner/assistant
  turn assembler，provider item id 仅作 correlation；macOS audio bridge 按 learner turn 输出带 500ms
  pre-roll 的独立 16 kHz WAV，每轮单独创建 recording asset 与 local Whisper job。单轮 ASR 失败只标记
  该 turn，finish 会 drain provider 最后一轮并等待全部 post-processing，正常 session 仍 completed；
  Production Corpus 继续只接收 finalized local learner turns。首页新增宽/窄各唯一的自由对话入口，
  内容选区保留话题锚定入口，session/ordered turns 新增只读 GET 并在同一 panel 支持历史回看。
  权限获取移到 provider socket 之前，replacement Q9、ADR/architecture/data-model/phase 状态同步更新。
  自动验证：4 个 controller 权限顺序/多轮/partial/dedup 测试、首页/最小窗口测试、Rust application/persistence/
  API focused tests、Flutter analyze 与 `flutter build macos --debug` 全部通过；真实 provider/device 三轮
  boundary、barge-in、最后一轮 drain 与 owner ACCEPT 仍待执行，未冒充完成。

- 2026-07-22 11:15 CST: Phase 3.19.1 durable contract gate 完成。新增 ADR 0027 与 realtime
  conversation domain glossary：Conversation Session 只描述 provider conversation 生命周期；双方
  Conversation Turn 使用本地 sequence 排序，provider item id 仅作 correlation；Provider Caption
  只服务 live guidance；每个 learner turn 只有自己的本地录音与 Whisper 完成后才成为 learner
  output。Conversation History 保存双方，Production Corpus 仍只投影 finalized learner turns；单轮
  local ASR 失败不抹掉同 session 其它成功轮，也不把正常结束的 provider session 改成 failed。
  下一门为带真实三轮音频的 boundary spike 与 free/topic 产品入口契约。

- 2026-07-22 11:05 CST: 为 GitHub Issue #7 建立 Phase 3.19.1 Realtime Conversation Product
  Correction（3.19 的纠偏子阶段，不绕过新功能冻结），保持已完成 3.15.7 历史文档冻结。新增
  CONTEXT/PLAN/RESEARCH，审计当前整场录音在 Flutter `finish()` 中被压成单 learner turn 的根因，
  并固定调研 OpenAI Realtime Agents、LiveKit Agents/Flutter starter 与 Pipecat 的具体 commit。
  结论是复用现有 provider-neutral Rust session/turn/SQLite/Production Corpus 深模块，后续引入本地
  turn assembler、逐 learner turn audio + Whisper authority 和 ordered 双方 timeline；assistant 只进
  conversation facts，不进 learner corpus，Gap Review 保持既有只读路径。PROJECT/REQUIREMENTS
  （LOOP-026）/ROADMAP/STATE 与 3.19 subtraction audit 同步该方向。当前只完成调研与 phase 建立，
  未开始实现；下一门是 durable lifecycle 设计与真实三轮 audio-boundary spike。

- 2026-07-22: 设计资产落库 —— `design-notes/` 新增三份 listen 视觉稿（refs #28）。
  `listen-visual-identity.html`（整体气质定稿，暗色墨绿炭 `#1a2420` + 信号青 `#4db8a8`
  + 琥珀 `#e6b45c`，是 #28 宪章的视觉锚点）、`listen-mark-exploration.html`（wordmark/
  符号四方向探索，#32 的取材来源）、`listen-motion.html`（动效语言，已列出可直接抄进
  #32 的 motion token：`--dur-tap/hover/base/slow/ambient` + 三条 ease）。此前这三份稿子
  只在本地未提交，导致 #28 指向 `blob/HEAD/...visual-identity.html` 的链接是断的；本次
  提交修复断链，并给后续设计 slice（#29–#32）一个仓内可引用的事实来源。纯文档，不含代码，
  不触及测试。

- 2026-07-21: 设置最小窗口尺寸 640×560（closes #19，refs #18, #12）。#18 的收尾残留：
  AppBar 改成纯图标后仍有一个**硬地板 480px**（实测 470 溢出 10px、460 溢出 20px、
  440 溢出 40px，与 locale 无关，因为图标宽度固定），再往下只能把四组菜单折成单个
  overflow popup，牺牲可发现性去迁就一个不该被支持的形态。
  根因不在 AppBar：app 从来没设过窗口下限（`MainFlutterWindow.swift` 只有
  `setFrame`，无 `contentMinSize`），而 480 低于仓库里**所有**断点（最小的
  `sidePanelTabLabels` 是 520）——低于 520 时工作台、侧栏、播放控件、首页早已全部
  处于最降级形态，继续为更窄的宽度加退化分支是在为不存在的形态写代码。正确的边界是
  给窗口设下限，而不是让每个 widget 各自防御到 0px。
  顺带一提，默认窗口是 `MainMenu.xib` 里的 800×600，**正好落在 #18 修掉的溢出区间里**。
  取值 640×560：宽度在 480 硬地板之上留足余量，且 640 已是测试里当作"紧凑桌面布局"的
  标准宽度；高度 560 让精讲练习窗（自身 clamp 在 360–560）减去工具栏后仍落在其区间内。
  常量以 `ListenBreakpoints.minWindowWidth/Height` 为单一事实来源并写明依据，Swift 侧
  引用同名常量。新增 `window_min_size_test.dart` 3 例：**解析 Swift 源文件断言两侧数值
  一致**（跨语言常量最容易各改各的，仓库里已有 `breakpoint_discipline_test.dart` 读源文件
  的先例）、断言下限严格大于 480 硬地板、以及在恰好最小尺寸下 en/zh 两 locale 渲染无
  overflow。两次变异验证：把 Swift 侧改成 400 → 漂移那例变红；把 Dart 下限改成 470 →
  硬地板与实际渲染两例同时变红。
  已跑 `flutter build macos --debug` 确认 Swift 改动真能编译。
  analyze 零告警，全量测试 517 项绿。

- 2026-07-21: 修复 `PlayerAppBar` 在窄窗口下的布局溢出（closes #18，refs #12）。
  四个带文字标签的菜单按钮 + 设置图标全部固定宽度、没有任何窄屏退化路径，en locale
  下窗口窄于 836px 时 AppBar 的 title `Row` 被挤爆，debug 下显示黄黑条纹
  （800px 溢出 36px、760px 溢出 76px、700px 溢出 136px）。zh 不受影响——
  「内容/字幕/学习」比 `Content/Subtitles/Learning` 短，**这是 locale 相关的布局 bug**。
  新增 `ListenBreakpoints.appBarLabels = 860`，低于它时菜单按钮只留图标；
  **阈值按最长的 locale 定而不是最短的**，注释里写明 en 实测需要 836，取 860 留余量，
  以免将来某个更长的翻译又把溢出带回来。下拉箭头在窄形态下保留——只剩图标时若连箭头
  都没有，按钮会读成普通动作而不是"能展开菜单"。「更多」菜单本来就是纯图标，不受影响。
  `player_app_bar_test.dart` 8 例：新增窄屏回归（en/zh × 700/760/800 六种组合断言
  无 `takeException`）与"窄屏下标签消失但 tooltip 仍在、菜单仍可展开并派发"。
  变异验证：把阈值改成 0（等价于恒显标签）后两条新用例立刻变红。
  **残留已知问题**：约 480px 以下纯图标形态仍会溢出（此时与 locale 无关）。根因是
  全 app 没有设最小窗口尺寸（`MainFlutterWindow.swift` 未设 `contentMinSize`），
  而该宽度低于仓库里所有其他断点，属于另一个层面的决定，未在本刀处理。
  analyze 零告警，全量测试 514 项绿。

- 2026-07-21: 首页入口层级收敛——rail 管"去哪儿"，卡片管"看什么"（closes #17，refs #12）。
  宽窗口首页此前把同一批目的地渲染了两遍：左侧 rail 与卡片区的「到期任务与学习资产」
  两两完全重合（字幕资源/词汇本/我的表达/复习/学习教练），打开媒体/打开 URL 同样两处都有。
  两处视觉权重不同（rail 是紧凑列表项，卡片带副标题）暗示层级不同，实际调的是同一个回调。
  按职责拆开：rail 只留导航（我的学习 5 项 + 设置），拿掉重复的打开媒体/打开 URL；
  卡片区只留内容动作（继续当前内容、添加来源、媒体库），学习卡改为 `if (compact)`。
  **方向刻意与 #12 原始判断相反**：媒体载入后 `MediaWorkbench` 会盖住 `ListeningHome`，
  AppBar 才是唯一常驻入口，所以收敛对象是首页这两层，AppBar 一项没动。
  关键是不能把窄窗口的路径一起删掉——rail 在 760px 以下整体消失，学习卡正是那时的
  唯一路径，因此是宽度条件渲染而非直接删除，每个宽度恰好一层拥有它们，不需要新控件。
  `listening_home_test.dart` 从 5 例增至 7 例：宽窗断言每个目的地"恰好一处"（此前那条
  测试写的是 `findsNWidgets(2)`，把重复当成了预期行为），窄窗断言全部仍可达。
  变异验证：把 `if (compact)` 改成 `if (false)`（等价于"直接删卡片"这个更省事的做法）后，
  窄窗那例立刻变红——这正是它存在的理由。analyze 零告警，全量测试 512 项绿。

- 2026-07-21: 「更多」菜单按语义分节（#16 收尾，refs #12）。导出日志（诊断）与
  词汇导出/导入、词表导入（数据管理）此前平铺在一起，读起来是一堆没有关系的动作。
  用已有的 `_MenuHeader` 加「诊断」「数据管理」两个分节头 + 一条 `PopupMenuDivider`，
  新增 l10n key `diagnostics` / `dataManagement`（en/zh；没有复用 `diagnosis`——
  那个在 zh 下是"句子诊断"，属于另一个领域概念）。
  `player_app_bar_test.dart` 的对应用例同步断言两个分节头存在，且菜单项集合不变
  （分节头不带 value，不会混进派发列表）。
  至此 #16 全部完成：必填回调 25 → 22，AppBar 不再持有任何依赖当前选中态的操作，
  仓库内 AppBar 链路英文硬编码归零。analyze 零告警，全量测试 511 项绿。

- 2026-07-21: 「纠正词元」从全局菜单移入 `WordLearningPanel`（#16 第四刀，refs #12）。
  与短语候选相反，这个功能**没有重复**，且是全应用唯一入口——后端 `correct_lemma` 是
  完整实现（写 lemma override、带"目标词已是独立词条"的冲突检测，
  `crates/application/src/lexical.rs`），删掉等于让一个已实现的后端能力彻底无法触达。
  问题只在位置：它依赖 `learningController.selectedToken`，放在全局菜单里，无选中词时
  同样是裸 `return` 静默失败。
  改为 `WordLearningPanel` 动作行上的一个可选按钮（`onCorrectLemma == null` 时不渲染），
  沿现成的可选回调管道透传，与 `onOpenListeningDictionary` 同型：组合根 → `SidePanel`
  → 面板，组合根 → `ReadingChannelHost` → `ReadingWordInspector` → 面板，听/读两条
  路径都能触达。`correctCurrentLemmaFlow` 本体不动。必填回调 23 → 22。
  新增 `vocabulary_book_test.dart` 一例：不传回调时按钮不存在，传了才渲染且点击派发。
  做过变异验证——把 `if (widget.onCorrectLemma != null)` 改成 `if (true)` 后该例立刻变红，
  确认不是空断言。analyze 零告警，全量测试 511 项绿。

- 2026-07-21: 删除 AppBar「短语候选」入口——同一功能的劣化第二套（#16 第三刀，refs #12）。
  短语候选早就有一条更好的上下文入口：`TokenLine` 把候选内联渲染成字幕行上的可点击下划线
  胶囊（`PhraseUnderlineSpan`，带 tooltip 与状态色），点击直接走 `openPhraseFlow` 存进
  词汇本，候选还随 cue 自动刷新（`MediaSessionCoordinator` / 组合根各一处 `loadPhraseCandidates`）。
  AppBar 那一项打开的是同一批数据的候选列表对话框，而且**无当前 cue 时是裸 `return`
  静默失败**——用户在首页点它不会有任何反馈。
  连带删除只被它引用的死代码：`showCurrentPhraseCandidatesFlow`、`showPhraseCandidates`
  （**复数**，候选列表对话框，~90 行）、组合根的 `_showCurrentPhraseCandidates`，
  以及随之变孤儿的 l10n key `phraseCandidates` / `noPhraseCandidates`（en/zh 各一）。
  活路径全部保留并已由测试守住：`LearningState.phraseCandidates`、`loadPhraseCandidates`、
  `TokenLine` 胶囊渲染（`learning_assets_ui_test.dart` 覆盖点击派发）、
  `showPhraseCandidate`（**单数**，短语详情弹窗，仍用 `phraseCandidatesHint` /
  `confirmPhrase`）、`openPhraseFlow`。必填回调 24 → 23。
  analyze 零告警，全量测试 510 项绿。

- 2026-07-21: 删除 AppBar 死参数 `onSearchOpenSubtitles` 及其身后的不可达分支
  （#16 第二刀，refs #12）。`PlayerAppBar.onSelected` 里有
  `if (value == 'opensubtitles')`，但 `itemBuilder` 里**没有任何 value 为
  `'opensubtitles'` 的菜单项**——这个必填回调从来不会触发，`main.dart` 的传参也是死代码。
  字幕菜单里真正的 OpenSubtitles 搜索是主/副字幕各自的 `primary-search`/`secondary-search`
  两项（标题本就是 `l.text('openSubtitles')`），不受影响。
  顺着删下去发现它还挡着一段不可达代码：`searchOpenSubtitlesFlow` 的 `bool? secondary`
  之所以可空，是为了在 null 时补弹一个"装到主字幕还是副字幕"的对话框，而**只有这个死回调
  会传 null**。既然入口不存在，该分支永远跑不到，遂把 `secondary` 收成 `required bool`
  并删掉 18 行对话框（`usePrimary`/`useSecondary` 两个 l10n key 另有活的调用方，保留）。
  必填回调 25 → 24。analyze 零告警，全量测试 510 项绿。

- 2026-07-21: AppBar 补测试安全网 + 本地化最后两处英文硬编码（#16 第一刀，refs #12）。
  新增 `test/player_app_bar_test.dart`（6 例）：AppBar 是媒体载入后唯一常驻的入口面
  （`MediaWorkbench` 会在 Stack 里盖住 `ListeningHome`），此前却没有任何 widget 测试，
  接下来要动菜单结构，先把结构钉住。按 `PopupMenuItem<String>.value` 而非标签断言四组菜单
  的成员与顺序——主/副字幕两组标签完全相同，按标签查找无法区分是哪一行触发了回调。
  写测试时发现一个此前没人注意到的事实：**四个带文字标签的菜单按钮 + 设置图标塞不进
  800×600**，默认测试画布下 `AppBar` 的 title Row 直接 overflow，因此全部用例跑在
  1400×900。这条已单独记入 #16 待评估。
  同时修掉两处英文硬编码：`player_app_bar.dart` 的 `'Correct selected lemma'` 与
  `learning_flows.dart` 里 `_LemmaCorrectionDialog` 的 `'Correct lemma'`（后者是原 issue
  漏掉的第二处，同一条链路上），统一走新增的 l10n key `correctLemma`（en/zh）。
  末例是一条通用回归闸：zh locale 下逐个展开四组菜单，断言每个菜单项文本都含汉字，
  任何绕过 `AppLocalizations` 的英文串都会立刻变红。全量测试 510 项绿。

- 2026-07-21: 播放器浮层提出为 `PlayerOverlays`（#15 追加刀，refs #12）。精讲练习窗、
  hunting 提示卡、切片播放窗这三个"浮在当前通道之上"的窗口与通道机制无关，整体搬到
  `widgets/layout/player_overlays.dart` 并自带 `ListenableBuilder`。收益是可度量的：
  `practiceController` 与 `slicePlayerController` 在整个组合根里只被这段 build 读到
  （`SidePanel`/`PlaybackBar`/`PlayerStage` 都不碰），因此双双移出聚合
  `Listenable.merge`，**11 → 9 项**（拆分前 13）。
  过程中发现并修掉一个自己引入的真实布局回归：外层 Stack 的子树换成
  `PlayerOverlays` 后，内层若是裸 `Stack`，它的子节点全是 `Positioned`（
  `IntensivePracticeWindow` 的头注明确写了"必须是 Stack 的直接子节点，Positioned 的
  parent data 才有效"），在 Stack 给非定位子节点的 loose 约束下会塌缩成 0×0，三个浮层
  直接从屏幕上消失。改为 `Positioned.fill` 包住内层 Stack，几何与拆分前逐像素一致。
  新增 `test/player_overlays_test.dart` 把这条钉住：断言浮层 Stack 尺寸等于外层
  （1200×900）且提示卡保持 18px 上边距。同样做了变异验证——把 `Positioned.fill` 换成
  `IgnorePointer` 后测试报 `Size(0.0, 0.0)` 立刻变红。`main.dart` 2013 → 1922 行。
  全量测试 504 项绿。

- 2026-07-21: 通道选择收敛为 `ContentChannelCoordinator`，`immersiveStage` 三元嵌套改 switch
  （#15 第四刀，refs #12）。新增 `controllers/content_channel_coordinator.dart`：把
  `_selectContentChannel` 里四个分支各自重复的"先拆掉别的通道"收敛成一处，`selected` 由三个
  通道协调器的 `isOpen` 派生。它**刻意不是 ChangeNotifier**——自身无状态，`selected` 是派生值。
  `ContentChannel` 枚举从 `widgets/layout/content_channel_switcher.dart` 迁到
  `models/content_channel.dart`：通道机制是领域逻辑，协调器不该 import widget 层
  （`ContentChannelAvailability` 是"为什么这个 chip 不可点"的呈现概念，留在 switcher 里）。
  组合根 build 里 118 行的 `immersiveStage` 三元嵌套变成 4 分支 switch，读起来与
  `ContentChannel` 一一对应。
  聚合 `Listenable.merge` 从 13 项降到 **11 项**（拆分前 13）：新增
  `contentChannels.selection` 一个句柄取代 `readingController + writingChannel +
  speakingActions` 三项，组合根从此看不到各通道内部的页面态抖动；`speakingTaskController`
  也一并移出——它在组合根 build 里只作为参数传给 `SpeakingChannelHost`，状态读取全在 host 内部。
  配套在 `ReadingChannelCoordinator` 上加 `openChanges` getter，明确"关心通道选择的监听者
  该听哪个"，避免误听协调器自身的页面态通知。
  新增 `test/content_channel_switching_test.dart`：按组合根同款接线（一个
  `ListenableBuilder` 监听 `selection`，`selectedChannel`/`immersiveStage` 全部派生）挂载
  `MediaWorkbench`，点击切换器走完 听→读→写→说→听 主链路，逐步断言当前 host 类型与
  上一个通道确实被拆掉。做过一次变异验证：去掉协调器里的写作拆除后该测试立刻变红
  （说通道停在 writing），确认不是空测试。`main.dart` 2039 → 2013 行。全量测试 503 项绿。

- 2026-07-21: 口语通道页面态提出为 `SpeakingChannelCoordinator` + `SpeakingChannelHost`
  （#15 第三刀，refs #12）。这一刀与前两刀的差别是：会话与音频焦点规则本就在
  `SpeakingActionsCoordinator` 里，留在组合根的是它上面一层的**页面态**——L1 理解检查
  （`_speakingL1CheckSource/_speakingL1PlayCount`）、实时会话开关（`_realtimeConversationOpen`）、
  以及会话所服务的个人表达 pattern（`_activePersonalPattern`）。新协调器持有
  `SpeakingActionsCoordinator` 而不是取代它，`isOpen` 直接转发。
  `_closeSpeakingSurface` 里纠缠的三件事按依赖方向拆开：自评弹窗、回评审队列、回个人表达页
  都是组合根拥有的 dialog/flow，改为 `askPersonalExpressionAssessment`/`onReturnToReview`/
  `onReturnToPersonalExpression` 三个 bind seam，协调器只决定"何时该问、该回哪里"；
  3.17 handoff 事实的落库逻辑本身留在协调器。`_speakingTargetCandidates` 与
  `_containsSpeakingTarget`（词边界匹配、非 ASCII 走子串）是纯函数，整体搬入。
  两处等价化的守卫内置：`closeL1Check()`/`closeRealtimeConversation()` 自带"未打开则不动"
  短路，因此三个调用点（`_selectContentChannel`、`onMediaSwitched`、写作通道的
  `closeOtherChannels`）不再各自写 `if (xxx != null)`。`speakingChannel` **不需要**进组合根的
  聚合 merge——`selectedChannel` 与 `immersiveStage` 的分支条件都是 `speakingActions.isOpen`
  （已在 merge 里），三向子分支整个在 host 内部。新增
  `test/speaking_channel_coordinator_test.dart`（9 项）覆盖候选目标的词边界/非 ASCII/
  ASR 不可靠三条规则、实时会话与 L1 检查的开启前置条件、以及关闭表面时"未完成的个人表达
  会话不落库"。`main.dart` 2231 → 2039 行。全量测试 502 项绿。

- 2026-07-21: 写作通道提出为 `WritingChannelCoordinator` + `WritingChannelHost`（#15 第二刀，
  refs #12）。新增 `controllers/writing_channel_coordinator.dart`（3 个页面态字段
  `studioSource/kind/playCount` + `openTask/close/speakText/playSource`）与
  `widgets/channels/writing_channel.dart`（`WritingTaskStudio` 分支 + 自带
  `ListenableBuilder`）。两处刻意的形制调整：(1) 跨通道收尾（关口语 L1 检查、关口语会话、
  关阅读）不进写作协调器，改为 `closeOtherChannels` seam 由组合根注入——写作通道不该知道
  "阅读""口语"是什么，这块归 #15 第四刀的通道协调器；(2) `speakWritingText` 原先在协调逻辑里
  直接 `ScaffoldMessenger` 弹 SnackBar，现改为 `Future<bool> speakText()` 返回合成是否可用，
  由 host 在有 context 的地方提示，协调器层不再依赖 widget。本地化 prompt/rubric 模板同阅读刀，
  由 host 从 context 自取。顺带修掉本刀自身引入的一个回归：`writingChannel.isOpen` 同时驱动
  组合根 build 里的 `selectedChannel` 与 `immersiveStage` 分支，而 host 的
  `ListenableBuilder` 只覆盖 studio 子树，因此 `writingChannel` 必须留在组合根顶部的聚合
  `Listenable.merge` 里（否则从通道切换器打开写作时组合根不重建，studio 不出现）——merge 列表
  回到 14 项，真正的瘦身要等第四刀把通道选择收敛进 `ContentChannelCoordinator`。新增
  `test/writing_channel_coordinator_test.dart`（5 项）覆盖锚定播放头所在段落、无字幕轨为空操作、
  切换写作类型重置回放计数、关闭清空 source、以及合成不可用时的返回值契约。
  `main.dart` 2329 → 2231 行。全量测试 493 项绿。

- 2026-07-21: 阅读通道视图提出为 `ReadingChannelHost`（#15 第一刀收尾，refs #12）。新增
  `widgets/channels/reading_channel.dart`：`_readingView()` 的四表面选择（任务工作台 >
  读听对照 > 听力回述 > 阅读器+词条检视器）整体搬入 StatelessWidget，顺序与每个回调原样保留。
  本地化模板（`readingTaskTemplate`/`listeningRetellTemplate`）改由 host 自己从 context 取，
  组合根不再为阅读分支持有 `l`；`PersonalExpressionSourceView` 的构造也搬进 host（只读它
  已持有的 player/subtitle），组合根侧只剩 `onSaveSentencePattern` 一个回调。原先的
  `api != null` 分支守卫去掉——host 只在组合根 `api != null` 的分支下构造，`api` 收为非空参数。
  host 自带 `ListenableBuilder`（readingChannel + reading/learning/settings/subtitle），
  组合根顶部的聚合 `Listenable.merge` 因此摘掉 `readingChannel`（14 → 13 项，#12 第 2 项的
  首笔收益）。新增 `test/reading_channel_host_test.dart`（4 项）覆盖静息态是阅读器、
  词条检视器开合、对照卡→回述面板的让位、以及任务工作台优先级最高。`main.dart` 2418 → 2329 行
  （本刀累计 2639 → 2329）。全量测试 488 项绿。

- 2026-07-21: 阅读通道页面状态机从组合根提出（#15 第一刀，refs #12）。新增
  `controllers/reading_channel_coordinator.dart`：`ReadingChannelCoordinator` 接管
  `_PlayerScreenState` 里的 8 个阅读页面态字段（任务工作台/读听对照/听力回述/词条检视器
  各自的 source，听力回述播放计数，以及阅读游标的防抖计时器与最后保存锚点）与 12 个相关方法
  （`open/close/openWord/openTask/openDiff/openListeningCheck/playRange/savePosition` 等）。
  形制照抄 `SpeakingActionsCoordinator`（`isOpen` + open/close + `bind()` 注入
  `getApi/isMounted` 与宿主 seam），getter 名镜像原字段名，便于逐处比对。`api`/`isMounted`
  走 bind seam 而非构造参数，`close()` 因此保持无参，可直接作为 `closeReading` 回调传给
  口语协调器。切片回放与词条打开经 `openSlicePlayback`/`openWord` 两个回调回到宿主，
  协调器本身不依赖 widget 层。行为等价搬运：`setState` 换成 `notifyListeners()`（组合根
  build 顶部的 `Listenable.merge` 加入 `readingChannel`），唯一签名变化是
  `openListeningCheck` 去掉了原先从未使用的 `paragraph` 形参。新增
  `test/reading_channel_coordinator_test.dart`（8 项，走注入 transport 的假后端）覆盖游标恢复、
  任务/对照/回述三个面板的开合、`close()` 一次性收尾全部表面、切片回放 occurrence 快照，
  以及游标写入的防抖与去重。`main.dart` 2639 → 2418 行。全量测试 484 项绿。

- 2026-07-21: 内核降级播放状态改走本地化（承接上一条的副作用修复）。
  `media_session_coordinator.dart` 里 `'Playing locally; core unavailable: $coreError'`
  是硬编码英文，违反"用户可见文案一律走 `AppLocalizations`"的约定；此前被
  `startsWith('Playing')` 吞掉所以看不见，上一条把它放出来后这个问题才显形。新增
  `statusPlayingCoreUnavailable`（en/zh），措辞同时点明"本地播放中"与"本地内核不可用"。
  顺带核对了 en/zh 的键覆盖：zh 多出的 9 个 `l1_difficulty_*` 是有意为之——`l1Difficulty()`
  在缺键时回落到后端给出的英文解释，因此 en 侧本就不该有这些键，不是遗漏。
- 2026-07-21: 集中响应式断点 + 三个小修（#14，refs #12）。(1) 新增
  `lib/theme/breakpoints.dart`：9 处散落在 `LayoutBuilder` 里的宽度阈值收敛为
  `ListenBreakpoints` 的语义化常量（含 issue 未列出的 `reading_word_inspector.dart` 980）。
  数值相同但理由不同的（760 出现在首页侧栏与播放控制条、900 出现在播放控制条与阅读面板）
  保留为两个常量而非合并——它们各自来自所在部件的可用宽度，本就可以独立漂移；播放控制条
  900 的原有注释原样搬进常量文档。新增 `test/breakpoint_discipline_test.dart` 扫描 `lib/`，
  禁止再出现裸数字阈值（仿 `theme_palette_discipline_test.dart`，三位数以上才算断点，
  避免误伤 `maxWidth <= 0` 这类退化约束守卫）。(2) `_timingQuality` 去掉 map 查找上的 `!`：
  数据缺失时返回空串而非崩溃；`side_panel.dart` 调用侧本就有 timings 非空守卫，
  `diagnosis_card.dart` 的显示条件顺带收紧为非 null 且非空。(3) 修复 `dispose()` 里最后一次
  进度保存与 sidecar 关停的竞态：`requestStop()` 会 `_client.close(force: true)`，与
  `unawaited(saveProgress(...))` 并发即中断在途请求、丢掉退出时的播放位置。改为抽出
  `_stopApiAfterFinalProgressSave()`，保存完成后再串行 `requestStop`（2s 超时兜底），
  仍不阻塞 `dispose` 本身；app 先退出时由 sidecar 的孤儿 watchdog 回收。(4) 首页"本地内核"
  卡片不再用 `statusText.startsWith('Playing')` 判断——Slice 3 本地化后该前缀对中文永远不成立，
  播放中会把"正在播放 X"当成内核状态显示。改为 `PlayerState` 新增 `statusIsPlayback` 标志
  （与既有 `statusIsError` 同构），由 `setStatus(..., playback: true)` 在两处播放状态设置点标注，
  组合根据此过滤后传入更名后的 `coreStatusText`。顺带修掉旧启发式的一个副作用：
  "Playing locally; core unavailable: …" 这条真正的内核降级消息此前也被前缀匹配吞掉，
  现在标为非 playback、可以正常显示。新增两项测试（播放标志的置位/清除、zh 语言下的卡片渲染）。
  analyze 零告警，Flutter 476 项测试通过。
- 2026-07-21: sidecar 正常退出改走优雅关闭。桌面端 `dispose()` 原先发 SIGKILL，sidecar 因此
  在常规退出时也拿不到 graceful 路径、数据库只能靠崩溃恢复。有了孤儿 watchdog 兜底后，
  `LocalApi.kill()` 改名 `requestStop()` 并改发 SIGINT：常规退出优雅关库，若 app 先一步消失
  则由 watchdog 在 2s 内回收。连带修掉两个由此暴露的问题：(1) 强制退出兜底原先只挂在
  `orphaned()` 分支上，改发 SIGINT 后走的是 ctrl_c 分支，兜底永不武装、graceful drain 卡住
  就会重新变成孤儿——现改为无论哪个分支触发都武装；(2) SIGINT 处理器原先要等 `axum::serve`
  首次 poll 才安装，而握手在那之前打印，父进程一见握手就发信号会落到默认动作上被杀——现改为
  在 `main` 开头即安装（新增 `Interrupt` 类型，non-unix 回落 `ctrl_c`）。
  `tests/orphan_watchdog.rs` 更名 `tests/shutdown_lifecycle.rs` 并新增 SIGINT 用例：断言退出码
  为 0（若信号未被处理则是被信号杀死、无退出码，测试首次运行正是这样失败并暴露了竞态）。
  实机复核：`osascript quit` 后 app 与 sidecar 死亡间隔 266ms，远小于 watchdog 的 0~2s 轮询
  窗口，证明 `dispose()` 确实执行且 SIGINT 确实送达。api-http 66 项、Flutter 473 项测试通过。
- 2026-07-21: 修复 api-http sidecar 在桌面端异常退出后成为孤儿进程。桌面端只在 `dispose()`
  里关闭 sidecar，而崩溃、强制退出、任何 SIGKILL 都不会执行 `dispose()`，sidecar 随即被过继给
  pid 1 长期滞留——每次这样的退出泄漏一个进程、一条数据库连接和一个端口（本机实测确有 PPID=1
  的残留）。修复放在 sidecar 一侧（这是唯一能覆盖父进程被 SIGKILL 的位置）：启动时记录父 pid，
  每 2s 比对一次 `getppid()`，一旦变化即走既有的 graceful shutdown；若 5s 内没退干净则强制
  `exit(0)`，避免挂住的连接把进程留下。启动时父 pid 已是 1 的合法场景（如已守护化）不会被误判。
  新增 `crates/api-http/tests/orphan_watchdog.rs`：经中间 shell 拉起 sidecar，先断言父进程健在
  时 4s 内不自杀（防止误杀比泄漏更糟），再 SIGKILL 父进程并断言 sidecar 20s 内退出；已验证该
  测试在停用 watchdog 后会以 "sidecar outlived its parent" 失败。测试使用临时 HOME 与
  `LLPLAYERNEXT_DB`，不触碰真实数据库。另在真实路径复核：`flutter run` 起 app 后 SIGKILL
  app 进程，sidecar 1s 内自行退出、无残留。api-http 65 项测试通过。
  注：桌面端 `dispose()` 目前发的是 SIGKILL（`LocalApi.kill()`），sidecar 因此在正常退出时也
  拿不到 graceful 路径；SQLite 本身崩溃安全，故未一并改动。
- 2026-07-21: 修复设置对话框在组合根重建时整棵树崩溃。`_SettingsDialogState.didUpdateWidget`
  无条件重跑 `_initFromWidget()`，而后者会重新赋值 4 个 `late final` TextEditingController，
  第二次即抛 `LateInitializationError`，并级联出 deactivated-ancestor、
  `renderObject.child == child`、`_dependents.isEmpty`、Duplicate GlobalKey 等一连串断言，
  最终红屏 + Lost connection。触发条件是"对话框打开时组合根重建"——切界面语言早已能触发，
  Slice 4 的外观切换只是让它变成必经路径。改为：控制器在 `initState` 建一次并持有到销毁，
  `didUpdateWidget` 只重新采纳标量设置，且仅在宿主真的改了对应路径时才覆写文本框（否则会
  丢掉用户未保存的输入）；`_initFromWidget` 更名为 `_adoptSettings` 以反映语义。
  仓库内 `word_learning_panel`/`intensive_practice_window`/`listening_dictionary_entry_view`
  已是此写法，本次是让唯一的例外对齐既有约定。新增回归测试：宿主在对话框打开期间切换
  themeMode，断言不抛异常、对话框存活、主题生效且采纳新值（已验证该测试在修复前会以生产
  同款 `LateInitializationError` 失败）。全量 473 项测试通过。
- 2026-07-21: 推进 GitHub #13（#12 Slice 4）：实现暗色主题 `ListenTheme.dark()` 并支持
  跟随系统/浅色/深色三态切换与持久化。`light()`/`dark()` 收敛为共享的 `_build(ColorScheme)`，
  组件主题（appBar/card/dialog/menu/input/slider/switch/chip/tooltip 等）一律从 scheme 派生，
  浅色输出与改造前逐项等价；`ColorScheme` 没有槽位的两个色（disabled 前景、text/outline 按钮的
  pressed 主色）提取为 `ListenSchemeShades` 扩展，作为唯一真源同时供主题与调用点使用。
  暗色表面锚定在 `ListenColors.player` 近黑上（新增 15 个 `dark*` 常量），品牌青在暗色下提亮为
  `#5cc6b8` 以满足 AA。新增 `themeMode` 设置字段（AppSettings/SettingsController/settings_dialog
  外观三选/settings_flow 回写）与全局 `appThemeMode` ValueNotifier，`MaterialApp` 接
  `darkTheme` + `themeMode`，`_loadSettings()` 启动时回灌，重启后保持。
  关键前置工作：13 个 chrome 组件文件中 168 处硬编码亮度相关色（surface/border/muted/fog/
  selected/disabled/infoSurface 与 primary/accent/info/error）全部改为 `Theme.of(context)
  .colorScheme.*`，否则暗色下必然出现白底与低对比文字；`capabilityAssessmentColor` 等 4 个
  枚举→色映射函数改为显式接收 `ColorScheme`。按需求保留 `widgets/subtitle/` 覆盖层的独立暗色
  词汇（渲染在任意视频帧之上，不随主题切换）。新增 6 项测试：暗色 scheme 断言、双主题组件结构
  一致性、WCAG AA 对比度逐对校验（正文/次要文字/四个状态色/容器对）、`themeModeFromSetting`
  映射、themeMode 端到端生效，以及一条源码级不变量测试（`theme_palette_discipline_test.dart`）
  防止后续再把浅色常量写回 chrome。flutter analyze 零告警，全量 472 项测试通过。
  注：作者本机系统为浅色，暗色外观仅经上述程序化校验，未做人工目视确认。
- 2026-07-21: 修复 debug 模式下应用永久卡在启动页（白屏 + "Starting local core..."）。Slice 3 把
  `_connectApi()` 的首行状态文案换成 `l.text('statusStartingCore')` 后，该调用经 `initState`
  同步执行，`AppLocalizations.of(context)` 在 initState 完成前访问 InheritedWidget 触发断言抛出；
  异常又落在 `try` 之外，逃逸成未捕获的 unawaited future，于是 `connectingApi` 永远为 `true`、
  `api` 永远为 `null`，`LocalApi.connect()` 从未执行到 `Process.start`（实测无任何 api-http 子进程）。
  改为经 `addPostFrameCallback` 在首帧后发起连接，并把 `try` 上移包住整个函数体，使同步段的任何
  异常都走错误态而非静默无限转圈。实测：未捕获异常归零，sidecar 正常拉起，进入首页。
  注：此前怀疑的"僵尸进程锁 SQLite"已证伪——系统无 api-http 残留、无 `-wal`/`-shm`，
  sidecar 单独启动握手仅 0.22s。
- 2026-07-21: 推进 GitHub #12（Slice 3）：统一错误呈现 + 本地化全部状态栏硬编码字符串。
  `PlayerController.setStatus` 新增 `error` 标志（`statusIsError` 进入 PlayerState）；错误状态
  在播放条状态行以 error 色 + 图标渲染，并由组合根监听、每条新错误弹一次 SnackBar。约 90 处
  硬编码 `setStatus('English...')` 全部改走本地化 key（新增 en/zh 各 ~135 词条）：main.dart 与
  四个 flow 文件直接用 `l.text`；media_session/vocabulary/media_library 等沿用既有 text seam；
  resource_actions/playback_actions/practice_actions/listening_inbox/subtitle_sources 的 bind
  新增可选 `text` seam（缺省回退 key，测试断言 key）；speaking_actions 与 backend_event 补
  text 注入。同时本地化两处反向硬编码中文：main.dart 个人表达自评对话框（peAssess* 词条）与
  review_queue_screen 整屏（reviewTitle/reviewKind*/reviewHint*/评分按钮等 ~38 词条），
  presence 选择值由 '出现/没出现' 改为语义值 present/absent。更新 6 个测试文件的期望到 key
  约定。flutter analyze 无告警，Flutter 466 项全过。

- 2026-07-21: 推进 GitHub #12（Slice 2b）：逐词/逐块/逐音素高亮游标退出聚合通知。
  `currentWordToken`/`currentChunkIndex`/`currentDetectedPhone` 从 `SubtitleState` 移出，
  改为 `SubtitleController` 内部专用 `ValueNotifier`（对外暴露 `*Listenable`）——此前逐词
  高亮每个词边界、音素彩带每个音素（开启时 10-20Hz）都会经 `Listenable.merge` 重建整棵树。
  消费方改为局部订阅：PlayerStage 的 TokenLine（merge position/word/chunk，chunk 高亮关闭
  时不挂 position tick）、声音结构区域（merge position/word）、SidePanel 的 DiagnosisCard
  实时音素显示（ValueListenableBuilder）。`clearSpeechEnhancements` 同步重置游标。
  新增回归测试：updateCurrentWord 触发 scoped 通知且聚合通知为 0。Flutter 466 项全过。

- 2026-07-21: 推进 GitHub #12（Slice 2a）：消除播放期 10Hz 全树重建。`position` 从
  `PlayerState` 移出，改为 `PlayerController` 内部专用 `ValueNotifier`（`positionListenable`），
  `setPosition` 不再触发聚合 `notifyListeners`——此前每 100ms 一次的位置轮询会经
  `Listenable.merge` 重建整个 Scaffold（AppBar/首页/工作台/侧栏/播放条）。真正渲染实时进度的
  四处改为局部订阅：PlaybackControls 的进度条与时间标签（compact/full 各自最小包裹）、
  PlayerStage 的 TokenLine（仅 chunk 高亮开启时才挂 10Hz tick）、音素彩带、节奏彩带区域。
  同步读取方（saveProgress、循环判断、flows）经 getter 不受影响。删除无人使用的
  `positionFraction`。新增回归测试：10 次 position tick 聚合通知为 0、位置通知去重。
  flutter analyze 无告警，Flutter 465 项全过。

- 2026-07-21: 推进 GitHub #12（Slice 1）：修复 `Store` selector slot 泄漏。`StoreBuilder`/
  `StoreBuilder2` 不再调用 `Store.select()` 注册 slot，改为监听聚合通知并本地 memoize 选值——
  内联闭包不再随父级 rebuild 无限累积 `ValueNotifier`，顺带修复旧实现不处理 `store` 实例
  变化导致监听残留在旧 store 上的 bug。`Store` 新增 `dispose()`（释放全部 slot notifier）与
  `debugSlotCount`（测试用），并在文档中明确 slot 仅供长生命周期 selector 使用的契约。
  新增回归测试：20 次父级 rebuild 后 slot 数为 0、新闭包仍持续跟踪更新、store 换绑后旧 store
  更新被忽略、dispose 释放 notifier。Flutter 464 项全过。

- 2026-07-21: 完成 GitHub #9（前端）：移除 Speaking/Writing 的 rubric 自评，LLM 反馈改为
  带完整上下文的教师式自由文本。Speaking 去掉 assessing 阶段（阶段条剩 听/录/核对/完成），
  ready_feedback 保存录音、确认词汇目标后直接「完成任务」进 done，不再写 self_assessment
  judgment；Writing 去掉意义自检（selfVerdicts/selfAssessment），提交修订只写 attempt 与
  finding dispositions。两个 studio 的逐点 LLM judgment + 逐点纠正（adjudicateLlm）替换为
  新的 LlmFeedbackAssist 组件（请求 `POST /v1/llm/providers/{id}/feedback`，展示 prose 点评，
  不落库）；Reading 的 rubric 自评与逐点 judge 保持不变。main.dart 的 pattern-production
  收尾改为弹一次性自评选择（personal expression 3.17 交接事实仍必填）。OpenAPI 登记新路由。
  flutter analyze 无告警，Flutter 459 项全过，api-http 52+12 项全过。

- 2026-07-21: 推进 GitHub #9（后端）：新增输出通道自由文本反馈 seam。application 增加
  `OutputFeedbackRequest/Draft` 与 `OutputFeedbackProvider` trait（携带 source_transcript +
  prompt_snapshot + learner_response 完整上下文）；`feedback_on_semantic_attempt` use case
  从存储的 attempt/rubric 组装请求、调 provider、返回 ephemeral 草稿（不落库、不写
  observation/projection）；llm-provider 以 `{feedback: string}` schema 实现（prompt 版本
  output-feedback/v1，教师式定性点评、禁止打分）；HTTP 新增
  `POST /v1/llm/providers/{id}/feedback`。Reading 的 rubric judge seam 原样保留。
  contract 测试补双协议一致性与空反馈拒绝两条，15 项全过。

- 2026-07-21: 推进 GitHub #7（问题四）：realtime provider 对话框的 Qwen 配置支持中国站。
  选择 Qwen 适配器后新增 Region 下拉（International dashscope-intl / China Model Studio），
  中国站模式提供 Workspace ID 输入并实时拼出
  `wss://{workspaceId}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime`，未填 workspace
  时占位 endpoint 不允许保存。flutter analyze 通过。

- 2026-07-21: 推进 GitHub #7（问题五）：提交 Qwen Omni Realtime 真实 provider 集成测试
  `crates/realtime-provider/tests/qwen_integration.rs`。测试以 `#[ignore]` + `QWEN_API_KEY`
  / `QWEN_WORKSPACE_ID` 环境变量门控，不含任何有效密钥；覆盖 WebSocket 握手 + Bearer 认证、
  SessionReady、PCM 音频发送、事件接收与关闭。realtime-provider 增加 rustls dev 依赖。

- 2026-07-21: 修复 GitHub #5（D-319-22）：精听练习窗口切换相邻句不再闪烁。根因：切句会新建
  practice item，`_createItemFromDraft` 先把 `item` 置空再等待 API，而窗口挂载条件是
  `item != null`，在途期间整窗被卸载、返回后重挂。现挂载条件放宽为 `draft != null ||
  item != null`（draft 在切句时同步更新、只有关闭才清空），窗口内容也只依赖 draft 渲染
  prompt（在途期间 `busy` 已禁用提交），实现原位更新；prompt 视图补显 `controller.error`，
  避免创建失败时窗口驻留却看不到错误。新增「item 在途期间 prompt 持续可见」回归测试；
  全量 459 项 Flutter 测试通过。

- 2026-07-21: 修复 GitHub #1（D-319-12）：首页新增「我的表达」稳定主入口。左侧「我的学习」
  在词汇与复习之间加入「我的表达」项，资产区新增同名卡片（含摘要文案，中英文案均补充
  `personalExpressions`/`personalExpressionSummary`）；点击进入既有 PersonalExpressionScreen
  （标题、搜索、新建、列表齐备），返回后回到首页。资产区网格改为每行最多 3 张卡并自动换行，
  避免 5 张卡挤在一行。补充宽/窄两种布局的入口 widget 测试。

- 2026-07-20 21:06 CST: 撤销 Owner Journeys v2 Q3 初版并登记 D-319-23/GitHub #6。初版未按
  代码核对，错误臆造 Hunting 启动后的目标数/预算常驻 UI、三态作答后的影响说明、证据跳转与 fit
  反馈，同时遗漏 `I` 加入 Listening Inbox、`Shift+I` 开始/结束泛听、`Shift+P` 暂停捕获并快速
  检查。按 owner 裁决改为低打扰契约：目标只在出现点前后短暂 priming/check；作答成功只安静
  后台记录并关闭提示，错误才打断；详细影响留给用户主动打开的 evidence/history。Q3 重写为八个
  基于真实入口的步骤，原 Q3.1–Q3.5 全部作废，不计为产品 FAIL；同步 correction 与 subtraction
  audit，D-319-04 收窄为显式回访入口问题。

- 2026-07-20 20:54 CST: Q2.6 按重写后的真实入口补测 PASS：有字幕媒体 → 右侧文稿当前句 →
  「测一下？」→「整句听写」→ 练习窗口播放/暂停，当前句边界与停止行为成立。同时发现相邻句
  导航独立 P2：点击上一句/下一句时当前练习 panel 瞬间消失后返回；登记 D-319-22/GitHub #5，
  目标为窗口/panel 持续驻留、只在原位更新句子与练习内容。Q2 整体仍因 D-319-20/21 FAIL。

- 2026-07-20 20:48 CST: 记录 Owner Journeys v2 Q2：Q2.1–Q2.3、Q2.5 有字幕主场景、Q2.7
  PASS；Q2.4 因结束泛听摘要缺少本次实际时长改判 FAIL，并登记 D-319-20/GitHub #3；无字幕
  媒体点击精听仍暴露不可执行的当前句/短段任务，登记 D-319-21/GitHub #4，要求真实 unavailable
  状态与字幕导入/生成恢复动作。Q2.6 原文“选择一条句子，播放来源一次”没有对应清晰入口，属于
  QA 脚本错误而非 owner FAIL；现已重写为“右侧文稿选当前句 → 测一下？ → 整句听写 → 练习窗口顶部
  圆形播放/暂停”的可执行步骤，等待单项重测。

- 2026-07-20 20:14 CST: 记录 Phase 3.19 Owner Journeys v2 的 Q1 首轮结果：Q1.3「复习」与
  Q1.5 Coach 主入口 PASS；Q1.1/Q1.2 因首页「我的学习」缺少「我的表达」主入口 FAIL，Q1.4
  因词条详情缺少「证据与历史」入口 FAIL。Run 1 的 D-319-12、D-319-09 分别补充 Run 2
  复现证据并登记 GitHub #1/#2；两项保持独立 P1 入口缺陷，修复前不允许用顶部高级菜单或
  内部路径绕过。

- 2026-07-20 14:46 CST: 将 Phase 3.19 提升为 subtraction-first 产品硬门：遗留 P1、入口、任务
  边界、结果可见性与返回路径未收口，且 Phase 3.x 假需求/假 fallback 未完成 KEEP/SIMPLIFY/
  REMOVE/UNAVAILABLE/DEFER RESEARCH 审计前，禁止规划或建设任何新功能。新增 LOOP-024/025，
  同步 PROJECT/ROADMAP/STATE/AGENT 与 correction plan。Run 1 J0–J5 保留为历史证据，新增
  `3.19-OWNER-JOURNEYS-V2.md` 作为 Run 2 目标体验契约：固定首页/内容工作台主入口，并为媒体库、
  泛听/精听、狩猎、Review、证据建议、我的表达、说写选区、Coach、Realtime、Embedding、TTS
  逐步写明准备、准确点击、即时反馈、任务边界、持久写入、回访位置与失败条件；主入口缺失直接
  FAIL，禁止让 owner 用高级菜单、开发者工具或内部知识替产品寻找路径。新增 live subtraction
  audit，已对媒体模式、fit、Hunting、Review、evidence/proposal、Speaking、Personal Expression、
  Coach、Realtime、Embedding、TTS 与数据完整性路径给出首轮 KEEP/SIMPLIFY/REMOVE/PROVE 裁决。

- 2026-07-20 13:54 CST: Phase 3.19 owner Run 1 完成首轮全局旅程：J0 packaged-app smoke 全部
  PASS，J1/J2 部分通过并暴露 Review 驻留体验、精听/泛听语义、任务输入单位、效果可见性、
  Personal Expression IA/选区等 P1 缺口；J3 麦克风权限、J4 embedding 安装阻塞，J5 在 UX
  裁决前延期。新增 ADR 0025/0026、项目 glossary 与 product-correction 计划，把显式有界
  ContentSelection 和 goal-preserving fallback 固化进 PROJECT/REQUIREMENTS/ROADMAP/STATE/AGENT。
  以 owner 原始症状先建立红测试，再修复 Review 当前页播放/暂停及 Realtime 捕获前主动请求
  macOS 麦克风权限；两项定向回归、Flutter analyze、456 项 Flutter 全量测试及 macOS Debug
  build 通过，等待重打 package 后 owner 复测。当前 release 结论为 DO NOT RELEASE YET，
  冷启动数据不通过伪造学习记录解锁。

- 2026-07-19 08:42 CST: 将 Phase 3.19 release acceptance 从粗粒度 QA 索引扩写为可直接执行的
  owner 测试脚本。新增统一 PASS/FAIL/BLOCKED/N/A 记录协议、数据库副本与停止规则、合法 writer
  对比严格只读 surface 的边界、七个推荐执行批次；J0–J5 与 multilingual check 细化为逐步准备、
  操作、预期结果和记录栏，完整覆盖 content fit/Hunting/≥8 Review cards、Speaking/Role Reply、
  Personal Expression version/export/offline/delete、proposal reject/confirm/override/rebuild、Coach typed
  return/source loss、realtime failure matrix、embedding lifecycle/scale、TTS audio focus/cache。附加只读
  SQLite count snapshot 与原 phase QA disposition 映射；所有 owner 结论仍保持 pending。

- 2026-07-19 00:44 CST: 启动 Phase 3.19 Product Validation & Release Closeout。Phase 3.x
  进入 feature freeze，把 3.4/3.5/3.14/3.15.7/3.15.8/3.15.9/3.16/3.17/3.18 分散的 owner QA
  合并为五条风险优先端到端旅程，并建立统一 release acceptance、P0/P1 defect policy 与 owner
  ACCEPT / DO NOT RELEASE 出口；不新增产品能力、不预定 Phase 4。首轮自动基线全绿：full strict
  Rust 685、Flutter 453、contracts 5 examples，0 failed；macOS release build、zip integrity、解压后
  deep/strict ad-hoc signature、sidecar/runtime/notices 均通过。真实 GUI 首次启动、媒体、麦克风、
  provider、embedding scale、TTS 听感和 owner 数据旅程仍明确 pending，未由实现者代验。

- 2026-07-18 23:17 CST: Phase 3.18 Cross-modal Coach code complete。按 `main@88223b0b`
  重审并收紧旧 PLAN：Coach 只聚合、解释和编排既有事实/资产，不创建综合等级、跨通道蕴含或
  第二 capability authority。SQLite bounded live read model 分层返回四通道 attempt、supporting
  judgment、adjudication、observation、proposal、confirmed projection、history 与 personal-
  expression attempt；effective assessment 保持 3.17 override 优先，unassessed 不算失败。新增
  typed provenance/immutable snapshot/source-unavailable 降级、provider-independent availability、
  typed Review/Hunting/Cross-modal Review/Personal Expression destination 与 Flutter return context；
  无 schema/cache/rebuild 或 learning writer。Rust 受影响 crate 250 unit tests + 23 integration/
  migration tests、strict Clippy、Flutter analyze/453 tests、contracts 全绿。owner 真实数据/来源失联/
  GUI QA 留 `3.18-MANUAL-QA.md`，未执行或冒充相邻阶段 owner QA。

- 2026-07-18 21:02 CST: Phase 3.17 Four-channel Projection & Cross-modal Review code complete。
  按 `main@5bf8fbd3` 重审 authority 与真实 evidence 底盘，新增 SQLite v44 append-only proposal/
  decision、Reading v1/Listening v2/Speaking v1 独立算法、Writing `insufficient_evidence`、显式
  confirmation 唯一 projection writer、override 优先、history、算法 supersede 与全语言 rebuild。
  observation append 和旧 upgrade confirmation 不再直写 projection；cross-modal read model 不把
  unassessed 当失败，并保留 source ref/immutable snapshot。OpenAPI、typed Dart client、词典资产层
  proposal gate 与跨通道队列贯通。`UserSentencePattern`、分通道 immutable attempts、Hunting List、
  corpus/embedding 边界及 FocusTarget 拒绝保持不变；owner 真实库/重启/来源丢失体验留
  `3.17-MANUAL-QA.md`，未执行或冒充相关 owner QA。

- 2026-07-18 20:20 CST: Phase 3.16 Personal Expression & Sentence Patterns code complete。
  按 `main@c86a5952` 重审旧 PLAN，并以三 consumer razor 拒绝通用 FocusTarget：不迁移已验收的
  Hunting List，不以 3.17 未来 consumer 提前泛化。新增 SQLite v43 durable
  `UserSentencePattern`、不可变来源快照/append-only version/slots、分通道 immutable attempt，
  来源媒体无 FK cascade；system construction ref 可空且不覆盖用户模板。CRUD/search/history/
  typed JSON export、OpenAPI/Flutter client、Reading 句内显式收藏与“我的表达”资产旅程贯通；
  Writing 保存用户 typed response，Speaking 复用既有录音→local ASR→corrected transcript 住户。
  embedding/corpus 只可提供显式候选 provenance，零自动收藏/扩写及 observation/projection/
  proposal/confirmation writer。Rust workspace、strict Clippy、contracts、Flutter analyze/full tests
  全绿；owner 真实媒体/麦克风/重启/来源删除/离线体验留 `3.16-MANUAL-QA.md`，未执行或夹带
  3.15.7/3.15.8/3.15.9 的独立 owner QA。

- 2026-07-16 22:21 CST: Phase 3.15.8 Semantic Embedding code complete。先以真实 FastEmbed
  all-MiniLM-L6-v2/ONNX 与 Ollama all-minilm 两条异构路径 spike；两者虽同为 384-d MiniLM，
  数值空间显著不同，因此 fingerprint 固定 provider/model revision/runtime/artifact SHA/dimension/
  normalization/purpose/index schema，禁止跨空间比较与迁移。新增 provider deep module、显式
  +0B-base 本地模型 lifecycle、OpenAI-compatible seam、SQLite v42 float32 BLOB 原子可重建索引，
  media + written/spoken local-authoritative production 按意思 top-K 与 source/model provenance。
  3.15.6 原 top-K/readiness/ranking 不变，只给既有 target additive near-semantic clue，明确不是
  synonym/capability truth，零 attempt/evidence/observation/capability/proposal/review/corpus writer，
  3.17 gate 保留。OpenAPI/typed Dart/词汇册 install-rebuild-search-disable-delete UI 贯通；验证含
  真实 production adapter smoke、Rust workspace、strict Clippy、contracts、Flutter analyze/full、
  macOS Debug build。owner 首次安装/离线/大语料体验 QA 留独立清单；未执行 3.15.7 provider/
  device QA、3.15.9 听感 QA或 hunting 毫秒 flaky 修复。

- 2026-07-16 17:32 CST: Phase 3.15.6 Cross-channel Production Gap Review 实现。以 3.15.5
  rebuildable corpus 与 reading/listening capability、成功 observation、recognition contexts
  做只读 gap-(c) join；排序固定为 ECDICT BNC rank band → 接收证据强度 → 近期性 → lemma，
  只返回 top-K 并逐项解释。新增 `empty/starter/ready` 诚实降级：owner 真实只读副本探针仅
  1 document / 1 token / 1 lemma，因此不做小样本伪校准，starter 靶子明确不是能力结论。
  词典资产页新增最小复盘入口并回到既有词汇/复习动作；全链路零 attempt/evidence/observation/
  capability/projection writer。spoken、embedding 近义、durable template 与确认门分别留给
  3.15.7、3.15.8、3.16、3.17。

- 2026-07-16 18:10 CST: Phase 3.15.9 TTS code complete。新增 application provider-neutral
  synthesis port 与 local-runtime manager（校验、voice 选择、稳定 cache key、single-flight、原子
  发布、统计/清理），macOS production 使用零下载离线 `/usr/bin/say` system voice；HTTP/OpenAPI/
  typed Dart client 贯通。Flutter 以共享 auxiliary audio controller 统一 dictionary remote audio
  与 TTS，播放前获取焦点并在替换/录音/真实 reference/销毁时释放。词典标准音频与真人 slice
  继续优先，缺失才 synthetic fallback；personal corpus/Writing 只朗读 learner-owned text。
  TTS 零 learning repository/writer，保持 3.15.5 projection-vs-authoritative-asset 边界。验证：真实
  system speech smoke、Rust manager/route/OpenAPI、contracts、Flutter 全量 442 项、analyze 全绿；
  owner GUI 听感 QA 保留清单，未冒充已验收。

- 2026-07-16 16:15 CST: Phase 3.15.9 TTS 开工审计并将 PLAN 修订为 READY v2。按
  `main@1614ed74` 实际底盘否决“直接照搬 Piper/七态下载生命周期”的预设：macOS 系统语音
  已提供零下载、离线、多语言 voice 与文件输出，v1 先以其作为本地 adapter，Piper 保留为经
  质量/许可/体积审计后的跨平台候选。新计划把浅的“文本→音频”深化为 provider/voice 描述、
  规范化请求、稳定 cache identity、single-flight/原子发布、取消与资源清理的 synthesis module；
  明确 dictionary 标准音频优先/TTS 明示 fallback、真人 slice 优先、Writing 只读 learner text，
  以及零 attempt/corpus/observation/judgment/projection writer。Flutter 将统一 remote pronunciation
  与 TTS 的 auxiliary playback/单音频焦点，但各场景保留独立 surface。

- 2026-07-16 16:07 CST: Phase 3.15.5 Personal Production Corpus 完成。新增 SQLite v39
  document + lemma occurrence + FTS5 可重建投影；Writing typed attempt 成功落库后 best-effort
  增量刷新，全量 reindex 先派生后单事务替换，失败保留旧投影。完整回答每 document 只存一份，
  token 保存 surface/lemma/Unicode-scalar span；新增 exact lemma/phrase FTS HTTP API、OpenAPI 与
  Flutter 词典「我的产出」（次数、回答、revision/assistance、原 attempt revision 链，加载/空/
  不可用三态）。原 `scaffolding: bool` 修正为 factual assistance provenance，零 spoken writer、
  零 observation/capability writer。3.16 边界裁定为可重建语料投影 vs 显式 durable 模板资产。
  v39 migration 遵守 additive/idempotent 约定并通过 v29/v30 旧库升级回归。验证：production
  persistence 3 项、api-http 端到端、Clippy strict、Flutter 全量 437 项、contracts 全绿；
  `flutter analyze --fatal-infos --fatal-warnings` 干净。Rust workspace 复跑只命中一个既有 hunting
  check 毫秒级 event-id 碰撞 flaky，单测立即复跑通过，未扩张本 phase 修改该领域。

- 2026-07-16 14:58 CST: 补充项目级产品开放性与 conversation 多 surface 原则。`AGENT.md`
  明确 phase scope、既有 UI 容器和架构模式不是永久产品禁令，只有平台/物理资源、延迟、
  协议/网络、成本、隐私安全、数据正确性与兼容性等真实工程条件构成硬约束；共享深模块复用
  事实和生命周期但不强制界面同形。同步 `PROJECT.md`、`REQUIREMENTS.md`、`ROADMAP.md`、
  `STATE.md` 及 `3.15.7-PLAN.md`：首个当前内容锚定对话不排斥未来 GPT-like 开放聊天、角色扮演等场景原生
  surface；它们共享 session/turn/audio/transcript、个人产出语料与 finalized-session 复盘处理，
  复盘呈现可为独立页、聊天内卡片、后台生成或稍后回访。ROADMAP 同步 P1–P6 实际顺序并移除
  已取消 3.12.1 的旧资格门表述。

- 2026-07-16 13:50 CST: Phase 3.12.2 与 3.15 收口 + P2–P6 立 phase。owner QA 通过：
  3.12.2 真实 provider 下三 Studio「AI 出题 + AI 判定 + 纠正」端到端通过（新增
  `3.12.2-CLOSEOUT.md`，PLAN 置 COMPLETE）；3.15 按 `3.15-MANUAL-QA.md` 真实内容/重启/
  窄窗口/音频焦点验收通过（CLOSEOUT 状态翻正，Deferred 中 3.12.1 资格门表述更正为已由
  3.12.2 取代）。按 discuss §11 裁决新建五个 phase（压在 3.16–3.18 前，取插入编号）：
  `3.15.5-personal-production-corpus`（P2，产出语料可重建投影、写作先行、scaffolding 仅
  预留字段、开工裁 3.16 边界）、`3.15.6-production-gap-review`（P3，gap-(c) 复盘；本轮
  评审把参照系排序提升为 v1 核心，小 N 走 3.10 式诚实降级，UI 克制到管线验证级）、
  `3.15.7-realtime-speech-conversation`（P4，realtime 中立 seam，OpenAI+Qwen，中立必须
  owner 可实测）、`3.15.8-semantic-embedding`（P5）、`3.15.9-tts-speech-synthesis`
  （P6，正交、建议 3.15.5 后即插）。STATE.md 更新当前位置/执行序列/语义能力边界（judge
  三级资格口径由显示诚实边界取代）并压缩已收口 phase 冗述；下一执行 3.15.5。

- 2026-07-16 13:15 CST: Phase 3.12.2 Slice 3 — LLM judgment 显示接线复制到 Speaking +
  Writing（纯 Flutter，后端 judge 用例本就按 attempt_id + response_revision 取存量作答，
  purpose 无关，零后端改动）。三个 Studio 现共用新抽取的 `LlmJudgmentAssist`
  widget（`widgets/panels/llm_judgment_assist.dart`，Reading 内嵌实现迁移至此——第三住户
  出现后才抽取的显示件，共享本地化键 `llmAssist*` 取代 `readingTaskAi*`）；provider 选择
  逻辑收敛到 `coach_llm.dart` 的 `pickLlmProviderId` + `preferredLlmProviderId`（列表失败
  吞掉、入口隐藏，manual 路径永不依赖 provider）。Speaking：`SpeakingTaskController` 在
  attempt 落库后解析 judge provider，新增 `requestLlmJudgment`/`adjudicateLlm`，assessing/
  done 阶段显示可纠正 AI 反馈，retryOnce 重置 LLM 判定；LLM 判定与用户自评并存、互不改写。
  Writing：内容/组织判定走同一 SemanticJudgeProvider（区别于 Harper 表面 finding），
  `WritingTaskController` 判定**最新 attempt 的最新 revision**（revising 侧栏判初稿 rev1，
  提交修改稿后旧判定清空、done 页可对 rev2 重新请求，判定永不跨 revision 冒充）。全程守
  显示诚实边界：evidence_class `heuristic_proxy`、append-only adjudication 引用 LLM
  judgment id、零 observation/projection。新增 Speaking/Writing 控制器各两条测试（判定+
  纠正诚实性、无 judgment-capable provider 时入口隐藏且零 judge 调用）。验证：flutter
  analyze 干净、完整 flutter test 434 通过；无契约改动。

- 2026-07-16 11:53 CST: Phase 3.12.2 Slice 2 — Reading LLM rubric 生成接线。后端新增
  `POST /v1/llm/providers/{id}/rubric`（routes/llm.rs `generate_rubric_via_llm_provider`）：调用
  `SemanticRubricProvider` 生成理解题草稿并**只返回内容草稿、不落库**——身份/版本/来源快照仍
  只在用户保存已审阅 rubric 的正常 create 路径铸造，vendor 层永不成为 rubric 身份写者（守
  ADR 0021）；provider 失败一律不返回、走标准化 secret-free 错误。OpenAPI v1.yaml 补路径，
  route-drift 门通过。Flutter：新增 `RubricDraftView`（客户端分配 p1..pN point_id）、
  `generateRubricViaLlmProvider` API；`ReadingTaskController` openTask 一次解析 judge/rubric 两个
  provider，editing 阶段新增 `generateRubric`——AI 生成的题目载入**可编辑模板**（不自动应用），
  用户复核/增删后保存；保存时若来自 AI 草稿则记录诚实 `llm` provenance（携带 model_id/prompt/
  schema），否则 `manual`。`ReadingTaskSheet` editing 阶段新增「AI 生成理解题」入口（无 rubric
  provider 时隐藏）。新增本地化键、后端 rubric 路由测试与控制器生成测试。验证：cargo test
  api-http 44 / llm-provider 12、validate-contracts、fmt/clippy strict 全绿；flutter analyze 干净、
  完整 flutter test 430 通过。

- 2026-07-16 11:29 CST: fix(llm-provider) — OpenAI 兼容适配器改用广泛兼容的 `json_object`
  结构化输出模式，schema 内嵌进 prompt，取代此前硬编码的 `json_schema` response_format。
  DeepSeek 等众多"OpenAI 兼容"端点只支持 `{"type":"json_object"}`，对 `json_schema` 直接回
  HTTP 400，导致 probe 与 judge/rubric 全部失败（owner 用 deepseek-v4-flash 实测 `/judge`
  报 `unexpected status 400`）。语义层本就对解析结果做 schema 后校验（不符即 SchemaInvalid、
  不写 judgment），故不依赖 wire 层强约束；`json_object` 模式需 prompt 含 "json" 词元并携带
  schema 形状，均已在 system 提示中保证。Anthropic 走 tool_use 不受影响，中立契约套件
  `drafts[0]==drafts[1]` 仍成立。新增回归测试钉住请求体使用 `json_object` 且 schema 入
  prompt；llm-provider 13 测试通过，fmt/clippy 干净。

- 2026-07-16 11:10 CST: Phase 3.12.2 Slice 1 — Reading LLM judgment 显示接线（纯 Flutter，
  复用 3.12 已就绪的 `POST /v1/llm/providers/{id}/judge`）。`coach_llm.dart` 新增 typed
  `llmProviders()` 与 `judgeViaLlmProvider()`；`ReadingTaskController` 提交作答后惰性解析首个
  允许 `semantic_judgment` 的 provider（优先有凭证者，失败静默不阻塞 manual 路径），新增
  `requestLlmJudgment` 与 append-only `adjudicateLlm`（镜像 manual adjudicate，永不改写原
  judgment 行）。`ReadingTaskSheet` 在 assessing/done 阶段新增「请求 AI 反馈」入口与逐点 LLM
  判定展示：标注「AI 辅助反馈 · 可纠正」「仅供参考，不计入能力档案」，可 adjudicate；无
  judgment-capable provider 时整块隐藏。LLM 判定与用户自评并存不互相改写，evidence_class 保持
  `heuristic_proxy`，零 observation/projection。新增本地化键与两条控制器测试（请求→纠正→
  heuristic 边界 / 无 provider 隐藏）；flutter analyze 全绿，reading task controller+sheet 11 测试通过。

- 2026-07-16 10:58 CST: 产品方向讨论沉淀 + Phase 划分裁决。新增 discuss
  `conversation-output-corpus-and-model-categories.zh.md`：把 realtime 语音对话定为**独立中立
  模型类别**（中立在能力类别层成立，非一个 seam 通吃），对话厂商与证据文稿解耦（用户音频统一
  走本地 whisper.cpp）；说/写统一为**个人输出产出语料库**（写作 attempts 现成先行）；复盘 =
  跨通道 gap-(c)「能认不能产出」描述性画像，不自动写 projection；从整个产品推导 10 类模型地图
  与本地/云落位。裁决：取消 Phase 3.12.1（留出集资格门对个人工具过度），改显示诚实边界；新增
  Phase 序列 P1（studio LLM 反馈接线，folder 3.12.2）→ P2 产出语料 → P3 gap 复盘 → P4 realtime
  （首批 OpenAI Realtime + 千问）→ P5 嵌入 / P6 TTS；3.18 收窄为聚合、3.17 保留投影确认门。
  新增 `.planning/phases/3.12.2-studio-llm-feedback/3.12.2-PLAN.md`（Slice 1 Reading judgment
  显示 / Slice 2 Reading rubric 生成 / Slice 3 复制到 Speaking+Writing）。仅规划文档，无代码变更。

- 2026-07-16 08:39 CST: Phase 3.15 Writing Studio v1 code complete，进入 owner 手工 QA。
  PLAN 按 3.14 closeout 保鲜并建立 Reference Matrix；确认
  Writing 自有 editor/revision 状态机，不复制 Reading/Speaking controller 或虚构通用 lifecycle
  interface。新增 `one_sentence_summary` / `opinion_response`、Summary/Dictogloss/Opinion 多稿 typed-only validator 与
  Dictogloss playback/prompt 条件；新增项目自有分层 Writing finding/provenance 和 accept/reject
  disposition；接受必须引用一个保留原文 hash 并含后续 typed revision 的新 immutable attempt，
  provider suggestion 不能静默成为用户稿。schema v38 新增可变但非证据的 durable scratch 与
  append-only finding/disposition；Writing 当前内容通道、自有 editor 状态机、600ms autosave/重启
  恢复、来源折叠、请求后 feedback、固定 rubric 意义自评、Harper 0.40 离线表面 finding、历史复写
  参照和 Unicode-safe diff 已落地。finding/manual judgment/observation/projection 继续分离，v1 零
  writing observation/projection writer；真实内容、窄窗口与音频焦点留 `3.15-MANUAL-QA.md`。

- 2026-07-15 23:40 CST: Phase 3.14 Speaking Studio v1 Slice 0–5 code complete。
  内容 Speaking 通道现支持 10–60 秒 L2 retelling 与 full sentence/keywords/no text 三档
  Role Reply；延迟复述从 review asset 进入同一状态机，不建独立首页。链路串通麦克风权限、
  单一音频焦点、RecordingAsset、独立短录音 whisper.cpp job、raw/corrected transcript、
  ASR reliability、请求后逐点自评、append-only adjudication、一次立即重说与显式复习难度。
  新增单录音客观时长/≥120ms 停顿/waveform facts；无 qualified judge 时完整降级为这些事实 +
  用户自评，不显示综合口语分。只有 completed L2/Role + 非 unreliable ASR + corrected literal hit +
  用户显式确认，才写 assistance-aware `SpeakingProduction` observation，且零 projection；L1 核对
  独立复用 typed listening fact。Reading/Speaking lifecycle audit 证实资源副作用不同，未抽取
  pass-through interface。严格回归 Rust 581、contracts、Flutter analyze 与完整 Flutter tests
  423 项 Flutter tests 通过；owner 按 `3.14-MANUAL-QA.md` 在可热重启版本统一体验真实麦克风/
  真人普通话/GUI。

- 2026-07-15 22:49 CST: Phase 3.14 Slice 1 code complete，并启动内容通道 L2 retelling
  surface。新增独立 Speaking 状态机，串通固定信息点 rubric、麦克风权限、单一音频焦点、
  RecordingAsset、短录音 ASR、raw/corrected transcript 核对、append-only spoken attempt、
  用户请求后的逐点自评 judgment 与最多一次立即重说；ASR uncertainty/失败不会写成口语失败。
  Speaking 作为当前内容通道打开整面阶段自适应场景，录音时不显示 transcript/feedback，核对后
  才能请求自评；无独立首页、Reading 复制、固定三栏或弹层。来源/用户录音切源前均暂停其他
  声源，退出恢复原主媒体位置但不自动播放。Role Reply 事实守卫已具 assistance/prompt snapshot，
  UI 与延迟资产入口留后续 Slice；Reading/Speaking lifecycle interface 进入第二住户实证审计，
  尚未抽取 mega abstraction。

- 2026-07-15 22:19 CST: Phase 3.14 Slice 0 短录音 ASR 与底盘预检 code complete。
  新增独立 `RecordingAsset -> RecordingTranscriptionJob` API/runtime/client contract，校验
  16k mono PCM16、文件长度和 SHA-256，支持语言、取消、raw segment transcript、latency
  与完整 provider/runtime/model/recording provenance；不导入字幕、不评分、不写学习证据。
  真实新闻英文 14s（348ms）与取消 60s（122ms）通过；普通话 TTS coverage（560ms）发现
  whisper.cpp `-ojf` 中文 token 非法 UTF-8，独立路径改用可靠的 `-oj` segment JSON。
  Reference Matrix 复核后继续排除 H5P 固定答案、iSpraak 逐词/总分与 Sentence Paths 未核验
  评分语义；真人普通话麦克风 QA 留 owner 最小步骤。Slice 1 同步落地 durable raw/corrected
  transcript 分离、L2/RoleReply 必须关联录音、RoleReply assistance/prompt snapshot 与 typed
  Flutter request；继续复用 v35 append-only semantic attempt，零 judgment/observation/projection，
  不提前抽取 Reading/Speaking 生命周期 interface。

- 2026-07-15 21:53 CST: Phase 3.13.5 正式收口并以实际底盘修订 3.14–3.18 PLAN。
  3.14 Speaking Studio 升为 READY v2 并新增 Reference Matrix；后续统一采用内容通道与
  资产旅程的混合导航，任务共享层收窄为第二住户验证后抽取的生命周期 interface，明确
  禁止复制 Reading controller、固定三栏、常驻反馈与多阶段弹层。

- 2026-07-15 20:30 CST: Phase 3.13.5 真实媒体走查修复阅读查词的可见出口：整面
  阅读器不再把已更新的词汇状态藏在旧 SidePanel 中；显式点击单词后，宽窗口展开
  360–460px 当前单词右侧栏，窄窗口使用可关闭覆盖层。收起不清空选择、不改变阅读
  游标；词汇状态、能力覆盖、阅读标记、来源回听与听力词典继续复用既有语义。阅读器
  同时补齐词汇概览及“干净正文 / 阅读标记 / 听力推测”分离视图，不合成含混认识率。

- 2026-07-15 19:51 CST: Phase 3.13.5 进入 Flutter 实施前清偿裁决一致性：PLAN 的
  Scope/Key Work 改写为混合导航与阶段自适应容器，明确保留首次 manual rubric 创建、
  append-only 重做、来源 capability gating 与单一音频焦点；PROJECT/REQUIREMENTS/
  ROADMAP/STATE 同步内容会话 + 资产驱动两条旅程，新增 UI-018 验收口径。

- 2026-07-15 19:34 CST: Phase 3.13.5 Slice 0 走查裁决落地 + 原型 v2。owner+codex
  评审结论"方向通过、布局退回"写入 PLAN（五项裁决表）；宏观旅程讨论（参照
  每日英语听力"资源首页→学习页→模式菜单"）后导航定为**混合模型**：首页 +
  内容工作台（听/读/说/写通道切换器一跳、听保留三子姿态、⌘1–4）+ 资产层
  （词典/复习/我的表达/Coach 承接跨媒体任务），四通道平级 Studio rail 不建
  （field razor）。原型 v2 重做七屏：首页（分组 rail + 四通道进度继续卡 +
  到期资产 + 全局迷你播放条）、工作台通道切换（含退出/返回语义注记）、
  阅读器 v2（默认干净、翻译默认隐藏、词汇概览分列阅读标记/听力推测不合成
  认识率、透镜三态分视图、句子 hover/点击选中/键盘聚焦）、任务容器阶段
  自适应（作答期反馈隐藏防泄露、口语录音中心化、写作编辑器≥60%、stepper
  不可跳未来、含可重做）、表面行为约束（白名单→行为规则）。补 meta charset。
  Reference Matrix v2：逐项"明确不借鉴"列、新增每日英语听力参考行、裁决
  状态节。维护债清偿：外部参考库 §2 着色表述对齐词汇透镜裁决（PROJECT/
  REQUIREMENTS 核对无矛盾无需改）。浏览器实测：本地 HTTP 干净加载下七屏
  渲染与全部交互（透镜/概览/任务三阶段/录音状态机/反馈请求制）通过；
  Artifact 已更新同 URL。

- 2026-07-15 18:41 CST: Phase 3.13.5 Slice 0 交付：低保真 HTML 原型
  `spikes/studio-shell-ux-prototype/index.html`（七屏，底部切换条 + 方向键：
  A 姿态扩展 / B Studio 切换两导航候选各带取舍与裁决点；C 阅读器——干净/
  词汇透镜一键切换、着色来源诚实区分（实线=阅读标记、虚线=听力证据/投影）、
  句子悬停工具栏替代 chip 排、材料级词汇概览；D/E/F 共享任务容器三区布局
  （来源/产出/反馈 + 阶段常显 stepper）分别入住 3.13 阅读任务、3.14 录音
  循环骨架（可交互状态机 mock）、3.15 写作分层反馈骨架；G 表面语法规则
  草案含现状六表面迁移映射）。已发布为 Artifact 供 owner 走查。同步交付
  `3.13.5-REFERENCE-MATRIX.md`（借鉴/不借鉴/契约映射/证据等级 + 表面规则
  草案 + 五项待裁决清单）。PLAN guardrail 按 owner 意见修正：全文词汇状态
  着色从禁项改为"词汇透镜"（防 Lute 记账语义与通道误导，默认态随 Slice 0
  裁决）。浏览器实测七屏渲染与交互（透镜/录音状态机/stepper）通过。

- 2026-07-15 14:59 CST: 立项 Phase 3.13.5 Studio Shell UX（owner 裁决）。owner
  确认四个 UX 痛点（阅读不像阅读为核心、入口藏深、表面类型六种无规则、任务
  流繁琐），确立"场景原生 UX"原则（阅读像阅读器，听/说/写各符合其场景），
  沿 3.35 插入式 UI phase 先例在 3.14 前插入独立 phase。PLAN 交付范围：Slice 0
  低保真原型把门（导航模型两候选 + 阅读器化 + 共享任务容器 + 3.14/3.15 骨架
  预演 + Reference Matrix）、导航与入口落地、阅读器化正文（文内工具栏替代
  chip 排）、共享任务容器迁入 3.13 任务流、真实媒体走查（合并 3.13 剩余
  owner 走查项）。guardrail：只改承载方式不改学习语义、低保真裁决前不写
  Flutter、不重开 3.35 听力工作台改版。STATE 决策/下一步更新，3.14 PLAN 上游
  输入增补 3.13.5 依赖。

- 2026-07-15 14:42 CST: 修复 3.13 owner GUI 走查首个缺陷：阅读姿态"听整段"/
  逐句 chip 与听测面板播放全部无法回听。根因：`_playReadingRange` 与
  ListeningCheckPanel 手写的 occurrence map 缺 `media_fingerprint_snapshot`，
  共享 `OccurrenceMediaResolver` 在 linked-media 路径之前即以 invalidSnapshot
  拒绝（后端 QA 为纯 HTTP、widget 测试回调为假，接线层缺口未被覆盖）。修复：
  occurrence 构造收敛为 `currentMediaSliceOccurrence` helper（归属 resolver
  文件，形状契约单一来源），两个调用点携带当前播放器 fingerprint；fingerprint
  缺席仍诚实降级为显式错误。新增
  `test/reading_slice_occurrence_test.dart` 回归（helper→resolver 真实链路 +
  降级用例）。验证：flutter analyze 零问题、flutter test 409 全绿。

- 2026-07-15 13:45 CST: Studio 3.13–3.16 外部参考库入库。将 owner 委托 codex 的
  外部项目调研经批判性修订后收入
  `.planning/discuss/studio-3.13-3.16-external-reference-library.zh.md`：A 级
  优先级按 3.13 CODE COMPLETE 现状重排（3.13 参考降级为 GUI 走查对照 +
  Slice 7 预备，A 级集中到下一 phase 3.14：Sentence Paths / H5P Speak the
  Words / iSpraak，Harper spike 可提前排）；Reference Matrix 模板新增
  "对应既有契约/不变量"与"证据等级"必填列（3.13 v2→v2.1 validator 证伪
  教训 + evidence-class 纪律）；H5P Essay 从"无 LLM 默认路径"重定位为
  "目标表达字面命中"客观展示参考（无 LLM 路径维持 rubric 对照 + 自评）；
  剔除正文无依据的 ReadingTree/InsightGUIDE；闭源 Sentence Paths 标注
  heuristic_proxy。3.14/3.15/3.16 PLAN 各增"外部参考输入"节并要求开工
  修订时建立各自 REFERENCE-MATRIX。STATE 下一步工作同步指针。

- 2026-07-15 03:30 CST: Phase 3.13 Slice 6 完成 + phase CODE COMPLETE。真实媒体后端
  全链路 QA：隔离 DB + 真实 sidecar + CNN10 真实 mp4/244 句 whisper 转写，新闻段
  20/20 通过（位置往返、rubric 409→lookup 恢复、阅读 attempt/自评/adjudication、
  听侧独立 rubric + 隐藏文本 attempt、读听两侧可发现、真实词条阅读标记 204 且零
  projection），对话段（31 个 speaker-turn cue）rubric/attempt/judgment 通过；形成
  可追溯读听差异结论（read=yes / listen=partial → diffMixed）。撰写
  `3.13-REAL-MEDIA-QA.md`（含 owner GUI 走查清单）与 `3.13-CLOSEOUT.md`，PLAN 置
  CODE COMPLETE，STATE 更新（下一 phase 3.14；Slice 7 LLM 接线随 owner 3.12.1
  裁决）。

- 2026-07-15 02:30 CST: Phase 3.13 Slice 5 完成：reading observation writer（显式标记）。
  domain 显式扩展封闭枚举 `ObservationTaskType::ReadingContextMarking` +
  `observation_spec_for_reading_marking`（capability=Reading；assistance 按标记时翻译
  可见性记 FullText/None——只有无辅助的阅读观察未来才可能独立支撑 acquired，镜像
  listening 不变量）；application `record_reading_marking` 刻意窄于 listening 标记路径
  （不写 legacy LexicalObservation、不写 recognition evidence、零 projection——channelized
  writer 只对 Listening 通道重投影，结构性成立）；HTTP `POST /v1/reading/markings` +
  OpenAPI。Flutter：`WordLearningPanel` 在阅读姿态下显示"读懂了/读不懂"按钮（词点击
  经合成 token 映射回真实 cue，sentence 上下文正确）。负向测试：阅读标记不漏入
  listening 通道/legacy 表/projection/history，未知词条 404 且零写入；无翻译标记为
  None-assistance。验证：domain/application/persistence/api-http 12 套件全绿（persistence
  reading 6 项、api-http reading 4 项），validate-contracts 通过，flutter analyze 零问题 /
  test 406 全绿。

- 2026-07-15 01:55 CST: Phase 3.13 Slice 4 完成：只听对照 + 读听差异解释卡。PLAN 记
  v2.1 修正：v2"同 rubric 双条件配对"被 3.11 validator 证伪（ReadingComprehension 强制
  文本可见、复述类强制隐藏），改为**同 source segment 双 rubric 事实并置**（阅读理解 vs
  L1 复述），不改 3.11 契约。实现：`ReadingTaskController` 泛化 purpose（听侧 attempt
  诚实记 source_text_visible=false + l1_trigger=user_requested + 实际播放次数，UI 强制
  至少听一遍才可提交）；听测以 `ListeningCheckPanel` 整面替换阅读视图（文本因此天然
  隐藏，且刻意非模态——切片窗保持可操作）；复述模板优先镜像阅读侧 rubric points；
  `reading_diff.dart` 纯归约（adjudication 最新者生效 → 必答点 yes/partial/no/
  unassessed，abstain/缺席=未评估不算失败）+ `ReadingDiffController` 读端聚合（跨
  rubric 不做逐点比较）+ 四象限 possibilities 解释卡对话框；阅读视图锚定段落新增
  "读听对照"chip。验证：flutter analyze 零问题 / test 406 全绿（新增 diff 归约 6 项、
  explanation 1 项、diff controller 2 项、听侧条件 payload 1 项）。

- 2026-07-15 01:10 CST: Phase 3.13 Slice 3 完成：段落任务全链路（manual rubric + 自评）。
  后端新增 additive 读端点 `GET /v1/semantic/rubrics/lookup`（按 source 身份六元组查最新
  rubric——客户端无法重推服务端 fingerprint id，409 后无从定位既有 rubric 是真实缺口；
  repository/use case/OpenAPI/route-drift 齐备）。Flutter：semantic DTO 首个真实 consumer
  落地（`models/semantic_task.dart` 手写 + 直接 pin `gold-fixture-v1.json` 的 5 项契约测
  试）、`SemanticApi` part（sha256 与 Rust `transcript_sha256` 对齐）、`ReadingTaskController`
  状态机（lookup→模板编辑→rubric v1→作答→逐点自评→adjudication；409 并发回退 lookup；
  覆盖/部分 span 取全响应且按 Unicode scalar 计数）、`ReadingTaskSheet` 底部工作流 +
  段落"任务"chip + 切片回听计数进 attempt 的诚实 `audio_play_count`。自评 judgment 记
  `evidence_class=self_assessment` + provenance 注明 span 语义，不冒充 gold；全程零
  observation/projection 写入。重要契约事实（PLAN v2 裁决 1 修正预告）：3.11 validator
  规定 ReadingComprehension 必须 source_text_visible=true，同 rubric"只读/只听"配对不成
  立，Slice 4 读听差异改为同 source segment 双 rubric 事实并置，届时记 PLAN v2.1。验证：
  Rust workspace 33 套件全绿（api-http 新增 lookup + 客户端 payload 端到端 2 项），clippy
  零告警，validate-contracts 通过；flutter analyze 零问题 / test 396 全绿（新增 controller
  5 项、sheet 1 项、契约 5 项）。

- 2026-07-15 00:05 CST: Phase 3.13 Slice 2 完成：阅读位置持久化。schema v37
  `reading_positions`（track 键控 upsert，刻意非 append-only——位置是游标不是证据）；
  domain `ReadingPosition` + `ReadingPositionRepository` trait（Disabled 降级：读回 None
  写报错）+ `ReadingUseCases`（空 anchor 拒绝）+ SQLite 实现；HTTP
  `GET/PUT /v1/reading/positions/{track_id}` + OpenAPI 路径与 `ReadingPosition` schema
  （route-drift 门通过）。Flutter：`ReadingPositionView` 手写 DTO + fixture 契约测试
  （ADR 0014）、`ReadingApi` part、进入阅读姿态时恢复游标（拉取失败静默从头开始）、
  段落锚定 800ms 防抖写入 + 关闭时冲刷、失败 best-effort 不打扰。验证：cargo
  workspace 33 套件全绿（persistence 113 含新增 3 项、api-http 含新增 2 项路由测试）、
  clippy 无新告警、validate-contracts 通过、flutter analyze 零问题 / test 385 全绿。

- 2026-07-14 23:05 CST: Phase 3.13 Slice 1 完成：阅读姿态 UI 骨架。新增
  `ReadingController`（Store 模式：paragraphs 派生、anchorCueId 阅读游标、翻译投影按
  段落时间范围中点匹配副字幕轨）与 `ReadingView`（替换 MediaWorkbench 播放区：段落流
  排版、词点击经合成 token 映射回真实 cue 进词汇面板、锚定段落显示整段/逐句回听 chip
  走 3.5.7 切片窗、翻译全局开关、非语音分隔段弱化显示、进入时暂停主播放/退出恢复原
  播放状态）。`composeParagraphCue` 合成段落 cue 复用 TokenLine 流排（TokenLine 新增
  textAlign 参数，默认 center 不变）；side panel 姿态区新增"读一下？"入口（有 track
  即可用，不要求当前句）。ReadingView 自监听 controller。新增 9 项 controller/组合/
  widget 测试；flutter analyze 零问题，flutter test 383 全绿。

- 2026-07-14 22:25 CST: Phase 3.13 Slice 0 完成：段落 read model spike 通过。真实数据
  证伪 PLAN v1 的"gap 阈值分段"假设（whisper 转写 244 cue 仅 2 个非零间隙），落地
  两级派生纯函数 `deriveReadingParagraphs`（标点/说话人/间隙/runaway 断句 → 说话人/
  间隙/词数软上限组段，非语音 cue 成分隔段，段落身份=首 cue id）；`♪` 计句终符、
  含词歌词行算阅读内容。新闻 49 段中位 37 词、歌词 8 段中位 49 词，目检通过。新增
  dev 工具 `dump_sentences`（Rust example，产线切句导出）与 `paragraph_spike.dart`；
  12 项单测，flutter analyze 零问题 / test 374 全绿，clippy/fmt 通过。结论与已知
  限制见 `3.13-SLICE0-SPIKE.md`。

- 2026-07-14 21:55 CST: Phase 3.13 Reading Studio v1 开工：PLAN 按上游落地现状修订为
  v2 并建分支 `claude/3.13-reading-studio-v1`。关键裁决：读听差异直接骑在 3.11
  `SemanticTaskConditions`（source_text_visible/audio_play_count）+
  `judgments_directly_comparable` 上，读端派生聚合、不新增权威表；段落 read model
  为派生投影不落库；阅读位置定为 v37 upsert cursor 不进 append-only 事实族；无 LLM
  默认路径 = manual rubric + 用户自评 manual judgment；semantic Dart DTO 由本 phase
  作为首个真实 consumer 交付（ADR 0014）；reading observation 收窄为用户显式标记
  （capability=Reading）；provider-backed rubric/judgment 为后置切片，跟随 owner
  3.12.1 资格裁决。执行方式变更：本 phase 起由 Claude 全程实现（codex 无额度）。

- 2026-07-14 21:30 CST: Phase 3.9.4 收口。Slice 4 QA：Rust workspace 614 tests、
  clippy strict、fmt、contracts、flutter analyze/test 362 全绿；隔离 DB + 真实 spaCy
  capability + 两条真实字幕轨道的后端 HTTP 全链路实测通过（持久化/激活/幂等/
  cache-hit 补偿/force/文本回退生成/syntax 接管 active），临时 track cache 已清理。
  撰写 `3.9.4-REAL-MEDIA-QA.md`（含 owner GUI 清单）与 `3.9.4-CLOSEOUT.md`，
  更新 STATE，phase 分支合回 main。

- 2026-07-14 21:05 CST: Phase 3.9.4 Slice 3 完成：语义分组获得播放跟随与点击跳转，
  按 ADR 0016 投影实现——新增纯函数 `senseGroupPlaybackRange`（token span →
  WordTiming min/max，容忍乱序/缺失，无匹配返回 null），TokenLine 缓存投影（列表
  identity 变化才重算，播放 tick 只做区间比较），点击合成 DisplayChunk 复用既有
  onChunk → seekChunk 通路与 offset 换算；semantic 纯模式改为与 prosodic 同级的
  实线胶囊并复用 chunk 高亮设置，删除 provisional 虚线画笔与 tooltip；compare 模式
  保持 prosodic 底 + 虚线差异标记不变。新增投影 helper 六类单测与 TokenLine
  semantic 高亮/点击/null 投影/compare 回归 widget 测试；flutter analyze 无告警，
  flutter test 362 全绿。

- 2026-07-14 20:47 CST: Phase 3.9.4 Slice 2 完成：Flutter speech-enhancement 加载在
  sense group 为空且非请求错误时触发一次文本规则回退生成并激活（每 track 单次守卫，
  失败降级为空并记录 errors）；设置页 semantic/compare 选项标注"可用/数据未就绪"短
  状态，未就绪且选中语义相关模式时 grouping 下拉 helper 显示逐词回退说明（中英文案）。
  新增 controller 三场景测试与 SettingsDialog 两态 widget 测试（该文件首个 widget
  测试基建）；监督评审中修正了 codex 无法在 sandbox 验证的测试 fixture 非法下拉值
  （ruleHintsLevel/soundPatternDisplayMode/phonemeRibbonStyle/phoneticAnalysisPreference）
  并把长文案从选项文本移入 helperText 以消除真实 RenderFlex 溢出。flutter analyze
  无告警，flutter test 353 全绿。

- 2026-07-14 20:29 CST: Phase 3.9.4 Slice 1 完成：track syntax-analysis 的新鲜
  batch 与 cache-hit batch 都通过 application 用例持久化并激活 SenseGroup，失败仅记录
  tracing warning、不影响 syntax 响应，capability unavailable 早退保持无副作用。扩展
  api-http ready fake-provider 集成测试，覆盖首次 syntax batch 的 groups 一致性、cache hit
  幂等和 force 重算不重复。

- 2026-07-14 20:20 CST: Phase 3.9.4 Slice 0 完成：application 新增
  `MediaAnalysisUseCases::persist_sense_group_analysis_from_batch`，把语法分析 batch 中
  已算好的 sense groups 映射持久化为 `SenseGroupAnalysis` 并激活；text/id 推导与既有
  生成路径抽公共 helper；幂等（active 同 id 跳过）、syntax 接管 fallback active
  （fingerprint 含 provider_id）、空 batch 返回 None。新增 6 个单测覆盖混合/纯回退/
  幂等/接管/双入口一致性/空 batch；application 65 tests、clippy -D warnings、fmt 全绿。

- 2026-07-14 20:03 CST: 建立 Phase 3.9.4 SenseGroup UX Unification（分支
  `phase/3.9.4-sensegroup-ux-unification`）。核实语义分组四层断链（syntax 分析不落
  SQLite、syntax-aware 生成入口为死参数、Flutter 无生成/激活调用方、加载只认 active），
  写入 `3.9.4-CONTEXT.md` 决策 D1–D6（时间戳走 ADR 0016 投影、持久化直接映射
  batch、幂等激活、cache-hit 补偿、Flutter 触发文本回退、编排收在 application）与
  `3.9.4-PLAN.md` Slice 0–4；上游桌面方案文档归档至 phase design-notes。

- 2026-07-14 20:50 CST: Phase 2.24 严格收口。AppServices 变为 composition-only，三个
  深模块与六个窄模块承接用例；Flutter raw return 约 97→1，production Rust wildcard 归零，
  Python production entry 1433→262 行。最终 Rust 608、Flutter 348、Python 11、contracts 5
  全绿，fmt/clippy strict 与 architecture guard 通过；详见 `2.24-CLOSEOUT.md`。

- 2026-07-14 20:28 CST: Phase 2.24 Rust hygiene gate 收口：生产代码 86 处 wildcard imports
  全部展开并清除未使用依赖，测试 prelude 仍可局部使用 `super::*`；architecture guard 新增生产
  wildcard 回归检查。同步清理历史 fmt/clippy 基线，`cargo fmt --all -- --check` 与
  `cargo clippy --workspace --all-targets -- -D warnings` 首次全绿，workspace 所有 test targets
  编译通过。

- 2026-07-14 19:55 CST: Phase 2.24 `AppServices` 深化完成：practice session、review
  scheduling、hunting 与 listening inbox 归入 `PracticeUseCases`，lexical evidence 通过显式
  collaborator 写入。application 中散布的 18 个 `impl AppServices` 已全部删除；顶层仅剩
  composition/builders 与 9 个聚合模块访问器，workspace production check 与全部 test targets
  编译通过。

- 2026-07-14 19:41 CST: Phase 2.24 第二个深用例族完成：media/subtitle、四类 timeline、
  transcription/phonetic derived resources、corpus、content-fit、diagnosis 与 coach material
  统一进入 `MediaAnalysisUseCases`，共享资源失效与 provenance 边界，并显式依赖 lexical
  collaborator。api-http、local-runtime 与测试均删除旧 `AppServices` 直调；application 59、
  local-runtime 14、api-http 48、persistence 121 tests 全绿。

- 2026-07-14 19:18 CST: Phase 2.24 首个深用例族完成原地替换：lexical normalization、
  entries/capability evidence、sense folders、vocabulary transfer 与 recognition upgrade 统一进入
  `LexicalLearningUseCases`，只持有该一致性边界需要的 ports；api-http、跨域协作者和持久化测试
  均通过 module interface，旧 `AppServices` lexical 直出方法删除。Application 59、api-http
  48、persistence 121 tests 全绿，workspace tests 可完整编译。

- 2026-07-14 18:53 CST: Phase 2.24 Flutter raw-return ledger 收敛完成：vocabulary
  list/import 与 OpenSubtitles search 建模，未使用的全局 LLTimeline import 客户端入口删除；
  vocabulary book 同步改为 typed details。仅保留 vocabulary export 这一项经审定的开放版本文档
  例外，并以 transport contract 验证 additive fields 无损透传。Analyze、相关 51 tests 与
  architecture guard 全绿。

- 2026-07-14 18:42 CST: Phase 2.24 typed-resource 第六批：learning resources、transcription
  providers/models/jobs 与 phonetic providers/models/jobs/feedback 全部改为显式领域模型，
  三个 UI surface 和 subtitle source coordinator 不再读取匿名 wire maps；raw-return
  allowlist 从 26 降至 5。Flutter analyze、相关 23 tests 与 architecture guard 全绿。

- 2026-07-14 18:17 CST: Phase 2.24 typed-resource 第五批：LLM provider registration、corpus
  search、subtitle import/lifecycle 与 word/chunk/phone timeline lifecycle 全部在 LocalApi
  seam 解码为既有领域模型，调用侧旧 `fromJson` 被原地删除；raw-return allowlist 从 42 降至
  26。Flutter analyze 与相关 38 tests 全绿。

- 2026-07-14 17:49 CST: Flutter typed-resource 第四批将 MediaItem、chunk partition、syntax
  status、learner profile/L1 specialty、capability override、lemma normalization 移至 LocalApi
  解码，UI/occurrence resolver/settings 删除对应 map field knowledge；补充 learner/L1 contract
  tests。raw-return allowlist 从 51 项继续降至 42 项，analyze、定向 17 tests、全量 347
  tests 与 guard 全绿。

- 2026-07-14 17:44 CST: 继续压缩 Flutter raw-return allowlist：cold-start candidates、
  sense-group analysis/summary/lifecycle 与 LLTimeline export 改为 LocalApi typed decoding，
  controller/widget 删除 wire parsing。补齐 `LLTimelineDocument` 及其 export children 的
  `toJson`，同一个领域对象同时服务 UI 与无损 JSON 导出；相关 43 tests、timeline round-trip、
  analyze 与 architecture guard 全绿，allowlist 再减少 8 项。

- 2026-07-14 17:34 CST: Phase 2.24 Flutter typed-resource 第二批：字幕轨道、词时间、
  word/chunk/phone timeline summaries、pronunciation provider/analysis 与 phonetic analysis
  在 LocalApi 边界解码，controller/coordinator/event flow 删除对应 wire-shape knowledge。
  新增 raw-return allowlist 守卫，使剩余 transport DTO 债务可审计且禁止净新增；Flutter
  analyze、定向 23 tests 与全量 346 tests 全绿。另将 pronunciation/timing 9 个方法从
  `AppServices` 原地替换为仅持有 4 个相关 port/provider 集的 `PronunciationUseCases`；
  application/local-runtime/api-http 共 109 tests 全绿。

- 2026-07-14 17:23 CST: 继续 Phase 2.24 高内聚治理。删除语义不明的 `m18.rs`/
  `m18_ui.dart`，分别替换为 lexical entries、learning resources、subtitle search HTTP
  modules 与 `learning_assets_ui.dart`。新增 Dictionary/Recording use-case modules；Flutter
  lexical、dictionary、pronunciation、language、syntax、timeline、content-fit、media-triage、
  LLM-probe caller clusters 改为 resource-client typed decoding。SQLite 1350 行 subtitle
  persistence 按 7 个 repository 职责拆分；Python production CLI 1433→262 行，核心实现按
  I/O/acoustics/report/conversion/audio/alignment/orchestration 拆分。新增并接入 contract 流程的
  architecture coupling guard。Rust 205、Flutter 345、Python 11 tests 与 analyze 全绿。

- 2026-07-14 16:53 CST: 启动 Phase 2.24 Flutter typed-resource slice：diagnosis API client
  直接解码并返回 `Diagnosis`，主 controller 删除 `fromJson(await api...)` wire-shape 知识；
  新增 transport seam contract test。`flutter analyze` 与 API/learning-workflow 相关 16 tests
  全绿。

- 2026-07-14 16:48 CST: 完成 Phase 2.24 runtime ownership 尾项：M18 learning-resource
  lifecycle、OpenSubtitles provider 和 syntax capability manager/cache I/O 从 api-http
  迁入 local-runtime，HTTP 层缩回协议映射；resource install 复用 ArtifactDownloader 并由
  deterministic fake 覆盖校验失败、原子发布和清理。开始深化 AppServices，将 semantic task
  与 LLM provider/secret、learner profile singleton lifecycle 原地替换为只持有所需
  repository 的 use-case modules，不保留旧直出 wrapper。application/local-runtime/
  api-http/persistence-sqlite 共 219 个定向 tests 全绿；learner profile 后续切片另通过 4 个
  L1 聚合测试与 36 个 HTTP tests。

- 2026-07-14 16:28 CST: 执行 Phase 2.24 首批高耦合治理。speech-analysis 的 17 个公开
  implementation modules 改为 private，通过 timing/chunking/phonetics/audible-structure
  curated facade 暴露能力；删除 application 6 个无 caller legacy engine wrappers。
  新增无 Axum 依赖的 local-runtime crate，原地迁出 transcription/phonetic/speech-batch/
  sound-line coordinators 与 event payload，新增并实际接入 Tokio/fake ProcessRunner、
  Reqwest/fake ArtifactDownloader，共享 tool discovery 不再跨 workflow 私借。删除
  TimelineResourceRepository/LearningAssetRepository/ReviewRepository 三个 fat ports，
  按 word/chunk/sense/phone、capability/entry/observation/content/bundle、
  review/hunting/recognition-upgrade 拆为 12 个窄端口，Sqlite 直接实现且无聚合桥接。

- 2026-07-14 15:58 CST: 建立 Phase 2.24 System Cohesion & Coupling Consolidation，新增
  CONTEXT/BASELINE/PLAN，记录 `api-http` runtime ownership、speech/application 公共类型泄漏、
  宽 repository/AppServices、Flutter raw JSON client、Rust/Python locality 五组治理目标；明确
  deep-module/seam 裁决（单实现纯算法禁止机械加 trait）、P0→P2 六步执行顺序、完整测试门槛
  与 3.13 前推荐工程关口。同步新增 ARCH-011，并更新 ROADMAP/STATE。

- 2026-07-14 12:10 CST: 机械拆分 `dictionary-provider/src/lib.rs`（1425 → 15 行 lib +
  按上游资源分模块：cedict 523（中文词典+拼音发音，共享 CC-CEDICT 索引）/ ecdict 271 /
  edict 253 / free_dictionary 155 / support 10（共享 `ResourceSignature`）/ tests 271）。
  逐字搬移；跨模块可见性最小升级：`resolve`/`numbered_pinyin_to_marks`/
  `parse_free_dictionary_phonetics`/`ResourceSignature` 升 `pub(crate)`（测试与共享所需）。
  doc comment 逐行对拍与原文件完全一致。`cargo test` 8 全绿（与基线同数）、workspace
  测试零失败、clippy 告警 28 与基线持平。

- 2026-07-14 11:40 CST: 机械拆分 `models/types.dart`（1657 → 12 行 library + 5 个 part
  文件：lexical 504 / pronunciation 452 / media_fit 283 / dictionary 237 / diagnosis 171
  行），沿 `models/timeline.dart` 既有 part 模式，40 个类逐字搬移、消费端 import 零改动。
  `flutter analyze` 零问题、`flutter test` 344 全通过。

- 2026-07-14 11:20 CST: 机械拆分 `api_service.dart`（1629 → 263 行核心 + 9 个按资源域的
  part 文件，各 73–345 行）。`LocalApi` 保留 connect/transport/`_request`/events/close
  生命周期；143 个资源方法逐字搬入 `services/api/{media,subtitles,timelines,speech,
  transcription,lexical,practice,listening_hunting,coach_llm}.dart` 的 `extension on
  LocalApi`（part 共享库作用域，私有 `_request` 照常可用；唯一文本改动是 media.dart 里
  static `_isAudio` 按 Dart 规则加 `LocalApi.` 限定）。29 个消费文件 import 与调用点
  零改动。附带 spike 结论：放弃从 OpenAPI 生成 Dart DTO——types.dart 的模型类携带领域
  便利方法（如 `triageQueue`），生成会破坏该设计；防漂移继续走既有 `test/contract/`
  对拍测试（已 12 个）+ Rust 侧 OpenAPI parity test。`flutter analyze` 零问题、
  `flutter test` 344 全通过。

- 2026-07-14 10:40 CST: 删除 46 方法的 fat `SubtitleRepository` trait 及其 4 组 blanket
  桥接 impl（repositories.rs 1375 → 848 行）。消费侧窄 trait（`SubtitleTrackRepository`/
  `PronunciationRepository`/`TimelineResourceRepository`/`LLTimelineResourceRepository`）
  早已存在且 AppServices 全部经窄 trait 依赖——fat trait 只是实现侧聚合，导致每加一个
  持久化方法要同步写 4 处（fat trait + 窄 trait + 桥接 + sqlite impl）。现
  `persistence-sqlite/subtitles.rs` 直接按资源 impl 4 个窄 trait（方法体逐字不变，仅
  lltimeline 两方法挪至文件尾自成 impl 块），新增方法今后只写 2 处。测试导入改窄
  trait。`cargo test --workspace` 608 全绿，clippy 告警 30 与基线持平（零回归）。

- 2026-07-14 10:05 CST: main.dart 拆分 S9 —— 3.9.3 合并带来的 `_checkSyntaxCapability`
  能力监控（方法 + busy/ready/analyzed 三个状态标志）逐字搬入
  `SubtitleSourcesCoordinator.checkSyntaxCapability`（字幕轨分析域的自然归属）；2 秒轮询
  Timer 生命周期留在宿主 `initState`/`dispose`。新增 2 例隔离测试（ready 轨道恰好分析
  一次、not_installed 时保持静默）。`flutter analyze` 零问题、`flutter test` 344 全通过
  （342 + 2）。

- 2026-07-14 09:35 CST: main.dart 拆分 S8 —— 词汇/学习类对话框与导航流程迁往
  `widgets/flows/learning_flows.dart`（沿用 flows 顶层函数模式）：
  `openLearningAssetsFlow`/`openLearningResourcesFlow`/`showCurrentPhraseCandidatesFlow`/
  `openPhraseFlow`/`correctCurrentLemmaFlow`/`showVocabularyFlow`/`openReviewQueueFlow`/
  `openCoachDashboardFlow`/`importWordListFlow`。宿主保留同名薄 wrapper。顺带修复新
  widget test 暴露的潜在缺陷：correct-lemma 对话框此前在退场动画期间就 dispose
  `TextEditingController`（debug 断言隐患），改由 `_LemmaCorrectionDialog` 自持生命周期。
  新增 `test/learning_flows_test.dart`（3 例：无选中 token no-op、修正词元发
  POST /lexical-normalization/correct、null api 不导航）。main.dart 1737 → 1551 行。
  `flutter analyze` 零问题、`flutter test` 337 全通过（334 + 3）。

- 2026-07-14 09:05 CST: main.dart 拆分 S7b —— 字幕资源类对话框/导航流程迁往
  `widgets/flows/subtitle_resource_flows.dart`（沿用 `media_import_flows.dart` 顶层
  flow 函数既有模式，非 coordinator）：`deleteSubtitleResourceFlow`/
  `exportSubtitleResourceFlow`/`generateSubtitlesFlow`/`openTranscriptionCenterFlow`/
  `openPhoneticAnalysisCenterFlow`/`openSubtitleResourcesFlow`/`openColdStartMarkingFlow`。
  宿主保留同名薄 wrapper 转调（R3：最小化 build 改动面）；`_generateSubtitles` 的
  setState 任务登记改注入 `recordTaskStatus` 回调（刻意不复用 `_setTaskStatus`，
  后者会额外覆盖 player status 文本，保持逐字语义）。新增
  `test/subtitle_resource_flows_test.dart`（4 例 widget test：删除取消/确认发
  DELETE、导出 null-api 不弹窗、导出双格式渲染与 dismissal）。main.dart
  1842 → 1737 行。`flutter analyze` 零问题、`flutter test` 334 全通过（330 + 4）。

- 2026-07-14 08:52 CST: main.dart 拆分 S7a —— 抽出 `SubtitleSourcesCoordinator`（仅上下文
  无关子集）：`ensureCurrentPronunciation`/`analyzePhonetics`/`handleDrop`/`isMediaPath`/
  `isSubtitlePath` 逐字搬到 `lib/controllers/subtitle_sources_coordinator.dart`，注入
  `getApi`/`isMounted`/`showSnackBar`/`setTaskStatus`/`openMediaPath`/`openSubtitlePath`。
  对话框驱动的来源流程（delete/export/generate/import word list/cold-start 等）按 S5 既定
  裁决留在宿主，后续 S7b 评估迁往 `widgets/flows/` 既有模式。逻辑/字符串不变。新增
  `test/subtitle_sources_coordinator_test.dart`（9 例：扩展名分类、drop 路由/前置守卫/
  不支持类型、发音缓存与去重、phonetics 无轨守卫/成功派发/失败上报）。main.dart
  1937 → 1842 行。`flutter analyze` 零问题、`flutter test` 330 全通过（321 + 9）。

- 2026-07-14 08:47 CST: main.dart 拆分 S6 —— 抽出 `MediaLibraryCoordinator`。首页媒体库/
  triage 动作 9 个方法（`recordRecentMedia`/`prefetchHomeSummary`/`loadMediaLibrary`/
  `openLibraryEntry`/`startExtensiveFromLibrary`/`startIntensiveFromLibrary`/
  `setLibraryTriageIntent`/`toggleFamiliarSupply`/`continueRecentMedia`）逐字搬到
  `lib/controllers/media_library_coordinator.dart`；coordinator 自持 `savedVocabulary`/
  `mediaLibrary` 两个首页汇总事实（原 State 字段），`setState` 改注入 `requestRebuild`；
  media-session 操作按 PLAN R5 走注入回调（`openMediaPath`/`openMedia`）而非直接持有
  coordinator。逻辑/字符串不变。新增 `test/media_library_coordinator_test.dart`（11 例：
  加载成功/失败保留旧值/null API no-op、缺失文件守卫、triage 就地替换与失败上报、continue
  回退拣选器/重开近期路径、recordRecentMedia 无媒体 no-op）。main.dart 2051 → 1937 行。
  `flutter analyze` 零问题、`flutter test` 321 全通过（310 + 11）。

- 2026-07-14 01:15 CST: main.dart 拆分 S5 —— 抽出 `VocabularyActionsCoordinator`（仅上下文无关
  数据方法）。vocabulary 入口大量 BuildContext 耦合（`showDialog`/`Navigator.push`/
  `MaterialPageRoute`），按代码库约定「coordinator 无 context、对话框留宿主」，这些导航/对话框
  方法保留在 State；可抽子集为 10 个纯数据方法：`loadWordEntries`/`loadPhraseEntries`/
  `loadPhraseCandidates`/`openWord`/`setSelectedWordStatus`/`setCapabilityOverride`/
  `saveSelectedLearningContent`/`recordCurrentSource`/`markFirstWord`/`observeSelected`，连同
  私有 `_sourceFor`（仅被这些方法使用，随之内化）逐字搬到
  `lib/controllers/vocabulary_actions_coordinator.dart`，注入 `getApi`/`isMounted`/`text`/
  `refreshDiagnosis`，其余用归位后的 `settings.resolveLearningLanguage`。逻辑/字符串不变。新增
  `test/vocabulary_actions_coordinator_test.dart`（markFirstWord 必刷 diagnosis、无选择的
  observeSelected 静默 no-op）。main.dart 2206 → 2051 行。`flutter analyze` 零问题、`flutter test`
  310 全通过（308 + 2）。

- 2026-07-14 00:50 CST: main.dart 拆分 S3+S4（合并）—— 抽出 `PracticeActionsCoordinator`。
  精听练习与 shadowing 深度交织（`_navigatePracticeSentence` 同时派发 cloze 与 shadowing、
  `_replayPracticeWindow`/`_setShadowingStep` 共享），故合为单个 coordinator 避免跨 coordinator
  循环依赖。19 个方法（四种练习启动、练习窗循环、提交、录音/回放/ABA、rate/step、external/
  slice-window shadowing、复习保存、句子导航、teardown）逐字搬到
  `lib/controllers/practice_actions_coordinator.dart`；注入 `getApi`/`isMounted`/`refreshDiagnosis`/
  `seekCue`，`tools` 由持有的 settings 内部派生，其余全用 S2.5 归位后的 `playbackActions.*` 与
  `settings.resolveLearningLanguage`。逻辑/字符串不变；~24 处调用点改走 coordinator。新增
  `test/practice_actions_coordinator_test.dart`（4 例：无 draft replay no-op、submit 必刷 diagnosis
  回调、无目标句不 seek、无 attempt 不改状态）。main.dart 2469 → 2206 行。`flutter analyze`
  零问题、`flutter test` 308 全通过（304 + 4）。

- 2026-07-14 00:25 CST: main.dart 拆分 S2.5 —— 把跨领域共享 glue helper 归位到自然属主，
  为后续 coordinator 抽取降低注入面。`_mediaTimeMs` 与 `_currentPracticeChunk(s)` 迁入
  `PlaybackActionsCoordinator`（已持 `mediaTime`/`currentChunkRef`/subtitle）；`_learningLanguage`
  改为 `SettingsController.resolveLearningLanguage(trackLanguage)`，main.dart 16 处调用点改为
  `settingsController.resolveLearningLanguage(subtitleController.primaryTrack?.language)`。
  `ListeningInboxCoordinator` 随之去掉 `mediaTimeMs` 注入，直接用 `playbackActions.mediaTimeMs`。
  `_sourceFor`（仅 vocab 使用）留待 vocab slice。逻辑逐字不变；新增 3 例测试（coordinators_test
  的 mediaTimeMs/practice-chunk 空态、settings_test 的 resolveLearningLanguage 优先级）。
  `flutter analyze` 零问题、`flutter test` 304 全通过（301 + 3）。

- 2026-07-14 00:05 CST: main.dart 拆分 S2 —— 抽出 `ListeningInboxCoordinator`。把
  `_captureListeningInbox` / `_refreshListeningInbox` / `_replayListeningInboxItem` /
  `_processListeningInboxItem` 四个方法逐字搬到 `lib/controllers/listening_inbox_coordinator.dart`
  （注入 `getApi`/`isMounted`/`mediaTimeMs` + 复用既有 `playbackActions`），逻辑/字符串不变。
  `_hardInterruptListening` 与 `_toggleExtensiveListening`（含 `showDialog` 与跨 slice
  `_refreshDiagnosis` 依赖）暂留 State，待其依赖抽出后处理；两个 `loopRange` 方法后续归入
  `PlaybackActionsCoordinator`。新增 `test/listening_inbox_coordinator_test.dart`（3 例：process
  review-item 分支、null-range replay 守卫、null-api no-op）。main.dart 2527 → 2476 行。
  `flutter analyze` 零问题、`flutter test` 301 全通过（298 + 3）。

- 2026-07-13 23:40 CST: main.dart 拆分 S1 —— 抽出 `HuntingActionsCoordinator`。把
  `_toggleHuntingMode` / `_reindexHuntingCorpus` / `_answerHuntingCheck` 三个方法逐字搬到
  `lib/controllers/hunting_actions_coordinator.dart`，仅做 seam 改写（`api`→`getApi()`、
  `mounted`→`isMounted()`、`l.text`→注入 `text()`、controller 接收者按现有 coordinator 短命名）；
  逻辑/分支/字符串不变。`_PlayerScreenState` 新增 `huntingActions` 字段 + `initState` bind，
  3 处调用点改走 coordinator。新增 `test/hunting_actions_coordinator_test.dart`（5 例：toggle
  启/停、reindex 成功/失败、null-api no-op），复用既有 `LocalApi.withTransport` fake。main.dart
  2578 → 2527 行。`flutter analyze` 零问题、`flutter test` 298 全通过（293 + 5）。

- 2026-07-13 23:20 CST: 立 `main.dart` Coordinator 抽取治理 mini-phase 的可执行 PLAN
  （`.planning/phases/main-dart-coordinator-extraction/PLAN.md`）。核实 `_PlayerScreenState`
  从 2.23 的 1457 行回涨至 2578 行，且无任何测试 mount `PlayerScreen`、State 无 DI，故整屏
  widget 测试不可行；测试网改建在代码库既有的 Coordinator 隔离单测层。PLAN 按现有
  `media_session_coordinator` 模板，分 Slice 0（fakes + 前置）+ S1–S7（Hunting / Inbox /
  Shadowing / Practice / Vocabulary / MediaLibrary / SubtitleSources），逐 Slice test-first、
  逐字搬移、analyze+test+对拍验证；`initState`/`dispose`/`build`/视图组合与高频 `_onPosition`
  保留在 State。属语义重构（非机械搬移），与本次 lexical/timeline 两个纯机械拆分区分。

- 2026-07-13 23:05 CST: 机械拆分 `apps/desktop/lib/models/timeline.dart`（2837 → 10 行 library +
  6 个 part 文件，最大 `rhythm.dart` 965 行，均低于 AGENT.md 1500 行阈值）。采用 Dart
  `part`/`part of`：原文件零 import、完全自包含，故 43 处 `import 'models/timeline.dart'` 全部
  保持不变。按子领域切分：`timeline/subtitle.dart`（token/cue/track/capabilities）、`word_chunk.dart`
  （Word/Chunk timeline + evidence + SenseGroup）、`sound.dart`（PhoneTimeline + sound 原语）、
  `rhythm.dart`（RhythmFrame 模型全族）、`document.dart`（LLTimeline document/metadata/artifact/
  DetectedPhone）、`display.dart`（DisplayChunk/partition/cursor）。逐字搬移，脚本验证 2618 非空行
  与原文完全一致（仅 dart format 空行规整）。`flutter analyze` 零问题、`flutter test` 293 全通过、
  未违反 ADR 0014（手写解析不变，仅分文件）。

- 2026-07-13 22:47 CST: 机械拆分 `persistence-sqlite/src/lexical.rs`（1801 → 948 行，低于
  AGENT.md 1500 行阈值）。按子领域抽出三个子模块：`lexical/import_export.rs`（bulk
  import/export + capability-state 持久化的两个 inherent impl 块 + `merge_imported_entry`）、
  `lexical/capability.rs`（capability profile/state 读写 helper）、`lexical/rows.rs`（row 反序列化
  + sense-folder/observation reader）。`LearningAssetRepository` trait impl 因 Rust 不允许 trait
  impl 跨文件拆分，保留在 `lexical.rs`。纯搬移不改逻辑；`export_lexical_assets`/
  `import_lexical_assets` 升为 `pub(crate)` 以保持 tests 可见。`cargo test -p persistence-sqlite`
  110+5+6 全绿，workspace build 通过，clippy 告警数 19 与拆分前完全一致（零回归）。

- 2026-07-13 22:25 CST: Phase 3.9.3 完整收口并冻结。最终 `jsonl-v2` 修复带前导空格字幕的
  spaCy SPACE token/head 重映射，delivery identity 现同时绑定 provider/requirements/sidecar/model；
  真实 244 cue App 路径为 243 analyzed + 1 `invalid_sentence` 隔离，首次 rebuild 2.10s、同 fingerprint
  hot hit 0.11s。实测完成 clean install、restart persistence、stale/update、模型损坏 partial/恢复、
  disable/enable、cancel/retry 和 uninstall；取消安装改为终止完整 venv/ensurepip process group，确认
  staging 零残留。Rust workspace/Clippy/contracts/Python、Flutter analyze/test、release backend 与 macOS
  build 全绿；QUALIFICATION、REAL-MEDIA-QA、codebase、STATE、PLAN、CLOSEOUT 已同步。

- 2026-07-13 21:54 CST: Phase 3.9.3 交付 App 内可选句法 capability 竖切片。后端新增持久化
  `not_installed/downloading/ready/partial/failed/stale/disabled` 状态、版本化 Application Support
  安装目录和 install/cancel/retry(update)/verify/enable/disable/uninstall HTTP 路径；fully pinned
  runtime/model 在 staging 校验后原子发布，基础 bundle 仍不含 Python/runtime/model。spaCy JSONL
  adapter 改为 probe/analyze 共享长驻进程，支持主动 idle release、崩溃单次恢复和 lifecycle shutdown。
  整轨分析新增 subtitle/token/language/model/config fingerprint、single-flight、逐句 partial 隔离、cache
  hit/stale/force rebuild；Flutter 设置页提供完整动作、进度/错误/当前轨道状态，安装完成或打开未分析
  轨道时静默后台启动，相同 fingerprint 复用。新增 Rust/HTTP/Dart DTO/transport/widget tests 与 OpenAPI；
  未安装不启动 Python、不弹窗、不阻塞字幕或播放，B `want_to`/C/ChunkTimeline/Construction 边界未变。

- 2026-07-13 21:33 CST: 新建 Phase 3.9.3 Syntax Capability Delivery & Lifecycle，基于冻结的
  3.9.2 最终提交 `71be2c20` 建立独立分支与 phase 文档。计划把已资格 spaCy Provider 补成
  App 内可安装/校验/取消/重试/更新/停用/卸载的可选能力，并交付持久状态机、长驻 sidecar、
  整轨 fingerprint cache、stale/rebuild、自动后台分析和 Flutter 完整用户路径；未安装零打扰、
  base bundle +0B、B/want-to/C/ChunkTimeline/Construction identity 边界保持不变。

- 2026-07-13 19:30 CST: Phase 3.9.2 Syntax Provider Product Activation 收口。corrected v2
  holdout、逐 query qualification、spaCy opt-in lifecycle、单 batch/逐句共享编排、真实媒体与
  missing/corrupt/invalid/timeout 降级全部通过；contracts、句法相关 crates 与 Rust workspace
  全绿。最终裁决为 spaCy artifact + B `going_to`/`used_to`/`have_to` + SenseGroup + matcher
  qualified，B `want_to` fallback-only；base bundle +0B，C/ChunkTimeline/Construction identity
  边界冻结。PLAN/STATE/CLOSEOUT 已更新，phase 转 COMPLETED。

- 2026-07-13 19:22 CST: Phase 3.9.2 激活可选 spaCy 共享句法产品 capability。application
  新增单次 probe/batch、逐句 finalise 的 consumer orchestrator；同一 artifact ID 供已资格
  B（`going_to` / `used_to` / `have_to`）、syntax-aware SenseGroup 与 dependency candidate
  matcher 共用，`want_to` 继续精确 text fallback。新增 HTTP/OpenAPI composition、未配置/timeout/
  坏树逐句隔离测试；base 路径不启动 Python。fresh opt-in 安装以 fully pinned spaCy 3.8.13 +
  `en_core_web_sm` 3.8.0 实测通过 probe 与 development v2，clean install 162,250,752 bytes，
  base bundle +0B；runtime/model/training-data 许可与安装/刷新/停用/卸载分别审计。模型 identity
  排除非内容 `__pycache__/*.pyc` 后在 research/fresh venv 稳定一致；真实媒体 244 cues 中唯一
  双 root 句单独 fallback，不影响其余句，句法仍不进入 C、不替代 ChunkTimeline、不铸造
  Construction identity。

- 2026-07-13 18:57 CST: Phase 3.9.2 Slice 0 建立 corrected syntax qualification v2。冻结旧 v1
  历史，新增 development/validation v2、独立 digest 与 scorer，把 attachment gold、产品歧义
  policy 和 artifact validity 分层，并改为逐 consumer query 授权。spaCy 开发/锁定验证均达到
  100% lexical/exact mapping、零 silent/tree issue；`going_to`、`used_to`、`have_to` 各自 100%
  qualified。basic dependency 无法稳定区分 want-to wh subject/object，且锁定歧义例 raw allow，
  因而 `want_to` 明确为 `fallback_only`，不能再整体否决 artifact，也不能整体放行 provider。

- 2026-07-13 18:45 CST: 新建 Phase 3.9.2 Syntax Provider Qualification Correction and Product
  Activation。纠正 3.9.1 将 `Which team do you want to win?` 的保守 block policy 当作唯一
  parser attachment gold 的评估错误；冻结旧报告，另建 v2 subject/object 清晰最小对照和
  ambiguous-abstain gate。首选 spaCy 作单一产品候选；若修正版资格通过，则在不让 Python/model
  成为基础产品硬依赖的前提下，让 B、syntax-aware SenseGroup 与 Construction candidate matcher
  共享同一 validated artifact，并保留 C/ChunkTimeline/Construction identity 边界和无模型 fallback。

- 2026-07-13 16:53 CST: Phase 3.9.1 Shared Syntactic Analysis Provider 收口。完整 contracts 与
  Rust workspace 测试通过；PLAN/STATE/CLOSEOUT 记录负向资格结论：Stanza/spaCy 共享中立契约、
  token mapping、sidecar failure taxonomy、B/SenseGroup consumer 与 Construction candidate
  matcher 均已验证，但两个候选都因锁定 wh-extraction 高风险假阳性不得激活。模型、runtime、
  treebank/training provenance 分层审计完成；无模型产品路径保持原 B 与 rule SenseGroup，句法
  不进入 C、不替代 ChunkTimeline、不铸造 Construction identity。

- 2026-07-13 16:48 CST: Phase 3.9.1 Slice 6 建立 Construction dependency matcher seam 与真实
  媒体 QA。matcher 只在 qualified + activatable artifact 上输出带 source artifact、subtitle
  token span 与 bindings 的可重建候选，类型和序列化守卫证明不会铸造 Construction canonical/
  occurrence identity 或 capability。以 owner 本地 244 cue / 1773 word 新闻字幕运行 Stanza/
  spaCy：两者 lexical mapping 100%、exact span 98.76%、零静默错位且刷新确定；Stanza 零树错误，
  spaCy 在一个口语残句产生双 root 并被 validator 闭合拒绝。生产 SenseGroup 对真实 Stanza
  输出保持教学粒度和 `New York City` 多词短语完整性；missing/corrupt/invalid sidecar 均不生成
  draft。报告不复制字幕正文，未资格候选仍不接入产品，B/SenseGroup 保留原 fallback，C 与
  ChunkTimeline 未改动。

- 2026-07-13 16:36 CST: Phase 3.9.1 Slice 5 新增独立 syntax-aware SenseGroup Provider。
  新增 `syntax-aware-sense-group/v1` / `dependency_teaching_partition_v1`，与既有
  `rule-based-sense-group/v1` 分开 fingerprint、持久化和 candidate/active/archive 生命周期；
  metrics 引用 syntactic artifact/descriptor 并显式记录 `chunk_timeline_dependency=false`。
  dependency clause/conj/subordinator/PP subtree 只提出 boundary/head/NP-PP-clause label，强标点、
  phrase candidate 完整性、min 2/hard max 8 与典型 3–5 组教学粒度仍作最终裁决；错误 snapshot
  或低 coverage 精确返回原 rule partition。新增 4 项 syntax partition fixture 和 rule/syntax
  双 run 持久化回归；未资格 Provider 在 application gate 被拒绝，现有 HTTP 默认生成路径保持
  rule Provider，ChunkTimeline 代码与生命周期均未改动。

- 2026-07-13 16:27 CST: Phase 3.9.1 Slice 4 建立 Reference B 句法 consumer seam。
  `ConnectedSpeechContext` 将 validator activatable 与外部 provider qualification 设为两个独立
  gate；未资格/缺失 artifact 与原 `predict_default_connected` 输出逐项相同。本阶段只把锁定
  验证通过的 future/motion `going to`、habitual/state（含 `get used to`）和 `have to do with`
  idiom 用中立 UPOS/lemma/features 映射作保守门控；失败的 `want to` wh-extraction 仍固定走
  现有 text heuristic。B evidence 区分 `prediction_provenance:syntax_model`（带 artifact ID）
  与 `text_heuristic`，但 status 仍为 `PossibleByRule`，不冒充 C/audio evidence。新增 5 项
  syntax consumer/fallback 回归；speech-analysis 175 单元 + 12 集成测试全通过。

- 2026-07-13 16:22 CST: Phase 3.9.1 Slice 3 完成冻结评估与负资格判定。
  开发集仅用于 neutral query/mapping 调整；随后按预登记 digest 对验证集每个候选只运行一次。
  Stanza 1.13.0/en_ewt 与 spaCy 3.8.13/en_core_web_sm 3.8.0 均达到 100% lexical/exact
  mapping、零静默错位/树错误，并在 future/motion `going to`、habitual/state `used to`、
  obligation/idiom `have to` 对上满分；但两者都在 multi-token wh-extraction
  `Which team ... want to win` 产生一项高风险 `wanna` 假阳性，依锁定零容忍 gate 判为
  `not_qualified`，未添加 validation-specific 特例。资源 gate 均通过（Stanza/spaCy cold p95
  2.63/1.21s、warm p95 106.4/4.1ms、RSS 0.86/0.32GB、产品包 +0B）；runtime/model/
  treebank 分层许可证、精确 installed-tree checksum/size 和 raw case reports 已审计，Stanza
  传递训练数据 provenance 不完整仍独立保持 research-only。

- 2026-07-13 16:10 CST: Phase 3.9.1 Slice 2 新增隔离式 Python 句法研究 Provider。
  新建 `syntactic-provider` Rust crate 与版本化 JSONL sidecar，Stanza/spaCy 均只输出同一
  provider-neutral draft；进程边界保持 stdout 纯协议、stderr 诊断，lazy runtime/model
  探测和 runtime missing/model missing/corrupt/unsupported language/invalid output/timeout
  闭合失败不会生成 artifact。token 映射覆盖 Unicode scalar offset、缩约 N:1、缩写 1:N、
  normalized overlap 与显式 unaligned；Stanza/spaCy 原生标签在适配器内归一化，产品包不
  链接 Python/model。新增 opt-in 隔离 venv、研究资产分层许可证 manifest、8 项 Python
  sidecar contract 与 4 项 Rust process contract，并纳入全局 contract validator。

- 2026-07-13 15:56 CST: Phase 3.9.1 Slice 1 建立 provider-neutral Rust 契约。
  domain 新增版本化 `SyntacticAnalysis`、完整 provider/runtime/model/checksum provenance、
  Unicode scalar char span 多对多映射、UD 字段、source/config/model 隔离 fingerprint，以及
  span/coverage/HEAD/单 root/无环/sentence ownership validator；application 新增 draft-only
  `SyntacticAnalysisProvider`、capability 与 closed error taxonomy，并由 server-side finalizer
  铸造 artifact identity、拒绝 invalid provider 输出。fake provider、缩约 N:1、低 coverage
  abstain、坏 span/head/cycle 和模型升级重算测试通过；本 slice 不增加持久化或 parser runtime。

- 2026-07-13 14:21 CST: Phase 3.9.1 Slice 0 建立共享句法 Provider 的可执行研究边界。
  新增 ADR 0023，锁定 provider-neutral、可重建 artifact、Unicode scalar half-open char span
  1:N/N:1 token 映射、closed validation/abstain 降级、隔离 provider/runtime/model/config 的缓存
  身份，以及不得填充 C、替代 ChunkTimeline 或铸造 Construction identity 的边界。新增 24 条
  开发/锁定验证歧义 fixture（含真实 CNN10 字幕短摘录与受控最小对照）、4 条 mapping contract
  fixture 和无 parser 依赖的 validator；预登记 alignment/关键歧义/失败/延迟/内存/体积 gate，
  并分别审计 Stanza/spaCy runtime、model weights 与 UD/treebank 许可，未知项保持 research-only。

- 2026-07-13 13:59 CST: 新建 Phase 3.9.1 Shared Syntactic Analysis Provider。确定以
  UD/CoNLL-U 语义建立共享、可重建的 token-aligned 句法 artifact，通过现有 Python sidecar
  模式先评估 Stanza/spaCy，供 Reference B、SenseGroup 与 Construction 共用；明确模型缺席
  时保留现有保守 B 与标点/长度 SenseGroup，句法结果不得填充 C、替代 ChunkTimeline 或铸造
  Construction canonical identity。新增 CAP-011/012，锁定 char-span 1:N/N:1 token 映射、
  开发/验证集分离、真实字幕歧义评估及代码/runtime/model/treebank 分层许可证审计。

- 2026-07-13 13:25 CST: Phase 3.9 英语语流规则第二批。Reference B 规则源升级为 v3；Phrase
  rule 新增上下文门控，不再把字面相邻词无条件缩约：`going to` 只接受动词补语候选并阻断
  专名/限定词/常见地点歧义，`want to` 对 wh-extraction 歧义保守缺席，`used to` 区分
  habitual 与 `be used to + NP/gerund`。新增 `gotta`、`hafta/hasta`、`had to`、habitual
  `used to`、`supposed to/ought to`、安全层 `trying to`，以及
  `lemme/gimme/kinda/sorta/outta/lotta/lotsa/dunno` 的完整 A→B 音素结构；weak form 补标点、话语
  起始 `/h/`、`the + vowel` 阻断。新增正例、motion/NP/疑问抽取/形容词 used-to 等反例和
  UI 结构断言；speech-analysis 170 项测试全通过。规则与来源同步登记到 3.9 catalog。
  `connected_speech_rules.rs` 达到规模线后，将构式/弱读阻断提取到 `context.rs`（主文件回落
  到 1403 行），为下一批音节规则保留清晰模块边界。

- 2026-07-13 12:17 CST: Phase 3.9 第 4 项启动：新增 General American 英语语流完整规则目录，
  按 `B-safe` / `B-context` / `C-only` / `dialect` 记录音素环境、阻断条件、口音范围、来源和
  实现状态，明确“全部纳入目录”不等于把声学渐变现象伪造成 B。首批 B 扩展：硬编码
  `did you` 改为通用 `/t,d,s,z/ + /j/` coalescence，并修正输出为 `/dɪdʒu/`；新增 `/n/`
  在双唇/软腭音前的部位同化、V#V `[j]/[w]` 连接、跨词弱功能词前的美式 flap；词内 flap
  加入“重读元音后、非重读元音前”条件，`/t,d/` 删除收紧为词尾辅音簇 + 辅音环境。新增
  标点/强边界阻断，避免跨逗号等标点触发 linking/assimilation/deletion；新增规则环境与
  反例测试，speech-analysis 全部 165 项回归通过。

- 2026-07-13 10:57 CST: 修复长句 A/B/C 结构带后半句不可见。新增三视图共用的跟随式
  sentence viewport：紧凑模式按当前 token/播放节点自动横向定位，左右渐隐提示仍有内容；
  展开按钮切换为可换行、可纵向滚动的完整句结构。A 跟随单词，B 同时跟随规则跨度与普通
  文本跨度，C 跟随当前音频节点；切换视图不再只能看到句首。新增长句第 11 节点定位和完整
  展开回归测试，中英 tooltip 同步补齐。

- 2026-07-13 10:47 CST: 修正 Rhythm C 证据门控。播放器不再把 text/WordTimeline 派生的
  RhythmFrame 作为“预测 C”显示；C 现在同时要求当前句已加载音素，且 frame 自身
  `phone_evidence_coverage > 0`。无音素证据时只提供当前句/全轨音频分析入口，A/B 仍可正常
  使用。新增四象限回归测试锁定“有 frame 无 phones”“有 phones 无 frame phone evidence”
  均不得显示 C。

- 2026-07-13 10:30 CST: 修复导入过 LLTimeline 后刷新听感结构仍显示不可用。Flutter 资源
  加载不再用带 artifacts 的旧文档整体覆盖后端新导出文档；现在保留新导出的 WordTimeline
  派生 RhythmFrame，仅把旧 artifacts 合并回来。新增回归测试覆盖“旧文档无 rhythm frames、
  新导出有 rhythm frames”的真实 QA 场景。

- 2026-07-13 10:12 CST: 将 Phase 3.9 A/B/C audible-structure 两批实现合入已完成
  Phase 3.12 的 main；保留 3.12 收口事实，并将 3.9 状态切换为主工作区真实媒体 QA 与
  增量修正。后续工作从 main 新建专用阶段分支，不在 main 直接开发。

- 2026-07-13 09:24 CST: Phase 3.12 Vendor-neutral LLM Provider 收口，CODE COMPLETE。
  创建 `3.12-CLOSEOUT.md`（五切片 0/1/2/2b/3 交付清单、七项 Key Decisions、四条 exit signal
  逐条核验通过、验证记录、QA 归属、Deferred 清单）；PLAN 置 CODE COMPLETE；STATE.md 主线
  切换至 Phase 3.13 Reading Studio / 3.12.1 Judge Qualification 并登记已完成 phase 索引。
  Exit signals 全部核验通过：两异构 adapter 同契约套件证中立、切 provider 领域 JSON 不变 +
  provenance 保留、删/禁 key 诚实降级、密钥不落普通存储 + 错误不回显凭证。剩余为 owner 真实
  provider 端到端产品 QA（人工门）与增量协议 Slice 4（owner 按需）；judge 质量资格属 3.12.1。

- 2026-07-13 09:24 CST: Phase 3.12 Slice 3：Flutter 最小设置 UI（AI providers）。
  新增 `apps/desktop/lib/models/llm_provider.dart` 手写 DTO（`LlmProviderProfileView`
  /`LlmProviderCapability`/`LlmCapabilityClaim`/`LlmProbeResult`，ADR 0014）+
  `test/contract/llm_provider_contract_test.dart` fixture 契约测试（4 项，pin 到
  OpenAPI v1.yaml）；`LocalApi` 增 listLlmProviders/registerLlmProvider/deleteLlmProvider/
  probeLlmProvider（secret 只写、DELETE 204→null）；自包含 `LlmProviderSettings` widget
  （provider 列表 + 添加表单 + 连通/能力 probe 测试 + 删除；协议下拉 OpenAI/Anthropic、
  用途勾选、密钥 obscured 提交后即清空、数据去向警告、"未获显示资格 仅供诊断"提示、
  has_credential 徽标不显示 secret）；SettingsDialog 加第 7 个导航类目"AI providers"
  与 section（新增可空 `api` 参数，缺 sidecar 时降级提示），settings_flow 传入既有 `api`；
  localization en+zh 补 24 键。判定默认不获显示资格（属 3.12.1），UI 明示。
  验证：flutter analyze 全项目零问题；flutter test 288 全通过（含新增 4 契约）。
  Rust 侧本切片未改动。至此 3.12 功能面完成，剩余：增量协议（Slice 4，owner 按需）、CLOSEOUT。

- 2026-07-13 08:57 CST: Phase 3.12 Slice 2b：provider 工厂 + 真实 OS-keychain + HTTP 路由。
  llm-provider 新增 `BuiltSemanticProvider`（按 profile.adapter_kind 建 OpenAI/Anthropic
  adapter，暴露 as_judge/as_rubric/probe；新协议= 新 match 臂，契约不变）+ 工厂契约测试
  （两 profile 建对应 adapter、probe 实测能力）。api-http：`crates/api-http/src/routes/llm.rs`
  四路由 `GET/POST /v1/llm/providers`、`GET/DELETE /v1/llm/providers/{id}`、
  `POST .../{id}/probe`（连通+能力实测）、`POST .../{id}/judge`（provider-backed 判定→
  记为 heuristic_proxy，不进 surface）；响应用 `ProviderProfileView`（只暴露 has_credential，
  **不含 auth_ref/secret**）；`secret` 请求字段 write-only 入 keychain。`KeychainSecretStore`
  （`secret_store_keychain.rs`，security-framework generic password，cfg-gated macOS + 非
  macOS 显式 unsupported，auth_ref=随机 account id）；`ApiState` 加 `secret_store`（默认
  in-memory，`with_secret_store` 注入 keychain）；main.rs 接 profile repo + keychain。
  OpenAPI v1.yaml 补 4 路由 + `LlmProviderProfileView`/`RegisterLlmProvider`/`CapabilityClaim`/
  `ProviderCapability`/`LlmAdapterKind`/`LlmUse`/`DataRetentionPreference`/`CostBudget` schema。
  api-http 集成测试（默认 in-memory store + 本地 fake endpoint）：注册不回显 secret、列表无
  secret、probe 实测 supported、删除移除、未知 provider judge→404。
  **修 bug**：`LlmAdapterKind` serde snake_case 会产出 `open_ai_chat_completions` 与 `as_str()`
  的 `openai_chat_completions` 分叉（DB 列 vs JSON blob），显式 `#[serde(rename)]` 对齐。
  验证：domain 74 / application 53+ / llm-provider 12 / persistence 109 / api-http 44+12 全通过；
  新文件 clippy 零告警；validate-contracts OK（OpenAPI route-drift 门通过）。剩余：最小设置
  UI（Slice 3）、增量协议 OpenAI Responses/Gemini（Slice 4）、CLOSEOUT。

- 2026-07-13 08:22 CST: Phase 3.12 Vendor-neutral LLM Provider 后端优先切片落地
  （Slice 0/1/2a/2b，设置 UI 与真实 keychain 实现后置）。**中立性证明（核心 exit
  signal）成立**：新增 `crates/llm-provider/`，用 `reqwest` 手写两个异构协议 adapter
  （OpenAI Chat Completions-compatible = Bearer/扁平 messages/native response_format；
  Anthropic Messages = x-api-key+version/顶层 system/content block/tool_use 结构化输出），
  由泛型 `LlmSemanticProvider<A>` 组合 prompt/schema/parse 一次写成；本地 axum fake-server
  契约套件驱动**两个 adapter 过同一场景**（成功/拒绝/schema-invalid/截断/限流/超时/probe），
  核心断言 `drafts[0]==drafts[1]`（异构 wire→相同领域输出）通过（10 契约测试）。
  domain 新增 `llm_provider.rs`（`LlmAdapterKind`、`LlmProviderProfile`、opaque
  `LlmAuthRef`、`ProviderCapability`/`CapabilityClaim`=Declared/Probed/Unknown、`LlmUse`、
  `DataRetentionPreference`、标准化 secret-free `LlmProviderError` 分类学）；application
  新增两层 seam（`LlmChatAdapter` wire seam + `SemanticRubricProvider`/`SemanticJudgeProvider`
  application seam + `RubricDraft`/`JudgmentDraft` 仅内容草稿）。**draft-not-domain-type
  边界**：provider 只返内容草稿，身份 fingerprint/版本/快照 hash/3.11 validator 全部
  服务端持有（`record_llm_judgment` + `judge_semantic_attempt`）——四层分离经 LLM 路径
  仍成立，5 种失败模式一律不写 judgment（诚实降级）。**密钥安全**：`SecretStore` trait +
  in-memory 实现；`0036_llm_provider_profiles.sql`（只存 auth_ref，无密钥列）+
  `LlmProviderProfileRepository` SQLite 实现 + register/delete-with-secret use case；
  守卫测试证明**注册后 raw key 不出现在任何 DB 列或 JSON blob**、删除 provider 同删密钥、
  密钥被外部删除时降级为 None 不报错。api-http 补 `Provider`/`SecretStore` 错误 → HTTP 映射
  （secret-free，auth 无 payload）。新增 ADR 0022（provider 中立/draft 边界/keychain+auth_ref/
  能力 probe/诚实降级/无显示资格）。远端对照证伪写入 PLAN v3：架构照 rust-genai 中立-类型派、
  拒绝 LiteLLM 归一 OpenAI wire、能力描述符借 LiteLLM 分类学但对本地 endpoint 必须 probe、
  密钥严于 genai(env)/aichat(明文)。修正 `MIGRATION_VERSION` 35→36。验证：domain 74 /
  application 41 / llm-provider 10 契约 / persistence 109（含 4 profile + 4 LLM judgment）/
  api-http 53 全通过；新文件 clippy 零告警；validate-contracts OK；git diff --check 通过。
  本 phase 判定默认**不获任何显示资格**（资格评估属 3.12.1）；剩余：真实 OS-keychain
  SecretStore 实现、provider-backed HTTP 路由与工厂、最小设置 UI、closeout。
- 2026-07-13 08:40 CST: 扩展 Phase 3.9 B 预测可听结构到 weak form、contraction、
  assimilation、deletion 与 flapping。Deletion 由空预测改为在完整跨词结构中移除词尾
  `/t|d/`（如 `last call`：`/læst | kɔl/ → /læs.kɔl/`）；flapping 不再只
  输出孤立 `DX`，而是在完整词内把元音间 `/t|d/` 替换为 `/ɾ/`。其余三类使用完整规则
  音素生成可听结构；新增测试确保所有类别都有 A/B 且纯文本规则不生成 C。

- 2026-07-13 08:28 CST: 恢复 Phase 3.9 的 A/B/C audible-structure 算法与 UI 重构并完成
  linking 首条竖切片。`RhythmConnectedSpeechRef` 新增向后兼容的 A citation、B predicted、
  C actual 可听结构（音组、IPA、学习者 cue、书写 token 来源映射）；`pick up` 的文本规则现
  输出 `/pɪk | ʌp/ → /pɪ.kʌp/` 与 `pɪ-kʌp`，不再只显示 linking 类别。C 仅在存在
  observed phone evidence 时生成，timing/prosody 只作边界与分组证据。Flutter B ribbon
  直接呈现书写结构到可听结构的变化，C ribbon 展示 phone-segmental 支持的实际音组；OpenAPI、
  Dart model、Rust/Flutter/contract 回归同步扩展。Phase 3.12 继续在独立 worktree 并行推进。

- 2026-07-12 19:20 CST: 清除 speech-analysis 既有 deny 级 clippy error。
  `sense_group_partition.rs` 测试里的恒真断言 `assert!(any_span_covers || true, ...)`
  （Phase 3.4.2 引入，触发 `overly_complex_bool_expr`）改为实义断言
  `assert!(any_span_covers, ...)`：探查确认含中间标点的句子里逗号 token 确实被相邻
  sense group span 吸收，断言现在真正锚定该行为并匹配测试名，注释同步纠正。
  speech-analysis 155 项测试通过；workspace-wide `cargo clippy --all-targets` error 归零。

- 2026-07-12 18:55 CST: Phase 3.11 Slice 4 收口，Semantic Task Evidence Foundation
  CODE COMPLETE。新增 ADR 0021（semantic attempt/judgment/observation/capability 四层分离、
  独立任务族 spike 裁决、rubric 身份含 purpose、abstain 一等、adjudication 非 override、
  v35 append-only、portable/export 不进 VocabularyAssetBundle、§3.7 过渡规则由本 ADR 取代）；
  evidence matrix 标记 FINALIZED；创建 `3.11-CLOSEOUT.md`；PLAN 置为 CODE COMPLETE；
  STATE.md 主线切换至 Phase 3.12 并登记已完成 phase 索引。修复 api-http 测试
  needless_range_loop 告警。exit signals 全部核验通过；本 phase 无独立 UI，真实内容
  端到端 QA 归属首个消费它的 Studio（3.13）。

- 2026-07-12 18:40 CST: Phase 3.11 Slice 3 落地：最小 HTTP API + OpenAPI 契约。新增
  `crates/api-http/src/routes/semantic.rs`：`/v1/semantic/rubrics`(+`/{id}`、
  `/{id}/attempts`)、`/v1/semantic/attempts`(+`/{id}`、`/{id}/judgments`)、
  `/v1/semantic/judgments`(+`/{id}/adjudications`)、`/v1/semantic/adjudications`
  九条只写读面（无 update/delete，append-only；id 服务端按 fingerprint 生成）；
  `contracts/openapi/v1.yaml` 补齐九路径与 19 个 schema（Semantic* / Rubric* /
  AttemptResponse / PointJudgment / JudgmentAbstain 等）；domain 新增
  `semantic_task_attempt_id` fingerprint 助手。api-http 契约测试引用 Slice 1 gold
  fixture 走完整 HTTP 链路（好/差/abstain 三判定 + adjudication 往返、abstain 逐点为空、
  矩阵违规与篡改哈希返回 400、未知 rubric 版本 404）。本 phase 不交 Dart DTO（推迟
  3.13 首个真实 consumer）。api-http 53 项、workspace 25 套件、validate-contracts
  全部通过。

- 2026-07-12 18:05 CST: Phase 3.11 Slice 2 落地：schema v35 + repository + use case。
  新增 `0035_semantic_tasks.sql`（semantic_rubrics/semantic_task_attempts/
  semantic_judgments/judgment_adjudications 四表，UPDATE/DELETE 全部触发器禁止，
  刻意不建任何指向 media 的外键）；`SemanticTaskRepository` trait + SQLite 实现
  （queryable 列 + 全量 JSON 文档，无更新/删除方法）；AppServices 语义任务 use case
  （rubric 版本续接校验、attempt/judgment/adjudication 全链路 domain validator 前置、
  重复冲突与篡改哈希拒绝）；`ApplicationError::Invalid` 动态校验错误 → HTTP 400
  `invalid_input`。负向测试：语义全流程零 lexical observation/capability 变更、
  adjudication 后 judgment 行逐字节不变、删除媒体后全链路仍可读、四表 append-only
  触发器生效、3.8 shadowing 完成路径延伸断言不产生任何 semantic 事实。dictogloss
  in-progress 草稿持久化显式推迟到首个 Studio consumer（迁移文件注释记录 additive
  路径）。workspace 测试全绿；clippy 唯一 error 为 speech-analysis 既有基线。

- 2026-07-12 17:48 CST: Phase 3.11 Slice 1 落地：domain 语义任务契约层。新增
  `crates/domain/src/semantic_task.rs`：`SemanticTaskKind` 封闭枚举（七类任务）、
  `SemanticRubric`（自足来源快照 + 版本 + 修订注记 + generator provenance）、
  `SemanticTaskAttempt`（clip 级事实，仅 completed/abandoned，无对错层）、
  `SemanticJudgment`（逐点 covered/partial/missing/uncertain + 回答内精确 char span +
  双侧快照哈希 + abstain 一等）、`JudgmentAdjudication`（确认/纠正，不回写 judgment）；
  validator 落实矩阵裁决（隐藏原句、L1 触发原因、dictogloss 独占多稿、ASR 可靠性、
  span 越界/verdict-span 契约、rubric 版本一致性）与可比较性谓词。新增
  `testdata/semantic-task/gold-fixture-v1.json`（同一 rubric 好/差/abstain 三判定 +
  一次 adjudication）。domain 70 项、workspace 25 套件全部通过；semantic_task 无
  clippy warning。无网络、无模型即可完整验证。

- 2026-07-12 17:25 CST: Phase 3.11 Slice 0 完成并通过 owner 复核门。`3.11-PLAN.md` 按
  上游现状修订为 v2（固定 v34/ADR 0021 基线、五切片可执行粒度、Dart DTO 推迟到 3.13）；
  新增 `3.11-EVIDENCE-MATRIX.md`：七类语义任务 + 五条负向裁决的 evidence matrix（真实
  CNN10 片段示例、Lee 1986 / Wajnryb 1990 文献核实）、typed contract spike 裁决为方案 C
  （新封闭枚举 `SemanticTaskKind` + 独立 attempt 表族，复用 PracticeTarget/Anchor，
  `PracticeKind` 不动、不改开放 string）；确立"3.11 不新增任何 LearningObservation
  writer"。执行分支 `codex/3.11-semantic-task-evidence-foundation`。

- 2026-07-12  CST: Phase 3.10 Coach Dashboard 收口。owner 产品 QA 通过所有 QA-A ~ QA-E
  项目：入口语义、数字来源事实可下钻、建议可执行无副作用、材料轨迹与毕业确认正确、历史不足
  降级干净。创建 `3.10-CLOSEOUT.md`，更新 `STATE.md` 将主线切换至 Phase 3.11。

- 2026-07-12 15:05 CST: Phase 3.10 自动化与代码范围完成，转 owner 产品 QA。Dashboard 新增
  指标来源明细 API/弹窗（实际 session/attempt/event/history ID、结果与时间）、同一材料多次
  `ListeningCompleted` 理解度轨迹、基于重复自报与练习正确率的毕业候选、确认式
  `graduated` triage intent，以及“不清楚→转精听 / 听懂大意→保留泛听”的确认式 content-fit
  建议；所有动作只整理内容库，不静默修改能力。新增 10,000 事件有界性能测试与材料轨迹/
  毕业回归，建立 `3.10-MANUAL-QA.md`，PASS 前阶段不收口。最终验证中 Flutter analyze、
  Flutter 284 项与 contracts 通过；Phase 3.10 focused Rust 测试全部通过。workspace 全量仍被
  两项既有基线阻断：Clippy 的 `sense_group_partition.rs` deny 级恒真布尔表达式，以及
  Phase 3.8 shadowing event 测试期望 `not_scored`、实际 payload 为 null；均与 Dashboard 改动无关。

- 2026-07-12 14:44 CST: Phase 3.10 Coach Dashboard 首条完整竖切片落地。新增只读
  `CoachDashboardRepository` 与 SQLite 周期聚合、`GET /v1/coach/dashboard` channel-ready
  envelope、可追溯规则建议和无历史 starter checklist；reading/speaking/writing 缺少主动
  验证时明确返回 unassessed。Flutter 新增 typed DTO、Store/controller、双语 Dashboard 页面
  和工作台入口，展示泛听、练习、复习、listening capability history 与 L1 规则命中事实，
  并可直达复习、猎词或返回真实输入。新增 application、SQLite、HTTP、transport/controller
  回归与 OpenAPI 契约。Flutter 284 项、analyze、contracts 通过；workspace test 首轮仅因新增
  路由尚未写入 OpenAPI 而失败，契约已补齐待复跑；strict clippy 仍被既有
  `construction.rs` Rust 1.94 `collapsible_if` 阻断。

- 2026-07-12 11:52 CST: Owner 将 Phase 3.9 L1-aware Diagnosis v1 明确延期，暂不收口、
  不创建 CLOSEOUT，亦不把当前真实媒体 QA 记为通过。已合入的实现与自动化验证保留；延期原因
  是当前 UX 依赖词汇状态/历史 observation、基础诊断和 RhythmFrame 规则命中的多重前置，尚未
  形成“本句没听懂 → 定位 → 回听 → 同类短练习”的自然学习闭环，且规则时间段可能来自 text
  prior / 估算 timing。主线切换至 Phase 3.10 Coach Dashboard；3.9 数据不作为其硬依赖。

- 2026-07-12 09:07 CST: Owner 明确确认 Phase 3.8 Shadowing & Recording Comparison
  真实媒体、真实麦克风及跨媒体入口 QA 全部通过。`3.8-MANUAL-QA.md` 记录首轮发现的
  跨媒体主字幕导航泄漏、修复与复验 PASS；新增 `3.8-CLOSEOUT.md`，计划状态转为 COMPLETE，
  `STATE.md` 当前第一优先切换至 Phase 3.9。Phase 3.8 冻结后仍保持非评分 completion、
  录音资产 outlive media 与客观比较不作发音评价的边界。

- 2026-07-12 09:02 CST: 修复 Phase 3.8 跨媒体 shadowing 播放器 UX 泄漏。从复习卡或词典
  内联片段进入“跟一下”时，练习窗现在固定为当前来源片段，隐藏主字幕上一句/下一句与句数
  进度；播放/暂停按钮和空格键改为控制独立切片播放器，导航函数同时拒绝跨媒体调用，避免
  任何快捷键误播主播放器。新增 widget 回归测试；`flutter analyze` 与相关测试通过。

- 2026-07-12 08:33 CST: Phase 3.8 Shadowing & Recording Comparison 自动化实现完成并进入
  owner 真实媒体 QA。macOS 端新增 `AVAudioRecorder` 权限与 mono PCM16 WAV 采集，Flutter
  练习浮窗点亮“跟一下”第四题型，支持 chunk → 1+2 → 整句、0.75/0.9/1.0x、跨媒体入口、
  原音/录音/A-B-A 独占播放、双波形及客观时长/停顿比较；媒体/比较失败保留录音和 snapshot，
  权限拒绝可引导系统设置。新增 Rust DSP、HTTP/OpenAPI/Flutter typed seam 与回归测试；
  `cargo test --workspace`、Flutter 278 项、`flutter analyze`、契约校验、包含 sidecar/runtime 的
  macOS Release 打包及
  `git diff --check` 通过。严格 clippy 仅被既有 `construction.rs` `collapsible_if` 阻断。
  同时修复正式打包二次签名丢失 Runner entitlements，产物现保留麦克风输入权限键。新增
  `3.8-MANUAL-QA.md`，Phase 保持 ACTIVE，等待 owner 裁决后再收口。

- 2026-07-11 20:36 CST: Phase 3.8 首条后端竖切片落地。新增 schema v33
  `recording_assets`、SQLite `RecordingRepository` 与 recording create/get/delete API；
  `RecordingAsset` 保存语言、容器/codec、采样率、声道、sample format、byte length、SHA-256、
  recorder version 和来源片段 snapshot，为 3.14 录音转录保留诚实输入。新增
  `PracticeResult::Completed` 与 shadowing completion API，非评分录音完成明确不写 speaking
  observation、不生成 review、不计入 content-fit，并以 persistence/HTTP/contract 回归锁定。

- 2026-07-12 10:40 CST: Phase 3.9 L1-aware Diagnosis v1 全量落地（Mandarin → English）。
  （1）LearnerProfile L1 持久化：schema v34 `learner_profiles`（v33 按 later-lander-renumbers
  规则保留给 3.8 in-flight 的 `recording_assets`），实现既有 `LearnerProfileRepository` trait、
  统一读取面 `LearnerProfileView`（L1 权威 / UI 语言快照 / L2 保留位，三轴分离）、
  GET/PUT `/v1/learner/profile`，设置对话框“学习”类新增母语（L1）下拉，未设置时全链路无感。
  （2）L1L2 难点 profile provider：diagnosis-core 新增 `l1l2_difficulty_rules`（zh→en 九类难点，
  weak function words / schwa / final consonants / clusters / t-d deletion / flapping / linking /
  stress-timed rhythm / compressed forms），每类含 family 识别规则（rhythm_frames weak
  groups/compression spans + 2.16 connected-speech 六 family，evidence class 一律
  heuristic_proxy）与 possibilities 语气解释；无检测器的两类（final consonants/clusters）
  声明空 family 永不虚假触发；研究依据逐条记录于 `3.9-L1-PROFILE-EVIDENCE.md`。
  （3）诊断集成：`SentenceDiagnosis` 附加 `l1_hints`（带可复听 span，无 span 不出提示）与
  `l1_context`（unsupported_pair 显示语言中立提示），降级阶梯为无 L1→字节不变基础诊断、
  组合不支持→仅 context、无 sound-side 失败/无 rhythm frame→仅 context；命中写幂等
  `l1_difficulty_hit` LearningEvent（(sentence, kind) 指纹去重，供 3.10 难点分布）。
  （4）corpus family 标注投影：reindex 在 v28 投影上追加 kind=connected_speech、
  normalized_key=family 的可重建行（word timeline 生命周期、转写管线、lltimeline 导入均补齐
  reindex 触发点）；`/v1/learner/l1-specialty` 按难点聚合全库同类片段（跨媒体 round-robin），
  corpus 缺席降级为当前 track 内存聚合（indexed=false）；Flutter 诊断卡新增母语听觉视角区
  （复听 chip 走循环播放、同类片段对话框：试听走 3.5.7 切片窗、当前 track 条目可一键进
  3.5.6 句听写练习）。验证：cargo test --workspace 全绿（含新增 diagnosis-core 8 项、
  persistence L1 链路 6 项）、flutter analyze 0 issue、flutter test 278 项、
  validate-contracts（OpenAPI/event/player）通过；clippy 仅存量告警。

- 2026-07-11 20:07 CST: Owner 明确确认 Phase 3.7 Hunting List 真实媒体功能验收通过。
  `3.7-MANUAL-QA.md` 记录 PASS，新增 `3.7-CLOSEOUT.md`，计划状态转为 COMPLETE 并冻结；
  `STATE.md` 当前第一优先切换至 Phase 3.8。此次收口不改变 Gate Q 中 Q3（复习）与 Q4
  （content-fit）主动延期的 QA 债归属。

- 2026-07-11 19:50 CST: Phase 3.7 Slice 5a completion 统计落地。泛听理解度自报对话在狩猎
  模式启用时显示“命中 N 次 / 听出 M 次”；typed completion request 新增可选 hunting summary，
  application 校验总提示 ≤5 且回答数不超过提示数，并把 prompted/recognized/not-recognized/
  not-noticed 四类计数写入 `listening_completed` event payload，不进入 content-fit。新增 Rust
  持久化与 Flutter HTTP seam 回归，Rust API/SQLite 145 项、Flutter 274 项、analyze、OpenAPI/
  event/player contract 与 diff check 均通过。真实媒体连续感 QA 由 owner 按新增
  `3.7-MANUAL-QA.md` 执行，Phase 保持 ACTIVE，未提前收口。

- 2026-07-11 15:31 CST: Phase 3.7 Slice 3/4 落地。后端新增当前 media/track 的猎词目标出现点
  查询：word 复用 lemma-normalized corpus key，phrase 复用 FTS 句子匹配，所有提示要求稳定
  sentence 关联，并以 `indexed=false` 区分未建索引与零命中。Flutter 新增会话级
  `HuntingSessionController`，从真实播放器 position stream 驱动显式狩猎开关、前置 priming、
  句后 check、总预算 5/每目标 2；不自动暂停或重播，切媒体/结束泛听即清零。三态作答中
  “是/否”走 ADR 0017/0019 observation/evidence 链路，“没注意”只写
  `hunting_check_answered` LearningEvent。新增 reindex 提示、播放菜单/浮层 UI、中英本地化及
  Rust HTTP/application/persistence、Flutter controller/widget/contract 回归；Rust 相关全量、
  Flutter 274 项、OpenAPI/event/player contract 均通过。

- 2026-07-11 15:03 CST: Phase 3.7 Slice 2 Flutter 猎词单管理 UI 落地。新增
  `HuntingController + Store<HuntingState>` 与 typed target/candidate API seam；听力词典工具栏
  增加带 active 数量徽标的猎词单入口，词条详情可手动加入，管理面板支持查看/归档目标、
  确认复习失败候选并跳回词条。补齐中英本地化、controller/widget/contract 测试；
  `flutter analyze`、新增 6 项聚焦测试与 Flutter 全量 271 项测试通过。

- 2026-07-11 14:51 CST: Phase 3.7 首个后端竖切片落地：新增 schema v32
  `hunting_targets`，将复习失败候选与用户确认的猎词目标分离；支持 manual、review candidate
  与 Listening Inbox 来源校验，实施最多 5 个 active 目标的硬上限、归档/重启用身份，并新增
  候选读取及目标创建/列表/归档 API、OpenAPI/TypeScript contract 与 Rust 回归测试。确认
  review candidate 后将候选转为 `consumed`，不自动扩容猎词单；同时修复契约校验脚本仍只
  接受词汇资产 v5、与当前 OpenAPI v5/v6/v7 权威范围漂移的问题。

- 2026-07-11 14:44 CST: Gate Q owner 裁决落地：Q1（3.3 泛听）与 Q2（3.35 工作台）明确
  通过；Q3（3.4 复习）与 Q4（3.5 内容分档）因后续仍需调整 UX/功能而明确延期，残余 QA
  债保留在原 phase，不转嫁给 3.7。Gate Q 据此通过，Phase 3.7 Hunting List 转为 ACTIVE。

- 2026-07-11 12:56 CST: 四通道规划落地后的评审修订。3.12 判定为超载 phase：judge 资格
  评估（fixture + 人工 gold + 留出集 + 三级资格裁决）拆出为新 Phase 3.12.1（新建
  `3.12.1-PLAN.md`），3.12 修订 v2 收窄为两个异构协议 adapter（OpenAI-compatible +
  Anthropic Messages）先证厂商中立、OpenAI Responses/Gemini native 降为增量 slice。
  统一 judge 三级资格口径（未经留出集校验不进学习 surface / 仅可显示可纠正 feedback /
  supporting evidence），修复共享上下文 §3.5 与 final 稿 §9 的矛盾。共享上下文新增
  §3.6 seam 预留裁决标准（解释 3.7 拒绝 FocusTarget 与 3.10 接受 channel-ready
  envelope 的一致依据）、§3.7 过渡期证据权威与计划保鲜纪律（3.11–3.18 为方向承诺，
  开工前须按现状修订）。final 讨论稿补修订记录（FINAL 稿改动今后走修订记录）。同步
  PHASE-BREAKDOWN（序列表/依赖图/执行顺序/全局规则 13）、ROADMAP、REQUIREMENTS
  （LOOP-013/014）、3.10/3.13/3.14/3.17 计划引用。STATE.md 已完成 3.x phase 条目
  压缩入索引表（396 → 307 行，恢复 ≤400 余量）。

- 2026-07-11 12:15 CST: 对照四通道最终讨论与现有 3.7–3.10 计划完成路线重排。四份计划
  升级 v3：3.7 保持 listening-only 且新增 3.3/3.35/3.4/3.5 真实 QA Gate Q；3.8 明确为
  shadowing 模仿层，非评分 completion 不得用 `Correct` 伪造 speaking success，并为后续
  录音转录保留诚实 seam；3.9 不提前接 LLM/两层复述；3.10 建 channel-ready envelope，
  无数据通道显示未评估而非 0。新建 3.11–3.18 八个 PLAN 与共享上下文，依次覆盖 semantic
  task/evidence、厂商中立 LLM provider 与 judge 校验、Reading/Speaking/Writing Studio、
  Personal Expression、四通道 projection/review、Cross-modal Coach closeout。同步 Phase
  Breakdown、PROJECT、REQUIREMENTS、ROADMAP、STATE 与最终讨论稿；未修改任何已冻结 phase。

- 2026-07-11 12:04 CST: 四通道产品方向形成最终讨论版，并将长期定位从“听力理解播放器”
  更新为“以真实内容为共同语境、听力先行的四通道语言学习工作台”；当前 Phase 3.7–3.10
  听力执行顺序不变，后续逐个验证 Reading/Speaking/Writing Studio。最终稿收敛两层复述、
  clip-level attempt 与 lexical capability 的粒度边界、SemanticRubric/SemanticJudgment、
  用户 adjudication 与 capability override 分离、LLM judge 校验门禁。新增厂商中立 LLM
  provider 裁决：领域 trait 不依赖单一 wire format，初始协议适配覆盖 OpenAI Responses /
  Chat Completions-compatible、Anthropic Messages、Gemini native API 与本地兼容服务；同步
  PROJECT、REQUIREMENTS、ROADMAP 与 STATE，不修改冻结 phase 文档。

- 2026-07-11 11:55 CST: 新增四技能扩展讨论稿的评审结论文档
  （`.planning/discuss/four-skills-expansion-review-and-llm-boundary.zh.md`）：
  记录对原稿的批判性评审（P0 隐藏语义评判依赖、范围过大、缺前置 spike、引用待核实）；
  owner 裁决正面引入 LLM API 作为语义能力 provider，并定五条架构边界（application 层
  provider trait + ADR、判定为 heuristic_proxy 级证据带模型/prompt 快照、用户可 override、
  结构化断言不给综合分、spike 校验后才获写证据资格）；确立"说"通道两层复述设计
  （L1 意义复述 → L2 表达复述）及其证据归属（第一层写 listening 不写 speaking、
  第一层为诊断工具非固定前置）。本文不改变现有 phase 排期与冻结边界。

- 2026-07-11 11:25 CST: 新增四通道产品讨论稿，调研 Phase 3.7–3.10 听力主线之外的
  speaking / reading / writing 功能；提出片段复述、角色接话、媒体伴生阅读、读听差异诊断、
  dictogloss 重构、个人表达模板与分层写作反馈，并给出四通道 evidence matrix、优先级及
  对 3.7–3.10 的演进建议。本文仅作后续产品输入，不改变现有 phase 排期与冻结边界。

- 2026-07-11 09:58 CST: 3.7–3.10 计划修订为 v2（四份 v1 计划写于 3.4.1/3.5.x/3.6 落地前）。
  共性：状态语言换四通道 capability 口径、证据链路对齐 ADR 0017/0019、播放对齐 3.5.7
  双实例架构。个性：3.7 目标定位优先复用 corpus 投影（lemma 归一）+"没注意"不写观察
  证据 + 狩猎小结挂 extensive-only completion + 标注 3.3 未收口前置；3.8 入口宿主改为
  3.5.6 练习浮窗第四题型 + shadowing 锁定韵律层 chunk（ADR 0016）+ attempt 排除出
  content-fit 折算；3.9 corpus connected-speech family 检索明确为新增可重建投影工程量 +
  LearnerProfile 收窄为补 L1；3.10 删除悬案区回访/卡点解决率（3.5.6 已撤机制）+ 精听不
  虚构 session 时长 + durable 事实清单对齐 v19–v31 schema + 建议引擎补猎词单联动。
  STATE.md 同步记录决策。

- 2026-07-11 09:32 CST: 3.6.1 收口后审计修复。SQLite schema v31 为
  `lexical_sense_folder_occurrences` 补 `BEFORE UPDATE` 父词条一致性触发器（0030 只防
  INSERT，assign 的 upsert UPDATE 路径此前仅靠应用层 SQL 守卫）；词典资产导入的义项边
  改为显式词条一致性谓词——原实现依赖触发器 `RAISE(ABORT)` 兜底，而 `OR IGNORE` 不降级
  ABORT，脏边会令整个导入失败而非按注释所称被跳过（已用 sqlite 实验证实）。新增测试：
  切片跨文件夹移动语义、UPDATE 触发器拒绝跨词条改写、脏边导入被跳过、v30→v31 迁移。
  顺手清理 lexical.rs 既有 needless_borrow clippy 警告。验证：persistence 83 +
  application 50 + api-http 35/12 全绿，clippy persistence-sqlite 零警告。

- 2026-07-11 08:48 CST: 重排底部 compact 迷你播放器为三段式布局：媒体信息改为圆形媒体标识、
  标题与时间双行展示，上一句/播放暂停/下一句居中且强化主播放按钮，倍速、静音和工作台展开
  收至右侧；进度条贴合播放器顶边，并为窄窗口保留自适应收缩。新增 compact widget 布局回归测试。

- 2026-07-11 08:37 CST: Phase 3.6.2 Dictionary Inline Clip UX 收口。词典详情移除根层
  `SlicePlaybackWindow` overlay，保留同一第二解码核心并改为默认视频的内嵌切片卡；未归类
  重复竖向卡片改为 PageView 横向轨道，支持触控/鼠标滑动、左右箭头/左右键切片与空格播放暂停。
  迁移 3 个旧竖向卡片测试并新增无 `Positioned` 内嵌 renderer 覆盖；Flutter 定向测试 24 passed。

- 2026-07-10 23:30 CST: 启动 Phase 3.6.2 Dictionary Inline Clip UX。owner 反馈 3.6 词典页
  错把 3.5.7 的浮窗 renderer 复用为根层 overlay；本阶段将保留第二解码核心，改为词条详情内嵌
  当前切片卡与水平切片浏览轨道，不改冻结的 3.6 / 3.6.1 文档或后端契约。

- 2026-07-10 23:25 CST: Phase 3.6.1 Sense Folders 收口。Owner 已接受真实媒体桌面 QA；
  CLOSEOUT、STATE 与冻结计划已同步。下一步建议为独立的 SceneLex 消费契约 spike，只定义
  已发布外部义项/资源的版本与发布状态，以及与本地文件夹 `external_ref` 的对齐，不实现
  下载、生成或自动消歧。

- 2026-07-10 23:25 CST: 开始 Phase 3.6.1 Sense Folders。新增本地义项文件夹的领域模型、
  schema v30、词典详情 API 与桌面端手动归类界面：文件夹是用户身份权威，外部 semantic
  reference 仅为可选不透明对齐字段；切片归类不写入学习证据、不改变词条级四通道画像，
  未归类切片仍完整显示。词典资产导出升级至 v7 并保留 v5/v6 导入。SceneLex/API/自动消歧
  均未接入。自动验证：Rust application 50、persistence 81、api-http 35 + HTTP integration 12
  全绿；Flutter analyze 与 widget test 全绿。真实桌面 owner QA 待执行。

- 2026-07-10 21:05 CST: Phase 3.6 债务清偿并收口。SQLite schema v29 新增
  `corpus_occurrences_fts` FTS5 伴生索引（rowid 镜像、触发器维护、迁移回填），多词 corpus
  查询从 `LIKE '%…%'` 全表扫描升级为分词短语匹配；`delete_track` 在 FK cascade 前显式清理
  FTS 行，连贯性不依赖 cascade 触发器。词 token 索引键与自由文本单词查询双向经
  `normalize_lexical_form`（用户纠正 → provider lemma → 基线）归一——"run" 能找到
  "running" 的语境；v29 前的存量索引需手动"重建媒体库语料索引"一次以获得 lemma 匹配。
  新增 lemma 归一与删轨连贯性测试；同步 DATA-MODEL（v28/v29 投影记录）与 OpenAPI 搜索
  语义描述。验证：Rust 三 crate 全绿（persistence 79 passed）、`validate-contracts.sh`
  通过、clippy 零新增警告、`git diff --check` 通过。真实媒体手工 QA 按 owner 决定豁免，
  `3.6-CLOSEOUT.md` 已写，phase 冻结；STATE 与 3.6-PLAN Progress 同步。

- 2026-07-10 20:19 CST: Phase 3.6 收口批次二（除真实媒体 QA 外全部剩余项）。后端：corpus
  搜索改为按 media 轮转采样（窗口函数交错排序），大词条截断页跨来源多样化，补采样测试。
  Flutter 词典详情：切片 wpm 估算标注与"默认顺序/按语速"排序（UI 状态改按 occurrence 身份
  键控，排序不串已揭示/已标记状态）；每切片"加入复习"出口（ReviewItem 带 sentence anchor
  时间窗，复习队列按 3.4 卡型派生；范围裁决：不内嵌 3.1 practice 会话 UI，词典动作出口收敛
  到复习队列）；回补词典化时移除的四通道 override 就地编辑、释义/笔记编辑与升级建议确认/
  拒绝 banner；外链兜底（零切片/零结果态 YouGlish 外链 + 词典发音按钮，明示仅供参考不作
  练习素材）；命中 limit 显示"已跨媒体采样"提示。新增语速估算单测与 5 个 widget 测试。
  验证：`cargo test -p persistence-sqlite`、`flutter analyze` 零问题、`flutter test`
  265 passed、`git diff --check` 通过。已知债挂账：phrase LIKE 全扫（FTS5 备选）、自由文本
  lemma 归一。

- 2026-07-10 19:58 CST: Phase 3.6 Slice 3 收尾接线 + Slice 1 体验修正。后端：corpus 索引纳入
  active chunk timeline 的 chunk 行（含空格查询同时命中句子与 chunk），chunk timeline
  activate/archive/delete 与激活式生成触发该轨重建；新增 `rebuild_corpus_index` 全库回填
  use case 与 `POST /v1/corpus/reindex` 契约（存量媒体库的主动重建入口）。Flutter：词典页
  从弹窗改为 master-detail 页内详情并自持第二解码切片窗——播放例句不再退出词典、不触碰主
  播放器（入路由时暂停）；深链改为按 entry id 直取详情；词条详情新增"在我的媒体库中搜索"
  （corpus 命中经切片窗试听、一键收为该词条来源切片，去重已保存句子）；词汇本零结果时降级
  为 corpus 纯查询；词典页工具栏新增重建索引入口；"加入复习"回补到词典详情；新增
  `CorpusOccurrence` 手写 DTO + fixture 契约测试与 library-section widget 测试。
  回归修复（3.5/3.5.6 接缝）：精听 session 在 extensive-only completion 后永不完成，练习
  准确率校准失去触发点——改为 attempt 提交时增量折算（`record_practice_accuracy_feedback`），
  completion 仅折算理解度自报。验证：`cargo test -p application -p persistence-sqlite
  -p api-http` 全绿、`validate-contracts.sh` 通过、`flutter analyze` 零问题、`flutter test`
  259 passed、`git diff --check` 通过。

- 2026-07-10 16:26 CST: Phase 3.6 Slice 3 后端索引基础。新增 SQLite schema v28 的
  `corpus_occurrences` 可重建本地投影、`CorpusIndexRepository` 实现与
  `GET /v1/corpus/search` OpenAPI 契约；字幕导入和轨道语言修改会替换该轨道的索引。首批
  索引精确 lexical token 与句级 phrase occurrence：单词精确命中不与句级行重复，含空格短语
  查询只返回句级上下文。chunk / connected-speech index 与 Flutter 搜索/收例句交互仍在 Slice 3
  后续接线范围内。

- 2026-07-10 16:10 CST: Phase 3.6 Slice 2 接线。词典每个带稳定 sentence ID 的来源切片在
  “先听 → 显示文本”后可单键标记“这次听出/没听出”；复用既有 lexical-observation API，
  因而保持 sentence-level diagnosis 兼容记录，并自动追加 ADR 0017 的 listening
  context-marking evidence、既有识别证据/建议与 projection 链路。旧切片若无稳定句子链接，
  明确仅可试听、不伪造证据。

- 2026-07-10 15:56 CST: 启动 Phase 3.6 Listening Dictionary MVP 第一刀（Flutter-only，零新
  后端表/字段/契约）：词汇本详情演进为“学习对象 → 来源切片”的听力词典视图，显示四通道
  画像与诚实的本地切片覆盖度；每条切片默认隐藏句子文本、可手动揭示目标词高亮，并复用
  3.5.7 独立切片播放器（含未关联来源的既有指纹恢复路径）。词汇学习面板与诊断 lexical
  barrier 可直达指定词条；新增中英文文案和 widget tests。corpus index/搜索、逐例听出标记、
  义项文件夹与复习/练习出口仍按 3.6 后续 slices 推进。

- 2026-07-10 15:46 CST: Phase 3.5.7 Slice Playback Window 收口。Flutter-only：以独立
  fvp/video_player 第二实例取代词汇来源句的主播放器劫持；新增可注入
  `OccurrenceMediaResolver`（关联媒体/文件定位/指纹验证/注册）、默认音频优先且可展开视频的
  `SlicePlaybackWindow`、音频焦点互斥与中英文文案。所有 A 组来源句入口迁移，删除
  `playOccurrence`/`loopOccurrence`；B 组当前媒体 `loopRange` 未迁移。真实 macOS 双实例
  spike 通过，`flutter analyze`、`flutter test`（252 passed）与 `git diff --check` 通过；owner
  确认收口，冻结 phase，3.6 复用该播放端承接多切片卡片浏览。

- 2026-07-10 15:20 CST: Phase 3.5.6 Intensive Practice Floating Window 收口。新增
  `3.5.6-CLOSEOUT.md`，将执行 PLAN 标为完成并冻结；STATE 从 owner 声明收尾更新为正式收口。
  真实媒体手工 QA 按 owner 决定豁免；此 phase 不闭合 milestone，`MILESTONES.md` 不变。

- 2026-07-10 14:58 CST: 规划：切片播放器与听力词典 v2（纯文档，无代码）。基于
  `.planning/discuss/personal-listening-dictionary-and-slice-player.zh.md` 的评审结论（新增 §9，
  状态改 REVIEWED）：新增 Phase 3.5.7 Slice Playback Window 计划（独立第二解码实例浮窗取代
  `playOccurrence` 主播放器劫持，Slice 0 为双实例可行性 spike，B 组 loopRange 不迁移）；
  3.6 听力词典 PLAN 修订为 v2（第一刀零新后端"学习对象 → 切片"资产词典页，corpus index/搜索
  降为第二刀，义项为 3.6.x 独立 phase 且 sense spike 从"3.6 前"改排到义项切片前，图谱视图
  推迟，`LexicalEntry` 不改名）。STATE 记录 3.5.6 owner 收口（CLOSEOUT 待补）、新决策与
  下一步工作。

- 2026-07-10 14:19 CST: Phase 3.5.6 清理 3.2 的失效内部聚合。物理删除 application 的卡点
  writer、`PracticeSessionSummary` read-side aggregation、`StuckPoint*` DTO/helpers 及相应
  persistence 历史测试；既有 SQLite `learning_events`、practice attempts 与 review 数据不删，
  但不再派生“悬案/本次总结”。泛听结束 use case 改名为 extensive-only
  `complete_listening_session`，不再写旧的 open/unexplained/familiar-material 字段，理解度自报与
  content-fit calibration 仍保留。同步 ARCHITECTURE / DATA-MODEL / STATE；验证 Rust
  persistence/application/api-http、Flutter 全量测试和 contracts 均通过。

- 2026-07-10 10:15 CST: Phase 3.5.6 自动化收尾补强。新增
  `intensive_practice_window_test.dart` 覆盖浮窗 mini-player 收起/恢复、相邻句导航和关闭回调；
  测试暴露并修复了 `IntensivePracticeWindow` 将 `Positioned` 包在 `LayoutBuilder` 下导致的
  `StackParentData` 运行时断言——现改为以 viewport 尺寸计算浮窗位置，使 `Positioned` 保持为
  workbench Stack 的直接子项。`flutter analyze` 与新 widget test 通过。

- 2026-07-10 10:00 CST: Phase 3.5.6 Slice 0–3 首轮落地。精听从右侧 `PracticePanel` 移至新建、
  可拖动的 `IntensivePracticeWindow`：姿态栏“测一下”直接打开，支持迷你播放控制收起/展开、
  复听、相邻句连续换题、结果 diff、retry 与加入复习队列；关闭会清理 `loopPractice` 与 transient
  practice state。移除右侧 Practice tab、精听 mark/skip/悬案/session summary/精听完毕 UI，
  `PracticeController` 不再加载 summary 或写卡点/diagnosis-viewed 事件。公开契约移除 summary/
  stuck-point/diagnosis-viewed/通用 practice complete routes 和 DTO；泛听结束收敛为
  `POST /v1/listening/sessions/{id}/complete`，应用层只允许 `extensive` session，保留理解度自报
  与 `ListeningCompleted` 写入。同步 OpenAPI、generated client、Flutter DTO/测试和契约 gate。
  定向 `flutter analyze`、Flutter practice tests、`cargo test -p application -p api-http`、
  `validate-contracts.sh` 已通过；浮窗 widget 交互与真实媒体 QA 待 Slice 4。

- 2026-07-10 09:44 CST: 启动 Phase 3.5.6 Intensive Practice Floating Window，新增
  `3.5.6-PLAN.md`，将浮窗、迷你播放器、相邻句导航、精听卡点/session 机制撤回及测试顺序
  拆成独立 slices。计划明确关键边界：`completePracticeSession` 也服务 Phase 3.3 泛听的
  comprehension report / `ListeningCompleted`，因此精听 UI 不再调用它，但不能无差别删除；
  卡点专属契约可移除，泛听结束语义须保留或迁为专名 API。同步更新 `STATE.md` 当前阶段与时间戳。

- 2026-07-10 09:27 CST: Phase 3.5.5 Intensive Listening UX Fix 收口。撰写
  `3.5.5-CLOSEOUT.md`（如实记录 delivered 8 组 + carved-out 1 组 + deferred 6 项）;9 组走查
  问题交付 8 组（回退首页、循环标注、内容匹配度入口、词汇来源竞态、听懂了吗含 C 视图第 4 项、
  溢出菜单、词汇本升级 A+B、意群/chunk 表达统一），全程守住 ADR 0016 数据双层分离。最大的
  一块独立功能"精听浮动练习小窗"（含 P0）切出到新 Phase 3.5.6（建 `3.5.6-intensive-practice-window/
  3.5.6-CONTEXT.md`，引用上游设计文档，PLAN 待独立会话撰写）。`STATE.md` 新增 3.5.5 完成条目
  与 3.5.6 下一步、更新头部时间戳与最近决策。MILESTONES 不动（3.5.5 非里程碑）。

- 2026-07-10 09:22 CST: Phase 3.4.3 Construction Modeling Spike 收口（纯 domain，未建设
  SQLite/API/Flutter/LLTimeline schema）。新增 `construction` domain seam 和可执行 en/zh/ja
  manual gold fixture：区分 `SentenceExemplar`（来源快照素材）、人工 canonical
  `Construction`（`language + key + schema_version`）、可重建的
  `ConstructionOccurrence`（token span + slots + construction-owned variant policy）及
  `UserSentencePattern`（独立用户资产、可选 system link）。fixture 覆盖时态/语态/否定/疑问、
  一句多构式/嵌套、recognition/production + read/listen/speak/write modality，以及从没有任何
  system occurrence 的任意日语句子提炼个人模板。结论：证据足以锁定边界，但不足以冻结
  canonical library、自动 provider、迁移与消费工作流，故不建生产表；下一步先验证“收藏句 →
  个人模板”产品切片。`cargo test -p domain construction --lib` 4 passed。

- 2026-07-10 09:14 CST: 字幕「分组」显示统一（Flutter-only，UX 收敛）。将原先两个
  相互独立、可叠加显示的可见性开关 `showChunkGrouping`/`showSenseGrouping` 合并为
  单一模式枚举 `groupingMode`（`off`/`prosodic`/`semantic`/`compare`，字符串持久化，
  默认 `off`）。**渲染**（`token_line.dart`）：`prosodic` 复用既有语流语块胶囊（实线
  边框）;`semantic` 用同样胶囊几何但**虚线 + 琥珀 accent 描边 + 临时标记 tooltip**，
  明确标注其为启发式「标记」而非声学证据;`compare` 以语流胶囊为底，在每一处「语义
  边界与语流边界不重合」的分歧点（token 间）叠加 `ListenColors.accent` 小箭标 + 虚线
  刻度 + 「语义与语流在此不一致」tooltip——这些分歧点即听力热点。两套数据仍各自独立
  流入 `TokenLine`（`chunkPartition` + `senseGroups`），由控件按模式择一绘制。
  **设置**：`AppSettings` 去掉两个旧 bool、新增 `groupingMode` + 加载期迁移
  （`show_sense_grouping==true`→`semantic`;否则 `show_chunk_grouping`(缺省视为 true)
  →`prosodic`;否则 `off`），保持 v8 向后兼容;新增 `chunkHighlightActive` 派生
  （仅 `prosodic`/`compare` 且开启当前分组高亮时，当前语块高亮才随播放走）。设置弹窗与
  flow 用单个 4 选项下拉替换两个开关，子控件（分组显示方式/当前分组高亮/高亮样式）改按
  `groupingMode != off` 联动。**改名/本地化**：面向用户不再暴露 Chunk/SenseGroup/意群，
  统一「分组 / Grouping」;新增 en+zh 键 `groupingMode*`、`groupingSemanticProvisional`、
  `groupingDivergenceHint`，改写 `chunkDisplayStyle`/`highlightCurrentChunk`/
  `chunkHighlightStyle` 文案为「分组」措辞。`player_stage`/`side_panel`/`transcript_panel`
  改为透传 `groupingMode` + 两套数据，转写列表与视频字幕同源同模式。
  **数据模型保持分离**（不改后端/`crates/**`、不改 SenseGroup/ChunkTimeline 领域/持久化/
  API），符合 ADR 0016：语义与语流本就会分歧，该分歧正是最有教学价值的信号。
  **本轮延后**（follow-up）：播放循环/导航仍绑定语流语块、不随模式切换;意群算法
  （NLP/置信度）不改，`semantic` 本轮刻意保持粗糙的「标记」。新增/更新测试：4 种模式
  渲染（语流胶囊、语义虚线临时标记、compare 在分歧处出标记而在重合处不出、off 平铺）
  + 6 项 `groupingMode` 迁移/派生用例。`flutter analyze` 零问题、`flutter test` 247 passed。
- 2026-07-09 23:43 CST: Phase 3.5.5 词汇本升级 Slice 2-4 完成（能力过滤为主 + 四通道
  摘要 + 纳入 Phrase）。**Slice 2 后端 API**：application `list_vocabulary` 暴露
  `kind`/`status`/`capability_filter`（去掉 `Some(Word)` 硬编码，`kind=None` 返回词+短语）;
  路由 `VocabularyQuery` status 改可选、新增 `kind`/`capability`/`assessment`（后两者同时
  present 才构成 `CapabilityFilter`）;OpenAPI 加性更新（status 去 required + 4 个新 param）;
  2 处测试调用适配。**Slice 3 Flutter 数据**：`api_service.listVocabulary` 改命名可选参数
  （status 可选 + capability/assessment/kind），2 处调用方（`savedVocabularyCount` 等）适配。
  **Slice 4 词汇本 UI**：`VocabularyBookView` 列表项渲染四通道能力摘要（复用
  `effectiveAssessment`，acquired=绿/not_acquired=琥珀/unassessed=灰，带 tooltip）+ word/phrase
  徽标 + 来源快照;`VocabularyScreen` 过滤器从旧三态换为能力维度选择（reading/listening/
  speaking/writing）+ 状态过滤（全部/已掌握/未掌握/未评估），legacy status 后端保留;详情弹窗
  查词典/发音对 Phrase 做 null 容错。共享配色 helper `capabilityAssessmentColor` 统一列表与
  过滤器。新增 l10n 键 vocabFilterAll/vocabFilterCapabilityHint;新增 widget 测试验证四通道
  图标 + phrase 徽标渲染。契约工件 `local-api-v1.ts` 同步更新。`flutter analyze` 零问题、
  `flutter test` 236 passed、`cargo test -p persistence-sqlite/-p api-http` 全绿、
  `validate-contracts.sh` 通过。留待独立 phase：问题 3（统一学习对象抽象、句子/构式/搭配
  作为资产）、旧状态 ChoiceChips 移除。

- 2026-07-09 23:05 CST: Phase 3.5.5 词汇本升级 Slice 1（后端能力过滤持久化，A+B 计划）。
  `LearningAssetRepository::list_lexical_entries` 新增 `Option<CapabilityFilter>` 参数
  （domain 新增 `CapabilityFilter{capability, assessment}`）。SQLite impl 分两分支：无过滤
  走原查询;有过滤时 `LEFT JOIN lexical_capability_states`(sense_id='' 条目级)并按有效结论
  过滤——`COALESCE(json_extract(override_json,'$.conclusion'), json_extract(projection_json,
  '$.conclusion'))`,`unassessed` 匹配无状态行(override 优先于 projection,缺失=未评估)。
  三处调用方传 `None`(application 通用 wrapper 与 vocabulary 暂不暴露,slice 2 再接);两处
  持久化测试补 `None`。新增测试 `list_lexical_entries_filters_by_effective_capability_assessment`
  验证 acquired/not_acquired/unassessed 三态过滤 + override 覆盖 projection + per-capability
  语义。`cargo test -p persistence-sqlite` 74+5+6 全绿。后续 slice：application/route/OpenAPI
  加性暴露过滤 → Flutter 数据层 → 词汇本 UI（四通道摘要 + 能力过滤器 + Phrase + ListenTheme）。

- 2026-07-09 22:38 CST: Phase 3.5.5 收尾（既有失败测试 + 溢出菜单阈值）。①修复
  `content_fit_card_test.dart > renders both dimension bands...` 的既有失败：de4bc2e7
  把 `contentFit` 文案从 'Content fit' 改成 'Difficulty'（'难度适配'）时漏更新测试，
  第 53 行仍断言旧文案 'Content fit'；改为当前 'Difficulty'（测试陈旧，非代码 bug）。
  ②底部工具栏溢出菜单阈值 `roomy` 从 1080 降到 900（方案建议 840~900）：平铺功能按钮
  （泛听/Chunk/字幕菜单）撑到 900px 才收进 `more_horiz` 溢出菜单，功能区约 800px 仍舒适。
  `flutter analyze` 零问题，全量 `flutter test` 235 passed（此前唯一的既有失败已消除）。

- 2026-07-09 22:33 CST: Phase 3.5.5 —"听懂了吗"方案第 4 项落地（C 视图按需加载 +
  移除技术分析按钮）。此前只做了文案改名，方案核心结构未动。本次：DiagnosisCard 移除
  "分析真实发音 / 分析整条字幕"两个技术按钮及 `onAnalyzePhonetics`/`onAnalyzeTrackPhonetics`
  参数（那是"作用范围"这一纯技术决策塞给用户）；改为在 C·本次音频听感参照位置
  (`player_stage.dart` mode=='actual' 且无 rhythmFrame) 原位显示加载提示
  `_SoundReferenceLoadPrompt`，提供[加载当前句][加载全部字幕]两个力度选项，语义从技术
  动作转为"看这一句 / 一次分析整轨后切句免等"。`PlayerStage` 新增 `onLoadSoundReference`
  回调，`main.dart` 接 `_analyzePhonetics`（preference=='off' 时为 null 退回旧不可用
  提示）。清理传递链：移除 `SidePanel.onAnalyzePhonetics` 参数/字段/本地包装。新增
  en/zh 键 soundReferenceNoData/loadCurrentSentence/loadWholeTrack/soundReferenceLoadHint，
  删除废弃键 analyzeRealPronunciation/analyzeSubtitleTrack。`diagnosis_card_test.dart`
  移除测两个已删按钮的用例（其余 4 用例仍绿）。`flutter analyze` 零问题，全量
  `flutter test` 除 1 个先前既有失败（`content_fit_card_test.dart` 的 golden-target
  用例，在 clean HEAD 上同样失败、与本次改动无关）外全部通过。

- 2026-07-09 22:07 CST: Phase 3.5.5 UX 修复（词汇来源记录竞态）。fc70949d 的自动来源
  记录走 `unawaited` 发 occurrence 写入后紧接着 reload/fetch details，两个 HTTP 请求
  无序，reload 可能先于写入返回，导致"刚遇到的来源句在面板上不立即出现"（需重开词汇
  才显示），且写入错误被吞。`LearningWorkflowController.openWord`（已存在词分支）与
  `setCapabilityOverride`（`not_acquired` 时）均改为 `await` occurrence 写入并 try/catch
  兜底，保证 details 重载能看到新记录、且写入失败不影响能力覆盖结果；手动"记录当前句"
  按钮原本就是 awaited，无需改。移除不再使用的 `dart:async` 导入。`flutter analyze`
  零问题，`learning_workflow_controller_test.dart` 11 passed。注：fc70949d 的"听懂了吗"
  方案仅落地文案改名，方案第 4 项（把"分析真实发音/分析整条字幕"移出 DiagnosisCard、
  改 C 视图按需加载）尚未实现，待定。

- 2026-07-09 22:00 CST: Phase 3.5.5 UX 修复（循环标注 + 内容匹配度入口）。
  **循环标注 bug**：`PlaybackActionsCoordinator.loopRange` 此前把 chip 标签硬编码为
  `'loopRange'`，调用方传入的场景描述只进了瞬时状态文本，导致收件箱/卡点/复查/
  声音线证据/音素/热点/节奏/练习等所有 range 循环在循环 chip 上全部显示同一个
  "范围循环"，提交声称的"区分场景"未生效。改为新增 `loopRange(..., {String labelKey})`
  命名参数，chip 用 `labelKey`、状态文本仍用 `label`；9 个调用点（main.dart×6、
  side_panel.dart×3）各传对应场景 key。新增 en/zh 本地化键 loopPractice/loopInbox/
  loopStuckPoint/loopRhythm/loopPhone/loopHotspot（loopEvidence 复用已有键）。
  **内容匹配度入口**：de4bc2e7 在侧栏姿态区加的 `_contentFitSummary` 只是完整
  `ContentFitCard` 的有损单行复制（仅两个 fit chip + 弹窗），而带冷启动补标注按钮、
  精听目标提示、校准状态的完整卡片仍埋在"字幕资源"技术 tab 里，空词汇画像新用户
  最需要的冷启动入口在默认转写 tab 不可达。改为在转写 tab（浏览/决策主面）直接渲染
  完整 `ContentFitCard`（透传 `onStartColdStart`），移除有损的 `_contentFitSummary`，
  不再在词汇/诊断/练习深度 tab 上重复堆叠。命名语义（内容匹配度/理解/听辨）与意群一样
  留待单独的语义重设计，本次不碰。`flutter analyze` 零问题，`flutter test
  coordinators_test.dart` 7 passed。

- 2026-07-08 18:20 CST: Phase 3.5 Slice 8 — Cold-start quick-marking flow。后端：
  `cold_start_word_candidates` 从 track transcript 抽样高频未评估词（共享
  `normalize_lexical_form` 归一化路径，按频次降序、同频字典序，clamp 50）。
  API `GET /v1/subtitles/{track_id}/cold-start-words?limit=20` + OpenAPI spec +
  `ColdStartWordCandidate` schema。端点测试验证排序、标注后候选消失。Flutter：
  `ColdStartWordCandidate` DTO + `coldStartWords` API method。
  `ColdStartMarkingSheet` 弹窗逐词三选一标注（KnownRecognized/KnownNotRecognized/
  UnknownMeaning/Skip），写入复用现有 `upsertWordLexicalEntry`，关闭后回调
  `loadContentFit` 刷新 fit 卡。`ContentFitCard` 降级态显示"快速标注"入口，
  回调经 `SubtitleResourceManagerPanel` → `SubtitleResourcesScreen` / `SidePanel` →
  `main.dart` 传递。en/zh 双份本地化（coldStart* 键）。契约测试 + widget 测试覆盖。
  `cargo test --workspace` 全绿，`flutter analyze` 零问题，`flutter test` 236 passed。

- 2026-07-08 12:35 CST: Phase 3.4.2 Slice 6 — Closeout。创建 `3.4.2-CLOSEOUT.md`（exit
  signals 逐条验证、alignment 推迟理由、ChunkTimeline 改名评估结论"继续推迟"、
  累积文件变更清单）。`3.4.2-PLAN.md` 全部 checkbox 标记完成、状态 COMPLETED。
  `STATE.md` 更新 Phase 3.4.2 完成记录。Phase 3.4.2（Semantic / Prosodic Group
  Separation）全部 7 个 Slice 交付完毕。

- 2026-07-08 12:15 CST: Phase 3.4.2 Slice 5 — Flutter 集成。Dart 模型三类（SenseGroup/
  SenseGroupAnalysis/SenseGroupAnalysisSummary，手写 fromJson/toJson，ADR 0014 纪律）。
  ApiService 6 方法（list/summaries/generate/activate/archive/delete）。SubtitleController
  + SubtitleState 新增 `senseGroupsBySentence: Map<String, List<SenseGroup>>` 缓存 +
  copyWith + 清除 + 便捷访问器。SpeechEnhancementWorkflowController 加载 active analysis
  并按 sentence_id 分桶。MediaSessionCoordinator 透传。Settings 新增 `showSenseGrouping`
  布尔（默认 off）+ 持久化 + en/zh 本地化。契约测试 7 用例
  （SenseGroup 最小/完整/round-trip、SenseGroupAnalysis 含组/active、Summary 解析）。
  flutter analyze 零问题，flutter test 233 passed。

- 2026-07-08 11:45 CST: Phase 3.4.2 Slice 4 — Application use cases + API routes + LLTimeline 集成。
  新增 `crates/application/src/sense_groups.rs`（generate/list/summarize/get/activate/archive/delete，
  generate 无 word timeline 硬依赖，纯文本 partition → SenseGroup 组装含 char-span text 切片）。
  API 7 个 handler（`timelines.rs`）+ 6 条路由注册（`lib.rs`）覆盖 GET/POST/DELETE/activate/archive。
  LLTimeline 导出填充 `sense_group_analyses` + `active_sense_group_analysis_id`，导入镜像
  chunk_timelines 保存+激活流程。`remap_lltimeline_identity` 扩展 5 处（media/track remap、
  sentence_id remap、parent_word_timeline_id remap、analysis id remap + group id remap、
  active id remap）。OpenAPI spec 新增 5 paths + 5 component schemas（SenseGroupAnalysis/
  SenseGroupAnalysisSummary/SenseGroup/SenseGroupSource/GenerateSenseGroupAnalysis）。

- 2026-07-08 11:15 CST: Phase 3.4.2 Slice 3 — SenseGroupAnalysis 持久化层落地。新增
  `migrations/0025_sense_group_analyses.sql`（`sense_group_analysis_runs` 表，4 索引含
  active 唯一约束，镜像 chunk_timeline_runs 模式），在 `migrations.rs` 注册 v25 slot。
  `repositories.rs` 三处扩展（SubtitleRepository trait / TimelineResourceRepository trait /
  blanket impl）各 7 方法（save/list/get/active/activate/archive/delete）。`subtitles.rs`
  SQLite 实现全部 7 方法，activate 自动降级先前 active 为 Candidate。测试：lifecycle
  全链路（candidate→active→archived、第二个 activate 顶替第一个）、active 唯一约束、
  JSON round-trip（多组含 label/sources 字段）、迁移恢复测试验证 v25 表存在。

- 2026-07-08 10:30 CST: Phase 3.4.2 Slice 2 — 规则回退 partition provider 落地。新增
  `crates/speech-analysis/src/sense_group_partition.rs`（`partition_sentence` 纯文本分组，
  标点+长度+短语保护规则），在 `lib.rs` 注册模块。14 个单元测试覆盖英文 ≥5 句、中文 ≥3 句、
  边界情况及不变量断言（组不重叠、连续覆盖全部 Word token、每组 ≥1 Word）。合入
  `codex/3.4.2-sense-group-separation` 获取 Slice 1 domain contract。

- 2026-07-08 08:15 CST: Phase 3.5 Slice 7 反馈回流 → 个人 sound fit 校准项。
  校准项 = 独立持久表 `content_fit_calibrations`(迁移 v27)中的反馈计数记录
  (理解度自报三档计数 + 计分练习尝试/正确计数),是学习者证据不是缓存:
  与 fit 缓存分离、在任何 fit 重算后存活;原始材料信号永不改写。写路径:
  complete practice session 尾部把本 session 的理解度自报(3.3 泛听)与计分
  练习表现(跳过不计)累加进对应媒体的校准记录(无 media 或无反馈不写;
  已结束 session 重复 complete 不重复计数;best-effort——fit 是装饰,校准存储
  不可用不能挡 session 完成)。读路径:fit 计算末尾以纯函数从计数导出修正
  (`sound_fit_calibration_outcome`,domain 单点定义,全部 heuristic_proxy:
  自报 ≥2 条按多数方向 ±1 档、平票取谨慎向 harder;练习 ≥5 次尝试正确率
  ≥0.85 → 易一档 / ≤0.5 → 难一档;双通道相加 clamp 到 ±1 档),只平移 sound
  档位并追加两个可解释校准信号(comprehension_report_unclear_ratio /
  practice_correct_rate,decisive 标记);任一通道证据足够即
  `evidence_grade → usage_calibrated`(零修正也算校准:使用验证了档位)。
  算法版本 content-fit-v1 → v2(管线加入校准输入;分档常量未动),
  fingerprint 纳入校准水位(新反馈自动失效缓存)。openapi FitSignal kind
  枚举 + Dart 本地化(en/zh)+ contract fixture 校准态测试同步;UI 无需改动
  (usage_calibrated 文案与信号渲染 Slice 4 已就位)。测试:domain 校准
  真值表 5 项(最小证据/多数与平票/正确率端点/双通道合成与 clamp/应用后
  材料信号不动 + 饱和);persistence 集成 3 项(自报两次 unclear → 难一档 +
  usage_calibrated + 换词汇强制重算后校准存活;无 media/无反馈不写;
  精听 1/6 正确 → 难一档 + decisive 信号)。验证:cargo test --workspace
  440 passed / 0 failed,flutter analyze 干净,flutter test 227 passed,
  clippy 四 crate 零新增(20 处告警全在既有文件),validate-contracts 仅
  本机既有 4 个 CJK jieba 失败。

- 2026-07-08 07:55 CST: Phase 3.5 Slice 5 三队列分拣 + 首页媒体库列表。后端:
  `GET /v1/media` 媒体库读模型(每个媒体 + primary 语言轨的缓存 fit +
  用户分拣意图 + 3.2 熟料标记;逐媒体 fit 失败静默降级为无徽标不掉行)、
  `PUT /v1/media/{media_id}/triage-intent` 持久化 pin 泛听 / pin 精听 / 暂缓
  (null 清除);迁移 v26 `media_triage_intents`(v25 槽位留给 3.4.2,
  "后落地方顺延"规则记录在迁移文件与 migrations.rs 注释);
  `MediaRepository` 增 list/意图三方法,`LearningEventRepository` 增
  `list_event_subject_ids`(熟料媒体查询);openapi 同步
  (MediaLibraryEntry/SetTriageIntentRequest)。队列本身保持派生视图
  (ADR 0018 决策 6):派生规则放客户端展示层(与 isIntensiveListeningTarget
  同先例),服务端只存意图、只供事实。Flutter:首页"开始听"下方新增媒体库列表
  (`media_library_section.dart`),按 精听靶单 / 泛听队列 / 暂缓区 / 未分级 分组,
  黄金靶置顶并挂"精听靶"徽标,行内双维 fit mini chips 复用 fit_* 档位语汇;
  派生阶梯:用户意图 > 熟料回听供给(设置可关,`familiar_material_suggestions`,
  默认开、徽标克制)> 黄金靶 → 精听 > 任一维 too_hard → 暂缓 > 其余泛听,无事实
  不建议;行点击 = 普通打开(红线:完全无视分拣行为不变),一键泛听(打开 + 起
  extensive session)/ 一键精听(打开 + 落 practice 面板)。测试:persistence 4 项
  (意图 roundtrip/列表事实/熟料回流/校验+返回)、api-http 端点 1 项(列表含 fit +
  意图存取清除)、Dart contract fixture 7 项(wire shape/容错/round-trip/队列派生
  真值表)+ widget 5 项(分组排序/意图覆盖/熟料开关迁移/回调/空态)。验证:
  cargo test --workspace 432 passed / 0 failed,flutter analyze 干净,flutter test
  226 passed,clippy 四 crate 零新增,validate-contracts 仅本机既有 4 个 CJK
  jieba 失败。

- 2026-07-08 02:00 CST: Phase 3.5 剩余工作编排(owner 决策)。Slice 8 冷启动快速标注流
  交接:新增 `3.5-SLICE8-COLDSTART-GUIDE.md`(自包含实施指南——抽样端点镜像 content_fit
  的归一化统计、标注复用现有词条路径零新写入面、fit 卡降级态挂入口、五个坑位:归一化
  同路 / 未评估≠不认识 / 零新写入面 / 不阻塞红线 / jieba 本机既有失败),由独立实现者
  执行,可与 Slice 5/7 并行。Slice 5 UI 方向确定:不做独立页面,首页"开始听"下方加
  媒体库列表(新 list-media 端点),按队列分组、黄金靶置顶。推进顺序:Slice 5 → 7
  (新 session);3.5-PLAN 与 STATE 同步。

- 2026-07-08 01:40 CST: Phase 3.5 Slice 6 listening-projection-v1(ADR 0019)。首个证据
  投影算法,确认门控的保守规则:acquired 只由升级确认事件从证据流导出(裸任务成功与
  上下文标记只作辅助,护住 3.4 "5 语境→建议→确认"管线);无辅助任务失败降档,已确认
  词有单次 lapse 保护(SRS lapse 惯例),任务成功可重固确认词并打断失败连击;
  confidence(0.85 task 级 / 0.40 弱化)与 evidence_as_of_ms 填充 3.4.x 预留 seam。
  触发:append_channelized_observation 内同步重算(限读最新 200 条)+ recency guard
  (更新的兼容/导入写入压过更旧的证据结论)。写入者阶梯:override(读时)> task 级
  证据 > 兼容/导入 > 弱化证据——兼容同步不得以 acquired 覆盖 task 级证据结论(A 方案:
  自报"认识"不能翻任务失败的盘),降档与清除始终放行(无失败棘轮);兼容同步尾部统一
  从画像重导 status 列,堵住 create/import 直写 entry.status 的绕行。升级确认对
  listening 的投影直写移除(ADR 0017 决策 4 兑现),非 listening 通道保留过渡直写。
  两个刻意的行为变化(记录于 ADR 0019 决策 4):仅标记/导入支撑的词单次听写/复习
  失败即翻为 KnownNotRecognized;任务失败后经 status 面板重标"认识"不再翻回。共享
  上下文 §14、3.5-PLAN、STATE 同步。测试:domain 规则真值表 6 项;集成 2 项(五语境
  确认后投影出处为 listening-projection-v1 + conf 0.85;任务失败翻档 + 阶梯拦截自报
  升级 + reading 通道不受影响);既有升级/复习/资产测试全数保持通过。验证:workspace
  427 passed / 0 failed,clippy 15 告警与基线持平零新增。

- 2026-07-07 22:00 CST: Phase 3.5 Slice 4 API + 当前媒体 fit 展示。后端:
  `GET /v1/subtitles/{track_id}/content-fit`(track-scoped,走 Slice 3 缓存读路径)+
  openapi path/schema(FitSignal/DifficultyDimension/ContentDifficultyProfile);
  api-http 端点测试(未标注词汇时诚实报 too_hard + assessed 0 + unassessed decisive,
  二次读命中缓存返回一致)。Flutter:手写 DTO(ADR 0014)+ contract fixture 测试 5 项
  (wire shape、黄金靶派生 meaning 易 × sound 难、诚实阈值镜像后端 0.5、round-trip、
  缺 signals 容错);`ContentFitCard` 落字幕资源面板(当前媒体摘要面):双维档位
  chips(轻松/合适/有挑战/需要辅助——预期管理文案守 guardrail)+ 黄金靶提示 +
  详情弹窗(信号→文案,decisive 标记,不见公式)+ 词汇画像不足的诚实降级提示
  (档位不隐藏只重新框定);fit 拉取挂 timeline 资源加载,失败静默清卡不阻塞;
  widget 测试 5 项。媒体库列表徽标推迟到 Slice 5(队列 UI 才有媒体列表)。验证:
  workspace 420 passed / 0 failed;flutter analyze 无 issue;flutter test 214 全过;
  api-http clippy 无新增告警。

- 2026-07-07 21:10 CST: Phase 3.5 Slice 3 persistence 难度缓存。schema v24:
  `0024_content_difficulty_profiles.sql`(每 subject 一行的可重算缓存,无 FK,
  靠 fingerprint 自失效);`DifficultyRepository` sqlite 实现(JSON 快照 + 投影查询列
  整体重写)。缓存读路径 `content_fit_for_track`:廉价指纹校验(track 指纹 + active
  word/chunk timeline 身份 + 语言级词汇水位,不做归一化不组装文档),命中返回缓存,
  失效重算并回存;指纹组装收敛为单一定义点,compute 路径共用(词汇水位从"匹配条目
  max"改为语言级 `lexical_vocabulary_watermark`(count, max_learning_updated_at)新
  仓储方法——语言内任何标记使该语言全部缓存失效,粗粒度但绝不陈旧)。AppServices 增
  `difficulty` 仓储(Disabled 默认 + `with_difficulty_repository`,api-http main 已接线)。
  **迁移编号协调**:3.5 先落地取 v24,worktree 中未动工的 3.4.2 顺延 v25(其 PLAN/
  实施指南/CHANGELOG 已在 worktree 分支同步改号,commit 271e87c1)。测试:缓存命中
  (篡改行回读证明)、词汇变更失效重算并回存、迁移恢复测试断言 content_difficulty_profiles
  表与 MIGRATION_VERSION。验证:workspace 419 passed / 0 failed,clippy 前后 15 告警
  零新增。

- 2026-07-07 20:20 CST: Phase 3.5 Slice 2 application fit 计算服务。新增
  `crates/application/src/content_fit.rs`:`compute_content_fit_for_track` 从
  `export_lltimeline_document` 单点组装输入,词义知识经 `LexicalEntry::status`
  (= `legacy_status_view` 保守折叠视图,override 已折入)读取;transcript word token
  经 `normalize_lexical_form` 归一(空归一 token 排除出分子分母)后批量查询;信号:
  unknown/unassessed/KNR 密度、语速(仅句内 speech time,排除句间静默)、弱读/压缩
  密度(rhythm frames 派生自 active word timeline,缺失则省略)、平均 chunk 长度;
  `input_fingerprint` = 算法版本 + track 指纹 + active word/chunk timeline 身份 +
  词汇水位(条目数 + max learning_updated_at)的 SHA-256(domain 新增
  `content_fit_fingerprint` 助手)。测试:语速排除句间空隙/零时长单测 2 项;sqlite
  集成 4 项(双维密度与档位、快语速升档且 rhythm 信号在场、指纹稳定性与词汇变更
  失效、语言缺失/无 word token 校验错误)。验证:workspace 418 passed / 0 failed,
  touched crates clippy 无新增告警。

- 2026-07-07 19:40 CST: Phase 3.5 Slice 1 domain 双维难度契约。新增
  `crates/domain/src/content_fit.rs`:`ContentDifficultyProfile` v2(meaning/sound 双
  `DifficultyDimension` + 结构化 `FitSignal`(kind/value/decisive)+
  `assessed_token_ratio` + `evidence_grade` + `algorithm_version`)、banding 纯函数
  (`meaning_fit` 覆盖率分档、`sound_fit` KNR 基档 + 语速/弱读单向升档饱和于 too_hard)、
  全部阈值常量单点定义(heuristic_proxy,注研究锚点);诚实降级判定
  `has_sufficient_vocabulary_profile`(MIN_ASSESSED_TOKEN_RATIO=0.5)。旧单维
  `ContentDifficultyProfile`/`InputFit` 壳从 learning_loop.rs 移除(零外部引用,原地
  重塑无兼容负担);`InputFit` 迁入新模块,glob re-export 路径不变。测试 7 项:阈值
  端点、unassessed 保守折算与 decisive 标记、KNR 基档、升档与饱和、慢速交付信号仅
  informational、缺失可选信号省略、画像充分性阈值。验证:workspace 412 passed / 0
  failed,domain clippy 零告警。ADR 0018 FitSignal 形状同步为 decisive 标记。

- 2026-07-07 19:00 CST: Phase 3.5 Difficulty & Content Triage 立项（Slice 0）。新增
  ADR 0018 双维 fit 定义：meaning/sound 双维 `ContentDifficultyProfile` v2 形状、
  信号集 v1（unknown/unassessed/known_not_recognized 密度、语速、弱读/压缩密度、
  chunk 长度）、研究锚点（听力 95% 词汇覆盖 van Zeeland & Schmitt 2013、阅读 98%
  Hu & Nation 2000、语速 Tauroza & Allison 1990 / Griffiths 1992、弱读瓶颈
  Field 2008）与映射告诫、分档规则（阈值全部 heuristic_proxy，常量单点定义，改常量
  必须升 algorithm_version）、诚实降级（assessed_token_ratio + evidence_grade）、
  三队列为派生视图、listening-projection-v1 随本 phase 落地并移除升级确认投影直写
  （ADR 0017 决策 4 到期义务）。3.5-PLAN.md 重写为 9-slice 版（句级画像裁剪出 v1，
  subject_kind 留 seam）；STATE.md 更新阻塞项与下一步；迁移编号协调：3.4.2 预留
  v24，3.5 名义 v25，后落地方顺延。

- 2026-07-07 17:30 CST: Phase 3.4.4 Learning Evidence Channelization 收口（Slice 4）。
  新增 3.4.4-CLOSEOUT.md（交付清单、outcome 入身份指纹的关键修正记录、Non-Goals 兑现、
  Exit Signals 核验）；PLAN 标 COMPLETED；共享上下文 §14 标记证据层完成；STATE.md 更新
  当前位置与下一步（3.5 可启动，首个证据投影算法随 fit 定义实现）。

- 2026-07-07 17:00 CST: Phase 3.4.4 Slice 3 写入路径接线与便携资产。四条路径全部产出
  通道化 observation：上下文标记（双写，legacy 最新覆盖行为不变但通道化流保留每次判断）、
  练习提交（成功与失败均记录，修复失败偏置；无句子锚点也可记录）、复习提交（按 rating
  映射，source 与 anchors 去重）、升级确认（ADR 0017 决策 4 过渡条款，确认本身入证据流）。
  `VocabularyAssetBundle` 追加 optional `learning_observations`（版本仍 6，旧包缺字段
  兼容），导出全量、导入按 id 幂等追加并跳过本地不存在的 entry。修复身份设计缺陷：
  outcome 纳入 id 指纹（context marking 的 source_ref 按 (entry, sentence) 恒定，同毫秒
  不同判断必须是两行）。测试：练习成功/失败通道化断言、复习失败通道化断言、标记双写
  与资产包 round-trip（3 条 observation 幂等导入）、升级确认入流断言。
  验证：`cargo test --workspace` 405 passed、0 failed；clippy 无新增警告。

- 2026-07-07 16:00 CST: Phase 3.4.4 Slice 2 持久化 schema v23。新增
  `0023_learning_observations.sql`（追加式表，entry 级联删除，
  entry+capability+occurred_at 索引）；迁移回填：未清除的 legacy LexicalObservation
  逐行转为 listening/context_marking observation（origin=legacy_backfill、
  source_ref=旧 id、surface_form=original_form），已清除的标记视为撤回不回填，
  回填幂等（INSERT OR IGNORE）。LearningAssetRepository 新增
  append_learning_observation / list_learning_observations（按通道过滤、时间倒序分页）。
  测试：v23 回填断言（含 cleared 排除与幂等）、追加语义（同 (entry, sentence) 两行共存、
  重复追加幂等）；migration_recovery_test 种子补 lexical_observations 表并断言 v23。
  验证：`cargo test -p persistence-sqlite` 67 tests 全过。

- 2026-07-07 15:35 CST: Phase 3.4.4 Slice 1 domain 契约。新增
  `crates/domain/src/learning_observation.rs`：`LearningObservation`（追加式身份 =
  entry + task + source_ref + occurred_at 指纹）、ObservationTaskType / ObservationOutcome /
  AssistanceLevel / ObservationOrigin 枚举、ADR 0017 任务→通道映射 v1 的单点定义
  （observation_spec_for_marking / _practice / _review，Skipped 不产证据）。
  5 个单元测试（身份不可覆盖、映射表、snake_case 契约与 round-trip）。

- 2026-07-07 15:20 CST: 启动 Phase 3.4.4 Learning Evidence Channelization（Slice 0）。
  新增 ADR 0017：通道化追加式 LearningObservation（capability/task_type/assistance/
  surface_form/origin，禁止 latest-wins 身份）；任务→通道映射 v1 表；投影写入者互斥
  （upgrade 确认声明为过渡直写）；legacy LexicalObservation 以 legacy_backfill 来源回填；
  资产包 additive 携带 observation。新增 3.4.4-PLAN（Slice 0-4，明确 Non-Goals：不做
  投影算法、不迁移 diagnosis、不加 API/UI）。占用 schema v23,3.4.2 迁移号协调至 v24。
  STATE.md 同步。

- 2026-07-07 13:10 CST: `CapabilityProjection` 预留分级能力 seam 字段（精化评审 §4.1）：
  `confidence: Option<f32>`（0.0..=1.0 结论强度）与 `evidence_as_of_ms: Option<u64>`
  （投影所依据证据窗口截止时间），serde default + None 不序列化，旧 JSON/DB 行/资产包
  完全兼容；真证据投影算法上线前保持 None。受 f32 影响，capability 结构链
  （CapabilityProjection/DimensionState/Profile/History、VocabularyAssetBundle、
  LexicalEntryDetails）从 Eq 降为 PartialEq。OpenAPI CapabilityProjection schema 增加
  两个 optional 属性。Flutter 不改：字段为 None 时线上 JSON 形状不变，Dart fromJson
  对未知键安全。新增 serde 兼容性测试。验证：`cargo test --workspace` 全部通过、
  `cargo clippy` 无新增警告；`./scripts/validate-contracts.sh` 的 4 个 CJK 分词失败为
  本机缺 jieba 的既有环境问题，与本变更无关（已在无改动树上复现确认）。

- 2026-07-07 12:40 CST: 修复 capability projection 来源标注失真（精化评审 §5.1）。
  `sync_capability_from_legacy_status` 增加 source 参数：外部词表导入
  （`import_external_vocabulary`）写 `Import`，legacy status 写路径的实时兼容同步写
  `LegacyLearningStatusMigration`（与 v22 一次性回填共享来源语义，以 algorithm_version
  `legacy-status-compat-v1` 区分）；`EvidenceProjection` 保留给真证据路径（升级确认）。
  新增两个来源断言测试。历史已写入的旧标签不回溯迁移。
  验证：`cargo test -p application -p persistence-sqlite` 全部通过。

- 2026-07-07 12:10 CST: Learning Domain Model v2 第二轮精化评审裁决落档。新增
  `.planning/discuss/learning-domain-model-v2-refinement-review.zh.md`（八项优化空间、
  复杂度分层原则、字段裁决标准、砍掉项与排期）；共享上下文新增不变量 16-18（listening
  acquired 条件语义、投影写入者互斥、精细度不泄漏交互层）、§5.3 evidence shape 增补
  `surface_form`、新增 §14 Refinement Addendum；STATE.md 记录决策并更新下一步
  （证据层 slice 为 3.5 前置、sense 身份 spike 为 3.6 前置）。

- 2026-07-07 21:00 CST: 迁移号第二次协调：v24（0024_content_difficulty_profiles）由
  main 上先落地的 Phase 3.5 Slice 3 占用，本阶段 sense_group_analyses 迁移顺延为
  v25/0025；PLAN 与实施指南同步改号（顺延规则不变）。

- 2026-07-07 15:00 CST: 迁移号协调：schema v23（0023_learning_observations）由 main 上的
  Phase 3.4.4 证据层占用，本阶段 Slice 3 的 sense_group_analyses 迁移改用 v24/0024；
  PLAN 与实施指南同步更新，并注明合并时编号再冲突的顺延规则。

- 2026-07-07 14:00 CST: 新增 3.4.2-IMPLEMENTATION-GUIDE.md（Slice 2-6 交接实施指南）。

- 2026-07-07 12:20 CST: ADR 0016 增补决策 9（2026-07-07 修正案）：用户意群修正是独立
  per-sentence overlay 层。

- 2026-07-07 CST: 启动 Phase 3.4.2 Semantic / Prosodic Group Separation（Slice 0-1）。

- 2026-07-06 CST: 完成 Phase 3.4.1 Slice 6 authority switch and closeout。capability profile
  成为唯一权威决策来源：diagnosis-core `classify_entry()` 移除 legacy `LearningStatus` 回退
  分支，只使用 capability profile 进行 meaning/recognition barrier 分类；upgrade suggestion
  `confirm_upgrade_suggestion()` 统一为 capability-first 路径（旧无 `capability` 字段的
  suggestion 默认走 listening projection），移除 legacy status 双写路径；external vocabulary
  import 补齐 capability profile sync（修复导入后 profile 缺失导致诊断降级为 insufficient
  的 bug）。`LearningStatus` enum 和 `LexicalEntry.status` 字段标记 deprecated，保留用于
  schema 兼容和 legacy API 消费者。Phase 3.4.1 全部 6 个 slice 完成，PLAN 标记 COMPLETED。
  验证：`cargo test --workspace` 395 passed、`flutter test` 204 passed。

- 2026-07-06 CST: 修复 persistence-sqlite 关键死锁：`lexical_details()` 持有
  `self.connection.lock()` 后调用 `self.lexical_capability_profile()` 导致 Mutex 不可重入死锁，
  改为直接调用 `read_capability_profile(&conn, ...)` 复用已持有的连接。全量 Rust 测试通过
  （395 tests，含 persistence-sqlite 64 + api-http 43）。

- 2026-07-06 CST: 完成 Phase 3.4.1 Slice 5 API, events and Flutter。OpenAPI additive capability
  profile GET/PUT contract（`/v1/lexical-entries/{id}/capability-profile` 和
  `/v1/lexical-entries/{id}/capability/{capability}`）。SSE 新增 `lexical-capability-changed` event，
  `LexicalCapabilityChangedPayload` 含 entry ID、capability 和 effective assessment。Dart 手写
  DTO：`CapabilityProjection`、`CapabilityOverride`、`CapabilityDimensionState`（effectiveAssessment
  getter：override > projection > unassessed）、`LexicalCapabilityProfile`；`LexicalEntryDetails`
  新增可选 `capabilityProfile` 字段。`LearningState` 新增 `capabilityProfiles` map，
  `LearningController.updateCapabilityProfile` 维护；`BackendEventCoordinator` 处理
  `LexicalEntryChangedEvent` 时提取 profile，`LearningWorkflowController.openWord` 加载时存储；
  新增 `setCapabilityOverride` 方法通过 API 设置/清除单通道 override。词汇面板四通道显示
  （reading/listening/speaking/writing），每通道 acquired/not_acquired ChoiceChip + unassessed 独立
  italic 表达 + override 标识；字幕 `TokenLine` 从 `capabilityProfiles` 派生 display status
  （reading not_acquired → unknown_meaning、reading acquired + listening not_acquired →
  known_not_recognized、both acquired → known_recognized）。复习结束页/词汇详情 suggestion
  按钮改用 localization keys（`confirmListeningAcquired`/`deferUpgrade`/`listeningUpgradeSuggestion`）。
  新增 `capability_profile_contract_test.dart`（6 tests）和 `backend_event_contract_test.dart` 扩展
  （2 tests）。验证：`flutter analyze` 0 issues、`flutter test` 204 passed、`cargo check --workspace`
  clean、api-events schema parity 3 passed、event contract examples regenerated。

- 2026-07-06 13:30 CST: 完成 Phase 3.4.1 Slice 4 diagnosis and review suggestion migration。
  diagnosis-core 新增 `diagnose_with_profiles()`，meaning barrier 改用 reading effective
  assessment、recognition barrier 改用 listening effective assessment + sentence observation，
  unassessed 维度严格不触发 barrier 只产生 InsufficientInformation（含 entry IDs）。旧
  `diagnose_with_phrases()` 退化为从 legacy status 创建 profiles 后委托新实现。Application
  层 `diagnose_sentence()` 批量读取 capability profiles 传给 diagnosis-core。UpgradeSuggestion
  新增可选字段 capability/previous_assessment/suggested_assessment（serde(default) additive），
  `evaluate_upgrade_suggestion()` 改为检查 listening.effective_assessment == NotAcquired，
  生成的 suggestion 标记 capability=Listening。`confirm_upgrade_suggestion()` 对 capability-aware
  suggestion 直接更新 listening projection + sync legacy，旧 suggestion 走 legacy 路径。
  新增 6 个 diagnosis-core 测试（profile 驱动 meaning/recognition barrier、unassessed
  insufficient、context observation override、both acquired → other factors）和 4 个集成测试
  （capability override 影响诊断、unassessed insufficient、capability-aware 确认更新 listening
  projection、legacy suggestion 旧路径确认）。验证：cargo test --workspace（395+ passed）、
  clippy 无新增警告。

- 2026-07-06 12:15 CST: 完成 Phase 3.4.1 Slice 3 application and portable assets。新增 application
  层 capability profile 读取、用户 per-channel override 设置/清除及双向 compatibility adapter：
  legacy status 变更同步到 capability projection（不覆盖已有 user override），capability override
  变更同步回 legacy status view。VocabularyAssetBundle 升级到 v6，携带完整 capability_profiles；
  v5 旧 bundle 导入时通过 legacy mapping 自动生成 migration projection；v6 导入按 per-dimension
  时间戳合并，imported projection 不能覆盖本地较新 user override。新增
  `LearningChangeSource::CapabilityOverrideSync`。新增 5 个测试：创建词条时 capability 同步、
  override 设置/清除影响 legacy status、v6 export/import round-trip、v5 bundle legacy mapping 导入、
  imported projection 不覆盖 local override。验证：`cargo test --workspace`（386 passed）、
  `cargo clippy --workspace --all-targets` 无新增警告、contract validation 无新增失败。

- 2026-07-06 11:14 CST: 完成 Phase 3.4.1 Slice 2 persistence foundation。SQLite schema
  v22 新增 `lexical_capability_states` 与 `lexical_capability_history`，按 entry + optional sense +
  capability 保存 system projection 和 user override；v21 legacy status 在同一迁移事务中按
  ADR 0015 回填为带 `legacy_learning_status_migration` provenance 的 projection，原
  `lexical_entries.status` 保留不删。扩展 LearningAssetRepository，支持 profile 读取、projection
  更新、override 设置/清除和 before/after history；effective 读取保持 override 优先，清除后恢复
  projection。新增 v21 精确回填、旧列保留、迁移前文件备份、重复打开、失败恢复和 repository
  round-trip 回归。验证：`cargo test -p persistence-sqlite`（44 unit + 5 migration recovery +
  6 integration passed）、`cargo clippy -p persistence-sqlite --all-targets --no-deps -- -D warnings`、
  `cargo test -p application`（48 passed）、`cargo fmt --all`、`git diff --check` 通过；跨依赖
  strict clippy 仍被既有 speech-analysis lint 阻断。

- 2026-07-06 11:07 CST: 完成 Phase 3.4.1 Slice 1 domain contract。新增 reading/listening/
  speaking/writing `LexicalCapability`、三值 `CapabilityAssessment`、不可持久化 unassessed 的
  concrete conclusion、带 provenance 的 system projection、user override 与 effective profile
  优先级；新增可选 `LexicalSenseId` seam。实现 ADR 0015 固定的 legacy status 回填和保守反向
  view，覆盖四种旧状态、productive channel 保持 unassessed、override 不删除 projection、
  无法表达组合不强制降级及 snake_case 序列化。当前切片不修改 SQLite/API/运行行为。验证：
  `cargo test -p domain`（25 passed）、`cargo clippy -p domain --all-targets -- -D warnings`、
  `cargo fmt --all`、`git diff --check` 通过。

- 2026-07-06 11:00 CST: 启动 Phase 3.4.x Learning Domain Model v2。Phase 3.4 与
  3.35 暂停最终真实媒体/owner QA，保留已完成代码与自动化结果；建立
  `baseline/learning-model-v1` 迁移基线。新增 3.4.1~3.4.3 共享上下文和分阶段 PLAN，
  锁定四通道词汇能力画像、`unassessed / not_acquired / acquired`、evidence/system
  projection/user override 分层、SenseGroup 与声音/韵律组双层模型及 Construction identity
  spike。ADR 0015 取代 ADR 0012 的单值 `LearningStatus` 长期权威决定，并固定 schema v21
  legacy 映射、v22 additive migration 与 conservative legacy view；同步更新 ROADMAP、
  REQUIREMENTS、STATE、phase breakdown、AGENT 和 codebase 架构/数据模型事实源。

- 2026-07-06 10:17 CST: Phase 3.4 升级建议引擎 v1 落地。SQLite schema v21 新增
  `recognition_evidence` 与 `upgrade_suggestions`；practice 正确、review `good/easy` 和逐例
  `RecognizedInContext` 证据按 lexical entry + sentence（无 sentence 时按 media）去重，累计
  5 个不同语境后生成 `heuristic_proxy` 建议。建议只在用户确认后执行
  `known_not_recognized -> known_recognized`，并写入 `lexical_status_history` 与
  `StatusChanged` event；拒绝保持原状态并冷却 30 天。新增 pending/history/confirm/reject API、
  OpenAPI/TypeScript/Dart 契约，复习结束页与词汇详情提供非打断式确认/拒绝入口；补齐阈值、
  状态护栏、冷却、持久化、HTTP 和 Flutter 回归测试。验证：`cargo test -p application -p
  persistence-sqlite -p api-http`、`flutter analyze`、`flutter test`（194 passed）、
  `validate-contracts`、目标文件格式检查与 `git diff --check` 通过；clippy 仅报告既有跨 crate
  warnings。

- 2026-07-05 21:59 CST: Phase 3.4 复习失败证据与猎词候选池落地。SQLite schema v20 新增
  `hunting_candidates`，按 lexical entry + review item 聚合失败次数并保留媒体、字幕轨、
  句子、目标词和 prompt snapshot；`again` 评分在词条与句子仍有效时追加
  `NotRecognizedInContext` `LexicalObservation`，来源丢失时只保留 snapshot 候选，不伪造
  observation，也不修改 `LearningStatus`。`ReviewSubmission` 返回生成的 observation/candidate
  IDs，`ReviewCompleted` 事件同步记录证据引用。为遵守单文件 1500 行护栏，将复习调度与卡型
  派生机械拆到 `practice/review.rs`。验证：`cargo test -p application -p
  persistence-sqlite -p api-http`、`flutter analyze`、`flutter test`（193 passed）、
  `validate-contracts`、`cargo clippy -p application -p persistence-sqlite -p api-http
  --all-targets`、`git diff --check` 通过；clippy 仅报告既有跨 crate warnings。

- 2026-07-05 21:51 CST: Phase 3.4 四类 audio-first 卡型差异化落地。到期队列新增
  application-owned `ReviewCard` 读模型，基于 `ReviewItem` 来源和锚点稳定派生听音识词、
  chunk cloze、phrase 出现判断、原句回听四类卡；卡型不写入 SQLite，历史复习项无需迁移。
  Flutter 队列分别提供翻词、文本填空、二选一判断和原句对照交互，完成后继续复用三档自评
  与既有调度器。同步 OpenAPI、TypeScript/Dart DTO、契约校验与架构/数据模型文档，并新增
  Rust 派生规则测试、API 断言和四类 Flutter widget 回归测试。验证：`cargo test -p
  application -p api-http`、`flutter analyze`、`flutter test`（193 passed）、
  `validate-contracts`、`git diff --check` 全部通过。

- 2026-07-05 21:33 CST: 启动 Phase 3.4 Audio-first Review Queue。新增 SQLite schema v19
  `review_schedules` 并为历史复习项回填立即到期计划；补齐到期队列与三档评分 API，评分写入
  `ReviewAttempt`、推进 heuristic_proxy 调度并追加 `ReviewCompleted` 事件。Flutter 新增
  ReviewController/Store、首页及学习工具入口、声音优先翻面卡和 snapshot 降级；复习音频仅在
  来源 media 与当前 media 匹配时播放，避免错播。词汇本详情新增手动加入复习，使队列无需
  精听/泛听前置也可独立使用。同步 OpenAPI、TypeScript/Dart DTO、架构与数据模型文档及
  Rust/Flutter 回归测试。验证：相关 Rust tests 全通过，`flutter analyze` 与 `flutter test`
  （189 passed）、`validate-contracts`、`git diff --check` 通过；strict clippy 被当前工具链新报的
  存量 `speech-analysis` / `application` lint 阻断，本阶段改动未引入对应告警。

- 2026-07-05 21:11 CST: Phase 3.35 收尾复审修复与 UX 优化。修复三处走查遗留实质问题：
  (1) 首页“继续学习”原本是死代码（媒体信息与 mediaPath 同生同灭），改为持久化最近媒体
  路径/标题/进度/字幕数到 settings，“继续播放”真正重开并按后端进度恢复位置；(2) 首页
  readiness 冷启动全为 0，改为连接后预取全局听力收件箱与词汇量（客户端聚合，capped 显示
  “N+”），字幕就绪改用最近媒体的字幕数并在无最近媒体时显示占位；(3) 播放设置弹窗倍速
  下拉改用本地状态，选后即时刷新。附带修复分栏拖动逐帧写盘（新增 `saveSoon` 防抖）与
  首页 Inbox 标签硬编码英文。UX 优化：文稿自动跟随在用户拖动/滚轮时暂停并显示“回到当前句”
  悬浮按钮（程序化滚动不触发）；窄窗口上下布局的媒体区改为可纵向拖动并支持压缩/复位；
  姿态动作栏仅在文稿/词汇/诊断/练习 tab 上下文显示，资源与收件箱 tab 隐藏；Test 姿态由
  文字胶囊改为与相邻 OutlinedButton 一致的描边下拉触发器；文稿空态补齐标题+原因+导入动作；
  无媒体播放条移除四个无意义禁用图标。新增文稿跟随暂停/恢复与首页继续播放回归测试。
  验证：`flutter analyze` 通过、`flutter test` 188 passed、`git diff --check` 通过。

- 2026-07-05 20:17 CST: 补齐 Phase 3.35 收尾材料：新增每日英语听力参考取舍矩阵、
  三种目标窗口尺寸与真实媒体手工 QA 清单，以及 `AWAITING_OWNER_QA` closeout 草稿；
  同步 PLAN 和 STATE，将当前阶段准确记录为“代码与自动化完成，等待 owner 截图/手工验收”，
  未提前标记 COMPLETED。

- 2026-07-05 20:13 CST: Phase 3.35 UX 走查 P2 收口。在线 URL 入口改为“添加来源”
  流程，输入时校验地址并识别 YouTube/普通网页，使用分段控件明确选择在线播放或下载到
  本机，同时展示访问授权提示；沿用现有 yt-dlp 解析、后台下载和下载状态条，不新增虚假的
  在线资源库或 provider。新增媒体 overlay、听觉参考、音素类别和学习状态语义色 token，
  字幕、音素与节奏组件不再直接持有产品色值。新增 URL 来源 widget 回归测试。

- 2026-07-05 20:07 CST: Phase 3.35 UX 走查 P1 收口。字幕与时间轴资源页首层改为
  学习能力和可用状态，provider、generator、precision、候选时间线及 artifact 收入技术详情；
  句子诊断移除 190px 高度限制，拆为常显摘要和可展开证据分析；词汇详情按学习状态、
  释义与发音、来源原句、折叠历史重排，并以媒体位置和本地日期替代原始毫秒值；设置页新增
  通用、字幕、学习、资源、外部工具、实验功能六类侧边导航。同步更新 P1 widget 回归测试。

- 2026-07-05 12:05 CST: Phase 3.35 UX 走查 P0 收口。新增
  `3.35-UX-REVIEW-CHECKLIST.md`，记录首页状态、顶部工具栏、播放工作台、播放条、
  右侧面板、资源/诊断/词汇/设置、在线来源和颜色 token 的 P0/P1/P2 问题清单。
  首页新增“继续学习”和资源状态摘要；顶部工具栏按内容、字幕、学习、更多分组；媒体/文稿
  分栏比例写入设置并新增压缩/复位控制；播放条把泛听、Inbox、语块和字幕样式收进模式菜单；
  右侧面板 tab 在宽度允许时显示文字，并补足词汇/诊断空态说明。验证：
  `flutter analyze`、`flutter test`（185 passed）通过。

- 2026-07-05 08:55 CST: 修复播放界面右侧文稿未稳定跟随当前句的问题。
  `TranscriptPanel` 改为按当前 cue 对应的真实列表行执行 `Scrollable.ensureVisible`，
  不再依赖旧的固定 `cue.index * 76` 行高估算；目标行尚未构建时先按列表比例预定位，
  下一帧再用真实行位置校准，适配长字幕可变行高。新增 widget 回归测试覆盖可变高度文稿
  从后段 cue 切换到前段 cue 时仍能把当前句滚入视口。验证：`flutter analyze`、
  `flutter test`（184 passed）通过。

- 2026-07-05 08:47 CST: 修复 Phase 3.35 字幕资源页与右侧资源 tab 的布局挤压。
  字幕资源列表和时间轴资源详情改为同一高度池内的可拖动上下分栏，时间轴详情移除固定
  `maxHeight: 430`，改为在分配到的区域内独立滚动；独立“字幕资源”页面和媒体工作台右侧
  tab 共享该行为，避免矮窗口下资源详情顶穿底部播放区。新增 widget 回归测试覆盖分隔线
  拖动和紧凑高度无 overflow。验证：`flutter analyze`、`flutter test`（183 passed）通过。

- 2026-07-04 23:25 CST: Phase 3.35 首轮 UI 与产品配色落地。新增来源中立首页、浅色工具栏、
  独立播放条和可拖动媒体/字幕分栏工作台；窄窗口自动上下布局，右侧导航改为等宽图标 tab，
  文稿支持可变行高，播放控制不再依赖横向拖动。新增集中式 `ListenTheme`，采用冷杉绿、
  雾灰、暖金与近黑媒体画布，并统一按钮、输入、弹窗、菜单、滑杆、选中/禁用状态；字幕
  资源、timeline、练习、诊断、人工校对、任务和下载状态已从旧深色硬编码迁移。新增主题、
  首页与工作台 widget 测试。验证：`flutter analyze`、`flutter test`（182 passed）、
  `git diff --check` 通过；等待 owner 截图反馈与真实媒体手工 QA 后继续 Phase 3.35 收口。

- 2026-07-04 22:34 CST: 新增 Phase 3.35 Listening Workbench UI Redesign 规划。
  在 Phase 3.3 与 3.4 之间插入独立 UI 重构阶段，参考每日英语听力的内容层级、同步字幕与
  播放学习一体化组织，计划统一 app shell、来源中立内容入口、播放器工作台、字幕、学习
  上下文面板、design tokens 与响应式状态；明确不做像素复刻、不复制品牌，也不在本 phase
  实现 YouTube provider。同步修正产品定位：local-first 不等于 local-only，未来 YouTube 等
  在线来源将与本地内容进入统一学习工作台，学习资产和高频路径仍默认本地。更新 PROJECT、
  REQUIREMENTS（UI-016/UI-017）、ROADMAP、STATE 与 Phase 3.0 breakdown。documentation-only。

- 2026-07-04 21:53 CST: Phase 3.3 泛听 Listening Inbox MVP 落地。
  后端新增 `ListeningInboxItem` domain model、`ListeningInboxRepository`、SQLite schema v18
  `listening_inbox_items` 表、Inbox capture/list/process API，以及
  `listening_inbox_captured` / `listening_inbox_processed` 事件；`completePracticeSession`
  支持可选理解度自报，session 创建写入 `listening_started`。桌面端新增
  `ExtensiveListeningController`、Listening Inbox typed DTO/API、右侧 Inbox 整理面板、
  播放条泛听 toggle/软打断/硬打断按钮和应用内快捷键（`I`、`Shift+I`、`Shift+P`）。
  Inbox 项可回听、存入 `ReviewItem`、升格微精听练习项、收藏片段或归档；未处理项按
  默认 7 天过期降级归档。OpenAPI 与 handwritten TypeScript contract 已同步。
  新增 `3.3-MANUAL-QA.md`，将真实 30 分钟泛听、软/硬打断、Inbox 整理、重启持久化、
  过期归档和零打扰检查拆成可执行手工 QA 清单。
  验证：`cargo test -p application -p persistence-sqlite -p api-http -- --nocapture`、
  `cargo clippy -p application -p persistence-sqlite -p api-http --all-targets`（保留既有
  clippy warnings）、`flutter analyze`、`flutter test`、`./scripts/validate-contracts.sh`、
  `git diff --check` 通过。系统级全局热键、独立收藏浏览容器与 30 分钟真实媒体手工 QA
  仍留作 3.3 closeout 前事项。

- 2026-07-04 21:15 CST: 修复精听听写输入与播放器字幕快捷键冲突。
  新增 `PlayerGlobalShortcuts`，当焦点位于 `EditableText` 文本输入控件时临时让播放器级快捷键让路，
  避免真实听写中输入 `h` 被全局 `H` 隐藏字幕快捷键截获；无文本输入焦点时原播放器快捷键行为保持不变。
  新增 widget 回归测试覆盖 `H` 在输入态与非输入态的分发差异。

- 2026-07-04 16:38 CST: Phase 3.2 卡点与 session summary 切片落地。
  后端新增卡点/诊断查看/完成 session 事件流与 session summary API，卡点状态由
  `learning_events`、practice attempts、review items 派生，不引入新的持久化状态表；
  OpenAPI 与 TypeScript contract 同步更新。桌面端新增精听卡点标记/跳过、悬案区 v0、
  复习归因、诊断查看记录、完成精听 session 与熟料标记入口。新增 Rust persistence/API
  集成测试、Flutter controller/contract 测试，并更新 planning closeout、架构、数据模型与
  测试索引。验证：`cargo test -p application -p persistence-sqlite -p api-http`、
  `cargo clippy -p application -p persistence-sqlite -p api-http --all-targets`、
  `flutter analyze`、`flutter test`（170 passed）、`./scripts/validate-contracts.sh`、
  `git diff --check` 全部通过；真实媒体 GUI 手工 QA 尚待 owner 最终确认。

- 2026-07-04 16:06 CST: 桌面 app 品牌名与图标切换到 `listen`。
  根据 `docs/brand/listen/` 品牌材料，将 macOS app 产品名、Bundle ID、窗口标题、
  打包脚本产物名和用户可见导出文件名从 LLPlayerNext 切到 `listen`；使用推荐的
  `listen-icon-concept-b-1024.png` 重新生成 AppIcon iconset。用户数据路径采用兼容策略：
  新安装写入 `~/Library/Application Support/listen`，若旧 `LLPlayerNext` 数据库存在则继续读取旧库；
  设置文件读取新路径并回退旧路径，保存时写入新路径。

- 2026-07-04 15:50 CST: Phase 3.1 精听练习切片落地。
  桌面端新增 Test posture 的首个竖切片：三姿态入口、cloze / chunk dictation /
  sentence dictation 练习面板、练习 session/item/attempt/review 的 typed Dart DTO 与
  LocalApi 客户端封装、失败项一键进入 review；练习面板支持听后作答、结果 diff、重试、
  重放当前证据窗口和打开诊断。诊断侧完成 C-1 phrase-aware diagnosis：当前句命中的
  Phrase lexical entries 会参与 meaning / recognition barrier 判断；C-2 rhythm hotspots
  可从诊断卡直接 loop 对应 evidence range。新增 Flutter controller/contract/widget 测试与
  diagnosis-core phrase 回归测试。验证：`flutter analyze`、`flutter test`（168 passed）、
  `cargo test -p diagnosis-core`、`cargo test -p application`、`cargo test -p api-http`、
  `./scripts/validate-contracts.sh`、`git diff --check` 全部通过。

- 2026-07-04 12:46 CST: Phase 3.x 产品形态与执行序列全部落地（documentation-only）。
  新增 `.planning/discuss/listen-learning-activity-path.zh.md`：完整用户学习活动路径
  （冷启动 -> 材料供给 -> 泛听 -> 精听 -> 整理 -> 回访 -> 教练）与一级产品原则 P1-P6
  （精听/泛听一级心智、功能按场景分不按设备分且生产端唯一 PC-only、可组合不强制流程、
  泛听默认零打扰、不课程化不游戏化、硬件北极星约束），并定义核心概念（三姿态、双维
  难度、卡点、悬案区、Listening Inbox、微精听、片段收藏、熟料回听、猎词单、理解度
  自报、升级建议等）。新增 `3.0-PHASE-BREAKDOWN.md` 确立 Phase 3.1 ~ 3.10 执行序列、
  全局设计规则（可组合性、capability gating、guardrails 继承、evidence class、先派生
  后建模）与依赖图；新增十个 phase 目录及 PLAN：3.1 练习切片（含 C-1/C-2 进诊断）、
  3.2 卡点与 session summary、3.3 泛听 Inbox、3.4 audio-first 复习与升级建议、
  3.5 双维难度分拣、3.6 听力词典 MVP、3.7 猎词单、3.8 shadowing、3.9 L1-aware 诊断、
  3.10 教练 dashboard。同步更新 PROJECT.md（2026-07-04 产品定义更新 + §15.6 原则）、
  ROADMAP.md（头部路线注记 + §14.12 执行序列）、STATE.md（Phase 3.0 执行序列、
  最近决策、下一步改为 Phase 3.1 开工）、3.0-PLAN.md（breakdown 指针）。
  无产品代码变更。

- 2026-07-03 21:20 CST: 恢复误删的 listen brand 与用户旅程资源。
  最新一次 cleanup 提交误删了 `docs/brand/listen/` 品牌说明和 6 张视觉概念资产，
  以及 `.planning/discuss/listen-user-journeys-current-and-planned.md` / `.zh.md` 两份用户旅程文档；
  本提交在最新 main 顶部以 revert-style 恢复这些文档和资产。documentation-only，无产品代码变更。

- 2026-07-03 21:15 CST: 合入 listen brand 视觉概念与用户旅程文档。
  恢复并保留 `docs/brand/listen/` 品牌说明和 6 张视觉概念资产，同时将
  `.planning/discuss/listen-user-journeys-current-and-planned.md` 与中文版本
  `.planning/discuss/listen-user-journeys-current-and-planned.zh.md` 纳入 main；两份旅程文档覆盖
  当前已可达功能和 Phase 3.x 规划功能的用户路径。documentation-only，无产品代码变更。

- 2026-07-03 21:08 CST: Phase 2.23 正式收口 + ADR 0014。
  真实媒体手工 smoke 通过（owner 确认）后新增 `2.23-CLOSEOUT.md`：全部硬指标达成
  （main.dart 1457 行 / setState 10、sound_analysis 14 模块、schema v17、STATE 瘦身、
  cargo 358 / flutter 164 passed），A-1..A-7 + Step 3 + T1-T9 全部完成，C 类归 3.x、
  D 类明确 defer，phase 文件夹冻结。T7 决策落定为 **ADR 0014**：Dart 模型解析保持手写，
  fixture 契约测试为防漂移标准机制；存量 `timeline.dart` 不做 codegen 迁移，3.x 新 DTO
  默认手写 + 契约测试，新模型家族体量显著增长时再做仅新代码试点（新 ADR）。
  STATE.md 按维护规则把 2.23 压缩为已完成索引行（152 行），主线全面转入 Phase 3.x。
  仅规划/决策文档，无代码变更。

- 2026-07-03 16:07 CST: Phase 2.23 Step 3 完成 — main.dart 收缩为 composition root + UI 状态单轨化。
  硬指标达成：main.dart 3601 → **1457 行**（gate ≤1500）、setState 107 → **10**（gate ≤30，
  剩余均为局部 UI 状态）。六刀切法：(1) status 单源化——删除与 `PlayerController.status`
  重复的宿主字段（含一处双写），~95 处 setState 迁到 controller；(2) 新增
  `ResourceActionsCoordinator`（资源动作，8 个重复 timeline 方法收敛为共享骨架）；
  (3) 新增 `MediaSessionCoordinator`（媒体/字幕/LLTimeline 导入、生成轨、speech enhancements）；
  (4) 新增 `PlaybackActionsCoordinator`（chunk 导航/循环/occurrence 回放，顺带去除
  `_openVocabulary`/`_playOccurrence` 重复源解析块）；(5) Widget 提取 `PlayerStage`（491 行
  stage+overlay，phone-evidence 展开态内化）、`SidePanel`、`PlaybackBar`；(6) Flow 函数提取
  settings/online/embedded/OpenSubtitles/manual review（pristine 标志降级为流内局部变量）。
  coordinator 均 context-free，宿主经 `bind()` 注入运行时钩子；对话框留在宿主薄包装。
  controller + Store 定调为唯一 UI 状态模式并写入 `ARCHITECTURE.md` Flutter 节；
  `SubtitleController` 新增 `activeWordTimingCount` 派生 getter。新增
  `test/coordinators_test.dart`（6 测试）。验证：`flutter analyze` 无问题、`flutter test`
  **162 passed**（基线 156）、每刀独立全绿。待办（归用户）：按 `2.22-FRONTEND-E2E-QA.md`
  P0 路径跑真实媒体手工 smoke。
- 2026-07-02 23:52 CST: Phase 2.23 handoff T5 — 机械拆分巨型 Rust
  测试文件。`crates/persistence-sqlite/src/tests.rs` 拆为 `tests/`
  模块目录（migrations/timelines/lexical/subtitles_dictionary/vocabulary/
  phonetic_analysis/learning_loop + shared `mod.rs`），最大文件 507 行；
  `crates/api-http/src/tests.rs` 拆为 route-group 模块目录
  （general/media_subtitles/timelines/phonetic_analysis/speech_language/practice/
  openapi + shared `mod.rs`），OpenAPI parity 单独成文件，最大文件 902 行。
  仅调整测试模块相对 `include_*` 路径与模块开头 test attribute 边界，断言不改。
  验证：`cargo test -p persistence-sqlite --quiet` 46 passed、
  `cargo test -p api-http --quiet` 40 passed、`cargo test --workspace --quiet`
  358 passed、`./scripts/validate-contracts.sh` 通过。

- 2026-07-02 23:46 CST: Phase 2.23 handoff T4 — `sound_analysis.rs`
  机械拆分为 `crates/speech-analysis/src/sound_analysis/` 模块目录。
  `mod.rs` 仅保留 module declarations 与 public re-export，对外
  `speech_analysis::sound_analysis::*` 路径不变；实现切为 build/config/phones/
  connected/tokens/anchors/nuclei/grouping/boundaries/references/hotspots/quality/
  helpers/constants/tests，最大文件为 `tests.rs` 901 行，所有实现文件低于
  1500 行。字符串字面量 multiset 对比旧单文件保持 534/534 完全一致，
  provenance / signal-source / evidence 文案未改值；`AGENT.md` 新增
  >1500 行或多子域文件先拆模块的触发规则。验证：`cargo test -p speech-analysis
  --quiet` 152 passed、`cargo test --workspace --quiet` 358 passed、
  `./scripts/validate-contracts.sh` 通过。

- 2026-07-02 23:38 CST: Phase 2.23 handoff T3 — 建立基线快照
  `.planning/phases/2.23-architecture-debt-paydown/2.23-BASELINE.md`。
  记录 main.dart 3601 行 / 107 个 `setState`、`sound_analysis.rs` 3383 行、
  `timeline.dart` 2596 行、persistence/api-http 巨型测试文件 2603/2024 行、
  各 Rust crate 测试计数合计 358、Flutter 测试 158 passed。T3 预检先发现
  既有 `cargo fmt` drift，本批先用 workspace `cargo fmt` 修复 4 个 Rust 文件的
  formatter-only 差异，再完成基线记录。验证：
  `./scripts/test.sh --quick --low-memory` 4/7 passed（3 skipped，lib tests
  325 passed）、`cargo test --workspace --quiet` 358 passed、
  `./scripts/validate-contracts.sh` 通过、`flutter analyze` 无问题、
  `flutter test` 158 passed。

- 2026-07-02 23:14 CST: Phase 2.23 handoff T7 — 新增 Dart LLTimeline contract
  解析安全网与 codegen 调研。`apps/desktop/test/contract/lltimeline_parse_test.dart`
  直接读取 2 个 committed rhythm LLTimeline fixtures，覆盖 segments、WordTimeline、
  document-level `rhythm_frames`、`PhoneTimeline.sound_analysis.rhythm_frame` fallback
  与 audible-structure references/provenance/quality 关键字段。负向实验确认改坏
  `rhythm_frames` 字段会让测试变红。新增
  `design-notes/timeline-dart-codegen-research.md`，评估 json_serializable/freezed
  收益、成本和对现有手写容错语义的影响；本批不做迁移、不写 ADR。
  验证：`flutter analyze` 无问题、`flutter test` 158 passed。

- 2026-07-02 23:06 CST: Phase 2.23 handoff T6 — 完成剩余 SSE event payload
  typed 化。新增/扩展 `event_payloads.rs` 中 lexical-observation-cleared、
  vocabulary-assets-imported、pronunciation provider diagnostic、
  pronunciation-analysis-completed 与 route/job 共用 progress/completed payload；
  迁移 m18、pronunciation、timeline word-timing route、vocabulary import 和
  speech batch emit sites，生产发射点不再用 ad-hoc `json!` map 构造 event payload。
  验证：`cargo test -p api-http --quiet` 通过；专门 grep 仅剩 contract test 的
  `service-started` 示例。

- 2026-07-02 22:59 CST: Phase 2.23 handoff T2 — 修复文档事实源漂移。
  `ARCHITECTURE.md` 依赖图改为 `dictionary-provider` 与 `persistence-sqlite`
  同级适配器（均依赖 `application` 并实现其 trait），依赖方向图同步为
  `domain <- core engines <- application <- api-http / persistence-sqlite / dictionary-provider`。
  `STATE.md` 从 1208 行压缩为当前状态机 + 活跃/搁置 phase + 已完成 phase 索引，
  删除静态分支字段和不一致 progress 账；`MAINTENANCE.md` 增加 STATE ≤400 行、
  phase 收口压缩索引、不记录瞬时 git 事实等防复发规则。

- 2026-07-02 22:52 CST: Phase 2.23 handoff T1/T8/T9 — SQLite schema v17 drops
  the unused `learning_resources` table without touching historical migrations;
  migration tests now assert upgraded databases no longer contain that table.
  `DATA-MODEL.md` records WordTimeline vs legacy `word_timings` authority,
  document-level `rhythm_frames` vs transitional `PhoneTimeline.sound_analysis`
  rhythm frames, and the JSON-quoted `status = '"active"'` partial-index coupling.
  `ARCHITECTURE.md` / `STACK.md` now reflect schema v17 and the removed table;
  the 2.23 review register marks B-1, B-3, and B-5 closed.

- 2026-07-02 20:52 CST: Phase 2.23 分工落定 — 新增交接任务包 `2.23-HANDOFF-TASKS.md`。
  剩余待修项（B-1 僵尸表、B-2 文档漂移、B-3 双家退役条件、B-5 小项）与 PLAN
  Step 0/2/4/5（基线、sound_analysis 拆分、Dart contract 安全网、tests 拆分）整理为
  T1-T9 自包含任务（步骤/验收/铁律/依赖冲突提示），交其他执行人；Step 3（main.dart
  收缩）由原审核会话执行人负责。顺带核实并修正一处事实：`state/store.dart` 的
  `Store<T>` 已被 player/learning/subtitle 三大控制器使用（非死雏形），Step 3 的
  "状态模式定调"决策消解为 controller + Store 转正唯一模式（PLAN/CONTEXT 已同步修正）。
  仅规划文档，无代码变更。

- 2026-07-02 20:36 CST: Phase 2.23 审核缺陷收口第二批 — B-4 与 C-7 主切片。
  (1) **B-4 learning-loop 双表示写入收敛**：五个 upsert 的 `ON CONFLICT DO UPDATE` 从
  只更新 `*_json`（practice_items/practice_attempts/review_attempts 完全不更新查询列）
  改为完整非主键列更新，列与 JSON 永远出自同一 struct 同一语句；round-trip 测试扩展
  覆盖改 kind/result/status 后列值与 JSON 投影一致、按 status 过滤正确。
  (2) **C-7 SSE payload 生产端 typed 化 + 跨语言 golden 契约**：新增
  `api-http/src/event_payloads.rs`（6 个 typed payload struct，统一
  `speech-cache-invalidated` 两处不一致形状），迁移 6 处 ad-hoc `json!` 发射点；
  新增 `contracts/events/examples.json` golden 信封，Rust 侧
  `event_contract_examples_match_producers`（`UPDATE_EVENT_EXAMPLES=1` 再生成）与
  Dart 侧 `test/contract/backend_event_contract_test.dart` 双端锁定 Flutter typed
  消费的全部 6 个事件的 wire shape。register 同步更新（B-4→A-6、C-7→A-7+剩余项）。
  验证：`cargo test --workspace` 358 passed、`flutter analyze` 无问题、
  `flutter test` 156 passed（+6 契约测试）、`./scripts/validate-contracts.sh` 通过。

- 2026-07-02 20:13 CST: Phase 2.23 审核缺陷收口 — 修复五项高优先级架构缺陷（Rust 内部契约，
  API/JSON shape 零变化）。(1) 诊断归一化接缝：`diagnosis-core::diagnose` 新增 token→词条 key
  映射参数，application 用 provider 归一化链解析后传入，屈折形式（"went"）不再误判 unclassified；
  (2) 观察身份统一：新增 `domain::lexical_observation_id(entry, sentence)` 确定性单源函数，
  三处生成点（API/practice/import）收敛，同句新观察覆盖 result 但 ID 稳定，
  `generated_observation_ids` 不再悬挂，import 幂等改善；(3) SSE 事件契约：schema 补
  `sound-line-changed/completed` 漂移，api-events 新增 `EventName::ALL` + 编译期穷尽守卫 +
  双向 parity 测试；(4) LLTimeline 导入身份重写所有权归一：`remap_lltimeline_sentence_ids`
  更名 `remap_lltimeline_identity` 并吸收调用方 track/media 重写循环，新增全文档
  "原始 ID 零残留"不变量测试（覆盖 W8 脱钩 bug 类）；(5) `LexicalEntry` 双身份轴硬化：
  kind↔granularity 映射收进 domain，`validate_unit_coherence()` 在 persistence 写读两侧
  强制四轴一致。新增 `2.23-REVIEW-FINDINGS-REGISTER.md` 登记全部审核发现的归属
  （已修/交接他人/归 3.x/defer）；同步 `DATA-MODEL.md`（观察身份语义）与
  `ARCHITECTURE.md`（diagnosis-core 输入契约）。
  验证：`cargo test --workspace` 357 passed、`./scripts/validate-contracts.sh` 通过、
  clippy 无新增警告；Flutter 未运行（shape 不变，无需改动）。

- 2026-07-02 13:50 CST: 方向决策 — speech-analysis 算法线搁置，主线转入 Phase 3.x 学习闭环。
  Phase 2.19/2.20/2.21 整体搁置（STATE.md 标记 ⏸ 并注明重启条件；audible-structure v1
  contract 保持权威 shape，3.x 按现状消费）；Phase 3.0 升为当前主线。Phase 2.23 相应调整：
  Step 3（main.dart 收缩）升为 P0 并提前到 Rust 拆分之前执行（3.x Flutter practice UI 前置），
  Step 2（sound_analysis 拆分）降为 P1、改在算法线静默窗口内零冲突完成。同步更新
  ROADMAP.md 路线注记、`2.23-CONTEXT.md` / `2.23-PLAN.md`。仅规划文档，无代码变更。

- 2026-07-02 13:35 CST: 新增 Phase 2.23 Architecture Debt Paydown（建档，未开工）。
  基于 2026-07-02 全库架构审核（依赖方向 / api-http 越层 / 端口-适配器 / 测试基线均验证成立），
  立案五项累积债务：A1 `main.dart` god file + UI 状态双轨（3601 行 / 107 setState）、
  A2 `sound_analysis.rs` 单文件膨胀（3383 行，contract 已锁 v1）、A3 文档事实源漂移
  （ARCHITECTURE.md dictionary-provider 依赖方向画反、STATE.md 1149 行且 frontmatter 与正文矛盾）、
  A4 Dart 手写模型解析无契约守卫（timeline.dart 2596 行）、A5 巨型 tests.rs（2534/2021 行）。
  新增 `2.23-CONTEXT.md` / `2.23-PLAN.md`（6 步、全可测量验收、机械治理不改行为），
  STATE.md 登记 Phase 2.23 section。仅规划文档，无代码变更。

- 2026-07-02 10:45 CST: Phase 2.22 defer 清零 (2/5) — SM-04 下载栏消失行为。
  Failed 下载栏在可配置延时后自动消失（`DownloadController.failedAutoDismiss`，默认 10s，
  因失败态无可留操作）；Completed 栏保留以保住 “Open”，点 Open 时顺带 dismiss 消栏。旧 failed
  timer 被 generation 守卫，不会误清后续新下载。新增 3 个单测。
  验证: `flutter analyze` 无问题、`flutter test` 150 passed。

- 2026-07-02 10:15 CST: Phase 2.22 defer 清零 (1/5) — SM-05 副字幕缺失提示。
  副字幕开启但根本没有副字幕轨道（`secondaryTrack == null`）时，overlay 显示克制的
  “No secondary subtitle / 无副字幕”提示；已有轨道内的空档保持空（字幕空档正常，不提示）。
  用 `secondaryTrack` vs `currentSecondaryCue` 区分两种情况。顺带删除第二个死代码 overlay
  widget `widgets/layout/subtitle_overlay.dart`（与旧 side_panel 同型孤儿，main.dart 用内联渲染）。
  验证: `flutter analyze` 无问题、`flutter test` 147 passed。

- 2026-07-02 09:45 CST: Phase 2.22 判定达成、转收口。
  阶段三目标（确认功能工作流/路径、建立用户可见状态机、据状态机找出问题）按 journey/状态机层面
  判定达成：`2.22-USER-VISIBLE-STATE-MACHINE.md`（R0-R8 + Section C 就绪 lane）已建，Defect
  Register 产出并闭环修复 SM-01/02/03/07b（+ 记录 F1-F8）。剩余 SM-04/05/06/07剩余/08 明确 defer
  （待 UX / polish / YAGNI / 候选下一后端阶段）。新增
  `2.22-CLOSEOUT.md`，`STATE.md` 标记 Phase 2.22 ✅ 已收口（真实媒体手工 smoke 待用户跑）。
  逐功能模板化（约 40 个 checklist 功能）journey 层已覆盖、价值低，刻意不做。
  自动化：`flutter analyze` 无问题、`flutter test` 147 passed。

- 2026-07-02 09:15 CST: Phase 2.22 转绿 + SM-01 缩范围收口。
  (1) **转绿**: `diagnosis_card_test` 的 `rhythm frame renders before phone evidence`
  因 `stressAnchors` 文案由 `Anchors` 改为 `Heard anchors`（information-anchors 语义重构）
  而断言过时，更新为 `Heard anchors:`；其余断言仍匹配当前诊断卡渲染。
  (2) **SM-01（缩范围，收口标准 #5）**: 全量审计确认自由字符串 `status` 只有一处被读值驱动
  行为（manual-review 关闭守卫的 `status == 'Loading manual review timeline...'` 魔法字符串），
  其余全是写入/显示。该处改为 typed `_manualReviewStatusPristine` 标志，自由字符串不再驱动
  任何行为（行为由 typed lane 驱动：readiness / `DownloadController` / `UserTaskStatus`）。
  ~99 处显示型 `status` 写入的全量枚举化判定为镀金，未做。
  验证: `cd apps/desktop && flutter analyze` 无问题、full `flutter test` 147 passed。

- 2026-07-02 00:52 CST: 为 Rhythm C 正式引入 `information_anchors`。
  `RhythmFrame` 新增兼容字段 `information_anchors`，用于建模“人耳实际抓到哪些音素/声音点并据此推断句义”，
  不再把 `stress_anchors` 当作 C 的核心语义；生成器会从 phone timing 或 word timing + canonical phones
  产出音素级信息锚点（保留否定、指示、疑问等高信息功能词），C UI 优先渲染 information anchors，
  旧资源缺字段时才回退到 stress anchors。Readiness 同步把 information anchors 计入音频支持判定。

- 2026-07-02 00:30 CST: 优化 Rhythm C 的真实可听锚点表达。
  C `This audio` 不再把前景锚点过度收窄为“重读音节”：后端允许短但有音频时序支持的
  content sound 成为 audio-supported listening anchor，并将 anchor confidence 与
  nucleus prominence 分开校准，让能量/音高突出优先决定主核；前端将锚点 label 从单个重读元音
  扩展为“语义锚点词 + 元音核/临近辅音边缘”的可听信息节点（如 `changed` + `/tʃeɪndʒd/`），
  弱读团仍保持低对比背景。同步将 C 的文案从 stress/rhythm 调整为 heard information anchors。
  新增短时序 content anchor 与 consonant-vowel shape 的回归测试。

- 2026-07-02 00:15 CST: 优化 Rhythm B 默认语流规则的底层算法口径。
  B 的 text-prior 规则现在从发音 provider 取得 ARPABET 音素序列，跨词 linking、
  同辅音保持、t/d weakening 与 American flap 都按音素特征判断，不再按拼写字母猜测；
  修复 t/d weakening 错把“下一个词尾是辅音”当作条件的问题，改为真正的“下一个词首为辅音”；
  弱读/短语规则会过滤 canonical 与 reduced 完全相同的 no-op 标注，并在 fallback 发音不可靠时
  回退到规则表的强读音素。同步更新旧 `analyze_rules` 出口和规则目录说明，删除旧拼写 helper，
  新增 no-op、phone-boundary linking、t/d vowel/consonant 条件等回归测试。

- 2026-07-01 23:11 CST: 重构 Rhythm B/C 字幕视图的学习语义与视觉层级。
  B `Common speech` 不再把规则拆成卡片列表，而是按原句 token range 就地显示弧线、
  下划线、规则名和 A → B IPA 变化，未变化文本退为上下文；C `This audio` 从诊断标签集合
  收敛为可听前景/背景：用词典音素标记音频支持的重音与 nucleus，弱读音团低对比显示，
  phrase boundary 仅作分隔，compression/hotspot 不再占用默认表面，详细 phone evidence
  仍由 C 内按需展开；音频支持的 C 视图会逐项排除仅有 text-prior 的预测 anchor，防止预测项
  混入真实听感。同步更新中英文提示和 Flutter widget 回归测试，并完成真实桌面渲染检查。

- 2026-07-01 21:30 CST: 声音线彻底解耦为独立后台工作流。
  新增 `SoundLineCoordinator`（`crates/api-http/src/sound_line.rs`）：拥有自己的 job
  生命周期（queued/running/completed/cancelled/failed）、独立 temp 目录与独立音频提取，
  订阅 `transcription-job-changed(completed)` 后自动入队，并暴露
  `/v1/sound-line/jobs` 的 create/list/get/cancel/retry。转录流程 `process_job` 不再
  内嵌声音线 spawn 与延迟清理，只负责文字线（存 active `whisper-dtw` timeline）并在完成后
  立即清理 work_dir——文字线路径上不再有任何声音线代码。事件拆分：文字线用
  `word-timings-completed(line=text)`，声音线改用新的 `sound-line-changed` /
  `sound-line-completed`；前端新增 `SoundLineCompletedEvent`，文字线静默刷新、声音线单独
  报告就绪。红线（声音线永不 activate、绝不改动 active 文字线）由 api-http 测试
  `sound_line_resources_never_disturb_active_text_timeline` 固化。共用的 ffmpeg 参数
  构造抽为 `ffmpeg_wav_args`。验证覆盖 `application`/`api-http`/`api-events` 测试、
  OpenAPI contract 与 Flutter backend event coordinator 测试。

- 2026-07-01 20:10 CST: ASR 文字线与声音线解耦。
  whisper.cpp + DTW 现在只负责文字线，生成 active `whisper-dtw` WordTimeline 后即可完成
  ASR job，保留词级跳动、chunk 与词典音标的原有路径；forced alignment、pause refinement
  与 word-acoustic cues 改为后台声音线任务，产出 `line=sound` candidate WordTimeline 与
  RhythmFrame 资源，不再覆盖 active text timeline。LLTimeline 导出优先让 RhythmFrame
  挂到带声学 cues 的声音线 timeline，前端监听 `word-timings-completed` 后刷新当前资源。
  验证覆盖 `application`、`api-http` 后端测试与 Flutter backend event coordinator 测试。

- 2026-07-01 19:16 CST: ASR word-timeline 后处理恢复安全降级。
  修复最新提交后 ASR 任务会因 `word timing boundary must not be empty` 标红的问题：
  whisper.cpp DTW 重复时间点现在会被拆成单调、非空词区间，裁到句子边界后仍为 0
  长度的句子会回退而不是写入非法 timing；转录导入后的 WordTimeline、pause refinement
  与 word-acoustic cue 保存重新改为 best-effort，失败时保留已生成字幕轨并返回 0 cue/legacy
  fallback 状态，不再中断主 ASR job。验证覆盖 `speech-analysis`、`application` 与
  `api-http` 测试。

- 2026-07-01 18:34 CST: Phase 2.21 Rhythm A/B/C subtitle views。
  字幕层主切换从历史 `rhythm` / `phones` 改为三个都属于 Rhythm 的 reference：A
  `citation` 显示词典独立读音，B `connected` 显示规则预测的语流形式及 A → B 音标差异，
  C `actual` 显示当前音频 RhythmFrame。Phones 继续保留，但降为 C 内按需展开的 L4
  evidence，不再占用一级模式。Rust/OpenAPI/Flutter 为 B 增加 surface、rule family/hint、
  canonical/default symbols 与 display IPA；旧设置值安全迁移到 C。验证包含 Rust
  sound-analysis、domain/application/api-http、OpenAPI contracts 和 Flutter 定向测试。

- 2026-07-01 17:48 CST: Phase 2.21 consumer self-contained audible structure。
  明确轻量消费端必须以 bundled whisper.cpp + Rust 自成完整基础生态，sidecar 只提升质量。
  新增 `speech-analysis::word_acoustics`：在本机转录 WAV 删除前提取 per-word RMS energy、
  F0 median/range、pitch prominence 和 pitch reset，并持久化到
  `rhythm_word_acoustic_cues` artifact。RhythmFrame 现在让 pitch 参与 anchor/nucleus，
  允许明显 pitch reset 支持 phrase boundary；`AsrReported` 作为低精度音频时序参与
  duration/compression/boundary，只有 `Estimated` 保持纯文本预测。转录链路不再静默吞掉
  WordTimeline/acoustic persistence 错误。W8 QA 改为阈值校准与回归，不再作为 RMS/F0
  是否进入消费端的采用门槛；架构边界记录于 ADR 0013。

- 2026-07-01 16:05 CST: Phase 2.22 SM-07b — overlay predicted-only listening 徽标。
  当前句 listening structure 若无音频信号源（纯 text-prior 预测），overlay 的
  `RhythmFrameRibbon` 现在显示 `predicted` 徽标 + “基于文本预测、非实测音频” tooltip，
  不再让预测读起来像实测音频。`_rhythmFrameHasAudioSupport` 提升为公开
  `rhythmFrameHasAudioSupport(RhythmFrame)`，overlay 与 listening-structure readiness
  共用同一判据。修复了徽标在窄 leading 区的 `RenderFlex` 溢出（由 widget 测试发现）。
  过程记录：SM-07a（readiness 去重）经读码证伪为低价值纠缠改动——两处 readiness 实为不同的
  word-timing-count fallback，非纯重复——已 deprioritize。
  验证: `cd apps/desktop && flutter analyze` 无问题、full `flutter test` 134 passed
  （`capability_readiness_test.dart` 新增谓词 + predicted 徽标 widget 测试）。

- 2026-07-01 15:45 CST: Phase 2.22 建模重建 + 前端拆分增量（SM-02 / SM-03）。
  复核发现 GPT 的 2.22 遗漏了用户可见状态机建模、Capability Stack 的 L 层号自相矛盾、
  readiness 仅覆盖 5/11 层，且“前端 closeout 已完成”属高估。
  (1) **权威模型**: 新增
  `.planning/phases/2.22-user-facing-workflow-semantics/2.22-USER-VISIBLE-STATE-MACHINE.md`
  （R0-R8 surface 区域 + Section C 能力就绪 lane + Defect Register SM-01..08 / SM-F1..F8）；
  修正 `2.22-FEATURE-SEMANTICS-MODEL.md` 的 L 层号并新增 Model↔Code 对账；
  `2.22-CURRENT-FEATURE-INVENTORY.md` 改为覆盖清单 + 已验证 P0 模板 F1-F8。
  (2) **记账纠正**: `STATE.md` / `2.22-PLAN.md` 去除“closeout 已完成”高估，列清 OPEN 项。
  (3) **SM-02**: 删除死且分叉的 `apps/desktop/lib/widgets/layout/side_panel.dart`
  （其 Resources tab 用旧 `TimelineResourceSummaryPanel`，接线会退化 Resources tab，故删非接）。
  (4) **SM-03**: 下载状态从散落 5 处（`activeDownload` / `downloadError` /
  `downloadGeneration` + PlayerState `downloadProgress` / `downloadedMediaPath`）
  收敛为单一 `DownloadController`（generation + disposed 守卫，仅依赖 Stream/Future 原语，
  与下载服务解耦以便单测）；`main.dart` −84 行，`PlayerState` 去掉 2 个死字段。
  验证: `cd apps/desktop && flutter analyze` 无问题、full `flutter test` 131 passed
  （新增 `test/download_controller_test.dart` +5）。

- 2026-07-01 15:15 CST: 修复 Whisper 生成字幕后的 Timeline resource 状态误判。
  当当前字幕已加载 generated word timings 但没有 active `WordTimelineSummary` 时，
  Timeline resource 面板现在会把 Word sync 显示为可用，并显示词级 timing 数量；
  generated LLTimeline document 也会被视为可导出资源，不再显示成“旧时间轴降级”导致
  生成语块和导出 LLTimeline JSON 被禁用。

- 2026-07-01 14:45 CST: 修复点击字幕单词后右侧面板不立即跳到词汇学习的问题。
  `LearningWorkflowController.openWord` 现在会在词条、词典、发音和语言画像查询完成前，
  立即记录 selected token/cue 并切换到 Word learning tab；异步查询完成后再填充详情。
  新增回归测试覆盖 lookup 未返回时 side panel 已切换到词汇学习。

- 2026-07-01 14:25 CST: Phase 2.22 frontend workflow semantics closeout slice。
  (1) **Typed task feedback**: 新增 `UserTaskStatus`，把本机 Whisper 字幕生成和
  Phone evidence/audio-analysis job 映射为 `working/success/warning/error/cancelled/unknown`
  等前端状态；`BackendEventCoordinator` 先写 typed task state，再保留摘要文字。
  (2) **Playback controls**: 底部控制栏显示字幕生成与音素证据分析 task chip，
  不再只依赖自由字符串表达 ASR/audio-analysis 进度；切换媒体会清除旧任务状态。
  (3) **Closeout docs**: 新增
  `.planning/phases/2.22-user-facing-workflow-semantics/2.22-BACKEND-CONTRACT-GAPS.md`
  和 `2.22-FRONTEND-E2E-QA.md`，把前端语义审计暴露的后端契约缺口记录为后续输入，
  同时固定前端端到端 smoke 路径。
  验证: `cd apps/desktop && dart format ...`、
  `cd apps/desktop && flutter analyze`、focused
  `flutter test test/backend_event_coordinator_test.dart test/task_status_test.dart`、
  full `flutter test`、`git diff --check` 通过。

- 2026-07-01 14:15 CST: Phase 2.22 Step 3 subtitle resource capability-first。
  字幕资源 tile 现在以用户能力为主，直接展示 Subtitles、Word sync、Chunk replay、
  Phone evidence 的可用/不可用状态和数量；Listening structure 不再被假装成逐资源已知事实，
  active resource 指向下方 timeline details，inactive resource 明确需要激活后检查。
  同步记录一个后端闭环发现：当前 API 能逐字幕资源提供 sentence/word/chunk/phone
  能力计数，但没有直接的 per-subtitle-resource Listening structure readiness 查询，
  该事实目前只能在激活/export track timeline 后获得。

- 2026-07-01 13:58 CST: 推进 Phase 2.22 P0 user-facing workflow semantics。
  (1) **Local Whisper path**: 生成字幕弹窗现在返回是否真正创建任务；主界面在任务创建后显示
  主/副字幕生成预期，生成主字幕自动载入后会汇总 Word sync、Chunk replay、Listening
  structure、Phone evidence readiness。
  (2) **Overlay missing states**: Phone evidence 模式在已有分析对象但无 detected phones
  时不再静默消失，而是显示明确不可用提示。
  (3) **Layout semantics**: 隐藏字幕不再隐藏 transcript/resources/diagnosis side panel；
  no-media 状态改为简洁打开媒体控制条；副字幕与 chunk 控件在不可用时提供明确原因。
  (4) **Download status**: 下载条改用 typed `DownloadStatusSnapshot`
  区分 downloading/completed/failed；开始下载会清掉旧完成路径，取消/关闭会使后到的
  yt-dlp future 失效，避免 dismissed bar 复活。
  验证:
  `/Users/shadow/.local/share/flutter/bin/dart format ...`、
  `cd apps/desktop && /Users/shadow/.local/share/flutter/bin/flutter analyze`、
  `cd apps/desktop && /Users/shadow/.local/share/flutter/bin/flutter test`、
  `git diff --check` 通过。

- 2026-07-01 13:30 CST: 完成 Phase 2.22 Step 0 UI audit 文档化。
  新增
  `.planning/phases/2.22-user-facing-workflow-semantics/2.22-STEP0-UI-AUDIT.md`，
  按当前 Flutter 工作树核对用户可见入口、状态区域、端到端路径、标签语义债务和 P0/P1 owner steps；
  同步 `2.22-PLAN.md` 与 `2.22-CURRENT-FEATURE-INVENTORY.md` 指向该 Step 0
  产物。本次补充为 documentation-only，没有新增产品代码。

- 2026-07-01 13:22 CST: Phase 2.22 Step 0 audit checkpoint and first P0
  readiness slice.
  (1) **Current UI audit**: verified the current Flutter entry/state surfaces
  against `main` for media open/playback, URL/download, drag/drop,
  SRT/VTT/imported/embedded/OpenSubtitles/local Whisper subtitle paths, subtitle
  resources, timeline resources, overlay listening/phone layers, side panel,
  controls, diagnostics, vocabulary, settings, and task/status feedback.
  (2) **Capability readiness model**: added a typed frontend
  `CapabilityReadinessSnapshot` covering Subtitles, Word sync, Chunk replay,
  Listening structure, and Phone evidence with Phase 2.22 states
  `available/degraded/unavailable/stale/error`.
  (3) **Resource panel UX**: timeline resource summary now shows a compact
  user-facing "Learning capabilities" readiness strip before advanced
  WordTimeline/ChunkTimeline/PhoneTimeline details, including honest degraded
  states for estimated/predicted listening structure and unavailable phone
  evidence.
  (4) **Language cleanup**: renamed primary UI copy from `sound pattern` /
  `Listening rhythm` to `Listening structure` / `Phone evidence` while keeping
  internal setting keys and resource names stable for compatibility.
  验证: `cd apps/desktop && flutter analyze`、`cd apps/desktop && flutter test`
  通过。

- 2026-07-01 12:59 CST: 新增 Phase 2.22 User-Facing Workflow Semantics。
  (1) **Phase shell**: 新建
  `.planning/phases/2.22-user-facing-workflow-semantics/`，包含 context、feature
  semantics model、current feature inventory 和 plan，明确当前问题是所有用户功能的入口、状态、降级和端到端路径混乱，
  不是单个 `rhythm_frames` 开关。
  (2) **Product contract**: 定义用户可见能力栈：Media source、Playback、Subtitles、
  Transcript/overlay、Word sync、Chunk replay、Listening structure、Phone evidence、
  Vocabulary、Diagnosis、System/task feedback、Practice/Review readiness；
  readiness states 统一为 available/generating/degraded/unavailable/unsupported/stale/error。
  (3) **UI worktree input**: `2.22-CURRENT-FEATURE-INVENTORY.md` 参考
  `worktree-ui-feature-semantic-mapping` 的功能描述，先覆盖媒体、字幕、播放、资源、词汇、
  诊断、听感/音素、设置和任务反馈等当前全部功能，后续 Step 0 按当前 main 校验。
  (4) **Roadmap/requirements sync**: PROJECT、ROADMAP、STATE、handoff 和 REQUIREMENTS 已同步
  Phase 2.22；新增 `M2-UX` 阶段与 `UX-001` 至 `UX-008` 需求，覆盖能力模型、本机
  Whisper 默认路径、资源面板、Listening structure / Phone evidence 语义、typed status、
  布局入口和端到端验证。
  验证: documentation-only change；`git diff --check` 通过。

- 2026-07-01 10:36 CST: 修复 Phase 2.18 后旧本地库 schema 漂移导致的媒体/字幕断链。
  (1) **Destructive repair migration**: SQLite schema 升到 v16，新增
  `0016_destructive_lexical_reset.sql`，重建 `LexicalEntry + LexicalUnit`
  所需的 lexical/learning-resource 表，清理旧 v7 lexical schema。
  (2) **Runtime impact**: 修复已有库 `user_version=15` 但缺少
  `lexical_observations`、`granularity`、`normalization`、`normalized_key`
  时，媒体注册、SRT 导入和字幕增强加载被 `no such table/column` 阻断的问题。
  (3) **Custom Whisper DTW**: 自定义 whisper.cpp 模型不再因为
  `family=custom` 跳过 `-dtw`；现在会从 `display_name`/`local_path`
  解析 stock preset，覆盖 `ggml-large-v3-q5_0.bin` 等量化文件名，恢复
  Whisper 生成字幕后的 WordTimeline/Chunk 材料。
  (4) **Regression**: 新增坏库回归测试，模拟旧 0007 已跑完且版本号已到 15 的真实形态，
  确认迁移到 v16 后表结构恢复且旧词库数据按当前断代策略丢弃。
  验证: `cargo test -p persistence-sqlite -- --nocapture`、
  `cargo test -p api-http dtw -- --nocapture`、
  `cargo test -p api-http --test api_integration_test -- --nocapture`、
  `./scripts/test.sh --quick --json` 通过；复制坏库的真实 HTTP media register + SRT import
  smoke 通过。

- 2026-07-01 CST: 合并 testing-system-buildout 后清理 main 既有 analyze 告警——
  移除 `test/controllers_test.dart:233` 与 `test/timeline_resource_summary_panel_test.dart:33`
  中 `rhythmFrames: const []` 冗余的 `const`（`unnecessary_const`，随 Phase 2.21 韵律
  提交引入，非本次合并造成）。零行为变化，`flutter analyze` 恢复 0 issue。

- 2026-07-01 00:46 CST: Phase 2.21 W8 local product QA pack。
  (1) **Artifact remap fix**: LLTimeline import now remaps
  `rhythm_word_acoustic_cues.payload.timeline_id` and cue `sentence_id` alongside
  WordTimeline/sentence ids, so imported production-side energy artifacts remain
  attached to generated RhythmFrames.
  (2) **Local W8 pack**: refreshed Brooklyn product media into
  `.tmp/rhythm-frame-qa/w8-product/brooklyn-w8.lltimeline.json` with 114
  `wordtimeline_timing_acoustic_prominence_v1` RhythmFrames; selected 10 QA
  sentences and generated `annotations-template.jsonl`, `selected-sentences.md`,
  and 10 wav clips under `.tmp/rhythm-frame-qa/w8-product/`.
  (3) **Gate honesty**: empty annotation templates validate but no longer count
  as manual annotations; the generated W8 template still reports
  `annotated_sentence_count = 0` until human labels are filled.
  验证: `cargo test -p application --quiet`、`python3 scripts/test_evaluate_rhythm_frame.py`
  通过；Brooklyn W8 readiness gate reports 114 WordTimeline+energy RhythmFrames.

- 2026-07-01 00:18 CST: Phase 2.21 W8 product QA tooling checkpoint。
  (1) **Manual QA contract**: RhythmFrame annotation schema, sample labels,
  committed fixture labels, and scorer now include `nuclei` and
  `connected_speech_refs` as first-class manual QA fields.
  (2) **W8 gates**: `evaluate-rhythm-frame.py` can emit capped templates that
  skip missing RhythmFrame rows and can gate minimum RhythmFrame sentence count,
  WordTimeline RhythmFrame count, and energy-prominence RhythmFrame count.
  (3) **Readiness honesty**: current local Phase 2.17 real-media artifacts are
  measurable but not closeout-ready: 47 selected sentences have only 1 old v0
  phone-timeline RhythmFrame, 0 WordTimeline RhythmFrames, 0 energy-prominence
  RhythmFrames, and 0 manual labels. Next step is regeneration with the current
  production pipeline, then manual labels.
  验证: `python3 scripts/test_evaluate_rhythm_frame.py` 通过；fixture W8 gate 通过。

- 2026-06-30 23:32 CST: Phase 2.21 review backlog W6 information-structure
  prominence prior。
  (1) **Text prior**: RhythmFrame anchor scoring now lightly down-weights repeated
  content words and gives phrase-final content a small focus boost.
  (2) **Honesty invariant**: this remains `TextPrior`; it adjusts prominence and
  confidence but never upgrades a claim to `AudioSupported` without timing,
  energy, pitch, or phone evidence.
  (3) **Tests/docs**: added a unit test for repeated-content downweighting and
  phrase-final focus boost; synced phase/codebase docs.
  验证: `cargo test -p speech-analysis --quiet` 通过。

- 2026-06-30 23:29 CST: Phase 2.21 review backlog W5 Reference A OOV fallback
  hardening。
  (1) **Fallback v2**: `speech-analysis` pronunciation provider version updated
  to `74790861+fallback-v2`; CMUdict-missing words now use a deterministic G2P
  fallback with common English digraphs, soft c/g, final silent e, and x handling.
  (2) **Stress honesty**: fallback phones now assign a single primary stress to
  the first fallback vowel and mark later fallback vowels unstressed, instead of
  treating every OOV vowel as primary stress.
  (3) **Tests/docs**: added a unit test for fallback stress behavior and synced
  phase/codebase docs.
  验证: `cargo test -p speech-analysis --quiet` 通过。

- 2026-06-30 23:24 CST: Phase 2.21 review backlog W4 energy cue live path
  arch slice。
  (1) **Production-side provider**: `scripts/timeline-production/production_pipeline.py`
  now computes per-word RMS relative energy from extracted 16k mono wav and writes
  a `rhythm_word_acoustic_cues` LLTimeline artifact with `energy_prominence`,
  `dbfs`, and sentence-median delta diagnostics. Failures degrade to a diagnostics
  artifact instead of breaking WordTimeline production.
  (2) **Application consumption**: LLTimeline export parses active WordTimeline
  matching acoustic cue artifacts and passes them into `RhythmWordAcousticCue`;
  generated document-level RhythmFrames can now report
  `wordtimeline_timing_acoustic_prominence_v1` and include `energy` in
  `quality.prominence_sources`.
  (3) **Tests/docs**: API export/import regression now verifies artifact →
  RhythmFrame energy provenance; added production pipeline synthetic-wav test and
  synchronized phase/codebase docs. W8 manual QA remains required before RMS
  calibration becomes a release gate.
  验证: `python3 scripts/timeline-production/test_production_pipeline_acoustic_cues.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `cargo test -p application -p api-http -p speech-analysis --quiet` 通过。

- 2026-06-30 23:13 CST: Phase 2.21 review backlog W3 Reference B connected-form
  rule engine。
  (1) **Reference B engine**: 新增
  `speech-analysis::connected_speech_rules`，用英语文本生成 default connected forms，
  覆盖 closed weak-form lexicon、`could have -> K UH D AH V`、want/going to、did you、
  linking、t/d weakening、contraction、assimilation 和 flapping candidates。
  (2) **A/B/C divergence**: `SoundAnalysis.connected_speech` 和
  `RhythmFrame.connected_speech_refs` 会合并 B rules 与 CTC L4 evidence；B-matched
  audio 标为 `teachable_rule` 并带 `text_prior + phone_segmental`，B-unmatched audio
  才标为 `clip_specific`。纯 B prediction 保持 `TextPrior` / `Predicted`。
  (3) **Fixtures/UI tests**: default_connected source 统一为
  `english_connected_speech_rules_v1`；no-phone document-level fixture 现在包含
  text-prior connected refs，但 `phone_evidence_coverage` 仍为 `0.0`。
  (4) **Planning sync**: 同步 PLAN、CONTEXT、STATE、handoff、ARCHITECTURE、
  DATA-MODEL、TESTING 和 QA README；后续优先级前移到 W4 product-side energy QA 和
  W5/W6 text-prior hardening。
  验证: `cargo test -p speech-analysis --quiet`、
  `cargo test -p domain -p application -p api-http -p speech-analysis --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart` 通过。

- 2026-06-30 22:57 CST: Phase 2.21 review backlog W2 first-class WordTimeline →
  RhythmFrame path。
  (1) **Named resource path**: `LLTimelineDocument` 新增 document-level
  `rhythm_frames`，OpenAPI / Rust domain / Flutter typed model 同步解析；export 会
  从 active WordTimeline + dictionary/canonical stress 生成 `wordtimeline-rhythm-frame`
  resource，不经 phonetic-analysis job、PhoneTimeline 包装或 synthetic phones。
  (2) **UI consumption**: subtitle rhythm layer 现在按 sentence 优先使用
  `LLTimelineDocument.rhythm_frames`，没有 document-level frame 时才 fallback 到
  `PhoneTimeline.sound_analysis.rhythm_frame`。
  (3) **Scorer + fixture**: RhythmFrame scorer 会消费 document-level rhythm frames；
  no-phone committed fixture 已迁移为 `phone_timelines: []` + `rhythm_frames`，证明
  WordTimeline-only JSON 消费路径。
  (4) **Planning sync**: 同步 PLAN、CONTEXT、STATE、handoff、ARCHITECTURE、
  DATA-MODEL、TESTING 和 QA README；后续优先级前移到 W3 default connected-form B
  reference、W4 product-side energy provider 和 W5/W6 text-prior hardening。
  验证: `cargo test -p domain -p application -p api-http -p speech-analysis --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `./scripts/validate-contracts.sh`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/timeline_test.dart test/controllers_test.dart test/timeline_resource_summary_panel_test.dart test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `cargo fmt --check`、Flutter bundled `dart format --set-exit-if-changed`
  和 `git diff --check` 通过。

- 2026-06-30 22:32 CST: Phase 2.21 review backlog W1 honesty fix。
  (1) **Timing-source provenance**: `speech-analysis::sound_analysis` 的
  `RhythmToken` 现在记录 `timing_audio_supported`，只有 `ForcedAligned` /
  `AsrAligned` / `UserAdjusted` WordTiming 会把 duration/gap/rate 解释成 `Timing`
  signal source；`Estimated` timing 输出 `wordtimeline_estimated_prominence_v1`、
  `quality.timing_source = word_timeline_estimated` 和 text-prior-only provenance。
  (2) **Claim status**: stress anchors、weak groups、compression spans、phrase
  boundaries 和 listening hotspots 不再因为 estimated timing 被标成
  `AudioSupported`；estimated timing 反例不会选 phrase-scoped nucleus。
  (3) **Planning sync**: 同步 2.21 PLAN、STATE 和 handoff，把后续优先级切到 W2
  first-class WordTimeline → RhythmFrame path、W3 default connected-form rules 和
  W4 product-side energy provider。
  验证: `cargo test -p domain -p application -p speech-analysis --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `./scripts/validate-contracts.sh`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `cargo fmt --check`、Flutter bundled `dart format --set-exit-if-changed`
  和 `git diff --check` 通过。

- 2026-06-30 18:27 CST: Phase 2.21 Step 2 补齐 energy cue seam 与 no-phone
  committed fixture。
  (1) **Energy provenance seam**: `SoundAnalysisConfig` 新增 sentence-scoped
  `RhythmWordAcousticCue`，`speech-analysis::sound_analysis` 会把 word-level
  `energy_prominence` 传播到 stress anchor prominence、phrase-scoped nucleus
  selection、`generated_from = wordtimeline_timing_acoustic_prominence_v1`、
  `references.actual.source = word_timeline_duration_energy` 和
  `quality.prominence_sources`；application builder 当前显式传 `None`，等待正式
  product audio feature provider。
  (2) **No-phone JSON proof**: 新增
  `testdata/rhythm-frame-qa/fixture-no-phone-rhythm.lltimeline.json` 并纳入 committed
  manifest/scorer smoke，覆盖 `phone_evidence_coverage = 0.0`、无
  `connected_speech_refs` 但仍可消费 anchors/nuclei/weak/compression/boundary/hotspot。
  (3) **Tests/docs**: Rust 单测覆盖 energy cue provenance 与 nucleus selection；
  Python scorer 单测断言 no-phone fixture 的 coverage/source/counts；同步 STATE、
  handoff、codebase docs 和 QA README。
  验证: `cargo test -p domain -p application -p speech-analysis --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `./scripts/validate-contracts.sh`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `cargo fmt --check`、Flutter bundled `dart format --set-exit-if-changed`
  和 `git diff --check` 通过。

- 2026-06-30 18:13 CST: Phase 2.21 Step 2 先接入 WordTimeline-driven RhythmFrame
  generation boundary。
  (1) **Generator seam**: `SoundAnalysisConfig` 新增 sentence-scoped `WordTiming`
  输入，`speech-analysis::sound_analysis` 在构造 RhythmFrame L1-L3 时优先使用 active
  WordTimeline timing + dictionary/canonical syllable stress，输出
  `generated_from = wordtimeline_timing_prominence_v1` 和
  `quality.timing_source = word_timeline`；无 WordTimeline 时才退回
  `phone_timeline_transitional`。
  (2) **Application wiring**: research fixture 和 CTC phonetic-analysis builder 在生成
  `sound_analysis` 前读取 active WordTimeline 的当前句 timings 并传入 generator，
  让 API refresh/export 产生的 JSON 开始走 WordTimeline-first L1-L3 substrate。
  (3) **No-phone proof**: 新增 Rust 单元测试，证明 observed CTC phone evidence absent
  时仍能从 WordTimeline + canonical stress 生成 anchors、phrase-scoped nuclei、weak groups、
  compression spans 和 phrase boundaries；CTC phone evidence coverage 保持 `0.0`。
  (4) **Planning sync**: 同步 STATE、handoff 和 ARCHITECTURE；下一刀继续把 RMS
  energy/loudness cue 从 experiment harness 接入 product-side generator。
  验证: `cargo test -p speech-analysis --quiet`、`cargo test -p application --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、`python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `./scripts/validate-contracts.sh` 通过。

- 2026-06-30 18:00 CST: Phase 2.21 Step 1 重写 `RhythmFrame` contract 到 audible
  structure v1。
  (1) **Contract/model**: `crates/domain/src/sound_analysis.rs`、OpenAPI 和 Flutter
  typed model 新增 A/B/C `references`、`RhythmSignalSource`、`RhythmEvidenceClass`、
  `RhythmClaimStatus`、prominence cues、phrase-scoped `nuclei`、
  `connected_speech_refs` 和 signal-source aware `quality`。
  (2) **Generator bridge**: 当前 `speech-analysis` 输出改为
  `legacy_phone_timing_adapter_v1` / `phone_timeline_transitional`，以新字段表达
  predicted vs audio-supported provenance；CTC phone evidence 只通过 L4
  connected-speech refs/hotspots 暴露，不再作为 L1-L3 contract truth。
  (3) **UI/evaluation/fixtures**: 字幕 rhythm ribbon 和 diagnosis card 显示 nucleus 与
  provenance；RhythmFrame QA scorer 和 Helsinki scorer 输出 signal source / evidence
  class 汇总；committed RhythmFrame/Helsinki fixtures 替换为 2.21 shape，不保留 v0
  `quality.timing_source = phone_timeline` 假设。
  (4) **Planning sync**: 同步 `.planning/STATE.md`、handoff 和 codebase
  ARCHITECTURE/DATA-MODEL/TESTING，把 Phase 2.21 下一步改为 WordTimeline +
  duration/energy generation boundary。
  验证: `cargo test -p domain -p speech-analysis --quiet`、`cargo test -p domain -p application --quiet`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、`python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`、
  `./scripts/validate-contracts.sh`、`cargo fmt --check`、Flutter bundled `dart format --set-exit-if-changed`
  和 `git diff --check` 通过。

- 2026-06-30 17:37 CST: 将 actual audible structure contract 从 Phase 2.20 中拆出为
  独立 Phase 2.21。
  (1) **New phase**: 新增
  `.planning/phases/2.21-audible-structure-architecture/2.21-CONTEXT.md`、
  `2.21-PLAN.md` 和 `2.21-AUDIBLE-STRUCTURE-MODEL.md`，单独推进 audible-structure
  架构锁、RhythmFrame contract rewrite、WordTimeline + duration/energy substrate 和
  provenance model。
  (2) **Compatibility decision**: 明确旧 `RhythmFrame` v0、旧 fixture、旧本地 artifact
  兼容性不再阻塞本 phase；正确 structure 优先。
  (3) **Model normalization**: 将 rhythm group/foot 改为可吸附前置或后置 weak material，
  将 default connected form 定义为 ranked/contextual variants，将 nucleus 改为 phrase-scoped
  candidate 并允许低证据 abstain，同时加入 syllable timing seam。
  (4) **Planning sync**: 同步 `STATE.md`、`ROADMAP.md` 和 handoff，把 Phase 2.20 定位为
  UI/实验/评测铺垫，把 Phase 2.21 设为当前结构主线。
  验证: documentation-only phase split, `git diff --check` 通过。

- 2026-06-30 13:41 CST: 为 Phase 2.20 D -> F 路线补上 duration/RMS manual QA
  对比实验工具。
  (1) **Experiment harness**: 新增 `scripts/prepare-rhythm-acoustic-qa.py`，
  读取 manifest / LLTimeline / 本地音频，按句输出 current CTC-derived
  `RhythmFrame`、active WordTimeline duration/rate 特征和 per-word RMS energy/loudness
  对比；非 wav 媒体通过本机 `ffmpeg` 解码，所有新 evidence 标为
  `heuristic_proxy` / `manual_product_qa_input`，不写回产品资源。
  (2) **Manual QA template**: 脚本支持 `--emit-template` 输出兼容现有
  RhythmFrame manual annotation schema 的 JSONL，并把三路系统候选放入
  `system_compare`，用于 5-10 句人工听感标注。
  (3) **Tests/docs**: 新增 `scripts/test_prepare_rhythm_acoustic_qa.py`，用合成 wav
  fixture 覆盖 active WordTimeline、current RhythmFrame、duration/rate candidate、
  RMS prominence candidate 和 template CLI；同步 Phase 2.20 evaluation、STATE 和
  handoff。
  验证: `python3 -m py_compile scripts/prepare-rhythm-acoustic-qa.py scripts/test_prepare_rhythm_acoustic_qa.py`、
  `python3 scripts/test_prepare_rhythm_acoustic_qa.py`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/prepare-rhythm-acoustic-qa.py --manifest testdata/sound-line-real-media/manifest.jsonl --case-id p217-brooklyn-news-001 --limit 1`
  的等价 import smoke（1 句 scored，ffmpeg 音频加载成功，WordTimeline timing present）、
  `git diff --check` 通过。
- 2026-06-30 21:05 CST: 收口修复——移除 `test/builder_test.dart` 冗余的
  `package:flutter/foundation.dart` import（`material.dart` 已提供 `@immutable`），
  全项目 `flutter analyze` 恢复 0 issue。收口验证：`flutter analyze` 干净、
  `flutter test`（115）、`cargo test -p api-http -p persistence-sqlite` 全绿。

- 2026-06-30 20:52 CST: 兑现 A1——用新解锁的 transport seam 为两个 workflow controller
  补测试（此前因 `LocalApi` 不可注入完全无法单测）。
  (1) **`learning_workflow_controller_test.dart`**（7 测试）：`refreshDiagnosis` 的
  generation guard——happy、null cue 清空、**新请求超越时丢弃 stale 结果**、切换 cue 后
  丢弃、diagnose 错误映射为 null；`loadPhraseCandidates` 经 `LocalApi.withTransport`
  端到端加载与 null-api 清空。
  (2) **`speech_enhancement_workflow_controller_test.dart`**（2 测试）：
  `loadTimelineResource` 降级——4 个子资源全失败→`unavailable`、部分失败→warning 且不
  误报 unavailable。
  验证: `flutter analyze`（0 issue）、`flutter test`（106→115 全绿）。

- 2026-06-30 20:30 CST: 收口 Tier A 测试，并修复架构债 A1（`LocalApi` transport 非注入），
  这是第一处"架构修复解锁测试"的闭环。
  (1) **A1 seam（生产代码，行为不变）**：`apps/desktop/lib/services/api_service.dart`
  抽出 `ApiTransport` typedef + `LocalApi.withTransport(...)` 测试构造器；`_request`
  （79 个调用点）改走 `_transport ?? _httpClientTransport`，默认实现保留原样 header/请求
  逻辑。生产路径字节级不变；SSE 与上传/下载 3 处特殊 `_client` 裸调暂留。
  (2) **解锁的测试**：新增 `apps/desktop/test/api_service_transport_test.dart`（3 测试）：
  GET 经 seam 解码、非 2xx → `HttpException`、PUT body 编码经 seam 转发。
  (3) **文档**：`CONCERNS.md` A1 标记已修复（§1/§6），记录后续补方法级/controller 测试；
  `TESTING.md` 同步。
  验证: `flutter analyze`（api_service + 新测试，0 issue）、`flutter test`（103→106 全绿）。
  合并摩擦评估：main（Phase 2.21 韵律）未触及 `api_service.dart` 及本 worktree 测试目标，
  唯一保证冲突是 CHANGELOG.md（琐碎可解）。

- 2026-06-30 20:05 CST: Tier A 续作——补 SQLite 迁移失败恢复刻画测试（CONCERNS §2/§3
  点名的脆弱区，至今无自动化）。新增
  `crates/persistence-sqlite/tests/migration_recovery_test.rs`（4 测试）：
  (1) 升级落后版本旧库时创建 `<path>.pre-migration.bak`，备份保留迁移前版本与内容；
  (2) 全新库（路径不存在）不创建备份；
  (3) 重开最新版本库幂等、不再创建备份；
  (4) **迁移失败时**（预置 `media_items` 表与裸 `CREATE TABLE` 迁移 0001 冲突）原库
  完整保留在备份中可恢复，且 live 库 `user_version` 不前进。
  刻画当前真实行为，作为后续迁移系统重构的安全网。
  验证: `cargo test -p persistence-sqlite --test migration_recovery_test`（4/4）。

- 2026-06-30 14:34 CST: Tier A 续作——api-http 集成测试覆盖 lexical entry 学习核心
  生命周期。`api_integration_test.rs` 新增 1 条：PUT `/v1/lexical-entries` upsert（word，
  status=unknown_meaning）→ GET 列表按 language/kind 命中 → GET `/{id}` 详情往返 →
  PUT `/{id}/learning-content` 持久化 user_definition / personal_note。新增 `put_json` 助手。
  验证: `cargo test -p api-http --test api_integration_test`（11/11）。

- 2026-06-30 14:28 CST: Tier A 续作——补 Flutter 状态层 widget 测试，并记录 A1 对
  workflow controller 测试的硬阻塞。
  (1) **Store builder 测试**: 新增 `apps/desktop/test/builder_test.dart`，覆盖
  `StoreBuilder` / `StoreBuilder2` 的选择性重建（无关字段不重建、选中字段才重建、
  equal-state no-op，4 测试）。
  (2) **A1 证据加固**: `CONCERNS.md` §1 记录 `LocalApi` 只有私有构造 `LocalApi._`、
  唯一入口 `connect()` 起真实 sidecar，测试连子类伪造都做不到；`LearningWorkflowController`
  / `SpeechEnhancementWorkflowController` 直接持有 `LocalApi`，单测被此 seam 挡死，
  确认延后到 A1 修复后。
  验证: `flutter test test/builder_test.dart`（4/4）。

- 2026-06-30 14:21 CST: 在测试体系建设期对架构做证据化审计并记录到 `CONCERNS.md`，
  决定走"测试优先安全网"——先记录、继续铺测试、收口后再统一修架构。
  (1) **新增待修复登记**（§6）：A1 `LocalApi` transport 非注入（`api_service.dart:49`，
  挡住 Tier A 客户端单测，该项测试延后到 seam 修复后）；A2 `build_word_timeline` /
  `save_word_timeline_snapshot` 参数过多（`application/src/lib.rs:213`/`:292`，clippy
  `too_many_arguments`）；A3 workspace clippy warning 漂移；A4 `speech-analysis` 拆 crate、
  A5 `domain/lib.rs` 拆分（结构性大改，先出评审再动）。
  (2) **已证伪**：`AppServices::new` 8 参数是接口隔离（ISP），非 smell，不修。
  (3) **刷新过期条目**：§3 测试缺口表中 application/api-http 集成测试更新为"🟡 部分"，
  指向 `crates/api-http/tests/api_integration_test.rs`。
  验证: documentation-only，`git diff --check` 通过。

- 2026-06-30 14:07 CST: Tier A 续作——扩 `api-http` 全栈集成测试路由覆盖，
  仍为纯测试改动。`api_integration_test.rs` 新增 3 条：
  (1) **LLTimeline 资源契约**: 导入 `testdata/lltimeline/v1-minimal.lltimeline.json`
  完整文档 → 200 SubtitleTrack，并验证捆绑的 word timeline 随文档持久化。
  (2) **Word timeline 生命周期**: `create`（candidate）→ `activate`（active），
  覆盖播放器消费的核心资源激活路径。
  (3) **Diagnosis 端点**: 对导入字幕的句子返回结构良好的 `SentenceDiagnosis`。
  验证: `cargo test -p api-http --test api_integration_test`（10/10）；
  测试文件零新增 clippy warning（workspace 既有 lint 漂移与本改动无关）。

- 2026-06-30 14:01 CST: 启动测试体系建设 Tier A（worktree `testing-system-buildout`），
  落地跨语言后端栈与前端状态/推送层的基础测试，零生产代码改动。
  (1) **Rust 全栈集成**: 新增 `crates/api-http/tests/api_integration_test.rs`，
  以真实 `router(ApiState::new(...))` + `SqliteRepository::in_memory()`、`tower::oneshot`
  进程内驱动 `api-http → application → persistence` 整栈（鉴权拒绝、health、media
  注册/读取/404、字幕导入往返、archive/restore/delete 生命周期，7 测试）。
  (2) **Flutter SSE 推送核心**: 新增 `apps/desktop/test/backend_event_coordinator_test.dart`，
  覆盖 `BackendEventCoordinator` 全部分发分支（service-started、转写 job completed/in-progress/
  跨 media、音素 job primary/非 primary、lexical-entry 转发、未知事件 no-op，9 测试）。
  (3) **Flutter 状态容器**: 新增 `apps/desktop/test/store_test.dart`，覆盖 `Store<T>`
  selector 身份 memoize、字段级精准通知、equal-state no-op、replace 刷新（6 测试）。
  (4) **路线决策**: `api_service.dart`（`dart:io HttpClient`，非注入式）的全栈消费契约
  归入 Tier B 真实 sidecar E2E，本阶段不为凑覆盖改造生产客户端；`.planning/codebase/TESTING.md`
  第 9 节记录 Tier A/B/C 建设路线与缺口状态。
  验证: `cargo test -p api-http`（7/7）、`flutter test`（84→99 全绿）、`flutter analyze` 干净。
  既有遗留: `api-http` lib `lib.rs:823` 有 3 个既有 clippy let-chains warning（非本次引入），
  `--strict` 下会红，留待单独清理。

- 2026-06-30 13:29 CST: Phase 2.20 路线复盘后更新交接文档，准备新 session 继续推进。
  (1) **Route correction**: 新增
  `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ROUTE-CORRECTION.md`，
  明确 Phase 2.20 的目标是 actual audible structure，而不是 default predicted reading；
  `RhythmFrame` contract/UI/QA 继续保留，但 generator 主线从 CTC-derived rhythm skeleton
  迁移到 forced-aligned WordTimeline + duration/rate + RMS energy/loudness，F0/pitch reset
  作为校准后的正式候选。
  (2) **Acoustic path revision**:
  `2.20-ACOUSTIC-FEATURE-PATH.md` 已改为路线修订说明，重新定位
  `pre_boundary_lengthening` 为 fallback/diagnostic `heuristic_proxy`，不再把本地缺少
  `librosa`/Parselmouth 等包当作不上 production-side acoustic prosody 的理由。
  (3) **Handoff**: 重写 `.planning/handoff/continue-here.md`，记录最新 20 句
  Helsinki/LibriTTS diagnostic（stress anchor F1 `0.574949`、phrase boundary F1
  `0.210145`、boundary evidence `pause=218` / `pre_boundary_lengthening=17`）和下一步
  D -> F 对比实验：current CTC-derived RhythmFrame vs forced-aligned WordTimeline +
  duration/rate vs WordTimeline + RMS energy。
  (4) **Planning sync**: 同步 `2.20-PLAN.md`、`2.20-ALGORITHM-METRICS-RESEARCH.md`、
  `2.20-EVALUATION.md` 和 `.planning/STATE.md`，明确 CTC phone evidence 降级为
  flapping/deletion/weak-form/phone-mismatch 等 segmental evidence，不再当 rhythm skeleton。
  验证: documentation-only handoff update, `git diff --check` 通过。

- 2026-06-30 12:57 CST: 将 Phase 2.20 算法/指标原则写入 agent 入口，并让
  Helsinki/LibriTTS scorer 输出基准上下文。
  (1) **Agent rule**: `AGENT.md` 新增 Algorithms And Metrics 原则，明确项目已有数据、
  小样本 smoke、自动标签和当前指标不默认视为正确答案；算法、指标和阈值应尽量来自
  published research、corpus annotation convention、reported tool baseline 或 manual product
  QA；有依据时可以大胆试，但要记录 `gold` / `silver_label` / `heuristic_proxy` /
  `manual_product_qa` / `coverage` evidence class。
  (2) **Benchmark context**: `scripts/evaluate-helsinki-prosody.py` 在每个报告中输出
  `benchmark_context`，标明 Helsinki/LibriTTS 是 `weak_prosody_regression` /
  `silver_label`，记录 prominence/boundary label 语义、Talman et al. 2019 BERT text-model
  prominence baselines（2-way accuracy `0.832`、3-way accuracy `0.686`）和不能直接与
  end-to-end audio RhythmFrame F1 比较的 caveat。
  (3) **Docs/tests**: 同步 rhythm-prosody README、Phase 2.20 evaluation/plan 和
  `.planning/STATE.md`，并让 Helsinki scorer 单测校验报告上下文。
  验证: `python3 -m py_compile scripts/evaluate-helsinki-prosody.py scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/evaluate-helsinki-prosody.py --prosody-dir /Users/shadow/prosody --split dev --limit 3 --lltimeline-manifest .tmp/helsinki-libritts-rhythm-dev-smoke/manifest.jsonl`、
  `git diff --check` 通过。

- 2026-06-30 10:40 CST: 为 Phase 2.20 补齐算法/指标校准原则并跑通首个
  Helsinki/LibriTTS 真实 smoke。
  (1) **Research calibration**: 新增
  `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ALGORITHM-METRICS-RESEARCH.md`，
  明确当前项目指标、小样本 smoke、Helsinki automatic labels 都只是 diagnostic/silver
  signal；后续算法与 gate 需要对齐 published prosody/phonetics baselines、corpus annotation
  convention 或 manual product QA。
  (2) **Local smoke**: 使用 `.tmp/helsinki-libritts-rhythm-dev-smoke/manifest.jsonl`
  跑通本地 API refresh，3/3 LibriTTS/Helsinki dev 样本生成 `sound_analysis.rhythm_frame`；
  diagnostic Helsinki silver-label score 为 stress anchor F1 `0.827586`、phrase boundary F1
  `0.285714`。该结果只记录为 pipeline diagnostic，不作为 closeout gate。
  (3) **Scorer/algorithm hygiene**: `scripts/evaluate-helsinki-prosody.py` 修正 LLTimeline
  raw token index 到 word index 的映射，并在 API 导入重映射 sentence id 后回退到文本匹配；
  `speech-analysis` 的默认 stress anchor 规则避免把 function words 作为主 anchor，并扩展
  常见英语 function-word 列表。
  验证: `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo test -p speech-analysis sound_analysis --quiet`、
  `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo fmt --check`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_helsinki_libritts_benchmark.py`、
  `python3 scripts/evaluate-helsinki-prosody.py --prosody-dir /Users/shadow/prosody --split dev --limit 3 --lltimeline-manifest .tmp/helsinki-libritts-rhythm-dev-smoke/manifest.jsonl`
  通过。

- 2026-06-30 10:20 CST: 打通 Helsinki/LibriTTS 本地 benchmark baseline 准备链路。
  (1) **Prep script**: 新增 `scripts/prepare-helsinki-libritts-benchmark.py`，可从 Helsinki
  Prosody labels 选择小样本，定位 LibriTTS `.wav`，生成 ignored baseline `.lltimeline.json`
  和 dual-use manifest；支持 extracted split directory，也支持
  `/Users/shadow/Downloads/dev-clean.tar.gz` / `test-clean.tar.gz` 这类 split archive，只抽取
  selected wav 到 `.tmp/.../audio`。
  (2) **Evaluator fix**: `scripts/evaluate-helsinki-prosody.py` 在 baseline artifact 尚无
  `phone_timelines` 时会基于 `segments` 识别句子，并报告 `missing_rhythm_frame`，不再误报
  `missing_sentence`。
  (3) **Tests/docs**: 新增 `scripts/test_prepare_helsinki_libritts_benchmark.py`，覆盖目录输入、
  archive 输入、missing audio 和 baseline LLTimeline shape；同步 rhythm-prosody README、
  Phase 2.20 evaluation/plan、`.planning/STATE.md` 和 `.planning/codebase/TESTING.md`。
  验证: `python3 -m py_compile scripts/evaluate-helsinki-prosody.py scripts/test_evaluate_helsinki_prosody.py scripts/prepare-helsinki-libritts-benchmark.py scripts/test_prepare_helsinki_libritts_benchmark.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_prepare_helsinki_libritts_benchmark.py`、
  `python3 scripts/prepare-helsinki-libritts-benchmark.py --prosody-dir /Users/shadow/prosody --libritts-archive /Users/shadow/Downloads/dev-clean.tar.gz --split dev --limit 3 --output-dir .tmp/helsinki-libritts-rhythm-dev-smoke`、
  `python3 scripts/evaluate-helsinki-prosody.py --prosody-dir /Users/shadow/prosody --split dev --limit 3 --lltimeline-manifest .tmp/helsinki-libritts-rhythm-dev-smoke/manifest.jsonl --include-sentences`
  通过。

- 2026-06-30 09:55 CST: 建立 Phase 2.20 Helsinki/LibriTTS weak-label prosody benchmark adapter。
  (1) **Scorer**: 新增 `scripts/evaluate-helsinki-prosody.py`，解析 Helsinki Prosody split
  文件，并用 prominence labels 评估 `RhythmFrame.stress_anchors`，用 word-boundary labels
  评估 `RhythmFrame.phrase_boundaries`；支持 `--prosody-dir`、`--labels`、
  `--lltimeline-manifest`、`--lltimeline-dir`、threshold 和 quality gate 参数。
  (2) **Fixture/tests**: 新增 `testdata/rhythm-prosody-benchmarks/`，包含可提交的
  Helsinki-style label fixture、LLTimeline fixture、manifest 和 README；新增
  `scripts/test_evaluate_helsinki_prosody.py` 覆盖 label parsing、RhythmFrame matching、
  missing-rhythm 状态和 committed fixture CLI gate。
  (3) **Docs**: 同步 Phase 2.20 benchmark research/evaluation/plan、`.planning/STATE.md`
  和 `.planning/codebase/TESTING.md`，明确 Helsinki labels 是 stress/boundary silver-label
  regression，不替代 weak group/compression/hotspot 的 manual product QA。
  验证: `python3 -m py_compile scripts/evaluate-helsinki-prosody.py scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/test_evaluate_helsinki_prosody.py`、
  `python3 scripts/evaluate-helsinki-prosody.py --labels testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt --lltimeline-manifest testdata/rhythm-prosody-benchmarks/fixture-manifest.jsonl --min-scored-sentences 1 --min-anchor-f1 1.0 --min-boundary-f1 1.0 --fail-on-quality-gate`、
  `python3 scripts/evaluate-helsinki-prosody.py --prosody-dir /Users/shadow/prosody --split dev --limit 5`
  通过。

- 2026-06-30 00:00 CST: 重新组织 Phase 2.20 benchmark 方向为 stress/rhythm-first。
  (1) **Research**: 新增
  `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-BENCHMARK-RESEARCH.md`，
  调研 Helsinki Prosody/LibriTTS、BU Radio Speech、Rhythm and Pitch Corpus、
  Aix-MARSEC/ProPOSEC、Buckeye、TED-LIUM、IViE、NXT Switchboard、Wav2ToBI 和
  ToBI references，并明确没有单一公开集能覆盖完整 learner-facing RhythmFrame 产品链路。
  (2) **Evaluation pivot**: `2.20-EVALUATION.md` 增加 benchmark roles：
  `evidence_quality`、`weak_prosody_regression`、`human_prosody_gold`、
  `product_listening_qa`、`robustness_probe`。
  (3) **Plan sync**: `2.20-PLAN.md` 将 TIMIT 调整为 evidence-layer sanity，
  将 Helsinki/LibriTTS 设为首选公开弱标签回归方向，将 BU/RaP/Aix 设为可选 human
  prosody gold，将 Buckeye/TED/product media 保留为 weak group/compression/hotspot
  产品 QA gate。
  验证: documentation-only change, `git diff --check` 通过。

- 2026-06-29 20:16 CST: 为 Phase 2.20 字幕层 rhythm 模式补齐 expected pronunciation reference。
  (1) **UI**: 新增 `ExpectedPronunciationReference`，按词展示词典 IPA，并按当前 token
  高亮当前词；无逐词 variant 时降级显示句级 `display_ipa`。
  (2) **Rhythm surface**: 主播放器在 sound pattern `rhythm` 模式中把 expected pronunciation
  放在 RhythmFrame 上方，使“预期读音”和“真实听感节奏”同屏出现；`phones` 模式仍保留为
  phone evidence 证据层。
  (3) **Localization/tests**: 新增中英本地化文案，`phoneme_ribbon_test.dart` 覆盖 expected
  reference 的词级 IPA 和 tooltip。
  验证: `$HOME/.local/share/flutter/bin/dart format --set-exit-if-changed apps/desktop/lib/main.dart apps/desktop/lib/localization.dart apps/desktop/lib/widgets/subtitle/expected_pronunciation_reference.dart apps/desktop/test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter analyze`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test`
  通过。

- 2026-06-29 20:07 CST: 为 Phase 2.20 字幕层 sound pattern 增加 rhythm/phones 就地快切。
  (1) **UI**: 新增 `SoundPatternModeToggle` 图标控件，在字幕层声音时间带旁用 rhythm /
  phone evidence 两个图标切换显示模式，不需要进入设置弹窗。
  (2) **State wiring**: 主播放器把快切接入现有 `sound_pattern_display_mode` 持久化设置，
  保持默认 rhythm-first，同时保留 phone evidence ribbon 作为可切换证据层。
  (3) **Tests**: `phoneme_ribbon_test.dart` 覆盖图标快切只在切到另一模式时触发回调。
  验证: `$HOME/.local/share/flutter/bin/dart format --set-exit-if-changed apps/desktop/lib/main.dart apps/desktop/lib/widgets/subtitle/sound_pattern_mode_toggle.dart apps/desktop/test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter analyze` 通过。

- 2026-06-29 20:03 CST: 为 Phase 2.20 字幕层 RhythmFrame ribbon 增加 cue loop 交互。
  (1) **UI**: `RhythmFrameRibbon` 新增可选 `onLoopCue` 回调，rhythm cue chip 在有回调时变为
  可点击目标，并保留 tooltip/semantics。
  (2) **Playback wiring**: 字幕层 rhythm 模式接入现有 source loop 逻辑，点击 anchor/weak/
  compression/hotspot chip 可循环播放对应听感区间；phone evidence ribbon 的原有 loop 行为不变。
  (3) **Tests**: `phoneme_ribbon_test.dart` 新增 rhythm cue loop callback 覆盖。
  验证: `$HOME/.local/share/flutter/bin/dart format --set-exit-if-changed apps/desktop/lib/widgets/subtitle/rhythm_frame_ribbon.dart apps/desktop/lib/main.dart apps/desktop/test/phoneme_ribbon_test.dart`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart`
  通过。

- 2026-06-29 20:02 CST: 为 Phase 2.20 RhythmFrame QA/scorer 增加仓库内可重复运行的
  committed fixture gate。
  (1) **Fixture**: 新增 `testdata/rhythm-frame-qa/fixture-manifest.jsonl`、
  `fixture-rhythm.lltimeline.json` 和 `fixture-annotations.jsonl`，用两句合成
  LLTimeline 覆盖 stress anchors、weak groups、compression spans、phrase boundaries
  与 listening hotspots，不依赖本地真实媒体或 ignored `.tmp` artifacts。
  (2) **Regression**: `scripts/test_evaluate_rhythm_frame.py` 新增 CLI smoke，验证
  strict annotation validation、`--fail-on-quality-gate`、1.0 rhythm coverage、2 条
  annotated sentences、0 misleading/unsupported hotspot gates。
  (3) **Docs**: 同步 `testdata/rhythm-frame-qa/README.md`、Phase 2.20 evaluation/plan、
  `.planning/STATE.md` 和 `.planning/codebase/TESTING.md`，明确 committed fixture 与
  本地真实媒体 QA 的边界。
  验证: `python3 -m py_compile scripts/evaluate-rhythm-frame.py scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/evaluate-rhythm-frame.py --manifest testdata/rhythm-frame-qa/fixture-manifest.jsonl --annotations testdata/rhythm-frame-qa/fixture-annotations.jsonl --strict-annotations --min-rhythm-coverage 1.0 --min-annotated-sentences 2 --min-overall-useful-rate 1.0 --max-hotspot-misleading-rate 0.0 --max-hotspot-unsupported-rate 0.0 --fail-on-quality-gate`
  通过。

- 2026-06-29 19:40 CST: 建立 Phase 2.20 RhythmFrame QA/scorer 初版。
  (1) **Manual QA schema**: 新增 `testdata/rhythm-frame-qa/`，包含 annotation schema、
  sample JSONL 和标注/评分说明，覆盖 stress anchors、weak groups、compression spans、
  phrase boundaries、listening hotspots 与 `correct/useful_but_incomplete/unclear/misleading/unsupported`
  rubric。
  (2) **Scorer**: 新增 `scripts/evaluate-rhythm-frame.py`，可读取 Phase 2.17 manifest 和
  local-only LLTimeline artifacts，输出 `rhythm_frame` 覆盖率、每句结构摘要、manual label
  matching、hotspot score distribution 和 `summary.manual_qa` 聚合；支持 `--emit-template`
  生成标注模板，并支持 `--strict-annotations` 校验 duplicate、invalid score 和 unknown
  sentence target。新增 closeout quality gates：`--min-rhythm-coverage`、
  `--min-annotated-sentences`、`--min-overall-useful-rate`、
  `--max-hotspot-misleading-rate`、`--max-hotspot-unsupported-rate` 和
  `--fail-on-quality-gate`。
  (3) **Baseline**: 当前旧 `.tmp/sound-line-real-media` artifacts 为 8 cases / 51 phone timelines /
  0 rhythm frames，符合预期，因为这些 artifact 生成早于 Phase 2.20 `rhythm_frame` 字段；本机
  smoke 重跑 `p217-brooklyn-news-001 --sentence-limit 1` 后 scorer 可读到 1 条 refreshed
  RhythmFrame（ignored `.tmp` artifact，不提交）。
  验证: `python3 -m py_compile scripts/evaluate-rhythm-frame.py scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/test_evaluate_rhythm_frame.py`、
  `python3 scripts/evaluate-rhythm-frame.py --manifest testdata/sound-line-real-media/manifest.jsonl`、
  `PATH="/opt/homebrew/opt/rustup/bin:$PATH" python3 scripts/run-sound-line-real-media-case.py --case-id p217-brooklyn-news-001 --sentence-limit 1`
  通过。

- 2026-06-29 15:28 CST: 将 Phase 2.20 RhythmFrame 推进到字幕层主显示。
  (1) **Subtitle layer**: 新增 `RhythmFrameRibbon`，在字幕下方直接展示 listening rhythm
  时间线、stress anchors、weak groups、compression spans、listening hotspots 和当前播放位置。
  (2) **Mode switch**: `sound_pattern_display_mode` 持久化为 `rhythm` / `phones` 两种模式；
  声音模式时间带默认 rhythm-first，原 phone evidence ribbon 保留为可切换证据层。
  (3) **Settings/UI**: 设置弹窗新增“声音时间带模式”，中英本地化同步；右侧诊断卡继续保留
  compact rhythm detail。
  验证: `dart format --set-exit-if-changed`、`git diff --check`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter analyze`、
  `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test`、
  `cargo fmt --check`、`cargo test --workspace --quiet`、`./scripts/validate-contracts.sh` 通过。

- 2026-06-29 15:07 CST: 推进 Phase 2.20 RhythmFrame v0 纵切片。
  (1) **Resource shape**: `SoundAnalysis` 新增可选 `rhythm_frame`，OpenAPI 同步
  `RhythmFrame` / stress anchors / weak groups / compression spans / phrase boundaries /
  listening hotspots / quality schema；`SoundLearningPhone` 保留可选 lexical stress。
  (2) **Algorithm**: `speech-analysis::sound_analysis` 生成 deterministic rhythm-first
  baseline，融合 CMUdict/fallback lexical stress、function-word grouping、phone timing
  pause/duration 和 connected-speech evidence；raw phone mismatch 不会单独生成高置信默认听感解释。
  (3) **Flutter**: typed timeline model 解析 `rhythm_frame`，诊断卡在 phone evidence 前展示
  compact rhythm-first 区块（anchors、weak groups、compressed spans、hotspots、confidence）。
  (4) **Planning sync**: 更新 `.planning/STATE.md` 与 codebase 架构/数据模型/测试事实源。
  验证: `cargo test --workspace --quiet`、`./scripts/validate-contracts.sh`、
  `cd apps/desktop && flutter analyze`、`cd apps/desktop && flutter test` 通过。
  备注: `cargo clippy --workspace --all-targets -- -D warnings` 仍被既有 unrelated lint 阻塞
  （`chunk_partition.rs`、`phone_recognition.rs`、`forced_align.rs`）。

- 2026-06-29 14:37 CST: 补充 Phase 2.20 rhythm-first listening analysis 调研记录。
  新增 `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-RESEARCH.md`，
  从英语听力认知、L2 connected speech、prosody annotation、参考工具/数据集和产品形态
  判断 rhythm-first 方向基本成立但需避免把 stress-timed English 当成绝对物理定律。
  同步 `2.20-PLAN.md` 指向该 research basis。
  验证: documentation-only change, not run.

- 2026-06-29 14:32 CST: 建立 Phase 2.20 rhythm-first listening analysis 新方向。
  (1) **Product pivot**: 将真实语流分析的默认产品中心从 phone-level ribbon 调整为
  rhythm-first listening frame，优先展示 stress anchors、weak groups、compression spans、
  phrase boundaries 和 listening hotspots；phone-level expected/observed alignment 保留为
  evidence layer 和长期模型质量工作。
  (2) **Phase docs**: 新增
  `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-CONTEXT.md`、
  `2.20-PLAN.md` 和 `2.20-EVALUATION.md`，明确 UI surface、RhythmFrame resource shape、
  deterministic baseline、benchmark/manual QA 分层和 pipeline bottleneck attribution。
  (3) **Planning sync**: 同步 `.planning/PROJECT.md`、`.planning/REQUIREMENTS.md`、
  `.planning/ROADMAP.md`、`.planning/codebase/TESTING.md` 和 `.planning/STATE.md`，
  新增 RHY-001 至 RHY-008 需求，并把 Phase 2.19 phone benchmark scoring 定位为底层
  evidence-quality 支撑。
  验证: documentation-only change, not run.

- 2026-06-29 10:26 CST: 启动 Phase 2.19 real benchmark scoring 初始评估。
  (1) **Scorer**: 新增 `scripts/evaluate-sound-line-benchmarks.py`，从 Phase 2.17 manifest
  和 ignored `.tmp` artifacts 读取结果，并对 TIMIT `.PHN`、Buckeye `.phones`、TED-LIUM `.stm`
  做本地 reference 对比。
  (2) **初始结果**: TED-LIUM transcript/timing 对齐为 exact；Buckeye s0201a/s0301a 初始
  PER 分别约 0.304/0.352；Buckeye s0101a 与 TIMIT Phase 2.17 artifact 暴露明显窗口/映射问题，
  其中 TIMIT 小窗口 PER 约 0.874，显著差于历史 fb-espeak TIMIT dev baseline 0.304636。
  (3) **规划**: 新增 `.planning/phases/2.19-real-benchmark-scoring/2.19-PLAN.md` 和
  `2.19-INITIAL-RESULTS.md`，明确后续要排查 TIMIT sentence window、espeak symbol mapping、
  Buckeye lead-in filtering、boundary metrics 和 product-media manual listening precision。
  验证: `python3 -m py_compile scripts/evaluate-sound-line-benchmarks.py`、
  `python3 scripts/evaluate-sound-line-benchmarks.py --manifest testdata/sound-line-real-media/manifest.jsonl`、
  `python3 scripts/phonetic-eval.py score testdata/phonetic-analysis/reference-dev-v1-content-only.jsonl testdata/phonetic-analysis/prediction-fb-espeak-timit-mapped-v1.jsonl` 通过。

- 2026-06-29 10:15 CST: 收口 Phase 2.17 real-media sound-line QA。
  (1) **Headless runner**: 新增 `scripts/run-sound-line-real-media-case.py`，通过临时
  `api-http` + SQLite 执行 register media、LLTimeline import、句级 CTC phonetic job、poll 和
  export，不再依赖手点 UI 生成 PhoneTimeline。
  (2) **Runtime 修复**: CTC sidecar 启动环境现在自动注入 Homebrew `PATH` 和可用的
  `PHONEMIZER_ESPEAK_LIBRARY`；修复 `phonetic_alignment::backtrace` 在 detected index zero
  deletion 路径上的 `usize` 下溢 panic，避免 background job 卡在 `analyzing`。
  (3) **Artifact refresh**: 8 个 Phase 2.17 local-only 小窗口 artifacts 已刷新到 ignored
  `.tmp/sound-line-real-media/cases/`，manifest `lltimeline.sha256` 同步当前本机 artifact。
  Brooklyn / Venezuela 保留 deletion、weak_form、assimilation、flapping markers；TED-LIUM /
  Buckeye / TIMIT 不再从 raw insertion 生成 `linking` 爆炸。
  (4) **Closeout**: `2.17-CTC-MISMATCH-FINDINGS.md` 更新为 accepted findings，新增
  `2.17-CLOSEOUT.md`，同步 `2.17-PLAN.md`、`.planning/STATE.md` 和 QA README/case note。
  验证: `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo fmt --check`、
  `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo test -p speech-analysis`、
  `python3 -m py_compile scripts/run-sound-line-real-media-case.py scripts/verify-sound-line-real-media.py`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --strict-local --require-ready`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --json` 通过。

- 2026-06-29 09:35 CST: 收敛 Phase 2.17 local-only artifact 与 benchmark 评估边界。
  (1) **Artifact 边界**: 将 8 个生成的 `.lltimeline.json` 保持在 ignored
  `.tmp/sound-line-real-media/cases/`，manifest 通过 `lltimeline.local_path` 引用；repo 继续只提交
  manifest、notes、checksum 和 verifier，不提交 local-only 派生 transcript/timeline。
  (2) **Verifier**: 支持 `lltimeline.local_path`，并统一 marker playback window 阈值文案。
  `--strict-local`、`--require-ready` 和 `--json` 在当前本机 artifacts 上均通过。
  (3) **评估边界**: `2.17-PLAN.md` 明确 benchmark case 用于 pipeline vs reference/gold
  比较，product-media case 用于 UI/听感 QA；当前 Buckeye/TED-LIUM/TIMIT artifacts 暴露
  `linking` marker 爆炸，说明链路 ready 但学习质量未 ready。
  (4) **Findings**: 新增 `2.17-CTC-MISMATCH-FINDINGS.md` draft，并同步 Brooklyn 当前 family
  breakdown 与下一步过滤/去重方向。

- 2026-06-29 09:52 CST: 收紧 Phase 2.17 linking marker 生成与 verifier 质量警告。
  (1) **算法门控**: `speech-analysis::sound_analysis` 不再把 generic CTC insertion 自动提升为
  learner-facing `linking` marker；没有跨词边界上下文时只保留底层 alignment，不生成教学解释。
  (2) **Verifier 质量警告**: `verify-sound-line-real-media.py` 现在会 warning 缺少 WordTimeline 的
  phone-only artifact，以及单一 connected-speech family 占比过高的 marker 爆炸。
  (3) **重跑策略**: `2.17-PLAN.md` 与 `2.17-CTC-MISMATCH-FINDINGS.md` 明确当前 `.tmp`
  timelines 是旧逻辑 artifact，应先重跑 Brooklyn + 一个 Buckeye/TED-LIUM 代表 case，再决定是否
  全量重跑 8 个 local-only artifacts。
  验证: `cargo test -p speech-analysis sound_analysis`、`python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --strict-local`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --json`、
  `python3 -m py_compile scripts/verify-sound-line-real-media.py` 通过。

- 2026-06-28 22:58 CST: 推进 Phase 2.17 real-media QA pack 中间态。
  (1) **QA pack 骨架**: 新增 `testdata/sound-line-real-media/` README、8-case manifest
  和 case notes stub，覆盖 local news、TED-LIUM、Buckeye、TIMIT；local-only 资源只记录
  locator/checksum，不提交媒体或完整 transcript timeline。
  (2) **Verifier**: 新增 `scripts/verify-sound-line-real-media.py`，支持 default /
  `--strict-local` / `--json` / `--require-ready`，并按当前 inclusive phone range 契约从
  `sound_analysis.learning_phones` 推导 marker playback window。
  (3) **CTC sidecar 环境**: `speech-analysis` 启动 wav2vec2 phoneme sidecar 时补入常见
  Homebrew PATH，避免 Rust 子进程找不到 `espeak`。
  (4) **计划更新**: `2.17-PLAN.md` 记录当前完成项、未完成项、真实阻塞点、下一步 headless
  QA runner 方向，以及 UI E2E 当前只有组件级测试、缺少体系化端到端覆盖的判断。
  验证: `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --json`、
  `python3 scripts/verify-sound-line-real-media.py --manifest testdata/sound-line-real-media/manifest.jsonl --require-ready`
  按预期失败于 readiness、`cargo test -p speech-analysis` 通过。

- 2026-06-28 20:29 CST: 扩展 Phase 2.17 — Real Media Sound-Line QA 执行计划。
  (1) **Benchmark 分层**: 明确 TIMIT 作为 phone-level sanity check，Buckeye 作为优先
  natural connected speech benchmark，本地新闻/TED-LIUM/LibriSpeech/VCTK/Common Voice
  作为 product-like 或 supplemental regression 材料。
  (2) **可交接执行方案**: `2.17-PLAN.md` 新增 manifest schema、local-only 许可策略、
  verifier 规则、manual QA observation 模板、CTC mismatch decision table 要求、执行步骤和
  下一智能体 handoff checklist。

- 2026-06-28 19:37 CST: 落地 Phase 3.0.1 学习行为架构代码地基。
  新增 domain learning-loop 模型与 ID，application practice service、Practice / Review /
  LearningEvent repository traits，SQLite schema v15 与 `practice_sessions`、`practice_items`、
  `practice_attempts`、`review_items`、`review_attempts`、`learning_events` 表，最小
  `/v1/practice/*` 与 `/v1/review/*` API 路由，OpenAPI/generated client/contract validation
  同步，以及 persistence/API 测试。同步刷新 `.planning/codebase/ARCHITECTURE.md`、
  `.planning/codebase/DATA-MODEL.md`、`.planning/codebase/STRUCTURE.md` 和
  `.planning/codebase/STACK.md`。新增
  `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-CLOSEOUT.md` 记录后端地基收口。

- 2026-06-28 17:31 CST: 新增 Phase 3.0.1 学习行为架构地基规划。
  新增 `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-CONTEXT.md`、
  `3.0.1-ARCHITECTURE.md` 和 `3.0.1-PLAN.md`，定义 Practice / Review / LearningEvent /
  Corpus / Difficulty / LearnerProfile / Recording 边界，以及 cloze + chunk dictation 第一条
  vertical slice；同步更新 Phase 3.0 plan、`.planning/PROJECT.md`、`.planning/REQUIREMENTS.md`、
  `.planning/ROADMAP.md` 与 `.planning/STATE.md`。

- 2026-06-28 17:14 CST: 建立 Phase 3.0 英语听力学习闭环规划参考。
  新增 `.planning/phases/3.0-english-listening-learning-loop/3.0-CONTEXT.md` 和
  `.planning/phases/3.0-english-listening-learning-loop/3.0-PLAN.md`，将真实输入、
  可理解度判断、诊断、cloze/听写/字幕渐隐、听力驱动词汇、本地 YouGlish-like 语料库、
  Mandarin -> English L1-aware diagnosis、shadowing 和诊断型 dashboard 收敛为后续
  Phase 3.0 对齐依据；同步更新 `.planning/PROJECT.md`、`.planning/REQUIREMENTS.md`、
  `.planning/ROADMAP.md` 与 `.planning/STATE.md`。

- 2026-06-28 16:26 CST: 同步 Phase 2.18 后的入口文档。
  更新 `AGENT.md`、`.planning/PROJECT.md`、`.planning/REQUIREMENTS.md`、
  `.planning/ROADMAP.md`、`.planning/MAINTENANCE.md` 和 `.planning/STATE.md`：
  当前阶段/版本改为 Milestone 2 / 0.7.0，学习资产权威模型改为
  `LexicalEntry + LexicalUnit + LearningStatus`，旧 `WordProfile` / `WordObservation`
  兼容路径不再作为 active path；phase 完成模板统一为 `X.X-CLOSEOUT.md`。

- 2026-06-28 16:19 CST: Phase 2.18 正式收口。
  新增 `.planning/phases/2.18-codebase-architecture-refactor/2.18-CLOSEOUT.md`，
  将 `2.18-PLAN.md` 标记为 `COMPLETED`，并更新 `.planning/STATE.md` 的当前阶段、兼容性决策、
  剩余非阻塞后续项和收口记录。删除过期 `.planning/DEFERRED-ITEMS.md`；跨阶段遗留项以后以
  各 phase closeout、`.planning/STATE.md` 和后续 phase plan 为准。
  当前未彻底完成但不阻塞收口的事项：`main.dart` media/session/resource wiring 继续拆分、
  route manifest 共享事实源、显式 UI async state、`speech-analysis` 子域拆分、真实媒体 QA。

- 2026-06-28 08:59 CST: Phase 2.18 前端 typed payload 与 workflow 收口。
  (1) **Typed payload**: Flutter 新增/补齐 `DictionaryLookupBundle`、`WordPronunciation`、
  `PronunciationAnalysis`、`PhoneticAnalysis`、`PhoneticFinding` 等 DTO，`LearningController` /
  `SubtitleController` 不再以裸 `Map<String, dynamic>` 保存 dictionary、pronunciation、phonetic-analysis
  业务状态。
  (2) **Widget boundary**: `WordLearningPanel` 和 `DiagnosisCard` 改为消费 typed DTO。
  (3) **Workflow extraction**: phrase candidate、word entry load/open/update、lexical observation、
  learning-content save 下沉到 `LearningWorkflowController`；timeline resource refresh、word timing、
  sentence pronunciation、chunk partition、phone/sound-pattern analysis 加载下沉到
  `SpeechEnhancementWorkflowController`，`main.dart` 进一步收缩为 UI wiring/status。
  验证: `flutter analyze apps/desktop`、`flutter test --reporter compact` 通过。

- 2026-06-27 18:20 CST: Phase 2.18 主路径重构完成候选。
  (1) **旧学习资产路径删除**: active code path 收敛为 `LexicalEntry + LexicalUnit`；
  旧 word-profile domain/repository/API/OpenAPI/generated client/script/Flutter fixture 路径已移除。
  (2) **词汇与诊断**: diagnosis、lexical observation、vocabulary v5 export/import 均使用 lexical entry。
  (3) **Flutter typed state**: `LearningController` 改为 typed lexical entries、phrase candidates、
  selected details、language profile 和 diagnosis；TokenLine 使用 typed phrase candidate/lexical entry。
  (4) **Timeline envelope**: Rust 与 Flutter 新增 `TimelineMetrics` / `ChunkEvidence` typed envelope，
  保留 object-shaped `metrics_json` / `evidence_json` wire/storage 字段。
  (5) **文档事实源**: 刷新 `.planning/codebase/ARCHITECTURE.md` 与
  `.planning/codebase/DATA-MODEL.md`。
  验证: `cargo check -p domain -p application -p persistence-sqlite -p api-http`、
  `cargo test -p application -p persistence-sqlite -p api-http --quiet`、
  `flutter analyze apps/desktop`、`flutter test --reporter compact` 通过。

- 2026-06-27 16:45 CST: Phase 2.18 重构首轮落地。
  (1) **契约**: 补齐缺失 OpenAPI/generated client 路由，并让 contract validation 双向校验 router
  与 OpenAPI path set。
  (2) **Rust 边界**: `AppServices` 拆出 subtitle track、pronunciation、timeline resource、
  LLTimeline resource repository 依赖；learning asset 边界更名为 `LearningAssetRepository`。
  (3) **学习资产模型**: `LexicalEntry` 新增权威 `LexicalUnit`，SQLite lexical 唯一性改为
  `language + granularity + normalization + normalized_key`；`WordStatus` 更名为 `LearningStatus`。
  (4) **应用 DTO**: `application::dto` 不再公开 `speech_analysis` 类型别名。
  (5) **Timeline 生命周期**: SQLite word/chunk/phone timeline runs 增加每 track 单 active partial unique
  index，并新增 schema-level 测试。
  (6) **Flutter 状态流**: 新增 typed `BackendEvent`、`BackendEventCoordinator` 和带 generation guard 的
  `LearningWorkflowController.refreshDiagnosis()`。
  验证: `cargo test -p application --quiet`、`cargo test -p api-http openapi --quiet`、
  `cargo test -p persistence-sqlite --quiet`、`./scripts/validate-contracts.sh`、
  `./scripts/test.sh --quick --low-memory` 通过。

- 2026-06-27 15:38 CST: Phase 2.18 明确为非兼容式断代重构。
  (1) **兼容性决策**: 用户确认不需要考虑历史兼容性，旧 SQLite 数据、旧 LLTimeline 资源、
  旧 WordProfile 资源、旧 API/UI adapter 均可抛弃。
  (2) **规划调整**: Phase 2.18 文档从“legacy adapter / 可迁移”改为“新模型优先 / 旧路径删除”，
  默认以 `LexicalEntry + LexicalUnit`、统一 timeline lifecycle、typed Flutter state 和新 contract 为准。

- 2026-06-27 15:33 CST: 扩展 Phase 2.18 为 Codebase Architecture Refactor。
  (1) **范围升级**: 根据用户追加要求，将原“架构契约与项目卫生”阶段升级为代码层面的全面重构阶段，
  覆盖核心学习资产模型、timeline lifecycle、repository/use-case/API 边界、Flutter 状态机与
  async generation guard。
  (2) **新增审计**: 新增
  `.planning/phases/2.18-codebase-architecture-refactor/2.18-REFACTOR-AUDIT.md`，
  记录 `WordProfile` / `LexicalEntry` / `LexicalUnit` 并存、`SubtitleRepository` 过宽、
  `application::dto` 泄漏 `speech_analysis` DTO、`main.dart` orchestrator 过重和动态 JSON 状态等问题。
  (3) **规划同步**: 将 Phase 2.18 文档迁移到
  `.planning/phases/2.18-codebase-architecture-refactor/`，并更新 `.planning/STATE.md`。

- 2026-06-27 12:50 CST: 创建 Phase 2.17 — Real Media Sound-Line QA。
  (1) **阶段目标**: 从继续扩展模型能力转向真实英语媒体回归包，验证
  `sound_analysis.connected_speech`、声音线 marker、evidence 回放和 raw CTC mismatch
  过滤边界是否能支撑真实学习体验。
  (2) **规划交付**: 新增 `.planning/phases/2.17-real-media-sound-line-qa/2.17-CONTEXT.md`
  和 `2.17-PLAN.md`，定义 manifest、checksum、lightweight verifier、manual listening
  observations 和 `2.17-CTC-MISMATCH-FINDINGS.md`。
  (3) **repo 边界**: 明确不提交无再分发许可的媒体本体，repo 内优先保留 manifest、验证脚本、
  QA notes 和过滤决策记录。

- 2026-06-27 10:47 CST: Phase 2.3 正式收口 + 声音线 evidence 回放入口。
  (1) **Phase 2.3 closeout**: 真实媒体手动 QA 已通过，`.planning/STATE.md` 与
  `2.3-CLOSEOUT.md` 从“待手动 QA”更新为正式完成。
  (2) **Listen to this moment**: sound pattern ribbon 的 evidence marker cell 可点击，
  触发 source loop 播放 marker 覆盖的 `LearningPhone` 时间窗，让 connected-speech
  explanation 从静态标签进入可听验证。
  (3) **测试**: `phoneme_ribbon_test.dart` 覆盖 marker tap -> loop callback。
  验证: `flutter analyze`、`flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart`、
  `cargo test -p speech-analysis`、`./scripts/validate-contracts.sh` 通过。

- 2026-06-27 10:38 CST: Phase 2.16 — Real Connected Speech Model v1 收口。
  (1) **真实语流解释层**: `SoundAnalysis` 新增向后兼容的 `connected_speech` metadata，
  分离 expected symbols、stable learning symbols、observed acoustic symbols、family/status/confidence
  和 learner-facing label/hint。
  (2) **核心现象 v1**: `speech-analysis` 从 phone alignment pattern 生成 weak form/reduction、
  deletion、linking、assimilation、contraction、flapping 六类 explanation；generic high-confidence
  substitution 不会生成 connected-speech teaching explanation，避免 raw CTC mismatch 污染教学标签。
  (3) **UI 消费**: Flutter timeline model 解析/导出 `connected_speech`，声音线 marker 可直接使用
  explanation label/hint；无旧 `findings` 时也能展示学习者解释。
  (4) **契约与文档**: OpenAPI 同步 `ConnectedSpeechExplanation` schema；新增
  `.planning/phases/2.16-real-connected-speech-model-v1/2.16-CLOSEOUT.md`，并更新 `STATE.md`。
  验证: `cargo test -p speech-analysis`、`flutter analyze`、
  `flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart`、
  `./scripts/validate-contracts.sh` 通过。

- 2026-06-27 10:23 CST: Phase 2.15 — Sound Line Learning UX 收口。
  (1) **声音线 UX 语义化**: `PhonemeRibbon` 新增 text/sound lane，声音线使用独立音频图标、
  颜色组和圆角形态，继续显示音节间隔、韵律短语边界与 evidence marker；文字线和声音线均
  增加 tooltip 解释各自学习语义。
  (2) **真实 sound_analysis 门控**: 新增 `buildSoundPatternPhones()`，声音线只在当前句存在
  `sound_analysis.learning_phones` 时渲染；缺失时显示轻量不可用状态，不做词典 fallback，
  也不显示 raw CTC-only 教学标签。
  (3) **学习者文案**: evidence marker tooltip 从内部 finding/status 改为
  `supported by audio`、`possible linking`、`possible reduction`、`possible deletion` 等低风险学习表达。
  (4) **测试稳定性**: 新增 `phoneme_ribbon_test.dart`，扩展 `timeline_test.dart` 覆盖无
  `sound_analysis` 不 fallback、CTC observed mismatch 不污染教学标签和 evidence 文案映射；修复
  `phonetic_analysis_ui_test.dart` 在周期 Timer 页面上使用 `pumpAndSettle` 的既有超时。
  验证: `flutter analyze`、`flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart`、
  `flutter test test/phonetic_analysis_ui_test.dart`、`flutter test` 通过。
  收口文档: `.planning/phases/2.15-sound-line-learning-ux/2.15-CLOSEOUT.md`。

- 2026-06-27 10:12 CST: 新增根目录 `AGENT.md`，作为 coding agent 新会话入口。
  记录 `.planning` 首读顺序、双路线项目形态、架构边界、代码放置规则、工具链
  `CARGO` / `FLUTTER` / `PATH` 环境准备、常用验证命令、文档维护规则和收尾检查事项。

- 2026-06-27 CST: Phase 2.15 / 2.16 路线确认。
  (1) Phase 2.15 定义为 **Sound Line Learning UX**：把第二条声音线推进为用户能理解、
  能开启、能训练、能信任的产品闭环，聚焦真实媒体 QA、独立 UI 语义、空状态和
  evidence marker 的学习化表达。
  (2) Phase 2.16 定义为 **Real Connected Speech Model v1**：在 2.15 产品闭环稳定后，
  系统化覆盖弱读、吞音/省音、连读、同化、缩约、flapping 等高频真实语流现象；明确
  不承诺一次实现完整 Prosodic Hierarchy。

- 2026-06-26 CST: Phase 2.14 — Sound-First Learning Architecture 收口。
  (1) **稳定教学标签优先**: 明确并落地
  `CTC provides audio evidence and timing; expected pronunciation provides teaching labels`。
  Phoneme ribbon 不再直接显示 raw CTC label；当 expected `/s/` 遇到 CTC 误判 `/k/`
  时，默认训练 UI 仍显示稳定 `/s/`，CTC 只提供 timing/confidence/mismatch evidence。
  (2) **SoundAnalysis 资源化**: 新增 `SoundAnalysis`、`SoundLearningPhone`、
  `SoundSyllable`、`SoundProsodicPhrase` 等领域模型；`PhoneticAnalysis` 与
  `PhoneTimeline` 均携带可选 `sound_analysis`，旧 JSON 兼容，SQLite 继续复用完整
  `timeline_json` 持久化，LLTimeline export/import 通过 PhoneTimeline 资源路径保留。
  (3) **声音组织算法**: 新增 `speech_analysis::sound_analysis`，将 expected phones 与
  observed CTC phones 对齐为 `LearningPhone`，实现 SSP 音节化、pause-aware onset
  boundary 和 pause-based prosodic phrase detection。
  (4) **Flutter 消费**: `PhoneTimeline` 解析 `sound_analysis`；前端拆分为两个独立入口：
  文字线 phoneme ribbon 使用文本/词典 expected phone，并只借用 observed CTC timing/evidence；
  没有 expected phone 时不显示 raw CTC-only 教学标签。
  声音线 sound pattern ribbon 只在存在 `sound_analysis` 时显示，消费 `learning_phones`、
  音节间隔、韵律短语边界和 finding evidence marker，不做词典 fallback。marker 会映射到
  stable learning phone 上，`detected_in_audio` 强标记、alignment/uncertain 弱标记，不改写
  教学标签。observed insertion/linking evidence 会锚定到最近 learning phone marker，保持证据
  可见但不新增教学 phone。
  `detected_in_audio` 后端升级策略同步收紧：高置信 generic `phone_substitution`
  不再声明为真实语流检测，只有弱读、flapping、同化、缩约、省音等已知 connected-speech
  family 可升级。
  (5) **研究边界文档化**: 补充 Phase 2.14 context 与 Prosodic Hierarchy alignment 文档，
  明确当前实现是 `Phone -> LearningPhone -> Syllable -> pause-based ProsodicPhrase`
  的最小可靠子集，不声称完整实现 Foot / Prosodic Word / Phonological Phrase /
  Intonation Phrase。
  验证: `cargo test --workspace --quiet`、`flutter analyze`、
  `flutter test test/timeline_test.dart`、`./scripts/validate-contracts.sh` 通过。
  收口文档: `.planning/phases/2.14-sound-first-learning-architecture/2.14-CLOSEOUT.md`。

- 2026-06-26 CST: Phase 2.13 — Text-Centered Phoneme Ribbon 收口。
  (1) **长短句自适应显示**: 短句完整显示音素带；长句自动切换为分页窗口，只显示当前
  音素附近的一页，避免把过多音素压缩成不可读噪音。
  (2) **低疲劳交互**: 移除长句模式下的波浪、脉冲、连续居中滑动和底部进度条；窗口
  内容保持稳定，当前音素只在当前页内轻量高亮，跨页时才整体换页。
  (3) **设置与降级链闭合**: 设置中新增音素带显示方式，短句可选轻量 wave；CTC 真实
  音素优先，无 CTC 时从词典发音 + 词级时间戳合成 `DetectedPhone`，无可用数据则隐藏。
  收口文档: `.planning/phases/2.13-phoneme-ribbon-interaction/2.13-CLOSEOUT.md`。
  验证: `git diff --check` 通过；当前 shell 未提供 `flutter`/`dart`，未运行 analyze/test。

- 2026-06-26 CST: 音素设置精简 + PhonemeRibbon 降级策略 + 双主线架构规划。
  (1) **设置精简**: 11 个音素相关设置项收敛为 4 个（phonemeRibbonVisible /
  phonemeRibbonStyle / phoneticAnalysisPreference / learningLanguage）。移除的 6 项硬编码为合理默认值：
  pronunciationVisible 跟随 ribbon 开关、phonemeDisplay 固定 IPA、
  precomputePronunciation 始终开启、phonemeHighlightVisible 联动 ribbon、
  showExperimentalPhoneticResults 始终显示、phoneticCachePolicy 固定 keep_completed。
  涉及 settings_dialog.dart / main.dart / settings_controller.dart / localization.dart /
  subtitle_overlay.dart，settings.dart 保留字段用于 JSON 向后兼容。
  (2) **Ribbon 降级逻辑修正**: 开关逻辑修复（ribbon 开=显示音素信息，关=全部隐藏）；
  CTC 数据优先、无 CTC 时回退 IPA 文字、均无则隐藏；新增
  `synthesizePhonesFromDictionary()` 函数从词典发音 + 词级时间戳合成 DetectedPhone。
  (3) **双主线架构确立**: 文字线（Whisper 转录 → 词 → chunk → 词典音素，回答"说了
  什么"）和声音线（CTC 音素 → 音节 → 韵律短语，回答"怎么说的"），sentence 为共享
  作用域。Phase 2.13 修订为文字线音素收口，新建 Phase 2.14 声音线学习架构。
  验证: `dart analyze` 0 issues。

- 2026-06-25 CST: CTC 音素分析链路端到端打通 + 任务生命周期管理。
  (1) **链路修复**: 创建项目根目录 `.venv`（torch 2.12 + torchaudio 2.11 +
  transformers 5.12 + torchcodec + phonemizer），`phone_recognition.rs` 新增
  `sidecar_python()` 自动从 `current_exe`/`current_dir` 向上搜索 `.venv/bin/python3`；
  后端 `models()` 过滤掉 `research-fixture` provider 避免 Flutter 误选；
  `main.dart` `_analyzePhonetics()` 改用 SnackBar 反馈替代不可见的 `status` 变量。
  (2) **任务生命周期管理**: 后端新增 `DELETE /v1/phonetic-analysis/jobs/{id}`
  和 `POST /v1/phonetic-analysis/jobs/clear` 端点；repository trait 增加
  `delete_phonetic_job` 和 `delete_terminal_phonetic_jobs`，SQLite 层实现。
  Flutter `phonetic_analysis_ui.dart` 全面重写：状态图标（颜色区分完成/失败/进行中/
  排队）、本地化状态标签芯片、活跃任务 1s 轮询空闲降为 5s、任务计数徽章、
  单任务删除（带确认）、批量"清除已完成"、创建时间相对显示、错误信息卡片内展示。
  中英文各新增 13 个本地化键。验证: Rust 编译通过, `dart analyze` 0 issues。

- 2026-06-25 CST: 修复模型下载三个 bug：(1) 脚本路径解析用相对路径导致 App 运行时
  找不到 `download-phoneme-model.py`，改为从 `current_exe()`/`current_dir()` 向上搜索
  `scripts/` 目录；phoneme-cli sidecar 同步修复。(2) 下载进度无反馈 —— `snapshot_download()`
  阻塞无回调，新增后台线程每 3s 轮询模型目录大小并输出 JSON 进度。(3) Flutter 进度条
  运算符优先级 bug（`?? 0.0 / size`），提取 `_installProgress()` 方法。新增：模型
  下载失败时红色错误提示；启动时 `reset_stale_installs()` 自动将卡住的 `installing`
  状态重置为 `downloadable`。模型下载已验证成功（~1.26GB fb-espeak）。
  验证: Rust 299 tests + Flutter 65 tests 全部通过。

- 2026-06-25 CST: 修复桌面播放器播放位置不上报导致的进度条与字幕同步停滞。
  `DesktopPlayerAdapter` 恢复 100ms position polling，并通过
  `VideoPlayerController.position` 主动触发 fvp `getPosition()`，避免只读取缓存
  `value.position`。position stream 仅由主动 polling/seek/stop 发布，避免
  `VideoPlayerController` 的 buffering/state listener 用旧缓存 position 覆盖真实位置。
  切换媒体、播放失败与 dispose 会取消旧 timer，seek/stop 后立即发布当前位置；
  增加 generation 校验防止旧播放器异步结果污染新媒体。修复 Store-backed
  Player/Subtitle/Learning controllers 未转发 ChangeNotifier 通知的问题，确保
  `main.dart` 的 `ListenableBuilder` 在 position/cue 更新时重建进度条与字幕层。
  增加 controller 通知回归测试。验证: `flutter analyze` 0 issues,
  `flutter test` 65/65 passed, `flutter build macos --debug` passed。

- 2026-06-25 CST: Phase 2.10 Steps 2-6 — fb-espeak CTC phoneme provider 选型与集成。
  (1) **Step 2 补充 benchmark**: fb-espeak PER=30.5%（Apache 2.0）选定；
  vitouphy PER=19.5% 因 TIMIT 许可阻塞被排除。
  (2) **Step 3 生产管线集成**:
  - `DetectedPhone` 新增 `display_ipa` 字段，UI 以 IPA 为主显示
  - `speech-analysis/phone_recognition.rs`: IPA→ARPAbet 映射 + sidecar 封装
  - `phonetic_fixture.rs`: `build_ctc_phonetic_analysis()` 真实 CTC 推理路径
  - `api-http/phonetic_analysis.rs`: CTC provider 注册 + model seed + 执行分派
  - `scripts/wav2vec2-phoneme-cli.py`: Python sidecar（CTC decode + logit confidence）
  - `scripts/setup-phoneme-model.sh`: 命令行模型下载脚本
  - `scripts/download-phoneme-model.py`: 后台模型下载 sidecar（JSON 进度输出）
  - Flutter `diagnosis_card.dart`: IPA 优先显示
  - Flutter `phonetic_analysis_ui.dart`: 模型下载按钮 + 进度条（App 内一键下载）
  - `install_model` API: 后台 spawn Python 下载进程，带进度回报和状态更新
  - Flutter `api_service.dart`: 新增 `installPhoneticAnalysisModel()` API 调用
  (3) **Step 4 finding 升级**: 隐式完成（现有 alignment + findings 管线已支持真实 confidence）
  (4) **Step 5 端到端验证**: 待下载模型后测试
  (5) **Step 6 回归**: Rust 299 tests + Flutter 64 tests 全部通过
  使用方式: App 设置 → Audio analysis models → 点击下载按钮；或命令行 `./scripts/setup-phoneme-model.sh`。

- 2026-06-25 CST: Phase 2.11 Steps 1-3 完成 + Phase 2.10 研究计划。
  (1) **Step 3 — domain lib.rs 拆分**: 从 1317 行缩减到 194 行。新增 13 个领域模块
  (media / subtitle / pronunciation / word_timing / chunk_timeline / phone_timeline /
  lltimeline / phonetic_analysis / learning / dictionary / transcription / vocabulary /
  diagnosis)，测试下沉到各自模块。
  (2) **Step 1 — 能力矩阵 API**: Phase 2.12 已完成（`_isHan` 替换为 profile 驱动门控，
  `/v1/languages` + `/v1/languages/{code}/profile` 端点已就位）。
  (3) **Step 2 — 学习语言来源**: AppSettings 新增 `learningLanguage` 字段（默认 `auto`），
  优先级链：用户设置 > 字幕轨语言 > `en` fallback。设置对话框顶部新增学习语言下拉框。
  中英双语 localization。
  (4) **Phase 2.10 研究计划**: 编写 `2.10-RESEARCH-PLAN.md`，盘点已有基础设施
  (PhoneTimeline / MFA / ZIPA / 评估 harness)，规划 4 阶段研究流程
  (环境验证 → 候选 benchmark → 选型决策 → 结果记录)。
  (5) **验证**: 294 cargo tests + 64 flutter tests passed, `flutter analyze` 0 issues。

- 2026-06-25 CST: Phase 2.12 — UI State Management Refactoring (Flutter).
  (1) **Store\<T\> 基础设施**: 通用响应式状态容器，支持 `select()` 细粒度字段级
  ValueNotifier 订阅。新增 StoreBuilder/StoreBuilder2 声明式选择器 Widget。
  (2) **Typed domain models**: 新增 `models/types.dart`，提供 WordProfile、WordDetail、
  Diagnosis、PhraseCandidate 等 7 个 typed 类替代 `Map<String, dynamic>`。
  (3) **Controller 迁移**: PlayerController / SubtitleController / LearningController
  内部迁移到 Store，保留 ChangeNotifier 向后兼容。
  (4) **布局提取**: SubtitleOverlay（原 _playerSurface()）和 SidePanel（原 _sidePanel()）
  提取为独立 Widget 文件，减少 main.dart 的构建方法复杂度。
  (5) **验证**: `dart analyze` 0 issues, `flutter test` 64/64 passed。
  分支: `refactor/ui-state-management`。规划文档:
  `.planning/phases/2.12-ui-state-management-refactoring/`

- 2026-06-24 CST: Phase 2.9 closeout + Phase 2.10/2.11 planning.
  (1) **Phase 2.9 收口**: 生产管线多语言解耦完成。2.9-CLOSEOUT.md 记录 Rust 侧
  (AlignerRegistry/语言传播/CJK 分词) + Python 侧 (mlx-whisper/jieba/M:N 对齐)
  全部交付、中文端到端验证结果和设计决策。
  (2) **残留项总览**: 新增 `.planning/DEFERRED-ITEMS.md`，汇总 Phase 2.1–2.9 全部
  残留/延后项，按 P1(英语语流+架构)/P2(小项)/P3(中文/日语) 分级。
  (3) **Phase 2.10 规划**: English Real Speech Analysis — 选出 phone-level provider，
  让英语语流分析从文本预测升级为音频检测。候选 MFA/ZIPA/Wav2IPA/Allosaurus。
  (4) **Phase 2.11 规划**: Architecture Seam Consolidation — 能力矩阵 API、学习语言
  来源、domain 拆分、L1 诊断 seam、听觉锚定准备。Step 1–3 可与 2.10 并行。

- 2026-06-24 CST: Chinese word-level tokenization + mlx-whisper ASR integration.
  (1) **jieba word segmentation**: `tokenize()` in `lltimeline_common.py` now uses
  jieba for Chinese word segmentation instead of character-level splitting. "今天"
  is one token (not "今"+"天"), producing natural word-boundary highlights during
  karaoke playback. Falls back to per-character if jieba unavailable. English
  tokenization unchanged.
  (2) **ASR-to-token alignment**: new `align_asr_words_to_tokens()` handles M:N
  mapping between ASR word boundaries and jieba token boundaries via character-
  position alignment. Merges timing from multiple ASR words when they compose one
  jieba token (e.g. ASR ["上","海"] -> jieba "上海").
  (3) **mlx-whisper integration**: `mlx-whisper-transcribe.py` standalone script
  wrapping `mlx_whisper.transcribe()` with WhisperX-compatible JSON output.
  `production_pipeline.py` gains `--asr` flag (`whisperx`/`mlx-whisper`) and
  `resolve_mlx_whisper_command()`. ~7.5x faster than WhisperX CPU on Apple Silicon.
  (4) Quality comparison on 8-min Chinese audio: mlx-whisper avg_confidence 0.954
  vs WhisperX 0.953, fewer overlaps (2 vs 4), comparable word coverage.

- 2026-06-24 CST: Phase 2.9 — Production multilingual decoupling + pluggable model
  architecture.
  (1) **Pluggable aligner registry**: new `aligners/` package with `AlignerPlugin`
  base class, `MfaAligner` and `MmsFaAligner` plugins extracted from
  `production_pipeline.py`. Registry provides `register()`, `get_aligner()`,
  `available_aligners(language)`, `all_aligners()`. Adding a new aligner (e.g.
  Qwen3-ForcedAligner) requires one plugin file + one `register()` call.
  `production_pipeline.py` dispatch rewritten to use registry — no more if/elif.
  New `list-aligners` subcommand; `doctor` now reports registered aligner status.
  (2) **CJK tokenizer**: `lltimeline_common.py` tokenizer extended to emit each
  CJK character (Chinese, Japanese hiragana/katakana) as an individual word token.
  English tokenization unchanged. 11 new tests for CJK + regression.
  (3) **Language propagation**: `--language` parameter flows through entire
  production chain. `post_aligner_chain()` filters aligners by language: Chinese
  skips MFA (English-only) and uses MMS_FA directly. `apply-mfa-alignment` and
  `apply-mms-fa-alignment` subcommands accept `--language`.
  (4) **CJK chunk partition (Rust)**: `chunk_partition.rs` strong punctuation
  detection extended with CJK sentence-final punctuation (U+3002, U+FF1F, etc.).
  `build_chunk` text joining uses no separator for all-CJK chunks. `is_cjk_char`
  helper covers CJK Unified Ideographs, hiragana, katakana.
  (5) **Rust pipeline language propagation**: `ForcedAlignRequest` gains optional
  `language` field. `refine_transcription_word_timelines()` accepts and propagates
  language from `detected_language` through to the forced-align sidecar.
  (6) **GUI**: post-aligner dropdown dynamically populated from aligner registry.
  Verified: all 24 Python tests pass, all 294+ Rust workspace tests pass, clippy
  clean (no new warnings).

- 2026-06-24 CST: Phase 2.9 planning — Production engine multilingual decoupling.
  Created CONTEXT and PLAN docs identifying 5 English binding points in the
  production pipeline: language propagation, forced alignment language-aware
  degradation, pronunciation analysis provider-ization, text chunk language
  dispatch, and Chinese end-to-end validation. Consumer-side is now
  language-agnostic (Phase 2.6-2.8); this phase targets the production side.
  Updated STATE to reflect Phase 2.8 completion and Phase 2.9 planning.

- 2026-06-24 CST: Phase 2.8 — Token timing alignment + rhythm-aware estimation.
  (1) **Character-level time alignment**: `asr_timing.rs` rewritten to perform
  character-level time interpolation (`align_words_to_tokens`) when whisper BPE
  word count mismatches app tokenizer word count (common for CJK where BPE merges
  characters differently from jieba/lindera). English 1:1 direct path unchanged
  (`extract_direct`). New `TimingSource::AsrAligned` variant for interpolated
  timings. `MergedWord` now carries `text` for alignment computation.
  (2) **Rhythm-aware estimation fallback**: `estimate_word_timings_with_rhythm`
  selects strategy from `LanguageLearningProfile.rhythm_prosody`: `CharWeight`
  for stress-timed (en, clamped char count, `v1`), `SyllableEqual` for
  syllable-timed (zh, equal CJK char weight, `v2-syllable`), `MoraCount` for
  mora-timed (ja, kana/kanji mora counting with small-kana exclusion,
  `v2-mora`). `pronunciation.rs` wired to pass profile rhythm.
  (3) **Public alignment API**: `align_timings_to_tokens` exposed for lltimeline
  import and future re-tokenize scenarios. `word_timing_cache_is_usable` updated
  to accept `v2-*` provider versions.
  (4) **Match arm updates**: `AsrAligned` added to `chunk_partition.rs`
  `acoustic_gap_threshold` (same threshold as `AsrReported`) and
  `application/lib.rs` `timing_priority` (priority 2, same as `AsrReported`).
  Verified: 294 workspace tests pass (7 new: Chinese BPE alignment, English
  direct mapping regression, character time distribution, public alignment API,
  syllable-timed equal weight, mora counting, default rhythm regression),
  clippy clean.

- 2026-06-24 CST: Phase 2.7 — Pronunciation provider dispatch + language-agnostic
  timing/chunk. (1) **PronunciationProvider trait**: new dispatch trait in
  `providers.rs` with `analyze_sentence`, `lookup_word`, `rule_catalog` methods.
  `EnglishPronunciationProvider` wraps `speech_analysis` crate;
  `ChinesePronunciationProvider` produces pinyin from CC-CEDICT with per-character
  fallback. Providers registered in `ApiState::new`, dispatched by
  `sentence_language()` match against `info().languages`. (2) **pronunciation.rs
  rewrite**: `analyze_pronunciation`, `lookup_pronunciation`, `pronunciation_rules`
  all route through registered providers. Cache validation keyed on provider
  id/version. `analyze_pronunciation_track` uses `filter_map(.ok())` to skip
  sentences that fail (e.g. punctuation-only). API routes `/v1/pronunciation/lookup`
  and `/v1/pronunciation/rules` accept `language` query parameter (default "en").
  (3) **Chinese pinyin display**: Chinese subtitles now show tone-marked pinyin
  below the subtitle line via existing `display_ipa` rendering path — no Flutter
  code change needed. (4) **Timing/chunk language-agnostic**: `estimate_word_timings`
  (character-weighted time distribution) and acoustic chunk detection (gap-based)
  confirmed as language-agnostic algorithms. Chinese profile upgraded from
  `Unsupported` to `Supported` for `word_timeline` and `chunk_timeline`. Only
  `detect_text_chunks` (COCA n-gram / PHRASE List) remains English-gated.
  (5) **phonetic_fixture.rs**: non-English skips canonical phone alignment
  (empty canonical list). Verified: 286 workspace tests pass, user confirmed
  Chinese pinyin + word tracking + chunk highlight working, English regression clean.

- 2026-06-23 CST: Phase 2.6 extension — capability matrix API, language selection
  UI, and per-character meaning breakdown. Three user-visible features:
  (1) **Capability matrix API**: `GET /v1/languages` lists supported languages,
  `GET /v1/languages/{code}/profile` returns the full `LanguageLearningProfile`
  (tokenization, dictionary, pronunciation capabilities). Flutter API service
  wired with `listLanguages()` and `lookupLanguageProfile()`.
  (2) **Language selection UI**: `PATCH /v1/subtitles/{track_id}/language` lets
  users override auto-detected language on a subtitle track. Backend follows the
  `set_track_status` pattern (trait → sqlite UPDATE → return updated track).
  `_LanguageChip` widget in the subtitle resource tile shows current language with
  a popup menu; changing language refreshes word/phrase profiles for the active
  track.
  (3) **Per-character meaning**: `DictionaryLookup` extended with
  `character_breakdowns: Vec<CharacterBreakdown>` (character + phonetic + meaning).
  `ChineseDictionaryProvider::resolve()` splits multi-character words and does
  per-char CC-CEDICT/seed lookups to populate meanings. Word learning panel reads
  backend breakdowns first, falls back to client-side syllable splitting. Meaning
  row renders below pinyin in small text. Gate changed from hardcoded
  `profile['language'] == 'zh'` to profile-driven
  `pronunciation == 'zh.pinyin'`. `character_breakdowns` uses
  `skip_serializing_if = "Vec::is_empty"` for backward compatibility with cached
  dictionary entries. Verified: workspace 250 tests, flutter 64, contracts pass,
  no-default-features clean, en/zh/ja regression baseline unchanged.

- 2026-06-23 15:28 CST: Promoted Japanese from a guard fixture to a real language
  (lindera morphological tokenization + JMdict/EDICT2 dictionary), empirically
  validating the dispatch-layer fix from the earlier falsification spike. Added
  `JapaneseTokenizer` with lindera 4.0 + embedded IPADIC behind an opt-in
  `lindera` feature (default off — not vendored offline; offline/default builds
  use character-level fallback). Added `JapaneseDictionaryProvider` reading
  EDICT2 line format with a 15-word seed fallback, registered in the api-http
  dictionary stack. The ja profile now declares `ja.morphological` tokenization,
  `jmdict` dictionary, and `ja.kana` pronunciation — all routed by profile and
  provider with zero edits to dispatch core, `detect_language`, per-char gating,
  or diagnosis. This empirically confirms ROADMAP §14.11: adding a real
  Han-script-sharing language required only profile + provider + registration.
  Surfaced a deferred seam: `core.surface` normalization does not unify Japanese
  inflections (食べる/食べた) because Fix 4 re-derives the normalized key from
  surface text, discarding lindera's base form — base-form unification needs
  the provider-supplied opaque key to flow through `tokenize()`. Updated
  maintenance checklist to require minute-precision changelog timestamps.
  Verified: workspace 286 tests, `--features lindera` morphological proof,
  `--no-default-features` 24 tests, flutter 64, clippy clean, contracts pass;
  en/zh regression baseline unchanged.

- 2026-06-23 09:07:10 CST: Closed out Phase 2.6 (step 7). Consolidated the
  bilingual regression into an explicit set and added a crown-jewel capstone test
  proving English and Chinese vocabularies and their source snapshots stay
  language-isolated (a Chinese word never appears in the English vocabulary and
  vice versa). Wrote `2.6-CLOSEOUT.md` and updated STATE / ROADMAP / REQUIREMENTS
  to mark Phase 2.6 complete for the English + Chinese acceptance set. LANG-001/
  002/003/005/006/007/008/010 are implemented; LANG-004 (auditory-anchored
  observation) and LANG-009 (L1 diagnosis seam) remain reserved seams by design,
  as does non-English audio → listening-unit production (a separate future
  program). English behavior stayed the regression baseline throughout. Verified
  with the full workspace suite (279 tests), flutter analyze/test (63), and
  validate-contracts.

- 2026-06-22 21:49:03 CST: Added the Phase 2.6 Chinese learning panel and
  language-aware diagnosis (step 6). Sentence diagnosis now layers the learning
  language's listening factors onto the recognition barrier as namespaced,
  per-profile *possibilities* (zh: tone_confusion/word_boundary/homophone/
  neutral_tone/tone_sandhi; en: weak_form/linking/...), explicitly framed as
  factors to consider rather than detections from audio — there is no Chinese
  audio analysis yet (deferred per ADR 0012). The decoration lives in the
  application layer (`diagnose_sentence`), keeping `diagnosis-core` language-
  agnostic; a new `reasons` field on `DiagnosisHint` carries them. The word panel
  gained a per-character breakdown for multi-character Han words, aligning each
  character with its pinyin syllable (字 → 拼音/声调) — derived from the dictionary
  phonetic with no extra lookups and gated on script, not language. The diagnosis
  card renders reasons localized with a clean fallback for unknown reasons.
  Verified with new application and widget tests; English diagnosis stays the
  regression baseline.

- 2026-06-22 21:09:21 CST: Integrated CC-CEDICT as the real Chinese dictionary
  source, replacing the 25-word built-in stub with the full ~120k-entry community
  dictionary while keeping the seed as an offline fallback. `ChineseDictionaryProvider`
  now reads an installed CC-CEDICT `.u8` file (cached, mirroring the ECDICT loader),
  parsing `Traditional Simplified [pin1 yin1] /glosses/` and converting tone-numbered
  pinyin to tone marks (handling `u:`→`ü`, neutral tone, capitalized proper nouns, and
  the standard a/e/ou/last-vowel placement); both simplified and traditional headwords
  resolve. Registered CC-CEDICT in the learning-resource catalog with a pinned mirror
  commit and verified SHA-256 (CC-BY-SA 4.0), so it installs like ECDICT/CMUdict.
  Known limitation: words with multiple readings keep the first entry. Verified with
  new parser/tone tests and a throwaway smoke check against the real 118k-entry file.
- 2026-06-22 21:00:00 CST: Fixed two backend `language=en` hardcodes that Step 4
  (client-scoped) missed, so Chinese diagnosis and phrase detection use the sentence's
  actual track language. Added a `sentence_track_language` repository method (joining
  `subtitle_sentences` to `subtitle_tracks`) and a `sentence_language` application
  helper (track language, else `en`); `diagnose_sentence` and `phrase_candidates` now
  resolve through it instead of assuming English. Previously a Chinese sentence's
  diagnosis read English word profiles and ignored the user's Chinese statuses. Added a
  test proving zh diagnosis reads zh profiles and en does not leak.
- 2026-06-22 20:20:02 CST: Added the Phase 2.6 Chinese dictionary and
  pronunciation provider (step 5). Introduced a built-in `ChineseDictionaryProvider`
  in `dictionary-provider` (`supported_languages: ["zh"]`) seeded with common
  words/characters, each carrying tone-marked pinyin (the `zh` profile's
  `zh.pinyin`/`zh.tone`) and a short gloss, and registered it in the api-http
  dictionary stack. The existing `lookup_dictionary` dispatch already routes by
  `supported_languages`, so clicking a Chinese token now shows pinyin + meaning
  while English providers are skipped; unknown words degrade to no result without
  affecting playback or word status. Pinyin is delivered through the dictionary
  phonetics, and the word-learning panel now hides the IPA pronunciation section
  when no variant has real content (Chinese has no IPA provider). Seed data is a
  placeholder for a licensed CC-CEDICT-scale source behind the same interface.
  Verified with new provider, language-routing, and Flutter checks.
- 2026-06-22 17:30:00 CST: Removed the Phase 2.6 `language=en` hardcoding (step 4)
  so the learning language comes from the active subtitle track instead of a
  constant. `subtitle_core::import` now detects the language from the subtitle
  script when the caller does not declare one (Han -> zh, else en) and uses it for
  both tokenization and the stored `track.language`; a declared language still
  wins and English tokenization stays the regression baseline. The Flutter
  `SubtitleTrack` model reads the language the core already serialized, and a
  `_learningLanguage` resolver (active primary track language, `en` fallback)
  threads it through the vocabulary, dictionary, word-profile, source-snapshot and
  phrase paths and `_sourceFor`. The `LocalApi` vocabulary/dictionary/lexical
  methods take a required language; also dropped the dead `normalizeLexical`
  client wrapper. Verified with workspace tests, flutter analyze/test and
  validate-contracts.
- 2026-06-22 16:06:45 CST: Added the Phase 2.6 LexicalUnit model (step 3) in
  `domain` (`lexical_unit.rs`): a language-relative vocabulary learning object
  whose identity is two orthogonal axes — granularity
  (core.char/word/phrase/morpheme) x normalization
  (core.surface/lemma/citation/root) — plus an opaque normalized_key with no
  substring/affix assumption (ADR 0012 R2). Word-granularity identity stays
  `language:normalized_key` so existing English WordProfile ids remain readable;
  non-word granularities namespace the key so Chinese characters never pollute
  Chinese words or English lemmas. English normalizes to a lowercased lemma,
  Chinese keeps the surface form (no lemma assumed), and a
  baseline_normalized_key helper leaves real citation/root normalization to
  per-language providers. Verified with new domain tests and clippy.
- 2026-06-22 16:00:04 CST: Implemented the Phase 2.6 language-aware
  tokenization foundation (steps 1-2 of the multilingual learning phase).
  Added a `LanguageLearningProfile` capability matrix in `domain`
  (`language_profile.rs`) with open namespaced-string `kind` fields (per ADR
  0012 R0), English/Chinese/degraded profiles, and a `profile_for` resolver
  that maps regional variants to their base language and degrades unknown
  languages cleanly; the global `WordStatus` enum is left untouched as the
  language invariant. Replaced the single `tokenize_english` call path in
  `subtitle-core` with a `Tokenizer` trait and a profile-driven
  `tokenize(language, text)` dispatch: English keeps the existing baseline,
  unknown/absent languages degrade to whitespace, and `zh.word_segmentation`
  routes to a Chinese tokenizer. Chinese tokenization uses jieba-rs 0.7.4 word
  segmentation by default (`jieba` feature), with a character-level fallback
  under `--no-default-features`; both preserve original character spans and
  handle mixed CJK/Latin/number runs. Verified with the full workspace test
  suite (255 tests), the no-default-features fallback path, and clippy; the
  English tokenization path is unchanged. jieba-rs is now pinned in Cargo.lock.
- 2026-06-22 11:59:40 CST: Documented the multilingual listening-learning
  product direction across the strategic docs after the Phase 2.5.5 validation,
  following the `.planning/MAINTENANCE.md` rules. Updated PROJECT.md (vision is
  now multilingual and listening-first; new §4.4 principles, §10.9 concepts, and
  §15.5 Milestone 2 multilingual direction). Added REQUIREMENTS.md section 18.4
  with LANG-001..LANG-010 (capability matrix/profile, language-aware
  tokenization, LexicalUnit granularity×normalization, ListeningUnit view plus
  listening-anchored observation, `language=en` removal, Chinese
  dictionary/pinyin provider, Chinese learning panel/diagnosis, comprehension-axis
  invariant with per-profile diagnosis reasons, L1 seam, open kind taxonomy) and
  a release-matrix row; noted TXT-001 is generalized by LANG-002. Added
  ROADMAP.md §14.11 multilingual workstream under Milestone 2. Recorded the
  architecture decision as ADR 0012 and added forward-looking multilingual
  sections to codebase/ARCHITECTURE.md and codebase/DATA-MODEL.md. No code
  changed; English behavior remains the regression baseline.
- 2026-06-22 11:45:56 CST: Added Phase 2.5.5 Language Learning Abstraction
  Validation as a design/validation phase inserted before Phase 2.6
  (Multilingual Learning Foundation), mirroring the earlier 2.3.5-before-2.4
  pattern. Validated the multilingual learning abstraction against real
  second-language-acquisition research rather than engineering aesthetics:
  the meaning-vs-sound diagnosis axis maps to Field's decoding-vs-meaning
  listening model, language-specific listening units to Cutler's
  cross-linguistic segmentation (English stress, French syllable, Japanese
  mora, Mandarin syllable/tone), the LexicalUnit to Nation's word family,
  chunks to Wray's formulaic language, lexical competition to the
  Marslen-Wilson cohort model, and L1 filtering of L2 perception to Best
  (PAM) and Flege (SLM). Locked the comprehension axis as the single language
  invariant: the global vocabulary status enum stays language-agnostic and
  reusable, while diagnosis reason taxonomy becomes per-profile and
  extensible. Added an L1->L2 diagnosis seam (nullable, unused in v1, no
  schema change). Ran a typological falsification with Japanese and Arabic
  that forced three abstraction revisions: R0 `kind` taxonomies must be open
  namespaced strings with clean degradation instead of exhaustive enums
  (Japanese mora, Arabic templatic morphology fall outside the original
  closed sets); R1 listening observations must be able to anchor to a
  `ListeningUnit`, not only a `LexicalUnit`, so tone/pitch minimal-pair
  failures have a home; R2 `normalized_key` must be provider-opaque because
  Arabic non-concatenative roots (k-t-b) are not surface substrings. Scoped
  the architecture to the top-15 learning languages with typological
  clustering and flagged Hindi's abugida as the next writing-system probe.
  Fed the validated foundation back into Phase 2.6 as seven implementation
  constraints and resolved two of its open questions. No production code
  changed; deliverables are design docs (SLA foundation, falsification,
  closeout) plus updates to STATE and the Phase 2.6 plan.
- 2026-06-22 10:30:00 CST: Updated `validate-contracts.sh` MFA strategy
  assertion from `--strategy align-one` to `--strategy align` to match the new
  batch-align default. All 16 Python tests and the full contract validation
  suite now pass with the updated defaults.
- 2026-06-22 09:15:00 CST: Switched the MFA default strategy from `align-one`
  to batch `align`. The `align-one` strategy spawned a separate `mfa
  align_one` process per segment, incurring ~11 s of model-loading overhead
  each time; for 115 segments this meant 210 s total. Batch `align` loads the
  model once and aligns all segments in a single process (58 s, 3.6× faster)
  with identical output. The original reason for `align-one` was an MFA 3.3.9
  SQLite export bug (empty interval CSVs); re-testing confirmed the bug is no
  longer present. `align-one` is kept as `--mfa-strategy align-one` fallback.
- 2026-06-22 09:04:00 CST: Completed Phase 2.5 Sound Pattern /
  PhoneTimeline. PhoneTimeline is now a first-class resource with SQLite schema
  v14, candidate/active/archive lifecycle APIs, LLTimeline import/export
  round-tripping, OpenAPI coverage, and desktop resource management. Completed
  phonetic analyses now bridge to PhoneTimeline candidates; the desktop app can
  show, activate, archive, delete, and consume active PhoneTimeline resources
  for current-phone highlighting and diagnostic sound-pattern display, while
  falling back to legacy phonetic analyses when no active resource exists.
  Added the Phase 2.5 provider benchmark gate and recorded the no-release
  provider decision: research fixtures and candidate models stay out of the
  default product path until benchmark, provenance, and license gates pass.
- 2026-06-21 21:16:48 CST: Completed Phase 2.4 ChunkTimeline generation and
  consumption. Chunk boundaries are now persisted as first-class
  `ChunkTimeline` resources with SQLite schema v13, active/candidate/archive
  lifecycle APIs, LLTimeline import/export round-tripping, and OpenAPI
  coverage. The desktop app now lists ChunkTimeline candidates in Subtitle
  Resources, can generate/activate/archive/delete them, prioritizes the active
  ChunkTimeline for playback, and adds chunk navigation, click-to-seek, loop
  current chunk, and expanded chunk practice controls. Updated Phase 2.4
  closeout docs. Verified with `cargo test --workspace --quiet`,
  `flutter analyze`, `flutter test`, `./scripts/validate-contracts.sh`, and
  `git diff --check`.
- 2026-06-21 10:19:08 CST: Implemented the first Phase 2.3 manual
  WordTimeline review pass in the desktop app. Manual Review now opens a
  sentence-level inspector backed by a full cloned WordTimeline draft, supports
  integer-millisecond start/end editing with ±10ms/±50ms controls, plays the
  current sentence or word using draft boundaries, and saves a full
  `created_by=user` / `status=active` user-adjusted WordTimeline revision.
  Added complete Flutter WordTimeline read/create client methods, millisecond
  payload serialization, draft validation/dirty tracking, and focused tests.
  Verified with `flutter analyze` and `flutter test` (59 tests passed).
- 2026-06-21 10:31:53 CST: Made Phase 2.3 Manual Review discoverable as a
  labeled button in the Timeline Resource Summary instead of an icon-only
  action, and fixed word-click navigation so selecting a subtitle word opens the
  Word Learning side panel rather than the Subtitle Resources panel. Verified
  with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 10:39:53 CST: Fixed Manual Review playback verification leaking
  its temporary source loop after closing the dialog. The review flow now
  restores the previous source loop state when the inspector exits, so using
  Play sentence / Play word no longer leaves normal playback looping the review
  segment. Verified with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 10:51:01 CST: Reworked subtitle resource export so the existing
  Export action asks for an output format. Users can now choose SRT or
  LLTimeline JSON from the same export flow; LLTimeline export writes the full
  `.lltimeline.json` document via `GET /v1/subtitles/{track_id}/lltimeline/export`.
  Verified with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 11:02:30 CST: Added a direct Export LLTimeline JSON action to the
  Timeline Resource Summary so users can export the full resource from the same
  area that shows active/manual WordTimeline versions. The button reuses the
  same track-level `.lltimeline.json` export path and is covered by widget
  tests. Verified with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 02:55:00 CST: Hardened the timeline-production browser GUI so it
  cancels cleanly and previews without blocking. `cancel()` now signals the
  whole process group (`start_new_session` + `os.killpg` SIGTERM, escalating to
  SIGKILL after a 3s grace) instead of orphaning the whisperx/MFA worker, and
  reports a real exit code (130 on cancel) so the UI no longer sticks on
  "Running..." Command preview no longer synchronously SHA256-hashes multi-GB
  media (instant placeholder for preview; real hash computed only on `/run`);
  previewed commands survive `poll()` until the next run; and `main()` forces
  line-buffered stdout so the server URL appears even under pipe redirection.
  Added `test_production_pipeline_gui_contract.py` (10 tests) covering the
  process-group cancel, fingerprint resolution, placeholder, and stdout
  behavior. Verified end-to-end against the Brooklyn middle-school sample:
  whisperx baseline + `from-whisperx-json` convert and MMS-FA post-alignment
  both produce a valid `llplayer.timeline.v1` `.lltimeline.json`.
- 2026-06-20 21:08:52 CST: Added subtitle-resource consumption capability
  visibility in the standalone Subtitle Resources panel. Each resource now
  reports sentence, word, chunk, and phone timing availability with counts;
  resource refresh probes capabilities independently so partial failures do not
  hide usable subtitles; and opening a new media clears stale resource
  capability state before reloading.
- 2026-06-20 21:08:52 CST: Hardened active subtitle-resource consumption after
  LLTimeline import by loading word timings, chunk partitions, phone analyses,
  and pronunciation independently. Resource-list capability refresh no longer
  triggers full-track chunk partition generation, so importing a large
  `.lltimeline.json` is not blocked by panel capability probing.
- 2026-06-20 21:36:31 CST: Promoted subtitle resources to a top-level desktop
  entry, opening a dedicated management page like the vocabulary book instead
  of relying on the right-side transcript panel. LLTimeline import now refreshes
  visible resources after success, and current-media imports reuse an existing
  same-media/same-subtitle fingerprint track id so repeated or previously
  imported `.lltimeline.json` resources remain visible and consumable.
- 2026-06-20 21:46:04 CST: Fixed the desktop development sidecar selection trap
  where a stale `target/release/api-http` was preferred over the freshly built
  debug sidecar, leaving real user databases at schema v9 without
  `word_timeline_runs`, `lltimeline_resources`, or subtitle lifecycle status.
  Rebuilt the release sidecar, migrated the local database to schema v12, and
  verified the desktop sample MP4 plus `baseline.lltimeline.json` imports as a
  visible subtitle resource with 1,755 word timings.
- 2026-06-20 10:14:20 CST: Added the first full subtitle-resource lifecycle
  management pass. `SubtitleTrack` resources now carry `available|archived`
  status with SQLite migration `0012_subtitle_resource_lifecycle`; the local API
  can archive, restore, delete, export, and list resources; and the Subtitle
  Resources panel exposes archive/restore/delete/export actions while preventing
  archived resources from being activated.
- 2026-06-20 10:05:16 CST: Reworked Phase 2.2 app-side subtitle resource
  handling so subtitles and `.lltimeline.json` files behave as attachable,
  visible resources for the current media. Added current-media LLTimeline
  import with fingerprint mismatch confirmation, remapped imported track /
  sentence / WordTimeline identifiers for exchange-safe attachment, exposed
  media subtitle-resource listing APIs, and moved Timeline Resource Summary out
  of the Transcript panel into a standalone Subtitle Resources side panel that
  can import, list, activate, and refresh subtitle resources.
- 2026-06-20 08:39:01 CST: Hardened the MFA `align-one` sidecar so a single
  segment `mfa align_one` subprocess failure is recorded as a per-segment
  diagnostic/skipped timing instead of crashing the whole run, while still
  failing fast when every segment fails so production fallback can engage.
- 2026-06-20 00:34:23 CST: Created Phase 2.3 manual timeline review UI
  planning docs, defining the sentence-level Word Timing Inspector approach,
  user-adjusted WordTimeline save/activate/export flow, playback verification
  controls, and Phase 2.4 handoff boundary.
- 2026-06-20 00:18:59 CST: Replaced the timeline production Tkinter GUI with a
  local browser-based GUI backed by Python's standard-library HTTP server,
  using macOS `osascript` only for folder/media selection and avoiding Tk file
  dialogs entirely.
- 2026-06-20 00:11:42 CST: Attempted to reduce the timeline production Tk save
  dialog crash on macOS/Python 3.13 by removing the multi-pattern file type
  filter; this was later superseded by replacing the Tk GUI entirely.
- 2026-06-19 23:59:47 CST: Fixed timeline production GUI/CLI WhisperX discovery by
  auto-detecting the default timeline-production venv under
  `~/Library/Caches/LLPlayerNext/research/timeline-production/venv/bin/whisperx`;
  the GUI now pre-fills this path when present.
- 2026-06-19 23:28:09 CST: Added a standalone Tkinter GUI wrapper for the local
  LLTimeline production pipeline at
  `scripts/timeline-production/production_pipeline_gui.py`, covering media
  selection, output paths, SHA256 fingerprinting, WhisperX/post-aligner options,
  dry-run command preview, live logs, cancellation, and output-folder access.
- 2026-06-19 23:18:55 CST: Completed Phase 2.2 app timeline resource UI alignment. Added
  LLTimeline resource metadata/artifact persistence (`lltimeline_resources`),
  import/export artifact round-trip coverage, Flutter LLTimeline client methods,
  timeline resource controller state, and a Transcript-panel Timeline Resource
  Summary UI for import, active/candidate WordTimeline visibility, production
  readiness/artifacts, candidate activation, and a Phase 2.3 manual-review
  entry placeholder. Verified active WordTimeline playback binding remains on
  `trackWordTimings()` with legacy fallback.
- 2026-06-19 16:20:39 CST: Added the Phase 2.2 start handoff document at
  `.planning/handoff/project-handoff-2026-06-19-phase-2.2-start.md`, summarizing
  the completed Phase 2.1 hardening work, verified commands, remaining
  non-blocking architecture debt, and the recommended Phase 2.2 audit-first
  entry path for LLTimeline resource UI alignment.
- 2026-06-19 16:10:34 CST: Completed the Phase 2.1 application orchestration
  debt fix for transcription word timelines. Added
  `AppServices::refine_transcription_word_timelines` with a
  `ForcedAlignSidecar` input and `WordTimelinePipelineResult`, moving
  DTW extraction, MMS_FA sidecar invocation, forced-alignment merge,
  pause-refinement, WordTimeline snapshot creation, activation, and legacy
  fallback storage out of `api-http`. `crates/api-http/src/transcription.rs`
  now only reads the generated Whisper JSON, resolves the optional sidecar, and
  calls application orchestration. Updated Phase 2.1 and CONCERNS docs to mark
  this architecture debt handled while keeping mega-file splitting and
  monotonicity ablation as later standalone work.
- 2026-06-19 16:10:34 CST: Also moved the phonetic research fixture's canonical
  phone alignment and finding construction out of
  `crates/api-http/src/phonetic_analysis.rs` into
  `AppServices::build_research_fixture_phonetic_analysis`, so the HTTP
  coordinator keeps job state, queueing, repository writes, and events while
  application owns the speech-analysis composition.
- 2026-06-19 16:10:34 CST: Removed the remaining direct `speech_analysis`
  references from `crates/api-http/src/lib.rs` by exposing chunk partition
  response types and learned prosodic provider catalog access through the
  application layer.
- 2026-06-19 16:01:48 CST: Closed Phase 2.1 with a documented scope cut after
  completing the current hardening work: P0 word-index placeholders, P1 shared
  tokenizer/evaluation guardrails, production post-aligner fallback, and P3
  evaluation-stat de-duplication. Deferred the application orchestration
  extraction, application/persistence mega-file split, and forced-align
  monotonicity ablation into explicit architecture debt so Phase 2.2 can start
  without a risky broad refactor. Updated `.planning/STATE.md`,
  `.planning/codebase/CONCERNS.md`, and Phase 2.1 docs accordingly.
- 2026-06-19 15:55:21 CST: Marked the timeline-production / aligner-evaluation
  phase as temporarily closed and moved it into long-running research and
  production-script maintenance. Prepared Phase 2.2 planning docs for app-side
  `.lltimeline.json` resource UI alignment, covering resource import visibility,
  WordTimeline candidate summaries, active timeline selection, playback binding,
  and a later manual-review entry point.
- 2026-06-19 15:51:14 CST: Generalized the timeline-production post-alignment
  stage into a selectable degradation strategy. `produce-whisperx` now accepts
  `--post-aligner auto|mfa|mms-fa|none`; `auto` and `mfa` try MFA first, fall
  back to MMS_FA, and preserve the original WhisperX WordTimeline if all
  post-aligners fail, recording `post_alignment_failure` artifacts in the
  reusable `.lltimeline.json` resource. Added `apply-mms-fa-alignment`,
  extended `doctor` with MMS_FA runtime visibility, and updated contract
  dry-runs for the ordered fallback chain.
- 2026-06-19 15:41:28 CST: Paused further aligner benchmark expansion and
  documented deferred Qwen3-ForcedAligner, BFA/easytranscriber/CTC, and MMS_FA
  research directions under the timeline-production research docs. Advanced the
  current production mainline by adding MFA post-alignment orchestration to
  `scripts/timeline-production/production_pipeline.py`: `produce-whisperx` now
  supports `--post-aligner mfa`, appending an MFA `align-one` WordTimeline while
  preserving the WhisperX timeline as a candidate fallback, and
  `apply-mfa-alignment` can append MFA timings to an existing `.lltimeline.json`
  without rerunning WhisperX. Extended contract dry-runs for both production
  MFA entrypoints.
- 2026-06-19 15:19:15 CST: Completed the first MFA English US ARPA
  `align-one` TIMIT TEST 100 evaluation: 881/881 matched words, start MAE
  14.46ms, start P95 48.0ms, end MAE 18.20ms, end P95 53.0ms, tail mean abs
  34.12ms, tail P95 112.05ms, and no text mismatches. Updated Phase 4 docs to
  mark MFA as the strongest observed word-boundary aligner under a high-quality
  transcript/utterance-anchor condition, with WhisperX transcript + MFA as the
  next realistic production-route test.
- 2026-06-19 14:43:16 CST: Installed the local research-only MFA runtime via
  Homebrew `micromamba`, created the isolated MFA 3.3.9 environment under
  `~/Library/Caches/LLPlayerNext/research/mfa/env`, and updated the MFA setup
  and alignment sidecar scripts to force `MFA_ROOT_DIR` into the same research
  cache and prepend the MFA environment's `bin` directory to subprocess `PATH`
  so model files, MFA temporary defaults, and OpenFST/Kaldi binary resolution do
  not spill into `~/Documents/MFA` or the user's shell profile. Added a
  parallel `align-one` MFA sidecar strategy after batch `mfa align` reached
  successful first-pass alignment on TIMIT TEST 100 but failed in MFA's SQLite
  interval collection/export path with empty interval CSVs; `align-one` now
  resolves saved dictionaries and pre-extracted acoustic model directories
  before launching parallel jobs and gives each MFA child process an isolated
  `MFA_ROOT_DIR` to avoid concurrent model-cache extraction and
  command-history YAML writes.
- 2026-06-19 11:44:19 CST: Expanded the TIMIT TEST 100 alignment benchmark
  comparison across MMS_FA + TIMIT transcript, full WhisperX CLI, and
  WhisperX CLI + MMS_FA post-alignment; documented that MMS_FA remains the best
  current upper-bound route with a high-quality transcript, while the WhisperX
  CLI + MMS_FA post-pass improves start timing but regresses end/tail timing.
  Added the research-only MFA sidecar scaffold (`setup-mfa-research.sh`,
  `mfa-align-cli.py`) plus TextGrid parser contract coverage, with MFA
  installation and real runs still pending because this machine does not yet
  have `mfa`, `conda`, `mamba`, or `micromamba` available.
- 2026-06-19 11:00:47 CST: Implemented the M2.1 P1 tokenizer/evaluation
  guardrail: added shared `scripts/lltimeline_common.py`, moved benchmark,
  production, and evaluation tooling onto the same word normalization/token
  helpers, added regression coverage for multi-apostrophe words, and extended
  word timeline comparison reports with normalized text mismatch counts, rates,
  and samples.
- 2026-06-19 10:54:54 CST: Implemented the M2.1 P0 forced-alignment
  `word_index` contract fix: `align-cli.py` now emits `skipped: true`
  placeholders using unfiltered word indexes, `forced_align::merge_alignments`
  treats placeholders as per-word DTW fallback, contract tests cover CJK and
  punctuation skip cases, and ADR 0011 / M2.1 planning docs now match the
  existing top-level `timings[]` sidecar JSON shape.
- 2026-06-18 20:45:41 CST: Fixed the timeline-production research venv setup
  to install with `uv pip`, downloaded and smoke-loaded the WhisperX
  `large-v3` ASR stack plus the English wav2vec2 alignment model, added
  `scripts/timeline-production/whisperx-align-request.py` for known-transcript
  benchmark alignment, and produced the first TIMIT TEST 20 WhisperX alignment
  report: 171/171 matched words, start MAE 65.50ms, start P95 141.5ms, end MAE
  45.02ms, end P95 151ms, and tail lag mean -142.55ms.
- 2026-06-18 20:23:44 CST: Added TIMIT benchmark candidate tooling with
  `prepare-alignment-bundle` and `add-alignment-candidate`, fixed the MMS_FA
  sidecar for torchaudio 2.9 audio loading and tokenizer behavior, and produced
  the first real TIMIT TEST 20 MMS_FA evaluation report: 171/171 matched words,
  start MAE 56.38ms, start P95 128ms, end MAE 33.71ms, and end P95 81.5ms.
- 2026-06-18 20:15:11 CST: Validated local TIMIT full gold intake from
  `/Users/shadow/data/lisa/data/timit/raw`, generating local TEST/TRAIN
  LLTimeline gold resources under the research benchmark cache. Hardened the
  TIMIT converter for overlapping word rows, non-positive-duration rows,
  transcript-unmapped words, and leading/trailing apostrophe tokens, with
  smoke-test and contract validation coverage.
- 2026-06-18 19:47:03 CST: Reordered Phase 4 benchmark work to use existing
  high-quality gold corpora before CNN10/NBC self-built samples, documented the
  TIMIT → Buckeye → LibriSpeech alignments → news gold set sequence, added
  `scripts/benchmark-datasets.py timit-to-lltimeline` for local TIMIT
  `.WRD/.PHN/.TXT` conversion into `LLTimeline JSON v1`, and covered it with a
  synthetic TIMIT-style smoke fixture in contract validation.
- 2026-06-18 19:37:24 CST: Started Phase 4 evaluation work by adding
  document-level `compare-lltimeline` reports for comparing baseline,
  candidate, and gold word timelines inside one `.lltimeline.json`, including
  P95 boundary offsets, sentence-tail lag metrics, a multi-candidate LLTimeline
  fixture, contract validation coverage, and updated `.planning/` evaluation
  docs.
- 2026-06-18 19:30:22 CST: Completed Phase 3 Production Pipeline V1 by adding
  `production-report.json` generation for LLTimeline outputs, automatic report
  emission from `produce-whisperx`, contract validation for production quality
  reports, and `.planning/` status updates that move the project into Phase 4
  evaluation work.
- 2026-06-18 18:00:00 CST: Completed the `.planning/codebase/` documentation system.
  Renamed `CONVENTIONS.md` → `MAINTENANCE.md` (项目维护规则，与代码约定区分).
  Created three new codebase files: `STRUCTURE.md` (物理文件布局 + 新代码放哪),
  `CONCERNS.md` (技术债/已知问题/脆弱区域/测试缺口清单), and `CONVENTIONS.md`
  (项目级代码约定: crate 依赖规则、错误处理、异步、API 设计、Flutter/Python 模式).
  Added dedicated section for the unified test runner (`scripts/test.sh`) in TESTING.md.
  Co-Authored-By: Claude <noreply@anthropic.com>
- 2026-06-18 17:32:00 CST: Restructured the project documentation system by
  introducing the GSD-inspired `.planning/` directory as the project management
  hub. Moved `prd.md` → `.planning/PROJECT.md`, `roadmap.md` → `.planning/ROADMAP.md`,
  `requirements.md` → `.planning/REQUIREMENTS.md`. Created `.planning/STATE.md`
  as living project memory, `.planning/MILESTONES.md` as completed milestone index,
  `.planning/MAINTENANCE.md` as maintenance rules, and `.planning/codebase/` with
  ARCHITECTURE / STACK / DATA-MODEL / TESTING architecture skeleton docs.
  Consolidated `docs/discuss/` → `.planning/discuss/`, `docs/handoff/` →
  `.planning/handoff/`, `docs/timeline-production/` → `.planning/phases/2.0-
  production-engine/timeline-production/` (long-term subsystem). Migrated M2.0
  planning and feature docs from `docs/planning/`, `docs/features/`, and
  `docs/development/` into the 2.0-production-engine phase directory with
  upstream design notes in a dedicated `design-notes/` subdirectory. Frozen
  M1.x documents remain in `docs/` with index links from MILESTONES.md.
  Co-Authored-By: Claude <noreply@anthropic.com>
- 2026-06-18 16:08:50 CST: Added the `produce-whisperx` Phase 3 orchestration
  command to run media preparation, WhisperX execution, and LLTimeline
  conversion as one production pipeline entrypoint, with dry-run validation.
- 2026-06-18 16:06:35 CST: Added `run-whisperx` to the Phase 3 production
  pipeline with default/custom WhisperX command support, dry-run contract
  validation, run reports, and JSON output discovery for downstream LLTimeline
  conversion.
- 2026-06-18 16:02:53 CST: Extended the Phase 3 production pipeline with
  `prepare-media`, preprocessing artifacts, optional external vocal isolation
  command support, and LLTimeline artifact embedding for preprocessing reports.
- 2026-06-18 15:57:18 CST: Started Phase 3 production pipeline work with a
  research-only timeline-production script set, ffmpeg audio preparation,
  WhisperX JSON to `LLTimeline JSON v1` conversion, a sample WhisperX fixture,
  and contract validation coverage for the conversion bridge.
- 2026-06-18 15:53:09 CST: Completed Phase 2 resource lifecycle support for
  word timelines with summary, publish, archive-active, delete, OpenAPI/client
  coverage, and `lltimeline-resource.py` lifecycle commands; transcription job
  lifecycle methods are now represented in the handwritten local API client.
- 2026-06-18 15:36:01 CST: Completed the LLTimeline JSON v1 Phase 1 core by
  adding OpenAPI schemas, handwritten client methods, contract validation, and
  `scripts/lltimeline-resource.py` for validating, importing, and exporting
  `.lltimeline.json` files through the local API.
- 2026-06-18 15:21:41 CST: Added LLTimeline JSON v1 import support with
  `POST /v1/lltimeline/import`, round-trip HTTP coverage, and a minimal
  `.lltimeline.json` contract fixture that deserializes through the domain
  model.
- 2026-06-18 15:11:06 CST: Added the `docs/timeline-production/` documentation
  structure and started Phase 1 of the production-engine route with
  `LLTimeline JSON v1` domain contracts plus an HTTP export endpoint that wraps
  subtitle segments and active/candidate `WordTimeline` resources into a
  resource document.
- 2026-06-18 14:50:26 CST: Reframed the product definition around two
  coordinated tracks: a local heavy production engine for high-precision
  WordTimeline/PhoneTimeline/ChunkTimeline generation, evaluation, correction,
  and `.lltimeline.json` export; and a lightweight LLPlayerNext consumer that
  reads those resources for word highlighting and chunk playback without
  bundling heavy ASR/FA runtimes.
- 2026-06-18 11:40:04 CST: Transcription now preserves staged word timeline
  candidates from a single ASR run: raw Whisper DTW, MMS forced-alignment merge
  when available, and pause-refined final timings. The final stage is activated
  while prior candidates remain exportable for objective comparison without
  rerunning transcription.
- 2026-06-18 11:28:07 CST: Added a developer-facing word timeline evaluator
  that compares exported `WordTimeline` JSON files, reports weak DTW-vs-FA
  drift and anomaly metrics, optionally scores against gold word boundaries,
  and emits JSON/Markdown reports with smoke fixture coverage in contract
  validation.
- 2026-06-18 11:14:42 CST: Started Phase 1 word timeline resources with
  versioned `WordTimeline` domain contracts, SQLite schema v10 persistence,
  activation/archive semantics, active-timeline compatibility sync back to
  legacy `word_timings`, and HTTP management/export endpoints.
- 2026-06-18 11:07:27 CST: Added research-mode acoustic forced alignment for Whisper transcription:
  developers can prepare an isolated torchaudio MMS_FA venv, and transcription
  will auto-detect it, merge validated per-word aligned timings after DTW, and
  silently retain DTW timings when the sidecar is unavailable or fails.
- 2026-06-18 11:07:27 CST: Added transcription job regeneration and archiving
  support so subtitle timing experiments can rerun with current algorithms while
  old completed jobs stay queryable by id but hidden from the active job list
  and reuse lookup.
- Fixed development sidecar discovery: the Flutter desktop app now walks
  up directory ancestors to find the `api-http` binary (preferring
  `target/release` over `target/debug`), and the Rust API sidecar walks up
  from both its own executable path and the current working directory to
  locate `whisper-cli`, `ffmpeg`, and `ffprobe` inside
  `third_party/runtime/macos-arm64`. Together these fixes let the app find
  the full ASR toolchain when launched from anywhere inside the repository
  tree.
- Added `resolve_bundled_tool` and `runtime_candidates_from` to the
  transcription coordinator so the API sidecar discovers the bundled
  `whisper-cli` runtime by walking ancestor directories from both
  `current_exe` and `current_dir`. Flutter's sidecar resolution checks
  `target/release/api-http` before `target/debug/api-http`, so both
  profiles must be rebuilt after upgrading the Rust source.
- Started Milestone 2.0 Phase 0 with a fixed 60-slot real-speech evaluation
  catalog covering news, interview, conversation, speech rate, recording
  quality, and six target connected-speech phenomena.
- Added a provider-neutral phonetic evaluation tool that reports Phone Error
  Rate, detected-phone timeline validity, and subtitle-token association
  coverage, with success and failure smoke fixtures.
- Recorded candidate-provider roles, licensing constraints, a concrete Phase 0
  execution plan, and a proposed ADR that prevents product integration or
  `detected_in_audio` claims before quality and licensing gates pass.
- Added Vosk/Kaldi as a lightweight ASR and forced-alignment research baseline,
  without treating canonical decoder alignment as real detected-phone output.
- Proposed an AGPL/commercial dual-license direction and a permissive,
  versioned out-of-process provider SDK boundary while preserving the current
  no-license-granted repository state until legal and contributor preparation
  is complete.
- Added an isolated candidate-research harness that checks the pinned ZIPA
  dependency/artifact boundary, requires licensed external audio, rejects
  sequence-only output without phone timestamps, and records reproducibility
  and performance metadata.
- Added provider-neutral Milestone 2.0 domain contracts, schema v9 persistence,
  durable analysis jobs, detected-phone timelines, alignment findings, user
  feedback, API/events, and explicit model-management rejection paths.
- Added a deterministic research fixture that is disabled in normal builds,
  cannot be distributed as a model, never upgrades its low-confidence findings
  to `detected_in_audio`, and supports repeatable contract verification.
- Added desktop settings v8, current-sentence experimental analysis triggering,
  SSE progress refresh, detected-phone highlighting, and clearly labeled
  audio-detection results that remain hidden by default.
- Added focused widget coverage for the audio-analysis model/job center and
  distinct current-sentence and whole-track analysis triggers.
- Verified detected-phone highlighting across non-monotonic playback position
  changes and passed the existing packaged macOS build/runtime/signing smoke.
- Added `scripts/verify-m20.sh`, v8-to-v9 migration coverage, fake-provider
  idempotency checks, and low-confidence finding safety tests.
- Passed the complete M2.0 historical headless regression with 150 Rust tests,
  Flutter analysis, and 45 Flutter tests; the latest Flutter suite contains 46
  passing tests after the playback-position coverage increment.
- Passed the packaged macOS release build, bundled-runtime discovery, ad-hoc
  signing verification, extracted-package launch, video/audio smoke, and
  persistence checks.
- Milestone 2.0 remains incomplete: no real provider has passed the licensed
  evaluation, quality, performance, provenance, and distribution gates.
- Added an external evaluation-input manifest validator and preparation guide
  that check catalog membership, immutable audio checksums, explicit license
  decisions, bounded word/phone timelines, and independent human review before
  candidate development runs.
- Separated ZIPA code and model revisions and added a smoke-tested experimental
  CTC argmax frame-span projection, while retaining an explicit real-audio
  calibration gate before treating projected timestamps as stable.
- Added a research-only ZIPA CTC ONNX runner and explicit opt-in environment
  setup with pinned dependencies, separate code/model revisions, and
  checksum-verified external downloads.
- Started C2 acoustic-first partition quality with partitioner V2. Gap scoring
  now uses source-specific thresholds for ASR-reported, forced-aligned, and
  user-adjusted timings, while estimated timings remain excluded from acoustic
  evidence.
- Added moderate-gap evidence that can combine with punctuation support without
  overriding phrase protection on its own. Strong acoustic gaps remain able to
  split inside a text phrase.
- Treat punctuation from known ASR-generated subtitle tracks as inferred model
  output instead of a forced boundary. Inferred punctuation must combine with
  acoustic or product evidence before it changes the display partition.
- Reduced weak-evidence single-word fragments at chunk edges and added
  regression tests for ASR punctuation reliability, timing-source sensitivity,
  phrase protection, and fragment suppression.
- Added structured sentence chunk diagnostics containing selected and rejected
  boundary candidates, raw scores, thresholds, forcing state, primary source,
  and evidence. Product-facing partition responses remain unchanged.
- Added an initial golden calibration baseline covering ordinary short
  sentences, preferred-length splitting, single-word-tail suppression, and
  decisive acoustic gaps.
- Completed C2 acoustic-first partition quality. Readability scoring now
  favors supported boundaries near the preferred chunk length, weak evidence
  cannot create undersized fragments, soft/hard length limits prevent
  protected phrases from producing unreadably long chunks, and stronger
  phrase protection still yields to decisive acoustic gaps.
- Added a version-controlled V2 golden corpus covering fast speech, hesitation,
  moderate pauses, ASR-inferred versus trusted punctuation, fixed expressions,
  and long subtitles. The corpus enforces fragment and overlong-chunk quality
  bounds.
- Added `GET /v1/subtitles/{track_id}/chunk-diagnostics` for inspecting selected
  and rejected candidates using the same source-aware configuration as the
  product-facing track partition.
- Completed C3 rich acoustic evidence with partitioner V3. An independent
  pre-boundary-lengthening provider compares real word duration against a
  robust local baseline and can select meaningful boundaries without a pause.
- Added a conservative filled-pause hesitation provider that lowers boundary
  confidence around ASR-recognized `uh`, `um`, `erm`, `hmm`, and `mm` tokens.
  Ordinary hesitation gaps are suppressed while very large pauses remain
  eligible boundaries.
- Rich evidence is provider/version attributed, includes concrete measurement
  details, appears in existing chunk diagnostics, and is consumed as bounded
  signed score changes. Estimated timings and disabled/missing providers
  exactly degrade to C2 behavior.
- Added a C3 golden corpus covering no-pause lengthening, ordinary word
  durations, hesitation-gap suppression, and decisive pauses that survive the
  hesitation penalty.
- Completed C4 with an optional learned prosodic boundary provider and
  partitioner V4. The bundled project-authored MIT linear model runs locally,
  emits provider/revision/license-attributed evidence, and can assist only
  ambiguous rule-based boundaries.
- Added `GET /v1/chunk/providers` for inspecting learned-provider availability,
  runtime, and distribution metadata. Model or feature failures emit no
  evidence, and disabling the provider exactly preserves the C1-C3 pipeline.
- Added a C4 golden corpus covering learned-model contribution, ordinary
  delivery, decisive rule boundaries, and model-disabled fallback.
- Changed the default chunk presentation to static rounded capsules with clear
  visual spacing while preserving word-level highlighting inside each chunk.
  Current-chunk highlighting is now disabled by default and independently
  configurable as static background, slow scale bounce, or slow glow.
- Added an optional spacing-only chunk presentation and migrated existing v7
  desktop settings to the new static-capsule default.
- Added the Word Timing Accuracy milestone. Whisper DTW v2 now ignores
  punctuation timestamps when deriving lexical word edges and gives lexical
  alignment points a bounded duration so punctuation cannot consume audible
  pauses.
- Added optional local PCM energy pause refinement during Whisper
  transcription. Sustained audible pauses near coarse DTW boundaries restore
  adjacent word gaps as provider-attributed `ForcedAligned` timings, while
  missing or unsupported audio safely retains DTW timings.
- Changed timing precedence so refined forced alignment can replace coarse ASR
  timing while user-adjusted timing remains authoritative. Added
  `GET /v1/subtitles/{track_id}/word-timing-diagnostics` for inspecting final
  gaps and adjacent timing providers.
- Existing ASR tracks remain unchanged and must be re-transcribed to receive
  DTW v2 and audible-pause refinement.

## 0.7.2 - 2026-06-14

- Added the first user-visible chunk listening MVP. Primary subtitle sentences
  are rendered as complete, non-overlapping chunk groups and the active chunk
  follows playback using the existing local word-timing timeline.
- Added the stable `SentenceChunkPartition` display contract and V1
  acoustic-first rule partitioner. Real timing gaps, punctuation, phrase
  protection, and deterministic length fallback are resolved into one complete
  partition while estimated timings are excluded from acoustic evidence.
- Added `GET /v1/subtitles/{track_id}/chunk-partitions`, application-layer
  sentence and track partition methods, OpenAPI coverage, and independent
  fallback so chunk analysis failure never interrupts ordinary subtitles,
  word highlighting, or pronunciation enhancements.
- Added desktop chunk grouping and active-chunk highlighting settings. Chunk
  rendering preserves word clicks, vocabulary styles, and phrase interactions.
- Hardened text and acoustic chunk detection by rejecting invalid external
  phrase ranges, preventing phrase matches across punctuation, preserving
  empty-input sentence identity, and correcting gap-confidence interpolation.
- Added the staged C0-C4 chunk listening implementation plan. C0-C1 deliver the
  product loop; later milestones prioritize acoustic boundary quality and keep
  the display/API contract stable.
- Verified with workspace Rust tests, strict targeted clippy, Flutter analysis,
  Flutter tests, and whitespace checks.

## 0.7.1 - 2026-06-13

- Implemented text-level (lexical) chunk detection in the `speech-analysis` crate
  (`text_chunk_detection` module) as a companion to the existing acoustic
  (gap-based) chunk detection. The text detector partitions entire sentences
  into contiguous chunks where every word token belongs to exactly one chunk.
- Three data sources feed the text detector: (1) COCA n-gram collocations
  (MI ≥ 3.0, ~1K seed entries, compiled into the binary via `include_str!`),
  (2) PHRASE List (Martinez & Schmitt 2012, 505 pedagogically-selected
  functional phrases with category labels), and (3) existing ECDICT/built-in
  phrase candidates forwarded from the application layer.
- Sliding-window longest-match-first greedy overlap resolution ensures
  competing multi-word spans (e.g. "a lot of" vs "a lot") are resolved
  deterministically with longer spans taking priority.
- Cross-reference support between acoustic and text layers: new
  `BoundaryMarker::LexicalPhrase` variant, `CombinedChunkResult` type,
  `combine_chunks()` merging acoustic and text evidence with four-quadrant
  confidence logic (mutual-reinforcement, acoustic-only discount, text-only
  discount, no-signal), and `annotate_acoustic_with_text()` for decorating
  acoustic boundaries with lexical phrase markers.
- Added `AppServices::detect_text_chunks`, `detect_text_chunks_for_track`,
  and `detect_combined_sentence_chunks` methods.
- 18 new unit tests across `text_chunk_detection` covering empty/single-word
  input, COCA collocation matching, PHRASE List detection, external candidate
  forwarding, longest-match resolution, case-insensitive matching, partition
  coverage integrity, boundary count consistency, token order preservation,
  punctuation filtering, MI→confidence mapping, and source counts.

- Enabled whisper.cpp DTW (Dynamic Time Warping) token-level timestamps during
  ASR transcription so generated subtitle tracks produce `asr_reported` word
  timings instead of falling back to the weighted estimator.
- Added `-ojf` (JSON-full) and `-dtw <preset>` flags to the whisper-cli
  invocation. The JSON-full output carries per-token `t_dtw` cross-attention
  alignment timestamps in centiseconds.
- New `asr_timing` module merges whisper subword tokens into lexical words by
  leading-whitespace rules and produces `WordTiming` entries with
  `timing_source = asr_reported`.
- DTW is enabled only for `whisper`-family models; custom models skip the step.
- Every stage degrades safely: unavailable `t_dtw` values, segment count
  mismatches, word count mismatches, boundary violations, and non-monotonic
  timestamps all fall back to the existing deterministic weighted estimator on a
  per-sentence basis.
- The Flutter frontend, database schema, and `timing_priority` logic required
  zero changes — `AsrReported` (priority 3) already overrides `Estimated`
  (priority 1) in the existing word-timing pipeline.
- Established a unified testing workflow (`scripts/test.sh`) that consolidates
  `cargo fmt`, `clippy`, `test`, `flutter analyze`, `flutter test`, and contract
  validation into a single command with structured pass/fail summary output.
  Supports `--quick`/`--rust`/`--flutter`/`--full` modes, `--json` for
  machine-readable CI/AI output, `--verbose` for raw logs, `--debug` for
  internal tracing, and `--strict` to require `Cargo.lock`, deny Rust warnings,
  and make Flutter infos/warnings fatal. Successful-run logs are deleted;
  failed-run logs remain at the reported path while the terminal prints only
  the summary and key error lines.
- Extracted shared test utilities (`scripts/lib-testing.sh`) from the six
  `verify-m*.sh` acceptance scripts: cargo resolution, API lifecycle
  (start/stop/wait), curl helpers, and JSON assertion functions.
- Added the project's first Rust integration test
  (`crates/speech-analysis/tests/asr_timing_integration_test.rs`) with a
  real whisper `-ojf` JSON fixture covering subword merge, `t_dtw=-1` filter,
  special tokens, repeated DTW points, and boundary/segment-count mismatch
  fallback.
- Completed the ASR timing fix against real bundled whisper.cpp output:
  `[_BEG_]` / `[_TT_*]` special tokens and punctuation no longer corrupt the
  final lexical word, merged words are text-validated before mapping, repeated
  DTW points become deterministic non-empty intervals, and zero-duration word
  timings are rejected by the storage contract. Previously stored zero-length
  timing caches are detected as unusable and automatically fall back to the
  deterministic estimator.
- Updated CI to invoke `./scripts/test.sh --rust` and `--flutter` instead of
  individual `cargo`/`flutter` commands, keeping the same check coverage while
  producing more actionable failure logs.
- Migrated all 6 `verify-m*.sh` acceptance scripts to source `lib-testing.sh`,
  eliminating duplicated cargo resolution, API lifecycle, cleanup traps, and
  curl helpers. `setup_test_dir()` now registers cleanup automatically, API
  startup restores signal handling for graceful shutdown, and M1.7/M1.8 use
  the shared environment-aware `start_api()` path. Fixed schema drift (v6→v8)
  in verify-m17 and verify-m18 that accumulated across milestones.
- Added the project's second Rust integration test suite
  (`crates/persistence-sqlite/tests/persistence_integration_test.rs`) covering
  file persistence across reopen, migration backup creation, concurrent access
  safety, subtitle import/export, and media availability lifecycle (6 tests,
  25 total for the crate).
- Added `cargo-llvm-cov` coverage collection to CI (`lcov.info` artifact) for
  tracking coverage trends across PRs.
- Fixed the dictionary-provider parallel-test flake by replacing PID/time-based
  fixture paths with `tempfile::NamedTempFile`; 50 repeated parallel runs pass.
- Added 42 unit tests to the `application` crate (previously zero coverage)
  covering `require_text`, `clean_optional`, `normalize_american_english` (19
  irregular/suffix rules), `normalize_phrase`, `phrase_candidates` (including
  token boundary and non-word-token handling), `lexical_from_word`,
  `lexical_source_from_word`, and `timing_priority`. Total workspace tests
  increased from 58 to 100+.
- Fixed a boundary bug in `phrase_candidates` where sentences shorter than a
  phrase's word count could trigger an out-of-bounds index panic; corrected
  the window count formula.
- Set CI coverage gate at 50% line coverage (`--fail-under-lines 50` in the
  coverage job) to prevent coverage regressions, with a planned increase to
  55%+ as test coverage expands.
- Enhanced `./scripts/test.sh --quick` to include `cargo test --workspace
  --lib` (unit tests only, excluding integration/doc tests) while remaining
  under 30s. Quick mode now runs: fmt → clippy → lib unit tests → analyze.
- Added fuzz testing infrastructure with 3 fuzz targets:
  `crates/subtitle-core/fuzz/` (SRT and WebVTT parsing),
  `crates/speech-analysis/fuzz/` (ASR timing JSON extraction). The manifests
  are independent workspaces with committed lock files, the ASR target matches
  the current API, and CI runs every target for a 10-second nightly-Rust smoke
  test.
- Rewrote `testdata/README.md` as a comprehensive fixture catalog documenting
  every test data file, its purpose, and which tests consume it.
- Created `docs/features/testing-milestone.md` as the tracking document for
  the test system improvement initiative with P0/P1/P2 tiered goals and
  progress tracking.
- Added 16 unit tests to the `diagnosis-core` crate (2 → 18) covering all
  `diagnose` function branches: `MeaningBarrier`, `RecognitionBarrier`,
  `InsufficientInformation`, `OtherFactors`, mixed scenarios, non-word token
  filtering, `None` status handling, duplicate lemma dedup, and edge cases.
- Added `criterion` performance benchmarks for `subtitle-core` (SRT/VTT parse,
  tokenize, normalize) and `speech-analysis` (ASR timing extraction, word
  timing estimation). 10 benchmark cases in total covering small fixtures and
  large synthetic inputs (2k sentences, 500 segments). CI compiles all
  benchmarks with `cargo bench --workspace --no-run --locked`.
- Added `proptest` property-based testing with 10 property tests across
  `speech-analysis` (timing output count, monotonicity, bounds, start≤end)
  and `subtitle-core` (normalize idempotence, tokenize word normalization,
  SRT/VTT no-panic, SRT draft field validity). Total workspace tests: 132.
- Added API surface regression test (`openapi_version_snapshot`)
  in `api-http` that snapshots the OpenAPI 3.1.0 version, 51-path count, 18
  key schema definitions, and /v1/ prefix convention. Full semantic
  breaking-change detection remains future work.
- Added `scripts/test-infrastructure.sh` to test cleanup traps, API process
  teardown, quick/full mode selection, strict flags, JSON output, and retained
  failure logs. CI runs this self-test before desktop checks.
- Added `scripts/test.sh --low-memory` to limit Cargo, Rust-test, Rayon, and
  Flutter-test concurrency, reuse Flutter dependency resolution, and diagnose
  child exit code 137 as `SIGKILL` / external resource enforcement. Human
  output now emits a lightweight progress heartbeat before each check so quiet
  commands remain visible to external executors.
- Added a focused ASR word-timestamp handoff documenting the completed
  real-whisper validation, fallback/storage invariants, verification baseline,
  and the current environment's direct-script `SIGKILL` limitation.
- Prevented quick/full mode duplication: the Rust lib-test subset now runs only
  in `--quick`, while Rust/full modes execute the complete suite once.
- Fixed Rust test pass-through handling so arguments after the runner's `--`
  are forwarded after Cargo's test-harness separator.
- Added `.claude/worktrees/` to `.gitignore` so local product/refactor worktrees
  are not accidentally staged.

## 0.7.0 - 2026-06-13

- Integrated the modular Flutter controller/widget architecture while
  preserving Milestone 1.9 pronunciation and word-sync behavior.
- Fixed nullable controller state so media, subtitle, selection, diagnosis,
  and loop state can be cleared without retaining stale values.
- Provider-neutral pronunciation, phoneme, speech-rule, and word-timing
  contracts with schema v8.
- Pinned CMUdict canonical en-US pronunciation with deterministic fallback,
  lexical stress, ARPAbet, IPA display, variants, and token mapping.
- Deterministic bounded word timings for ordinary subtitles and local
  current-word highlighting that remains correct after seek, loop, and rate
  changes.
- Rule-based weak form, contraction, linking, flapping, deletion, and
  assimilation hints from a fixed 18-rule catalog that explicitly does not
  claim real-audio detection.
- Provider/version-isolated canonical pronunciation caching, explicit cache
  invalidation events, and non-blocking track jobs with cancellation and retry.
- Desktop settings v7, pronunciation diagnostics, API/event contracts, and
  Milestone 1.9 automated verification.
- Fixed current-word timing loading by reading the API contract fields
  `timing_source` and `provider_id`.
- Added background, scale-bounce, and glow current-word styles while keeping
  word-timing provenance in diagnostics instead of the playback overlay.
- Confirmed AV1 playback during collaborative functional acceptance.
- Removed the startup stall caused by re-hashing installed learning resources,
  added an explicit core-starting/error/retry screen, and fixed short-sentence
  ECDICT phrase scanning.
- Completed collaborative functional acceptance. Independent Developer ID
  distribution signing and notarization remain deferred release work.

## 0.6.0 - acceptance candidate

- Unified word and user-confirmed phrase learning assets with schema v7 and
  vocabulary asset bundle v3.
- Versioned lemma normalization, persistent corrections, and phrase candidates.
- Clickable phrase underlines in learning subtitles; confirmed phrases remain
  independent assets with their own status and source ranges.
- Explicit checksum-verified ECDICT and CMUdict resource manager.
- Provider-neutral OpenSubtitles title, filename, and media-hash workflows.
- Provider-supplied pronunciation audio in the unified word learning panel.
- Vocabulary asset v3 import preserves newer local state and independently
  merges learning content, history, and durable source encounters.

## 0.5.0 - 2026-06-10

Milestone 1.7 local ASR learning subtitle release.

- Provider-, runtime-, model-, and profile-neutral transcription contracts.
- Durable single-concurrency whole-media jobs with progress, cancellation,
  retry, restart interruption handling, provenance, and idempotent completion.
- whisper.cpp model catalog, explicit verified downloads, custom model
  registration, model management, and persistent job center.
- Generated subtitles become ordinary interactive learning tracks and support
  SRT export.
- Reproducible macOS arm64 whisper.cpp and LGPL-only FFmpeg runtime build,
  license validation, application bundling, and deterministic fake-runtime
  acceptance test.

## 0.4.1 - 2026-06-10

- Draggable viewport-relative subtitle placement, independent primary/secondary
  font controls, and a stable video viewport when subtitle visibility changes.
- Restored the media-kit video texture layout after the subtitle overlay
  refactor, fixing the black video screen regression.

## 0.4.0 - 2026-06-10

Milestone 1.6 desktop learning experience release.

- Responsive subtitle presets and automatic native-subtitle suppression.
- Simplified Chinese and English desktop localization.
- TXT/CSV existing vocabulary import with conflict-safe status initialization.
- Unified word learning panel with durable user definitions and notes.
- Provider-agnostic aggregated dictionary API and multi-source UI.

## 0.3.0 - 2026-06-10

Milestone 1.5 vocabulary learning asset release.

- Status-driven vocabulary books with user-selected status as the authority.
- Durable status history and source sentence snapshots.
- Missing-media recovery and independent vocabulary asset backup/restore.
- Latest-effective context observations with clear support.
- Schema v4 migration with legacy history and source backfill.

## 0.2.0 - 2026-06-09

Milestone 1 macOS Apple Silicon MVP.

### Added

- Local video/audio playback and complete subtitle-learning loop.
- SRT/WebVTT import, interactive transcript, sentence navigation and loop.
- Word status, dictionary lookup, context observations, and diagnosis.
- Dual text subtitles with independent offsets.
- Drag-and-drop import and configurable subtitle appearance/layout.
- Embedded text-subtitle extraction through optional ffprobe/ffmpeg.
- Online-media URL resolution through optional yt-dlp.
- Versioned local settings, progress recovery, diagnostics, and release package.

### Deferred

- Windows/Linux, OpenSubtitles, bitmap subtitle interaction, mobile, ASR, and
  translation.
