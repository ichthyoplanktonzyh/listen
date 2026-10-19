# ADR 0008: Milestone 2.0 Phase 0 Phonetic Provider Research

- Status: Proposed
- Date: 2026-06-13

## Context

Milestone 2.0 requires real-audio phone recognition, but no candidate has yet
been measured on LLPlayerNext's fixed evaluation set. Product integration before
that measurement would violate the milestone's quality and licensing gates.

The Phase 0 evaluation catalog currently fixes 60 case slots. The audio,
transcripts, word ranges, and human-verified actual-phone references are not
checked into this repository until their licenses permit redistribution.

## Decision

Do not select or integrate a release provider yet.

Evaluate candidates in this order:

1. **ZIPA small CR-CTC ONNX** is the first Apple Silicon performance spike.
   Its paper claims permissive releases and the model repository publishes
   FP32, FP16, and INT8 ONNX artifacts. It is not eligible for product
   integration until the exact code and model licenses, model revision,
   training-data provenance, phone inventory, and distribution rights are
   recorded. Code and model provenance remain separate: the currently inspected
   GitHub code revision is `f96afe2842868bb1d3cea1efe191806fdcd3c955`, while
   the model repository revision is
   `9a8d85ba0d2adcbafe7087b82180d0e65c6f3426`.
2. **Wav2IPA/Buckeye direction** is the first American conversational-speech
   quality baseline. Buckeye material stays outside the repository and product
   because its access terms restrict use to non-profit research and education.
3. **A Wav2Vec2Phoneme-compatible model** is not a candidate until an exact
   model revision and license are named. Wav2Vec2Phoneme is an implementation
   family, not a distributable model decision.
4. **Vosk/Kaldi** is a lightweight ASR and forced-alignment research baseline.
   Its public API primarily exposes text, word timing, and confidence rather
   than a stable detected-phone timeline. Any Kaldi-internal phone-alignment
   experiment must prove that it preserves real pronunciation variation
   instead of normalizing it through the decoding lexicon and language model.
   Vosk API, Kaldi, and each exact model require separate license and
   distribution review even when their published licenses are permissive.
5. **Allosaurus** is a research baseline only. Its GPL-3.0 license is not
   accepted for default product distribution.

All candidates must emit the normalized JSONL shape consumed by
`scripts/phonetic-eval.py`. Provider-specific phone symbols remain unchanged in
raw results; comparison requires a separately reviewed mapping into the
evaluation phone set.

Candidate adapters remain outside the release-provider path until selected.
The long-term provider architecture should use the versioned, capability-
negotiated, preferably out-of-process boundary proposed in ADR 0009 so one
runtime or model license cannot determine the whole product architecture.

## Phase 0 Gates

A release-provider ADR may replace this proposal only after evidence includes:

- 50-100 human-verified evaluation cases with explicit source licenses;
- result timelines valid and within requested ranges for at least 95% of cases;
- at least 85% of detected phones associated with subtitle tokens;
- manually reviewed high-confidence finding precision of at least 75%;
- measured Apple Silicon real-time factor, peak memory, model size, and power;
- exact runtime/model revisions, checksums, licenses, training-data provenance,
  and distribution rights.

Phone Error Rate is reported but does not have a standalone release threshold.
The model must preserve useful real-speech variation instead of merely
normalizing audio to canonical pronunciation.

## Consequences

- M2.0 remains in Phase 0 and no output may be labeled `detected_in_audio`.
- Provider-neutral API, persistence, job, alignment, feedback, and disabled-by-
  default desktop scaffolding may be implemented and verified with a
  deterministic research fixture.
- No release provider may be enabled, no model may be distributed, and no
  result may be presented as real audio detection until the gates pass.
- Buckeye-derived audio and annotations remain external research inputs.
- The fixed catalog and scoring code can compare candidates without changing
  metrics between runs.

## Sources

- [ZIPA repository](https://github.com/lingjzhu/zipa)
- [ZIPA small ONNX artifacts](https://huggingface.co/anyspeech/zipa-small-crctc-300k)
- [Buckeye Speech Corpus](https://buckeyecorpus.osu.edu/)
- [Wav2Vec2Phoneme documentation](https://huggingface.co/docs/transformers/en/model_doc/wav2vec2_phoneme)
- [Allosaurus repository](https://github.com/xinjli/allosaurus)
- [Vosk API repository](https://github.com/alphacep/vosk-api)
- [Vosk model catalog](https://alphacephei.com/vosk/models)
- [Kaldi legal information](https://kaldi-asr.org/doc/legal.html)
- [ADR 0009](./0009-open-source-commercial-and-provider-ecosystem.md)
- [Milestone 2.0 plan](../planning/milestone-2.0.md)
