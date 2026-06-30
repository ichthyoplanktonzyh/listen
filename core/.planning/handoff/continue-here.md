# Continue Here — Phase 2.21 Audible Structure Architecture

> 最后更新：2026-06-30 CST
> 单一接续入口。先读 `AGENT.md` 和 `.planning/STATE.md`，再读本文件。

## 当前结论

Phase 2.20 的产品方向是对的：

```text
在字幕层显示当前句子的实际可听结构
```

已经落地的 `RhythmFrame` v0 resource、字幕层 rhythm UI、rhythm/phones toggle、
expected pronunciation reference、cue loop、QA scorer、Helsinki/LibriTTS scorer、
duration/RMS manual QA harness 和 benchmark role convention 都应保留为脚手架或实验
输入。

但是当前主工作方已经切到 Phase 2.21：

```text
先锁 actual audible structure architecture
再重写 RhythmFrame contract / generator / evaluation
```

旧 `RhythmFrame` v0、旧 fixture、旧 `.tmp` artifact 兼容性如果阻碍新结构，可以不保留。

## 上位文档

- `.planning/phases/2.21-audible-structure-architecture/2.21-AUDIBLE-STRUCTURE-MODEL.md`
- `.planning/phases/2.21-audible-structure-architecture/2.21-PLAN.md`
- `.planning/phases/2.21-audible-structure-architecture/2.21-CONTEXT.md`
- `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ROUTE-CORRECTION.md`
- `.planning/phases/2.20-rhythm-first-listening-analysis/2.20-ALGORITHM-METRICS-RESEARCH.md`

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

## Next Concrete Work

从 Phase 2.21 Step 1 开始：

1. 重写 `crates/domain/src/sound_analysis.rs` 的 `RhythmFrame` contract。
2. 同步 `contracts/openapi/v1.yaml`。
3. 同步 Flutter typed model：`apps/desktop/lib/models/timeline.dart`。
4. 替换 active fixtures/tests 到新 shape；不需要为 v0-only fixture 保兼容。
5. 再推进生成边界：WordTimeline + dictionary/syllable structure + duration/energy，
   CTC phones 只链接到 L4 connected-speech refs。

## Candidate Files

- `crates/domain/src/sound_analysis.rs`
- `contracts/openapi/v1.yaml`
- `apps/desktop/lib/models/timeline.dart`
- `apps/desktop/lib/widgets/subtitle/rhythm_frame_ribbon.dart`
- `apps/desktop/lib/widgets/panels/diagnosis_card.dart`
- `testdata/rhythm-frame-qa/fixture-rhythm.lltimeline.json`
- `scripts/evaluate-rhythm-frame.py`
- `scripts/evaluate-helsinki-prosody.py`
- `scripts/prepare-rhythm-acoustic-qa.py`

## Validation To Run Next

After contract edits:

- `python3 scripts/test_evaluate_rhythm_frame.py`
- `python3 scripts/test_evaluate_helsinki_prosody.py`
- `python3 scripts/test_prepare_rhythm_acoustic_qa.py`
- `./scripts/validate-contracts.sh`
- `PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo test -p domain -p application --quiet`
- `cd apps/desktop && $HOME/.local/share/flutter/bin/flutter test test/phoneme_ribbon_test.dart`
- `git diff --check`
