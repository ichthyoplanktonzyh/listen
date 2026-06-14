# LLPlayerNext Project Handoff: 2026-06-14 M2.0 Progress

## Scope And Repository State

- Workspace: `/Users/shadow/LLPlayerNext`
- Branch: `feature/asr-word-timestamps`
- Base commit: `888f310`
- Active objective: continue the current worktree's Milestone 2.0 until its
  real completion gates are satisfied and verified.
- Milestone 2.0 is **not complete**. No real phonetic provider has passed the
  quality, licensing, performance, and manual-review gates.

Ignore the unrelated listening-chunk feature discussion from another worktree.
In this worktree, preserve this user-owned untracked file exactly as-is:

- `docs/discuss/chunk-based-listening-comprehension.md`

Do not stage, edit, delete, or use that file as Milestone 2.0 scope.

The current worktree contains a large uncommitted Milestone 2.0 implementation.
Do not reset or discard it. Run `git status --short` before editing.

## Read First

1. `docs/planning/milestone-2.0.md`
2. `docs/planning/milestone-2.0-phase0-research.md`
3. `docs/decisions/0008-m20-phase0-phonetic-provider-research.md`
4. `docs/verification/milestone-2.0-phase0-report.md`
5. `scripts/verify-m20.sh`

## Implemented Milestone 2.0 Scaffold

### Research And Release Boundary

- Versioned 60-slot Phase 0 evaluation catalog and candidate registry.
- Provider-neutral scorer for Phone Error Rate, timeline validity, and token
  association coverage.
- `scripts/verify-m20-phase0.sh` and CI coverage.
- Deterministic research fixture is disabled in normal builds unless
  `LLPLAYERNEXT_ENABLE_FAKE_PHONETIC_PROVIDER=1`.
- The fixture model is explicitly non-distributable and not application
  verified.
- No fake or low-confidence result may be presented as real
  `detected_in_audio`.

### Core, Persistence, API, And Events

- Provider-neutral phonetic provider/model/job/analysis/finding/feedback domain
  contracts.
- Schema v9 migration and persistence for models, durable jobs, detected-phone
  timelines, alignments, findings, and feedback.
- Active jobs become `interrupted` on coordinator startup.
- Completed analyses remain readable after model deletion.
- Multiple model/analysis revisions are preserved instead of overwritten.
- Feedback is included in versioned vocabulary/user-asset bundle v4; generated
  analysis data remains excluded from user-asset backup.
- API and generated client cover provider/model management, durable jobs,
  track analyses, findings, and feedback.
- Model management safely rejects the research fixture and unavailable release
  provider operations.
- SSE events cover model/job/analysis/feedback changes.

### Deterministic Analysis And Fake Lifecycle

- Dynamic-programming phone alignment covers match, insertion, deletion,
  substitution, and merge.
- Deterministic finding classification covers weak form, elision, flapping,
  assimilation, contraction, and linking/insertion families.
- Confidence gates distinguish `uncertain`, `supported_by_alignment`, and
  `detected_in_audio`; only confidence `>= 0.75` may use the final state.
- Fake research modes support deterministic success, partial result, failure,
  slow/cancellable execution, retry, interruption, and idempotency tests.
- Track-scope jobs produce one persisted analysis per subtitle sentence.

### Desktop Experience

- Settings v8 persists provider/model preference, on-demand/batch/off mode,
  experimental-result visibility, detected-phone highlight, and cache policy.
- Saving unrelated settings preserves all v8 phonetic settings.
- Current sentence and whole-track analysis triggers.
- Audio-analysis model/job center with provider diagnostics, model licensing,
  provenance, experimental state, progress, cancellation, and retry.
- Local detected-phone highlighting follows playback position.
- Diagnosis card explicitly separates canonical pronunciation, rule prediction,
  and experimental audio detection.
- Detected phones and findings can loop their media ranges.
- Findings show evidence/confidence and support confirmed/rejected/ignored
  feedback.
- Latest analysis version wins in the desktop sentence map.

## Verification Evidence

The following checks passed before the final handoff-only edits:

- `bash scripts/validate-contracts.sh`
- `LLPLAYERNEXT_M20_SKIP_HISTORY=1 bash scripts/verify-m20.sh`
- Flutter analysis and 42 Flutter tests.
- Targeted Rust suites for domain, application, persistence, speech analysis,
  and API.
- API lifecycle tests cover success, partial result, cancellation, failure,
  retry, idempotency, whole-track analysis, feedback, and model rejection.
- Persistence tests cover v8-to-v9 migration, interruption, version retention,
  model deletion resilience, and feedback backup/restore.
- Focused widget tests cover the phonetic analysis center, cancellation/retry,
  and distinct current-sentence/whole-track triggers.
- Local detected-phone highlighting is covered across non-monotonic playback
  positions representing seek, loop return, and drag behavior.
- The complete historical `scripts/verify-m20.sh` regression passed with 150
  Rust tests and 45 Flutter tests.
- The latest Flutter suite contains 46 passing tests.
- `scripts/build-macos-mvp.sh` and `scripts/verify-mvp.sh` passed, including
  bundled-runtime discovery, ad-hoc signing verification, extracted-package
  launch, video/audio smoke, and persistence checks.

The last full strict run before the newest increments passed formatting,
Clippy, 147 Rust tests, Flutter analysis, and 41 Flutter tests. The execution
host then killed the final contract child with `SIGKILL`/137; the identical
contract command passed independently before and after. This host limitation is
recorded in `docs/verification/milestone-2.0-phase0-report.md`.

Rerun the complete verification set after further implementation before making
any stronger claim:

```bash
cd /Users/shadow/LLPlayerNext
export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$HOME/.local/share/flutter/bin:$PATH"

cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cd apps/desktop && flutter analyze && flutter test && cd ../..
bash scripts/validate-contracts.sh
LLPLAYERNEXT_M20_SKIP_HISTORY=1 bash scripts/verify-m20.sh
git diff --check
```

The full historical phase of `scripts/verify-m20.sh` may still encounter the
current host's long-command `SIGKILL` behavior. Do not treat that as a product
pass or failure without rerunning the killed command independently.

## Immediate Next Work

1. Populate and independently review at least 10 licensed development cases
   with human-verified actual-phone references.
2. Implement and validate a ZIPA timestamp-derivation adapter, because upstream
   simplified ONNX inference currently emits a phone sequence without a stable
   per-phone timeline.
3. Audit remaining automatic-test requirements in
   `docs/planning/milestone-2.0.md`, especially:
   - model download interruption/checksum/incompatibility/license/space paths
     once a real candidate model flow exists;
   - IPA display mapping for provider-specific detected phones;
4. Evaluate Vosk/Kaldi as a lightweight ASR and forced-alignment baseline,
   without treating canonical decoder alignment as actual-phone detection.
5. Continue Phase 0 research without weakening the release boundary or the
   proposed extensible-provider and dual-license strategy in ADR 0009.

## Phase 0 Research State

No candidate has been run on the fixed evaluation set. All 60 catalog entries
remain `planned`, with no licensed audio and human-verified actual-phone
references attached.

The latest research check established:

- Target host: Apple M1 Max, 32 GiB, arm64, macOS 26.5.1.
- ZIPA code repository states MIT, but the Hugging Face model repository does
  not expose model-license metadata. Model weights therefore remain
  distribution-unverified.
- ZIPA model repository revision:
  `9a8d85ba0d2adcbafe7087b82180d0e65c6f3426`.
- ZIPA ONNX artifacts observed:
  - FP32: 260,267,872 bytes, SHA-256
    `b7955abbf80065fdeeb90e80fe4e76c6e61f59a305b6015c48e34d7375f91e69`
  - FP16: 131,607,660 bytes, SHA-256
    `d5631c72b46ea4f39d46b4e76f999db16297e66de29c27b27699b341d78abe93`
  - INT8: 70,677,672 bytes, SHA-256
    `8f0505173e4606b4afe041f19477b38d6a72a98a19863562749066dc496e86ae`
- The host currently lacks `onnxruntime`, `torch`, `lhotse`, `soundfile`, and
  `librosa`. No performance number was fabricated.
- `scripts/phonetic-research-adapter.py` now provides the reproducible isolated
  dependency/artifact check and candidate harness. It requires licensed
  external audio, rejects missing/non-monotonic phone timestamps, emits the
  normalized scorer JSONL shape, and records runtime/resource/failure metadata.
- ZIPA upstream simplified ONNX inference prints a phone sequence but no stable
  per-phone timeline. Timestamp derivation remains an explicit research task.

The next safe Phase 0 step is to attach licensed reviewed development inputs
and implement a ZIPA-specific timestamp derivation adapter behind the isolated
harness. It must remain outside the release provider path until licenses and
quality gates pass.

## Completion Gate

Do not mark Milestone 2.0 complete, create `v0.8.0`, or claim real audio
detection until all of the following are proven:

- 50-100 licensed, human-verified evaluation cases;
- required candidate benchmarks and manual high-confidence precision review;
- acceptable exact runtime/model licenses, provenance, and distribution rights;
- Apple Silicon performance/resource measurements;
- selected release provider meeting the documented thresholds;
- full automatic, historical, packaging, and real-evaluation verification;
- collaborative user acceptance;
- closure documentation, commit, and tag.

If no provider meets the gates, record an explicit no-release-provider decision
and keep Milestone 2.0 incomplete rather than weakening the claims.
