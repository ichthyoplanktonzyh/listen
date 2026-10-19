use domain::{
    SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs, TimingSource,
};
use speech_analysis::timing::extract_word_timings_from_json;

fn word_token(index: u32, text: &str) -> SubtitleToken {
    SubtitleToken {
        index,
        kind: SubtitleTokenKind::Word,
        text: text.to_string(),
        normalized: Some(text.to_lowercase()),
        start_char: 0,
        end_char: text.len() as u32,
    }
}

fn sentence(id: &str, start_ms: u64, end_ms: u64, words: &[&str]) -> SubtitleSentence {
    SubtitleSentence {
        id: SubtitleSentenceId::parse(id).unwrap(),
        index: 0,
        start: TimeMs::new(start_ms),
        end: TimeMs::new(end_ms),
        original_text: words.join(" "),
        display_text: words.join(" "),
        tokens: words
            .iter()
            .enumerate()
            .map(|(i, text)| word_token(i as u32, text))
            .collect(),
    }
}

fn load_fixture() -> Vec<u8> {
    let path = format!(
        "{}/../../testdata/asr/sample-output.json",
        env!("CARGO_MANIFEST_DIR")
    );
    std::fs::read(&path).expect("failed to read ASR JSON fixture")
}

#[test]
fn parses_fixture_and_extracts_word_timings() {
    let json_bytes = load_fixture();

    // Segment 1: "Hello world." — 2 word tokens
    // Segment 2: "I was playing games." — 4 word tokens ("playing" ← "play"+"ing")
    // Segment 3: "This is what" — NOTE: "This" has t_dtw=-1; sentence has
    //             only 2 word tokens ("is", "what") to match after filtering
    let sentences = vec![
        sentence("s1", 0, 4000, &["Hello", "world"]),
        sentence("s2", 4000, 9000, &["I", "was", "playing", "games"]),
        sentence("s3", 9000, 11000, &["is", "what"]),
    ];

    let timings =
        extract_word_timings_from_json(&json_bytes, &sentences).expect("extraction should succeed");
    assert_eq!(
        timings.len(),
        8,
        "should extract 2 + 4 + 2 = 8 word timings"
    );

    // Lexical DTW points receive a bounded 80ms duration. Punctuation does not
    // extend the previous word because that would consume audible pauses.
    assert_eq!(timings[0].sentence_id, sentences[0].id);
    assert_eq!(timings[0].token_index, 0);
    assert_eq!(timings[0].text, "Hello");
    assert_eq!(timings[0].start_ms, 1000);
    assert_eq!(timings[0].end_ms, 1080);

    assert_eq!(timings[1].sentence_id, sentences[0].id);
    assert_eq!(timings[1].token_index, 1);
    assert_eq!(timings[1].text, "world");
    assert_eq!(timings[1].start_ms, 2500);
    assert_eq!(timings[1].end_ms, 2580);

    // ── Segment 2: "I", "was", "playing", "games" ──
    assert_eq!(timings[2].sentence_id, sentences[1].id);
    assert_eq!(timings[2].token_index, 0);
    assert_eq!(timings[2].text, "I");
    assert_eq!(timings[2].start_ms, 4000);
    assert_eq!(timings[2].end_ms, 4080);

    assert_eq!(timings[3].token_index, 1);
    assert_eq!(timings[3].text, "was");
    assert_eq!(timings[3].start_ms, 4800);
    assert_eq!(timings[3].end_ms, 4880);

    // "playing" = " play" + "ing" → start=5800 (play), end=6200 (ing)
    assert_eq!(timings[4].token_index, 2);
    assert_eq!(timings[4].text, "playing");
    assert_eq!(timings[4].start_ms, 5800);
    assert_eq!(timings[4].end_ms, 6280);

    assert_eq!(timings[5].token_index, 3);
    assert_eq!(timings[5].text, "games");
    assert_eq!(timings[5].start_ms, 7000);
    assert_eq!(timings[5].end_ms, 7080);

    // ── Segment 3: "is", "what" (t_dtw=-1 for "This" filtered out) ──
    assert_eq!(timings[6].sentence_id, sentences[2].id);
    assert_eq!(timings[6].token_index, 0);
    assert_eq!(timings[6].text, "is");
    assert_eq!(timings[6].start_ms, 9000);
    assert_eq!(timings[6].end_ms, 9080);

    assert_eq!(timings[7].token_index, 1);
    assert_eq!(timings[7].text, "what");
    assert_eq!(timings[7].start_ms, 9800);
    assert_eq!(timings[7].end_ms, 9880);

    // All timings should be AsrReported
    for t in &timings {
        assert_eq!(t.timing_source, TimingSource::AsrReported);
        assert_eq!(t.provider_id, "whisper.cpp");
        assert_eq!(t.provider_version, "dtw-v2");
        assert!(t.start_ms < t.end_ms);
        assert!(t.confidence.is_none());
    }
}

#[test]
fn segment_count_mismatch_returns_error() {
    let json_bytes = load_fixture();
    let sentences = vec![sentence("s1", 0, 1000, &["only", "one"])];

    let err = extract_word_timings_from_json(&json_bytes, &sentences).unwrap_err();
    assert!(err.to_string().contains("segment count mismatch"));
}

#[test]
fn word_count_mismatch_returns_empty_for_sentence() {
    let json_bytes = load_fixture();
    // Segment 3 has 2 merged words (after t_dtw=-1 filter), but we claim 3 → fallback
    let sentences = vec![
        sentence("s1", 0, 4000, &["Hello", "world"]),
        sentence("s2", 4000, 9000, &["I", "was", "playing", "games"]),
        sentence("s3", 9000, 11000, &["This", "is", "what"]), // 3 words, but only 2 merged
    ];

    let timings =
        extract_word_timings_from_json(&json_bytes, &sentences).expect("extraction should succeed");
    // Segments 1 and 2 succeed, segment 3 falls back (empty)
    assert_eq!(timings.len(), 6);
    // All timings should be from segments 1 and 2
    for t in &timings {
        assert!(
            t.sentence_id == sentences[0].id || t.sentence_id == sentences[1].id,
            "timing should be from segment 1 or 2, not 3"
        );
    }
}
