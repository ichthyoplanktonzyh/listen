# Continue Here — Phase 2.20 Rhythm-First Listening Analysis

> 最后更新：2026-06-30 CST
> 单一接续入口。先读 `AGENT.md` 和 `.planning/STATE.md`，再读本文件。

## 当前结论

Phase 2.20 的产品方向是对的：

```text
在字幕层显示当前句子的实际可听结构
```

已经落地的 `RhythmFrame` contract、字幕层 rhythm UI、rhythm/phones toggle、
expected pronunciation reference、cue loop、QA scorer、Helsinki/LibriTTS scorer
和 benchmark role convention 都应保留。

但是路线复盘确认：

```text
当前 generator 的 CTC-derived rhythm skeleton 不能作为 product truth
```

需要迁移到：

```text
forced-aligned WordTimeline skeleton
  + duration/rate evidence
  + RMS energy/loudness evidence
  + optional F0/pitch evidence after calibration
  + CTC phone evidence as segmental detail only
```

核心文档：

- `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ROUTE-CORRECTION.md`
- `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ACOUSTIC-FEATURE-PATH.md`
- `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ALGORITHM-METRICS-RESEARCH.md`
- `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-EVALUATION.md`

## 已落地但需重新定位

- `crates/speech-analysis/src/sound_analysis.rs`
  - deterministic RhythmFrame v0 已存在。
  - stress anchors 目前主要是 `text_predicted` prior，不是 observed prominence。
  - `pre_boundary_lengthening` 已实现，但现在只算 fallback/diagnostic `heuristic_proxy`。
  - CTC phone evidence 只应支持 flapping/deletion/weak-form/phone-mismatch 等 segmental
    explanations，不再当 rhythm skeleton。
- `scripts/evaluate-helsinki-prosody.py`
  - 已输出 `benchmark_context`。
  - 已输出 `score_summary.predicted_boundary_evidence_counts`。
- `testdata/rhythm-prosody-benchmarks/benchmark-roles.json`
  - 已约定 benchmark role/evidence class/closeout use。

## 最新本地 diagnostic

20 句 Helsinki/LibriTTS dev smoke 已完成，artifact 在 ignored `.tmp`：

```text
.tmp/helsinki-libritts-rhythm-dev-20/manifest.jsonl
.tmp/helsinki-libritts-rhythm-dev-20/timelines/*.lltimeline.json
```

Scorer result:

```text
scored_sentence_count: 20
text_mismatch_count: 1
stress_anchor_f1: 0.574949
phrase_boundary_f1: 0.210145
predicted_boundary_evidence_counts:
  pause: 218
  pre_boundary_lengthening: 17
```

Interpretation:

- This is not a gate.
- Current CTC-derived baseline over-predicts phrase boundaries.
- It confirms the need to move rhythm skeleton to forced-aligned WordTimeline +
  duration/rate + RMS energy.

## Next Concrete Work

Do not keep optimizing CTC-derived RhythmFrame as the main route.

Next session should implement or design this experiment:

1. Select 5-10 local sentences for manual QA.
2. Compare:
   - current CTC-derived RhythmFrame;
   - forced-aligned WordTimeline + duration/rate;
   - forced-aligned WordTimeline + RMS energy/loudness.
3. Use manual labels for:
   - actual prominent words;
   - weak/reduced groups;
   - compressed regions;
   - phrase boundaries;
   - hotspot score: `correct`, `useful_but_incomplete`, `unclear`, `misleading`,
     `unsupported`.
4. Decide whether duration+energy is enough for Phase 2.20 closeout or whether
   F0/pitch reset must enter this phase.

Candidate files to inspect:

- `scripts/run-sound-line-real-media-case.py`
- `scripts/prepare-helsinki-libritts-benchmark.py`
- `scripts/evaluate-rhythm-frame.py`
- `scripts/evaluate-helsinki-prosody.py`
- `scripts/timeline-production/`
- `crates/speech-analysis/src/rich_acoustic_evidence.rs`
- `crates/speech-analysis/src/sound_analysis.rs`

## Validation Already Run In This Thread

- `python3 scripts/test_evaluate_helsinki_prosody.py`
- `python3 scripts/test_rhythm_benchmark_roles.py`
- `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo fmt --check`
- `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo test -p speech-analysis sound_analysis --quiet`
- `python3 scripts/evaluate-helsinki-prosody.py --prosody-dir /Users/shadow/prosody --split dev --limit 20 --lltimeline-manifest .tmp/helsinki-libritts-rhythm-dev-20/manifest.jsonl`

Run `git diff --check` before handing off again.

## Important Rule

`AGENT.md` now states the governing principle: project data, smoke samples,
automatic labels and current metrics are diagnostic signals, not truth. Algorithm
and metric changes should be grounded in published research, corpus annotation
conventions, reported baselines, or manual product QA.
