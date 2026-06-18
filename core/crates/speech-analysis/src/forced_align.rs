//! Acoustic forced alignment result merging.
//!
//! The actual alignment runs in an external Python sidecar (`align-cli.py`,
//! using torchaudio's MMS_FA CTC forced aligner). This module is responsible
//! for *consuming* that sidecar's JSON output and merging the physically-aligned
//! timestamps into the existing `WordTiming` vector — validating each aligned
//! word and falling back to the original ASR (DTW) timing per-word when an
//! aligned value is implausible.
//!
//! Design goals:
//! - **Per-word degradation**: a single bad alignment must never corrupt an
//!   entire sentence. Only words that pass validation get `TimingSource::ForcedAligned`;
//!   the rest keep their original source.
//! - **Monotonicity**: the merged timeline must stay non-decreasing in
//!   `start_ms`. We enforce this strictly per sentence.
//! - **No surprises downstream**: `chunk_partition::acoustic_gap_threshold`
//!   already treats `ForcedAligned` with a stricter (180ms) threshold, so once
//!   a word flips to `ForcedAligned` the better path is taken automatically.

use domain::{SubtitleSentence, SubtitleTokenKind, TimingSource, WordTiming};
use serde::Deserialize;

pub const PROVIDER_ID: &str = "torchaudio-ctc-forced-aligner";
pub const PROVIDER_VERSION: &str = "mms-fa-v1";

/// One aligned word as emitted by `align-cli.py`.
///
/// `segment_index` matches `SubtitleSentence.index` (whisper segment order),
/// and `word_index` is the 0-based position among lexical word tokens in that
/// segment — the same indexing scheme used by `asr_timing::extract_word_timings`.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct AlignedWord {
    pub segment_index: u32,
    pub word_index: u32,
    #[allow(dead_code)]
    pub text: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub score: Option<f32>,
}

/// Wrapper for the sidecar's stdout JSON: `{ "timings": [...] }`.
#[derive(Debug, Clone, Deserialize)]
pub struct AlignOutput {
    pub timings: Vec<AlignedWord>,
}

/// Per-segment validation context: the sentence window and the list of
/// `WordTiming` row indices that belong to that sentence (in word order).
struct SegmentContext {
    sentence_index: u32,
    sentence_start_ms: u64,
    sentence_end_ms: u64,
    /// Indices into the `timings` slice owned by this sentence, in word order.
    rows: Vec<usize>,
}

/// Merge forced-alignment output into an existing `WordTiming` vector.
///
/// `asr_timings` is mutated in place: each row whose corresponding aligned
/// word passes validation is rewritten with the aligned `start_ms`/`end_ms`,
/// retagged `TimingSource::ForcedAligned`, and given the alignment `score` as
/// its confidence. Rows without a valid alignment are left untouched (they
/// keep their DTW timing and `AsrReported` source).
///
/// `aligned` may contain entries that don't match any sentence (e.g. when
/// whisper produced an extra segment); those are ignored. Entries referencing
/// a `segment_index` with no matching sentence are also ignored.
///
/// Returns the number of rows that were upgraded to `ForcedAligned`.
pub fn merge_alignments(
    asr_timings: &mut [WordTiming],
    aligned: &[AlignedWord],
    sentences: &[SubtitleSentence],
) -> usize {
    if aligned.is_empty() || asr_timings.is_empty() || sentences.is_empty() {
        return 0;
    }

    // Build per-segment row index maps. We key on sentence.index (== segment
    // order), collecting the positions of that sentence's word-timing rows in
    // ascending token_index order.
    let mut segments: std::collections::HashMap<u32, SegmentContext> =
        std::collections::HashMap::new();
    for sentence in sentences {
        let start_ms = sentence.start.get();
        let end_ms = sentence.end.get();
        // Collect row indices for this sentence, sorted by token_index.
        let mut rows: Vec<(u32, usize)> = asr_timings
            .iter()
            .enumerate()
            .filter(|(_, t)| t.sentence_id == sentence.id)
            .map(|(i, t)| (t.token_index, i))
            .collect();
        rows.sort_by_key(|(idx, _)| *idx);
        let rows: Vec<usize> = rows.into_iter().map(|(_, i)| i).collect();
        if rows.is_empty() {
            continue;
        }
        segments.insert(
            sentence.index,
            SegmentContext {
                sentence_index: sentence.index,
                sentence_start_ms: start_ms,
                sentence_end_ms: end_ms,
                rows,
            },
        );
    }

    // Group aligned words by (segment_index, word_index). word_index is the
    // 0-based word position within the segment, matching the ordering of
    // `SegmentContext.rows`.
    let mut upgraded = 0usize;
    for ctx in segments.values() {
        let rows = &ctx.rows;
        // Gather aligned entries for this segment, indexed by word_index.
        let mut by_word: std::collections::HashMap<u32, &AlignedWord> =
            std::collections::HashMap::new();
        for w in aligned {
            if w.segment_index == ctx.sentence_index {
                by_word.entry(w.word_index).or_insert(w);
            }
        }
        if by_word.is_empty() {
            continue;
        }

        // First pass: compute candidate (start, end) for every row, or None
        // if the aligned value is invalid. We store candidates separately so
        // the monotonicity check can reject a candidate without losing the
        // original timing.
        let mut candidates: Vec<Option<(u64, u64, Option<f32>)>> =
            vec![None; rows.len()];
        for (word_pos, _) in rows.iter().enumerate() {
            let Some(w) = by_word.get(&(word_pos as u32)) else {
                continue;
            };
            if !is_plausible(w.start_ms, w.end_ms, ctx) {
                continue;
            }
            candidates[word_pos] = Some((w.start_ms, w.end_ms, w.score));
        }

        // Enforce monotonicity within the sentence: a candidate whose start is
        // before the previous accepted end is rejected. We walk left-to-right
        // using whichever baseline (original or candidate) the previous row
        // settled on.
        let mut prev_end: Option<u64> = None;
        for (word_pos, &row_idx) in rows.iter().enumerate() {
            let original = &asr_timings[row_idx];
            let original_end = original.end_ms;
            // Decide the effective end of the previous row for monotonicity.
            let baseline_prev_end = prev_end.unwrap_or(0);

            if let Some((start, end, _score)) = candidates[word_pos] {
                if start < baseline_prev_end {
                    // Candidate would break monotonicity — drop it.
                    candidates[word_pos] = None;
                    prev_end = Some(original_end);
                } else {
                    prev_end = Some(end);
                }
            } else {
                prev_end = Some(original_end);
            }
        }

        // Apply accepted candidates.
        for (word_pos, &row_idx) in rows.iter().enumerate() {
            if let Some((start, end, score)) = candidates[word_pos] {
                let row = &mut asr_timings[row_idx];
                row.start_ms = start;
                row.end_ms = end;
                row.confidence = score.or(row.confidence);
                row.timing_source = TimingSource::ForcedAligned;
                row.provider_id = PROVIDER_ID.into();
                row.provider_version = PROVIDER_VERSION.into();
                upgraded += 1;
            }
        }
    }

    upgraded
}

/// A plausible aligned word must:
/// - have start <= end,
/// - fall entirely within the sentence window, and
/// - have non-zero duration (end > start) — a zero-duration alignment carries
///   no information over the DTW estimate.
fn is_plausible(start_ms: u64, end_ms: u64, ctx: &SegmentContext) -> bool {
    if end_ms <= start_ms {
        return false;
    }
    // Allow touching the sentence boundaries but not exceeding them.
    if start_ms < ctx.sentence_start_ms || end_ms > ctx.sentence_end_ms {
        return false;
    }
    true
}

/// Count how many lexical word tokens a sentence has (the unit `align-cli.py`
/// aligns). Useful for callers building the sidecar request.
pub fn count_lexical_words(sentence: &SubtitleSentence) -> usize {
    sentence
        .tokens
        .iter()
        .filter(|t| t.kind == SubtitleTokenKind::Word)
        .count()
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{
        SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs,
    };

    fn sentence(index: u32, id: &str, start: u64, end: u64, words: &[&str]) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index,
            start: TimeMs::new(start),
            end: TimeMs::new(end),
            original_text: words.join(" "),
            display_text: words.join(" "),
            tokens: words
                .iter()
                .enumerate()
                .map(|(i, text)| SubtitleToken {
                    index: i as u32,
                    kind: SubtitleTokenKind::Word,
                    text: (*text).into(),
                    normalized: Some(text.to_lowercase()),
                    start_char: 0,
                    end_char: text.len() as u32,
                })
                .collect(),
        }
    }

    fn dtw_timing(
        sentence_id: &SubtitleSentenceId,
        token_index: u32,
        text: &str,
        start_ms: u64,
        end_ms: u64,
    ) -> WordTiming {
        WordTiming {
            sentence_id: sentence_id.clone(),
            token_index,
            text: text.into(),
            start_ms,
            end_ms,
            confidence: None,
            timing_source: TimingSource::AsrReported,
            provider_id: "whisper.cpp".into(),
            provider_version: "dtw-v2".into(),
        }
    }

    #[test]
    fn upgrades_words_that_align_within_sentence_window() {
        let s = sentence(0, "s1", 0, 2000, &["hello", "world"]);
        let mut timings = vec![
            dtw_timing(&s.id, 0, "hello", 0, 1000),
            dtw_timing(&s.id, 1, "world", 1000, 2000),
        ];
        let aligned = vec![
            AlignedWord {
                segment_index: 0,
                word_index: 0,
                text: "hello".into(),
                start_ms: 120,
                end_ms: 480,
                score: Some(0.95),
            },
            AlignedWord {
                segment_index: 0,
                word_index: 1,
                text: "world".into(),
                start_ms: 600,
                end_ms: 980,
                score: Some(0.93),
            },
        ];
        let upgraded = merge_alignments(&mut timings, &aligned, &[s]);
        assert_eq!(upgraded, 2);
        assert_eq!(timings[0].start_ms, 120);
        assert_eq!(timings[0].end_ms, 480);
        assert_eq!(timings[0].timing_source, TimingSource::ForcedAligned);
        assert_eq!(timings[0].provider_id, PROVIDER_ID);
        assert_eq!(timings[0].confidence, Some(0.95));
        assert_eq!(timings[1].start_ms, 600);
        assert_eq!(timings[1].timing_source, TimingSource::ForcedAligned);
    }

    #[test]
    fn rejects_aligned_word_outside_sentence_window() {
        let s = sentence(0, "s1", 1000, 3000, &["hello", "world"]);
        let mut timings = vec![
            dtw_timing(&s.id, 0, "hello", 1000, 2000),
            dtw_timing(&s.id, 1, "world", 2000, 3000),
        ];
        // "hello" aligned at 500ms — before sentence start of 1000ms.
        let aligned = vec![AlignedWord {
            segment_index: 0,
            word_index: 0,
            text: "hello".into(),
            start_ms: 500,
            end_ms: 900,
            score: Some(0.9),
        }];
        let upgraded = merge_alignments(&mut timings, &aligned, &[s]);
        assert_eq!(upgraded, 0);
        assert_eq!(timings[0].timing_source, TimingSource::AsrReported);
        assert_eq!(timings[0].start_ms, 1000); // unchanged
    }

    #[test]
    fn rejects_zero_duration_alignment() {
        let s = sentence(0, "s1", 0, 2000, &["hello"]);
        let mut timings = vec![dtw_timing(&s.id, 0, "hello", 0, 2000)];
        let aligned = vec![AlignedWord {
            segment_index: 0,
            word_index: 0,
            text: "hello".into(),
            start_ms: 500,
            end_ms: 500,
            score: Some(0.9),
        }];
        let upgraded = merge_alignments(&mut timings, &aligned, &[s]);
        assert_eq!(upgraded, 0);
    }

    #[test]
    fn enforces_monotonicity_within_sentence() {
        let s = sentence(0, "s1", 0, 3000, &["a", "b", "c"]);
        let mut timings = vec![
            dtw_timing(&s.id, 0, "a", 0, 1000),
            dtw_timing(&s.id, 1, "b", 1000, 2000),
            dtw_timing(&s.id, 2, "c", 2000, 3000),
        ];
        // "b" candidate starts before accepted "a" end → rejected. Because
        // "b" falls back to its original 1000-2000ms span, "c" also cannot be
        // accepted at 1100ms without overlapping the fallback timing.
        let aligned = vec![
            AlignedWord {
                segment_index: 0,
                word_index: 0,
                text: "a".into(),
                start_ms: 100,
                end_ms: 900,
                score: Some(0.9),
            },
            AlignedWord {
                segment_index: 0,
                word_index: 1,
                text: "b".into(),
                start_ms: 200, // before a.end (900)
                end_ms: 800,
                score: Some(0.9),
            },
            AlignedWord {
                segment_index: 0,
                word_index: 2,
                text: "c".into(),
                start_ms: 1100,
                end_ms: 2000,
                score: Some(0.9),
            },
        ];
        let upgraded = merge_alignments(&mut timings, &aligned, &[s]);
        assert_eq!(upgraded, 1); // a upgraded, b/c rejected
        assert_eq!(timings[0].timing_source, TimingSource::ForcedAligned);
        assert_eq!(timings[1].timing_source, TimingSource::AsrReported); // b kept DTW
        assert_eq!(timings[2].timing_source, TimingSource::AsrReported);
    }

    #[test]
    fn ignores_aligned_entries_for_unknown_segments() {
        let s = sentence(0, "s1", 0, 1000, &["hello"]);
        let mut timings = vec![dtw_timing(&s.id, 0, "hello", 0, 1000)];
        let aligned = vec![
            AlignedWord {
                segment_index: 99, // no such segment
                word_index: 0,
                text: "ghost".into(),
                start_ms: 100,
                end_ms: 200,
                score: Some(0.9),
            },
            AlignedWord {
                segment_index: 0,
                word_index: 0,
                text: "hello".into(),
                start_ms: 100,
                end_ms: 500,
                score: Some(0.9),
            },
        ];
        let upgraded = merge_alignments(&mut timings, &aligned, &[s]);
        assert_eq!(upgraded, 1);
    }

    #[test]
    fn handles_multiple_sentences_independently() {
        let s0 = sentence(0, "s1", 0, 1000, &["one", "two"]);
        let s1 = sentence(1, "s2", 1000, 2000, &["three"]);
        let mut timings = vec![
            dtw_timing(&s0.id, 0, "one", 0, 500),
            dtw_timing(&s0.id, 1, "two", 500, 1000),
            dtw_timing(&s1.id, 0, "three", 1000, 2000),
        ];
        let aligned = vec![
            AlignedWord {
                segment_index: 0,
                word_index: 0,
                text: "one".into(),
                start_ms: 50,
                end_ms: 400,
                score: None,
            },
            // s1/word0 deliberately absent → stays AsrReported
        ];
        let upgraded = merge_alignments(&mut timings, &aligned, &[s0, s1]);
        assert_eq!(upgraded, 1);
        assert_eq!(timings[0].timing_source, TimingSource::ForcedAligned);
        assert_eq!(timings[1].timing_source, TimingSource::AsrReported);
        assert_eq!(timings[2].timing_source, TimingSource::AsrReported);
        // score=None should preserve existing confidence (None).
        assert_eq!(timings[0].confidence, None);
    }

    #[test]
    fn empty_or_mismatched_inputs_are_noops() {
        let s = sentence(0, "s1", 0, 1000, &["hello"]);
        let mut timings = vec![dtw_timing(&s.id, 0, "hello", 0, 1000)];
        assert_eq!(merge_alignments(&mut timings, &[], &[s.clone()]), 0);
        let empty: Vec<WordTiming> = Vec::new();
        let mut empty_timings = empty.clone();
        assert_eq!(
            merge_alignments(&mut empty_timings, &[], &[s.clone()]),
            0
        );
    }

    #[test]
    fn deserializes_sidecar_output() {
        let json = br#"{"timings":[{"segment_index":0,"word_index":0,"text":"hi","start_ms":10,"end_ms":90,"score":0.88}]}"#;
        let out: AlignOutput = serde_json::from_slice(json).unwrap();
        assert_eq!(out.timings.len(), 1);
        assert_eq!(out.timings[0].segment_index, 0);
        assert_eq!(out.timings[0].start_ms, 10);
        assert_eq!(out.timings[0].score, Some(0.88));
    }

    #[test]
    fn count_lexical_words_skips_punctuation() {
        let mut s = sentence(0, "s1", 0, 1000, &["hello", "world"]);
        s.tokens.push(SubtitleToken {
            index: 2,
            kind: SubtitleTokenKind::Punctuation,
            text: ".".into(),
            normalized: None,
            start_char: 0,
            end_char: 1,
        });
        assert_eq!(count_lexical_words(&s), 2);
    }
}
