use domain::{
    PhraseCandidate, SubtitleSentence, SubtitleSentenceId, SubtitleTokenKind, TimeMs, TimingSource,
    WordTiming,
};
use serde::Deserialize;
use speech_analysis::chunk_partition::{
    ChunkPartitionConfig, PARTITIONER_VERSION, partition_sentence,
};

#[derive(Debug, Deserialize)]
struct GoldenCorpus {
    cases: Vec<GoldenCase>,
}

#[derive(Debug, Deserialize)]
struct GoldenCase {
    name: String,
    text: String,
    gaps_ms: Vec<u64>,
    expected_chunks: Vec<String>,
    asr_generated: bool,
    phrase: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RichAcousticCorpus {
    cases: Vec<RichAcousticCase>,
}

#[derive(Debug, Deserialize)]
struct RichAcousticCase {
    name: String,
    text: String,
    durations_ms: Vec<u64>,
    gaps_ms: Vec<u64>,
    expected_chunks: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct LearnedProsodicCorpus {
    cases: Vec<LearnedProsodicCase>,
}

#[derive(Debug, Deserialize)]
struct LearnedProsodicCase {
    name: String,
    text: String,
    durations_ms: Vec<u64>,
    gaps_ms: Vec<u64>,
    expected_with_model: Vec<String>,
    expected_without_model: Vec<String>,
}

#[test]
fn v2_golden_corpus_matches_expected_partitions_and_quality_bounds() {
    let corpus: GoldenCorpus =
        serde_json::from_str(include_str!("../../../testdata/chunk/v2-golden.json")).unwrap();
    let mut single_word_chunks = 0usize;
    let mut overlong_chunks = 0usize;

    for case in corpus.cases {
        let sentence = sentence(&case.name, &case.text);
        let timings = timings(&sentence, &case.gaps_ms);
        let phrases = case
            .phrase
            .as_deref()
            .map(|phrase| phrase_candidate(&sentence, phrase))
            .into_iter()
            .collect::<Vec<_>>();
        let config = if case.asr_generated {
            ChunkPartitionConfig::for_asr_generated_subtitle()
        } else {
            ChunkPartitionConfig::default()
        };
        let result = partition_sentence(&sentence, &timings, &phrases, &config);
        let actual = result
            .chunks
            .iter()
            .map(|chunk| chunk.text.clone())
            .collect::<Vec<_>>();

        assert_eq!(result.partitioner_version, PARTITIONER_VERSION);
        assert_eq!(actual, case.expected_chunks, "golden case {}", case.name);
        single_word_chunks += result
            .chunks
            .iter()
            .filter(|chunk| chunk.text.split_whitespace().count() == 1)
            .count();
        overlong_chunks += result
            .chunks
            .iter()
            .filter(|chunk| chunk.text.split_whitespace().count() > config.soft_max_words)
            .count();
    }

    assert!(
        single_word_chunks <= 2,
        "golden corpus regressed to excessive fragments"
    );
    assert_eq!(overlong_chunks, 0, "golden corpus contains overlong chunks");
}

#[test]
fn v2_partitions_real_whisper_fixture_without_overlong_chunks() {
    let fixture = include_bytes!("../../../testdata/asr/sample-output.json");
    let sentences = [
        sentence("real-asr-1", "Hello world."),
        sentence("real-asr-2", "I was playing games."),
        sentence("real-asr-3", "is what"),
    ];
    let timings =
        speech_analysis::asr_timing::extract_word_timings_from_json(fixture, &sentences).unwrap();
    let config = ChunkPartitionConfig::for_asr_generated_subtitle();

    for sentence in sentences {
        let result = partition_sentence(&sentence, &timings, &[], &config);
        assert!(!result.chunks.is_empty());
        assert!(
            result
                .chunks
                .iter()
                .all(|chunk| { chunk.text.split_whitespace().count() <= config.soft_max_words })
        );
    }
}

#[test]
fn v3_rich_acoustic_corpus_changes_partitions_and_degrades_to_c2() {
    let corpus: RichAcousticCorpus = serde_json::from_str(include_str!(
        "../../../testdata/chunk/v3-rich-acoustic.json"
    ))
    .unwrap();

    for case in corpus.cases {
        let sentence = sentence(&case.name, &case.text);
        let timings = timings_with_durations(&sentence, &case.durations_ms, &case.gaps_ms);
        let result = partition_sentence(&sentence, &timings, &[], &ChunkPartitionConfig::default());
        assert_eq!(
            result
                .chunks
                .iter()
                .map(|chunk| chunk.text.clone())
                .collect::<Vec<_>>(),
            case.expected_chunks,
            "rich acoustic case {}",
            case.name
        );
    }

    let sentence = sentence("missing-rich-features", "We can solve this problem today");
    let timings = timings_with_durations(
        &sentence,
        &[120, 130, 125, 360, 120, 130],
        &[20, 20, 20, 20, 20],
    );
    let c2_result = partition_sentence(
        &sentence,
        &timings,
        &[],
        &ChunkPartitionConfig {
            pre_boundary_lengthening: None,
            filled_pause_hesitation: None,
            learned_prosodic: None,
            ..ChunkPartitionConfig::default()
        },
    );
    assert_eq!(c2_result.chunks.len(), 1);
}

#[test]
fn v4_learned_prosodic_corpus_only_changes_ambiguous_boundaries() {
    let corpus: LearnedProsodicCorpus = serde_json::from_str(include_str!(
        "../../../testdata/chunk/v4-learned-prosodic.json"
    ))
    .unwrap();

    for case in corpus.cases {
        let sentence = sentence(&case.name, &case.text);
        let timings = timings_with_durations(&sentence, &case.durations_ms, &case.gaps_ms);
        let with_model = partition_sentence(
            &sentence,
            &timings,
            &[],
            &ChunkPartitionConfig {
                pre_boundary_lengthening: None,
                ..ChunkPartitionConfig::default()
            },
        );
        let without_model = partition_sentence(
            &sentence,
            &timings,
            &[],
            &ChunkPartitionConfig {
                pre_boundary_lengthening: None,
                learned_prosodic: None,
                ..ChunkPartitionConfig::default()
            },
        );
        assert_eq!(
            with_model
                .chunks
                .iter()
                .map(|chunk| chunk.text.clone())
                .collect::<Vec<_>>(),
            case.expected_with_model,
            "learned case {} with model",
            case.name
        );
        assert_eq!(
            without_model
                .chunks
                .iter()
                .map(|chunk| chunk.text.clone())
                .collect::<Vec<_>>(),
            case.expected_without_model,
            "learned case {} without model",
            case.name
        );
    }
}

fn sentence(id: &str, text: &str) -> SubtitleSentence {
    SubtitleSentence {
        id: SubtitleSentenceId::from_fingerprint("chunk-golden", id),
        index: 0,
        start: TimeMs::new(0),
        end: TimeMs::new(10_000),
        original_text: text.into(),
        display_text: text.into(),
        tokens: subtitle_core::tokenize_english(text),
    }
}

fn timings(sentence: &SubtitleSentence, gaps_ms: &[u64]) -> Vec<WordTiming> {
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    assert_eq!(gaps_ms.len(), words.len().saturating_sub(1));
    let mut cursor = 0u64;
    words
        .iter()
        .enumerate()
        .map(|(position, token)| {
            let start_ms = cursor;
            let end_ms = start_ms + 200;
            cursor = end_ms + gaps_ms.get(position).copied().unwrap_or_default();
            WordTiming {
                sentence_id: sentence.id.clone(),
                token_index: token.index,
                text: token.text.clone(),
                start_ms,
                end_ms,
                confidence: None,
                timing_source: TimingSource::AsrReported,
                provider_id: "golden".into(),
                provider_version: "v1".into(),
            }
        })
        .collect()
}

fn timings_with_durations(
    sentence: &SubtitleSentence,
    durations_ms: &[u64],
    gaps_ms: &[u64],
) -> Vec<WordTiming> {
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    assert_eq!(durations_ms.len(), words.len());
    assert_eq!(gaps_ms.len(), words.len().saturating_sub(1));
    let mut cursor = 0u64;
    words
        .iter()
        .zip(durations_ms)
        .enumerate()
        .map(|(position, (token, duration))| {
            let start_ms = cursor;
            let end_ms = start_ms + duration;
            cursor = end_ms + gaps_ms.get(position).copied().unwrap_or_default();
            WordTiming {
                sentence_id: sentence.id.clone(),
                token_index: token.index,
                text: token.text.clone(),
                start_ms,
                end_ms,
                confidence: None,
                timing_source: TimingSource::ForcedAligned,
                provider_id: "rich-acoustic-golden".into(),
                provider_version: "v1".into(),
            }
        })
        .collect()
}

fn phrase_candidate(sentence: &SubtitleSentence, phrase: &str) -> PhraseCandidate {
    let phrase_words = phrase.split_whitespace().collect::<Vec<_>>();
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    let start = words
        .windows(phrase_words.len())
        .position(|window| {
            window
                .iter()
                .zip(&phrase_words)
                .all(|(token, expected)| token.text.eq_ignore_ascii_case(expected))
        })
        .expect("golden phrase must occur in sentence");
    PhraseCandidate {
        canonical_form: phrase.into(),
        display_form: phrase.into(),
        normalized_form: phrase.to_ascii_lowercase(),
        token_start: words[start].index,
        token_end: words[start + phrase_words.len() - 1].index,
        reason: "golden".into(),
    }
}
