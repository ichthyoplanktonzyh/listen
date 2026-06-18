# Milestone 2.0 Evaluation Input Preparation

This guide describes the external inputs required before a phonetic candidate
may be benchmarked. It is an operational checklist, not permission to copy
restricted audio or annotations into Git.

## First Development Batch

Prepare at least 10 development cases selected from the fixed `dev` slots in
`testdata/phonetic-analysis/evaluation-catalog-v1.tsv`.
The selected initial case IDs are locked in
[`m20-first-development-batch.md`](./m20-first-development-batch.md).

The first batch should collectively include:

- news, interview, and conversational speech;
- normal and fast speech;
- clean and noisy recordings;
- weak form, flap, `t/d` deletion, contraction, assimilation, and word linking;
- positive examples plus at least two negative or uncertain examples.

Each case needs an independently reviewed actual-phone timeline. Canonical
dictionary pronunciation or forced alignment alone is not an actual-phone
reference.

## External Manifest

Store licensed audio outside the repository unless redistribution is explicitly
allowed. Create a JSONL manifest outside Git with one object per case:

Generate the locked first-batch skeleton:

```bash
python3 scripts/phonetic-eval.py create-input-template \
  testdata/phonetic-analysis/evaluation-catalog-v1.tsv \
  --case-ids m20-001,m20-002,m20-004,m20-011,m20-013,m20-015,m20-021,m20-022,m20-023,m20-024 \
  > /absolute/path/to/development-inputs.jsonl
```

```json
{
  "case_id": "m20-001",
  "audio_path": "/absolute/path/to/licensed-audio.wav",
  "audio_sha256": "lowercase 64-character sha256",
  "transcript": "Exact spoken transcript.",
  "audio_start_ms": 1000,
  "audio_end_ms": 2400,
  "word_ranges": [
    {"text": "exact", "start_ms": 1000, "end_ms": 1300}
  ],
  "phone_set": "ipa_broad",
  "phones": [
    {"symbol": "phone", "start_ms": 1000, "end_ms": 1080}
  ],
  "annotator": "stable-person-or-team-id",
  "reviewer": "different-stable-person-or-team-id",
  "review_status": "verified",
  "source_license": "exact license or access terms identifier",
  "redistribution": "prohibited",
  "source_locator": "stable source URL or corpus identifier",
  "notes": "Optional annotation decisions and uncertainty."
}
```

For restricted corpora, `audio_path` may be an absolute path on the research
machine and `redistribution` must be `prohibited`. Do not commit that audio,
derived restricted annotations, or the external manifest without explicit
approval.

## Validation

Run:

```bash
python3 scripts/phonetic-eval.py validate-inputs \
  /absolute/path/to/development-inputs.jsonl \
  --catalog testdata/phonetic-analysis/evaluation-catalog-v1.tsv \
  --minimum-cases 10
```

The validator checks:

- every case belongs to the fixed catalog;
- audio exists and matches its immutable SHA-256;
- source license and redistribution decisions are explicit;
- transcript, media range, word ranges, phone set, and actual-phone timeline
  are present and valid;
- phone and word ranges are bounded and monotonic;
- an independent reviewer verified each reference.

Passing this command means the batch is structurally ready for a candidate
development run. It does not prove that the source license permits product
distribution, that the annotations are correct, or that any model is eligible
for release.

## Human Review Notes

Record uncertainty instead of forcing a narrow transcription. When annotators
cannot agree on the observed phone, preserve the disagreement in `notes` and
keep the example out of high-confidence precision calculations until resolved.

Use a stable, documented phone inventory. Any mapping from a provider-specific
inventory into the reference inventory requires separate review.
