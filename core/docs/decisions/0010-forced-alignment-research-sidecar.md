# ADR 0010: Forced Alignment Research Sidecar

## Status

Accepted for research validation on `feature/forced-alignment-research`.

## Context

LLPlayerNext already stores provider-neutral word timings and uses
`TimingSource::ForcedAligned` downstream. Whisper DTW v2 gives useful
word-level timing, but it is based on cross-attention alignment rather than a
direct acoustic model. Real-video testing showed cases where highlighting leads
the audible word.

Acoustic forced alignment can address this by aligning known transcript words to
the physical waveform. The available practical prototype is torchaudio's MMS_FA
CTC aligner, but that requires Python, PyTorch, torchaudio, and model cache
access. Those dependencies do not match the current pure native app bundle.

## Decision

Add forced alignment as an opt-in research sidecar:

- `scripts/forced-align/setup-venv.sh` prepares an isolated venv under
  `~/Library/Caches/LLPlayerNext/research/forced-align/`.
- `scripts/forced-align/align-cli.py` reads a JSON stdin request and writes
  aligned word timings as JSON stdout.
- `crates/api-http/src/transcription.rs` auto-detects the venv and script during
  Whisper transcription. If either is missing, the sidecar is skipped.
- `speech_analysis::forced_align::merge_alignments()` validates each aligned
  word and falls back to the original DTW timing per word.
- The sidecar runs after DTW extraction and before local pause refinement.

The Python and torch stack is not bundled into the app.

## Consequences

- Ordinary users see no behavior change and no extra runtime dependency.
- Developers can opt in by preparing the research venv.
- A failed sidecar cannot fail transcription or erase DTW timings.
- Successful aligned words automatically activate downstream
  `forced_aligned` chunk thresholds.
- The research path can be removed or replaced without schema changes because it
  uses the existing provider-neutral timing contract.

## Rejected Alternatives

- **Bundle Python and torch now.** Rejected because it would enlarge and
  complicate the native app bundle before quality and distribution questions are
  answered.
- **Add a UI switch now.** Rejected because the feature is not productized; venv
  presence is enough for a research opt-in.
- **Align the whole recording at once.** Rejected for the prototype because
  whisper segment windows provide useful anchors and reduce long-audio Viterbi
  drift.

## Future Path

If manual validation confirms better word highlighting and chunk boundaries, a
future ADR should choose a production aligner and packaging strategy. Preferred
directions are a Rust-native or ONNX Runtime based implementation with
license-cleared artifacts and explicit model provenance.
