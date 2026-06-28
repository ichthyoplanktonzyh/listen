use domain::{
    LanguageCode, MediaId, SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind,
    SubtitleTrack, SubtitleTrackId, SubtitleTrackStatus, TimeMs, normalize_lemma,
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
    pub identity_salt: Option<String>,
}

pub fn import(input: ImportSubtitle) -> Result<SubtitleTrack, SubtitleError> {
    let text = decode_text(&input.content)?;
    let format = SubtitleFormat::from_name(&input.source_name)?;
    let fingerprint = hex::encode(Sha256::digest(
        [
            input.content.as_slice(),
            input.identity_salt.as_deref().unwrap_or("").as_bytes(),
        ]
        .concat(),
    ));
    let track_id = SubtitleTrackId::from_fingerprint(
        "subtitle-track",
        &format!("{}:{fingerprint}", input.media_id.as_str()),
    );
    let mut cues = match format {
        SubtitleFormat::Srt => parse_srt(&text)?,
        SubtitleFormat::WebVtt => parse_webvtt(&text)?,
    };
    cues.sort_by_key(|cue| (cue.start_ms, cue.end_ms));
    // Resolve the learning language for tokenization and storage. A caller-
    // declared language always wins; otherwise we detect it from the subtitle's
    // own script so a Chinese subtitle is segmented with the Chinese tokenizer
    // instead of the whitespace baseline (Phase 2.6 Step 4).
    let language = input
        .language
        .clone()
        .unwrap_or_else(|| detect_language(cues.iter().map(|cue| cue.text.as_str())));
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
                tokens: tokenize(Some(&language), &display_text),
                display_text,
            }
        })
        .collect();
    Ok(SubtitleTrack {
        id: track_id,
        media_id: input.media_id,
        fingerprint,
        language: Some(language),
        source: input.source_name,
        status: SubtitleTrackStatus::Available,
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

/// A language-specific tokenizer producing `SubtitleToken`s that preserve the
/// original character ranges. Per ADR 0012 the concrete tokenizer is selected
/// from the learning language's profile, so adding a language is a provider
/// choice rather than a special-case branch.
pub trait Tokenizer {
    fn tokenize(&self, text: &str) -> Vec<SubtitleToken>;
}

/// Default whitespace/Latin tokenizer — the English regression baseline.
pub struct WhitespaceTokenizer;

impl Tokenizer for WhitespaceTokenizer {
    fn tokenize(&self, text: &str) -> Vec<SubtitleToken> {
        tokenize_english(text)
    }
}

/// Mandarin tokenizer.
///
/// With the default `jieba` feature this uses jieba-rs word segmentation; with
/// `--no-default-features` it falls back to character-level segmentation (the
/// `zh` profile's declared fallback). Both preserve the original character span
/// of every segment and cover whitespace, punctuation and mixed CJK/Latin/number
/// runs. The concrete segmenter sits behind the `Tokenizer` trait, so swapping
/// it never touches the call site.
pub struct ChineseTokenizer {
    #[cfg(feature = "jieba")]
    jieba: jieba_rs::Jieba,
}

impl ChineseTokenizer {
    pub fn new() -> Self {
        Self {
            #[cfg(feature = "jieba")]
            jieba: jieba_rs::Jieba::new(),
        }
    }

    /// Split text into contiguous substrings whose concatenation is the input.
    fn segments<'t>(&self, text: &'t str) -> Vec<&'t str> {
        #[cfg(feature = "jieba")]
        {
            self.jieba.cut(text, true)
        }
        #[cfg(not(feature = "jieba"))]
        {
            char_level_segments(text)
        }
    }
}

impl Default for ChineseTokenizer {
    fn default() -> Self {
        Self::new()
    }
}

impl Tokenizer for ChineseTokenizer {
    fn tokenize(&self, text: &str) -> Vec<SubtitleToken> {
        build_segment_tokens(self.segments(text))
    }
}

/// Build `SubtitleToken`s from contiguous segments whose concatenation is the
/// original text, preserving each segment's character span. Shared by the Chinese
/// word segmenter and the `core.char` character tokenizer. The word-token
/// `normalized` set here is only a placeholder: the profile-aware [`tokenize`]
/// entry point re-derives it from the learning language's declared normalization,
/// so segmenters never bake in an English lemma assumption.
fn build_segment_tokens<'t>(segments: impl IntoIterator<Item = &'t str>) -> Vec<SubtitleToken> {
    let mut tokens = Vec::new();
    let mut char_pos: u32 = 0;
    for segment in segments {
        let seg_len = segment.chars().count() as u32;
        let start = char_pos;
        char_pos += seg_len;
        if seg_len == 0 {
            continue;
        }
        let kind = segment_kind(segment);
        let normalized = (kind == SubtitleTokenKind::Word).then(|| normalize_lemma(segment));
        tokens.push(SubtitleToken {
            index: tokens.len() as u32,
            kind,
            text: segment.to_string(),
            normalized,
            start_char: start,
            end_char: char_pos,
        });
    }
    tokens
}

/// Character-level tokenizer for the `core.char` strategy (e.g. the Japanese
/// baseline until a morphological-analysis provider lands). One unit per CJK
/// ideograph / mark; Latin/number/kana runs are grouped. Selecting it is a
/// profile choice — a language that declares `core.char` reuses this with no new
/// code, which is the whole point of routing tokenization through the profile.
pub struct CharacterTokenizer;

impl Tokenizer for CharacterTokenizer {
    fn tokenize(&self, text: &str) -> Vec<SubtitleToken> {
        build_segment_tokens(char_level_segments(text))
    }
}

/// Japanese tokenizer for the `ja.morphological` strategy.
///
/// Real morphological analysis (lindera surface morphemes) lands behind a
/// `lindera` feature; until then — and on the offline/no-default build — it
/// degrades to character-level segmentation (one unit per kanji/kana) rather than
/// collapsing a space-less sentence to one token. This mirrors how the Chinese
/// tokenizer degrades from jieba to characters. The analyzer sits behind the
/// `Tokenizer` trait, so promoting Japanese from the guard fixture to a real
/// language was a profile + provider choice, never a dispatch edit — which is the
/// property this exercise validates. Tokens are surface forms (surface identity);
/// base-form (辞書形) unification is a deferred normalization seam.
pub struct JapaneseTokenizer {
    #[cfg(feature = "lindera")]
    segmenter: lindera::segmenter::Segmenter,
}

impl JapaneseTokenizer {
    pub fn new() -> Self {
        Self {
            #[cfg(feature = "lindera")]
            segmenter: build_lindera_segmenter(),
        }
    }

    /// Split into contiguous substrings whose concatenation is the input. With
    /// the `lindera` feature this is morphological; otherwise character-level.
    fn segments<'t>(&self, text: &'t str) -> Vec<&'t str> {
        #[cfg(feature = "lindera")]
        {
            lindera_segments(&self.segmenter, text)
        }
        #[cfg(not(feature = "lindera"))]
        {
            char_level_segments(text)
        }
    }
}

impl Default for JapaneseTokenizer {
    fn default() -> Self {
        Self::new()
    }
}

impl Tokenizer for JapaneseTokenizer {
    fn tokenize(&self, text: &str) -> Vec<SubtitleToken> {
        build_segment_tokens(self.segments(text))
    }
}

#[cfg(feature = "lindera")]
fn build_lindera_segmenter() -> lindera::segmenter::Segmenter {
    use lindera::dictionary::{DictionaryKind, load_embedded_dictionary};
    use lindera::mode::Mode;
    use lindera::segmenter::Segmenter;
    let dictionary = load_embedded_dictionary(DictionaryKind::IPADIC)
        .expect("embedded IPADIC dictionary must load");
    Segmenter::new(Mode::Normal, dictionary, None)
}

/// Reconstruct contiguous segments from lindera token byte offsets so the output
/// concatenates back to the original text, covering any inter-token gaps (e.g.
/// spaces around embedded Latin). Falls back to character-level on analyzer error.
#[cfg(feature = "lindera")]
fn lindera_segments<'t>(segmenter: &lindera::segmenter::Segmenter, text: &'t str) -> Vec<&'t str> {
    let tokens = match segmenter.segment(std::borrow::Cow::Borrowed(text)) {
        Ok(tokens) => tokens,
        Err(_) => return char_level_segments(text),
    };
    let mut segments = Vec::new();
    let mut cursor = 0usize;
    for token in &tokens {
        let (start, end) = (token.byte_start, token.byte_end);
        if start > cursor {
            segments.push(&text[cursor..start]);
        }
        if end > start {
            segments.push(&text[start..end]);
        }
        cursor = cursor.max(end);
    }
    if cursor < text.len() {
        segments.push(&text[cursor..]);
    }
    segments
}

/// Character-level segmentation. CJK ideographs and standalone marks (including
/// Japanese kana, which fall outside the Han range) are emitted per character;
/// Latin/number and whitespace runs are grouped so embedded words stay whole.
/// Output substrings concatenate back to the original text. This backs both the
/// `core.char` tokenizer (e.g. the Japanese baseline) and the Chinese
/// `--no-default-features` word-segmentation fallback.
fn char_level_segments(text: &str) -> Vec<&str> {
    #[derive(PartialEq)]
    enum Class {
        Han,
        Wordish,
        Whitespace,
        Mark,
    }

    fn class_of(ch: char) -> Class {
        if ('\u{3400}'..='\u{9fff}').contains(&ch) || ('\u{f900}'..='\u{faff}').contains(&ch) {
            Class::Han
        } else if ch.is_whitespace() {
            Class::Whitespace
        } else if ch.is_alphanumeric() {
            Class::Wordish
        } else {
            Class::Mark
        }
    }

    let mut segments = Vec::new();
    let mut iter = text.char_indices().peekable();
    while let Some((start, ch)) = iter.next() {
        let class = class_of(ch);
        let mut end = start + ch.len_utf8();
        // Only Latin/number and whitespace runs are grouped; Han ideographs and
        // marks stay one character per segment.
        if class == Class::Wordish || class == Class::Whitespace {
            while let Some(&(next_start, next_ch)) = iter.peek() {
                if class_of(next_ch) == class {
                    end = next_start + next_ch.len_utf8();
                    iter.next();
                } else {
                    break;
                }
            }
        }
        segments.push(&text[start..end]);
    }
    segments
}

fn segment_kind(segment: &str) -> SubtitleTokenKind {
    if segment.chars().all(char::is_whitespace) {
        SubtitleTokenKind::Whitespace
    } else if segment.chars().all(is_punctuation_char) {
        SubtitleTokenKind::Punctuation
    } else if segment.chars().any(|ch| ch.is_alphanumeric()) {
        SubtitleTokenKind::Word
    } else {
        SubtitleTokenKind::Other
    }
}

fn is_punctuation_char(ch: char) -> bool {
    ch.is_ascii_punctuation()
        || matches!(
            ch,
            '…' | '“'
                | '”'
                | '‘'
                | '’'
                | '—'
                | '–'
                | '，'
                | '。'
                | '！'
                | '？'
                | '、'
                | '；'
                | '：'
                | '（'
                | '）'
                | '《'
                | '》'
                | '「'
                | '」'
                | '【'
                | '】'
        )
}

/// Tokenize subtitle display text with the tokenizer declared by the learning
/// language's profile, then re-derive each word token's normalized key from the
/// profile's declared normalization. Selection goes through [`tokenizer_for`] (a
/// strategy -> tokenizer registry), so a new language is a profile + provider
/// choice, never a branch here; an unknown or absent language degrades cleanly to
/// the whitespace baseline. Normalization is applied at this single profile-aware
/// seam rather than inside each segmenter, so English keeps lemma folding while
/// surface-form languages (Chinese, Japanese) are not silently lowercased.
pub fn tokenize(language: Option<&LanguageCode>, text: &str) -> Vec<SubtitleToken> {
    let profile = language.map(domain::profile_for);
    let strategy = profile
        .as_ref()
        .map(|profile| profile.tokenization.as_str())
        .unwrap_or("core.whitespace");
    let mut tokens = tokenizer_for(strategy).tokenize(text);
    if let Some(profile) = profile.as_ref() {
        for token in &mut tokens {
            if token.kind == SubtitleTokenKind::Word {
                token.normalized = Some(domain::baseline_normalized_key(
                    &profile.lexical_normalization,
                    &token.text,
                ));
            }
        }
    }
    tokens
}

/// Resolve the tokenizer for a profile's declared tokenization strategy. This is
/// the single strategy -> tokenizer registration point — the tokenizer analog of
/// `domain::profile_for` and dictionary-provider registration. A language that
/// reuses a declared strategy (`core.whitespace`, `zh.word_segmentation`,
/// `core.char`) needs no edit here; an unknown strategy degrades cleanly to the
/// whitespace baseline instead of silently collapsing space-less text.
fn tokenizer_for(strategy: &str) -> &'static dyn Tokenizer {
    match strategy {
        "zh.word_segmentation" => chinese_tokenizer(),
        "ja.morphological" => japanese_tokenizer(),
        "core.char" => character_tokenizer(),
        _ => whitespace_tokenizer(),
    }
}

fn whitespace_tokenizer() -> &'static WhitespaceTokenizer {
    static INSTANCE: std::sync::OnceLock<WhitespaceTokenizer> = std::sync::OnceLock::new();
    INSTANCE.get_or_init(|| WhitespaceTokenizer)
}

fn chinese_tokenizer() -> &'static ChineseTokenizer {
    static INSTANCE: std::sync::OnceLock<ChineseTokenizer> = std::sync::OnceLock::new();
    INSTANCE.get_or_init(ChineseTokenizer::new)
}

fn character_tokenizer() -> &'static CharacterTokenizer {
    static INSTANCE: std::sync::OnceLock<CharacterTokenizer> = std::sync::OnceLock::new();
    INSTANCE.get_or_init(|| CharacterTokenizer)
}

fn japanese_tokenizer() -> &'static JapaneseTokenizer {
    static INSTANCE: std::sync::OnceLock<JapaneseTokenizer> = std::sync::OnceLock::new();
    INSTANCE.get_or_init(JapaneseTokenizer::new)
}

/// Detect the learning language from subtitle text when the caller did not
/// declare one. This is the built-in language-identification seam, kept
/// deliberately small for the current acceptance set: kana settles Japanese
/// first (kana is unique to Japanese and disambiguates it from Chinese, which
/// shares the Han script), then any remaining Han routes to Chinese, and
/// everything else stays on the English/whitespace baseline. Han alone cannot
/// tell `zh` from `ja`, so script presence is not sufficient — a kana-bearing
/// line is Japanese even though it also contains kanji. Per ADR 0012 an
/// undetected script degrades cleanly to English; a richer provider-based
/// language identifier can replace this without changing callers.
fn detect_language<'a>(texts: impl IntoIterator<Item = &'a str>) -> LanguageCode {
    let mut has_han = false;
    for ch in texts.into_iter().flat_map(str::chars) {
        if is_kana(ch) {
            return LanguageCode::parse("ja").expect("detection codes are valid");
        }
        has_han |= is_han(ch);
    }
    let code = if has_han { "zh" } else { "en" };
    LanguageCode::parse(code).expect("detection codes are valid")
}

/// Kana code points (hiragana, katakana, and their phonetic / halfwidth blocks).
/// Kana never appears in Chinese, so its presence is a reliable Japanese signal.
fn is_kana(value: char) -> bool {
    matches!(value,
        '\u{3040}'..='\u{309f}'      // Hiragana
        | '\u{30a0}'..='\u{30ff}'    // Katakana
        | '\u{31f0}'..='\u{31ff}'    // Katakana Phonetic Extensions
        | '\u{ff66}'..='\u{ff9f}'    // Halfwidth Katakana
    )
}

fn is_han(value: char) -> bool {
    matches!(value,
        '\u{3400}'..='\u{4dbf}'      // CJK Unified Ideographs Extension A
        | '\u{4e00}'..='\u{9fff}'    // CJK Unified Ideographs
        | '\u{f900}'..='\u{faff}'    // CJK Compatibility Ideographs
        | '\u{20000}'..='\u{2a6df}'  // CJK Unified Ideographs Extension B
    )
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
            identity_salt: None,
        };
        let first = import(input()).unwrap();
        let second = import(input()).unwrap();
        assert_eq!(first.id, second.id);
        assert_eq!(first.sentences[0].tokens[0].text, "Hello");
    }

    // ── Property-based tests ───────────────────────────────────────

    mod proptests {
        use super::*;
        use proptest::prelude::*;

        proptest! {
            /// normalize_display is idempotent: applying it twice yields the
            /// same result as applying it once.
            #[test]
            fn prop_normalize_display_idempotent(s in "\\PC*") {
                let once = normalize_display(&s);
                let twice = normalize_display(&once);
                prop_assert_eq!(&once, &twice);
            }

            /// normalize_display never panics on any input.
            #[test]
            fn prop_normalize_display_no_panic(s in "\\PC*") {
                let _ = normalize_display(&s);
            }

            /// tokenize_english: word tokens always have normalized form.
            #[test]
            fn prop_tokenize_word_tokens_have_normalized(
                s in "[a-zA-Z '.,!?-]{0,200}",
            ) {
                let tokens = tokenize_english(&s);
                // Verify round-trip: concatenated texts match original
                let reconstructed: String = tokens
                    .iter()
                    .map(|t| t.text.as_str())
                    .collect();
                prop_assert_eq!(&reconstructed, &s,
                    "tokenization does not round-trip");
                // Every word token has Some normalized form
                for token in &tokens {
                    if token.kind == SubtitleTokenKind::Word {
                        prop_assert!(token.normalized.is_some(),
                            "word token {:?} missing normalized form", token.text);
                    }
                }
            }

            /// parse_srt: never panics on any input.
            #[test]
            fn prop_parse_srt_no_panic(s in "\\PC*") {
                let _ = parse_srt(&s);
            }

            /// parse_webvtt: never panics on any input.
            #[test]
            fn prop_parse_webvtt_no_panic(s in "\\PC*") {
                let _ = parse_webvtt(&s);
            }

            /// parse_srt: valid SRT draft entries have required fields.
            #[test]
            fn prop_parse_srt_sentence_count(
                s in "[0-9\n:,> \r\na-zA-Z-]{0,500}",
            ) {
                if let Ok(drafts) = parse_srt(&s) {
                    for draft in &drafts {
                        prop_assert!(!draft.text.is_empty());
                        prop_assert!(draft.start_ms <= draft.end_ms);
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod language_tokenize_tests {
    use super::*;

    fn lang(code: &str) -> LanguageCode {
        LanguageCode::parse(code).unwrap()
    }

    fn is_han(ch: char) -> bool {
        ('\u{4e00}'..='\u{9fff}').contains(&ch)
    }

    fn word_texts(tokens: &[SubtitleToken]) -> Vec<String> {
        tokens
            .iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word)
            .map(|token| token.text.clone())
            .collect()
    }

    #[test]
    fn chinese_is_segmented_not_one_word_token() {
        let tokens = tokenize(Some(&lang("zh")), "我想喝咖啡");
        let words = word_texts(&tokens);
        assert!(
            words.len() > 1,
            "expected multiple word tokens, got {words:?}"
        );
        let rebuilt: String = tokens.iter().map(|token| token.text.as_str()).collect();
        assert_eq!(rebuilt, "我想喝咖啡");
        for token in &tokens {
            if token.kind == SubtitleTokenKind::Word {
                assert!(token.normalized.is_some());
            }
        }
    }

    #[test]
    fn mixed_chinese_english_splits_into_units_and_word() {
        let tokens = tokenize(Some(&lang("zh")), "我想喝 coffee");
        let words = word_texts(&tokens);
        assert!(words.iter().any(|word| word == "coffee"), "got {words:?}");
        assert!(
            words.iter().any(|word| word.chars().any(is_han)),
            "got {words:?}"
        );
        let rebuilt: String = tokens.iter().map(|token| token.text.as_str()).collect();
        assert_eq!(rebuilt, "我想喝 coffee");
    }

    #[test]
    fn char_ranges_are_contiguous_and_cover_text() {
        let text = "我想喝 coffee。";
        let tokens = tokenize(Some(&lang("zh")), text);
        let mut expected = 0u32;
        for token in &tokens {
            assert_eq!(token.start_char, expected);
            expected = token.end_char;
        }
        assert_eq!(expected as usize, text.chars().count());
    }

    #[test]
    fn english_and_default_keep_baseline() {
        let text = "I can't re-enter 42";
        assert_eq!(tokenize(Some(&lang("en")), text), tokenize_english(text));
        assert_eq!(tokenize(None, text), tokenize_english(text));
    }

    #[test]
    fn unknown_language_degrades_to_whitespace() {
        let text = "hello world";
        assert_eq!(tokenize(Some(&lang("xx")), text), tokenize_english(text));
    }

    #[test]
    fn japanese_segments_via_morphological_registry_not_one_token() {
        // ja declares `ja.morphological`; the registry routes it to the Japanese
        // tokenizer (lindera under the `lindera` feature, character-level fallback
        // offline) with no edit to `tokenize` itself, so a space-less sentence
        // becomes many tokens instead of collapsing to one (the falsified path).
        let tokens = tokenize(Some(&lang("ja")), "私は学生です");
        let words = word_texts(&tokens);
        assert!(words.len() > 1, "expected multiple tokens, got {words:?}");
        let rebuilt: String = tokens.iter().map(|token| token.text.as_str()).collect();
        assert_eq!(rebuilt, "私は学生です");
    }

    #[cfg(feature = "lindera")]
    #[test]
    fn japanese_lindera_segments_morphologically() {
        // With the real lindera analyzer, 学生 (student) is a single morpheme that
        // character-level segmentation would split into 学 / 生. This proves the
        // `lindera` feature actually drives `ja.morphological`, not the fallback,
        // and that token byte offsets reconstruct the original text exactly.
        let tokens = tokenize(Some(&lang("ja")), "私は学生です");
        let words = word_texts(&tokens);
        assert!(
            words.iter().any(|word| word == "学生"),
            "expected 学生 as one morpheme, got {words:?}"
        );
        let rebuilt: String = tokens.iter().map(|token| token.text.as_str()).collect();
        assert_eq!(rebuilt, "私は学生です");
    }

    #[test]
    fn surface_language_normalization_keeps_case_via_profile() {
        // Chinese declares core.surface normalization; an embedded Latin word must
        // not be silently lowercased the way the hardcoded English lemma fold was.
        let tokens = tokenize(Some(&lang("zh")), "我看 Netflix");
        let netflix = tokens.iter().find(|token| token.text == "Netflix");
        assert_eq!(
            netflix.and_then(|token| token.normalized.as_deref()),
            Some("Netflix"),
            "zh surface normalization should preserve case; tokens={tokens:?}"
        );
        // English still lemma-folds (lowercases) per its own profile.
        let en = tokenize(Some(&lang("en")), "Netflix");
        assert_eq!(
            en.iter()
                .find(|token| token.text == "Netflix")
                .and_then(|token| token.normalized.as_deref()),
            Some("netflix")
        );
    }
}

#[cfg(test)]
mod import_language_detection_tests {
    use super::*;

    fn import_srt(body: &str, language: Option<&str>) -> SubtitleTrack {
        import(ImportSubtitle {
            media_id: MediaId::parse("media").unwrap(),
            source_name: "a.srt".into(),
            content: format!("1\n00:00:00,000 --> 00:00:01,000\n{body}\n").into_bytes(),
            language: language.map(|code| LanguageCode::parse(code).unwrap()),
            identity_salt: None,
        })
        .unwrap()
    }

    fn word_count(track: &SubtitleTrack) -> usize {
        track.sentences[0]
            .tokens
            .iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word)
            .count()
    }

    #[test]
    fn undeclared_chinese_subtitle_detects_zh_and_segments() {
        let track = import_srt("我想喝咖啡", None);
        assert_eq!(
            track.language.as_ref().map(LanguageCode::as_str),
            Some("zh")
        );
        assert!(word_count(&track) > 1, "expected Chinese segmentation");
    }

    #[test]
    fn undeclared_english_subtitle_detects_en_baseline() {
        let track = import_srt("I can't re-enter", None);
        assert_eq!(
            track.language.as_ref().map(LanguageCode::as_str),
            Some("en")
        );
        let tokens = &track.sentences[0].tokens;
        assert_eq!(*tokens, tokenize_english("I can't re-enter"));
    }

    #[test]
    fn declared_language_overrides_detection() {
        // A caller-declared language wins even when the script suggests otherwise,
        // so an explicit en keeps the whitespace baseline on Han text.
        let track = import_srt("我想喝咖啡", Some("en"));
        assert_eq!(
            track.language.as_ref().map(LanguageCode::as_str),
            Some("en")
        );
        assert_eq!(
            word_count(&track),
            1,
            "en tokenizer treats Han run as one word"
        );
    }

    #[test]
    fn undeclared_japanese_detects_ja_not_zh_and_segments() {
        // Kana (は/で/す) disambiguates Japanese from Chinese even though the line
        // also contains kanji, so detection must not misroute it to zh — the
        // central falsification this dispatch fix closes.
        let track = import_srt("私は学生です", None);
        assert_eq!(
            track.language.as_ref().map(LanguageCode::as_str),
            Some("ja")
        );
        assert!(word_count(&track) > 1, "expected Japanese segmentation");
    }

    #[test]
    fn undeclared_kanji_only_line_without_kana_still_detects_zh() {
        // Han with no kana stays Chinese: the kana signal adds Japanese without
        // regressing the existing Chinese detection baseline.
        let track = import_srt("我想喝咖啡", None);
        assert_eq!(
            track.language.as_ref().map(LanguageCode::as_str),
            Some("zh")
        );
    }
}
