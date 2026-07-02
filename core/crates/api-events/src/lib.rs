use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const EVENT_SCHEMA_VERSION: u16 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum EventName {
    ServiceStarted,
    ServiceStopping,
    LexicalEntryChanged,
    LexicalObservationCreated,
    LexicalObservationCleared,
    VocabularyAssetsImported,
    MediaAvailabilityChanged,
    TranscriptionModelChanged,
    TranscriptionJobChanged,
    PronunciationAnalysisProgress,
    PronunciationAnalysisCompleted,
    WordTimingsProgress,
    WordTimingsCompleted,
    SoundLineChanged,
    SoundLineCompleted,
    SpeechCacheInvalidated,
    PronunciationProviderUnavailable,
    PronunciationProviderDegraded,
    PhoneticAnalysisModelChanged,
    PhoneticAnalysisJobChanged,
    PhoneticAnalysisCompleted,
    PhoneticAnalysisFeedbackChanged,
}

impl EventName {
    /// Every event name, kept in sync with the enum by `_exhaustiveness_guard`
    /// below: adding a variant without updating this list is a compile error.
    /// The schema parity test compares this list against
    /// `contracts/events/v1.schema.json` in both directions.
    pub const ALL: &'static [EventName] = &[
        EventName::ServiceStarted,
        EventName::ServiceStopping,
        EventName::LexicalEntryChanged,
        EventName::LexicalObservationCreated,
        EventName::LexicalObservationCleared,
        EventName::VocabularyAssetsImported,
        EventName::MediaAvailabilityChanged,
        EventName::TranscriptionModelChanged,
        EventName::TranscriptionJobChanged,
        EventName::PronunciationAnalysisProgress,
        EventName::PronunciationAnalysisCompleted,
        EventName::WordTimingsProgress,
        EventName::WordTimingsCompleted,
        EventName::SoundLineChanged,
        EventName::SoundLineCompleted,
        EventName::SpeechCacheInvalidated,
        EventName::PronunciationProviderUnavailable,
        EventName::PronunciationProviderDegraded,
        EventName::PhoneticAnalysisModelChanged,
        EventName::PhoneticAnalysisJobChanged,
        EventName::PhoneticAnalysisCompleted,
        EventName::PhoneticAnalysisFeedbackChanged,
    ];

    pub fn wire_name(self) -> String {
        serde_json::to_value(self)
            .expect("event name serializes")
            .as_str()
            .expect("event name is a string")
            .to_owned()
    }
}

// Forces a compile error when a variant is added without extending
// `EventName::ALL` (the match below must be updated in the same edit).
fn _exhaustiveness_guard(name: EventName) {
    match name {
        EventName::ServiceStarted
        | EventName::ServiceStopping
        | EventName::LexicalEntryChanged
        | EventName::LexicalObservationCreated
        | EventName::LexicalObservationCleared
        | EventName::VocabularyAssetsImported
        | EventName::MediaAvailabilityChanged
        | EventName::TranscriptionModelChanged
        | EventName::TranscriptionJobChanged
        | EventName::PronunciationAnalysisProgress
        | EventName::PronunciationAnalysisCompleted
        | EventName::WordTimingsProgress
        | EventName::WordTimingsCompleted
        | EventName::SoundLineChanged
        | EventName::SoundLineCompleted
        | EventName::SpeechCacheInvalidated
        | EventName::PronunciationProviderUnavailable
        | EventName::PronunciationProviderDegraded
        | EventName::PhoneticAnalysisModelChanged
        | EventName::PhoneticAnalysisJobChanged
        | EventName::PhoneticAnalysisCompleted
        | EventName::PhoneticAnalysisFeedbackChanged => {}
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EventEnvelope {
    pub version: u16,
    pub event: EventName,
    pub payload: Value,
}

impl EventEnvelope {
    pub fn v1(event: EventName, payload: Value) -> Self {
        Self {
            version: EVENT_SCHEMA_VERSION,
            event,
            payload,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_versioned_events() {
        let event = EventEnvelope::v1(
            EventName::LexicalEntryChanged,
            serde_json::json!({"entry": {"normalized_form": "hello"}}),
        );
        assert_eq!(event.version, 1);
    }

    #[test]
    fn event_contract_schema_is_present() {
        let schema = include_str!("../../../contracts/events/v1.schema.json");
        assert!(schema.contains("lexical-entry-changed"));
    }

    #[test]
    fn event_names_match_contract_schema_bidirectionally() {
        let schema: serde_json::Value =
            serde_json::from_str(include_str!("../../../contracts/events/v1.schema.json"))
                .expect("event schema parses");
        let documented = schema["properties"]["event"]["enum"]
            .as_array()
            .expect("event enum is an array")
            .iter()
            .map(|value| value.as_str().expect("enum entry is a string").to_owned())
            .collect::<std::collections::BTreeSet<_>>();
        let implemented = EventName::ALL
            .iter()
            .map(|name| name.wire_name())
            .collect::<std::collections::BTreeSet<_>>();
        let undocumented = implemented.difference(&documented).collect::<Vec<_>>();
        let unimplemented = documented.difference(&implemented).collect::<Vec<_>>();
        assert!(
            undocumented.is_empty(),
            "events implemented but missing from contracts/events/v1.schema.json: {undocumented:?}"
        );
        assert!(
            unimplemented.is_empty(),
            "events documented but not implemented in EventName: {unimplemented:?}"
        );
    }
}
