#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Fuzz ASR timing extraction: every byte sequence should either parse
    // or error gracefully — never panic, never OOM.
    if data.len() > 1_000_000 {
        return;
    }
    let _ = speech_analysis::asr_timing::extract_word_timings_from_json(data, &[]);
});
