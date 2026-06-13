use domain::{SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs};
use speech_analysis::chunk_detection::{
    detect_chunk_boundaries, detect_chunk_boundaries_for_track, ChunkDetectionConfig,
};
use speech_analysis::estimate_word_timings;

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

// ---------------------------------------------------------------------------
// Test 1: estimated timings produce connected chunks (no artificial
//         boundaries from character-weighted uniform distribution).
// ---------------------------------------------------------------------------
#[test]
fn estimated_timings_produce_single_chunk() {
    // Estimated timings distribute the sentence duration evenly, weighted by
    // character count. Adjacent words should have gaps close to zero, so no
    // chunk boundaries are expected.
    let sentence = sentence("s1", 0, 5000, &["I", "think", "that", "is", "right"]);
    let timings = estimate_word_timings(&sentence);

    let config = ChunkDetectionConfig::default();
    let result = detect_chunk_boundaries(&timings, &config);

    assert_eq!(result.chunks.len(), 1, "estimated timings should produce a single chunk");
    assert_eq!(result.chunks[0].token_start, 0);
    assert_eq!(result.chunks[0].token_end, 4);
    assert_eq!(result.chunks[0].text, "I think that is right");
    assert!(result.boundaries.is_empty());
    // All raw gaps should be small (uniform distribution leaves near-zero gaps)
    for &gap in &result.raw_gaps_ms {
        assert!(gap < 250, "estimated timings gaps should be well below threshold");
    }
}

// ---------------------------------------------------------------------------
// Test 2: threshold sensitivity — lower thresholds detect more boundaries.
// ---------------------------------------------------------------------------
#[test]
fn threshold_sensitivity_lower_finds_more_boundaries() {
    // Synthetic data with gaps of 0ms, 100ms, 200ms, 300ms between words.
    let sid = SubtitleSentenceId::parse("s1").unwrap();
    let timings = vec![
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 0, text: "w0".into(),
            start_ms: 0, end_ms: 80, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 1, text: "w1".into(),
            start_ms: 80, end_ms: 160, confidence: None,  // 0ms gap
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 2, text: "w2".into(),
            start_ms: 260, end_ms: 340, confidence: None,  // 100ms gap
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 3, text: "w3".into(),
            start_ms: 540, end_ms: 620, confidence: None,  // 200ms gap
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 4, text: "w4".into(),
            start_ms: 920, end_ms: 1000, confidence: None, // 300ms gap
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
    ];

    // Very low threshold: should find boundaries at 100ms, 200ms, 300ms gaps.
    let lo = ChunkDetectionConfig { gap_threshold_ms: 50, ..Default::default() };
    let r_lo = detect_chunk_boundaries(&timings, &lo);
    // Expected: gaps at [0, 100, 200, 300] → boundaries at 100, 200, 300 → 4 chunks
    assert_eq!(r_lo.boundaries.len(), 3, "low threshold should detect 3 boundaries");
    assert_eq!(r_lo.chunks.len(), 4);

    // Medium threshold: should find boundaries only at 200ms and 300ms.
    let md = ChunkDetectionConfig { gap_threshold_ms: 150, ..Default::default() };
    let r_md = detect_chunk_boundaries(&timings, &md);
    assert_eq!(r_md.boundaries.len(), 2, "medium threshold should detect 2 boundaries");
    assert_eq!(r_md.chunks.len(), 3);

    // High threshold: should find only the 300ms boundary.
    let hi = ChunkDetectionConfig { gap_threshold_ms: 250, ..Default::default() };
    let r_hi = detect_chunk_boundaries(&timings, &hi);
    assert_eq!(r_hi.boundaries.len(), 1, "high threshold should detect 1 boundary");
    assert_eq!(r_hi.chunks.len(), 2);

    // Very high: no boundaries.
    let vh = ChunkDetectionConfig { gap_threshold_ms: 500, ..Default::default() };
    let r_vh = detect_chunk_boundaries(&timings, &vh);
    assert!(r_vh.boundaries.is_empty());
    assert_eq!(r_vh.chunks.len(), 1);
}

// ---------------------------------------------------------------------------
// Test 3: chunk text reconstruction matches sentence word order.
// ---------------------------------------------------------------------------
#[test]
fn chunk_text_reconstruction_matches_words() {
    let sid = SubtitleSentenceId::parse("s1").unwrap();
    // 7 words with a clear boundary after word 3 (gap=400ms).
    let timings = vec![
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 0, text: "I".into(),
            start_ms: 0, end_ms: 120, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 1, text: "think".into(),
            start_ms: 130, end_ms: 300, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 2, text: "that".into(),
            start_ms: 310, end_ms: 450, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 3, text: "it's".into(),
            start_ms: 460, end_ms: 600, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        // 400ms gap — clear prosodic boundary
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 4, text: "important".into(),
            start_ms: 1000, end_ms: 1250, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 5, text: "to".into(),
            start_ms: 1260, end_ms: 1320, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid.clone(), token_index: 6, text: "note".into(),
            start_ms: 1330, end_ms: 1600, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
    ];

    let config = ChunkDetectionConfig::default();
    let result = detect_chunk_boundaries(&timings, &config);

    assert_eq!(result.boundaries.len(), 1);
    assert_eq!(result.boundaries[0].left_token_index, 3);
    assert_eq!(result.boundaries[0].right_token_index, 4);
    assert_eq!(result.boundaries[0].gap_ms, 400);
    assert_eq!(result.chunks.len(), 2);

    assert_eq!(result.chunks[0].token_start, 0);
    assert_eq!(result.chunks[0].token_end, 3);
    assert_eq!(result.chunks[0].text, "I think that it's");

    assert_eq!(result.chunks[1].token_start, 4);
    assert_eq!(result.chunks[1].token_end, 6);
    assert_eq!(result.chunks[1].text, "important to note");

    // Concatenated chunk text should cover all words in order.
    let reconstructed: Vec<&str> = result
        .chunks
        .iter()
        .flat_map(|c| c.text.split_whitespace())
        .collect();
    let original: Vec<&str> = timings.iter().map(|t| t.text.as_str()).collect();
    assert_eq!(reconstructed, original);
}

// ---------------------------------------------------------------------------
// Test 4: track-level detection does not merge across sentences.
// ---------------------------------------------------------------------------
#[test]
fn track_detection_isolates_sentences() {
    let sid1 = SubtitleSentenceId::parse("s1").unwrap();
    let sid2 = SubtitleSentenceId::parse("s2").unwrap();

    // Each sentence has one internal boundary (gap > threshold).
    let t1 = vec![
        domain::WordTiming {
            sentence_id: sid1.clone(), token_index: 0, text: "a".into(),
            start_ms: 0, end_ms: 100, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid1.clone(), token_index: 1, text: "b".into(),
            start_ms: 400, end_ms: 500, confidence: None,  // 300ms gap
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
    ];
    let t2 = vec![
        domain::WordTiming {
            sentence_id: sid2.clone(), token_index: 0, text: "c".into(),
            start_ms: 0, end_ms: 100, confidence: None,
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
        domain::WordTiming {
            sentence_id: sid2.clone(), token_index: 1, text: "d".into(),
            start_ms: 500, end_ms: 600, confidence: None,  // 400ms gap
            timing_source: domain::TimingSource::AsrReported,
            provider_id: "test".into(), provider_version: "v1".into(),
        },
    ];

    let config = ChunkDetectionConfig::default();
    let results = detect_chunk_boundaries_for_track(
        &[(sid1.clone(), t1), (sid2.clone(), t2)],
        &config,
    );

    assert_eq!(results.len(), 2);
    let r1 = &results[&sid1];
    let r2 = &results[&sid2];
    assert_eq!(r1.boundaries.len(), 1);
    assert_eq!(r2.boundaries.len(), 1);
    assert_eq!(r1.chunks.len(), 2);
    assert_eq!(r2.chunks.len(), 2);
    // Each sentence's chunks are independent — no cross-sentence merging.
}

// ---------------------------------------------------------------------------
// Test 5: real ASR fixture — verify detection runs without error and
//         produces at least one chunk per sentence.
// ---------------------------------------------------------------------------
#[test]
fn detects_chunks_from_real_asr_timings() {
    use speech_analysis::asr_timing::extract_word_timings_from_json;

    let fixture_path = format!(
        "{}/../../testdata/asr/sample-output.json",
        env!("CARGO_MANIFEST_DIR")
    );
    let json_bytes =
        std::fs::read(&fixture_path).expect("failed to read ASR JSON fixture");

    let sentences = vec![
        sentence("s1", 0, 4000, &["Hello", "world"]),
        sentence("s2", 4000, 9000, &["I", "was", "playing", "games"]),
        sentence("s3", 9000, 11000, &["is", "what"]),
    ];

    let timings =
        extract_word_timings_from_json(&json_bytes, &sentences).expect("extraction should succeed");

    let config = ChunkDetectionConfig::default();
    let result = detect_chunk_boundaries(&timings, &config);

    // Every word should appear in some chunk.
    let chunk_word_count: usize = result.chunks.iter().map(|c| c.text.split_whitespace().count()).sum();
    assert_eq!(chunk_word_count, timings.len());

    // Result metadata should be populated.
    assert_eq!(result.raw_gaps_ms.len(), timings.len().saturating_sub(1));
    assert_eq!(result.config.gap_threshold_ms, 250);

    // With DTW 100ms granularity, many gaps are large (800ms+), so we expect
    // multiple chunks. This is a known DTW artifact — word boundaries are
    // centred at DTW points, inflating inter-word gaps.
    assert!(!result.chunks.is_empty(), "must produce at least one chunk");
    // The number of boundaries is driven by DTW resolution; we don't assert on
    // a specific count, but every boundary must have a non-zero gap and valid
    // confidence.
    for b in &result.boundaries {
        assert!(b.gap_ms > 0, "boundary gap should be non-zero");
        assert!((0.0..=1.0).contains(&b.confidence), "confidence should be in [0,1]");
    }
}
