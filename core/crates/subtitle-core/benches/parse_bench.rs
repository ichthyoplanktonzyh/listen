use criterion::{Criterion, black_box, criterion_group, criterion_main};
use subtitle_core::*;

fn small_srt() -> &'static str {
    include_str!("../../../testdata/subtitles/timeline.srt")
}

fn small_vtt() -> &'static str {
    include_str!("../../../testdata/subtitles/timeline.vtt")
}

/// Generate a large synthetic SRT file for throughput benchmarking.
fn large_srt(sentence_count: usize) -> String {
    let mut buf = String::with_capacity(sentence_count * 80);
    for i in 0..sentence_count {
        let start = i as u64;
        let end = start + 2;
        buf.push_str(&format!("{}\n", i + 1));
        buf.push_str(&format!(
            "{:02}:{:02}:{:02},000 --> {:02}:{:02}:{:02},000\n",
            start / 3600,
            (start % 3600) / 60,
            start % 60,
            end / 3600,
            (end % 3600) / 60,
            end % 60,
        ));
        buf.push_str("This is sentence number ");
        buf.push_str(&i.to_string());
        buf.push_str(" for benchmark testing.\n\n");
    }
    buf
}

fn bench_parse_srt_small(c: &mut Criterion) {
    let srt = small_srt();
    c.bench_function("parse_srt (small fixture)", |b| {
        b.iter(|| parse_srt(black_box(srt)))
    });
}

fn bench_parse_srt_large(c: &mut Criterion) {
    let srt = large_srt(2_000);
    c.bench_function("parse_srt (2k sentences)", |b| {
        b.iter(|| parse_srt(black_box(&srt)))
    });
}

fn bench_parse_vtt_small(c: &mut Criterion) {
    let vtt = small_vtt();
    c.bench_function("parse_webvtt (small fixture)", |b| {
        b.iter(|| parse_webvtt(black_box(vtt)))
    });
}

fn bench_parse_vtt_large(c: &mut Criterion) {
    let vtt = {
        let srt = large_srt(2_000);
        // Convert SRT-style to WebVTT — just add WEBVTT header
        format!("WEBVTT\n\n{}", srt.replace(",", "."))
    };
    c.bench_function("parse_webvtt (2k sentences)", |b| {
        b.iter(|| parse_webvtt(black_box(&vtt)))
    });
}

fn bench_tokenize_english(c: &mut Criterion) {
    let text = "This is a typical English sentence with \"quoted text\" and contractions like don't, won't, and it's.";
    c.bench_function("tokenize_english", |b| {
        b.iter(|| tokenize_english(black_box(text)))
    });
}

fn bench_normalize_display(c: &mut Criterion) {
    let text = "This is a DISPLAY string with UPPERCASE and extra  spaces \t tabs.";
    c.bench_function("normalize_display", |b| {
        b.iter(|| normalize_display(black_box(text)))
    });
}

criterion_group!(
    benches,
    bench_parse_srt_small,
    bench_parse_srt_large,
    bench_parse_vtt_small,
    bench_parse_vtt_large,
    bench_tokenize_english,
    bench_normalize_display,
);
criterion_main!(benches);
