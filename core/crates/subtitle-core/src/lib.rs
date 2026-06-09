use domain::{
    LanguageCode, MediaId, SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind,
    SubtitleTrack, SubtitleTrackId, TimeMs, normalize_lemma,
};
use sha2::{Digest, Sha256};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubtitleFormat {
    Srt,
    WebVtt,
}

impl SubtitleFormat {
    pub fn from_name(name: &str) -> Result<Self, SubtitleError> {
        match name
            .rsplit('.')
            .next()
            .unwrap_or_default()
            .to_ascii_lowercase()
            .as_str()
        {
            "srt" => Ok(Self::Srt),
            "vtt" | "webvtt" => Ok(Self::WebVtt),
            _ => Err(SubtitleError::UnsupportedFormat(name.to_owned())),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ImportSubtitle {
    pub media_id: MediaId,
    pub source_name: String,
    pub content: Vec<u8>,
    pub language: Option<LanguageCode>,
}

pub fn import(input: ImportSubtitle) -> Result<SubtitleTrack, SubtitleError> {
    let text = decode_text(&input.content)?;
    let format = SubtitleFormat::from_name(&input.source_name)?;
    let fingerprint = hex::encode(Sha256::digest(&input.content));
    let track_id = SubtitleTrackId::from_fingerprint(
        "subtitle-track",
        &format!("{}:{fingerprint}", input.media_id.as_str()),
    );
    let mut cues = match format {
        SubtitleFormat::Srt => parse_srt(&text)?,
        SubtitleFormat::WebVtt => parse_webvtt(&text)?,
    };
    cues.sort_by_key(|cue| (cue.start_ms, cue.end_ms));
    let sentences = cues
        .into_iter()
        .enumerate()
        .map(|(index, cue)| {
            let display_text = normalize_display(&cue.text);
            let sentence_id = SubtitleSentenceId::from_fingerprint(
                "subtitle-sentence",
                &format!(
                    "{}:{index}:{}:{}:{display_text}",
                    track_id.as_str(),
                    cue.start_ms,
                    cue.end_ms
                ),
            );
            SubtitleSentence {
                id: sentence_id,
                index: index as u32,
                start: TimeMs::new(cue.start_ms),
                end: TimeMs::new(cue.end_ms),
                original_text: cue.text,
                tokens: tokenize_english(&display_text),
                display_text,
            }
        })
        .collect();
    Ok(SubtitleTrack {
        id: track_id,
        media_id: input.media_id,
        fingerprint,
        language: input.language,
        source: input.source_name,
        sentences,
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Cue {
    start_ms: u64,
    end_ms: u64,
    text: String,
}

pub fn parse_srt(text: &str) -> Result<Vec<SubtitleSentenceDraft>, SubtitleError> {
    parse_blocks(text, false)
        .map(|cues| cues.into_iter().map(SubtitleSentenceDraft::from).collect())
}

pub fn parse_webvtt(text: &str) -> Result<Vec<SubtitleSentenceDraft>, SubtitleError> {
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let mut lines = text.lines();
    if !lines
        .next()
        .is_some_and(|line| line.trim_start().starts_with("WEBVTT"))
    {
        return Err(SubtitleError::Parse {
            line: 1,
            message: "missing WEBVTT header".into(),
        });
    }
    let body = lines.collect::<Vec<_>>().join("\n");
    parse_blocks(&body, true)
        .map(|cues| cues.into_iter().map(SubtitleSentenceDraft::from).collect())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubtitleSentenceDraft {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

impl From<Cue> for SubtitleSentenceDraft {
    fn from(value: Cue) -> Self {
        Self {
            start_ms: value.start_ms,
            end_ms: value.end_ms,
            text: value.text,
        }
    }
}

fn parse_blocks(text: &str, webvtt: bool) -> Result<Vec<Cue>, SubtitleError> {
    let normalized = text.replace("\r\n", "\n").replace('\r', "\n");
    let lines: Vec<&str> = normalized.lines().collect();
    let mut cues = Vec::new();
    let mut index = 0;
    while index < lines.len() {
        while index < lines.len() && lines[index].trim().is_empty() {
            index += 1;
        }
        if index >= lines.len() {
            break;
        }
        if webvtt && (lines[index].starts_with("NOTE") || lines[index].starts_with("STYLE")) {
            while index < lines.len() && !lines[index].trim().is_empty() {
                index += 1;
            }
            continue;
        }
        if !lines[index].contains("-->") {
            index += 1;
        }
        if index >= lines.len() || !lines[index].contains("-->") {
            return Err(SubtitleError::Parse {
                line: index + 1,
                message: "expected cue timing".into(),
            });
        }
        let timing_line = index + 1;
        let (start_ms, end_ms) = parse_timing(lines[index], timing_line)?;
        index += 1;
        let mut body = Vec::new();
        while index < lines.len() && !lines[index].trim().is_empty() {
            body.push(if webvtt {
                strip_webvtt_tags(lines[index])
            } else {
                lines[index].to_owned()
            });
            index += 1;
        }
        if body.is_empty() {
            return Err(SubtitleError::Parse {
                line: timing_line,
                message: "cue text is empty".into(),
            });
        }
        cues.push(Cue {
            start_ms,
            end_ms,
            text: body.join("\n"),
        });
    }
    Ok(cues)
}

fn parse_timing(line: &str, line_number: usize) -> Result<(u64, u64), SubtitleError> {
    let (start, rest) = line.split_once("-->").ok_or_else(|| SubtitleError::Parse {
        line: line_number,
        message: "expected --> separator".into(),
    })?;
    let end = rest.split_whitespace().next().unwrap_or_default();
    let start = parse_timestamp(start.trim(), line_number)?;
    let end = parse_timestamp(end.trim(), line_number)?;
    if end <= start {
        return Err(SubtitleError::Parse {
            line: line_number,
            message: "cue end must be after start".into(),
        });
    }
    Ok((start, end))
}

fn parse_timestamp(value: &str, line: usize) -> Result<u64, SubtitleError> {
    let value = value.replace(',', ".");
    let parts: Vec<&str> = value.split(':').collect();
    let (hours, minutes, seconds) = match parts.as_slice() {
        [minutes, seconds] => (0, parse_number(minutes, line)?, *seconds),
        [hours, minutes, seconds] => (
            parse_number(hours, line)?,
            parse_number(minutes, line)?,
            *seconds,
        ),
        _ => return Err(timestamp_error(line)),
    };
    let (seconds, millis) = seconds
        .split_once('.')
        .ok_or_else(|| timestamp_error(line))?;
    let seconds = parse_number(seconds, line)?;
    let millis = match millis.len() {
        1 => parse_number(millis, line)? * 100,
        2 => parse_number(millis, line)? * 10,
        3 => parse_number(millis, line)?,
        _ => return Err(timestamp_error(line)),
    };
    if minutes >= 60 || seconds >= 60 {
        return Err(timestamp_error(line));
    }
    Ok(((hours * 60 + minutes) * 60 + seconds) * 1000 + millis)
}

fn parse_number(value: &str, line: usize) -> Result<u64, SubtitleError> {
    value.parse().map_err(|_| timestamp_error(line))
}

fn timestamp_error(line: usize) -> SubtitleError {
    SubtitleError::Parse {
        line,
        message: "invalid timestamp".into(),
    }
}

fn strip_webvtt_tags(value: &str) -> String {
    let mut output = String::new();
    let mut in_tag = false;
    for ch in value.chars() {
        match ch {
            '<' => in_tag = true,
            '>' if in_tag => in_tag = false,
            _ if !in_tag => output.push(ch),
            _ => {}
        }
    }
    output
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
}

pub fn normalize_display(value: &str) -> String {
    value.replace("\r\n", "\n").replace('\r', "\n")
}

pub fn tokenize_english(value: &str) -> Vec<SubtitleToken> {
    let chars: Vec<char> = value.chars().collect();
    let mut tokens = Vec::new();
    let mut start = 0;
    while start < chars.len() {
        let kind = token_kind(&chars, start);
        let mut end = start + 1;
        while end < chars.len() && token_kind(&chars, end) == kind {
            if kind == SubtitleTokenKind::Word && !continues_word(&chars, end) {
                break;
            }
            end += 1;
        }
        let text: String = chars[start..end].iter().collect();
        let normalized = (kind == SubtitleTokenKind::Word).then(|| normalize_lemma(&text));
        tokens.push(SubtitleToken {
            index: tokens.len() as u32,
            kind,
            text,
            normalized,
            start_char: start as u32,
            end_char: end as u32,
        });
        start = end;
    }
    tokens
}

fn token_kind(chars: &[char], index: usize) -> SubtitleTokenKind {
    let ch = chars[index];
    if ch.is_alphanumeric() || is_inner_word_mark(chars, index) {
        SubtitleTokenKind::Word
    } else if ch.is_whitespace() {
        SubtitleTokenKind::Whitespace
    } else if ch.is_ascii_punctuation() || matches!(ch, '…' | '“' | '”' | '‘' | '’' | '—' | '–')
    {
        SubtitleTokenKind::Punctuation
    } else {
        SubtitleTokenKind::Other
    }
}

fn is_inner_word_mark(chars: &[char], index: usize) -> bool {
    matches!(chars[index], '\'' | '’' | '-')
        && index > 0
        && index + 1 < chars.len()
        && chars[index - 1].is_alphanumeric()
        && chars[index + 1].is_alphanumeric()
}

fn continues_word(chars: &[char], index: usize) -> bool {
    chars[index].is_alphanumeric() || is_inner_word_mark(chars, index)
}

pub struct Timeline<'a> {
    sentences: &'a [SubtitleSentence],
    offset_ms: i64,
}

impl<'a> Timeline<'a> {
    pub fn new(sentences: &'a [SubtitleSentence], offset_ms: i64) -> Self {
        Self {
            sentences,
            offset_ms,
        }
    }

    pub fn current(&self, media_position_ms: u64) -> Option<&'a SubtitleSentence> {
        let subtitle_position = i128::from(media_position_ms) - i128::from(self.offset_ms);
        if subtitle_position < 0 {
            return None;
        }
        let position = subtitle_position as u64;
        let end = self
            .sentences
            .partition_point(|cue| cue.start.get() <= position);
        self.sentences[..end]
            .iter()
            .rev()
            .find(|cue| position < cue.end.get())
    }

    pub fn previous(&self, sentence_id: &SubtitleSentenceId) -> Option<&'a SubtitleSentence> {
        let index = self
            .sentences
            .iter()
            .position(|cue| &cue.id == sentence_id)?;
        index.checked_sub(1).and_then(|i| self.sentences.get(i))
    }

    pub fn next(&self, sentence_id: &SubtitleSentenceId) -> Option<&'a SubtitleSentence> {
        let index = self
            .sentences
            .iter()
            .position(|cue| &cue.id == sentence_id)?;
        self.sentences.get(index + 1)
    }

    pub fn media_start(&self, cue: &SubtitleSentence) -> u64 {
        (i128::from(cue.start.get()) + i128::from(self.offset_ms)).max(0) as u64
    }

    pub fn media_end(&self, cue: &SubtitleSentence) -> u64 {
        (i128::from(cue.end.get()) + i128::from(self.offset_ms)).max(0) as u64
    }
}

fn decode_text(content: &[u8]) -> Result<String, SubtitleError> {
    if content.starts_with(&[0xff, 0xfe]) {
        let units = content[2..]
            .chunks_exact(2)
            .map(|bytes| u16::from_le_bytes([bytes[0], bytes[1]]))
            .collect::<Vec<_>>();
        return String::from_utf16(&units).map_err(|_| SubtitleError::Encoding);
    }
    if content.starts_with(&[0xfe, 0xff]) {
        let units = content[2..]
            .chunks_exact(2)
            .map(|bytes| u16::from_be_bytes([bytes[0], bytes[1]]))
            .collect::<Vec<_>>();
        return String::from_utf16(&units).map_err(|_| SubtitleError::Encoding);
    }
    let content = content.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(content);
    String::from_utf8(content.to_vec()).map_err(|_| SubtitleError::Encoding)
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SubtitleError {
    #[error("unsupported subtitle format: {0}")]
    UnsupportedFormat(String),
    #[error("subtitle encoding must be UTF-8 or BOM-marked UTF-16")]
    Encoding,
    #[error("subtitle parse error at line {line}: {message}")]
    Parse { line: usize, message: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sentence(id: &str, start: u64, end: u64) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index: 0,
            start: TimeMs::new(start),
            end: TimeMs::new(end),
            original_text: id.into(),
            display_text: id.into(),
            tokens: vec![],
        }
    }

    #[test]
    fn parses_srt_and_vtt_fixtures() {
        let srt = include_str!("../../../testdata/subtitles/timeline.srt");
        let vtt = include_str!("../../../testdata/subtitles/timeline.vtt");
        assert_eq!(parse_srt(srt).unwrap().len(), 4);
        assert_eq!(parse_webvtt(vtt).unwrap().len(), 4);
    }

    #[test]
    fn tokenization_round_trips_and_handles_word_marks() {
        let text = "I can't re-enter 42.\nCafé — ok";
        let tokens = tokenize_english(text);
        assert_eq!(
            tokens
                .iter()
                .map(|token| token.text.as_str())
                .collect::<String>(),
            text
        );
        let words = tokens
            .iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word)
            .map(|token| token.text.as_str())
            .collect::<Vec<_>>();
        assert_eq!(words, ["I", "can't", "re-enter", "42", "Café", "ok"]);
    }

    #[test]
    fn timeline_handles_gaps_overlaps_boundaries_offset_and_navigation() {
        let cues = vec![
            sentence("a", 500, 2000),
            sentence("b", 1500, 2500),
            sentence("c", 3000, 4000),
        ];
        let timeline = Timeline::new(&cues, 100);
        assert!(timeline.current(500).is_none());
        assert_eq!(timeline.current(600).unwrap().id, cues[0].id);
        assert_eq!(timeline.current(1700).unwrap().id, cues[1].id);
        assert!(timeline.current(2600).is_none());
        assert_eq!(timeline.previous(&cues[1].id).unwrap().id, cues[0].id);
        assert_eq!(timeline.next(&cues[1].id).unwrap().id, cues[2].id);
        assert_eq!(timeline.media_start(&cues[0]), 600);
    }

    #[test]
    fn reports_parse_line() {
        let error = parse_srt("1\nbad timing\ntext").unwrap_err();
        assert!(error.to_string().contains("line 2"));
    }

    #[test]
    fn handles_large_timeline() {
        let cues = (0..2100)
            .map(|index| sentence(&format!("cue-{index}"), index * 1000, index * 1000 + 900))
            .collect::<Vec<_>>();
        let timeline = Timeline::new(&cues, 0);
        assert_eq!(timeline.current(2_099_500).unwrap().id, cues[2099].id);
        assert!(timeline.current(2_099_950).is_none());
    }

    #[test]
    fn imports_utf16_and_produces_stable_ids() {
        let text = "1\n00:00:00,000 --> 00:00:01,000\nHello\n";
        let mut utf16 = vec![0xff, 0xfe];
        for unit in text.encode_utf16() {
            utf16.extend(unit.to_le_bytes());
        }
        let input = || ImportSubtitle {
            media_id: MediaId::parse("media").unwrap(),
            source_name: "a.srt".into(),
            content: utf16.clone(),
            language: Some(LanguageCode::parse("en").unwrap()),
        };
        let first = import(input()).unwrap();
        let second = import(input()).unwrap();
        assert_eq!(first.id, second.id);
        assert_eq!(first.sentences[0].tokens[0].text, "Hello");
    }
}
