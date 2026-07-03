---
gsd_state_version: 1.0
milestone: v0.5.0
milestone_name: milestone
status: active
last_updated: "2026-07-02T13:35:00.000+08:00"
progress:
  total_phases: 11
  completed_phases: 1
  total_plans: 4
  completed_plans: 0
  percent: 0
---

# LLPlayerNext — 项目活记忆

> 最后更新：2026-07-01 CST
> 更新原因：Phase 2.20 deterministic RhythmFrame v0 已落地到 `sound_analysis.rhythm_frame`、
> OpenAPI、Flutter typed model、字幕层 rhythm-first ribbon、Rhythm A/B/C 就地快切、
> 字幕 expected pronunciation reference、字幕 rhythm cue loop、诊断卡 compact rhythm 区块，
> 并新增仓库内可重复运行的 RhythmFrame QA/scorer fixture gate；Phase 2.19 phone
> benchmark scoring 继续作为底层 evidence-quality 支撑。2026-06-30 已将 Phase 2.20
> benchmark 方向重组为 stress/rhythm 分层体系，并把算法/指标必须有研究、标注或
> product QA 依据的原则写入根目录 `AGENT.md`。同日路线复盘确认：`RhythmFrame`
> 产品 contract 正确，但 generator 主线需要从 CTC-derived rhythm 迁移到 forced-aligned
> WordTimeline + duration/rate + RMS energy/F0 的 layered hybrid。2026-06-30 17:37 CST
> 新增 Phase 2.21 Audible Structure Architecture，单独落实 actual audible structure
> contract；旧 `RhythmFrame` v0 兼容性不再阻塞新模型。2026-07-01 端到端使用路径复盘确认：
> 当前所有用户功能的前端语义、入口、状态和降级路径不够清晰，新增 Phase 2.22
> User-Facing Workflow Semantics，专门收敛本机 Whisper 默认路径、资源能力可用性、
> Listening structure / Phone evidence 语义分层、typed status 和端到端 QA。
> 2026-07-01 Phase 2.22 前端 P0 切片已落地（Step 0 audit、capability readiness、资源能力面板、
> Local Whisper 默认路径、typed download/task feedback、布局入口、前端 E2E QA 清单），但复核
> 发现 GPT 遗漏了用户可见状态机建模、Capability Stack 的 L 层号自相矛盾、readiness 仅覆盖 5/11
> 能力层且“前端 closeout 已完成”属高估。本次已重建 `2.22-USER-VISIBLE-STATE-MACHINE.md`（真正的
> 用户可见状态机 + 能力就绪 lane）、修正 `2.22-FEATURE-SEMANTICS-MODEL.md` 层号并新增 Model↔Code
> 对账、把 `2.22-CURRENT-FEATURE-INVENTORY.md` 改为覆盖清单 + 已验证 P0 模板，并纠正记账；余下
> OPEN 项（SM-01..SM-08）转入真正的前端重构。
> 2026-07-01 17:48 CST 明确 consumer self-contained invariant：bundled whisper.cpp
> 产出的 WordTimeline 必须解锁全部基础功能，sidecar 只升级质量。Rust 已接管 per-word
> RMS energy 与 F0/pitch，转录 WAV 删除前写入 acoustic cue artifact；`AsrReported`
> 作为低精度音频时序参与 RhythmFrame。W8 改为校准/回归用途，不再阻塞轻量 DSP 采用。
> 2026-07-01 18:34 CST 字幕层完成 Rhythm A/B/C 视图：A 词典独立读音、B 规则预测语流、
> C 当前实际听感；Phones 不再占用一级模式，只在 C 内作为 L4 evidence 按需展开。旧
> `rhythm` / `phones` 设置统一迁移到 `actual`，避免升级后丢失可用视图。
> 2026-07-02 13:35 CST 全库架构审核后新增 Phase 2.23 Architecture Debt Paydown（🧭 已建档未开工）：
> 收口 main.dart god file / sound_analysis.rs 单文件膨胀 / 文档事实源漂移 /
> Dart 手写解析无契约守卫 / 巨型测试文件五项债务，只做机械治理不改行为。
> 2026-07-02 13:50 CST 方向决策：Phase 2.19/2.20/2.21 speech-analysis 算法线整体搁置，
> 主线转入 Phase 3.x 英语听力学习闭环（英语先行）；闭环完成后再回到算法质量提升。
> Phase 2.23 相应调整：main.dart 收缩（A1）升为最高优先（3.x Flutter 工作前置），
> sound_analysis 拆分（A2）改在算法线静默窗口内做、零并行冲突。

## 当前位置

- **里程碑**：Milestone 2 — 本地重装生产引擎
- **Phase**：Phase 2.10 ✅ 端到端验证通过 +
  Phase 2.11 ⏳ Steps 1-3 完成（Step 4-5 待推进）+
  Phase 2.13 ✅ 文字线音素 Ribbon 收口完成 +
  Phase 2.14 ✅ 声音线学习架构收口完成 +
  Phase 2.15 ✅ 声音线学习 UX 收口完成 +
  Phase 2.16 ✅ 真实语流模型 v1 收口完成 +
  Phase 2.17 ✅ 真实媒体声音线 QA 已收口 +
  Phase 2.18 ✅ 代码架构全面重构已收口 +
  Phase 2.19 ⏸ 真实 benchmark scoring 已搁置（初始评估已落地）+
  Phase 2.20 ⏸ Rhythm-first 真实听感分析已搁置 +
  Phase 2.21 ⏸ Audible Structure Architecture 已搁置 +
  Phase 2.22 ✅ User-Facing Workflow Semantics 已收口（手工 smoke 待跑）+
  Phase 2.23 🧭 Architecture Debt Paydown 已建档 +
  Phase 3.0 ⏳ 英语听力学习闭环（当前主线，2026-07-02 起）+
  Phase 3.0.1 ✅ backend 学习行为架构地基已落地
- **分支**：`main`
- **版本**：0.7.0

## 项目双路线

自 2026-06-18 起，项目拆分为两条协同路线：

| 路线 | 目标 | 当前状态 |
|---|---|---|
| 本地重装生产引擎 | 生成精准 WordTimeline / ChunkTimeline / LLTimeline JSON | ✅ 阶段性收口，转长期研究 |
| 轻量消费端 LLPlayerNext | 稳定读取 `.lltimeline.json` 并播放学习 | ✅ Phase 2.22 已收口（手工 smoke 待跑）；剩余 SM 项已明确 defer |

## 后续产品方向

### Phase 2.20: Rhythm-first Listening Analysis ⏸ 已搁置（2026-07-02）

> 2026-07-02 起搁置：speech-analysis 算法线整体暂停，主线转入 Phase 3.x 学习闭环；
> 本 phase 未尽项（scorer、benchmark adapter 等继续作为脚手架保留）在算法线重启时续推。

- 目标：把真实语流分析从 phone-level 默认展示转为 rhythm-first listening frame，
  先回答“这句话实际怎么听、该抓哪些声音锚点、哪些区域被弱读/压缩/连起来”。
- 核心决策：
  - 单词问题由现有 lexical learning path 承接。
  - 声音识别问题默认先展示 stress anchors、weak groups、compression spans、
    phrase boundaries 和 listening hotspots。
  - Phone-level expected/observed alignment 保留为 evidence layer 和长期模型质量工作；
    当前 PER 较高不应阻塞 rhythm-frame UI。
  - Phase 2.19 的 TIMIT/Buckeye/TED-LIUM scoring 继续用于 phone/text/timing evidence quality，
    但不再作为唯一产品 gate。
  - Benchmark 方向已从 phone-first 重新组织为 stress/rhythm tiers：
    TIMIT 退回 evidence-quality，Helsinki Prosody / LibriTTS prosody labels 作为首选
    public weak-label regression，BU Radio Speech / RaP / Aix-MARSEC/ProPOSEC 作为可选
    human prosody gold，Buckeye/TED/product media 继续承担 product listening QA。
- 已落地：
  - `SoundAnalysis` 新增可选 `rhythm_frame`，包含 stress anchors、weak groups、
    compression spans、phrase boundaries、listening hotspots 和 quality。
  - `speech-analysis::sound_analysis` 已实现 deterministic v0：使用 CMUdict/fallback
    lexical stress、function-word grouping、phone timing pause/duration 和 connected-speech
    evidence；raw phone mismatch 不会单独生成高置信默认听感解释。
  - Flutter typed model 与诊断卡已能显示 compact rhythm-first 区块，phone chips/findings
    继续作为后续 evidence layer。
  - 字幕层声音模式已从历史 `rhythm` / `phones` 二选一升级为 Rhythm A/B/C：A 展示词典
    citation，B 展示 default connected rule 及 A → B 音标变化，C 展示当前 RhythmFrame、
    声音锚点、弱读音团、压缩区和听感热点。Phones 作为 C 内可展开 L4 evidence 保留；
    点击 C 的 rhythm cue chip 仍可复用 source loop 直接复听对应听感区间。
  - Rhythm/listening QA 初版工具已落地：`testdata/rhythm-frame-qa/` 提供标注 schema/template，
    `scripts/evaluate-rhythm-frame.py` 可对 Phase 2.17 manifest 输出 RhythmFrame 覆盖率和手工
    标注匹配分，并校验 duplicate/invalid score/unknown sentence 等标注问题；旧 `.tmp`
    artifacts 初始基线为 8 cases / 51 phone timelines / 0 rhythm frames。
    scorer 现支持可配置 closeout gates：`--min-rhythm-coverage`、
    `--min-annotated-sentences`、`--min-overall-useful-rate`、
    `--max-hotspot-misleading-rate`、`--max-hotspot-unsupported-rate` 和
    `--fail-on-quality-gate`。
    `testdata/rhythm-frame-qa/fixture-*` 现提供 committed synthetic LLTimeline + annotations，
    可在不重跑本地媒体的情况下验证 strict annotation validation 与质量门禁 CLI 路径。
    本机 smoke 重跑 `p217-brooklyn-news-001 --sentence-limit 1` 已生成 1 条 RhythmFrame，证明
    runner → algorithm → scorer 链路可用（ignored `.tmp` 本地 artifact，不提交）。
  - Helsinki/LibriTTS weak-label benchmark adapter 已落地：
    `scripts/evaluate-helsinki-prosody.py` 可解析 Helsinki Prosody prominence / word-boundary
    labels，并在提供 LLTimeline manifest 时评分 `RhythmFrame.stress_anchors` 和
    `phrase_boundaries`；`testdata/rhythm-prosody-benchmarks/` 提供 committed fixture 和 CLI
    gate，不提交 LibriTTS 音频或完整 Helsinki corpus。
  - LibriTTS/Helsinki local prep 已落地：
    `scripts/prepare-helsinki-libritts-benchmark.py` 可从 extracted LibriTTS split 目录或
    `/Users/shadow/Downloads/dev-clean.tar.gz` / `test-clean.tar.gz` 这类 split archive 中只抽取
    selected wav 到 `.tmp`，生成 baseline LLTimeline 和 dual-use manifest；本机 `dev --limit 3`
    smoke 已准备 3/3 样本，并由 evaluator 正确报告为 `missing_rhythm_frame`（等待 API refresh）。
  - Algorithm/metrics calibration 原则已建档：
    `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ALGORITHM-METRICS-RESEARCH.md`
    明确当前项目指标、小样本 smoke 和 Helsinki automatic labels 都不是“真理”，算法/指标变更
    需要对齐 published prosody/phonetics baselines、corpus annotation convention 或 manual
    product QA。
  - LibriTTS/Helsinki 3-sentence smoke 已跑通 local API refresh：3/3 生成 `rhythm_frame`，
    silver-label diagnostic score 为 stress anchor F1 0.827586、phrase boundary F1 0.285714；
    该数值只用于诊断，不作为 gate。
  - Helsinki/LibriTTS scorer report 已新增 `benchmark_context`：明确 benchmark role 为
    `weak_prosody_regression`、evidence class 为 `silver_label`，记录 Helsinki label 语义、
    Talman et al. 2019 BERT text-model prominence baselines（2-way accuracy 0.832、3-way
    accuracy 0.686），并说明这些 baseline 只是校准上下文，不能直接等同 end-to-end audio
    RhythmFrame F1。
  - Benchmark role manifest 已落地：
    `testdata/rhythm-prosody-benchmarks/benchmark-roles.json` 约定
    `evidence_quality`、`weak_prosody_regression`、`human_prosody_gold`、
    `product_listening_qa`、`robustness_probe` 五类角色、默认 evidence class、closeout use 和
    local-only 数据政策；`scripts/test_rhythm_benchmark_roles.py` 负责防止角色约定漂移。
  - 第一条 research-backed acoustic prosody feature path 已选定并实现：
    `2.20-ACOUSTIC-FEATURE-PATH.md` 将 pre-boundary final lengthening / local
    rate-normalized duration evidence 定为 Phase 2.20 的首个边界补强路径；
    `speech-analysis` 的 RhythmFrame phrase boundaries 现在可在无明显 pause 但边界前词显著
    拉长时输出 `evidence = "pre_boundary_lengthening"`。
  - 路线校正已建档：
    `2.20-ROUTE-CORRECTION.md` 明确 Phase 2.20 的目标是 actual audible structure，而不是
    default predicted reading；当前 `stress_anchors` 主要是 `text_predicted` prior，CTC phone
    evidence 应降级为 flapping/deletion/weak-form/phone-mismatch 等 segmental evidence，不再作为
    rhythm skeleton。主线改为 D -> F：forced-aligned WordTimeline + duration/rate + RMS
    energy/loudness，F0/pitch reset 作为校准后正式候选。
  - 最新本地 Helsinki/LibriTTS dev `limit 20` diagnostic 已完成：20/20 scored，
    stress anchor F1 0.574949，phrase boundary F1 0.210145，
    predicted boundary evidence counts 为 pause 218 / pre_boundary_lengthening 17；
    该结果只说明当前 CTC-derived baseline 过切 boundary，不能作为 gate。
  - Duration/RMS manual QA 对比实验工具已落地：
    `scripts/prepare-rhythm-acoustic-qa.py` 可读取 manifest / LLTimeline / 本地音频，
    输出 current CTC-derived `RhythmFrame`、active WordTimeline duration/rate 和 per-word
    RMS energy/loudness 三路对比；`--emit-template` 可生成带 `system_compare` 的
    manual annotation JSONL。该脚本只产出 `heuristic_proxy` / `manual_product_qa_input`
    实验材料，不写回产品资源。
  - 根目录 `AGENT.md` 已新增 Algorithms And Metrics 原则：已有项目数据、小样本 smoke、
    自动标签和当前指标不默认视为真理；算法/指标/阈值要尽量来自 published research、
    corpus annotation convention、reported tool baseline 或 manual product QA；有合理依据时
    可以大胆尝试，但必须标明 evidence class 和用途。
  - OpenAPI schema、Rust unit tests、Flutter widget test 和 contract validation 已同步。
- 下一步：
  1. 结构主线已转入 Phase 2.21：先重写 audible-structure / RhythmFrame contract。
  2. `scripts/prepare-rhythm-acoustic-qa.py` 暂作为 Phase 2.21 的 experiment seam，
     等 contract 稳定后再用于人工 QA 和 duration/energy 候选校准。
  3. Phase 2.20 已落地的 UI、scorer、Helsinki/LibriTTS adapter 和 benchmark roles 作为
     Phase 2.21 的脚手架继续复用。
- 规划文档：
  - `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-CONTEXT.md`
  - `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-PLAN.md`
  - `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-BENCHMARK-RESEARCH.md`
  - `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ALGORITHM-METRICS-RESEARCH.md`
  - `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ROUTE-CORRECTION.md`
  - `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ACOUSTIC-FEATURE-PATH.md`
  - `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-EVALUATION.md`

### Phase 2.21: Audible Structure Architecture ⏸ 已搁置（2026-07-02）

> 2026-07-02 起搁置：speech-analysis 算法线整体暂停，主线转入 Phase 3.x 学习闭环；
> W8 人工标注/阈值校准与端到端回归在算法线重启时续推。audible-structure v1 contract
> 保持为当前权威 shape，Phase 3.x 按现状消费，不在搁置期内改动。

- 目标：把 Phase 2.20 的 rhythm-first UI/实验铺垫上升为正式 actual audible structure
  architecture，并重写 `RhythmFrame` 的权威 contract。
- 核心决策：
  - 本 phase 可以不保留旧 `RhythmFrame` v0 兼容性；正确 structure 优先。
  - actual/audible claim 必须有至少一个 audio-backed signal：
    `timing`、`energy`、`pitch` 或 `phone_segmental`。只有 `text_prior` 的 claim
    必须标为 predicted。
  - 三参考模型是权威 expected-side 结构：citation form、default connected variants、
    actual delivery；`B-A` 是 teachable rule，`C-B` 是 clip-specific surprise。
  - L1-L3 RhythmFrame 必须能由 WordTimeline + dictionary/syllable structure +
    duration/energy 生成；CTC phone evidence 只拥有 L4 connected-speech/segmental
    evidence。
  - Nucleus 是 phrase-scoped learner-facing candidate；低证据 phrase 可以 abstain，
    不硬判。
- 已落地：
  - 新增 `.planning/phases/2.21-audible-structure-architecture/2.21-AUDIBLE-STRUCTURE-MODEL.md`
    作为 architecture lock。
  - 新增 `2.21-CONTEXT.md` 和 `2.21-PLAN.md`，明确本 phase 从 Phase 2.20 分离，
    并把 duration/RMS harness 降级为 experiment seam。
  - Step 1 contract rewrite 已落地：Rust domain、OpenAPI、Flutter typed model、
    subtitle ribbon、diagnosis card、RhythmFrame QA scorer、Helsinki scorer 和
    committed fixtures 已同步到 audible-structure v1 shape，包含 A/B/C references、
    signal-source/evidence-class provenance、prominence cues、phrase-scoped nuclei、
    connected-speech refs 和 quality signal sources；旧 v0 fixture 不再作为 active
    compatibility target。
  - Step 2 generation boundary 第一刀已落地：phonetic-analysis 构建 `sound_analysis`
    时会读取 active WordTimeline 的当前句 `WordTiming`，`RhythmFrame` L1-L3 token
    substrate 优先使用 WordTimeline timing + dictionary/canonical syllable stress；
    新增 no-phone-evidence 单元测试，证明 observed CTC phone evidence 为空时仍可生成
    anchors、phrase-scoped nuclei、weak groups、compression spans 和 phrase boundaries。
    无 WordTimeline 时才退回 `legacy_phone_timing_adapter_v1` /
    `phone_timeline_transitional`。
  - Step 2 energy cue seam 已落地：`SoundAnalysisConfig` 可接收 sentence-scoped
    `RhythmWordAcousticCue`，`speech-analysis` 会把 word-level `energy_prominence`
    传播到 stress anchor prominence、phrase-scoped nucleus selection、
    `generated_from = wordtimeline_timing_acoustic_prominence_v1`、
    `references.actual.source = word_timeline_duration_energy` 和
    `quality.prominence_sources`。W4 已补上 artifact path，Rust consumer baseline 现已
    直接生成 RMS/F0；W8 用于校准，不能把临时阈值当最终 release gate。
  - 新增 committed no-phone LLTimeline fixture / scorer smoke：
    `testdata/rhythm-frame-qa/fixture-no-phone-rhythm.lltimeline.json` 覆盖
    `phone_evidence_coverage = 0.0`，且 W3 后会携带 text-prior B-side
    connected-speech refs；anchors/nuclei/weak/compression/boundary/hotspot 仍不依赖
    observed phone evidence。
  - Review backlog W1 honesty fix 已落地：`RhythmToken` 会记录 WordTiming 是否来自
    audio-backed source；只有 `ForcedAligned` / `AsrAligned` / `UserAdjusted` 可产生
    `Timing` signal source 和 `AudioSupported` L1-L3 claim，`Estimated` timing 只产生
    `TextPrior` / `Predicted` anchors 且不选 nucleus。
  - Review backlog W2 first-class WordTimeline → RhythmFrame path 已落地：
    `LLTimelineDocument` 新增 document-level `rhythm_frames` resource；application
    export 会从 active WordTimeline + dictionary/canonical stress 直接生成 L1-L3
    `RhythmFrame`，不需要 phonetic-analysis job、PhoneTimeline 包装或 synthetic phones。
    Flutter 字幕 rhythm layer 会按 sentence 优先消费 document-level rhythm frame，再
    fallback 到 `PhoneTimeline.sound_analysis`。
  - Review backlog W3 Reference B rule engine 已落地：
    `speech-analysis::connected_speech_rules` 会从英语文本生成 default connected forms
    作为 B reference，包括约 50 个 function-word weak forms、`could have -> K UH D AH V`
    等 phrase reductions、linking、t/d weakening、assimilation、contraction 和 flapping。
    `RhythmFrame.connected_speech_refs` 现在用真实 B 区分 `teachable_rule` 与
    `clip_specific`；纯 B 预测保持 `TextPrior` / `Predicted`，不会伪装成 actual audio。
  - Consumer closure 已落地：`speech-analysis::word_acoustics` 从本机 Whisper 的 16k
    mono WAV 直接计算 per-word RMS relative prominence、F0 median/range、pitch
    prominence 与 pitch reset，并在临时 WAV 删除前写入
    `rhythm_word_acoustic_cues` artifact。application export 将 energy/pitch cue 注入
    RhythmFrame；anchor/nucleus 可带 `Energy`/`Pitch` provenance，明显 pitch reset 可支持
    phrase boundary。Python production artifact 保持兼容，作为更高质量覆盖来源。
  - `TimingSource::AsrReported` 现视为低精度但真实的音频时序，可驱动 duration、compression
    和 boundary；只有 `Estimated` 保持纯文本预测。转录链路不再吞掉 WordTimeline/acoustic
    持久化错误。
  - Review backlog W5 Reference A OOV hardening 已落地：CMUdict missing word fallback
    升级为 `fallback-v2`，支持常见 English digraph、soft c/g、final silent e、x，并只给
    第一个 fallback vowel primary stress，后续 vowel 标 unstressed，避免 OOV citation
    structure 把多个 syllable 都伪装成 primary stress。
  - Review backlog W6 information-structure prior 已落地：RhythmFrame anchor scoring
    会轻微降低重复 content word 的 text-prior prominence，并给 phrase-final content
    一个小 focus boost；该 cue 仍属于 `TextPrior`，不会在缺少 timing/energy/pitch/phone
    evidence 时升级 claim status。
  - W8 product QA tooling 已推进但未 closeout：
    `scripts/evaluate-rhythm-frame.py` / `annotation.schema.json` / fixture labels
    现在把 `nuclei` 和 `connected_speech_refs` 纳入一等 manual QA 字段；scorer 新增
    `--template-require-rhythm-frame` / `--limit` template 输出，以及
    `--min-rhythm-frame-sentences`、`--min-word-timeline-rhythm-sentences`、
    `--min-energy-prominence-sentences` gates。当前本地 Phase 2.17 real-media manifest
    readiness 为 47 句中仅 1 个旧 v0 phone-timeline RhythmFrame，0 个 WordTimeline
    RhythmFrame，0 个 energy prominence RhythmFrame，0 条 manual labels；因此 W8
    仍需先用当前 production pipeline regenerate 5-10 条真实句，再人工标注。
  - W8 local product QA pack 已生成：
    Brooklyn product media 通过 active WordTimeline + `rhythm_word_acoustic_cues`
    + API import/export 刷新到 `.tmp/rhythm-frame-qa/w8-product/brooklyn-w8.lltimeline.json`；
    readiness gate 显示 114/114 `wordtimeline_timing_acoustic_prominence_v1`
    RhythmFrames。已选 10 条产品 QA 句子并生成
    `.tmp/rhythm-frame-qa/w8-product/annotations-template.jsonl`、
    `.tmp/rhythm-frame-qa/w8-product/selected-sentences.md` 和 10 个 local wav clips。
    空模板 strict validation 通过但 `annotated_sentence_count = 0`，manual labels 仍未完成。
  - W8 generation 修复了一个 application import remap bug：
    `remap_lltimeline_sentence_ids` 现在会同步重写
    `rhythm_word_acoustic_cues.payload.timeline_id` 和 cue-level `sentence_id`，
    避免导入后 acoustic cue artifact 因 WordTimeline/sentence id 重映射而脱钩。
- 下一步：
  1. 推进 W8：填写 `.tmp/rhythm-frame-qa/w8-product/annotations-template.jsonl`
     的人工标签，校准 Rust RMS/F0 阈值并记录 octave/voicing 失败模式。
  2. 增加真实本机 Whisper job 的端到端回归，验证 active WordTimeline、acoustic artifact、
     RhythmFrame 与 Flutter listening layer 连续可见。
- 规划文档：
  - `.planning/phases/2.21-audible-structure-architecture/2.21-CONTEXT.md`
  - `.planning/phases/2.21-audible-structure-architecture/2.21-PLAN.md`
  - `.planning/phases/2.21-audible-structure-architecture/2.21-AUDIBLE-STRUCTURE-MODEL.md`

### Phase 2.22: User-Facing Workflow Semantics ✅ 已收口（手工 smoke 待跑）

- 目标：把当前所有用户功能组织成清晰、可发现、可降级、可验证的用户路径，包括媒体播放、
  URL/下载、拖拽、字幕获取、资源管理、Word sync、Chunk replay、Listening structure、
  Phone evidence、词汇、诊断、设置、任务中心和 practice/review backend readiness。
- 触发背景：
  - 端到端复盘发现，普通用户路径不是“消费 JSON 字段”，而是：
    `打开媒体 -> 本机 Whisper 生成字幕 -> 自动获得 Word sync / Listening structure
    可用性 -> 播放中使用听感结构、词汇诊断和练习`。
  - 当前 UI 仍混用 `sound pattern`、`phonetic analysis`、`rhythm`、`timeline resource`
    等内部或历史语义，Settings 中的开关也承担了过多功能发现职责。
  - `worktree-ui-feature-semantic-mapping` 的用户可见状态机/功能交互图提供了方法论输入，
    但该 worktree 早于 2.21，不能直接作为当前事实源。
- 核心决策：
  - “功能完成”必须包含入口、前置条件、能力状态、降级说明、下一步行动和端到端验证。
  - 主要 UI 应使用用户语义：Subtitles、Word sync、Chunk replay、Listening structure、
    Phone evidence、Vocabulary、Diagnosis、Practice/Review readiness。
  - 内部名如 WordTimeline、ChunkTimeline、PhoneTimeline、RhythmFrame、LLTimeline、
    provider id 和 artifact 仍可在高级资源详情中展示。
  - Settings 只配置偏好，不应成为发现主要学习能力的唯一入口。
  - 自由字符串 status 不应继续控制核心 UI 行为；关键工作流需要 typed readiness/task state。
- 初始验收路径：
  1. Local Whisper default path：
     `Open media -> Generate subtitles -> Generated track loads -> Word sync ready
     -> document-level rhythm_frames render as Listening structure`。
  2. Plain SRT/VTT path：字幕、词汇和基础诊断可用；缺少 Word sync / Listening structure
     时明确降级。
  3. LLTimeline resource path：资源面板展示 Word sync、Chunk replay、Listening structure、
     Phone evidence 和 artifacts 的能力摘要。
  4. Missing evidence path：缺少 WordTimeline、`rhythm_frames`、phone evidence 或 energy
     时，不把 predicted/text-prior claim 伪装成 measured audio。
- 已落地：
  - 新增 `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CONTEXT.md`。
  - 新增 `2.22-FEATURE-SEMANTICS-MODEL.md`，定义用户可见能力栈和 readiness states。
  - 新增 `2.22-CURRENT-FEATURE-INVENTORY.md`，基于 `worktree-ui-feature-semantic-mapping`
    的功能图建立全功能审计种子清单，并要求后续按当前 main 校验。
  - 新增 `2.22-PLAN.md`，按 UI audit、capability readiness、本机 Whisper 默认路径、
    资源面板、Listening structure 语义、typed status、布局入口和端到端 QA 分步推进。
  - Step 0 audit 已完成，覆盖媒体/播放、URL/下载、字幕获取、字幕资源、Timeline 资源、
    字幕显示、Word sync、Chunk replay、Listening structure、Phone evidence、词汇、
    诊断、设置、任务中心和全局状态反馈。
  - Flutter 前端已落地 typed `CapabilityReadinessSnapshot` 与 `UserTaskStatus`，
    资源/时间线面板和底部控制栏可表达能力可用性、降级和 ASR/audio-analysis 任务状态。
  - Local Whisper 默认路径、plain SRT/VTT 降级路径、LLTimeline 资源路径、overlay
    Listening structure / Phone evidence 缺失状态、no-media/side-panel/secondary/chunk
    controls 和 download status 已完成 P0 前端语义收敛。
  - 新增 `2.22-BACKEND-CONTRACT-GAPS.md`，记录 per-resource Listening structure readiness、
    job result capability summary、稳定 task lifecycle enum、批量资源能力摘要和
    Practice/Review readiness contract 等后端缺口；本阶段不修后端。
  - 新增 `2.22-FRONTEND-E2E-QA.md`，固定本地可重复的前端端到端 smoke checklist。
  - PROJECT / ROADMAP / REQUIREMENTS 已新增 Phase 2.22 与 `UX-001` 至 `UX-008` 需求。
- 建模纠偏（2026-07-01，本次复核）：
  - 新增 `2.22-USER-VISIBLE-STATE-MACHINE.md`：真正的用户可见状态机（R0-R8 surface 区域 +
    Section C 能力就绪 lane），对齐当前 main 并区分已修复/仍开放缺陷（SM-F1..F8 已修，
    SM-01..08 仍开放）。此前 STEP0 audit 只是散文区域表，不构成状态机。
  - 修正 `2.22-FEATURE-SEMANTICS-MODEL.md`：Capability Stack 与 Readiness Examples 的 L 层号
    自相矛盾已统一，并新增 Model↔Code 对账表（明确 5/11 层已建 readiness lane）。
  - `2.22-CURRENT-FEATURE-INVENTORY.md` 从裸清单改为“覆盖清单 + 已验证 P0 模板（F1-F8）”。
- 记账纠正（此前被表述为“已落地/closeout complete”，实际为部分完成）：
  - typed CapabilityReadiness 仅覆盖 5/11 能力层（缺 media/playback、transcript/overlay、
    vocabulary、diagnosis、download/task、practice/review），且仅接入资源面板 1-2 个 surface；
    PLAN Step 1 要求的其余就绪层仍未建。
  - 用户可见状态机此前未真正建模（本次补上）。
  - download 仍是 `activeDownload` + `downloadedMediaPath` 双字段派生，未统一为单一 owned state。
  - `widgets/layout/side_panel.dart` 的 `SidePanel` 为死代码，main.dart 仍用重复内联 `_sidePanel()`。
  - 自由字符串 `status` 仍承载大部分工作流状态（~99 setState）。
  - 真实进度：建模基座已重建 + 一批 P0 前端切片已落地（SM-F1..F8）。
- 收口（2026-07-02，判定达成，详见 `2.22-CLOSEOUT.md`）：
  - 阶段三目标按 journey/状态机层面判定达成（用户确认）：用户可见状态机已建（R0-R8 + Section C lane）、
    基于状态机的问题识别已产出 Defect Register、工作流/路径在 18 条 journey + 全 surface 区域确认。
  - “建状态机 → 找问题 → 修问题”闭环已跑通：SM-01（status 缩范围）、SM-02（死 side_panel）、
    SM-03（DownloadController）、SM-07b（predicted 徽标）已修——上面“记账纠正”里列的 download 双字段、
    side_panel 死代码、status 驱动行为已分别被 SM-03/02/01 修复。
  - 剩余 OPEN 明确 defer：SM-04（待 UX）、SM-05（polish）、SM-06（YAGNI，无消费方）、
    SM-07 剩余（polish）、SM-08（候选下一后端/声音线阶段）。
  - 逐功能模板化（约 40 个 checklist 功能）journey 层已覆盖、价值低，刻意不做。
  - 自动化：`flutter analyze` 无问题、`flutter test` 147 passed。
  - 唯一待办：按 `2.22-FRONTEND-E2E-QA.md` 在真实媒体上跑手工 smoke（归用户），回填后完全收口。
- 下一步（阶段外）：
  1. 用户跑真实媒体手工 smoke，回填结果。
  2. Phase 2.21 audible-structure / sound-line / ASR 解耦继续（本分支已承载）。
  3. 后续 backend/product phase 按 `2.22-BACKEND-CONTRACT-GAPS.md` 逐项补契约。
- 规划文档：
  - `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CONTEXT.md`
  - `.planning/phases/2.22-user-facing-workflow-semantics/2.22-FEATURE-SEMANTICS-MODEL.md`
  - `.planning/phases/2.22-user-facing-workflow-semantics/2.22-USER-VISIBLE-STATE-MACHINE.md`
  - `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CURRENT-FEATURE-INVENTORY.md`
  - `.planning/phases/2.22-user-facing-workflow-semantics/2.22-PLAN.md`
  - `.planning/phases/2.22-user-facing-workflow-semantics/2.22-STEP0-UI-AUDIT.md`
  - `.planning/phases/2.22-user-facing-workflow-semantics/2.22-BACKEND-CONTRACT-GAPS.md`
  - `.planning/phases/2.22-user-facing-workflow-semantics/2.22-FRONTEND-E2E-QA.md`
  - `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CLOSEOUT.md`

### Phase 2.23: Architecture Debt Paydown 🧭 已建档（未开工）

- 目标：收口 2026-07-02 架构审核确认的五项累积债务（A1-A5），全部用可测量
  指标验收，不改产品行为 / API contract / SQLite schema / 算法语义：
  - A1 `main.dart` 3601 行 + 107 setState、UI 状态双轨制 → 收缩为 composition
    root（≤ 1500 行、setState ≤ 30、状态模式单轨化）。
  - A2 `sound_analysis.rs` 3383 行单文件（contract 已锁 v1 但实现仍在单文件里长）
    → 机械拆分为模块目录，并把"单文件 >1500 行必拆"写入 AGENT.md。
  - A3 文档事实源漂移（ARCHITECTURE.md dictionary-provider 方向画反、STATE.md
    1149 行 frontmatter 与正文矛盾）→ 修图 + STATE 瘦身至 ≤ 400 行 +
    MAINTENANCE.md 防复发规则。
  - A4 `models/timeline.dart` 2596 行手写解析无契约守卫 → committed fixture
    驱动的 Dart contract 解析测试 + codegen 决策 ADR（只决策不迁移）。
  - A5 `persistence-sqlite`/`api-http` 巨型 tests.rs → 按表域/route group 机械拆分。
- Step 执行顺序（2026-07-02 随算法线搁置调整）：基线快照 → 文档修复 →
  main.dart 收缩（3.x Flutter 工作前置，升为 P0）→ sound_analysis 拆分
  （算法线静默窗口内做，零并行冲突）→ Dart contract 安全网 → 测试拆分 → closeout。
- 2026-07-02 数据模型/业务模型两轮审核后的缺陷收口（先于 Step 0-6 执行）：
  五项高优先级架构缺陷已修——诊断归一化接缝（"went"/"go" 屈折形式误判 unclassified）、
  观察身份统一（`domain::lexical_observation_id` 单源、attempt 引用不再悬挂）、
  SSE 事件枚举 parity（补 sound-line 漂移 + 双向 parity 测试）、LLTimeline 导入
  身份重写所有权归一（`remap_lltimeline_identity` + 全文档零残留不变量测试）、
  LexicalEntry 双身份轴一致性校验。`cargo test --workspace` 357 passed、
  contract validation 通过；API/JSON shape 零变化，Flutter 无需改动。
  其余简单项（僵尸表、双家退役条件、文档漂移等）与 3.x 归属项全部登记在
  `2.23-REVIEW-FINDINGS-REGISTER.md`，进入 3.x 前清零。
- 2026-07-02 晚第二批：B-4 learning-loop 双表示写入收敛（upsert 全列更新 +
  列/JSON 一致性测试）与 C-7 主切片（SSE payload 生产端 typed struct、
  `contracts/events/examples.json` golden 信封、Rust/Dart 双端契约测试锁定
  Flutter typed 消费的 6 个事件）已修。剩余待修项：B-1/B-2/B-3/B-5（简单项，
  交接）与 C-7 零散小事件（3.x 前/早期）。`cargo test` 358 passed、
  `flutter test` 156 passed。
- 分工（2026-07-02 定）：剩余待修项 + PLAN Step 0/2/4/5 已整理为交接任务包
  `2.23-HANDOFF-TASKS.md`（T1-T9），交其他执行人；Step 3（main.dart 收缩）
  由原审核会话执行人负责。Step 3 的"状态模式定调"决策已消解：核实
  `state/store.dart` 的 `Store<T>` 已被 player/learning/subtitle 三大控制器
  使用（非死雏形），controller + Store 转正为唯一 UI 状态模式。
- **Step 3 ✅ 完成（2026-07-03）**：main.dart 3601 → 1457 行（gate ≤1500）、
  setState 107 → 10（gate ≤30）。新增三个 context-free coordinator
  （resource_actions / media_session / playback_actions，宿主 `bind()` 注入
  钩子）、三个 layout widget（PlayerStage/SidePanel/PlaybackBar）、五组
  flow 函数（settings/媒体导入/OpenSubtitles/manual review）；status 单源化
  到 `PlayerController.status`。`flutter analyze` 无问题、`flutter test`
  162 passed（基线 156）；切法与指标实录见 `2.23-PLAN.md` Step 3 回填。
  待办：用户按 `2.22-FRONTEND-E2E-QA.md` P0 路径跑真实媒体手工 smoke。
- 规划文档：
  - `.planning/phases/2.23-architecture-debt-paydown/2.23-CONTEXT.md`
  - `.planning/phases/2.23-architecture-debt-paydown/2.23-PLAN.md`
  - `.planning/phases/2.23-architecture-debt-paydown/2.23-REVIEW-FINDINGS-REGISTER.md`
  - `.planning/phases/2.23-architecture-debt-paydown/2.23-HANDOFF-TASKS.md`

### Phase 3.0: English Listening Learning Loop ⏳ 当前主线（2026-07-02 启动）

- 目标：在 Phase 2 的真实声音流资源和 Phase 2.18 的新学习资产架构之上，把英语作为第一门语言
  做成完整学习闭环。
- 核心闭环：
  `真实输入 -> 可理解度判断 -> 诊断 -> 主动练习 -> 复习巩固 -> 进度反馈 -> 回到真实输入`。
- 核心理念：
  - 真正语言能力来自听力突破和大量可理解输入。
  - 常见语言学习功能必须重写为听力本位能力。
  - L1 与 L2 理论进入诊断层，首个真实组合为 Mandarin L1 -> English L2。
  - Cloze、听写、字幕渐隐、chunk replay 和本地 YouGlish-like 个人语料库是 Phase 3.0 的关键体验。
- 前置调整（2026-07-02）：Phase 2.19/2.20/2.21 算法线已搁置，不再作为前置；
  Phase 2.22 用户工作流语义已收口。3.x 直接在当前 audible-structure v1 contract 和
  2.22 用户语义之上推进输入难度、精听/泛听、主动验证、听力驱动词汇、
  L1-aware diagnosis、shadowing 和诊断型 dashboard；Flutter 侧开工前先过
  Phase 2.23 的 main.dart 收缩（A1），避免新 practice UI 继续堆在 god file 上。
- 规划文档：
  - `.planning/phases/3.0-english-listening-learning-loop/3.0-CONTEXT.md`
  - `.planning/phases/3.0-english-listening-learning-loop/3.0-PLAN.md`

### Phase 3.0.1: Learning Loop Architecture Foundation ✅ Backend Foundation Completed

- 已完成后端地基：domain model、application repository traits/service、SQLite schema v15、
  `/v1/practice/*` 与 `/v1/review/*` API、OpenAPI/generated client 和 contract validation。
- 第一条 backend vertical slice：
  `当前 chunk -> cloze / chunk dictation -> PracticeAttempt -> LexicalObservation / ReviewItem /
  LearningEvent`。
- 关键 guardrail：
  - 练习失败不静默修改全局 `LearningStatus`。
  - Anki 是互操作 adapter，不是内部权威复习模型。
  - Dashboard 从 learning event / durable attempt 聚合，不从 transient UI state 拼。
  - L1-aware diagnosis 走 profile/provider，不写死在 Flutter 文案。
- 后续 slice：
  Flutter practice controller/UI、corpus search、difficulty profile、learner profile persistence、
  recording/shadowing 和 dashboard aggregation。
- 规划文档：
  - `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-CONTEXT.md`
  - `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-ARCHITECTURE.md`
  - `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-PLAN.md`
  - `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-CLOSEOUT.md`

## 当前横切治理 Phase

### Phase 2.18: Codebase Architecture Refactor ✅ 已完成

- 目标：趁项目尚未继续膨胀，单独解决 2026-06-27 架构复盘发现的代码架构问题，不混入
  Phase 2.17 真实媒体 QA。
- 已完成重构主路径：
  - OpenAPI/generated client 已补齐缺失 route；contract validation 增加实现/契约双向 parity。
  - `SubtitleRepository` 已拆为 subtitle track、pronunciation、timeline resource、LLTimeline resource
    等 application 边界；`AppServices` 不再依赖全能 subtitle repository。
  - `LexicalEntry` 已携带权威 `LexicalUnit`，SQLite lexical identity 使用
    `language + granularity + normalization + normalized_key`；状态枚举更名为 `LearningStatus`。
  - `LearningAssetRepository` 是 lexical learning asset 的一等 repository 边界。
  - 旧 learning-asset domain/repository/API/OpenAPI/generated client/script/Flutter fixture 路径已从 active code path 删除。
  - 诊断、observation、vocabulary export/import 均走 lexical entry。
  - `application::dto` 不再公开 `speech_analysis` 类型别名，chunk partition/diagnostics/provider info
    已转换为 application-owned DTO。
  - SQLite word/chunk/phone timeline runs 已增加每 track 单 active partial unique index，并有
    schema-level 测试覆盖。
  - Flutter 新增 typed `BackendEvent` 与 `BackendEventCoordinator`，`main.dart` 不再直接解析 SSE payload；
    diagnosis refresh 已下沉到 `LearningWorkflowController` 并使用 generation guard 丢弃 stale result。
  - `LearningController` 的 lexical entries、phrase candidates、selected details、language profile、
    dictionary lookup、word pronunciation、diagnosis 已 typed。
  - `SubtitleController` 的 pronunciation provider、sentence pronunciation、phonetic analysis 已 typed；
    `WordLearningPanel` / `DiagnosisCard` 不再接收这些业务 payload 的裸 map。
  - `LearningWorkflowController` 继续承接 phrase candidate、word entry load/open/update、observation
    和 learning content 保存流程，`main.dart` 只保留 UI wiring/status。
  - 新增 `SpeechEnhancementWorkflowController`，timeline resource refresh、word timing、sentence
    pronunciation、chunk partition、phone/sound-pattern analysis 加载解析已从 `main.dart` 移出。
  - Rust/Flutter timeline models 已新增 `TimelineMetrics` / `ChunkEvidence` typed envelope。
  - `.planning/codebase/ARCHITECTURE.md` 与 `.planning/codebase/DATA-MODEL.md` 已刷新为当前事实源。
- 剩余债务：
  - `main.dart` 仍可继续拆 media/session/resource action wiring。
  - route manifest 尚未抽成共享事实源；当前由 route/OpenAPI parity test 守护。
  - UI 异步状态仍可进一步显式化为 loading / ready / stale / error / session 模型。
  - `speech-analysis` crate 内部仍承载多个子域，后续模型继续扩张时可再拆 crate 或 module boundary。
  - 真实媒体听感 QA、connected speech 样本包和长期回归素材归 Phase 2.17 / 后续 QA 推进。
- 兼容性决策：
  - 不需要保留历史兼容性。
  - 旧 SQLite 数据、旧 LLTimeline JSON、旧学习资产资源和旧 API/UI adapter 均可抛弃。
  - Phase 2.18 以 `LexicalEntry + LexicalUnit`、统一 timeline lifecycle、typed Flutter state
    和新 contract 为准。
- 收口记录：
  - 主重构提交：`c41244b refactor: complete phase 2.18 architecture overhaul`。
  - 过期 `.planning/DEFERRED-ITEMS.md` 已删除；跨阶段遗留项以各 phase closeout 与本 STATE 为准。
- 规划文档：
  - `.planning/phases/2.18-codebase-architecture-refactor/2.18-CONTEXT.md`
  - `.planning/phases/2.18-codebase-architecture-refactor/2.18-PLAN.md`
  - `.planning/phases/2.18-codebase-architecture-refactor/2.18-REFACTOR-AUDIT.md`
  - `.planning/phases/2.18-codebase-architecture-refactor/2.18-CLOSEOUT.md`

## 当前 Phase 状态

### Phase 1: LLTimeline JSON v1 核心契约 ✅

- Schema `llplayer.timeline.v1` 已定义
- metadata / segments / words / phonemes / chunks / artifacts 结构完整
- 导入导出 round-trip 测试通过

### Phase 2: 时间轴资源生命周期 ✅

- 版本化 WordTimeline 资源 CRUD
- activate / publish / archive 状态机
- `lltimeline-resource.py` 管理工具

### Phase 3: 生产管线 V1 ✅

- WhisperX ASR + 强制对齐集成
- `produce-whisperx` 端到端命令可用
- 音频预处理（16kHz mono WAV 提取）
- 可选人声分离（Demucs）
- WhisperX JSON → LLTimeline v1 转换
- `production-report.json` 记录覆盖率、overlap/gap、provider 和人工复核准备状态

### Phase 4: 客观评估体系 ✅ 暂时收口

- TIMIT 已接入为高质量 gold resource。
- `compare-lltimeline` 可比较同一 `.lltimeline.json` 内的 baseline/candidate/gold
  word timeline，并输出 P95、tail lag、coverage、overlap/gap 等指标。

- 已完成 MMS_FA、完整 WhisperX CLI、WhisperX+MMS_FA、MFA `align-one` 的首轮
  TIMIT TEST 100 对比。

- 结论：MFA `english_us_arpa + align-one` 是当前高质量 transcript 条件下最强的
  已观测词边界对齐器；MMS_FA 保留为轻量 fallback；Qwen3/BFA 等路线进入长期研究。

### Phase 2.1: 对齐管线加固 ✅ 阶段性结束

- P0 word_index 占位契约已完成。
- P1 tokenizer/evaluation guardrail 已完成。
- application `WordTimelinePipeline` 编排下沉已完成，api-http 转录流程不再直接调用
  `speech_analysis::{asr_timing, forced_align, pause_refinement}`。

- phonetic research fixture 的 phone alignment / finding 构造已下沉到 application。
- `crates/api-http/src` 已移除对 `speech_analysis` 的直接引用。
- production pipeline 已支持可插拔 post-aligner：
  `none|auto|mfa|mms-fa`。

- `auto` / `mfa` 按 MFA -> MMS_FA -> WhisperX 原始时间轴降级。
- P3 evaluate stats 去重已完成。
- persistence/application 巨型文件拆分、monotonicity 消融转为独立后续架构债，
  不阻塞 Phase 2.2。

### Phase 2.2: App Timeline Resource UI Alignment ✅ 已完成

- 目标：让 app 端能导入、展示、选择、激活和消费 `.lltimeline.json` 里的
  WordTimeline 资源。

- 当前生产端资源策略：
  `WhisperX -> optional post-aligner auto|mfa|mms-fa|none -> LLTimeline JSON`。

- `auto` / `mfa` 按 MFA -> MMS_FA -> WhisperX 原始时间轴降级。
- app 端已新增 Timeline Resource Summary，可导入 `.lltimeline.json`、展示
  active/candidate WordTimeline、生产 artifacts 和 readiness，并激活候选 timeline。

- LLTimeline metadata/artifacts 已持久化，导入后 export 可保留 production report /
  post-alignment artifacts。

- 播放器词级高亮继续通过 `trackWordTimings()`，后端优先返回 active WordTimeline，
  无资源时回落 legacy word timings。

- 人工复核入口占位已就绪，完整编辑器进入 Phase 2.3。

- 2026-06-20 正式收口确认：
  - SRT / WebVTT / ASR 字幕 / LLTimeline JSON 已统一为“字幕资源”语义。
  - 字幕资源导入后进入 SQLite，并由顶层“字幕资源”页面从数据库读取。
  - 字幕资源支持导入、刷新、激活、归档、恢复、删除、导出。
  - LLTimeline 可挂载到当前媒体；fingerprint mismatch 由用户确认后允许强制挂载。
  - active WordTimeline 驱动词级高亮，chunk / phone / pronunciation 独立降级。
  - 真实本地数据库已迁移到 schema v12，包含 `word_timeline_runs`、
    `lltimeline_resources` 和 `subtitle_tracks.status`；Phase 2.4 后端变更将 schema
    提升到 v13，新增 `chunk_timeline_runs`。
  - 已修正开发环境 stale release sidecar 优先的问题，避免旧 core 阻塞数据库迁移。
  - 收口文档：
    `.planning/phases/2.2-app-timeline-resource-ui/subtitle-resource-semantics-and-lifecycle.md`

### Phase 2.3: 人工校对 UI ✅ 已完成

- 目标：完成 app 端人工校正闭环。
- 初版不做完整 waveform editor，先做句子级 Word Timing Inspector。
- 从 Timeline Resource Summary 的 Manual Review 入口进入。
- 用户可查看当前句 word timings，微调 start/end，试听句子/词片段。
- 保存时创建 `created_by=user` / `timing_source=user_adjusted` WordTimeline，
  不覆盖 production candidate。

- 保存后自动激活 user-adjusted timeline，并刷新播放器高亮。
- 2026-06-21 第一版实现完成：
  - Flutter client 支持读取完整 WordTimeline 和创建 user-adjusted WordTimeline。
  - WordTiming / WordTimeline 模型支持完整 contract 解析和毫秒级保存 payload。
  - 新增 ManualReviewDraft，负责完整 timeline draft、dirty tracking、校验和保存
    payload。
  - 新增句子级 ManualTimelineReviewDialog，支持 Prev/Next、毫秒输入、±10/±50ms
    微调、播放当前句/词、Reset sentence 和 Save revision。
  - 保存后通过现有 `status=active` create path 自动激活，并刷新 summaries 与
    `trackWordTimings()`。
  - Manual Review 入口已调整为带文字按钮；点击字幕单词会打开 Word Learning 面板。
  - Manual Review 试听退出后会恢复进入前的 source loop，避免残留循环当前句。
  - 字幕资源导出入口已支持选择 SRT 或 LLTimeline JSON。
  - Timeline Resource Summary 已新增直接导出 LLTimeline JSON 的入口，便于从
    manual/original WordTimeline 版本视图直接导出完整资源。
  - 自动化验证：`flutter analyze`、`flutter test` 通过。
  - 2026-06-27 真实媒体手动 QA 已通过，Phase 2.3 正式收口。
- 规划文档：
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-CONTEXT.md`
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-PLAN.md`
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-ACCEPTANCE.md`
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-CLOSEOUT.md`
  - `.planning/phases/2.3-manual-timeline-review-ui/2.3-RESEARCH.md` (2026-06-20 调研完成)

### Phase 2.3.5: Rust 巨型单文件拆分 ✅ 已完成

- 目标：在 Phase 2.3 人工校对闭环之后、Phase 2.4 ChunkTimeline 之前，集中处理
  `persistence-sqlite`、`application`、`api-http` 的巨型 `lib.rs` 技术债。
- 阶段原则：只做 mechanical decomposition，不改业务行为、不改 API contract、不改
  SQLite schema、不新增产品能力。
- 完成内容：
  - `persistence-sqlite` 已按 connection / migrations / support / repository 表域拆分；
    root `lib.rs` 保留 module declarations、re-export 和 tests module。
  - `application` 已拆出 DTO、error、repository/provider traits、util 和 use case 模块；
    root `lib.rs` 保留 `AppServices` 装配、re-export 和共享 timeline helper。
  - `api-http` 已按 `routes/` route group 拆分 handler；root `lib.rs` 保留 router 装配、
    auth、SSE、错误响应和 coordinator 状态。
  - `api-http` 对 `speech-analysis` 的 Cargo 直接依赖已移除，HTTP 层通过
    `application` 编排访问语音分析能力。
- 收口体量：
  - `crates/persistence-sqlite/src/lib.rs`：约 19 行。
  - `crates/application/src/lib.rs`：约 609 行。
  - `crates/api-http/src/lib.rs`：约 496 行。
  - `crates/domain/src/lib.rs`：约 1317 行，暂不作为 Phase 2.4 前置项。
- 自动化验证：`cargo test --workspace --quiet` 通过。
- 规划文档：
  - `.planning/phases/2.3.5-rust-module-decomposition/2.3.5-CONTEXT.md`
  - `.planning/phases/2.3.5-rust-module-decomposition/2.3.5-PLAN.md`
  - `.planning/phases/2.3.5-rust-module-decomposition/2.3.5-CLOSEOUT.md`

### Phase 2.4: ChunkTimeline 生成与消费 ✅ 已完成

- 目标：把 chunk 从临时算法结果升级为可管理、可激活、可导出、可播放消费的
  ChunkTimeline 资源。
- 阶段第一优先级不是继续调算法，而是打通 ChunkTimeline 资源契约：
  `active WordTimeline -> ChunkTimeline candidates -> active ChunkTimeline -> player consumption`。
- 第一版 provider 采用 acoustic-first + semantic-assisted 策略：
  - 非 estimated WordTimeline 的 gap / duration evidence。
  - 标点、短语、语义边界启发式。
  - chunk 长度和学习可用性约束。
  - estimated timing 降级为 approximate / text-only，不声称精确声学边界。
- UI 目标：字幕资源管理中可见 ChunkTimeline candidates，并支持生成、激活、归档、
  删除、导出；播放器支持当前 chunk 高亮、点击跳转、chunk 循环、Prev/Next chunk 和
  渐进展开训练。
- 2026-06-21 完成内容：
  - `domain` 新增 `ChunkTimeline`、`ChunkTimelineChunk`、`ChunkTimelineSummary`、
    `ChunkTimelinePrecision` 和 `ChunkBoundarySource`。
  - SQLite schema v13 新增 `chunk_timeline_runs`，支持 candidate / active / archived
    生命周期与 active 唯一性。
  - `application` 已能从 active WordTimeline 生成 `acoustic_semantic_v1`
    ChunkTimeline candidate/active；estimated timing 标记为 approximate。
  - `api-http` 新增 ChunkTimeline list / summary / generate / get / activate / archive /
    delete / export 路由。
  - LLTimeline export/import 已保留 ChunkTimeline candidates 和 active id。
  - OpenAPI contract 已同步 ChunkTimeline schema 与路由。
  - Flutter API client/model 已接入 ChunkTimeline，并优先消费 active ChunkTimeline；
    无 active resource 时保留旧 `chunk-partitions` 降级路径。
  - 字幕资源管理 UI 已展示 ChunkTimeline candidates，并支持生成、激活、归档、删除、
    导出完整 LLTimeline。
  - 播放器已消费 active ChunkTimeline：当前 chunk 高亮、点击 chunk 跳转、
    Prev/Next chunk、Loop chunk、Expand chunk 和原有 Loop sentence 组成渐进训练路径。
  - 自动化验证：`cargo test --workspace --quiet`、`flutter analyze`、`flutter test`、
    `./scripts/validate-contracts.sh` 通过。
- 规划文档：
  - `.planning/phases/2.4-chunktimeline-generation-consumption/2.4-CONTEXT.md`
  - `.planning/phases/2.4-chunktimeline-generation-consumption/2.4-PLAN.md`
  - `.planning/phases/2.4-chunktimeline-generation-consumption/2.4-CLOSEOUT.md`

### Phase 2.5: Sound Pattern / PhoneTimeline ✅ 已完成

- 目标：把真实声音模式从“文字字幕的附属解释”升级为一等学习对象，让用户可以从
  sound pattern 直接建立到文字、chunk 和意义的映射。
- 产品动机：听力理解不只是 `audio -> words -> meaning`，更接近
  `audio -> sound patterns -> chunks / phrase patterns -> meaning`；word/text 是解释层
  和对齐层，不是唯一入口。
- 阶段第一优先级是 provider benchmark + PhoneTimeline 资源契约，而不是先做音标 UI：
  - 评估 MFA phone alignment、Wav2IPA/Wav2Vec2Phoneme、ZIPA、Allosaurus baseline。
  - 验证候选是否保留弱读、省音、闪音、缩约，而不是规范化回字典发音。
  - 定义 PhoneTimeline candidate / active / archived 生命周期。
  - 将 completed phonetic analysis 转换为可管理、可导入导出、可播放消费的
    PhoneTimeline resource。
- UI 目标：Sound Pattern View 显示 detected audio、canonical pronunciation 和 rule
  prediction 三层；支持 current phone 高亮、点击循环、finding 证据展开和用户反馈。
- 2026-06-21 首块实现：
  - `PhoneTimeline` 升级为一等资源模型，支持 candidate / active / archived 生命周期。
  - SQLite 新增 `phone_timeline_runs`，LLTimeline export/import 开始保留
    PhoneTimeline candidates 和 active id。
  - completed `PhoneticAnalysis` 会桥接生成 PhoneTimeline candidate。
  - 新增 PhoneTimeline list / summary / get / activate / archive / delete / export API。
  - `research-fixture` 桥接结果标记为 `approximate`，保持 synthetic / 非真实检测语义。
  - TIMIT benchmark dataset phone timeline 输出迁移到新资源契约。
- 2026-06-22 收口：
  - app 端 `LocalApi`、timeline models、`SubtitleController` 和 Timeline Resource Summary
    已接入 PhoneTimeline。
  - 资源面板可展示 PhoneTimeline candidates，并支持激活、归档、删除。
  - 播放/诊断侧优先消费 active PhoneTimeline；无 active resource 时回退旧
    `phonetic-analyses`。
  - `2.5-BENCHMARK.md` 明确 provider gate：当前 no release provider selected。
  - `scripts/verify-m20-phase0.sh` research infrastructure 验证通过。
- 规划文档：
  - `.planning/phases/2.5-sound-pattern-phonetictimeline/2.5-CONTEXT.md`
  - `.planning/phases/2.5-sound-pattern-phonetictimeline/2.5-PLAN.md`
  - `.planning/phases/2.5-sound-pattern-phonetictimeline/2.5-BENCHMARK.md`
  - `.planning/phases/2.5-sound-pattern-phonetictimeline/2.5-CLOSEOUT.md`

### Phase 2.5.5: 语言学习抽象校验 ✅ 已完成

- 目标：在 Phase 2.6 写多语言代码之前，校验语言学习抽象（1）立得住真实二语习得 SLA，
  （2）能扩展到主流学习语言 top-15 而不打特例分支；并锁定 invariant/variant 边界、
  L1 -> L2 诊断 seam 和两个扩展性 seam。
- 定位：与 Phase 2.3.5 同类的插入式前置加固 phase，交付设计文档而非生产代码。
- 触发动机：2.6 评审中确认 listening-first、Token/LexicalUnit/ListeningUnit 三分、
  validation-beyond-en/zh，并新确认“L2 听力难度被 L1 过滤”这一直接命中诊断核心的 SLA
  事实——它会改变诊断模型形状，必须在 2.6 写诊断前定下来。
- 核心工作：
  - SLA Foundation Mapping：每个抽象元素映射到真实听力/词汇研究依据
    （Field / Cutler / Nation / Wray / Best / Flege / Marslen-Wilson）。
  - 锁定唯一不变量为“理解轴”（词义×声音）；全局状态枚举语言无关、诊断 reason 按 profile
    可扩展。
  - L1 -> L2 诊断 seam：可空 L1 维度，只留 seam、不实现规则。
  - 开放 kind taxonomy + Token/LexicalUnit/ListeningUnit 单位间 N:M alignment 两个 seam
    规格化；LexicalUnit 粒度轴与归一形态轴拆分。
  - Japanese + Arabic 纸面证伪（mora/pitch、非线性词根-词型形态）。
  - top-15 学习语言 envelope 与类型学聚类。
- 2026-06-22 收口结论：
  - 主干 **SLA-grounded**（Field 诊断轴 / Cutler 跨语言切分 / Nation word family /
    Wray 语块 / Best·Flege L1 过滤 / Marslen-Wilson 候选竞争），非凭空想象。
  - 锁定唯一不变量＝理解轴；全局状态枚举语言无关、复用；诊断 reason 按 profile 可扩展。
  - Japanese + Arabic 逐字段证伪通过，逼出三条真实修订：
    - R0 开放 kind taxonomy 是硬约束（禁止穷举 enum）。
    - R1 听力 observation 可锚定 ListeningUnit（不止 LexicalUnit）。
    - R2 `normalized_key` provider-opaque（阿拉伯语非线性词根）。
  - L1 seam 已留（诊断签名 `(L1, L2_unit, status)`，v1 不读、不落 schema）。
  - 已回灌 2.6：新增 Validated Foundation 七条约束，两项 Open Question 标记解决。
  - 残留：hi（abugida 书写轴）列为下一个书写轴探针。
- 规划与交付文档：
  - `.planning/phases/2.5.5-language-learning-abstraction-validation/2.5.5-CONTEXT.md`
  - `.planning/phases/2.5.5-language-learning-abstraction-validation/2.5.5-PLAN.md`
  - `.planning/phases/2.5.5-language-learning-abstraction-validation/2.5.5-SLA-FOUNDATION.md`
  - `.planning/phases/2.5.5-language-learning-abstraction-validation/2.5.5-FALSIFICATION.md`
  - `.planning/phases/2.5.5-language-learning-abstraction-validation/2.5.5-CLOSEOUT.md`

### Phase 2.6: 多语言学习基础 ✅ 完成（Step 1-7，en + zh）

- 目标：将 LLPlayerNext 从“英语优先学习播放器”扩展为“语言能力可插拔的学习播放器
  底座”，首批真实验收语言为 English + Chinese。
- 阶段定位：延后到 2.3 / 2.3.5 / 2.4 / 2.5 之后，不打断当前资源主线；并以 Phase 2.5.5
  校验过的抽象为输入，须在 2.5.5 收口后进入。
- 当前判断：
  - 播放、字幕资源、时间轴资源、SQLite、来源快照等底座具备多语言扩展性。
  - 逐词学习、词汇状态、字典、lemma、发音和诊断仍明显英语优先。
  - 汉语是第二语言基线，用于迫使 tokenizer、LexicalUnit、拼音/声调和诊断模型从
    英语假设中解耦。
- 核心工作：
  - 定义 language capability matrix。
  - 引入 language-aware tokenizer。
  - 从英语 `lemma` 扩展为语言相关 `LexicalUnit`。
  - 清理 Flutter/API client 中的 `language=en` 硬编码。
  - 接入汉语最小词典 / 拼音 provider。
  - 建立英语 + 汉语双语言回归测试。
- 实现进度（2026-06-22）：
  - ✅ Step 1：`domain/language_profile.rs` 的 `LanguageLearningProfile` + 能力矩阵
    （开放 namespaced kind，en/zh/degraded，理解轴不变量 `LearningStatus` 不动）。
  - ✅ Step 2：`subtitle-core` 的 `Tokenizer` trait + profile 驱动 `tokenize(language, text)`；
    汉语默认 jieba-rs 0.7.4 词分词，`--no-default-features` 走字级 fallback；英语回归基线不变。
    全 workspace 255 测试通过、clippy 干净。
  - ✅ Step 3：`domain/lexical_unit.rs` 的 `LexicalUnit`（粒度×归一两轴 + 不透明 key；
    英语身份 `en:going` 向后兼容；汉语字/词 namespaced 不污染；不假设 lemma）。
  - ✅ Step 4：去 `language=en` 硬编码。`subtitle_core::import` 在未声明语言时按脚本检测
    （含汉字→zh，否则 en）用于分词与存储 `track.language`；Flutter `SubtitleTrack` 读取
    `language`，`_learningLanguage` 解析器（active 字幕轨语言→`en` fallback）串到所有
    lexical/vocab/dict/phrase 调用与 `_sourceFor`。英语回归基线不变。全 workspace 272
    测试 + flutter analyze/test + validate-contracts 通过。
  - ✅ Step 5：汉语词典/拼音 provider。`ChineseDictionaryProvider`（`supported_languages: ["zh"]`）
    接入 **CC-CEDICT**（约 12 万词条，读安装的 `.u8`、数字拼音转调号、简繁双查），25 词种子作离线
    兜底；CC-CEDICT 以钉死 commit + 校验和注册进学习资源目录（CC-BY-SA 4.0），像 ECDICT 一样可安装。
    注册进 api-http 词典栈，既有 `lookup_dictionary` 按 `supported_languages` 派发，英语 provider
    被跳过、未命中干净降级。拼音走词典 phonetics；`WordLearningPanel` 在无实义 IPA 变体时隐藏发音区。
  - ✅ 补 Step 4 遗漏的后端硬编码：`diagnose_sentence` / `phrase_candidates` 原写死 `en`，现按句子
    所属轨语言查 profile（新增 `sentence_track_language` 仓储方法 + `sentence_language` 助手）。
    修复前中文句子诊断读的是英语 profile、忽略用户中文状态。
  - ✅ Step 6：汉语面板 + 语言感知诊断。诊断在 application 层给 recognition barrier 叠加该语言
    profile 的听辨因素（zh: 声调/词边界/同音/轻声/变调；en: 弱读/连读…），namespaced、按 profile、
    明确标注为"可能因素非检测"（中文无音频分析，ADR 0012 延后）；`DiagnosisHint` 新增 `reasons`，
    `diagnosis-core` 保持语言无关。词面板新增汉字逐字拼音分解（字→拼音/声调，从词典拼音对齐、零额外
    查询、按脚本非语言门控）；诊断卡渲染 reason，未知 reason 干净降级。英语诊断回归基线不变。
  - ✅ Step 7：双语回归收敛为显式集（tokenizer/混排/检测、词典语言路由、诊断按轨语言、听辨因素、
    英汉词汇+来源快照隔离 capstone、CC-CEDICT 解析/调号、诊断卡+面板 widget）+ 收口文档
    `2.6-CLOSEOUT.md`。全 workspace 279 + flutter 63 + contracts 通过。
- 收口：`.planning/phases/2.6-multilingual-learning-foundation/2.6-CLOSEOUT.md`。仅留设计 seam
  LANG-004（听觉锚定观察）/ LANG-009（L1）；非英语音频生产属后续 production-engine program。
- 规划文档：
  - `.planning/phases/2.6-multilingual-learning-foundation/2.6-CONTEXT.md`
  - `.planning/phases/2.6-multilingual-learning-foundation/2.6-PLAN.md`
  - `.planning/phases/2.6-multilingual-learning-foundation/2.6-LANGUAGE-LISTENING-MODEL.md`

#### Phase 2.6 后续：派遣层证伪与加固（第三语言 spike，2026-06-23）✅

- 用日语（与中文**共享 Han 脚本**的远端样本）实测 ROADMAP §14.11 退出条件「加语言=只加
  provider+profile，不动既有代码」。**实验证伪：数据模型层成立，行为派遣层不成立**——日语未声明
  时被脚本启发判成 zh、`tokenize()` 写死 match 让日语塌成 1 个 token、逐字拼音按 Han 脚本（非语言）
  门控。根因：zh 是唯一非英语样本且与抽象同期共同设计，n=1 时脚本捷径无法与真正语言派发区分。
- 已加固使主张成真（en/zh 回归基线不变）：
  - `subtitle-core`：新增 `tokenizer_for(strategy)` 注册表（strategy→tokenizer 单一注册点，
    `profile_for` 的 tokenizer 类比）+ 始终可用的 `CharacterTokenizer`（`core.char`）；`tokenize()`
    出口按 profile 声明的 `lexical_normalization` 重算 word 归一（zh/ja=surface 不再被静默小写）。
  - `subtitle-core`：`detect_language` 加 kana→ja 语言识别 seam（kana 中文绝不出现），declared 优先，
    Han→zh 不回退。
  - `application/dictionary.rs`：词典查询归一改走 profile（与 tokenizer 一致）。
  - Flutter 词面板：逐字拼音改按学习语言门控（`profile['language']`），删 Han 脚本门控 `_isHan`。
  - `domain`：新增 `LanguageLearningProfile::japanese` / `profile_for("ja")`，仅作证伪守卫 fixture
    （`core.char` 基线、无 dict/pronunciation provider 干净降级、声明 `ja.mora`/`pitch_accent` 自身轴）。
- 范围纪律：identity 归一在仓储边界（约 6 处 `normalize_lemma`）对 en/zh/ja 行为等价（无大小写），
  **刻意不重构**（零行为、动 identity 模型的 churn），仅记为潜在 seam（未来「带大小写非 lemma」语言才咬）。
- 验证：workspace 284 + subtitle-core no-default-features 24 + flutter 64 + analyze/clippy/contracts 全通过。
- 收口文档：`.planning/phases/2.6-multilingual-learning-foundation/2.6-DISPATCH-FALSIFICATION-AND-FIX.md`。
- 残留 seam（刻意延后）：纯 kanji 无 kana 行仍判 zh（需真 language-id provider）；能力矩阵暴露 client
  （Open Question）；identity 边界 profile 化。

#### Phase 2.6 后续：真日语（经验验证派遣修复，2026-06-23）✅

- 把 ja 从守卫桩升级为**真语言**，以经验验证上面那次派遣修复真成立（桩证明不了）。
  - `subtitle-core`：`JapaneseTokenizer` = **lindera 4.0 + 内嵌 IPADIC** 形态分词，放 `lindera` feature
    后（**默认关**，lindera 未离线缓存，开会破离线构建；默认/离线走字级 fallback）。
  - `dictionary-provider`：`JapaneseDictionaryProvider` 走 **JMdict/EDICT2** 行格式 + 15 词 seed，镜像
    CC-CEDICT；按 kanji/kana 双查。
  - `domain`：ja profile `tokenization`→`ja.morphological`、`dictionary_providers`→`[jmdict]`、
    `pronunciation`→`ja.kana`（`lexical_normalization` 仍 `core.surface`）。
  - 注册：`tokenizer_for` 加 `ja.morphological` 一臂 + api-http 词典栈加一行。
- **验证结果**：加这门真·共享 Han 脚本的形态语言**只动 profile+provider+注册点，没碰 `tokenize()` 核心/
  `detect_language`/逐字门控/诊断**——ROADMAP §14.11「加语言=只加 provider+profile」对真语言**经验成立**。
- **浮出 seam（mini-证伪）**：日语活用（食べる/食べた）在 `core.surface` 身份下**不归并**；lindera 能给
  base form，但 Fix 4 从 surface 重算归一、丢弃 tokenizer lemma。归并需 provider 供归一 key 流过
  `tokenize()`（`LexicalUnit::new` 已支持不透明 key）——下一个 seam，surface-first 接受 v1 不归并。
- 验证：workspace 286 + `--features lindera`（形态证明：学生为单词素）+ no-default-features 24 + flutter 64
  + clippy/contracts 通过。
- 收口文档：`.planning/phases/2.6-multilingual-learning-foundation/2.6-REAL-JAPANESE-VALIDATION.md`。
- 残留：base-form 归并 seam；EDICT2 可下载资源注册（钉死+sha256，像 CC-CEDICT；seed+安装路径已就位）；
  纯 kanji 无 kana 检测；日语声学侧（独立 production program）。

### Phase 2.7: Pronunciation Provider Dispatch ✅ 完成（2026-06-24）

- `PronunciationProvider` trait 派发：`EnglishPronunciationProvider`（包装 speech_analysis）
  和 `ChinesePronunciationProvider`（CC-CEDICT 拼音）。发音标注、词发音查询、语流规则
  三层体验通过 trait dispatch 实现语言无关消费。
- 中文拼音：字幕下方显示声调拼音，通过已有 `display_ipa` 渲染路径，Flutter 无需改动。
- Timing/chunk 验证为语言无关算法：`estimate_word_timings`（字符权重）和声学 chunk 检测
  （gap-based）对所有已分词语言适用。中文 profile 升级为 `word_timeline: Supported`、
  `chunk_timeline: Supported`。仅 `detect_text_chunks`（COCA/PHRASE）保留英语门控。
- 用户验证：中文拼音 ✅ 词级跳动 ✅ chunk 高亮 ✅ 英文回归正常 ✅
- 遗留 gap 移至 Phase 2.8：whisper BPE → app token 时间对齐、韵律感知估算权重。

### Phase 2.8: Token Timing Alignment ✅ 完成（2026-06-24）

- 字符级时间对齐：whisper BPE 合并词数与 app tokenizer 词数不匹配时，自动执行字符级
  时间插值（`align_words_to_tokens`），而非丢弃回退估算。英语 1:1 直接映射不变。
- 新增 `TimingSource::AsrAligned`，表示 ASR 数据经字符级插值。
- 韵律感知估算 fallback：`estimate_word_timings_with_rhythm` 根据 profile 的
  `rhythm_prosody` 选择策略——`CharWeight`（stress-timed 英语）、`SyllableEqual`
  （syllable-timed 中文）、`MoraCount`（mora-timed 日语）。
- `align_timings_to_tokens` 公开 API 供 lltimeline 导入和外部 re-tokenize 场景使用。
- 验证：294 测试全通过，clippy 无新增错误。
- 收口文档：`.planning/phases/2.8-token-timing-alignment/2.8-CLOSEOUT.md`

### Phase 2.9: Production Multilingual Decoupling ✅ 已完成

- 目标：解耦生产管线对英语的强绑定，让非英语语言走通完整生产链路。
- Rust 侧（55cbfae）：`AlignerRegistry` 可插拔对齐器注册表、管线语言传播、CJK 分词
  传播、语言感知 chunk/timing、非英语强制对齐干净降级。
- Python 侧（e1ffcd0）：mlx-whisper ASR 集成（Apple GPU 加速，质量持平 WhisperX、
  速度快 7.5x）、`--asr whisperx|mlx-whisper` 双 ASR 切换、jieba 词级中文分词（不拆字）、
  `align_asr_words_to_tokens()` ASR-to-token M:N 字符位置对齐。
- 中文端到端验证：181 segments / 956 words（jieba 词级）/ avg_confidence 0.954。
  MMS_FA 对中文全跳过（字典 a-z only），ASR timestamps 即最终 timing。
- 验证：Python 14/14 + cargo test + clippy 全通过；英语回归基线不变。
- 收口文档：`.planning/phases/2.9-production-multilingual-decoupling/2.9-CLOSEOUT.md`

### Phase 2.10: English Real Speech Analysis ✅ 集成完成（2026-06-25）

- 目标：选出 phone-level provider，让英语语流分析从"文本预测"升级为"音频检测"。
- **Step 1 Provider Benchmark ✅**（2026-06-25）：
  - 10 条 TIMIT development cases 评估完成
  - 6 个候选已 benchmark：MFA (PER=33.8%) / ZIPA (PER=50.0%) / slplab (PER=31.5%，废弃) /
    l2-arctic (PER=97.0%，废弃) / fb-espeak (PER=30.5%) / vitouphy (PER=19.5%)
  - Benchmark 报告：`2.10-BENCHMARK.md`
- **Step 2 选型决策 ✅**（2026-06-25，补充 benchmark 完成）：
  - 🏆 **选定：`facebook/wav2vec2-lv-60-espeak-cv-ft`**（候选 E）
    - 许可证：Apache 2.0 ✅（Facebook 官方，CommonVoice + LibriVox 母语者语音）
    - PER：30.5%（优于 MFA 33.8%、ZIPA 50.0%）
    - Connected speech 保真度：✅ 输出真实 IPA（含 flap、弱读、schwa）
    - 模型大小：~1.26 GB（可接受，备选 ONNX 量化）
  - ❌ vitouphy (PER=19.5%) 被否决：TIMIT LDC restricted license → 不可分发
  - ❌ slplab / l2-arctic 被否决：L2 发音评估模型 ≠ 母语语流识别
  - ✅ MFA：保留为 canonical phone boundary provider（非 identity）
  - ⚠️ ZIPA：MIT 代码 + 模型许可未正式声明，作为备选
  - `release_provider_selected: true`
- **Step 3 Provider 集成 ✅**（2026-06-25）：
  - `DetectedPhone` 新增 `display_ipa` 字段（IPA 显示 + ARPAbet 内部对齐）
  - `speech-analysis/phone_recognition.rs`：IPA→ARPAbet 映射表 + sidecar 调用封装
  - `phonetic_fixture.rs`：`build_ctc_phonetic_analysis()` 真实 CTC 推理路径
  - `api-http/phonetic_analysis.rs`：CTC provider 注册 + model seed + 执行分派
  - `scripts/wav2vec2-phoneme-cli.py`：Python sidecar（CTC decode + timestamp + logit confidence）
  - `scripts/setup-phoneme-model.sh`：命令行模型下载脚本
  - `scripts/download-phoneme-model.py`：后台模型下载 sidecar（JSON 进度输出）
  - `install_model` API：后台 spawn Python 下载，带进度回报和状态更新
  - Flutter `phonetic_analysis_ui.dart`：模型下载按钮 + 进度条（App 内一键下载）
  - Flutter `api_service.dart`：新增 `installPhoneticAnalysisModel()` API
  - Flutter `diagnosis_card.dart`：IPA 优先显示
- **Step 4 Finding 升级 ✅**（隐式完成 — 现有 alignment + findings 管线已完整支持真实 confidence）
- **Step 5 App 验证 — 模型下载 ✅**（2026-06-25）：
  - App 内一键下载验证通过（~1.26GB fb-espeak 模型）
  - 修复三个 bug：脚本路径解析（相对路径→向上搜索）、进度反馈（后台轮询目录大小）、
    Flutter 进度条运算符优先级
  - 启动时 `reset_stale_installs()` 防止 `installing` 状态卡死
  - ⏳ 真实音频 CTC→IPA→finding 端到端测试待下次 session 验证
- **Step 6 测试回归 ✅**：Rust 299 tests + Flutter 64 tests 全部通过
- 新产出：`scripts/wav2vec2-ctc-phoneme-research.py`（候选 E/F 推理适配器）、
  `scripts/ipa-to-timit-phone-map.json`（IPA→TIMIT 映射表）
- 规划文档：`.planning/phases/2.10-english-real-speech-analysis/`

### Phase 2.11: Architecture Seam Consolidation ⏳ Steps 1-3 完成

- 目标：落地多语言扩展中预留的设计 seam，消除 client 脚本硬编码。
- **Step 1 能力矩阵 API ✅**：Phase 2.12 已完成（`_isHan` 替换为 profile 驱动门控）。
- **Step 2 学习语言来源 ✅**（2026-06-25）：AppSettings 新增 `learningLanguage`，
  优先级链 user > subtitle track > en fallback，设置对话框下拉框，中英双语。
- **Step 3 domain 拆分 ✅**（2026-06-25）：lib.rs 1317→194 行，13 个领域模块。
- Step 4–5：依赖 2.10，待条件推进。Step 6：低优先。
- 规划文档：`.planning/phases/2.11-architecture-seam-consolidation/`

### Phase 2.12: UI State Management Refactoring ✅ 已完成

- 目标：重构 Flutter 前端的响应式状态管理层，为 UI/UX 重构提供细粒度基础设施。
- **Store\<T\>**：通用响应式状态容器（`state/store.dart`），通过 `select()` 暴露
  字段级 ValueNotifier，Widget 只监听需要的数据切片。`StoreBuilder<T,R>` 声明式
  选择器 Widget（`state/builder.dart`）。
- **Typed domain models**：`models/types.dart` 提供 LexicalEntry、LexicalEntryDetails、
  Diagnosis、PhraseCandidate、PronunciationProvider、PronunciationAnalysis、
  LanguageProfile、PhoneticAnalysis 等 typed 类替代核心 `Map<String, dynamic>`。
- **Controller 迁移**：PlayerController / SubtitleController / LearningController
  内部由 ChangeNotifier 改为 Store 驱动，新增 `select()` 公开方法。保留原有
  convenience getter/setter 和 ChangeNotifier 接口，100% 向后兼容。
- **布局提取**：SubtitleOverlay（原 `_playerSurface()` ~100 行）和 SidePanel
  （原 `_sidePanel()` ~70 行）提取为独立 Widget。
- 验证：`dart analyze` 0 issues，`flutter test` 64/64 passed。
- 规划文档：`.planning/phases/2.12-ui-state-management-refactoring/`

### Phase 2.13: 文字线音素 Ribbon ✅ 已完成

- 目标：让文字线即使没有 CTC 真实 phone timeline，也能从 pronunciation provider +
  word timing 合成稳定 phoneme ribbon，实现 Whisper 转录后的音素跳动体验。
- 完成内容：
  - `PhonemeRibbon` 支持长句低疲劳分页窗口。
  - 无 CTC/PhoneTimeline 时，从字典 pronunciation + WordTiming 合成 phones。
  - 有 CTC/PhoneTimeline 时，原先会直接显示 raw detected phones；该行为在 Phase 2.14
    已被 stable learning phone layer 校正。

### Phase 2.14: Sound-First Learning Architecture ✅ 已完成

- 核心准则：**CTC provides audio evidence and timing; expected pronunciation provides teaching labels.**
- 目标：建立第二条声音线，以真实音频证据组织 timing、节奏、音节和韵律短语，同时保证用户
  默认看到的教学标签稳定可靠。
- 完成内容：
  - 新增 `SoundAnalysis` / `SoundLearningPhone` / `SoundSyllable` /
    `SoundProsodicPhrase` 领域模型。
  - `PhoneticAnalysis` 和 `PhoneTimeline` 新增可选 `sound_analysis`，旧 JSON 兼容。
  - `speech-analysis::sound_analysis` 已实现 expected-vs-observed 对齐、learning phone 生成、
    SSP 音节化、pause-aware onset boundary 和 pause-based prosodic phrase detection。
  - CTC `/k/` 误判 expected `/s/` 时，用户默认 ribbon 仍显示 `/s/`；CTC 只提供 timing /
    confidence / mismatch evidence。
  - CTC / research fixture phonetic analysis 自动生成 `sound_analysis`，创建 PhoneTimeline 时复制。
  - Flutter `PhoneTimeline` 解析 `sound_analysis`；文字线 phoneme ribbon 使用 expected
    phone + observed timing，声音线由独立 sound pattern ribbon 消费 `sound_analysis`
    并显示音节间隔、韵律短语边界和 evidence marker。
  - OpenAPI 新增 SoundAnalysis 相关 schema，并补齐 `DetectedPhone.display_ipa`。
- 验证：
  - `cargo test --workspace --quiet` 通过。
  - `flutter analyze` 通过。
  - `flutter test test/timeline_test.dart` 通过。
  - `./scripts/validate-contracts.sh` 通过。
- 收口文档：
  - `.planning/phases/2.14-sound-first-learning-architecture/2.14-CONTEXT.md`
  - `.planning/phases/2.14-sound-first-learning-architecture/2.14-PLAN.md`
  - `.planning/phases/2.14-sound-first-learning-architecture/2.14-STABLE-LEARNING-PHONE.md`
  - `.planning/phases/2.14-sound-first-learning-architecture/2.14-PROSODIC-HIERARCHY-ALIGNMENT.md`
  - `.planning/phases/2.14-sound-first-learning-architecture/2.14-CLOSEOUT.md`

### Phase 2.15: Sound Line Learning UX ✅ 已完成

- 目标：把 Phase 2.14 的第二条声音线从“结构和渲染能力”推进为用户能理解、能开启、
  能训练、能信任的学习界面。
- 完成内容：
  - 设置继续保留文字线 phoneme ribbon 与声音线 sound pattern ribbon 的独立开关。
  - `PhonemeRibbon` 新增 text/sound lane；声音线使用独立音频图标、色彩组和圆角形态，
    避免看起来像第二条相同的文字线 phoneme ribbon。
  - 声音线只消费 `sound_analysis.learning_phones`；当前句缺少 `sound_analysis` 时显示轻量
    unavailable state，不做词典 fallback，也不显示 raw CTC-only 教学标签。
  - evidence marker tooltip 映射为学习者文案：
    `supported by audio` / `possible linking` / `possible reduction` / `possible deletion`。
  - `buildSoundPatternPhones()` 集中守护稳定教学标签：observed CTC mismatch 仍不污染默认
    learning phone label。
  - 修复既有 `phonetic_analysis_ui_test.dart` 在周期 Timer 页面上使用 `pumpAndSettle`
    导致的稳定超时。
- QA 边界：
  - 自动化验证覆盖 UI/model 路径。
  - 当前仓库没有 2-3 条已生成 `sound_analysis` 的真实媒体 QA 包；完整真实媒体听感验收记录为
    Phase 2.16 输入，不伪装为已完成手动验收。
- 验证：
  - `flutter analyze` 通过。
  - `flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart` 通过。
  - `flutter test test/phonetic_analysis_ui_test.dart` 通过。
  - `flutter test` 通过。
- 收口文档：
  - `.planning/phases/2.15-sound-line-learning-ux/2.15-CLOSEOUT.md`

### Phase 2.16: Real Connected Speech Model v1 ✅ 已完成

- 目标：在 Phase 2.14/2.15 的 `LearningPhone` 声音线之上建立真实语流解释层，让用户看到
  “为什么这里听起来变了”，而不是把 raw CTC label 当成教学答案。
- 完成内容：
  - `SoundAnalysis` 新增向后兼容的 `connected_speech` explanation metadata。
  - explanation 明确分离 expected symbols、stable learning symbols、observed acoustic
    symbols、family/status/confidence 和 learner-facing label/hint。
  - Rust 分析层覆盖 6 类 v1 现象：weak form/reduction、deletion、linking、assimilation、
    contraction、flapping。
  - generic high-confidence substitution 不会生成 connected-speech teaching explanation；
    raw CTC 仍只作为 timing/evidence/diagnostic，不改写基础 learning phone label。
  - Flutter timeline model 解析 `connected_speech`，声音线 marker 可直接使用 learner-facing
    explanation label/hint；无旧 `findings` 时也能显示解释。
  - OpenAPI contract 同步 `ConnectedSpeechExplanation` schema，旧资源缺字段时仍可读取。
- QA 边界：
  - 本 phase 收口为模型契约、分析层规则、Flutter 消费和自动化守护完成。
  - 仓库仍缺 2-3 条可完全复现的真实英语媒体 QA 包；真实媒体截图/听感回归作为后续
    QA asset 工作，而不是伪装成本次已完成手动验收。
- 验证：
  - `cargo test -p speech-analysis` 通过。
  - `flutter analyze` 通过。
  - `flutter test test/timeline_test.dart test/phoneme_ribbon_test.dart` 通过。
  - `./scripts/validate-contracts.sh` 通过。
- 收口文档：
  - `.planning/phases/2.16-real-connected-speech-model-v1/2.16-CLOSEOUT.md`

### Phase 2.17: Real Media Sound-Line QA ✅ 已完成

- 已建立 `testdata/sound-line-real-media/` QA pack，manifest 覆盖 8 个 local-only case：
  Brooklyn / Venezuela product media、TED-LIUM、Buckeye、TIMIT。
- 新增 `scripts/verify-sound-line-real-media.py`，支持 default / `--strict-local` / `--json` /
  `--require-ready`，并对 phone-only artifact 和 marker family 爆炸给出质量 warning。
- 新增 `scripts/run-sound-line-real-media-case.py` headless API runner，不再需要手点 UI 才能生成
  PhoneTimeline / `sound_analysis`。
- 修复 CTC sidecar phonemizer/espeak 环境注入问题，并修复
  `phonetic_alignment::backtrace` detected-index-zero deletion 下溢 panic。
- 收紧 generic CTC insertion：无跨词边界上下文时不再生成 learner-facing `linking` marker。
- 8 个 `.tmp/sound-line-real-media/cases/*.lltimeline.json` local-only 小窗口 artifacts 已刷新；
  verifier `valid=true`、`ready=true`。Brooklyn / Venezuela 保留真实 product-media marker，
  TED-LIUM / Buckeye / TIMIT 不再出现旧的 100% `linking` 误报。
- 规划/收口文档：
  - `.planning/phases/2.17-real-media-sound-line-qa/2.17-CONTEXT.md`
  - `.planning/phases/2.17-real-media-sound-line-qa/2.17-PLAN.md`
  - `.planning/phases/2.17-real-media-sound-line-qa/2.17-CTC-MISMATCH-FINDINGS.md`
  - `.planning/phases/2.17-real-media-sound-line-qa/2.17-CLOSEOUT.md`

### Phase 2.19: Real Benchmark Scoring ⏸ 已搁置（初始评估已落地，2026-07-02）

- 目标：把 Phase 2.17 QA artifacts 与 benchmark reference/gold 做量化对比，回答 pipeline
  真实效果，而不只验证资源形状。
- 已新增 `scripts/evaluate-sound-line-benchmarks.py`：
  - TIMIT：`.PHN` content-phone PER。
  - Buckeye：`.phones` actual-pronunciation windowed PER。
  - TED-LIUM：`.stm` transcript exact match 与 segment timing offset。
- 初始结果：
  - TED-LIUM Al Gore / Bill Gates transcript 和 segment timing 与 `.stm` reference 精确匹配。
  - Buckeye s0201a / s0301a PER 分别约 0.304 / 0.352，接近历史 fb-espeak TIMIT dev baseline。
  - Buckeye s0101a PER 约 1.005，TIMIT Phase 2.17 artifact PER 约 0.874，均暴露窗口/映射/
    artifact 生成问题，不能作为最终模型质量结论。
  - 历史 fb-espeak TIMIT dev baseline 复跑为 PER 0.304636。
- 当前判断：pipeline 已经可评估，但 phone-level 质量尚未 release-grade；下一步优先排查
  TIMIT sentence window、espeak symbol mapping、Buckeye lead-in filtering 和 boundary metrics。
- 规划文档：
  - `.planning/phases/2.19-real-benchmark-scoring/2.19-PLAN.md`
  - `.planning/phases/2.19-real-benchmark-scoring/2.19-INITIAL-RESULTS.md`

### 强制对齐研究 🧭 长期推进

- torchaudio MMS_FA sidecar（`scripts/forced-align/align-cli.py`）。
- MFA research sidecar（`scripts/forced-align/mfa-align-cli.py`）。
- Qwen3-ForcedAligner、BFA/easytranscriber/CTC 暂列 deferred research。
- 研究结果必须通过统一 LLTimeline schema、tokenizer 和 benchmark 体系后再晋级主线。

## 最近重要决策

1. **2026-06-18 14:50** — 产品重构：从单一消费端拆分为生产引擎 + 消费端两条路线
2. **2026-06-18** — 引入 GSD 文档体系，建立 `.planning/` 目录
3. **生产端策略**：WhisperX 负责高质量 transcript/VAD，后处理 aligner 可选
   MFA/MMS_FA/未来候选，最终统一输出可复用 `.lltimeline.json`

4. **降级策略**：生产端 `auto` 路线按 MFA -> MMS_FA -> WhisperX 原始时间轴降级；
   app 端不得依赖重型 runtime
5. **Phase 2.2 收口边界**：字幕资源生命周期和 LLTimeline 消费闭环已完成；chunk
   语义质量、ChunkTimeline 资源化、chunk 候选选择和人工修正进入后续 Phase 2.4 /
   chunk 专项阶段，不再塞回 Phase 2.2。
6. **Sound Pattern 产品原则**：真实发声模式是听力学习的一等对象；PhoneTimeline /
   phonetic findings 的目标不是装饰性 IPA，而是帮助用户从真实声音模式直接建立到
   chunk、文字和意义的映射。
7. **Phase 2.3.5 架构关口已通过**：Rust 巨型单文件拆分已完成，后续
   ChunkTimeline / PhoneTimeline 新能力应进入对应 module，而不是继续堆入 root
   `lib.rs`。
8. **多语言策略**：产品长期支持主要语言，但不承诺世界所有语言；首批扩展验收语言
   为英语和汉语，先建立语言能力矩阵、语言感知 tokenizer 和 LexicalUnit 模型。
9. **多语言抽象先校验后实现**（2026-06-22）：在 Phase 2.6 之前插入 Phase 2.5.5，先用真实
   SLA 校验抽象、并用 Japanese/Arabic 做类型学证伪；确认“L2 听力难度被 L1 过滤”，诊断模型
   预留 L1 seam；唯一语言不变量是理解轴（词义×声音），其余结构走 profile/provider；不大包
   大揽，架构只对 top-15 学习语言封顶有效。
10. **产品方向文档化**（2026-06-22）：多语言听力学习确立为产品方向并写入战略文档——
    PROJECT.md（§2 愿景 / §4.4 原则 / §10.9 概念 / §15.5 里程碑）、REQUIREMENTS.md
    LANG-001..010、ROADMAP.md §14.11、codebase ARCHITECTURE/DATA-MODEL 多语言方向节、
    ADR 0012。英语行为为回归基线，下一步进入 Phase 2.6 实现。
11. **文字线/声音线双主线架构**（2026-06-26）：学习体验分两条主线——文字线（Whisper
    转录 → 词 → chunk → 词典音素，回答"说了什么"）和声音线（CTC 音素 → 音节 →
    韵律短语，回答"怎么说的"），两者差异即"为什么听不懂"。sentence 为共享作用域
    边界，数据共存于 LLTimeline/PhoneTimeline（`sound_analysis` 字段）。Phase 2.13 收口文字线
    音素体验，Phase 2.14 建立声音线架构。
12. **稳定教学标签优先**（2026-06-26）：CTC 是真实音频 observation/evidence，不是用户
    默认教学标签真值。phoneme ribbon 和声音线默认展示 `LearningPhone`：label 来自
    expected pronunciation，timing/confidence 来自 observed CTC。raw CTC mismatch 进入
    诊断/高级 evidence，不直接成为训练答案。
13. **声音线 UX 门控**（2026-06-27）：声音线是 sound pattern learning surface，不是
    第二条普通 phoneme ribbon。UI 只在当前句存在真实 `sound_analysis` 时渲染声音线；缺失时显示
    轻量 unavailable state，不做词典 fallback。Evidence marker 默认使用学习者文案，内部
    finding/status 保留为高级诊断语义。
14. **真实语流解释层**（2026-06-27）：`LearningPhone.symbol` 继续保持稳定教学标签；
    connected-speech 现象通过 `sound_analysis.connected_speech` 作为解释/marker metadata
    附着，不直接改写用户可见基础音素。Generic CTC substitution 不能生成高置信教学解释。
15. **声音线 evidence 可回放**（2026-06-27）：sound pattern ribbon 的 evidence marker 可点击
    循环播放对应 `LearningPhone` 时间窗，让 connected-speech explanation 从静态标签进入
    可听验证。

## 当前阻塞项

无。

## 下一步工作

1. 为 TIMIT / Buckeye / TED-LIUM 建立 reference scoring harness，分别比较 phone boundary /
   phone identity、word/phone label、transcript alignment；Phase 2.19 已有初始 scorer，下一步
   排查 TIMIT/Buckeye 异常窗口并补 boundary metrics。
2. 建立桌面 UI E2E/integration phase：启动真实 sidecar，导入媒体/LLTimeline，创建 phonetic job，
   等待 PhoneTimeline，点击 sound-line marker 并验证 playback window。
3. 在后续学习闭环 phase 中继续推进输入难度、精听/泛听、主动验证、听力驱动词汇和诊断 dashboard。

## 指标

- 已完成里程碑：M1.0, M1.5, M1.6, M1.7, M1.8, M1.9
- 活跃分支领先 main：持续增长，以 git log 为准
- 生产管线每天可处理的新闻视频：1-2 条（当前为手工触发）
