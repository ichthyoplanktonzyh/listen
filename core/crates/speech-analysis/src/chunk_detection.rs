//! Acoustic chunk boundary detection from word-level timestamps.
//!
//! This module detects prosodic chunk boundaries (intonation unit / tone unit
//! boundaries) from existing word-level timing data. The primary signal is the
//! inter-word gap duration: a pause above the configured threshold suggests a
//! prosodic boundary between two chunks.
//!
//! This is a Phase 1 spike implementation using gap-based detection only.
//! Future enhancements may incorporate pitch reset, pre-boundary lengthening,
//! and lexical features.

use std::collections::HashMap;

use domain::{SubtitleSentenceId, WordTiming};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// Parameters controlling chunk-boundary detection behaviour.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChunkDetectionConfig {
    /// Minimum inter-word gap (ms) to consider a prosodic boundary.
    /// Literature consensus: 200–300 ms. Default: 250.
    pub gap_threshold_ms: u64,

    /// When true, the effective threshold is lowered for gaps that coincide
    /// with punctuation (comma, period, etc.).  Default: true.
    pub use_punctuation_hint: bool,

    /// Multiplier applied to `gap_threshold_ms` when a punctuation hint is
    /// present.  Default: 0.5 (threshold halved).
    pub punctuation_threshold_multiplier: f32,
}

impl Default for ChunkDetectionConfig {
    fn default() -> Self {
        Self {
            gap_threshold_ms: 250,
            use_punctuation_hint: true,
            punctuation_threshold_multiplier: 0.5,
        }
    }
}

/// A detected prosodic boundary between two consecutive words.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChunkBoundary {
    /// Array position (0-based index into the `WordTiming` slice) of the word
    /// to the left of the boundary.  This is the primary position reference
    /// for chunk building because `token_index` may reset across sentences.
    pub position: u32,

    /// Token index of the word to the left of the boundary.
    pub left_token_index: u32,

    /// Token index of the word to the right of the boundary.
    pub right_token_index: u32,

    /// Gap duration in milliseconds = right.start_ms - left.end_ms.
    pub gap_ms: u64,

    /// Confidence that this is a genuine prosodic boundary, in [0.0, 1.0].
    pub confidence: f32,

    /// Additional acoustic or lexical evidence tags (empty in Phase 1).
    pub markers: Vec<BoundaryMarker>,
}

/// Additional evidence beyond the raw gap that may strengthen a boundary.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum BoundaryMarker {
    /// The left word is significantly longer than the speaker's mean word
    /// duration — a classic pre-boundary lengthening cue.
    PreBoundaryLengthening,

    /// Pitch is expected to reset at this position.
    PitchReset,

    /// A punctuation mark (comma, period, question-mark, exclamation-mark)
    /// immediately precedes the right word.
    PunctuationHint,

    /// A filled pause (uh, um) occupies this gap.
    Hesitation,

    /// A multi-word lexical/phrasal chunk was detected at this position from
    /// text-level analysis (COCA n-gram, PHRASE List, or dictionary match).
    LexicalPhrase {
        /// The phrase text (original case from the sentence).
        phrase: String,
        /// Source identifier: "coca", "phrase_list", "ecdict", "builtin".
        source: String,
    },
}

/// A group of consecutive words that form a single acoustic chunk.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChunkGroup {
    /// Index of the first word in this chunk (inclusive).
    pub token_start: u32,

    /// Index of the last word in this chunk (inclusive).
    pub token_end: u32,

    /// Space-joined text of the words in this chunk.
    pub text: String,

    /// Start time of the chunk in ms = timings[token_start].start_ms.
    pub start_ms: u64,

    /// End time of the chunk in ms = timings[token_end].end_ms.
    pub end_ms: u64,

    /// The boundary detected at the right edge of this chunk, if any.
    /// `None` for the sentence-final chunk.
    pub boundary: Option<ChunkBoundary>,
}

/// Complete chunk-detection result for a single sentence.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChunkDetectionResult {
    /// Sentence this result corresponds to.
    pub sentence_id: SubtitleSentenceId,

    /// Detected chunks in temporal order.
    pub chunks: Vec<ChunkGroup>,

    /// All detected boundaries within this sentence.
    pub boundaries: Vec<ChunkBoundary>,

    /// The configuration used to produce this result.
    pub config: ChunkDetectionConfig,

    /// Raw gap durations between every consecutive word pair (ms).
    /// Length = max(0, word_count - 1).  Useful for debugging and
    /// visualisation.
    pub raw_gaps_ms: Vec<u64>,
}

// ---------------------------------------------------------------------------
// Combined (acoustic + text) types
// ---------------------------------------------------------------------------

/// Combined chunk detection result merging acoustic and text-level evidence.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CombinedChunkResult {
    /// Sentence this result corresponds to.
    pub sentence_id: SubtitleSentenceId,
    /// Merged chunks with combined confidence.
    pub chunks: Vec<CombinedChunkGroup>,
    /// Whether acoustic timing data was available.
    pub acoustic_available: bool,
    /// Whether text chunk data was available.
    pub text_available: bool,
}

/// A single chunk group with both acoustic and text-level boundary evidence.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CombinedChunkGroup {
    pub token_start: u32,
    pub token_end: u32,
    pub text: String,
    pub start_ms: Option<u64>,
    pub end_ms: Option<u64>,
    pub acoustic_boundary: Option<ChunkBoundary>,
    pub text_boundary: Option<crate::text_chunk_detection::TextChunkBoundary>,
    /// Combined confidence in [0.0, 1.0].
    pub combined_confidence: f32,
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Detect acoustic chunk boundaries from word-level timings for a single
/// sentence.
///
/// `timings` must belong to the same sentence (all share the same
/// `sentence_id`) and be sorted by `start_ms` ascending.  The function
/// handles empty and single-word inputs gracefully.
pub fn detect_chunk_boundaries(
    timings: &[WordTiming],
    config: &ChunkDetectionConfig,
) -> ChunkDetectionResult {
    let sentence_id = timings
        .first()
        .map(|t| t.sentence_id.clone())
        .unwrap_or_else(|| {
            // Sentinel id for empty input — callers should guard against this,
            // but we degrade safely.
            SubtitleSentenceId::parse("empty").unwrap_or_else(|_| {
                panic!("failed to construct sentinel sentence id")
            })
        });

    let raw_gaps = compute_raw_gaps(timings);
    let raw_gaps_ms: Vec<u64> = raw_gaps.iter().map(|(_, gap)| *gap).collect();

    let mut boundaries: Vec<ChunkBoundary> = Vec::new();
    let mut chunks: Vec<ChunkGroup> = Vec::new();

    if timings.is_empty() {
        return ChunkDetectionResult {
            sentence_id,
            chunks,
            boundaries,
            config: config.clone(),
            raw_gaps_ms,
        };
    }

    // Single pass: detect boundaries by enumerating over gap positions.
    // `position` is the array index of the left word — it is the robust
    // position reference because `token_index` resets across sentences.
    for (position, &(_left_token_idx, gap_ms)) in raw_gaps.iter().enumerate() {
        let position = position as u32;
        let right_pos = position + 1;
        let left_token_idx = timings[position as usize].token_index;
        let right_token_idx = timings[right_pos as usize].token_index;

        let effective_threshold = effective_threshold(config, timings, right_pos as usize, gap_ms);

        if gap_ms >= effective_threshold {
            boundaries.push(ChunkBoundary {
                position,
                left_token_index: left_token_idx,
                right_token_index: right_token_idx,
                gap_ms,
                confidence: gap_confidence(gap_ms, effective_threshold),
                markers: Vec::new(), // Phase 1: no additional markers
            });
        }
    }

    // Build chunk groups by scanning through word positions and splitting at
    // detected boundaries.  Uses array position (not token_index) for robust
    // indexing across sentence boundaries.
    let mut chunk_start: usize = 0;
    for boundary in &boundaries {
        let chunk_end = boundary.position as usize;
        chunks.push(build_chunk(timings, chunk_start, chunk_end, Some(boundary.clone())));
        chunk_start = boundary.position as usize + 1;
    }
    // Final chunk (or only chunk when there are no boundaries).
    let last_idx = timings.len().saturating_sub(1);
    if chunk_start <= last_idx {
        chunks.push(build_chunk(timings, chunk_start, last_idx, None));
    }

    ChunkDetectionResult {
        sentence_id,
        chunks,
        boundaries,
        config: config.clone(),
        raw_gaps_ms,
    }
}

/// Convenience wrapper that uses [`ChunkDetectionConfig::default`].
pub fn detect_chunk_boundaries_default(timings: &[WordTiming]) -> ChunkDetectionResult {
    detect_chunk_boundaries(timings, &ChunkDetectionConfig::default())
}

/// Run chunk detection for every sentence in a track.
///
/// Timings are grouped by sentence; each group is processed independently.
/// Cross-sentence boundaries are never created.
pub fn detect_chunk_boundaries_for_track(
    timings_by_sentence: &[(SubtitleSentenceId, Vec<WordTiming>)],
    config: &ChunkDetectionConfig,
) -> HashMap<SubtitleSentenceId, ChunkDetectionResult> {
    let mut results = HashMap::new();
    for (sentence_id, word_timings) in timings_by_sentence {
        let result = detect_chunk_boundaries(word_timings, config);
        results.insert(sentence_id.clone(), result);
    }
    results
}

/// Compute raw inter-word gaps for a sequence of word timings.
///
/// Returns a vector of `(left_token_index, gap_ms)` pairs, one for each
/// consecutive word pair.  The gap is `next.start_ms - current.end_ms`.
/// If two words overlap, the gap is clamped to 0.
pub fn compute_raw_gaps(timings: &[WordTiming]) -> Vec<(u32, u64)> {
    if timings.len() < 2 {
        return Vec::new();
    }
    let mut gaps = Vec::with_capacity(timings.len() - 1);
    for pair in timings.windows(2) {
        let current = &pair[0];
        let next = &pair[1];
        let gap = next.start_ms.saturating_sub(current.end_ms);
        gaps.push((current.token_index, gap));
    }
    gaps
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Map a gap duration to a confidence score in [0.0, 1.0].
///
/// - `gap < threshold` → 0.0
/// - `gap == threshold` → 0.5
/// - `gap >= threshold + 500ms` → 1.0
/// - Linear interpolation in [0.5, 1.0] between threshold and threshold+500.
fn gap_confidence(gap_ms: u64, threshold: u64) -> f32 {
    if gap_ms < threshold {
        return 0.0;
    }
    let excess = (gap_ms - threshold) as f32;
    0.5 + (excess / 500.0).min(1.0) * 0.5
}

/// Compute the effective boundary threshold, potentially lowered by a
/// punctuation hint.
///
/// Phase 1: punctuation hints are not yet implemented because `WordTiming`
/// does not carry token/punctuation context.  When a `SubtitleSentence` is
/// available to the caller, this function can be extended to inspect
/// adjacent tokens.
fn effective_threshold(
    config: &ChunkDetectionConfig,
    _timings: &[WordTiming],
    _right_idx: usize,
    _gap_ms: u64,
) -> u64 {
    // Phase 1: no punctuation hint available from WordTiming alone.
    // Future: accept an optional &SubtitleSentence to inspect token kind.
    if config.use_punctuation_hint {
        // Placeholder — always falls through to base threshold for now.
    }
    config.gap_threshold_ms
}

/// Build a [`ChunkGroup`] spanning the given position range (inclusive).
fn build_chunk(
    timings: &[WordTiming],
    start_pos: usize,
    end_pos: usize,
    boundary: Option<ChunkBoundary>,
) -> ChunkGroup {
    let start_ms = timings[start_pos].start_ms;
    let end_ms = timings[end_pos].end_ms;
    let text: String = timings[start_pos..=end_pos]
        .iter()
        .map(|t| t.text.as_str())
        .collect::<Vec<_>>()
        .join(" ");

    ChunkGroup {
        token_start: timings[start_pos].token_index,
        token_end: timings[end_pos].token_index,
        text,
        start_ms,
        end_ms,
        boundary,
    }
}

/// Combine acoustic and text-level chunk detection results for a single
/// sentence.
///
/// Uses the text partition (which covers every word token) as the structural
/// basis, then overlays acoustic boundary evidence where available.
///
/// Confidence logic:
/// - Acoustic YES + Text YES → `(ac + tc) / 2 + 0.1` (clamped to 1.0)
/// - Acoustic YES + Text NO  → `ac * 0.8`
/// - Acoustic NO  + Text YES → `tc * 0.6`
/// - Neither                  → `0.0`
pub fn combine_chunks(
    acoustic: &ChunkDetectionResult,
    text: &crate::text_chunk_detection::TextChunkDetectionResult,
) -> CombinedChunkResult {
    use std::collections::HashMap;

    // Build lookup: left_token_index → ChunkBoundary (acoustic)
    let acoustic_bounds: HashMap<u32, &ChunkBoundary> = acoustic
        .boundaries
        .iter()
        .map(|b| (b.left_token_index, b))
        .collect();

    // Build lookup: left_token_index → TextChunkBoundary (from text)
    let text_bounds: HashMap<u32, &crate::text_chunk_detection::TextChunkBoundary> = text
        .boundaries
        .iter()
        .map(|b| (b.left_token_index, b))
        .collect();

    let mut combined: Vec<CombinedChunkGroup> = Vec::new();

    for text_chunk in &text.chunks {
        let ac_bound = acoustic_bounds.get(&text_chunk.token_end).copied().cloned();
        let tx_bound = text_bounds.get(&text_chunk.token_end).copied().cloned();

        let combined_confidence = match (&ac_bound, &tx_bound) {
            (Some(ac), Some(tc)) => {
                // Both detect a boundary — mutual reinforcement.
                ((ac.confidence + tc.confidence) / 2.0 + 0.1).min(1.0)
            }
            (Some(ac), None) => {
                // Acoustic boundary, no text phrase edge — possible breath/hesitation.
                ac.confidence * 0.8
            }
            (None, Some(tc)) => {
                // Text phrase edge, no acoustic pause — grammatical chunk.
                tc.confidence * 0.6
            }
            (None, None) => {
                // No boundary signal from either source.
                0.0
            }
        };

        // Map acoustic timing info if available.
        let (start_ms, end_ms) = if !acoustic.chunks.is_empty() {
            // Find the matching acoustic chunk by token range.
            acoustic
                .chunks
                .iter()
                .find(|ac| {
                    ac.token_start == text_chunk.token_start
                        && ac.token_end == text_chunk.token_end
                })
                .map(|ac| (Some(ac.start_ms), Some(ac.end_ms)))
                .unwrap_or((None, None))
        } else {
            (None, None)
        };

        combined.push(CombinedChunkGroup {
            token_start: text_chunk.token_start,
            token_end: text_chunk.token_end,
            text: text_chunk.text.clone(),
            start_ms,
            end_ms,
            acoustic_boundary: ac_bound,
            text_boundary: tx_bound,
            combined_confidence,
        });
    }

    CombinedChunkResult {
        sentence_id: acoustic.sentence_id.clone(),
        chunks: combined,
        acoustic_available: !acoustic.chunks.is_empty() || !acoustic.boundaries.is_empty(),
        text_available: !text.chunks.is_empty() || !text.boundaries.is_empty(),
    }
}

/// Annotate acoustic boundaries with text-derived [`BoundaryMarker::LexicalPhrase`].
///
/// For each acoustic boundary whose `left_token_index` matches a text chunk
/// boundary that has a `preceding_phrase`, a `LexicalPhrase` marker is pushed
/// onto the acoustic boundary's marker list.
pub fn annotate_acoustic_with_text(
    acoustic: &mut ChunkDetectionResult,
    text: &crate::text_chunk_detection::TextChunkDetectionResult,
) {
    for boundary in &mut acoustic.boundaries {
        for tb in &text.boundaries {
            if tb.left_token_index == boundary.left_token_index
                && let Some(ref phrase) = tb.preceding_phrase
            {
                let source = evidence_source_name(&tb.evidence);
                boundary.markers.push(BoundaryMarker::LexicalPhrase {
                    phrase: phrase.clone(),
                    source,
                });
            }
        }
    }
}

fn evidence_source_name(evidence: &crate::text_chunk_detection::TextChunkEvidence) -> String {
    use crate::text_chunk_detection::TextChunkEvidence;
    match evidence {
        TextChunkEvidence::Collocation => "coca".into(),
        TextChunkEvidence::PhraseList => "phrase_list".into(),
        TextChunkEvidence::DictionaryPhrase => "ecdict".into(),
        TextChunkEvidence::SingleWord => "default".into(),
    }
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{TimingSource, WordTiming};

    fn wt(
        sentence_id: &str,
        token_index: u32,
        text: &str,
        start_ms: u64,
        end_ms: u64,
    ) -> WordTiming {
        WordTiming {
            sentence_id: SubtitleSentenceId::parse(sentence_id).unwrap(),
            token_index,
            text: text.to_string(),
            start_ms,
            end_ms,
            confidence: None,
            timing_source: TimingSource::AsrReported,
            provider_id: "test".into(),
            provider_version: "v1".into(),
        }
    }

    // -- compute_raw_gaps --------------------------------------------------

    #[test]
    fn empty_timings_returns_empty_gaps() {
        assert!(compute_raw_gaps(&[]).is_empty());
    }

    #[test]
    fn single_word_returns_empty_gaps() {
        let t = vec![wt("s1", 0, "hello", 0, 100)];
        assert!(compute_raw_gaps(&t).is_empty());
    }

    #[test]
    fn two_words_computes_gap() {
        let t = vec![wt("s1", 0, "a", 0, 80), wt("s1", 1, "b", 180, 300)];
        let gaps = compute_raw_gaps(&t);
        assert_eq!(gaps.len(), 1);
        assert_eq!(gaps[0], (0, 100)); // 180 - 80
    }

    #[test]
    fn overlapping_words_gap_clamped_to_zero() {
        let t = vec![wt("s1", 0, "a", 0, 100), wt("s1", 1, "b", 80, 200)];
        let gaps = compute_raw_gaps(&t);
        assert_eq!(gaps[0].1, 0);
    }

    // -- detect_chunk_boundaries -------------------------------------------

    #[test]
    fn empty_timings_returns_empty_result() {
        let result = detect_chunk_boundaries_default(&[]);
        assert!(result.chunks.is_empty());
        assert!(result.boundaries.is_empty());
        assert!(result.raw_gaps_ms.is_empty());
    }

    #[test]
    fn single_word_returns_single_chunk() {
        let t = vec![wt("s1", 0, "hello", 100, 400)];
        let result = detect_chunk_boundaries_default(&t);
        assert_eq!(result.chunks.len(), 1);
        assert_eq!(result.chunks[0].text, "hello");
        assert!(result.chunks[0].boundary.is_none());
        assert!(result.boundaries.is_empty());
    }

    #[test]
    fn wide_gap_detects_boundary() {
        let t = vec![
            wt("s1", 0, "first", 0, 200),
            wt("s1", 1, "second", 500, 800), // 300ms gap
        ];
        let result = detect_chunk_boundaries_default(&t);
        assert_eq!(result.boundaries.len(), 1);
        assert_eq!(result.boundaries[0].gap_ms, 300);
        assert!(result.boundaries[0].confidence > 0.5);
        assert_eq!(result.chunks.len(), 2);
    }

    #[test]
    fn narrow_gap_no_boundary() {
        let t = vec![
            wt("s1", 0, "first", 0, 200),
            wt("s1", 1, "second", 250, 500), // 50ms gap
        ];
        let result = detect_chunk_boundaries_default(&t);
        assert!(result.boundaries.is_empty());
        assert_eq!(result.chunks.len(), 1);
        assert_eq!(result.chunks[0].text, "first second");
    }

    #[test]
    fn three_words_middle_gap_only() {
        let t = vec![
            wt("s1", 0, "a", 0, 50),
            wt("s1", 1, "b", 70, 120),
            wt("s1", 2, "c", 500, 600), // 380ms gap after b
        ];
        let result = detect_chunk_boundaries_default(&t);
        assert_eq!(result.boundaries.len(), 1);
        assert_eq!(result.boundaries[0].left_token_index, 1);
        assert_eq!(result.boundaries[0].right_token_index, 2);
        assert_eq!(result.chunks.len(), 2);
        assert_eq!(result.chunks[0].text, "a b");
        assert_eq!(result.chunks[1].text, "c");
    }

    #[test]
    fn gap_at_threshold_exact_produces_boundary_confidence_half() {
        let config = ChunkDetectionConfig {
            gap_threshold_ms: 250,
            ..Default::default()
        };
        let t = vec![
            wt("s1", 0, "x", 0, 100),
            wt("s1", 1, "y", 350, 500), // 250ms gap exactly
        ];
        let result = detect_chunk_boundaries(&t, &config);
        assert_eq!(result.boundaries.len(), 1);
        assert!((result.boundaries[0].confidence - 0.5).abs() < f32::EPSILON);
    }

    #[test]
    fn gap_below_threshold_no_boundary() {
        let config = ChunkDetectionConfig {
            gap_threshold_ms: 250,
            ..Default::default()
        };
        let t = vec![
            wt("s1", 0, "x", 0, 100),
            wt("s1", 1, "y", 349, 500), // 249ms gap
        ];
        let result = detect_chunk_boundaries(&t, &config);
        assert!(result.boundaries.is_empty());
    }

    #[test]
    fn large_gap_produces_max_confidence() {
        let t = vec![
            wt("s1", 0, "x", 0, 100),
            wt("s1", 1, "y", 1000, 1200), // 900ms gap
        ];
        let result = detect_chunk_boundaries_default(&t);
        assert_eq!(result.boundaries.len(), 1);
        assert!((result.boundaries[0].confidence - 1.0).abs() < f32::EPSILON);
    }

    // -- detect_chunk_boundaries_for_track ----------------------------------

    #[test]
    fn does_not_create_cross_sentence_boundaries() {
        let config = ChunkDetectionConfig::default();
        let data = vec![
            (
                SubtitleSentenceId::parse("s1").unwrap(),
                vec![
                    wt("s1", 0, "a", 0, 100),
                    wt("s1", 1, "b", 400, 600), // 300ms gap → boundary
                ],
            ),
            (
                SubtitleSentenceId::parse("s2").unwrap(),
                vec![
                    wt("s2", 0, "c", 0, 100),
                    wt("s2", 1, "d", 150, 300), // 50ms gap → no boundary
                ],
            ),
        ];
        let results = detect_chunk_boundaries_for_track(&data, &config);
        assert_eq!(results.len(), 2);

        let r1 = &results[&SubtitleSentenceId::parse("s1").unwrap()];
        assert_eq!(r1.boundaries.len(), 1);
        assert_eq!(r1.chunks.len(), 2);

        let r2 = &results[&SubtitleSentenceId::parse("s2").unwrap()];
        assert!(r2.boundaries.is_empty());
        assert_eq!(r2.chunks.len(), 1);
    }

    // -- gap_confidence ----------------------------------------------------

    #[test]
    fn confidence_below_threshold_is_zero() {
        assert_eq!(gap_confidence(100, 250), 0.0);
        assert_eq!(gap_confidence(249, 250), 0.0);
    }

    #[test]
    fn confidence_at_threshold_is_half() {
        assert!((gap_confidence(250, 250) - 0.5).abs() < f32::EPSILON);
    }

    #[test]
    fn confidence_saturates_at_one() {
        assert!((gap_confidence(750, 250) - 1.0).abs() < f32::EPSILON);
        assert!((gap_confidence(1000, 250) - 1.0).abs() < f32::EPSILON);
    }

    #[test]
    fn confidence_interpolates_until_threshold_plus_500() {
        assert!((gap_confidence(500, 250) - 0.75).abs() < f32::EPSILON);
    }
}
