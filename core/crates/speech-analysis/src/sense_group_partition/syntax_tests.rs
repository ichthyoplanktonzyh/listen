use std::collections::BTreeMap;

use domain::{
    PhraseCandidate, SenseGroupSource, SubtitleSentence, SubtitleSentenceId, SubtitleTokenKind,
    SyntacticAlignmentStatus, SyntacticSentenceAnalysis, SyntacticToken, TimeMs,
};

use super::{SenseGroupPartitionConfig, partition_sentence, partition_sentence_with_syntax};

#[derive(Clone, Copy)]
struct Annotation {
    lemma: &'static str,
    upos: &'static str,
    head: Option<usize>,
    relation: &'static str,
}

fn sentence(id: &str, text: &str) -> SubtitleSentence {
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

fn syntax(source: &SubtitleSentence, annotations: &[Annotation]) -> SyntacticSentenceAnalysis {
    let words = source
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    assert_eq!(words.len(), annotations.len());
    let tokens = words
        .iter()
        .zip(annotations)
        .enumerate()
        .map(|(index, (word, annotation))| SyntacticToken {
            parser_token_index: index as u32,
            surface: word.text.clone(),
            lemma: annotation.lemma.into(),
            upos: annotation.upos.into(),
            xpos: None,
            features: BTreeMap::new(),
            head_parser_token_index: annotation.head.map(|head| head as u32),
            dependency_relation: annotation.relation.into(),
            start_char: word.start_char,
            end_char: word.end_char,
            subtitle_token_indices: vec![word.index],
            alignment_status: SyntacticAlignmentStatus::Exact,
            confidence: None,
        })
        .collect();
    SyntacticSentenceAnalysis {
        sentence_id: source.id.clone(),
        source_text: source.display_text.clone(),
        source_char_count: source.display_text.chars().count() as u32,
        tokens,
        unaligned_subtitle_token_indices: Vec::new(),
        lexical_alignment_coverage: 1.0,
    }
}

fn word_count(source: &SubtitleSentence, start: u32, end: u32) -> usize {
    source
        .tokens
        .iter()
        .filter(|token| {
            token.kind == SubtitleTokenKind::Word && token.index >= start && token.index <= end
        })
        .count()
}

#[test]
fn clause_pp_and_subordinator_candidates_produce_teaching_granularity() {
    let source = sentence(
        "syntax-groups",
        "The long meeting ended we walked through the quiet park because rain was coming",
    );
    let parsed = syntax(
        &source,
        &[
            Annotation {
                lemma: "the",
                upos: "DET",
                head: Some(2),
                relation: "det",
            },
            Annotation {
                lemma: "long",
                upos: "ADJ",
                head: Some(2),
                relation: "amod",
            },
            Annotation {
                lemma: "meeting",
                upos: "NOUN",
                head: Some(3),
                relation: "nsubj",
            },
            Annotation {
                lemma: "end",
                upos: "VERB",
                head: Some(5),
                relation: "advcl",
            },
            Annotation {
                lemma: "we",
                upos: "PRON",
                head: Some(5),
                relation: "nsubj",
            },
            Annotation {
                lemma: "walk",
                upos: "VERB",
                head: None,
                relation: "root",
            },
            Annotation {
                lemma: "through",
                upos: "ADP",
                head: Some(9),
                relation: "case",
            },
            Annotation {
                lemma: "the",
                upos: "DET",
                head: Some(9),
                relation: "det",
            },
            Annotation {
                lemma: "quiet",
                upos: "ADJ",
                head: Some(9),
                relation: "amod",
            },
            Annotation {
                lemma: "park",
                upos: "NOUN",
                head: Some(5),
                relation: "obl",
            },
            Annotation {
                lemma: "because",
                upos: "SCONJ",
                head: Some(13),
                relation: "mark",
            },
            Annotation {
                lemma: "rain",
                upos: "NOUN",
                head: Some(13),
                relation: "nsubj",
            },
            Annotation {
                lemma: "be",
                upos: "AUX",
                head: Some(13),
                relation: "aux",
            },
            Annotation {
                lemma: "come",
                upos: "VERB",
                head: Some(5),
                relation: "advcl",
            },
        ],
    );
    let spans = partition_sentence_with_syntax(
        &source,
        &[],
        &SenseGroupPartitionConfig::default(),
        &parsed,
    );
    assert!((3..=5).contains(&spans.len()), "got {spans:?}");
    assert!(spans.iter().any(|span| span.label.as_deref() == Some("PP")));
    assert!(
        spans
            .iter()
            .all(|span| { word_count(&source, span.start_token_index, span.end_token_index) <= 8 })
    );
    assert!(spans.iter().all(|span| {
        span.sources.contains(&SenseGroupSource::DependencyParse) && span.head_token_index.is_some()
    }));
}

#[test]
fn dependency_candidate_never_splits_a_protected_phrase() {
    let source = sentence(
        "syntax-phrase",
        "We arrived near New York before the evening meeting started",
    );
    let words = source
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    let new = words.iter().find(|token| token.text == "New").unwrap();
    let york = words.iter().find(|token| token.text == "York").unwrap();
    let phrase = PhraseCandidate {
        canonical_form: "New York".into(),
        display_form: "New York".into(),
        normalized_form: "new york".into(),
        token_start: new.index,
        token_end: york.index,
        reason: "proper name".into(),
    };
    let parsed = syntax(
        &source,
        &[
            Annotation {
                lemma: "we",
                upos: "PRON",
                head: Some(1),
                relation: "nsubj",
            },
            Annotation {
                lemma: "arrive",
                upos: "VERB",
                head: None,
                relation: "root",
            },
            Annotation {
                lemma: "near",
                upos: "ADP",
                head: Some(4),
                relation: "case",
            },
            Annotation {
                lemma: "new",
                upos: "PROPN",
                head: Some(4),
                relation: "compound",
            },
            Annotation {
                lemma: "york",
                upos: "PROPN",
                head: Some(1),
                relation: "obl",
            },
            Annotation {
                lemma: "before",
                upos: "ADP",
                head: Some(8),
                relation: "case",
            },
            Annotation {
                lemma: "the",
                upos: "DET",
                head: Some(8),
                relation: "det",
            },
            Annotation {
                lemma: "evening",
                upos: "NOUN",
                head: Some(8),
                relation: "compound",
            },
            Annotation {
                lemma: "meeting",
                upos: "NOUN",
                head: Some(9),
                relation: "nsubj",
            },
            Annotation {
                lemma: "start",
                upos: "VERB",
                head: Some(1),
                relation: "advcl",
            },
        ],
    );
    let spans = partition_sentence_with_syntax(
        &source,
        &[phrase],
        &SenseGroupPartitionConfig::default(),
        &parsed,
    );
    let containing = spans
        .iter()
        .find(|span| new.index >= span.start_token_index && new.index <= span.end_token_index)
        .unwrap();
    assert!(york.index <= containing.end_token_index);
}

#[test]
fn strong_punctuation_remains_authoritative() {
    let source = sentence(
        "syntax-punct",
        "We stopped immediately; the rain kept falling hard",
    );
    let parsed = syntax(
        &source,
        &[
            Annotation {
                lemma: "we",
                upos: "PRON",
                head: Some(1),
                relation: "nsubj",
            },
            Annotation {
                lemma: "stop",
                upos: "VERB",
                head: None,
                relation: "root",
            },
            Annotation {
                lemma: "immediately",
                upos: "ADV",
                head: Some(1),
                relation: "advmod",
            },
            Annotation {
                lemma: "the",
                upos: "DET",
                head: Some(4),
                relation: "det",
            },
            Annotation {
                lemma: "rain",
                upos: "NOUN",
                head: Some(5),
                relation: "nsubj",
            },
            Annotation {
                lemma: "keep",
                upos: "VERB",
                head: Some(1),
                relation: "conj",
            },
            Annotation {
                lemma: "fall",
                upos: "VERB",
                head: Some(5),
                relation: "xcomp",
            },
            Annotation {
                lemma: "hard",
                upos: "ADV",
                head: Some(6),
                relation: "advmod",
            },
        ],
    );
    let spans = partition_sentence_with_syntax(
        &source,
        &[],
        &SenseGroupPartitionConfig::default(),
        &parsed,
    );
    assert!(spans[0].sources.contains(&SenseGroupSource::Punctuation));
}

#[test]
fn low_coverage_or_wrong_snapshot_is_exact_rule_fallback() {
    let source = sentence(
        "syntax-fallback",
        "We walked through the park after lunch together",
    );
    let mut parsed = syntax(
        &source,
        &[
            Annotation {
                lemma: "we",
                upos: "PRON",
                head: Some(1),
                relation: "nsubj",
            },
            Annotation {
                lemma: "walk",
                upos: "VERB",
                head: None,
                relation: "root",
            },
            Annotation {
                lemma: "through",
                upos: "ADP",
                head: Some(4),
                relation: "case",
            },
            Annotation {
                lemma: "the",
                upos: "DET",
                head: Some(4),
                relation: "det",
            },
            Annotation {
                lemma: "park",
                upos: "NOUN",
                head: Some(1),
                relation: "obl",
            },
            Annotation {
                lemma: "after",
                upos: "ADP",
                head: Some(6),
                relation: "case",
            },
            Annotation {
                lemma: "lunch",
                upos: "NOUN",
                head: Some(1),
                relation: "obl",
            },
            Annotation {
                lemma: "together",
                upos: "ADV",
                head: Some(1),
                relation: "advmod",
            },
        ],
    );
    parsed.lexical_alignment_coverage = 0.9;
    assert_eq!(
        partition_sentence(&source, &[], &SenseGroupPartitionConfig::default()),
        partition_sentence_with_syntax(
            &source,
            &[],
            &SenseGroupPartitionConfig::default(),
            &parsed,
        )
    );
}
