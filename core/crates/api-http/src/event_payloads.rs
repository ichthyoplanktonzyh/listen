//! Typed SSE payload shapes for events whose payloads were previously
//! hand-built `serde_json::json!` maps. Emit sites construct these structs so
//! every payload key has a single greppable owner; events that already
//! serialize a whole domain/DTO value (`transcription-job-changed`,
//! `phonetic-analysis-job-changed`, `lexical-entry-changed`,
//! `sound-line-changed`, ...) keep that value as their payload contract.
//!
//! The wire shapes the Flutter client parses into typed models are pinned by
//! `contracts/events/examples.json`: the producer side is asserted by
//! `event_contract_examples_match_producers` below, the consumer side by
//! `apps/desktop/test/contract/backend_event_contract_test.dart` parsing the
//! same committed file.

use api_events::{EventEnvelope, EventName};
use serde::Serialize;

use crate::speech_jobs::SpeechBatchKind;

fn envelope<T: Serialize>(event: EventName, payload: &T) -> EventEnvelope {
    EventEnvelope::v1(
        event,
        serde_json::to_value(payload).expect("event payload serializes"),
    )
}

/// `word-timings-completed` from the transcription text-line pipeline.
#[derive(Debug, Clone, Serialize)]
pub struct WordTimingsCompletedPayload {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub job_id: Option<String>,
    pub track_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line: Option<String>,
    pub count: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timeline_id: Option<String>,
}

impl WordTimingsCompletedPayload {
    pub fn envelope(&self) -> EventEnvelope {
        envelope(EventName::WordTimingsCompleted, self)
    }
}

/// `pronunciation-analysis-completed` from either a single-sentence route,
/// whole-track route, or background speech batch job.
#[derive(Debug, Clone, Serialize)]
pub struct PronunciationAnalysisCompletedPayload {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub job_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub track_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sentence_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub count: Option<usize>,
}

impl PronunciationAnalysisCompletedPayload {
    pub fn envelope(&self) -> EventEnvelope {
        envelope(EventName::PronunciationAnalysisCompleted, self)
    }
}

/// Progress payload for `word-timings-progress` or
/// `pronunciation-analysis-progress`. Background jobs include `job_id`; route
/// handlers emit the same shape without it.
#[derive(Debug, Clone, Serialize)]
pub struct SpeechBatchProgressPayload {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub job_id: Option<String>,
    pub track_id: String,
    pub processed: usize,
    pub total: usize,
}

impl SpeechBatchProgressPayload {
    pub fn envelope(&self, event: EventName) -> EventEnvelope {
        envelope(event, self)
    }
}

/// `lexical-observation-cleared`.
#[derive(Debug, Clone, Serialize)]
pub struct LexicalObservationClearedPayload {
    pub lexical_entry_id: String,
    pub sentence_id: String,
}

impl LexicalObservationClearedPayload {
    pub fn envelope(&self) -> EventEnvelope {
        envelope(EventName::LexicalObservationCleared, self)
    }
}

/// `vocabulary-assets-imported`.
#[derive(Debug, Clone, Serialize)]
pub struct VocabularyAssetsImportedPayload {
    pub lexical_entries: usize,
}

impl VocabularyAssetsImportedPayload {
    pub fn envelope(&self) -> EventEnvelope {
        envelope(EventName::VocabularyAssetsImported, self)
    }
}

/// `speech-cache-invalidated`. Batch jobs provide job/track context; the
/// single-sentence pronunciation route only knows the sentence.
#[derive(Debug, Clone, Serialize)]
pub struct SpeechCacheInvalidatedPayload {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub job_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub track_id: Option<String>,
    pub kind: SpeechBatchKind,
    pub sentence_id: String,
}

impl SpeechCacheInvalidatedPayload {
    pub fn envelope(&self) -> EventEnvelope {
        envelope(EventName::SpeechCacheInvalidated, self)
    }
}

/// Provider availability diagnostics shared by
/// `pronunciation-provider-unavailable` and `pronunciation-provider-degraded`.
#[derive(Debug, Clone, Serialize)]
pub struct PronunciationProviderDiagnosticPayload {
    pub provider_id: String,
    pub provider_version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub diagnostic: Option<String>,
}

impl PronunciationProviderDiagnosticPayload {
    pub fn envelope(&self, event: EventName) -> EventEnvelope {
        envelope(event, self)
    }
}

/// `sound-line-completed` from the independent sound-line workflow.
#[derive(Debug, Clone, Serialize)]
pub struct SoundLineCompletedPayload {
    pub job_id: String,
    pub track_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timeline_id: Option<String>,
    pub acoustic_cue_count: usize,
}

impl SoundLineCompletedPayload {
    pub fn envelope(&self) -> EventEnvelope {
        envelope(EventName::SoundLineCompleted, self)
    }
}

/// `phonetic-analysis-completed` batch summary.
#[derive(Debug, Clone, Serialize)]
pub struct PhoneticAnalysisCompletedPayload {
    pub job_id: String,
    pub track_id: String,
    pub analysis_ids: Vec<String>,
    pub phone_timeline_ids: Vec<String>,
}

impl PhoneticAnalysisCompletedPayload {
    pub fn envelope(&self) -> EventEnvelope {
        envelope(EventName::PhoneticAnalysisCompleted, self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::*;

    const EXAMPLES_PATH: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../contracts/events/examples.json"
    );

    /// Representative envelopes for every event the Flutter client parses into
    /// a typed model, built through the same producers the runtime uses.
    fn contract_examples() -> Vec<EventEnvelope> {
        let transcription_job = TranscriptionJob {
            id: TranscriptionJobId::parse("job-transcribe-1").unwrap(),
            media_id: MediaId::parse("media-1").unwrap(),
            media_title: "Example Media".into(),
            media_fingerprint: "media-fingerprint".into(),
            provider_id: "whisper.cpp".into(),
            provider_version: "v1".into(),
            runtime_id: "local".into(),
            runtime_version: "v1".into(),
            model_id: TranscriptionModelId::parse("model-base").unwrap(),
            model_revision: "r1".into(),
            model_checksum_sha256: "checksum".into(),
            destination: TranscriptionDestination::Primary,
            purpose: TranscriptionPurpose::Transcribe,
            requested_language: Some("en".into()),
            detected_language: Some("en".into()),
            audio_track: None,
            settings_json: "{}".into(),
            input_fingerprint: "input-fingerprint".into(),
            status: TranscriptionJobStatus::Transcribing,
            phase_progress: 42,
            error_code: None,
            error_message: None,
            retry_of_job_id: None,
            generated_track_id: Some(SubtitleTrackId::parse("track-1").unwrap()),
            created_at_ms: 1,
            started_at_ms: Some(2),
            completed_at_ms: None,
            updated_at_ms: 3,
            archived_at_ms: None,
        };
        let phonetic_job = PhoneticAnalysisJob {
            id: PhoneticAnalysisJobId::parse("job-phonetic-1").unwrap(),
            media_id: MediaId::parse("media-1").unwrap(),
            track_id: SubtitleTrackId::parse("track-1").unwrap(),
            sentence_id: None,
            scope: PhoneticAnalysisScope::Track,
            audio_start_ms: 0,
            audio_end_ms: 1000,
            provider_id: "phonetic-provider".into(),
            provider_version: "v1".into(),
            runtime_id: "local".into(),
            runtime_version: "v1".into(),
            model_id: PhoneticAnalysisModelId::parse("phone-model").unwrap(),
            model_revision: "r1".into(),
            model_checksum_sha256: "checksum".into(),
            requested_phone_set: "ipa".into(),
            settings_json: "{}".into(),
            input_fingerprint: "input-fingerprint".into(),
            status: PhoneticAnalysisJobStatus::Analyzing,
            phase_progress: 60,
            error_code: None,
            error_message: None,
            retry_of_job_id: None,
            analysis_id: None,
            created_at_ms: 1,
            started_at_ms: Some(2),
            completed_at_ms: None,
            updated_at_ms: 3,
        };
        let language = LanguageCode::parse("en").unwrap();
        let lexical_details = LexicalEntryDetails {
            entry: LexicalEntry {
                id: LexicalEntryId::parse("entry-1").unwrap(),
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
                status: Some(LearningStatus::KnownNotRecognized),
                user_definition: None,
                personal_note: None,
                normalization_provider: "ecdict".into(),
                normalization_version: "v1".into(),
                user_corrected: false,
                updated_at_ms: 1,
                learning_updated_at_ms: 1,
            },
            history: Vec::new(),
            occurrences: Vec::new(),
        };
        vec![
            EventEnvelope::v1(EventName::ServiceStarted, serde_json::json!({})),
            WordTimingsCompletedPayload {
                job_id: None,
                track_id: "track-1".into(),
                line: Some("text".into()),
                count: 12,
                timeline_id: Some("word-timeline-1".into()),
            }
            .envelope(),
            SoundLineCompletedPayload {
                job_id: "sound-line-job-1".into(),
                track_id: "track-1".into(),
                timeline_id: Some("word-timeline-1".into()),
                acoustic_cue_count: 34,
            }
            .envelope(),
            EventEnvelope::v1(
                EventName::TranscriptionJobChanged,
                serde_json::to_value(&transcription_job).unwrap(),
            ),
            EventEnvelope::v1(
                EventName::PhoneticAnalysisJobChanged,
                serde_json::to_value(&phonetic_job).unwrap(),
            ),
            EventEnvelope::v1(
                EventName::LexicalEntryChanged,
                serde_json::to_value(&lexical_details).unwrap(),
            ),
        ]
    }

    /// Pins the producer wire shapes to `contracts/events/examples.json`. The
    /// Flutter side parses the same file in
    /// `apps/desktop/test/contract/backend_event_contract_test.dart`, so a
    /// payload change must update the committed examples and pass both suites.
    /// Regenerate with `UPDATE_EVENT_EXAMPLES=1 cargo test -p api-http event_contract`.
    #[test]
    fn event_contract_examples_match_producers() {
        let produced = serde_json::json!({
            "$comment": "Golden SSE envelopes for events the Flutter client parses typed. \
                         Producer side: cargo test -p api-http event_contract. \
                         Consumer side: apps/desktop/test/contract/backend_event_contract_test.dart. \
                         Regenerate: UPDATE_EVENT_EXAMPLES=1 cargo test -p api-http event_contract.",
            "examples": contract_examples(),
        });
        if std::env::var("UPDATE_EVENT_EXAMPLES").is_ok() {
            std::fs::write(
                EXAMPLES_PATH,
                serde_json::to_string_pretty(&produced).unwrap() + "\n",
            )
            .expect("write event examples");
        }
        let committed: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(EXAMPLES_PATH).expect(
                "contracts/events/examples.json missing; regenerate with \
                 UPDATE_EVENT_EXAMPLES=1 cargo test -p api-http event_contract",
            ))
            .expect("event examples parse");
        assert_eq!(
            committed, produced,
            "event payload wire shape changed; regenerate contracts/events/examples.json \
             with UPDATE_EVENT_EXAMPLES=1 and re-run the Flutter contract test"
        );
    }
}
