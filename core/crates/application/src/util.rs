use std::time::{SystemTime, UNIX_EPOCH};

use domain::*;

use crate::{ApplicationError, LexicalSourceContext, SourceContext};

pub(crate) fn require_text(value: &str, field: &'static str) -> Result<(), ApplicationError> {
    if value.trim().is_empty() {
        return Err(ApplicationError::Validation(field));
    }
    Ok(())
}

pub(crate) fn clean_required(
    value: String,
    field: &'static str,
) -> Result<String, ApplicationError> {
    let value = value.trim().to_owned();
    require_text(&value, field)?;
    Ok(value)
}

pub(crate) fn clean_optional(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let value = value.trim().to_owned();
        (!value.is_empty()).then_some(value)
    })
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock must be after UNIX epoch")
        .as_millis() as u64
}

pub(crate) fn normalize_phrase(value: &str) -> String {
    value
        .split_whitespace()
        .map(normalize_lemma)
        .collect::<Vec<_>>()
        .join(" ")
}

pub(crate) fn lexical_from_word(profile: &WordProfile) -> LexicalEntry {
    LexicalEntry {
        id: LexicalEntryId::parse(profile.id.as_str().to_owned())
            .expect("word profile id is a valid lexical id"),
        language: profile.language.clone(),
        kind: LexicalEntryKind::Word,
        canonical_form: profile.lemma.clone(),
        normalized_form: profile.normalized_lemma.clone(),
        display_form: profile.display_form.clone(),
        status: profile.status,
        user_definition: profile.user_definition.clone(),
        personal_note: profile.personal_note.clone(),
        normalization_provider: "legacy-word-api".into(),
        normalization_version: "v1".into(),
        user_corrected: false,
        updated_at_ms: profile.updated_at_ms,
        learning_updated_at_ms: profile.learning_updated_at_ms,
    }
}

pub(crate) fn lexical_source_from_word(source: &SourceContext) -> LexicalSourceContext {
    LexicalSourceContext {
        media_id: source.media_id.clone(),
        sentence_id: source.sentence_id.clone(),
        original_form: source.original_form.clone(),
        sentence_text: source.sentence_text.clone(),
        media_title: source.media_title.clone(),
        media_fingerprint: source.media_fingerprint.clone(),
        start_ms: source.start_ms,
        end_ms: source.end_ms,
        token_start: None,
        token_end: None,
    }
}

pub(crate) fn normalize_american_english(value: &str) -> String {
    match value {
        "went" | "gone" | "going" | "goes" => "go".into(),
        "was" | "were" | "been" | "being" | "am" | "is" | "are" => "be".into(),
        "did" | "done" | "doing" | "does" => "do".into(),
        "had" | "having" | "has" => "have".into(),
        _ if value.len() > 4 && value.ends_with("ies") => {
            format!("{}y", &value[..value.len() - 3])
        }
        _ if value.len() > 5 && value.ends_with("ing") => value[..value.len() - 3].into(),
        _ if value.len() > 4 && value.ends_with("ed") => value[..value.len() - 2].into(),
        _ if value.len() > 3 && value.ends_with('s') && !value.ends_with("ss") => {
            value[..value.len() - 1].into()
        }
        _ => value.into(),
    }
}

pub(crate) fn phrase_candidates(sentence: &SubtitleSentence) -> Vec<PhraseCandidate> {
    const PHRASES: &[&str] = &[
        "according to",
        "as well as",
        "because of",
        "come up with",
        "figure out",
        "get along",
        "give up",
        "in front of",
        "in order to",
        "look forward to",
        "make sure",
        "pick up",
        "take care of",
        "turn out",
        "used to",
    ];
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    let normalized = words
        .iter()
        .map(|token| normalize_lemma(&token.text))
        .collect::<Vec<_>>();
    let mut values = Vec::new();
    for phrase in PHRASES {
        let parts = phrase.split_whitespace().collect::<Vec<_>>();
        for start in 0..normalized
            .len()
            .saturating_sub(parts.len().saturating_sub(1))
        {
            if normalized[start..start + parts.len()] == parts {
                values.push(PhraseCandidate {
                    canonical_form: (*phrase).into(),
                    display_form: words[start..start + parts.len()]
                        .iter()
                        .map(|token| token.text.as_str())
                        .collect::<Vec<_>>()
                        .join(" "),
                    normalized_form: (*phrase).into(),
                    token_start: words[start].index,
                    token_end: words[start + parts.len() - 1].index,
                    reason: "built-in en-US phrase rule".into(),
                });
            }
        }
    }
    values
}
