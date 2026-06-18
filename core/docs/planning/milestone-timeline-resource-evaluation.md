# Timeline Resource And Evaluation Milestone

## Goal

Build a product-grade resource and evaluation system for word/phone timelines,
so word highlighting, phone highlighting, and chunk partitioning are driven by
measurable, reusable, and human-correctable timing data rather than ad hoc
algorithm output or visual impressions.

## Non-Goals

- Do not choose a final production aligner before evaluation exists.
- Do not bundle Python, PyTorch, MFA, or Kaldi into the app in this milestone.
- Do not replace existing subtitle playback contracts until timeline resources
  can degrade safely to current behavior.
- Do not make chunk partitioning depend on unreviewed experimental data by
  default.

## Principles

- `SubtitleTrack` is the transcript/cue resource.
- `WordTimeline` is the reusable word-level timing resource.
- `PhoneTimeline` is the future phone-level timing resource.
- `ChunkTimeline` is the reusable chunk partition resource.
- Algorithm output is a candidate resource, not ground truth.
- User-adjusted resources have higher precedence than algorithm resources.
- Evaluation reports must be reproducible from stored inputs and artifacts.

## Phase 0: Current-State Hardening

### Problems

- Completed ASR jobs are reused by `input_fingerprint`, blocking re-generation
  after timing algorithm changes.
- Transcription jobs cannot be deleted or archived from the task list.
- SRT export is sentence-level only.
- Raw ASR/FA artifacts are discarded with the temp work directory.
- Word timings exist, but there is no versioned run identity.
- Chunk partitions are computed on demand and not reusable resources.

### Deliverables

- Add `archive` or `delete` for transcription jobs.
- Add `force: true` to transcription job creation, or include timing
  algorithm/config version in the ASR input fingerprint.
- Keep ordinary users safe by preserving current default reuse behavior unless
  force/regenerate is requested.
- Add a visible UI action for archive/delete and a separate action for
  "regenerate with current algorithms".
- Add tests that a completed job can be regenerated when forced.

### Acceptance Gate

- A user can run the same media/model/settings again after algorithm changes.
- The old job remains inspectable or archived unless explicitly deleted.
- Generated subtitle tracks are not orphaned silently.

## Phase 1: Versioned Word Timeline Resource

### Domain Model

Add a first-class `WordTimeline` resource:

```rust
pub struct WordTimeline {
    pub id: WordTimelineId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub config_hash: String,
    pub parent_timeline_id: Option<WordTimelineId>,
    pub created_by: TimelineCreator,
    pub status: TimelineStatus,
    pub metrics_json: serde_json::Value,
    pub words: Vec<WordTiming>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}
```

Suggested enums:

```rust
pub enum TimelineCreator {
    Algorithm,
    User,
}

pub enum TimelineStatus {
    Candidate,
    Active,
    Archived,
}
```

### Persistence

- Add a schema migration for `word_timeline_runs`.
- Keep current `word_timings` compatibility table or migrate it to a view-like
  active timeline lookup.
- Store timeline metadata separately from per-sentence timing JSON.
- Preserve provider/source on every `WordTiming`.
- Allow multiple timelines for one track.

### API

Add endpoints:

```text
GET  /v1/subtitles/{track_id}/word-timelines
GET  /v1/word-timelines/{timeline_id}
POST /v1/subtitles/{track_id}/word-timelines
POST /v1/word-timelines/{timeline_id}/activate
POST /v1/word-timelines/{timeline_id}/archive
GET  /v1/word-timelines/{timeline_id}/export
```

Compatibility:

- Existing `GET /v1/subtitles/{track_id}/word-timings` returns the active
  timeline's words.
- Existing `POST /v1/subtitles/{track_id}/word-timings` creates a
  `user-adjusted` timeline or updates the active user timeline.

### Acceptance Gate

- DTW, pause-refined, FA, and user-adjusted timings can coexist for one track.
- UI and playback use the active timeline.
- Existing tracks without timelines still fall back to estimated timings.

## Phase 2: Objective Timing Evaluation

### Evaluation Inputs

Support two modes:

```text
gold mode:
  media clip + transcript + manual word boundaries

weak mode:
  one or more algorithm timelines without manual boundaries
```

### Metrics

Gold metrics:

- start MAE and median absolute error;
- end MAE and median absolute error;
- onset accuracy at 25/50/100/200 ms;
- offset accuracy at 25/50/100/200 ms;
- lead/lag bias;
- coverage;
- monotonicity violations;
- duration outliers;
- sentence-end lag.

Weak metrics:

- pairwise timeline offset distribution;
- FA-DTW drift by sentence and by word position;
- first/last word cue offset;
- trailing lag after final word;
- overlap/gap anomalies;
- provider mix;
- confidence distribution;
- suspicious words list.

### Artifacts

Store or export:

```text
whisper-result.json
dtw-timeline.json
pause-refined-timeline.json
fa-raw-aligned.json
merged-fa-timeline.json
evaluation-report.json
evaluation-report.md
```

### API / CLI

Add a developer-facing CLI first:

```text
scripts/evaluate-word-timelines.py --track <id> --timeline <id> [--gold file]
```

Then expose HTTP:

```text
POST /v1/word-timelines/compare
GET  /v1/word-timelines/{timeline_id}/diagnostics
```

### Acceptance Gate

- A DTW vs FA comparison can be generated without rerunning transcription.
- A report lists measurable regressions and suspicious spans.
- Reports can be committed as fixtures for future algorithm changes.

## Phase 3: Research Aligners As Timeline Generators

### MMS_FA Candidate

- Keep current torchaudio sidecar as a research generator.
- Stop treating sidecar presence as an implicit product default once
  timelines exist.
- Generate a named candidate timeline:

```text
algorithm_id = "torchaudio-ctc-forced-aligner"
algorithm_version = "mms-fa-v1"
status = candidate
```

- Store raw `aligned.json` for diagnostics.

### MFA Candidate

Add an MFA research sidecar:

```text
scripts/forced-align/setup-mfa-research.sh
scripts/forced-align/mfa-align-cli.py
```

It should generate word and phone timeline candidates:

```text
algorithm_id = "montreal-forced-aligner"
algorithm_version = "<mfa-version>-<model-version>"
```

Use MFA as:

- a strong English candidate;
- a quality reference for MMS_FA and future native aligners;
- a research-only path until packaging, model, and license decisions are made.

### VAD / Windowing

Add windowing experiments as separate configs:

- full Whisper segment window;
- DTW-prior window;
- VAD-trimmed segment window;
- DTW-prior plus VAD-trimmed window.

Every config change must produce a distinct `config_hash`.

### Acceptance Gate

- The same track can have DTW, MMS_FA, and MFA candidate timelines.
- Evaluation reports show whether each candidate improves or regresses fast
  speech, pauses, and sentence-end lag.
- No research aligner overwrites a user-adjusted active timeline.

## Phase 4: Human Correction Workflow

### Word Timeline Editing

Add UI for adjusting word boundaries:

- drag word start/end handles;
- nudge selected boundary by small increments;
- split/merge untrustworthy word intervals only when token identity is stable;
- mark a word as uncertain or ignored for evaluation.

Save edits as:

```text
created_by = user
algorithm_id = "user-adjusted"
parent_timeline_id = <algorithm timeline>
status = active
```

### Chunk Timeline Editing

After chunk timelines exist, allow:

- split chunk;
- merge adjacent chunks;
- move chunk boundary to another word boundary;
- mark chunk boundary as user-confirmed.

### Acceptance Gate

- Human edits survive app restart.
- Algorithm regeneration never silently overwrites user edits.
- User-adjusted timelines can serve as gold references in later evaluations.

## Phase 5: Versioned Chunk Timeline Resource

### Domain Model

Add `ChunkTimeline`:

```rust
pub struct ChunkTimeline {
    pub id: ChunkTimelineId,
    pub track_id: SubtitleTrackId,
    pub word_timeline_id: WordTimelineId,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub config_hash: String,
    pub parent_chunk_timeline_id: Option<ChunkTimelineId>,
    pub created_by: TimelineCreator,
    pub status: TimelineStatus,
    pub chunks_json: serde_json::Value,
    pub diagnostics_json: serde_json::Value,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}
```

### API

```text
GET  /v1/subtitles/{track_id}/chunk-timelines
GET  /v1/chunk-timelines/{timeline_id}
POST /v1/subtitles/{track_id}/chunk-timelines
POST /v1/chunk-timelines/{timeline_id}/activate
POST /v1/chunk-timelines/{timeline_id}/archive
GET  /v1/chunk-timelines/{timeline_id}/diagnostics
```

Compatibility:

- Existing `GET /v1/subtitles/{track_id}/chunk-partitions` returns the active
  chunk timeline, or computes one from the active word timeline when missing.

### Acceptance Gate

- Chunk output can be compared across DTW/MMS_FA/MFA/user-adjusted word
  timelines.
- User-adjusted chunks are reusable resources.
- Diagnostics record why each boundary was selected or rejected.

## Phase 6: Productization Decision

Once evaluation data exists, choose a default generation path.

Candidate outcomes:

- **MFA wins clearly**: use MFA as English research/default generator first,
  then decide whether to package MFA, provide optional install, or derive a
  native/ONNX path.
- **MMS_FA plus VAD/windowing is close enough**: continue toward a lighter
  CTC-based product path.
- **Neither is stable enough**: keep algorithm timelines as suggestions and
  prioritize human correction and reuse.

Promotion gates:

- improves gold MAE/median error over DTW;
- reduces sentence-end lag in fast speech;
- does not increase overlap/monotonicity failures;
- improves or preserves chunk boundary quality;
- acceptable runtime on representative long media;
- license and packaging constraints are clear.

## Suggested Implementation Order

1. Add ASR job archive/delete and forced regeneration.
2. Introduce `WordTimeline` persistence while preserving existing word timing API.
3. Convert transcription output to create versioned word timeline candidates.
4. Add timeline export and weak comparison report.
5. Add raw artifact retention for research runs.
6. Add MFA research sidecar as a candidate/reference aligner.
7. Add manual word timing correction and user-adjusted timelines.
8. Add chunk timeline persistence and comparison.
9. Decide product default based on reports.

## Test Plan

- Persistence migration tests for multiple timelines per track.
- API tests for list/get/create/activate/archive/export timeline endpoints.
- Regression tests that existing word timing endpoints still work.
- Transcription tests for forced regeneration and old-job reuse behavior.
- Evaluation fixture tests with synthetic gold boundaries.
- Golden tests comparing chunk output from two word timelines.
- UI tests for archive/delete/regenerate controls.

## Documentation Updates

- Update `docs/features/asr-word-timestamps.md` after `WordTimeline` lands.
- Update `docs/features/forced-alignment.md` once MMS_FA becomes a named
  timeline generator instead of implicit venv-triggered behavior.
- Add a developer guide for creating timing evaluation clips.
- Add a user-facing guide for choosing and correcting generated timelines.
