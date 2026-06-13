use criterion::{Criterion, black_box, criterion_group, criterion_main};
use domain::{SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs};
use speech_analysis::asr_timing::extract_word_timings_from_json;
use speech_analysis::estimate_word_timings;

fn asr_fixture_bytes() -> Vec<u8> {
    include_str!("../../../testdata/asr/sample-output.json")
        .as_bytes()
        .to_vec()
}

fn asr_fixture_sentences() -> Vec<SubtitleSentence> {
    // Sentences matching sample-output.json: 3 segments
    [
        ("Hello world.", &["Hello", "world", "."] as &[&str]),
        (
            "I was playing games.",
            &["I", "was", "play", "ing", "games", "."],
        ),
        ("This is what", &["This", "is", "what"]),
    ]
    .into_iter()
    .enumerate()
    .map(|(idx, (text, words))| {
        let tokens: Vec<SubtitleToken> = words
            .iter()
            .enumerate()
            .map(|(wi, w)| SubtitleToken {
                index: wi as u32,
                kind: if w.chars().all(|c| c.is_alphanumeric()) {
                    SubtitleTokenKind::Word
                } else {
                    SubtitleTokenKind::Punctuation
                },
                text: (*w).into(),
                normalized: Some((*w).into()),
                start_char: 0,
                end_char: 0,
            })
            .collect();
        SubtitleSentence {
            id: SubtitleSentenceId::parse(format!("s{idx}")).unwrap(),
            index: idx as u32,
            start: TimeMs::new((idx * 1000) as u64),
            end: TimeMs::new((idx * 1000 + 800) as u64),
            original_text: (*text).into(),
            display_text: (*text).into(),
            tokens,
        }
    })
    .collect()
}

/// Generate synthetic ASR JSON in whisper -ojf format.
fn large_asr_json(segment_count: usize) -> String {
    let mut buf = String::with_capacity(segment_count * 200);
    buf.push_str("{\"transcription\":[");
    for i in 0..segment_count {
        if i > 0 {
            buf.push(',');
        }
        buf.push_str(&format!(
            r#"{{"text":"sentence {}","tokens":[{{"text":" word{}","t_dtw":{}}}]}}"#,
            i,
            i,
            (i * 500) as i64,
        ));
    }
    buf.push_str("]}");
    buf
}

fn matching_sentences(count: usize) -> Vec<SubtitleSentence> {
    (0..count)
        .map(|i| {
            let token = SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: format!("word{}", i),
                normalized: Some(format!("word{}", i)),
                start_char: 0,
                end_char: 0,
            };
            SubtitleSentence {
                id: SubtitleSentenceId::parse(format!("s{i}")).unwrap(),
                index: i as u32,
                start: TimeMs::new((i * 1000) as u64),
                end: TimeMs::new((i * 1000 + 800) as u64),
                original_text: format!("sentence {}", i),
                display_text: format!("sentence {}", i),
                tokens: vec![token],
            }
        })
        .collect()
}

fn bench_extract_word_timings_small(c: &mut Criterion) {
    let json = asr_fixture_bytes();
    let sentences = asr_fixture_sentences();
    c.bench_function("extract_word_timings (small fixture)", |b| {
        b.iter(|| extract_word_timings_from_json(black_box(&json), black_box(&sentences)))
    });
}

fn bench_extract_word_timings_large(c: &mut Criterion) {
    let json = large_asr_json(500);
    let json_bytes = json.as_bytes();
    let sentences = matching_sentences(500);
    c.bench_function("extract_word_timings (500 segments)", |b| {
        b.iter(|| extract_word_timings_from_json(black_box(json_bytes), black_box(&sentences)))
    });
}

fn make_sentence(word_count: usize) -> SubtitleSentence {
    let tokens: Vec<SubtitleToken> = (0..word_count)
        .map(|i| SubtitleToken {
            index: i as u32,
            kind: SubtitleTokenKind::Word,
            text: format!("word{}", i),
            normalized: Some(format!("word{}", i)),
            start_char: 0,
            end_char: 0,
        })
        .collect();
    SubtitleSentence {
        id: SubtitleSentenceId::parse("bench-sentence").unwrap(),
        index: 0,
        start: TimeMs::ZERO,
        end: TimeMs::new((word_count * 300) as u64),
        original_text: (0..word_count)
            .map(|i| format!("word{}", i))
            .collect::<Vec<_>>()
            .join(" "),
        display_text: (0..word_count)
            .map(|i| format!("word{}", i))
            .collect::<Vec<_>>()
            .join(" "),
        tokens,
    }
}

fn bench_estimate_word_timings(c: &mut Criterion) {
    let sentence = make_sentence(20);
    c.bench_function("estimate_word_timings (20 words)", |b| {
        b.iter(|| estimate_word_timings(black_box(&sentence)))
    });
}

fn bench_estimate_word_timings_many_words(c: &mut Criterion) {
    let sentence = make_sentence(100);
    c.bench_function("estimate_word_timings (100 words)", |b| {
        b.iter(|| estimate_word_timings(black_box(&sentence)))
    });
}

criterion_group!(
    benches,
    bench_extract_word_timings_small,
    bench_extract_word_timings_large,
    bench_estimate_word_timings,
    bench_estimate_word_timings_many_words,
);
criterion_main!(benches);
