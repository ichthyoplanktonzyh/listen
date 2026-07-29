use domain::{
    PhraseCandidate, SenseGroupSource, SubtitleSentence, SubtitleSentenceId, SubtitleTokenKind,
    SyntacticSentenceAnalysis, SyntacticToken, TimeMs,
};
use serde_json::Value;
use speech_analysis::audible_structure::{
    SenseGroupPartitionConfig, partition_sentence_with_syntax,
};

fn root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn fixture_case(case_id: &str) -> Value {
    let contents =
        std::fs::read_to_string(root().join("testdata/syntactic-analysis/ambiguity-dev-v1.jsonl"))
            .unwrap();
    contents
        .lines()
        .filter_map(|line| serde_json::from_str::<Value>(line).ok())
        .find(|case| case["case_id"] == case_id)
        .unwrap()
}

fn real_stanza_sentence(case_id: &str) -> (SubtitleSentence, SyntacticSentenceAnalysis) {
    let fixture = fixture_case(case_id);
    let report: Value = serde_json::from_str(
        &std::fs::read_to_string(
            root().join("testdata/syntactic-analysis/stanza-sense-group-regression-v1.json"),
        )
        .unwrap(),
    )
    .unwrap();
    let reported = report["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["case_id"] == case_id)
        .unwrap();
    let text = fixture["text"].as_str().unwrap();
    let sentence_id = SubtitleSentenceId::parse(case_id).unwrap();
    let source = SubtitleSentence {
        id: sentence_id.clone(),
        index: 0,
        start: TimeMs::new(0),
        end: TimeMs::new(10_000),
        original_text: text.into(),
        display_text: text.into(),
        tokens: subtitle_core::tokenize_english(text),
    };
    let tokens: Vec<SyntacticToken> = serde_json::from_value(reported["tokens"].clone()).unwrap();
    let syntax = SyntacticSentenceAnalysis {
        sentence_id,
        source_text: text.into(),
        source_char_count: text.chars().count() as u32,
        tokens,
        unaligned_subtitle_token_indices: Vec::new(),
        lexical_alignment_coverage: reported["alignment"]["lexical_alignment_coverage"]
            .as_f64()
            .unwrap() as f32,
    };
    (source, syntax)
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
fn real_caption_state_and_obligation_keeps_teaching_granularity() {
    let (source, syntax) = real_stanza_sentence("syn-dev-real-002");
    let config = SenseGroupPartitionConfig::default();
    let spans = partition_sentence_with_syntax(&source, &[], &config, &syntax);
    assert!((2..=5).contains(&spans.len()), "{spans:?}");
    assert!(spans.iter().all(|span| {
        word_count(&source, span.start_token_index, span.end_token_index) <= config.hard_max_words
    }));
    assert!(spans.iter().all(|span| {
        span.sources.contains(&SenseGroupSource::DependencyParse) && span.head_token_index.is_some()
    }));
}

#[test]
fn real_caption_multiword_proper_name_is_not_split() {
    let (source, syntax) = real_stanza_sentence("syn-dev-real-001");
    let words = source
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    let new = words.iter().find(|token| token.text == "New").unwrap();
    let city = words.iter().find(|token| token.text == "City").unwrap();
    let phrase = PhraseCandidate {
        canonical_form: "New York City".into(),
        display_form: "New York City".into(),
        normalized_form: "new york city".into(),
        token_start: new.index,
        token_end: city.index,
        reason: "real-caption proper name".into(),
    };
    let spans = partition_sentence_with_syntax(
        &source,
        &[phrase],
        &SenseGroupPartitionConfig::default(),
        &syntax,
    );
    let containing = spans
        .iter()
        .find(|span| new.index >= span.start_token_index && new.index <= span.end_token_index)
        .unwrap();
    assert!(city.index <= containing.end_token_index, "{spans:?}");
}
