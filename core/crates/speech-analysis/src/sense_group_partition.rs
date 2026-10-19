use std::collections::HashSet;

use domain::{
    PhraseCandidate, SenseGroupSource, SubtitleSentence, SubtitleTokenKind,
    SyntacticSentenceAnalysis,
};
use serde::{Deserialize, Serialize};

pub const PROVIDER_ID: &str = "rule-based-sense-group";
pub const PROVIDER_VERSION: &str = "v1";
pub const ALGORITHM: &str = "punctuation_length_rule_v1";
pub const SYNTAX_PROVIDER_ID: &str = "syntax-aware-sense-group";
pub const SYNTAX_PROVIDER_VERSION: &str = "v1";
pub const SYNTAX_ALGORITHM: &str = "dependency_teaching_partition_v1";

pub struct SenseGroupPartitionConfig {
    pub min_words: usize,
    pub soft_max_words: usize,
    pub hard_max_words: usize,
    pub target_groups_per_sentence: usize,
}

impl Default for SenseGroupPartitionConfig {
    fn default() -> Self {
        Self {
            min_words: 2,
            soft_max_words: 5,
            hard_max_words: 8,
            target_groups_per_sentence: 4,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SenseGroupSpan {
    pub start_token_index: u32,
    pub end_token_index: u32,
    pub sources: Vec<SenseGroupSource>,
    pub confidence: f32,
    pub label: Option<String>,
    pub head_token_index: Option<u32>,
}

pub fn partition_sentence(
    sentence: &SubtitleSentence,
    phrase_candidates: &[PhraseCandidate],
    config: &SenseGroupPartitionConfig,
) -> Vec<SenseGroupSpan> {
    partition_sentence_internal(sentence, phrase_candidates, config, &HashSet::new())
}

pub fn partition_sentence_with_syntax(
    sentence: &SubtitleSentence,
    phrase_candidates: &[PhraseCandidate],
    config: &SenseGroupPartitionConfig,
    syntax: &SyntacticSentenceAnalysis,
) -> Vec<SenseGroupSpan> {
    if syntax.sentence_id != sentence.id
        || syntax.source_text != sentence.display_text
        || syntax.source_char_count != sentence.display_text.chars().count() as u32
        || syntax.lexical_alignment_coverage < domain::DEFAULT_MIN_LEXICAL_ALIGNMENT_COVERAGE
    {
        return partition_sentence(sentence, phrase_candidates, config);
    }
    let boundaries = syntactic_boundary_candidates(sentence, syntax);
    let mut spans = partition_sentence_internal(sentence, phrase_candidates, config, &boundaries);
    for span in &mut spans {
        if let Some((label, head_token_index)) = syntactic_span_shape(syntax, span) {
            span.label = label;
            span.head_token_index = head_token_index;
            if !span.sources.contains(&SenseGroupSource::DependencyParse) {
                span.sources.push(SenseGroupSource::DependencyParse);
            }
            span.confidence = span.confidence.max(0.72);
        }
    }
    spans
}

fn partition_sentence_internal(
    sentence: &SubtitleSentence,
    phrase_candidates: &[PhraseCandidate],
    config: &SenseGroupPartitionConfig,
    syntax_boundaries: &HashSet<usize>,
) -> Vec<SenseGroupSpan> {
    let words: Vec<&domain::SubtitleToken> = sentence
        .tokens
        .iter()
        .filter(|t| t.kind == SubtitleTokenKind::Word)
        .collect();

    if words.is_empty() {
        return Vec::new();
    }

    if words.len() < config.min_words * 2 {
        return vec![SenseGroupSpan {
            start_token_index: words.first().unwrap().index,
            end_token_index: words.last().unwrap().index,
            sources: vec![SenseGroupSource::Rule],
            confidence: 0.5,
            label: None,
            head_token_index: None,
        }];
    }

    let mut boundaries: Vec<(usize, Vec<SenseGroupSource>)> = Vec::new();

    let mut word_count_in_group = 0usize;

    for (word_pos, word) in words.iter().enumerate() {
        word_count_in_group += 1;

        if word_pos == words.len() - 1 {
            break;
        }

        let next_word = words[word_pos + 1];
        let punct_between = punctuation_between_tokens(sentence, word.index, next_word.index);

        let in_phrase = phrase_candidates
            .iter()
            .any(|pc| pc.token_start <= word.index && pc.token_end >= next_word.index);

        if word_count_in_group >= config.hard_max_words && !in_phrase {
            boundaries.push((word_pos, vec![SenseGroupSource::LengthLimit]));
            word_count_in_group = 0;
            continue;
        }

        if let Some((_, strong)) = &punct_between
            && *strong
        {
            boundaries.push((word_pos, vec![SenseGroupSource::Punctuation]));
            word_count_in_group = 0;
            continue;
        }

        if let Some((_, false)) = &punct_between
            && word_count_in_group >= config.min_words
        {
            boundaries.push((word_pos, vec![SenseGroupSource::Punctuation]));
            word_count_in_group = 0;
            continue;
        }

        let remaining_words = words.len() - word_pos - 1;
        if syntax_boundaries.contains(&word_pos)
            && !in_phrase
            && word_count_in_group >= config.min_words
            && remaining_words >= config.min_words
            && boundaries.len() + 1 < config.target_groups_per_sentence
        {
            boundaries.push((word_pos, vec![SenseGroupSource::DependencyParse]));
            word_count_in_group = 0;
            continue;
        }

        if word_count_in_group >= config.soft_max_words && punct_between.is_some() {
            boundaries.push((word_pos, vec![SenseGroupSource::Punctuation]));
            word_count_in_group = 0;
            continue;
        }

        if word_count_in_group >= config.hard_max_words {
            boundaries.push((word_pos, vec![SenseGroupSource::LengthLimit]));
            word_count_in_group = 0;
            continue;
        }
    }

    let mut spans = Vec::new();
    let mut start_word_pos = 0usize;
    for (boundary_word_pos, sources) in &boundaries {
        let span_start = words[start_word_pos].index;
        let span_end = words[*boundary_word_pos].index;
        let mut span_sources = sources.clone();
        if phrase_candidates
            .iter()
            .any(|pc| pc.token_start >= span_start && pc.token_end <= span_end)
            && !span_sources.contains(&SenseGroupSource::Rule)
        {
            span_sources.push(SenseGroupSource::Rule);
        }
        let confidence = if span_sources.contains(&SenseGroupSource::DependencyParse) {
            0.72
        } else {
            0.5
        };
        spans.push(SenseGroupSpan {
            start_token_index: span_start,
            end_token_index: span_end,
            sources: span_sources,
            confidence,
            label: None,
            head_token_index: None,
        });
        start_word_pos = boundary_word_pos + 1;
    }

    if start_word_pos < words.len() {
        let span_start = words[start_word_pos].index;
        let span_end = words[words.len() - 1].index;
        let mut sources = vec![SenseGroupSource::Rule];
        if phrase_candidates
            .iter()
            .any(|pc| pc.token_start >= span_start && pc.token_end <= span_end)
        {
            sources = vec![SenseGroupSource::Rule];
        }
        spans.push(SenseGroupSpan {
            start_token_index: span_start,
            end_token_index: span_end,
            sources,
            confidence: 0.5,
            label: None,
            head_token_index: None,
        });
    }

    spans
}

fn syntactic_boundary_candidates(
    sentence: &SubtitleSentence,
    syntax: &SyntacticSentenceAnalysis,
) -> HashSet<usize> {
    let word_indices = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .map(|token| token.index)
        .collect::<Vec<_>>();
    let mut boundaries = HashSet::new();
    for token in &syntax.tokens {
        let relation = token.dependency_relation.as_str();
        let starts_unit = matches!(relation, "advcl" | "ccomp" | "parataxis" | "acl:relcl")
            || relation == "conj"
            || relation.starts_with("conj:");
        let mark_starts_clause = relation == "mark"
            && token
                .head_parser_token_index
                .and_then(|head| syntax.tokens.get(head as usize))
                .is_some_and(|head| matches!(head.dependency_relation.as_str(), "advcl" | "ccomp"));
        let case_starts_pp = relation == "case"
            && token
                .head_parser_token_index
                .and_then(|head| syntax.tokens.get(head as usize))
                .is_some_and(|head| {
                    head.dependency_relation == "obl"
                        || head.dependency_relation.starts_with("obl:")
                        || head.dependency_relation == "nmod"
                        || head.dependency_relation.starts_with("nmod:")
                });
        if !starts_unit && !mark_starts_clause && !case_starts_pp {
            continue;
        }
        let Some(first_word_index) = token
            .subtitle_token_indices
            .iter()
            .filter_map(|index| word_indices.iter().position(|word| word == index))
            .min()
        else {
            continue;
        };
        if first_word_index > 0 {
            boundaries.insert(first_word_index - 1);
        }
    }
    boundaries
}

#[cfg(test)]
mod syntax_tests;

fn syntactic_span_shape(
    syntax: &SyntacticSentenceAnalysis,
    span: &SenseGroupSpan,
) -> Option<(Option<String>, Option<u32>)> {
    let inside = syntax
        .tokens
        .iter()
        .filter(|token| {
            token
                .subtitle_token_indices
                .iter()
                .any(|index| *index >= span.start_token_index && *index <= span.end_token_index)
        })
        .collect::<Vec<_>>();
    let head = inside.iter().copied().find(|token| {
        token.head_parser_token_index.is_none()
            || token.head_parser_token_index.is_some_and(|head| {
                !inside
                    .iter()
                    .any(|candidate| candidate.parser_token_index == head)
            })
    })?;
    let starts_with_case = inside
        .first()
        .is_some_and(|token| token.dependency_relation == "case" || token.upos == "ADP");
    let label = if starts_with_case
        || head.dependency_relation == "obl"
        || head.dependency_relation.starts_with("obl:")
    {
        Some("PP".into())
    } else if matches!(head.upos.as_str(), "VERB" | "AUX") {
        Some("clause".into())
    } else if matches!(head.upos.as_str(), "NOUN" | "PROPN" | "PRON") {
        Some("NP".into())
    } else {
        None
    };
    let head_token_index = head
        .subtitle_token_indices
        .iter()
        .copied()
        .find(|index| *index >= span.start_token_index && *index <= span.end_token_index);
    Some((label, head_token_index))
}

fn punctuation_between_tokens(
    sentence: &SubtitleSentence,
    left_token_index: u32,
    right_token_index: u32,
) -> Option<(String, bool)> {
    let punct_text: String = sentence
        .tokens
        .iter()
        .filter(|t| {
            t.index > left_token_index
                && t.index < right_token_index
                && t.kind == SubtitleTokenKind::Punctuation
        })
        .map(|t| t.text.as_str())
        .collect();

    if punct_text.is_empty() {
        return None;
    }

    let strong = punct_text.chars().any(|c| {
        matches!(
            c,
            '.' | '!'
                | '?'
                | ';'
                | ':'
                | '\u{3002}'
                | '\u{FF1F}'
                | '\u{FF01}'
                | '\u{FF1B}'
                | '\u{FF1A}'
        )
    });
    Some((punct_text, strong))
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{SubtitleSentenceId, SubtitleToken, TimeMs};

    fn make_sentence_with_tokens(
        id: &str,
        tokens_in: Vec<(&str, SubtitleTokenKind)>,
    ) -> SubtitleSentence {
        let mut char_offset = 0u32;
        let tokens: Vec<SubtitleToken> = tokens_in
            .iter()
            .enumerate()
            .map(|(i, (text, kind))| {
                let start = char_offset;
                let len = text.chars().count() as u32;
                char_offset = start + len;
                SubtitleToken {
                    index: i as u32,
                    kind: *kind,
                    text: text.to_string(),
                    normalized: if *kind == SubtitleTokenKind::Word {
                        Some(text.to_lowercase())
                    } else {
                        None
                    },
                    start_char: start,
                    end_char: start + len,
                }
            })
            .collect();
        let full_text: String = tokens_in
            .iter()
            .map(|(t, _)| *t)
            .collect::<Vec<_>>()
            .join("");
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(10_000),
            original_text: full_text.clone(),
            display_text: full_text,
            tokens,
        }
    }

    fn en_sentence(id: &str, text: &str) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(10_000),
            original_text: text.into(),
            display_text: text.into(),
            tokens: subtitle_core::tokenize_english(text),
        }
    }

    fn zh_sentence(id: &str, text: &str) -> SubtitleSentence {
        let lang = domain::LanguageCode::parse("zh").unwrap();
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(10_000),
            original_text: text.into(),
            display_text: text.into(),
            tokens: subtitle_core::tokenize(Some(&lang), text),
        }
    }

    fn word_count(sentence: &SubtitleSentence, span: &SenseGroupSpan) -> usize {
        sentence
            .tokens
            .iter()
            .filter(|t| {
                t.kind == SubtitleTokenKind::Word
                    && t.index >= span.start_token_index
                    && t.index <= span.end_token_index
            })
            .count()
    }

    fn assert_invariants(sentence: &SubtitleSentence, spans: &[SenseGroupSpan]) {
        if spans.is_empty() {
            let word_count = sentence
                .tokens
                .iter()
                .filter(|t| t.kind == SubtitleTokenKind::Word)
                .count();
            assert_eq!(word_count, 0, "non-empty sentence produced no spans");
            return;
        }

        for span in spans {
            let wc = word_count(sentence, span);
            assert!(wc >= 1, "span must contain at least 1 word token");
        }

        for pair in spans.windows(2) {
            assert!(
                pair[0].end_token_index < pair[1].start_token_index,
                "spans must not overlap: [{}, {}] vs [{}, {}]",
                pair[0].start_token_index,
                pair[0].end_token_index,
                pair[1].start_token_index,
                pair[1].end_token_index,
            );
        }

        let all_words: Vec<u32> = sentence
            .tokens
            .iter()
            .filter(|t| t.kind == SubtitleTokenKind::Word)
            .map(|t| t.index)
            .collect();
        let mut covered = Vec::new();
        for span in spans {
            for &w in &all_words {
                if w >= span.start_token_index && w <= span.end_token_index {
                    covered.push(w);
                }
            }
        }
        assert_eq!(
            covered.len(),
            all_words.len(),
            "spans must cover all word tokens: covered {:?}, all {:?}",
            covered,
            all_words,
        );
    }

    // ── English tests ──────────────────────────────────────────────

    #[test]
    fn en_short_sentence_single_group() {
        let s = en_sentence("en1", "I see.");
        let spans = partition_sentence(&s, &[], &SenseGroupPartitionConfig::default());
        assert_eq!(spans.len(), 1);
        assert_invariants(&s, &spans);
    }

    #[test]
    fn en_comma_splits_when_enough_words() {
        let s = en_sentence("en2", "After the long meeting, we went home together.");
        let config = SenseGroupPartitionConfig::default();
        let spans = partition_sentence(&s, &[], &config);
        assert!(
            spans.len() >= 2,
            "comma should split: got {} groups",
            spans.len()
        );
        assert_invariants(&s, &spans);
    }

    #[test]
    fn en_long_no_punctuation_triggers_length_limit() {
        let s = en_sentence(
            "en3",
            "the quick brown fox jumped over the incredibly lazy dog sleeping peacefully",
        );
        let config = SenseGroupPartitionConfig::default();
        let spans = partition_sentence(&s, &[], &config);
        assert!(spans.len() >= 2, "long sentence without punct should split");
        for span in &spans {
            let wc = word_count(&s, span);
            assert!(
                wc <= config.hard_max_words,
                "span word count {} exceeds hard max {}",
                wc,
                config.hard_max_words,
            );
        }
        assert_invariants(&s, &spans);
    }

    #[test]
    fn en_parenthetical_with_commas() {
        let s = en_sentence(
            "en4",
            "The teacher, who was very strict, assigned extra homework today.",
        );
        let config = SenseGroupPartitionConfig::default();
        let spans = partition_sentence(&s, &[], &config);
        assert!(
            spans.len() >= 2,
            "parenthetical commas should produce multiple groups",
        );
        assert_invariants(&s, &spans);
    }

    #[test]
    fn en_strong_punctuation_forces_split() {
        let s = en_sentence("en5", "Stop! Don't go there; it is too dangerous.");
        let config = SenseGroupPartitionConfig::default();
        let spans = partition_sentence(&s, &[], &config);
        assert!(
            spans.len() >= 2,
            "exclamation and semicolon should force boundaries",
        );
        assert_invariants(&s, &spans);
    }

    #[test]
    fn en_phrase_candidate_protection() {
        let s = en_sentence("en6", "We should take care of the problem quickly.");
        let words: Vec<&SubtitleToken> = s
            .tokens
            .iter()
            .filter(|t| t.kind == SubtitleTokenKind::Word)
            .collect();
        let take_idx = words.iter().find(|w| w.text == "take").unwrap().index;
        let of_idx = words.iter().find(|w| w.text == "of").unwrap().index;
        let phrase = PhraseCandidate {
            canonical_form: "take care of".into(),
            display_form: "take care of".into(),
            normalized_form: "take care of".into(),
            token_start: take_idx,
            token_end: of_idx,
            reason: "test".into(),
        };
        let config = SenseGroupPartitionConfig::default();
        let spans = partition_sentence(&s, &[phrase], &config);
        for span in &spans {
            let contains_take =
                take_idx >= span.start_token_index && take_idx <= span.end_token_index;
            let contains_of = of_idx >= span.start_token_index && of_idx <= span.end_token_index;
            if contains_take || contains_of {
                assert!(
                    contains_take && contains_of,
                    "phrase 'take care of' must not be split across groups",
                );
            }
        }
        assert_invariants(&s, &spans);
    }

    #[test]
    fn en_sentence_with_mid_punctuation_includes_punct_tokens() {
        let s = en_sentence("en7", "Well, I think we should go home now.");
        let config = SenseGroupPartitionConfig::default();
        let spans = partition_sentence(&s, &[], &config);
        assert_invariants(&s, &spans);
        let comma_token = s.tokens.iter().find(|t| t.text == ",").unwrap();
        let any_span_covers = spans.iter().any(|span| {
            comma_token.index >= span.start_token_index && comma_token.index <= span.end_token_index
        });
        assert!(
            any_span_covers,
            "a mid-sentence punctuation token is absorbed into a sense group span"
        );
    }

    // ── Chinese tests ──────────────────────────────────────────────

    #[test]
    fn zh_normal_sentence() {
        let s = zh_sentence("zh1", "今天天气很好，我们一起去公园散步吧。");
        let config = SenseGroupPartitionConfig::default();
        let spans = partition_sentence(&s, &[], &config);
        assert!(!spans.is_empty());
        assert_invariants(&s, &spans);
    }

    #[test]
    fn zh_with_pause_mark() {
        let s = zh_sentence("zh2", "苹果、香蕉、橘子和葡萄都是水果。");
        let config = SenseGroupPartitionConfig::default();
        let spans = partition_sentence(&s, &[], &config);
        assert!(!spans.is_empty());
        assert_invariants(&s, &spans);
    }

    #[test]
    fn zh_long_sentence() {
        let s = zh_sentence(
            "zh3",
            "虽然这个任务看起来非常困难但是只要我们团结一致共同努力就一定能够完成。",
        );
        let config = SenseGroupPartitionConfig::default();
        let spans = partition_sentence(&s, &[], &config);
        assert!(!spans.is_empty());
        for span in &spans {
            let wc = word_count(&s, span);
            assert!(
                wc <= config.hard_max_words,
                "Chinese span word count {} exceeds hard max {}",
                wc,
                config.hard_max_words,
            );
        }
        assert_invariants(&s, &spans);
    }

    // ── Edge cases ─────────────────────────────────────────────────

    #[test]
    fn empty_sentence_returns_empty() {
        let s = make_sentence_with_tokens("empty", vec![]);
        let spans = partition_sentence(&s, &[], &SenseGroupPartitionConfig::default());
        assert!(spans.is_empty());
    }

    #[test]
    fn single_word_returns_single_group() {
        let s = en_sentence("single", "Hello");
        let spans = partition_sentence(&s, &[], &SenseGroupPartitionConfig::default());
        assert_eq!(spans.len(), 1);
        assert_invariants(&s, &spans);
    }

    #[test]
    fn all_confidence_values_are_half() {
        let s = en_sentence("conf", "The quick brown fox, jumping over the lazy dog.");
        let spans = partition_sentence(&s, &[], &SenseGroupPartitionConfig::default());
        for span in &spans {
            assert!(
                (span.confidence - 0.5).abs() < f32::EPSILON,
                "rule-based confidence must be 0.5, got {}",
                span.confidence,
            );
        }
    }

    #[test]
    fn token_indices_are_in_original_space() {
        let s = en_sentence("idx", "Hello, world! How are you?");
        let spans = partition_sentence(&s, &[], &SenseGroupPartitionConfig::default());
        let all_token_indices: Vec<u32> = s.tokens.iter().map(|t| t.index).collect();
        for span in &spans {
            assert!(
                all_token_indices.contains(&span.start_token_index),
                "start_token_index {} not in original token space",
                span.start_token_index,
            );
            assert!(
                all_token_indices.contains(&span.end_token_index),
                "end_token_index {} not in original token space",
                span.end_token_index,
            );
        }
        assert_invariants(&s, &spans);
    }
}
