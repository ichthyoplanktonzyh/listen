#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Fuzz WebVTT parsing: every byte sequence should either parse or error
    // gracefully — never panic, never OOM.
    if let Ok(text) = std::str::from_utf8(data) {
        if text.len() > 1_000_000 {
            return;
        }
        let _ = subtitle_core::parse_webvtt(text);
    }
});
