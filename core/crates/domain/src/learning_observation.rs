use serde::{Deserialize, Serialize};

use crate::{
    LearningObservationId, LexicalCapability, LexicalEntryId, LexicalSenseId, MediaId,
    ObservationResult, PracticeKind, PracticeResult, ReviewRating, SubtitleSentenceId,
};

/// Version tag for the static task-to-channel mapping defined by ADR 0017
/// decision 2. Rows record what the mapping said at write time; remapping
/// bumps this constant instead of rewriting history.
pub const OBSERVATION_MAPPING_VERSION: &str = "task-channel-mapping-v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ObservationTaskType {
    ContextMarking,
    Cloze,
    Dictation,
    SubtitleFade,
    Shadowing,
    ReviewRecall,
    UpgradeConfirmation,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ObservationOutcome {
    Success,
    Partial,
    Failure,
}

/// What the learner could see besides the audio. Per shared-context
/// invariant 16, only `None` observations can later support a listening
/// `acquired` conclusion on their own.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AssistanceLevel {
    None,
    PartialText,
    FullText,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ObservationOrigin {
    UserMarking,
    PracticeTask,
    ReviewTask,
    LegacyBackfill,
}

/// One real learner performance in one task and context. Append-only:
/// identity includes the source attempt and timestamp, never just
/// `(entry, sentence)` (ADR 0017 decision 1).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearningObservation {
    pub id: LearningObservationId,
    pub lexical_entry_id: LexicalEntryId,
    /// Reserved identity seam, mirrors `LexicalCapabilityProfile.sense_id`.
    pub sense_id: Option<LexicalSenseId>,
    pub capability: LexicalCapability,
    pub task_type: ObservationTaskType,
    pub outcome: ObservationOutcome,
    pub assistance: AssistanceLevel,
    /// The form as encountered ("went", not "go"); listening evidence must
    /// keep it because phonological forms do not transfer across inflections.
    pub surface_form: Option<String>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub media_id: Option<MediaId>,
    pub origin: ObservationOrigin,
    /// Practice/review attempt id or legacy observation id this row came from.
    pub source_ref: Option<String>,
    pub occurred_at_ms: u64,
}

/// Outcome participates in identity because some writers (context marking)
/// reuse a stable source ref: two different judgments in the same millisecond
/// must stay two rows, while a byte-identical replay stays idempotent.
pub fn learning_observation_id(
    lexical_entry_id: &LexicalEntryId,
    task_type: ObservationTaskType,
    outcome: ObservationOutcome,
    source_ref: Option<&str>,
    occurred_at_ms: u64,
) -> LearningObservationId {
    LearningObservationId::from_fingerprint(
        "learning-observation",
        &format!(
            "{}:{}:{}:{}:{occurred_at_ms}",
            lexical_entry_id.as_str(),
            serde_json::to_string(&task_type).expect("task type serializes"),
            serde_json::to_string(&outcome).expect("outcome serializes"),
            source_ref.unwrap_or(""),
        ),
    )
}

/// The channel/assistance/outcome a writer must record. Single definition
/// point for the ADR 0017 decision 2 table; call sites must not inline
/// channel judgments.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObservationSpec {
    pub task_type: ObservationTaskType,
    pub capability: LexicalCapability,
    pub assistance: AssistanceLevel,
    pub outcome: ObservationOutcome,
}

pub fn observation_spec_for_marking(result: ObservationResult) -> ObservationSpec {
    ObservationSpec {
        task_type: ObservationTaskType::ContextMarking,
        capability: LexicalCapability::Listening,
        assistance: AssistanceLevel::FullText,
        outcome: match result {
            ObservationResult::RecognizedInContext => ObservationOutcome::Success,
            ObservationResult::NotRecognizedInContext => ObservationOutcome::Failure,
        },
    }
}

/// Returns `None` for skipped and non-evaluated completed attempts: neither is
/// capability evidence.
pub fn observation_spec_for_practice(
    kind: PracticeKind,
    result: PracticeResult,
) -> Option<ObservationSpec> {
    let outcome = match result {
        PracticeResult::Correct => ObservationOutcome::Success,
        PracticeResult::Partial => ObservationOutcome::Partial,
        PracticeResult::Incorrect => ObservationOutcome::Failure,
        PracticeResult::Completed | PracticeResult::Skipped => return None,
    };
    let (task_type, capability, assistance) = match kind {
        PracticeKind::Cloze => (
            ObservationTaskType::Cloze,
            LexicalCapability::Listening,
            AssistanceLevel::FullText,
        ),
        PracticeKind::Dictation => (
            ObservationTaskType::Dictation,
            LexicalCapability::Listening,
            AssistanceLevel::None,
        ),
        PracticeKind::SubtitleFade => (
            ObservationTaskType::SubtitleFade,
            LexicalCapability::Listening,
            AssistanceLevel::PartialText,
        ),
        PracticeKind::Shadowing => (
            ObservationTaskType::Shadowing,
            LexicalCapability::Speaking,
            AssistanceLevel::FullText,
        ),
    };
    Some(ObservationSpec {
        task_type,
        capability,
        assistance,
        outcome,
    })
}

/// The user accepting an upgrade suggestion is itself a declaration-grade
/// success signal for the suggested capability (ADR 0017 decision 4).
pub fn observation_spec_for_upgrade_confirmation(capability: LexicalCapability) -> ObservationSpec {
    ObservationSpec {
        task_type: ObservationTaskType::UpgradeConfirmation,
        capability,
        assistance: AssistanceLevel::None,
        outcome: ObservationOutcome::Success,
    }
}

pub fn observation_spec_for_review(rating: ReviewRating) -> ObservationSpec {
    ObservationSpec {
        task_type: ObservationTaskType::ReviewRecall,
        capability: LexicalCapability::Listening,
        assistance: AssistanceLevel::None,
        outcome: match rating {
            ReviewRating::Again => ObservationOutcome::Failure,
            ReviewRating::Hard => ObservationOutcome::Partial,
            ReviewRating::Good | ReviewRating::Easy => ObservationOutcome::Success,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry_id() -> LexicalEntryId {
        LexicalEntryId::parse("entry").unwrap()
    }

    #[test]
    fn identity_includes_source_and_time_never_just_entry_and_sentence() {
        let same_entry = entry_id();
        let a = learning_observation_id(
            &same_entry,
            ObservationTaskType::Dictation,
            ObservationOutcome::Failure,
            Some("attempt-1"),
            100,
        );
        let b = learning_observation_id(
            &same_entry,
            ObservationTaskType::Dictation,
            ObservationOutcome::Failure,
            Some("attempt-2"),
            100,
        );
        let c = learning_observation_id(
            &same_entry,
            ObservationTaskType::Dictation,
            ObservationOutcome::Failure,
            Some("attempt-1"),
            200,
        );
        // A different judgment behind the same stable source ref (context
        // marking) in the same millisecond is still distinct evidence.
        let d = learning_observation_id(
            &same_entry,
            ObservationTaskType::Dictation,
            ObservationOutcome::Success,
            Some("attempt-1"),
            100,
        );
        assert_ne!(a, b);
        assert_ne!(a, c);
        assert_ne!(a, d);
        assert_eq!(
            a,
            learning_observation_id(
                &same_entry,
                ObservationTaskType::Dictation,
                ObservationOutcome::Failure,
                Some("attempt-1"),
                100,
            )
        );
    }

    #[test]
    fn marking_maps_to_listening_with_visible_text() {
        let recognized = observation_spec_for_marking(ObservationResult::RecognizedInContext);
        assert_eq!(recognized.capability, LexicalCapability::Listening);
        assert_eq!(recognized.assistance, AssistanceLevel::FullText);
        assert_eq!(recognized.outcome, ObservationOutcome::Success);
        assert_eq!(
            observation_spec_for_marking(ObservationResult::NotRecognizedInContext).outcome,
            ObservationOutcome::Failure
        );
    }

    #[test]
    fn practice_mapping_matches_adr_0017_table() {
        let dictation =
            observation_spec_for_practice(PracticeKind::Dictation, PracticeResult::Correct)
                .unwrap();
        assert_eq!(dictation.capability, LexicalCapability::Listening);
        assert_eq!(dictation.assistance, AssistanceLevel::None);

        let cloze =
            observation_spec_for_practice(PracticeKind::Cloze, PracticeResult::Partial).unwrap();
        assert_eq!(cloze.assistance, AssistanceLevel::FullText);
        assert_eq!(cloze.outcome, ObservationOutcome::Partial);

        let fade =
            observation_spec_for_practice(PracticeKind::SubtitleFade, PracticeResult::Incorrect)
                .unwrap();
        assert_eq!(fade.assistance, AssistanceLevel::PartialText);
        assert_eq!(fade.outcome, ObservationOutcome::Failure);

        let shadowing =
            observation_spec_for_practice(PracticeKind::Shadowing, PracticeResult::Correct)
                .unwrap();
        assert_eq!(shadowing.capability, LexicalCapability::Speaking);

        assert!(
            observation_spec_for_practice(PracticeKind::Cloze, PracticeResult::Skipped).is_none()
        );
        assert!(
            observation_spec_for_practice(PracticeKind::Shadowing, PracticeResult::Completed)
                .is_none()
        );
    }

    #[test]
    fn review_ratings_map_to_graded_outcomes() {
        assert_eq!(
            observation_spec_for_review(ReviewRating::Again).outcome,
            ObservationOutcome::Failure
        );
        assert_eq!(
            observation_spec_for_review(ReviewRating::Hard).outcome,
            ObservationOutcome::Partial
        );
        assert_eq!(
            observation_spec_for_review(ReviewRating::Good).outcome,
            ObservationOutcome::Success
        );
        assert_eq!(
            observation_spec_for_review(ReviewRating::Easy).outcome,
            ObservationOutcome::Success
        );
    }

    #[test]
    fn serialized_contract_uses_named_snake_case_values() {
        assert_eq!(
            serde_json::to_string(&ObservationTaskType::ContextMarking).unwrap(),
            "\"context_marking\""
        );
        assert_eq!(
            serde_json::to_string(&AssistanceLevel::PartialText).unwrap(),
            "\"partial_text\""
        );
        assert_eq!(
            serde_json::to_string(&ObservationOrigin::LegacyBackfill).unwrap(),
            "\"legacy_backfill\""
        );

        let observation = LearningObservation {
            id: LearningObservationId::parse("obs-1").unwrap(),
            lexical_entry_id: entry_id(),
            sense_id: None,
            capability: LexicalCapability::Listening,
            task_type: ObservationTaskType::Dictation,
            outcome: ObservationOutcome::Success,
            assistance: AssistanceLevel::None,
            surface_form: Some("went".into()),
            sentence_id: Some(SubtitleSentenceId::parse("s1").unwrap()),
            media_id: None,
            origin: ObservationOrigin::PracticeTask,
            source_ref: Some("attempt-1".into()),
            occurred_at_ms: 42,
        };
        let roundtrip: LearningObservation =
            serde_json::from_str(&serde_json::to_string(&observation).unwrap()).unwrap();
        assert_eq!(roundtrip, observation);
    }
}
