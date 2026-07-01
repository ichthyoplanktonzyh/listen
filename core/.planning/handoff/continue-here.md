# Continue Here — Phase 2.22 User-Facing Workflow Semantics

> 最后更新：2026-07-01 CST
> 单一接续入口。先读 `AGENT.md` 和 `.planning/STATE.md`，再读本文件。

## 当前结论

Phase 2.21 的 audible-structure 主体架构已经能支撑当前产品方向：

```text
在字幕层显示当前句子的实际可听结构，但不把 text prior 伪装成 measured audio。
```

现在端到端使用路径暴露出的主要问题已经转到前端语义和工作流：

```text
功能已经存在，但用户不知道该从哪里打开、何时可用、为什么不可用、下一步该做什么。
```

因此当前工程主线切到 Phase 2.22：

```text
把当前所有用户功能组织成清晰、可发现、可降级、可验证的用户路径
```

Phase 2.21 的 W8 manual listening QA 仍未完成，作为模型质量/校准并行待办保留；但下一步代码方向优先推进 Phase 2.22 的 UI/workflow 收敛。

## 上位文档

- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CONTEXT.md`
- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-FEATURE-SEMANTICS-MODEL.md`
- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CURRENT-FEATURE-INVENTORY.md`
- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-PLAN.md`
- `.planning/phases/2.21-audible-structure-architecture/2.21-AUDIBLE-STRUCTURE-MODEL.md`
- `.planning/phases/2.21-audible-structure-architecture/2.21-PLAN.md`
- `.planning/phases/2.21-audible-structure-architecture/2.21-CONTEXT.md`
- `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ROUTE-CORRECTION.md`
- `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ALGORITHM-METRICS-RESEARCH.md`

## Phase 2.22 Product Lock

User-facing capabilities should be described as:

- Subtitles
- Word sync
- Chunk replay
- Listening structure
- Phone evidence
- Vocabulary
- Diagnosis
- Practice/Review readiness

Internal names remain valid in advanced resource details:

- WordTimeline
- ChunkTimeline
- PhoneTimeline
- RhythmFrame
- LLTimeline
- provider ids / artifacts / metrics

Readiness states should be explicit:

```text
available | generating | degraded | unavailable | unsupported | stale | error
```

The P0 default path is:

```text
Open media
  -> Generate subtitles with local Whisper
  -> Generated track loads
  -> Word sync readiness appears
  -> document-level rhythm_frames render as Listening structure when available
  -> missing phone/energy evidence is clearly represented
```

## Architecture Lock

Phase 2.21 的关键约束：

- Actual/audible claim 必须有至少一个 audio-backed signal：
  `timing`、`energy`、`pitch` 或 `phone_segmental`。
- 只有 `text_prior` 的 claim 必须标为 predicted，不能展示成 measured/actual。
- Expected side 必须拆成三参考：
  citation form、default connected variants、actual delivery。
- L1-L3 必须能由 WordTimeline + dictionary/syllable structure + duration/energy
  生成；phone evidence absent 时仍然 valid。
- CTC phone evidence 只拥有 L4 connected-speech / segmental explanation。
- Nucleus 是 phrase-scoped learner-facing candidate；低证据 phrase 可以 abstain。
- Duration/RMS harness 是 experiment seam，不是 product generator。

## 已完成

- `cc2043e test: add rhythm acoustic QA harness`
  - 新增 `scripts/prepare-rhythm-acoustic-qa.py`
  - 新增 `scripts/test_prepare_rhythm_acoustic_qa.py`
  - 验证本地 Brooklyn 1 句可通过 ffmpeg 加载音频并产出 WordTimeline duration/RMS 对比。
- 新增 Phase 2.21 planning shell：
  - `2.21-CONTEXT.md`
  - `2.21-PLAN.md`
  - `2.21-AUDIBLE-STRUCTURE-MODEL.md`
- Phase 2.21 Step 1 contract rewrite：
  - `crates/domain/src/sound_analysis.rs` 新增 A/B/C `references`、
    `RhythmSignalSource`、`RhythmEvidenceClass`、`RhythmClaimStatus`、
    prominence cues、phrase-scoped `nuclei`、`connected_speech_refs` 和
    signal-source aware `quality`。
  - `contracts/openapi/v1.yaml` 和 Flutter typed model 已同步。
  - Subtitle rhythm ribbon / diagnosis card 已显示 nucleus 和 predicted vs
    audio-supported provenance。
  - RhythmFrame QA scorer / Helsinki scorer 已输出 signal source 与 evidence
    class 汇总。
  - committed RhythmFrame/Helsinki fixtures 已替换为 2.21 shape；旧 v0-only
    fixture 不再是 active compatibility target。
- Phase 2.21 Step 2 generation boundary 第一刀：
  - `SoundAnalysisConfig` 可携带 sentence-scoped active `WordTiming`。
  - `application::phonetic_fixture` / CTC builder 在创建 sound analysis 前读取 active
    WordTimeline 当前句 timings 并传入 `speech-analysis`。
  - `speech-analysis::sound_analysis` 优先用 WordTimeline timing + dictionary/canonical
    stress 构造 RhythmFrame L1-L3 tokens，输出 `generated_from =
    wordtimeline_timing_prominence_v1`、`quality.timing_source = word_timeline`。
  - 新增 no-phone-evidence Rust test：observed CTC phone evidence absent 时仍可生成
    anchors、phrase-scoped nuclei、weak groups、compression spans 和 phrase boundaries。
- Phase 2.21 Step 2 energy/no-phone seam：
  - `SoundAnalysisConfig` 新增 sentence-scoped `RhythmWordAcousticCue` 输入，
    `speech-analysis` 会把 `energy_prominence` 传播到 anchor prominence、nucleus
    selection、`generated_from = wordtimeline_timing_acoustic_prominence_v1`、
    `references.actual.source = word_timeline_duration_energy` 和
    `quality.prominence_sources`。
  - W4 已补上 production-side `rhythm_word_acoustic_cues` artifact path；W8 manual
    QA/calibration 之前仍不能把 duration/RMS harness 的临时阈值当 production gate。
  - 新增 committed no-phone LLTimeline fixture：
    `testdata/rhythm-frame-qa/fixture-no-phone-rhythm.lltimeline.json`，并纳入
    `fixture-manifest.jsonl` / scorer smoke，覆盖 `phone_evidence_coverage = 0.0`
    时仍有 anchors/nuclei/weak/compression/boundary/hotspot。
  - 无 WordTimeline 时仍保留 `legacy_phone_timing_adapter_v1` /
    `phone_timeline_transitional` fallback；这是下一步要降级/移除的剩余 bridge。
- Phase 2.21 review backlog W1 honesty fix：
  - `speech-analysis::sound_analysis` 已尊重 `WordTiming.timing_source`。
  - 只有 `ForcedAligned` / `AsrAligned` / `UserAdjusted` 会给 L1-L3 claim 增加
    `Timing` signal source 并升级为 `AudioSupported`；`Estimated` timing 只产生
    `TextPrior` / `Predicted` anchors，不选 phrase-scoped nucleus。
  - 新增 Rust 单测覆盖 estimated timing 反例和 aligned timing 正例。
- Phase 2.21 review backlog W2 first-class WordTimeline path：
  - `LLTimelineDocument` 已新增 document-level `rhythm_frames` resource。
  - application export 会从 active WordTimeline + dictionary/canonical stress 直接生成
    `wordtimeline-rhythm-frame`，不经过 phonetic-analysis job / PhoneTimeline 包装，也
    不 fabricate synthetic phones。
  - Flutter 字幕 rhythm layer 现在按 sentence 优先读取
    `LLTimelineDocument.rhythm_frames`，再 fallback 到 `PhoneTimeline.sound_analysis`。
  - 导入会校验 LLTimeline 内 rhythm frame 的 track/media 归属；当前持久源仍是 active
    WordTimeline，导出时可再生，后续若需要编辑/版本化 rhythm frame 再增加独立 DB lifecycle。
- Phase 2.21 review backlog W3 Reference B rule engine：
  - 新增 `speech-analysis::connected_speech_rules`，从英语文本生成 B-side default
    connected forms：closed weak-form lexicon、`could have -> K UH D AH V`、want/going
    to、did you、linking、t/d weakening、flapping 等。
  - `SoundAnalysis.connected_speech` 和 `RhythmFrame.connected_speech_refs` 会合并
    B 规则与 CTC L4 evidence；B-matched audio 标 `teachable_rule`，B-unmatched audio
    标 `clip_specific`。
  - no-phone document-level fixture 现在也有 `text_prior` / `predicted` connected refs，
    但 `phone_evidence_coverage = 0.0`，不把 B 预测伪装成 actual audio。
- Phase 2.21 review backlog W4 arch path：
  - `scripts/timeline-production/production_pipeline.py` 会从 production side 16k mono
    wav 计算 per-word RMS relative prominence，并写入 `rhythm_word_acoustic_cues`
    LLTimeline artifact。
  - application export 会读取 active WordTimeline 对应 artifact，把
    `energy_prominence` 传入 `RhythmWordAcousticCue`，从而生成 energy-backed
    RhythmFrame provenance；Flutter/app 内仍不承担音频 DSP。
  - W8 manual QA/calibration 仍未完成，不能把当前 RMS calibration 当 release gate。
- Phase 2.21 review backlog W5 Reference A OOV hardening：
  - `speech-analysis` pronunciation provider version 升级为 `fallback-v2`。
  - fallback G2P 现在处理常见 English digraph、soft c/g、final silent e、x，并只给第一个
    fallback vowel primary stress，后续 vowel unstressed，降低 OOV citation/stress prior
    污染。
- Phase 2.21 review backlog W6 information-structure prior：
  - RhythmFrame anchor scoring 会轻微降低重复 content word 的 text-prior prominence，
    并给 phrase-final content 小幅 focus boost。
  - 该 prior 仍只算 `TextPrior`，不会把缺少 timing/energy/pitch/phone evidence 的 claim
    升级成 `AudioSupported`。
- Phase 2.21 W8 product QA tooling：
  - RhythmFrame QA schema/scorer/template 已把 `nuclei` 和
    `connected_speech_refs` 纳入 first-class manual-label fields。
  - `scripts/evaluate-rhythm-frame.py --emit-template` 现在支持
    `--template-require-rhythm-frame` 和 `--limit`；quality gates 新增
    `--min-rhythm-frame-sentences`、`--min-word-timeline-rhythm-sentences`、
    `--min-energy-prominence-sentences`。
  - 旧 Phase 2.17 real-media artifacts 只有 1 条旧 v0 phone-timeline RhythmFrame；
    readiness summary 为 WordTimeline RhythmFrame = 0、energy prominence = 0、
    manual labels = 0，因此不能直接作为 W8 closeout。
  - 本轮已用 Brooklyn product media 生成新的 W8 local QA pack：
    `.tmp/rhythm-frame-qa/w8-product/brooklyn-w8.lltimeline.json` 有 114 个
    `wordtimeline_timing_acoustic_prominence_v1` RhythmFrames；
    `.tmp/rhythm-frame-qa/w8-product/annotations-template.jsonl` 有 10 条选中句子的
    空人工标注模板；`.tmp/rhythm-frame-qa/w8-product/clips/` 有对应 10 个 wav clips。
  - 已修复 import remap bug：LLTimeline import 重写 WordTimeline/sentence ids 时，
    `rhythm_word_acoustic_cues` artifact 的 `timeline_id` 和 cue `sentence_id` 也会同步重写。
    修复前 artifact 会保留旧 id，导致导出 RhythmFrame 没有 `energy` provenance。
  - 空模板 strict validation 通过，但 scorer 现在不会把空模板计为 manual annotations；
    当前 `annotated_sentence_count = 0`，W8 仍需人工听标。
- Phase 2.22 planning shell:
  - 新增 `2.22-CONTEXT.md`：解释为什么当前问题是用户可见工作流，而不是单个 `rhythm_frames` 开关。
  - 新增 `2.22-FEATURE-SEMANTICS-MODEL.md`：定义用户能力栈、readiness states、命名原则和 feature template。
  - 新增 `2.22-CURRENT-FEATURE-INVENTORY.md`：参考 `uiworktree` 的功能描述，覆盖媒体、字幕、播放、资源、词汇、诊断、听感/音素、设置和任务反馈等当前全部功能。
  - 新增 `2.22-PLAN.md`：按 UI audit、capability readiness、本机 Whisper 默认路径、资源面板、Listening structure 语义、typed status、布局入口和端到端 QA 推进。
  - PROJECT / ROADMAP / REQUIREMENTS / STATE 已同步 Phase 2.22 与 `UX-001` 至 `UX-008`。

## Next Concrete Work

工程主线从 Phase 2.22 Step 0 开始：

1. 审计当前 Flutter 全部功能入口、标签、状态和用户可见状态机，重点文件是 `main.dart`、
   `transcription_ui.dart`、AppBar、资源面板、settings、本地化文案和 subtitle overlay。
2. 设计并实现 app/session/media/subtitle 级 capability readiness model。
3. 优先修本机 Whisper 默认路径：生成字幕后，用户能看到 generated track、Word sync、
   Listening structure、Phone evidence 的可用状态和下一步行动。
4. 将 `sound pattern` 语义收敛为 Listening structure / Phone evidence，并修正文案中
   仍暗示必须有 `sound_analysis` 的旧描述。

并行保留 Phase 2.21 W8：

1. 填写 `.tmp/rhythm-frame-qa/w8-product/annotations-template.jsonl`
   的 anchors/nuclei/weak groups/reductions/manual scores，并跑 scorer gate。
2. 继续降级/移除 `phone_timeline_transitional` 对 L1-L3 的 fallback ownership，并用
   manual QA / Helsinki scorer 验证 provenance-aware scoring。

## Candidate Files

- `apps/desktop/lib/main.dart`
- `apps/desktop/lib/transcription_ui.dart`
- `apps/desktop/lib/localization.dart`
- `apps/desktop/lib/settings.dart`
- `apps/desktop/lib/controllers/subtitle_controller.dart`
- `apps/desktop/lib/controllers/speech_enhancement_workflow_controller.dart`
- `apps/desktop/lib/widgets/app_bar/player_app_bar.dart`
- `apps/desktop/lib/widgets/panels/subtitle_resource_manager_panel.dart`
- `apps/desktop/lib/widgets/panels/timeline_resource_summary_panel.dart`
- `apps/desktop/lib/widgets/settings/settings_dialog.dart`
- `apps/desktop/lib/widgets/subtitle/rhythm_frame_ribbon.dart`
- `apps/desktop/lib/widgets/panels/diagnosis_card.dart`
- `apps/desktop/test/`
- `crates/domain/src/sound_analysis.rs`
- `contracts/openapi/v1.yaml`
- `apps/desktop/lib/models/timeline.dart`
- `testdata/rhythm-frame-qa/fixture-rhythm.lltimeline.json`
- `scripts/evaluate-rhythm-frame.py`
- `scripts/evaluate-helsinki-prosody.py`
- `scripts/prepare-rhythm-acoustic-qa.py`
- `crates/application/src/word_timelines.rs`
- `crates/speech-analysis/src/sound_analysis.rs`
- `crates/speech-analysis/src/connected_speech_rules.rs`
- `scripts/timeline-production/production_pipeline.py`

## Validation To Run Next

Latest focused validation passed:

- `python3 scripts/test_evaluate_rhythm_frame.py`
- `python3 scripts/test_evaluate_helsinki_prosody.py`
- `python3 scripts/test_prepare_rhythm_acoustic_qa.py`
- `./scripts/validate-contracts.sh`
- `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo test -p domain -p speech-analysis --quiet`
- `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo test -p domain -p application --quiet`
- `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart test/diagnosis_card_test.dart`
- `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo fmt --check`
- `$HOME/.local/share/flutter/bin/dart format --set-exit-if-changed ...`
- `git diff --check`
