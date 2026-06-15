use domain::{SubtitleSentence, SubtitleTokenKind, TimingSource, WordTiming};
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

    // Merge subword tokens into words by splitting on leading whitespace.
    let words = merge_tokens_to_words(&seg.tokens);

    if words.len() != word_tokens.len() {
        // Mismatch between whisper word count and subtitle token count.
        // Fall back to estimation for this sentence.
        return Ok(vec![]);
    }

    let mut timings = Vec::with_capacity(words.len());
    for (position, (word, token)) in words.iter().zip(word_tokens.iter()).enumerate() {
        let start_ms = (word.start_t_dtw * 10) as u64;
        let next_start_ms = words
            .get(position + 1)
            .map(|next| (next.start_t_dtw * 10) as u64)
            .unwrap_or_else(|| sentence.end.get());
        let end_ms = ((word.end_t_dtw * 10) as u64)
            .saturating_add(DTW_TOKEN_DURATION_MS)
            .min(next_start_ms);

        if start_ms > end_ms || end_ms < sentence.start.get() || start_ms > sentence.end.get() {
            // Invalid timing — skip this sentence.
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

    // Validate monotonicity.
    for pair in timings.windows(2) {
        if pair[0].end_ms > pair[1].start_ms {
            return Ok(vec![]);
        }
    }

    Ok(timings)
}

#[derive(Debug)]
struct MergedWord {
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
        let is_new_word =
            token.text.starts_with(' ') || token.text.starts_with('\n') || words.is_empty();

        if is_new_word {
            words.push(MergedWord {
                start_t_dtw: token.t_dtw,
                end_t_dtw: token.t_dtw,
                mean_confidence: token.confidence(),
            });
        } else if let Some(current) = words.last_mut() {
            // Append subword token to the current word.
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
    fn is_lexical(&self) -> bool {
        self.text
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
        assert_eq!(words[0].start_t_dtw, 100);
        assert_eq!(words[0].end_t_dtw, 100);
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
        // "playing" is one word, "games" is another
        assert_eq!(words.len(), 2);
        assert_eq!(words[0].start_t_dtw, 100);
        assert_eq!(words[0].end_t_dtw, 120); // "ing" end
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
}
