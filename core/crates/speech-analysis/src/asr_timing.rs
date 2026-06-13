use domain::{SubtitleSentence, SubtitleTokenKind, TimingSource, WordTiming};
use serde::Deserialize;

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

    // Merge lexical subword tokens into words by splitting on leading whitespace.
    let words = merge_tokens_to_words(&seg.tokens);

    if words.len() != word_tokens.len()
        || words
            .iter()
            .zip(word_tokens.iter())
            .any(|(word, token)| canonical_word(&word.text) != canonical_word(&token.text))
    {
        // Never map timestamps by position when the lexical words disagree.
        return Ok(vec![]);
    }

    let Some(boundaries) = word_boundaries(&words, sentence) else {
        return Ok(vec![]);
    };

    let mut timings = Vec::with_capacity(words.len());
    for (index, (word, token)) in words.iter().zip(word_tokens.iter()).enumerate() {
        timings.push(WordTiming {
            sentence_id: sentence.id.clone(),
            token_index: token.index,
            text: token.text.clone(),
            start_ms: boundaries[index],
            end_ms: boundaries[index + 1],
            confidence: word.mean_confidence,
            timing_source: TimingSource::AsrReported,
            provider_id: "whisper.cpp".into(),
            provider_version: "dtw-v1".into(),
        });
    }

    Ok(timings)
}

#[derive(Debug)]
struct MergedWord {
    text: String,
    start_t_dtw: i64,
    mean_confidence: Option<f32>,
}

/// Merge whisper subword tokens into words.
///
/// A token that starts with whitespace (or is the first token) begins a new word.
/// Tokens without leading whitespace append to the current word.
/// Special, punctuation-only, and unavailable-DTW tokens are ignored. Ignoring
/// an unavailable lexical token causes the later text/count check to reject the
/// sentence instead of shifting timestamps onto the wrong word.
fn merge_tokens_to_words(tokens: &[WhisperToken]) -> Vec<MergedWord> {
    let mut words: Vec<MergedWord> = Vec::new();

    for token in tokens {
        if token.t_dtw < 0 || token.is_special() || !token.text.chars().any(char::is_alphanumeric) {
            continue;
        }

        let is_new_word =
            token.text.starts_with(' ') || token.text.starts_with('\n') || words.is_empty();

        if is_new_word {
            words.push(MergedWord {
                text: token.text.trim_start().to_owned(),
                start_t_dtw: token.t_dtw,
                mean_confidence: token.confidence(),
            });
        } else if let Some(current) = words.last_mut() {
            current.text.push_str(&token.text);
            if let Some(conf) = token.confidence() {
                current.mean_confidence = Some(
                    current
                        .mean_confidence
                        .map_or(conf, |existing| (existing + conf) / 2.0),
                );
            }
        }
    }

    words
}

impl WhisperToken {
    fn is_special(&self) -> bool {
        (self.text.starts_with("[_") && self.text.ends_with("_]"))
            || (self.text.starts_with("<|") && self.text.ends_with("|>"))
    }

    fn confidence(&self) -> Option<f32> {
        None // whisper.cpp DTW tokens don't include per-token confidence
    }
}

fn canonical_word(value: &str) -> String {
    value
        .chars()
        .filter_map(|ch| {
            if ch.is_alphanumeric() {
                Some(ch.to_lowercase().collect::<String>())
            } else if matches!(ch, '\'' | '’' | '-') {
                Some(if ch == '’' {
                    "'".into()
                } else {
                    ch.to_string()
                })
            } else {
                None
            }
        })
        .collect()
}

/// Converts DTW point timestamps into non-empty half-open word intervals.
///
/// Each word starts at its first lexical subword's DTW timestamp and ends at
/// the next word's start. The final word ends at the subtitle sentence end.
/// Repeated DTW points are separated by one millisecond so every word can be
/// selected by the desktop's `[start, end)` lookup.
fn word_boundaries(words: &[MergedWord], sentence: &SubtitleSentence) -> Option<Vec<u64>> {
    if words.is_empty() {
        return Some(vec![]);
    }

    let sentence_start = sentence.start.get();
    let sentence_end = sentence.end.get();
    if sentence_end.saturating_sub(sentence_start) < words.len() as u64 {
        return None;
    }

    let mut boundaries = Vec::with_capacity(words.len() + 1);
    for word in words {
        let start_ms = u64::try_from(word.start_t_dtw).ok()?.checked_mul(10)?;
        if start_ms > sentence_end {
            return None;
        }
        boundaries.push(start_ms.max(sentence_start));
    }
    if boundaries.windows(2).any(|pair| pair[0] > pair[1]) {
        return None;
    }

    for index in 1..boundaries.len() {
        boundaries[index] = boundaries[index].max(boundaries[index - 1].checked_add(1)?);
    }

    if boundaries.last().is_some_and(|last| *last >= sentence_end) {
        let mut next = sentence_end;
        for boundary in boundaries.iter_mut().rev() {
            next = next.checked_sub(1)?;
            *boundary = (*boundary).min(next);
        }
        if boundaries[0] < sentence_start {
            return None;
        }
    }

    boundaries.push(sentence_end);
    Some(boundaries)
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
                .map(|(i, text)| SubtitleToken {
                    index: i as u32,
                    kind: SubtitleTokenKind::Word,
                    text: text.to_string(),
                    normalized: Some(text.to_lowercase()),
                    start_char: 0,
                    end_char: text.len() as u32,
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
        assert_eq!(words[1].text, "world");
        assert_eq!(words[1].start_t_dtw, 200);
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
        // "playing" is one word, "games" is another
        assert_eq!(words.len(), 2);
        assert_eq!(words[0].text, "playing");
        assert_eq!(words[0].start_t_dtw, 100);
        assert_eq!(words[1].start_t_dtw, 140);
    }

    #[test]
    fn ignores_special_and_unavailable_tokens_without_corrupting_last_word() {
        let tokens = vec![
            WhisperToken {
                text: "[_BEG_]".into(),
                t_dtw: -1,
            },
            WhisperToken {
                text: " Hello".into(),
                t_dtw: 200,
            },
            WhisperToken {
                text: ".".into(),
                t_dtw: 300,
            },
            WhisperToken {
                text: "[_TT_100]".into(),
                t_dtw: -1,
            },
        ];
        let words = merge_tokens_to_words(&tokens);
        assert_eq!(words.len(), 1);
        assert_eq!(words[0].text, "Hello");
        assert_eq!(words[0].start_t_dtw, 200);
    }

    #[test]
    fn fallback_on_count_mismatch() {
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
        // Sentence only has 1 word token → mismatch → empty result
        let sentence = sentence("s1", 0, 1000, &["hello"]); // only 1 word
        let result = extract_sentence_word_timings(&seg, &sentence).unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn creates_non_empty_intervals_for_repeated_dtw_points() {
        let words = vec![
            MergedWord {
                text: "ask".into(),
                start_t_dtw: 420,
                mean_confidence: None,
            },
            MergedWord {
                text: "not".into(),
                start_t_dtw: 420,
                mean_confidence: None,
            },
            MergedWord {
                text: "what".into(),
                start_t_dtw: 556,
                mean_confidence: None,
            },
        ];
        let sentence = sentence("s1", 0, 8000, &["ask", "not", "what"]);

        assert_eq!(
            word_boundaries(&words, &sentence),
            Some(vec![4200, 4201, 5560, 8000])
        );
    }

    #[test]
    fn falls_back_when_merged_text_does_not_match_sentence_tokens() {
        let seg = WhisperSegment {
            text: "hello there".into(),
            tokens: vec![
                WhisperToken {
                    text: " hello".into(),
                    t_dtw: 10,
                },
                WhisperToken {
                    text: " there".into(),
                    t_dtw: 20,
                },
            ],
        };
        let sentence = sentence("s1", 0, 1000, &["hello", "world"]);

        assert!(
            extract_sentence_word_timings(&seg, &sentence)
                .unwrap()
                .is_empty()
        );
    }
}
