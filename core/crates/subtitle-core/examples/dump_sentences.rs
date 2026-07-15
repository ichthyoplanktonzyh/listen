//! Dev tool: run a subtitle file through the production `import` path and
//! print the resulting sentences as JSON lines. Used for reading-view QA
//! (paragraph derivation operates on production sentences, not raw cues).
//!
//! Usage: cargo run -p subtitle-core --example dump_sentences -- <file.srt>

use std::{env, fs};

use domain::MediaId;
use subtitle_core::{ImportSubtitle, import};

fn main() {
    let path = env::args()
        .nth(1)
        .expect("usage: dump_sentences <file.srt>");
    let content = fs::read(&path).expect("read subtitle file");
    let track = import(ImportSubtitle {
        media_id: MediaId::from_fingerprint("media", &path),
        source_name: path.clone(),
        content,
        language: None,
        identity_salt: None,
    })
    .expect("import subtitle");

    for sentence in &track.sentences {
        let words = sentence
            .tokens
            .iter()
            .filter(|token| token.kind == domain::SubtitleTokenKind::Word)
            .count();
        println!(
            "{}",
            serde_json::json!({
                "id": sentence.id.as_str(),
                "index": sentence.index,
                "start_ms": sentence.start.get(),
                "end_ms": sentence.end.get(),
                "word_count": words,
                "text": sentence.display_text,
            })
        );
    }
}
