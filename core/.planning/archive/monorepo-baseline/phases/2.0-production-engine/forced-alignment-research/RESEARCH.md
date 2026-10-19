# Milestone 2.0 Phase 0 Research Plan

## Current Decision

Phase 0 is active. No release provider has been selected and no candidate may
produce product-facing `detected_in_audio` findings.

The repository now contains a versioned 60-slot evaluation catalog and a
provider-neutral scorer. The catalog is structurally complete, but all entries
remain `planned` until licensed audio and human-verified actual-phone references
are attached outside or inside the repository as permitted.

## Required Inputs

For every catalog slot in
`testdata/phonetic-analysis/evaluation-catalog-v1.tsv`, record:

- licensed audio locator and immutable checksum;
- exact transcript and media-relative range;
- word ranges or a documented unavailable reason;
- actual-phone reference, phone set, annotator, and review status;
- target phenomena and whether the example is positive, negative, or uncertain;
- source license and redistribution decision.

Buckeye inputs must remain outside Git. The catalog may record identifiers and
checksums, but not restricted audio or derived annotations without approval.
The operational manifest format and review checklist are documented in
[`m20-evaluation-inputs.md`](../development/m20-evaluation-inputs.md).

## Benchmark Order

1. Populate and independently review at least 10 development cases.
2. Implement a ZIPA ONNX adapter as an isolated research spike.
3. Run the adapter on the reviewed development cases and normalize its output.
4. Measure Phone Error Rate, timeline validity, token association, real-time
   factor, peak memory, model size, and failure rate on Apple Silicon.
5. Add the Wav2IPA/Buckeye quality baseline under research-only controls.
6. Evaluate Vosk/Kaldi as a lightweight word-timing and forced-alignment
   baseline. Treat phone-level output as experimental until a reproducible
   adapter proves that it exposes actual pronunciation variation rather than
   canonical decoder alignments.
7. Name and review any specific Wav2Vec2Phoneme model before benchmarking it.
8. Run the locked test split only after candidate and threshold decisions are
   fixed.
9. Perform manual precision review for high-confidence weak-form, deletion,
   flap, assimilation, contraction, and linking findings.
10. Accept a release provider or record a no-provider decision in a final ADR.

Every candidate adapter must preserve the provider/runtime/model separation and
normalized result shape. Research code may use an in-process library for rapid
measurement, but release integration must not expose Kaldi, ONNX Runtime,
Transformers, or another candidate-specific type through the shared contract.
The preferred third-party release boundary is the versioned out-of-process
provider protocol proposed in ADR 0009.

## Normalized Result Shape

Each reference and prediction file is JSONL with one object per case:

```json
{
  "case_id": "m20-001",
  "audio_start_ms": 1000,
  "audio_end_ms": 2400,
  "phone_set": "provider_specific",
  "phones": [
    {
      "symbol": "phone",
      "start_ms": 1000,
      "end_ms": 1080,
      "token_index": 0
    }
  ]
}
```

Provider provenance, model revision, confidence, and raw output should be
included in real benchmark artifacts even though the scorer ignores additional
fields.

## Commands

Validate the fixed catalog:

```bash
python3 scripts/phonetic-eval.py validate-catalog \
  testdata/phonetic-analysis/evaluation-catalog-v1.tsv
```

Validate an external reviewed development-input manifest:

```bash
python3 scripts/phonetic-eval.py validate-inputs \
  /absolute/path/to/development-inputs.jsonl \
  --catalog testdata/phonetic-analysis/evaluation-catalog-v1.tsv \
  --minimum-cases 10
```

Score normalized output:

```bash
python3 scripts/phonetic-eval.py score reference.jsonl prediction.jsonl
```

Verify the Phase 0 research infrastructure:

```bash
scripts/verify-m20-phase0.sh
```

Inspect the pinned ZIPA dependency and artifact boundary without downloading or
approving anything:

```bash
python3 scripts/phonetic-research-adapter.py check-zipa --variant int8
```

Prepare the isolated research environment only after explicitly accepting that
the model license metadata remains unverified:

```bash
LLPLAYERNEXT_ACCEPT_UNVERIFIED_ZIPA_MODEL_LICENSE=1 \
  scripts/setup-zipa-research.sh
```

The setup script pins Python dependencies, code/model revisions, and checksums,
and stores everything outside the repository. Its explicit opt-in permits a
research download only; it does not approve redistribution or product use.

The isolated candidate harness rejects unlicensed audio and candidate output
without a monotonic per-phone timeline. ZIPA CTC ONNX output exposes
frame-level `log_probs` and `log_probs_len`, but upstream simplified inference
discards frame spans while collapsing the sequence. The research harness can
derive an explicitly experimental linear CTC frame projection; it must be
calibrated against real audio before the timestamps are treated as stable. The
harness records wall time, real-time factor, observed process RSS, model size,
revision, license identifier, and failures for successful external-adapter
runs.

`scripts/zipa-ctc-onnx-research.py` is the research-only ZIPA CTC runner. It
preserves CTC frame spans and emits the normalized candidate-adapter shape. It
is not a release provider, and its linear frame projection remains experimental
until calibrated on the reviewed development batch.

## Exit Criteria

Phase 0 is complete only when:

- all 50-100 fixed cases have verified references and explicit licenses;
- each required candidate has a reproducible benchmark report;
- candidate license, provenance, and distribution reviews are complete;
- Apple Silicon performance measurements are recorded;
- manual high-confidence finding precision is recorded;
- ADR 0008 is superseded by an accepted release-provider or no-provider ADR.
