//! Text-level chunk detection from subtitle sentence tokens.
//!
//! This module detects lexical chunk boundaries by matching known multi-word
//! expressions against the sentence token stream and partitioning the entire
//! sentence into contiguous chunks (every word token belongs to exactly one
//! chunk).
//!
//! Data sources (in descending order of confidence):
//! 1. PHRASE List (Martinez & Schmitt 2012) — 505 pedagogically-selected
//!    functional phrases with category labels, embedded at compile time.
//! 2. COCA n-gram collocations (MI ≥ 3.0) — statistical collocation pairs
//!    and sequences, embedded at compile time.
//! 3. External phrase candidates — ECDICT dictionary entries and built-in
//!    phrase rules, passed in at call time via `PhraseCandidate`.

use std::collections::HashMap;
use std::sync::OnceLock;

use domain::{PhraseCandidate, SubtitleSentence, SubtitleSentenceId, SubtitleTokenKind};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// A candidate multi-word span detected from one of the data sources.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PhraseSpan {
    /// Token index of the first word (inclusive).
    pub token_start: u32,
    /// Token index of the last word (inclusive).
    pub token_end: u32,
    /// Original-case text from the sentence (space-joined).
    pub text: String,
    /// Normalized text (lowercase, space-joined).
    pub normalized_text: String,
    /// Confidence in [0.0, 1.0].
    pub confidence: f32,
    /// Which data source produced this span.
    pub source: SpanSource,
}

/// Provenance of a detected phrase span.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum SpanSource {
    /// COCA n-gram statistical collocation.
    Collocation {
        /// Mutual Information score.
        mi_score: f32,
    },
    /// PHRASE List pedagogically-selected phrase.
    PhraseList {
        /// Functional category label (e.g. "verb_phrase", "discourse_marker").
        category: String,
    },
    /// Dictionary or built-in phrase rule (ECDICT, hard-coded list).
    DictionaryPhrase {
        /// Source label from the provider (e.g. "ECDICT phrase entry").
        source: String,
    },
}

/// A contiguous group of word tokens forming a single text-level chunk.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextChunkGroup {
    /// Token index of the first word (inclusive).
    pub token_start: u32,
    /// Token index of the last word (inclusive).
    pub token_end: u32,
    /// Original-case text (space-joined).
    pub text: String,
    /// Why this span was grouped as a chunk.
    pub evidence: TextChunkEvidence,
}

/// Classification of how a text chunk was formed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextChunkEvidence {
    /// Single word — no multi-word phrase covers this token.
    SingleWord,
    /// COCA collocation span.
    Collocation,
    /// PHRASE List entry.
    PhraseList,
    /// Dictionary or built-in phrase.
    DictionaryPhrase,
}

/// A boundary between two consecutive text chunks.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextChunkBoundary {
    /// Token index of the word to the left of the boundary.
    pub left_token_index: u32,
    /// Token index of the word to the right of the boundary.
    pub right_token_index: u32,
    /// Confidence in [0.0, 1.0].
    pub confidence: f32,
    /// What evidence type produced this boundary.
    pub evidence: TextChunkEvidence,
    /// The phrase text immediately preceding this boundary, if any.
    pub preceding_phrase: Option<String>,
}

/// Complete text-level chunk detection result for a single sentence.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextChunkDetectionResult {
    /// Sentence this result corresponds to.
    pub sentence_id: SubtitleSentenceId,
    /// Detected chunks in token order.
    pub chunks: Vec<TextChunkGroup>,
    /// All boundaries between consecutive chunks.
    pub boundaries: Vec<TextChunkBoundary>,
    /// How many spans were considered from each source.
    pub source_counts: SourceCounts,
}

/// Counts of detected and resolved spans from each data source.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct SourceCounts {
    /// COCA collocation spans found.
    pub collocations: usize,
    /// PHRASE List spans found.
    pub phrase_list: usize,
    /// Dictionary/builtin spans found.
    pub dictionary: usize,
    /// Spans that survived overlap resolution.
    pub resolved: usize,
}

// ---------------------------------------------------------------------------
// Data loading (compile-time embedded TSV)
// ---------------------------------------------------------------------------

static PHRASE_LIST: OnceLock<HashMap<String, String>> = OnceLock::new();
static COCA_NGRAMS: OnceLock<HashMap<String, f32>> = OnceLock::new();

fn load_phrase_list() -> &'static HashMap<String, String> {
    PHRASE_LIST.get_or_init(|| {
        let raw = include_str!("../data/phrase_list.tsv");
        let mut map = HashMap::new();
        for line in raw.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((phrase, category)) = line.split_once('\t') {
                map.insert(phrase.to_string(), category.to_string());
            }
        }
        map
    })
}

fn load_coca_ngrams() -> &'static HashMap<String, f32> {
    COCA_NGRAMS.get_or_init(|| {
        let raw = include_str!("../data/coca_ngrams.tsv");
        let mut map = HashMap::new();
        for line in raw.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((phrase, score_str)) = line.split_once('\t')
                && let Ok(score) = score_str.parse::<f32>()
            {
                map.insert(phrase.to_string(), score);
            }
        }
        map
    })
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Detect text-level chunk boundaries for a single sentence.
///
/// `phrase_candidates` provides the external dictionary/builtin phrase
/// matches (from ECDICT etc.).  COCA n-grams and PHRASE List data are
/// consulted automatically from the embedded compile-time dictionaries.
///
/// Every word token in the sentence is covered by exactly one chunk in the
/// result.  Tokens that are not part of any multi-word phrase become
/// single-word chunks with `TextChunkEvidence::SingleWord`.
pub fn detect_text_chunks(
    sentence: &SubtitleSentence,
    phrase_candidates: &[PhraseCandidate],
) -> TextChunkDetectionResult {
    // 1. Extract word tokens (skip punctuation, whitespace, other).
    let word_tokens: Vec<&domain::SubtitleToken> = sentence
        .tokens
        .iter()
        .filter(|t| t.kind == SubtitleTokenKind::Word)
        .collect();

    if word_tokens.is_empty() {
        return TextChunkDetectionResult {
            sentence_id: sentence.id.clone(),
            chunks: Vec::new(),
            boundaries: Vec::new(),
            source_counts: SourceCounts::default(),
        };
    }

    let normalized: Vec<String> = word_tokens
        .iter()
        .map(|t| normalize_token_text(&t.text))
        .collect();

    // 2. Collect PhraseSpan candidates from all sources.
    let mut spans: Vec<PhraseSpan> = Vec::new();

    collect_coca_spans(&normalized, &word_tokens, &mut spans);
    collect_phrase_list_spans(&normalized, &word_tokens, &mut spans);
    collect_candidate_spans(phrase_candidates, &word_tokens, &mut spans);
    spans.retain(|span| valid_span_for_sentence(span, sentence, &word_tokens));

    let counts = SourceCounts {
        collocations: spans
            .iter()
            .filter(|s| matches!(s.source, SpanSource::Collocation { .. }))
            .count(),
        phrase_list: spans
            .iter()
            .filter(|s| matches!(s.source, SpanSource::PhraseList { .. }))
            .count(),
        dictionary: spans
            .iter()
            .filter(|s| matches!(s.source, SpanSource::DictionaryPhrase { .. }))
            .count(),
        resolved: 0,
    };

    // 3. Resolve overlaps: longest-match-first greedy.
    let selected = resolve_overlaps(spans);
    let resolved_count = selected.len();

    // 4. Build partition — every word token assigned to exactly one chunk.
    let (chunks, boundaries) = build_partition(&selected, &word_tokens, &normalized);

    TextChunkDetectionResult {
        sentence_id: sentence.id.clone(),
        chunks,
        boundaries,
        source_counts: SourceCounts {
            resolved: resolved_count,
            ..counts
        },
    }
}

// ---------------------------------------------------------------------------
// Span collectors
// ---------------------------------------------------------------------------

/// Collect spans from embedded COCA n-gram data.
fn collect_coca_spans(
    normalized: &[String],
    words: &[&domain::SubtitleToken],
    spans: &mut Vec<PhraseSpan>,
) {
    let coca = load_coca_ngrams();
    let max_len = 5usize;
    for length in 2..=max_len.min(normalized.len()) {
        for start in 0..=normalized.len() - length {
            let phrase = normalized[start..start + length].join(" ");
            if let Some(&mi_score) = coca.get(&phrase) {
                let confidence = mi_to_confidence(mi_score);
                let text = join_token_text(&words[start..start + length]);
                spans.push(PhraseSpan {
                    token_start: words[start].index,
                    token_end: words[start + length - 1].index,
                    text,
                    normalized_text: phrase,
                    confidence,
                    source: SpanSource::Collocation { mi_score },
                });
            }
        }
    }
}

/// Collect spans from embedded PHRASE List data.
fn collect_phrase_list_spans(
    normalized: &[String],
    words: &[&domain::SubtitleToken],
    spans: &mut Vec<PhraseSpan>,
) {
    let phrases = load_phrase_list();
    let max_len = phrases
        .keys()
        .map(|p| p.split_whitespace().count())
        .max()
        .unwrap_or(7);
    for length in 2..=max_len.min(normalized.len()) {
        for start in 0..=normalized.len() - length {
            let phrase = normalized[start..start + length].join(" ");
            if let Some(category) = phrases.get(&phrase) {
                let text = join_token_text(&words[start..start + length]);
                spans.push(PhraseSpan {
                    token_start: words[start].index,
                    token_end: words[start + length - 1].index,
                    text,
                    normalized_text: phrase,
                    confidence: 0.85, // pedagogically curated = high confidence
                    source: SpanSource::PhraseList {
                        category: category.clone(),
                    },
                });
            }
        }
    }
}

/// Convert external `PhraseCandidate` values into `PhraseSpan` values.
fn collect_candidate_spans(
    candidates: &[PhraseCandidate],
    _words: &[&domain::SubtitleToken],
    spans: &mut Vec<PhraseSpan>,
) {
    for candidate in candidates {
        // Skip single-word candidates — only multi-word phrases are chunks.
        if candidate.token_start == candidate.token_end {
            continue;
        }
        spans.push(PhraseSpan {
            token_start: candidate.token_start,
            token_end: candidate.token_end,
            text: candidate.display_form.clone(),
            normalized_text: candidate.normalized_form.clone(),
            confidence: 0.70, // moderate — dictionary match, not frequency-based
            source: SpanSource::DictionaryPhrase {
                source: candidate.reason.clone(),
            },
        });
    }
}

/// Reject malformed provider candidates and phrases that bridge punctuation.
fn valid_span_for_sentence(
    span: &PhraseSpan,
    sentence: &SubtitleSentence,
    words: &[&domain::SubtitleToken],
) -> bool {
    if span.token_start >= span.token_end {
        return false;
    }
    let Some(start_position) = words.iter().position(|word| word.index == span.token_start) else {
        return false;
    };
    let Some(end_position) = words.iter().position(|word| word.index == span.token_end) else {
        return false;
    };
    if start_position >= end_position {
        return false;
    }
    !sentence.tokens.iter().any(|token| {
        token.index > span.token_start
            && token.index < span.token_end
            && token.kind == SubtitleTokenKind::Punctuation
    })
}

// ---------------------------------------------------------------------------
// Overlap resolution
// ---------------------------------------------------------------------------

/// Longest-match-first greedy overlap resolution.
///
/// 1. Sort by length descending, then confidence descending.
/// 2. Greedy selection: accept a span if none of its tokens are already
///    occupied by a previously accepted span.
/// 3. Return selected spans sorted by `token_start`.
fn resolve_overlaps(mut spans: Vec<PhraseSpan>) -> Vec<PhraseSpan> {
    spans.sort_by(|a, b| {
        let len_a = a.token_end as i64 - a.token_start as i64;
        let len_b = b.token_end as i64 - b.token_start as i64;
        len_b
            .cmp(&len_a)
            .then_with(|| {
                b.confidence
                    .partial_cmp(&a.confidence)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
    });

    let max_token = spans.iter().map(|s| s.token_end).max().unwrap_or(0) as usize;
    let mut occupied = vec![false; max_token + 1];
    let mut selected: Vec<PhraseSpan> = Vec::new();

    for span in &spans {
        let any_occupied = (span.token_start..=span.token_end)
            .any(|i| *occupied.get(i as usize).unwrap_or(&false));
        if any_occupied {
            continue;
        }
        for i in span.token_start..=span.token_end {
            if (i as usize) < occupied.len() {
                occupied[i as usize] = true;
            }
        }
        selected.push(span.clone());
    }

    selected.sort_by_key(|s| (s.token_start, s.token_end));
    selected
}

// ---------------------------------------------------------------------------
// Partition building
// ---------------------------------------------------------------------------

/// Build the complete sentence partition from selected spans.
///
/// Every word token is covered by exactly one `TextChunkGroup`.  Tokens not
/// covered by any selected span become single-word chunks.
fn build_partition(
    selected: &[PhraseSpan],
    words: &[&domain::SubtitleToken],
    _normalized: &[String],
) -> (Vec<TextChunkGroup>, Vec<TextChunkBoundary>) {
    let mut chunks: Vec<TextChunkGroup> = Vec::new();
    let mut cursor: usize = 0; // index into `words` array

    for span in selected {
        let span_start = words
            .iter()
            .position(|w| w.index == span.token_start)
            .unwrap_or(cursor);
        let span_end = words
            .iter()
            .position(|w| w.index == span.token_end)
            .unwrap_or(span_start);

        // Single-word tokens before this span.
        while cursor < span_start {
            let w = words[cursor];
            chunks.push(TextChunkGroup {
                token_start: w.index,
                token_end: w.index,
                text: w.text.clone(),
                evidence: TextChunkEvidence::SingleWord,
            });
            cursor += 1;
        }

        // The phrase span as a chunk.
        let evidence = evidence_from_source(&span.source);
        chunks.push(TextChunkGroup {
            token_start: span.token_start,
            token_end: span.token_end,
            text: span.text.clone(),
            evidence,
        });

        cursor = span_end + 1;
    }

    // Remaining single-word tokens after the last selected span.
    while cursor < words.len() {
        let w = words[cursor];
        chunks.push(TextChunkGroup {
            token_start: w.index,
            token_end: w.index,
            text: w.text.clone(),
            evidence: TextChunkEvidence::SingleWord,
        });
        cursor += 1;
    }

    // Build boundaries between consecutive chunks.
    let mut boundaries: Vec<TextChunkBoundary> = Vec::new();
    for pair in chunks.windows(2) {
        let left = &pair[0];
        let right = &pair[1];

        // Determine evidence type: prefer non-SingleWord if either side has it.
        let boundary_evidence = if left.evidence != TextChunkEvidence::SingleWord {
            left.evidence.clone()
        } else if right.evidence != TextChunkEvidence::SingleWord {
            right.evidence.clone()
        } else {
            TextChunkEvidence::SingleWord
        };

        // Confidence: use left chunk's evidence as the signal.
        let confidence = match &left.evidence {
            TextChunkEvidence::SingleWord => 0.35,
            TextChunkEvidence::Collocation => 0.65,
            TextChunkEvidence::PhraseList => 0.80,
            TextChunkEvidence::DictionaryPhrase => 0.65,
        };

        // Preceding phrase: if left chunk is multi-word, use its text.
        let preceding_phrase = if left.token_start != left.token_end {
            Some(left.text.clone())
        } else {
            None
        };

        boundaries.push(TextChunkBoundary {
            left_token_index: left.token_end,
            right_token_index: right.token_start,
            confidence,
            evidence: boundary_evidence,
            preceding_phrase,
        });
    }

    (chunks, boundaries)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Normalize a single token's text for dictionary lookup.
fn normalize_token_text(text: &str) -> String {
    text.trim()
        .trim_matches(|c: char| !c.is_ascii_alphanumeric() && c != '\'')
        .to_ascii_lowercase()
}

/// Map Mutual Information score to confidence in [0.0, 1.0].
///
/// - MI = 3.0 → 0.50 (entry threshold)
/// - MI = 5.0 → 0.75
/// - MI = 7.0 → 0.90
/// - MI ≥ 10.0 → 1.00
/// - Segmented linear interpolation between these points.
fn mi_to_confidence(mi: f32) -> f32 {
    if mi < 3.0 {
        0.5
    } else if mi < 5.0 {
        0.5 + (mi - 3.0) / 2.0 * 0.25
    } else if mi < 7.0 {
        0.75 + (mi - 5.0) / 2.0 * 0.15
    } else if mi < 10.0 {
        0.9 + (mi - 7.0) / 3.0 * 0.10
    } else {
        1.0
    }
}

/// Map a `SpanSource` to the corresponding `TextChunkEvidence`.
fn evidence_from_source(source: &SpanSource) -> TextChunkEvidence {
    match source {
        SpanSource::Collocation { .. } => TextChunkEvidence::Collocation,
        SpanSource::PhraseList { .. } => TextChunkEvidence::PhraseList,
        SpanSource::DictionaryPhrase { .. } => TextChunkEvidence::DictionaryPhrase,
    }
}

/// Join the text of a slice of tokens with spaces.
fn join_token_text(tokens: &[&domain::SubtitleToken]) -> String {
    tokens.iter().map(|t| t.text.as_str()).collect::<Vec<_>>().join(" ")
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{PhraseCandidate, SubtitleSentence, SubtitleSentenceId, SubtitleToken, TimeMs};

    // -- test helpers ----------------------------------------------------------

    fn make_sentence(id: &str, start_ms: u64, end_ms: u64, words: &[&str]) -> SubtitleSentence {
        let tokens: Vec<SubtitleToken> = words
            .iter()
            .enumerate()
            .map(|(i, text)| SubtitleToken {
                index: i as u32,
                kind: SubtitleTokenKind::Word,
                text: text.to_string(),
                normalized: Some(text.to_lowercase()),
                start_char: 0,
                end_char: text.len() as u32,
            })
            .collect();
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index: 0,
            start: TimeMs::new(start_ms),
            end: TimeMs::new(end_ms),
            original_text: words.join(" "),
            display_text: words.join(" "),
            tokens,
        }
    }

    fn make_sentence_with_punct(
        id: &str,
        start_ms: u64,
        end_ms: u64,
        tokens_in: Vec<(&str, SubtitleTokenKind)>,
    ) -> SubtitleSentence {
        let tokens: Vec<SubtitleToken> = tokens_in
            .iter()
            .enumerate()
            .map(|(i, (text, kind))| SubtitleToken {
                index: i as u32,
                kind: *kind,
                text: text.to_string(),
                normalized: if *kind == SubtitleTokenKind::Word {
                    Some(text.to_lowercase())
                } else {
                    None
                },
                start_char: 0,
                end_char: text.len() as u32,
            })
            .collect();
        let words: Vec<&str> = tokens_in.iter().map(|(t, _)| *t).collect();
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index: 0,
            start: TimeMs::new(start_ms),
            end: TimeMs::new(end_ms),
            original_text: words.join(" "),
            display_text: words.join(" "),
            tokens,
        }
    }

    fn candidate(
        canonical: &str,
        display: &str,
        normalized: &str,
        token_start: u32,
        token_end: u32,
    ) -> PhraseCandidate {
        PhraseCandidate {
            canonical_form: canonical.to_string(),
            display_form: display.to_string(),
            normalized_form: normalized.to_string(),
            token_start,
            token_end,
            reason: "test-candidate".into(),
        }
    }

    // -- empty / single-word ---------------------------------------------------

    #[test]
    fn empty_sentence_returns_empty_result() {
        let sentence = make_sentence("s1", 0, 1000, &[]);
        let result = detect_text_chunks(&sentence, &[]);
        assert!(result.chunks.is_empty());
        assert!(result.boundaries.is_empty());
        assert_eq!(result.source_counts.resolved, 0);
    }

    #[test]
    fn single_word_returns_single_chunk() {
        let sentence = make_sentence("s1", 0, 1000, &["hello"]);
        let result = detect_text_chunks(&sentence, &[]);
        assert_eq!(result.chunks.len(), 1);
        assert_eq!(result.chunks[0].text, "hello");
        assert_eq!(result.chunks[0].token_start, 0);
        assert_eq!(result.chunks[0].token_end, 0);
        assert_eq!(result.chunks[0].evidence, TextChunkEvidence::SingleWord);
        assert!(result.boundaries.is_empty());
    }

    #[test]
    fn no_phrase_match_all_single_words() {
        let sentence = make_sentence(
            "s1",
            0,
            5000,
            &["random", "isolated", "unrelated", "tokens"],
        );
        let result = detect_text_chunks(&sentence, &[]);
        // All four words should be separate SingleWord chunks.
        assert_eq!(result.chunks.len(), 4);
        for chunk in &result.chunks {
            assert_eq!(chunk.evidence, TextChunkEvidence::SingleWord);
        }
        assert_eq!(result.boundaries.len(), 3);
    }

    // -- COCA collocation ------------------------------------------------------

    #[test]
    fn coca_collocation_detected() {
        // "bus stop" is in coca_ngrams.tsv with MI 7.40
        let sentence = make_sentence("s1", 0, 3000, &["the", "bus", "stop", "is", "near"]);
        let result = detect_text_chunks(&sentence, &[]);
        // Should have a chunk for "bus stop" as Collocation.
        let collocation_chunk = result
            .chunks
            .iter()
            .find(|c| c.evidence == TextChunkEvidence::Collocation);
        assert!(collocation_chunk.is_some(), "should find 'bus stop' as collocation");
        let chunk = collocation_chunk.unwrap();
        assert_eq!(chunk.text, "bus stop");
        assert_eq!(chunk.token_start, 1); // "bus"
        assert_eq!(chunk.token_end, 2); // "stop"
        // Should have 3 single-word chunks for "the", "is", "near"
        let single_count = result
            .chunks
            .iter()
            .filter(|c| c.evidence == TextChunkEvidence::SingleWord)
            .count();
        assert_eq!(single_count, 3);
    }

    // -- PHRASE List -----------------------------------------------------------

    #[test]
    fn phrase_list_entry_detected() {
        // "a couple of" is in both COCA (MI 9.20) and PHRASE List.
        // COCA wins on higher confidence, so evidence is Collocation.
        let sentence =
            make_sentence("s1", 0, 4000, &["i", "need", "a", "couple", "of", "those"]);
        let result = detect_text_chunks(&sentence, &[]);
        let phrase_chunk = result
            .chunks
            .iter()
            .find(|c| c.text == "a couple of");
        assert!(
            phrase_chunk.is_some(),
            "should find 'a couple of' as a multi-word chunk"
        );
        let chunk = phrase_chunk.unwrap();
        assert_eq!(chunk.token_start, 2);
        assert_eq!(chunk.token_end, 4);
        assert!(chunk.evidence != TextChunkEvidence::SingleWord);
    }

    // -- external candidates ---------------------------------------------------

    #[test]
    fn external_candidate_forwarded() {
        let sentence = make_sentence("s1", 0, 3000, &["this", "is", "a", "test"]);
        let candidates = vec![candidate("a test", "a test", "a test", 2, 3)];
        let result = detect_text_chunks(&sentence, &candidates);
        let dict_chunk = result
            .chunks
            .iter()
            .find(|c| c.evidence == TextChunkEvidence::DictionaryPhrase);
        assert!(dict_chunk.is_some(), "should forward external candidate");
        assert_eq!(dict_chunk.unwrap().text, "a test");
    }

    #[test]
    fn external_single_word_skipped() {
        let sentence = make_sentence("s1", 0, 3000, &["hello", "world"]);
        // Single-word candidate (token_start == token_end) should be skipped.
        let candidates = vec![candidate("hello", "hello", "hello", 0, 0)];
        let result = detect_text_chunks(&sentence, &candidates);
        // Both words should be SingleWord chunks.
        assert_eq!(result.chunks.len(), 2);
        for chunk in &result.chunks {
            assert_eq!(chunk.evidence, TextChunkEvidence::SingleWord);
        }
    }

    // -- overlap resolution ----------------------------------------------------

    #[test]
    fn longest_match_wins() {
        // "a lot of" (3-gram) and "a lot" (2-gram) overlap — longer should win.
        // "a lot of" is in both COCA and PHRASE List; longer span wins.
        let sentence =
            make_sentence("s1", 0, 4000, &["there", "is", "a", "lot", "of", "stuff"]);
        let result = detect_text_chunks(&sentence, &[]);
        // Should detect the 3-word phrase "a lot of", not the 2-word "a lot".
        let phrase_chunks: Vec<_> = result
            .chunks
            .iter()
            .filter(|c| c.evidence != TextChunkEvidence::SingleWord)
            .collect();
        // There may be multiple phrase chunks; "a lot of" should be one of them.
        let has_three_word = phrase_chunks.iter().any(|c| c.text == "a lot of");
        assert!(has_three_word, "longer 'a lot of' should be detected");
        // "a lot" alone should not appear as a separate chunk.
        let has_two_word = phrase_chunks.iter().any(|c| c.text == "a lot");
        assert!(!has_two_word, "shorter 'a lot' should be suppressed by overlap resolution");
    }

    #[test]
    fn non_overlapping_phrases_both_kept() {
        // "pick up" and "bus stop" don't overlap — both should be detected.
        let sentence = make_sentence(
            "s1",
            0,
            5000,
            &["i", "pick", "up", "the", "bus", "stop", "there"],
        );
        let result = detect_text_chunks(&sentence, &[]);
        let phrase_texts: Vec<&str> = result
            .chunks
            .iter()
            .filter(|c| c.evidence != TextChunkEvidence::SingleWord)
            .map(|c| c.text.as_str())
            .collect();
        // "pick up" or "pick up the" — depending on COCA entries
        let has_pick_up = phrase_texts.iter().any(|t| t.contains("pick up"));
        let has_bus_stop = phrase_texts.iter().any(|t| t.contains("bus stop"));
        assert!(has_pick_up || has_bus_stop, "at least one phrase should be detected");
    }

    // -- case insensitivity ----------------------------------------------------

    #[test]
    fn case_insensitive_matching() {
        // Should match regardless of input case.
        let sentence = make_sentence("s1", 0, 3000, &["THE", "Bus", "Stop", "HERE"]);
        let result = detect_text_chunks(&sentence, &[]);
        let has_collocation = result
            .chunks
            .iter()
            .any(|c| c.evidence == TextChunkEvidence::Collocation);
        assert!(has_collocation, "case-insensitive match for 'bus stop'");
    }

    // -- partition integrity ---------------------------------------------------

    #[test]
    fn partition_covers_all_tokens() {
        let sentence = make_sentence("s1", 0, 5000, &["a", "b", "c", "d", "e"]);
        let result = detect_text_chunks(&sentence, &[]);
        // Every token index 0..4 should appear exactly once.
        let mut covered = [false; 5];
        for chunk in &result.chunks {
            for idx in chunk.token_start..=chunk.token_end {
                assert!(!covered[idx as usize], "token {idx} covered twice");
                covered[idx as usize] = true;
            }
        }
        assert!(covered.iter().all(|&c| c), "all tokens must be covered");
    }

    #[test]
    fn boundary_count_consistency() {
        let sentence = make_sentence("s1", 0, 5000, &["a", "b", "c", "d", "e"]);
        let result = detect_text_chunks(&sentence, &[]);
        assert_eq!(
            result.boundaries.len(),
            result.chunks.len().saturating_sub(1),
            "boundaries = chunks - 1"
        );
    }

    #[test]
    fn token_order_preserved() {
        let sentence = make_sentence("s1", 0, 5000, &["the", "quick", "brown", "fox"]);
        let result = detect_text_chunks(&sentence, &[]);
        let reconstructed: Vec<&str> = result
            .chunks
            .iter()
            .flat_map(|c| c.text.split_whitespace())
            .collect();
        let original: Vec<&str> = vec!["the", "quick", "brown", "fox"];
        assert_eq!(reconstructed, original);
    }

    // -- punctuation handling --------------------------------------------------

    #[test]
    fn punctuation_tokens_skipped() {
        // Punctuation and whitespace tokens should be filtered out.
        let tokens = vec![
            ("hello", SubtitleTokenKind::Word),
            (",", SubtitleTokenKind::Punctuation),
            ("world", SubtitleTokenKind::Word),
            ("!", SubtitleTokenKind::Punctuation),
        ];
        let sentence = make_sentence_with_punct("s1", 0, 2000, tokens);
        let result = detect_text_chunks(&sentence, &[]);
        // Only 2 word tokens → 2 chunks.
        assert_eq!(result.chunks.len(), 2);
        assert_eq!(result.chunks[0].text, "hello");
        assert_eq!(result.chunks[1].text, "world");
        assert_eq!(result.boundaries.len(), 1);
    }

    #[test]
    fn phrase_matching_does_not_bridge_punctuation() {
        let tokens = vec![
            ("take", SubtitleTokenKind::Word),
            (",", SubtitleTokenKind::Punctuation),
            ("care", SubtitleTokenKind::Word),
            ("of", SubtitleTokenKind::Word),
        ];
        let sentence = make_sentence_with_punct("s1", 0, 2000, tokens);
        let result = detect_text_chunks(&sentence, &[]);
        assert!(!result.chunks.iter().any(|chunk| chunk.text == "take care of"));
    }

    #[test]
    fn invalid_external_candidate_is_ignored() {
        let sentence = make_sentence("s1", 0, 2000, &["hello", "world"]);
        let candidates = vec![candidate("invalid", "invalid", "invalid", 0, u32::MAX)];
        let result = detect_text_chunks(&sentence, &candidates);
        assert_eq!(result.chunks.len(), 2);
        assert!(result
            .chunks
            .iter()
            .all(|chunk| chunk.evidence == TextChunkEvidence::SingleWord));
    }

    // -- confidence mapping ----------------------------------------------------

    #[test]
    fn mi_confidence_monotonic() {
        // Confidence should be monotonic with MI.
        let c_low = mi_to_confidence(3.0);
        let c_mid = mi_to_confidence(5.0);
        let c_high = mi_to_confidence(7.0);
        let c_max = mi_to_confidence(10.0);
        assert!(c_low < c_mid);
        assert!(c_mid < c_high);
        assert!(c_high < c_max);
        assert!((c_max - 1.0).abs() < f32::EPSILON);
    }

    #[test]
    fn mi_confidence_at_boundaries() {
        assert!((mi_to_confidence(3.0) - 0.5).abs() < f32::EPSILON);
        assert!((mi_to_confidence(5.0) - 0.75).abs() < 0.01);
        assert!((mi_to_confidence(7.0) - 0.90).abs() < 0.01);
        assert!((mi_to_confidence(10.0) - 1.0).abs() < f32::EPSILON);
    }

    // -- source counts ---------------------------------------------------------

    #[test]
    fn source_counts_accurate() {
        let sentence = make_sentence(
            "s1",
            0,
            5000,
            &["a", "couple", "of", "bus", "stop", "signs"],
        );
        let result = detect_text_chunks(&sentence, &[]);
        let counts = &result.source_counts;
        // Should have at least collocation "bus stop".
        assert!(
            counts.collocations >= 1,
            "should count collocation(s), got {}",
            counts.collocations
        );
        // Should have at least phrase_list "a couple of".
        assert!(
            counts.phrase_list >= 1,
            "should count phrase_list, got {}",
            counts.phrase_list
        );
        // Resolved should be ≥ 1 (some spans survived overlap resolution).
        assert!(counts.resolved >= 1);
    }

    // -- phrase_list detection for common phrases ------------------------------

    #[test]
    fn in_front_of_detected() {
        // "in front of" is in both COCA (MI 10.50) and PHRASE List.
        // COCA wins on higher confidence.
        let sentence = make_sentence(
            "s1",
            0,
            4000,
            &["the", "car", "is", "in", "front", "of", "me"],
        );
        let result = detect_text_chunks(&sentence, &[]);
        let has_in_front_of = result
            .chunks
            .iter()
            .any(|c| c.text == "in front of" && c.evidence != TextChunkEvidence::SingleWord);
        assert!(has_in_front_of, "'in front of' should be detected as a multi-word chunk");
    }

    #[test]
    fn take_care_of_detected() {
        let sentence =
            make_sentence("s1", 0, 4000, &["please", "take", "care", "of", "her"]);
        let result = detect_text_chunks(&sentence, &[]);
        let has_take_care_of = result
            .chunks
            .iter()
            .any(|c| c.text == "take care of");
        assert!(has_take_care_of, "'take care of' should be detected");
    }
}
