use serde::{Deserialize, Serialize};

use crate::{
    DomainError, LanguageCode, LexicalEntryId, LexicalObservationId, LexicalOccurrenceId,
    LexicalStatusHistoryId, LexicalUnit, MediaId, SubtitleSentenceId,
};

/// Deterministic observation identity: one observation per (entry, sentence),
/// latest result wins. Every creation site must derive the id from these two
/// axes only, so durable references (practice attempts, exports) stay valid
/// when a newer observation replaces the stored result.
pub fn lexical_observation_id(
    lexical_entry_id: &LexicalEntryId,
    sentence_id: &SubtitleSentenceId,
) -> LexicalObservationId {
    LexicalObservationId::from_fingerprint(
        "lexical-observation",
        &format!("{}:{}", lexical_entry_id.as_str(), sentence_id.as_str()),
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LearningStatus {
    UnknownMeaning,
    KnownNotRecognized,
    KnownRecognized,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ObservationResult {
    RecognizedInContext,
    NotRecognizedInContext,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LearningChangeSource {
    UserSelection,
    Import,
    UpgradeSuggestionConfirmation,
    CapabilityOverrideSync,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LexicalEntryKind {
    Word,
    Phrase,
}

impl LexicalEntryKind {
    /// Authoritative mapping to the `LexicalUnit` granularity axis. `kind` is a
    /// projection of `unit.granularity`, never an independent identity axis.
    pub fn granularity(self) -> &'static str {
        match self {
            LexicalEntryKind::Word => LexicalUnit::GRANULARITY_WORD,
            LexicalEntryKind::Phrase => LexicalUnit::GRANULARITY_PHRASE,
        }
    }

    pub fn from_granularity(granularity: &str) -> Option<Self> {
        match granularity {
            LexicalUnit::GRANULARITY_WORD => Some(LexicalEntryKind::Word),
            LexicalUnit::GRANULARITY_PHRASE => Some(LexicalEntryKind::Phrase),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalEntry {
    pub id: LexicalEntryId,
    /// Authoritative cross-language identity for this learning asset.
    pub unit: LexicalUnit,
    pub language: LanguageCode,
    pub kind: LexicalEntryKind,
    pub canonical_form: String,
    pub normalized_form: String,
    pub display_form: String,
    pub status: Option<LearningStatus>,
    pub user_definition: Option<String>,
    pub personal_note: Option<String>,
    pub normalization_provider: String,
    pub normalization_version: String,
    pub user_corrected: bool,
    pub updated_at_ms: u64,
    pub learning_updated_at_ms: u64,
}

impl LexicalEntry {
    /// `unit` is the authoritative identity; `language`, `kind`,
    /// `normalized_form`, and `display_form` are stored projections of it.
    /// Boundaries that construct or persist entries must reject divergence so
    /// the two representations cannot drift apart silently.
    pub fn validate_unit_coherence(&self) -> Result<(), DomainError> {
        if self.unit.language != self.language {
            return Err(DomainError::LexicalUnitMismatch("language"));
        }
        if self.unit.granularity != self.kind.granularity() {
            return Err(DomainError::LexicalUnitMismatch("granularity"));
        }
        if self.unit.normalized_key != self.normalized_form {
            return Err(DomainError::LexicalUnitMismatch("normalized_key"));
        }
        if self.unit.display_form != self.display_form {
            return Err(DomainError::LexicalUnitMismatch("display_form"));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalOccurrence {
    pub id: LexicalOccurrenceId,
    pub source_key: String,
    pub lexical_entry_id: LexicalEntryId,
    pub media_id: Option<MediaId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub original_form: String,
    pub sentence_text_snapshot: String,
    pub media_title_snapshot: String,
    pub media_fingerprint_snapshot: String,
    pub start_ms_snapshot: u64,
    pub end_ms_snapshot: u64,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub first_seen_at_ms: u64,
    pub last_seen_at_ms: u64,
    pub encounter_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalStatusHistory {
    pub id: LexicalStatusHistoryId,
    pub lexical_entry_id: LexicalEntryId,
    pub previous_status: Option<LearningStatus>,
    pub new_status: Option<LearningStatus>,
    pub changed_at_ms: u64,
    pub change_source: LearningChangeSource,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalObservation {
    pub id: LexicalObservationId,
    pub lexical_entry_id: LexicalEntryId,
    pub sentence_id: SubtitleSentenceId,
    pub original_form: String,
    pub result: ObservationResult,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalEntryDetails {
    pub entry: LexicalEntry,
    pub history: Vec<LexicalStatusHistory>,
    pub occurrences: Vec<LexicalOccurrence>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capability_profile: Option<crate::LexicalCapabilityProfile>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PhraseCandidate {
    pub canonical_form: String,
    pub display_form: String,
    pub normalized_form: String,
    pub token_start: u32,
    pub token_end: u32,
    pub reason: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::LanguageCode;

    fn entry() -> LexicalEntry {
        let language = LanguageCode::parse("en").unwrap();
        LexicalEntry {
            id: LexicalEntryId::parse("entry").unwrap(),
            unit: LexicalUnit::new(
                language.clone(),
                LexicalUnit::GRANULARITY_WORD,
                LexicalUnit::NORMALIZATION_LEMMA,
                "go",
                "go",
            ),
            language,
            kind: LexicalEntryKind::Word,
            canonical_form: "go".into(),
            normalized_form: "go".into(),
            display_form: "go".into(),
            status: None,
            user_definition: None,
            personal_note: None,
            normalization_provider: "test".into(),
            normalization_version: "v1".into(),
            user_corrected: false,
            updated_at_ms: 0,
            learning_updated_at_ms: 0,
        }
    }

    #[test]
    fn observation_id_is_deterministic_on_entry_and_sentence() {
        let entry_id = LexicalEntryId::parse("entry").unwrap();
        let sentence_id = SubtitleSentenceId::parse("sentence").unwrap();
        assert_eq!(
            lexical_observation_id(&entry_id, &sentence_id),
            lexical_observation_id(&entry_id, &sentence_id)
        );
        let other_sentence = SubtitleSentenceId::parse("other").unwrap();
        assert_ne!(
            lexical_observation_id(&entry_id, &sentence_id),
            lexical_observation_id(&entry_id, &other_sentence)
        );
    }

    #[test]
    fn kind_and_granularity_map_both_ways() {
        assert_eq!(
            LexicalEntryKind::Word.granularity(),
            LexicalUnit::GRANULARITY_WORD
        );
        assert_eq!(
            LexicalEntryKind::Phrase.granularity(),
            LexicalUnit::GRANULARITY_PHRASE
        );
        assert_eq!(
            LexicalEntryKind::from_granularity(LexicalUnit::GRANULARITY_WORD),
            Some(LexicalEntryKind::Word)
        );
        assert_eq!(
            LexicalEntryKind::from_granularity(LexicalUnit::GRANULARITY_CHAR),
            None
        );
    }

    #[test]
    fn coherent_entry_passes_validation() {
        assert!(entry().validate_unit_coherence().is_ok());
    }

    #[test]
    fn diverged_projection_fields_fail_validation() {
        let mut diverged_kind = entry();
        diverged_kind.kind = LexicalEntryKind::Phrase;
        assert_eq!(
            diverged_kind.validate_unit_coherence(),
            Err(DomainError::LexicalUnitMismatch("granularity"))
        );

        let mut diverged_key = entry();
        diverged_key.normalized_form = "went".into();
        assert_eq!(
            diverged_key.validate_unit_coherence(),
            Err(DomainError::LexicalUnitMismatch("normalized_key"))
        );

        let mut diverged_display = entry();
        diverged_display.display_form = "Go!".into();
        assert_eq!(
            diverged_display.validate_unit_coherence(),
            Err(DomainError::LexicalUnitMismatch("display_form"))
        );
    }
}
