use domain::{SubtitleSentence, SubtitleToken, SubtitleTokenKind, TimingSource, WordTiming};
use serde::Deserialize;

const DTW_TOKEN_DURATION_MS: u64 = 80;

/// Top-level whisper JSON-full output.
#[derive(Debug, Deserialize)]
struct WhisperOutput {
    transcription: Vec<WhisperSegment>,
}

#[derive(Debug, Deserialize)]
struct WhisperSegment {
    #[allow(dead_code)]
    text: String,
    tokens: Vec<WhisperToken>,
}

#[derive(Debug, Deserialize)]
struct WhisperToken {
    text: String,
    /// DTW timestamp in centiseconds. -1 when unavailable.
    #[serde(default = "dtw_unavailable")]
    t_dtw: i64,
}

fn dtw_unavailable() -> i64 {
    -1
}

/// Extracts word-level timings from whisper `-ojf` JSON output and maps them
/// to the lexical tokens of each sentence.
///
/// DTW timestamps are in centiseconds; the function converts to milliseconds
/// and validates monotonicity and sentence boundaries.
///
/// When whisper BPE word count matches app token count, timings map directly
/// (identity alignment). When they differ — common for CJK languages where
/// BPE merges characters differently from linguistic tokenizers — the function
/// performs character-level time interpolation to align whisper timings onto
/// app token boundaries.
pub fn extract_word_timings_from_json(
    json_bytes: &[u8],
    sentences: &[SubtitleSentence],
) -> Result<Vec<WordTiming>, ExtractError> {
    let output: WhisperOutput =
        serde_json::from_slice(json_bytes).map_err(|e| ExtractError::Json(e.to_string()))?;

    if output.transcription.len() != sentences.len() {
        return Err(ExtractError::SegmentCountMismatch {
            json: output.transcription.len(),
            sentences: sentences.len(),
        });
    }

    let mut all_timings = Vec::new();

    for (seg, sentence) in output.transcription.iter().zip(sentences.iter()) {
        let timings = extract_sentence_word_timings(seg, sentence)?;
        all_timings.extend(timings);
    }

    Ok(all_timings)
}

fn extract_sentence_word_timings(
    seg: &WhisperSegment,
    sentence: &SubtitleSentence,
) -> Result<Vec<WordTiming>, ExtractError> {
    let word_tokens: Vec<_> = sentence
        .tokens
        .iter()
        .filter(|t| t.kind == SubtitleTokenKind::Word)
        .collect();

    let words = merge_tokens_to_words(&seg.tokens);
    if words.is_empty() || word_tokens.is_empty() {
        return Ok(vec![]);
    }

    let word_spans = resolve_time_spans(&words, sentence.end.get());

    if words.len() == word_tokens.len() {
        return extract_direct(&words, &word_spans, &word_tokens, sentence);
    }

    // BPE/tokenizer mismatch — try character-level alignment.
    if let Some(aligned) = align_words_to_tokens(&words, &word_spans, &word_tokens, sentence) {
        return Ok(aligned);
    }

    // Alignment failed (text mismatch) — caller falls back to estimation.
    Ok(vec![])
}

/// Direct 1:1 mapping when whisper word count equals app token count.
fn extract_direct(
    words: &[MergedWord],
    spans: &[(u64, u64)],
    tokens: &[&SubtitleToken],
    sentence: &SubtitleSentence,
) -> Result<Vec<WordTiming>, ExtractError> {
    let mut timings = Vec::with_capacity(words.len());
    for (word, (token, &(start_ms, end_ms))) in words.iter().zip(tokens.iter().zip(spans.iter())) {
        if start_ms > end_ms || end_ms < sentence.start.get() || start_ms > sentence.end.get() {
            return Ok(vec![]);
        }

        timings.push(WordTiming {
            sentence_id: sentence.id.clone(),
            token_index: token.index,
            text: token.text.clone(),
            start_ms: start_ms.max(sentence.start.get()),
            end_ms: end_ms.min(sentence.end.get()),
            confidence: word.mean_confidence,
            timing_source: TimingSource::AsrReported,
            provider_id: "whisper.cpp".into(),
            provider_version: "dtw-v2".into(),
        });
    }

    for pair in timings.windows(2) {
        if pair[0].end_ms > pair[1].start_ms {
            return Ok(vec![]);
        }
    }

    Ok(timings)
}

/// Resolve DTW centisecond timestamps to millisecond (start, end) spans.
fn resolve_time_spans(words: &[MergedWord], sentence_end_ms: u64) -> Vec<(u64, u64)> {
    words
        .iter()
        .enumerate()
        .map(|(i, word)| {
            let start_ms = (word.start_t_dtw * 10) as u64;
            let next_start_ms = words
                .get(i + 1)
                .map(|next| (next.start_t_dtw * 10) as u64)
                .unwrap_or(sentence_end_ms);
            let end_ms = ((word.end_t_dtw * 10) as u64)
                .saturating_add(DTW_TOKEN_DURATION_MS)
                .min(next_start_ms);
            (start_ms, end_ms)
        })
        .collect()
}

/// Character-level time interpolation: distributes whisper BPE timing across
/// app tokenizer tokens by mapping each character to its proportional time
/// slice within its source BPE word.
///
/// Returns `None` if the concatenated texts don't match (case-insensitive),
/// meaning the two tokenizations are over different text and alignment is
/// impossible.
fn align_words_to_tokens(
    words: &[MergedWord],
    spans: &[(u64, u64)],
    target_tokens: &[&SubtitleToken],
    sentence: &SubtitleSentence,
) -> Option<Vec<WordTiming>> {
    let source_text: String = words.iter().map(|w| w.text.as_str()).collect();
    let target_text: String = target_tokens.iter().map(|t| t.text.as_str()).collect();

    if !texts_match_for_alignment(&source_text, &target_text) {
        return None;
    }

    let char_times = build_character_times(words, spans);
    if char_times.is_empty() {
        return None;
    }

    let mut source_pos = 0;
    let mut timings = Vec::with_capacity(target_tokens.len());

    for token in target_tokens {
        let char_count = token.text.chars().count();
        if char_count == 0 || source_pos + char_count > char_times.len() {
            return None;
        }

        let start_ms = char_times[source_pos].0;
        let end_ms = char_times[source_pos + char_count - 1].1;

        timings.push(WordTiming {
            sentence_id: sentence.id.clone(),
            token_index: token.index,
            text: token.text.clone(),
            start_ms: start_ms.max(sentence.start.get()),
            end_ms: end_ms.min(sentence.end.get()),
            confidence: Some(0.65),
            timing_source: TimingSource::AsrAligned,
            provider_id: "whisper.cpp".into(),
            provider_version: "dtw-aligned-v1".into(),
        });

        source_pos += char_count;
    }

    for pair in timings.windows(2) {
        if pair[0].end_ms > pair[1].start_ms {
            return None;
        }
    }

    Some(timings)
}

/// Build per-character (start_ms, end_ms) by distributing each source word's
/// time span evenly across its characters.
fn build_character_times(words: &[MergedWord], spans: &[(u64, u64)]) -> Vec<(u64, u64)> {
    let mut times = Vec::new();
    for (word, &(start_ms, end_ms)) in words.iter().zip(spans) {
        let n = word.text.chars().count().max(1) as u64;
        let duration = end_ms.saturating_sub(start_ms);
        for i in 0..word.text.chars().count() {
            let i = i as u64;
            times.push((
                start_ms + duration * i / n,
                start_ms + duration * (i + 1) / n,
            ));
        }
    }
    times
}

/// Compare source and target character sequences for alignment eligibility.
/// Case-insensitive to tolerate whisper capitalization differences.
fn texts_match_for_alignment(source: &str, target: &str) -> bool {
    let s: String = source.chars().flat_map(char::to_lowercase).collect();
    let t: String = target.chars().flat_map(char::to_lowercase).collect();
    s == t
}

/// Public re-export for use by the transcription pipeline and lltimeline
/// import when source word timings need re-alignment to a different
/// tokenization.
pub fn align_timings_to_tokens(
    source_segments: &[(String, u64, u64)],
    target_tokens: &[SubtitleToken],
    sentence: &SubtitleSentence,
) -> Option<Vec<WordTiming>> {
    let words: Vec<MergedWord> = source_segments
        .iter()
        .map(|(text, start_ms, end_ms)| {
            let start_cs = (*start_ms / 10) as i64;
            let end_cs = (*end_ms / 10) as i64;
            MergedWord {
                text: text.clone(),
                start_t_dtw: start_cs,
                end_t_dtw: end_cs,
                mean_confidence: None,
            }
        })
        .collect();

    let word_tokens: Vec<&SubtitleToken> = target_tokens
        .iter()
        .filter(|t| t.kind == SubtitleTokenKind::Word)
        .collect();

    if words.is_empty() || word_tokens.is_empty() {
        return None;
    }

    let spans: Vec<(u64, u64)> = source_segments
        .iter()
        .map(|(_, start, end)| (*start, *end))
        .collect();

    align_words_to_tokens(&words, &spans, &word_tokens, sentence)
}

#[derive(Debug)]
struct MergedWord {
    text: String,
    start_t_dtw: i64,
    end_t_dtw: i64,
    mean_confidence: Option<f32>,
}

/// Merge whisper subword tokens into words.
///
/// A token that starts with whitespace (or is the first token) begins a new word.
/// Tokens without leading whitespace append to the current word.
/// Punctuation-only and special tokens are ignored so they cannot consume an
/// audible pause after the preceding lexical word.
fn merge_tokens_to_words(tokens: &[WhisperToken]) -> Vec<MergedWord> {
    let mut words: Vec<MergedWord> = Vec::new();

    for token in tokens {
        if !token.is_lexical() {
            continue;
        }
        let trimmed = token.text.trim_start();
        let is_new_word =
            token.text.starts_with(' ') || token.text.starts_with('\n') || words.is_empty();

        if is_new_word {
            words.push(MergedWord {
                text: trimmed.to_string(),
                start_t_dtw: token.t_dtw,
                end_t_dtw: token.t_dtw,
                mean_confidence: token.confidence(),
            });
        } else if let Some(current) = words.last_mut() {
            current.text.push_str(trimmed);
            current.end_t_dtw = token.t_dtw;
            if let Some(conf) = token.confidence() {
                current.mean_confidence = Some(
                    current
                        .mean_confidence
                        .map_or(conf, |existing| (existing + conf) / 2.0),
                );
            }
        }
    }

    // Remove words where DTW was unavailable.
    words.retain(|w| w.start_t_dtw >= 0 && w.end_t_dtw >= 0);

    words
}

impl WhisperToken {
    fn is_special(&self) -> bool {
        (self.text.starts_with("[_") && self.text.ends_with("_]"))
            || self.text.starts_with("[_TT_")
            || (self.text.starts_with("<|") && self.text.ends_with("|>"))
    }

    fn is_lexical(&self) -> bool {
        !self.is_special()
            && self
                .text
                .trim()
                .chars()
                .any(|value| value.is_alphanumeric() || value == '\'')
    }

    fn confidence(&self) -> Option<f32> {
        None // whisper.cpp DTW tokens don't include per-token confidence
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ExtractError {
    #[error("JSON parse error: {0}")]
    Json(String),
    #[error("segment count mismatch: JSON has {json}, sentences have {sentences}")]
    SegmentCountMismatch { json: usize, sentences: usize },
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs};

    fn sentence(id: &str, start: u64, end: u64, words: &[&str]) -> SubtitleSentence {
        let mut char_offset = 0u32;
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index: 0,
            start: TimeMs::new(start),
            end: TimeMs::new(end),
            original_text: words.join(" "),
            display_text: words.join(" "),
            tokens: words
                .iter()
                .enumerate()
                .map(|(i, text)| {
                    let start_char = char_offset;
                    let len = text.chars().count() as u32;
                    char_offset += len;
                    SubtitleToken {
                        index: i as u32,
                        kind: SubtitleTokenKind::Word,
                        text: text.to_string(),
                        normalized: Some(text.to_lowercase()),
                        start_char,
                        end_char: start_char + len,
                    }
                })
                .collect(),
        }
    }

    fn chinese_sentence(id: &str, start: u64, end: u64, words: &[&str]) -> SubtitleSentence {
        let mut char_offset = 0u32;
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index: 0,
            start: TimeMs::new(start),
            end: TimeMs::new(end),
            original_text: words.join(""),
            display_text: words.join(""),
            tokens: words
                .iter()
                .enumerate()
                .map(|(i, text)| {
                    let start_char = char_offset;
                    let len = text.chars().count() as u32;
                    char_offset += len;
                    SubtitleToken {
                        index: i as u32,
                        kind: SubtitleTokenKind::Word,
                        text: text.to_string(),
                        normalized: Some(text.to_string()),
                        start_char,
                        end_char: start_char + len,
                    }
                })
                .collect(),
        }
    }

    #[test]
    fn merges_subword_tokens_to_words() {
        let tokens = vec![
            WhisperToken {
                text: " Hello".into(),
                t_dtw: 100,
            },
            WhisperToken {
                text: " world".into(),
                t_dtw: 200,
            },
        ];
        let words = merge_tokens_to_words(&tokens);
        assert_eq!(words.len(), 2);
        assert_eq!(words[0].text, "Hello");
        assert_eq!(words[0].start_t_dtw, 100);
        assert_eq!(words[0].end_t_dtw, 100);
        assert_eq!(words[1].text, "world");
        assert_eq!(words[1].start_t_dtw, 200);
        assert_eq!(words[1].end_t_dtw, 200);
    }

    #[test]
    fn appends_continuation_tokens_to_word() {
        let tokens = vec![
            WhisperToken {
                text: " play".into(),
                t_dtw: 100,
            },
            WhisperToken {
                text: "ing".into(),
                t_dtw: 120,
            },
            WhisperToken {
                text: " games".into(),
                t_dtw: 140,
            },
        ];
        let words = merge_tokens_to_words(&tokens);
        assert_eq!(words.len(), 2);
        assert_eq!(words[0].text, "playing");
        assert_eq!(words[0].start_t_dtw, 100);
        assert_eq!(words[0].end_t_dtw, 120);
        assert_eq!(words[1].text, "games");
        assert_eq!(words[1].start_t_dtw, 140);
        assert_eq!(words[1].end_t_dtw, 140);
    }

    #[test]
    fn punctuation_does_not_extend_previous_word() {
        let tokens = vec![
            WhisperToken {
                text: " hello".into(),
                t_dtw: 100,
            },
            WhisperToken {
                text: ",".into(),
                t_dtw: 180,
            },
            WhisperToken {
                text: " again".into(),
                t_dtw: 220,
            },
        ];
        let words = merge_tokens_to_words(&tokens);
        assert_eq!(words.len(), 2);
        assert_eq!(words[0].end_t_dtw, 100);
        assert_eq!(words[1].start_t_dtw, 220);
    }

    #[test]
    fn filters_t_dtw_unavailable() {
        let tokens = vec![
            WhisperToken {
                text: " Hello".into(),
                t_dtw: -1,
            },
            WhisperToken {
                text: " world".into(),
                t_dtw: 200,
            },
        ];
        let words = merge_tokens_to_words(&tokens);
        assert_eq!(words.len(), 1);
        assert_eq!(words[0].start_t_dtw, 200);
    }

    #[test]
    fn fallback_on_count_mismatch_now_aligns_when_text_matches() {
        let seg = WhisperSegment {
            text: "hello world".into(),
            tokens: vec![
                WhisperToken {
                    text: " hello".into(),
                    t_dtw: 100,
                },
                WhisperToken {
                    text: " world".into(),
                    t_dtw: 200,
                },
            ],
        };
        // Sentence only has 1 word token → text mismatch → still empty.
        let sentence = sentence("s1", 0, 5000, &["hello"]);
        let result = extract_sentence_word_timings(&seg, &sentence).unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn chinese_bpe_alignment() {
        // Whisper BPE: "因为我" as one token, "不知道" as another
        // App jieba:   "因为" + "我" + "不" + "知道"
        let seg = WhisperSegment {
            text: "因为我不知道".into(),
            tokens: vec![
                WhisperToken {
                    text: "因为我".into(),
                    t_dtw: 100, // 1000ms
                },
                WhisperToken {
                    text: "不知道".into(),
                    t_dtw: 400, // 4000ms
                },
            ],
        };
        let sentence = chinese_sentence("s1", 0, 8000, &["因为", "我", "不", "知道"]);
        let result = extract_sentence_word_timings(&seg, &sentence).unwrap();

        assert_eq!(result.len(), 4);
        assert_eq!(result[0].text, "因为");
        assert_eq!(result[1].text, "我");
        assert_eq!(result[2].text, "不");
        assert_eq!(result[3].text, "知道");

        // "因为我" spans 1000ms..4080ms (clamped by next word start=4000ms)
        // 3 chars → each ~1000ms
        // "因为" = chars 0,1 → 1000..~2333ms
        // "我" = char 2 → ~2333..~3000ms (clamped to 4000ms since it's the span's last char group)
        assert_eq!(result[0].timing_source, TimingSource::AsrAligned);
        assert_eq!(result[0].provider_version, "dtw-aligned-v1");

        // Verify monotonicity
        for pair in result.windows(2) {
            assert!(pair[0].end_ms <= pair[1].start_ms);
        }
    }

    #[test]
    fn english_direct_mapping_unchanged() {
        // English BPE ≈ whitespace, so 1:1 mapping still works.
        let seg = WhisperSegment {
            text: " Hello world".into(),
            tokens: vec![
                WhisperToken {
                    text: " Hello".into(),
                    t_dtw: 100,
                },
                WhisperToken {
                    text: " world".into(),
                    t_dtw: 200,
                },
            ],
        };
        let sentence = sentence("s1", 0, 5000, &["Hello", "world"]);
        let result = extract_sentence_word_timings(&seg, &sentence).unwrap();

        assert_eq!(result.len(), 2);
        assert_eq!(result[0].text, "Hello");
        assert_eq!(result[1].text, "world");
        assert_eq!(result[0].timing_source, TimingSource::AsrReported);
        assert_eq!(result[0].provider_version, "dtw-v2");
    }

    #[test]
    fn alignment_returns_none_on_text_mismatch() {
        assert!(!texts_match_for_alignment("hello", "world"));
        assert!(texts_match_for_alignment("Hello", "hello"));
        assert!(texts_match_for_alignment("因为我", "因为我"));
    }

    #[test]
    fn character_times_distributes_evenly() {
        let words = vec![MergedWord {
            text: "因为我".into(),
            start_t_dtw: 100,
            end_t_dtw: 100,
            mean_confidence: None,
        }];
        let spans = vec![(1000u64, 4000u64)];
        let times = build_character_times(&words, &spans);
        assert_eq!(times.len(), 3);
        assert_eq!(times[0], (1000, 2000));
        assert_eq!(times[1], (2000, 3000));
        assert_eq!(times[2], (3000, 4000));
    }

    #[test]
    fn public_align_timings_to_tokens() {
        let source = vec![
            ("因为我".to_string(), 1000u64, 4000u64),
            ("不知道".to_string(), 4000u64, 7000u64),
        ];
        let sentence = chinese_sentence("s1", 0, 8000, &["因为", "我", "不", "知道"]);
        let target_tokens: Vec<SubtitleToken> = sentence
            .tokens
            .iter()
            .filter(|t| t.kind == SubtitleTokenKind::Word)
            .cloned()
            .collect();
        let result = align_timings_to_tokens(&source, &target_tokens, &sentence);
        assert!(result.is_some());
        let timings = result.unwrap();
        assert_eq!(timings.len(), 4);
        assert_eq!(timings[0].text, "因为");
        assert_eq!(timings[1].text, "我");
        assert_eq!(timings[2].text, "不");
        assert_eq!(timings[3].text, "知道");
    }
}
