use domain::{
    SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs, TimingSource,
};
use speech_analysis::asr_timing::extract_word_timings_from_json;

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
    // Segment 3: "This is what" — "This" has t_dtw=-1, so the whole sentence
    // falls back rather than shifting the remaining timestamps.
    let sentences = vec![
        sentence("s1", 0, 4000, &["Hello", "world"]),
        sentence("s2", 4000, 9000, &["I", "was", "playing", "games"]),
        sentence("s3", 9000, 11000, &["This", "is", "what"]),
    ];

    let timings =
        extract_word_timings_from_json(&json_bytes, &sentences).expect("extraction should succeed");
    assert_eq!(
        timings.len(),
        6,
        "should extract the first two segments and fall back for the third"
    );

    // Segment 1 includes real whisper special tokens around the lexical tokens.
    assert_eq!(timings[0].sentence_id, sentences[0].id);
    assert_eq!(timings[0].token_index, 0);
    assert_eq!(timings[0].text, "Hello");
    assert_eq!(timings[0].start_ms, 1000);
    assert_eq!(timings[0].end_ms, 2500);

    assert_eq!(timings[1].sentence_id, sentences[0].id);
    assert_eq!(timings[1].token_index, 1);
    assert_eq!(timings[1].text, "world");
    assert_eq!(timings[1].start_ms, 2500);
    assert_eq!(timings[1].end_ms, 4000);

    // Segment 2: each interval ends at the next word start or sentence end.
    assert_eq!(timings[2].sentence_id, sentences[1].id);
    assert_eq!(timings[2].token_index, 0);
    assert_eq!(timings[2].text, "I");
    assert_eq!(timings[2].start_ms, 4000);
    assert_eq!(timings[2].end_ms, 4800);

    assert_eq!(timings[3].token_index, 1);
    assert_eq!(timings[3].text, "was");
    assert_eq!(timings[3].start_ms, 4800);
    assert_eq!(timings[3].end_ms, 5800);

    // "playing" = " play" + "ing"; its word start comes from the first subword.
    assert_eq!(timings[4].token_index, 2);
    assert_eq!(timings[4].text, "playing");
    assert_eq!(timings[4].start_ms, 5800);
    assert_eq!(timings[4].end_ms, 7000);

    assert_eq!(timings[5].token_index, 3);
    assert_eq!(timings[5].text, "games");
    assert_eq!(timings[5].start_ms, 7000);
    assert_eq!(timings[5].end_ms, 9000);

    // All timings should be AsrReported
    for t in &timings {
        assert_eq!(t.timing_source, TimingSource::AsrReported);
        assert_eq!(t.provider_id, "whisper.cpp");
        assert_eq!(t.provider_version, "dtw-v1");
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
    // Segment 3 has an unavailable lexical word and must fall back.
    let sentences = vec![
        sentence("s1", 0, 4000, &["Hello", "world"]),
        sentence("s2", 4000, 9000, &["I", "was", "playing", "games"]),
        sentence("s3", 9000, 11000, &["This", "is", "what"]),
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

#[test]
fn handles_real_whisper_special_tokens_and_repeated_dtw_points() {
    // Reduced verbatim structure from the bundled whisper.cpp v1.7.6 output
    // for samples/jfk.wav using `-ojf -dtw base`.
    let json_bytes = br#"{
      "transcription": [{
        "text": " And so, my fellow Americans, ask not what your country can do for you,",
        "tokens": [
          {"text":"[_BEG_]","t_dtw":-1},
          {"text":" And","t_dtw":52},
          {"text":" so","t_dtw":88},
          {"text":",","t_dtw":110},
          {"text":" my","t_dtw":122},
          {"text":" fellow","t_dtw":158},
          {"text":" Americans","t_dtw":230},
          {"text":",","t_dtw":316},
          {"text":" ask","t_dtw":420},
          {"text":" not","t_dtw":420},
          {"text":" what","t_dtw":556},
          {"text":" your","t_dtw":578},
          {"text":" country","t_dtw":636},
          {"text":" can","t_dtw":656},
          {"text":" do","t_dtw":684},
          {"text":" for","t_dtw":708},
          {"text":" you","t_dtw":728},
          {"text":",","t_dtw":850},
          {"text":"[_TT_400]","t_dtw":-1}
        ]
      }]
    }"#;
    let sentences = vec![sentence(
        "s1",
        0,
        8000,
        &[
            "And",
            "so",
            "my",
            "fellow",
            "Americans",
            "ask",
            "not",
            "what",
            "your",
            "country",
            "can",
            "do",
            "for",
            "you",
        ],
    )];

    let timings = extract_word_timings_from_json(json_bytes, &sentences).unwrap();

    assert_eq!(timings.len(), 14);
    assert_eq!(timings[5].text, "ask");
    assert_eq!((timings[5].start_ms, timings[5].end_ms), (4200, 4201));
    assert_eq!(timings[6].text, "not");
    assert_eq!((timings[6].start_ms, timings[6].end_ms), (4201, 5560));
    assert_eq!(timings.last().unwrap().text, "you");
    assert_eq!(timings.last().unwrap().end_ms, 8000);
    assert!(timings.iter().all(|timing| timing.start_ms < timing.end_ms));
}
