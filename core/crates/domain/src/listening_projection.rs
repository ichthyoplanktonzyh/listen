//! listening-projection-v1 (ADR 0019): the first real evidence-projection
//! algorithm. A pure function of the listening observation stream — algorithm
//! changes reproject history by bumping [`LISTENING_PROJECTION_ALGORITHM_VERSION`]
//! (invariant 3).
//!
//! v1 is deliberately conservative: the only event that can conclude
//! `acquired` is an upgrade confirmation (the user-sanctioned step of the
//! 3.4 suggestion pipeline, itself fed by markings/practice/review
//! recognition evidence); unassisted task failures conclude `not_acquired`
//! with a single-lapse protection for confirmed words. Context markings,
//! assisted practice, raw task successes, and partial outcomes are
//! supporting evidence only — their status-quo behavior is unchanged.
//!
//! All confidence constants are `heuristic_proxy` pending Slice 9 manual QA.

use crate::{
    AssistanceLevel, CapabilityConclusion, CapabilityProjection, CapabilityProjectionSource,
    LearningObservation, LexicalCapability, ObservationOutcome, ObservationTaskType,
};

pub const LISTENING_PROJECTION_ALGORITHM_VERSION: &str = "listening-projection-v1";

/// Task-grade conclusions (confirmation-acquired, failure-flipped). The
/// legacy compat writer may not upgrade over an evidence projection at this
/// confidence (ADR 0019 writer ladder).
pub const LISTENING_CONFIDENCE_TASK: f32 = 0.85;
/// A single lapse after a confirmed acquisition weakens, does not flip; at
/// this confidence the compat writer may overwrite again.
pub const LISTENING_CONFIDENCE_WEAKENED: f32 = 0.40;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Event {
    /// Upgrade confirmation success: the sanctioned acquisition event.
    ConfirmedSuccess,
    /// Unassisted task success (dictation/review): supporting before the
    /// first confirmation, re-strengthening after it.
    TaskSuccess,
    /// Unassisted task failure (dictation/review lapse).
    TaskFailure,
}

/// Projects the listening conclusion from channelized evidence.
///
/// `observations` must be listening-capability rows ordered newest-first (the
/// repository list order). Returns `None` when the stream cannot support any
/// conclusion — the caller must then leave the existing projection untouched.
pub fn listening_projection_v1(
    observations: &[LearningObservation],
    now_ms: u64,
) -> Option<CapabilityProjection> {
    let events: Vec<(Event, u64)> = observations
        .iter()
        .filter(|obs| {
            obs.capability == LexicalCapability::Listening
                && obs.assistance == AssistanceLevel::None
        })
        .filter_map(|obs| match obs.outcome {
            ObservationOutcome::Partial => None,
            ObservationOutcome::Success
                if obs.task_type == ObservationTaskType::UpgradeConfirmation =>
            {
                Some((Event::ConfirmedSuccess, obs.occurred_at_ms))
            }
            ObservationOutcome::Success => Some((Event::TaskSuccess, obs.occurred_at_ms)),
            ObservationOutcome::Failure => Some((Event::TaskFailure, obs.occurred_at_ms)),
        })
        .collect();
    let has_confirmation = events
        .iter()
        .any(|(event, _)| *event == Event::ConfirmedSuccess);

    for (index, (event, occurred_at_ms)) in events.iter().enumerate() {
        let (conclusion, confidence) = match event {
            Event::ConfirmedSuccess => {
                (CapabilityConclusion::Acquired, LISTENING_CONFIDENCE_TASK)
            }
            Event::TaskSuccess if has_confirmation => {
                (CapabilityConclusion::Acquired, LISTENING_CONFIDENCE_TASK)
            }
            // Raw successes before any confirmation feed the suggestion
            // engine but cannot conclude acquisition on their own.
            Event::TaskSuccess => continue,
            Event::TaskFailure => {
                let streak = events[index..]
                    .iter()
                    .take_while(|(event, _)| *event == Event::TaskFailure)
                    .count();
                if has_confirmation && streak < 2 {
                    // SRS lapse convention: one lapse on a confirmed word
                    // weakens, does not flip.
                    (CapabilityConclusion::Acquired, LISTENING_CONFIDENCE_WEAKENED)
                } else {
                    // Never-confirmed words flip on a real listening failure
                    // — the "看得懂听不出" discovery.
                    (CapabilityConclusion::NotAcquired, LISTENING_CONFIDENCE_TASK)
                }
            }
        };
        return Some(CapabilityProjection {
            conclusion,
            source: CapabilityProjectionSource::EvidenceProjection,
            algorithm_version: LISTENING_PROJECTION_ALGORITHM_VERSION.into(),
            confidence: Some(confidence),
            evidence_as_of_ms: Some(*occurred_at_ms),
            updated_at_ms: now_ms,
        });
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{LearningObservationId, LexicalEntryId, ObservationOrigin};

    fn obs(
        task_type: ObservationTaskType,
        outcome: ObservationOutcome,
        assistance: AssistanceLevel,
        occurred_at_ms: u64,
    ) -> LearningObservation {
        LearningObservation {
            id: LearningObservationId::parse(format!("obs-{occurred_at_ms}")).unwrap(),
            lexical_entry_id: LexicalEntryId::parse("entry-1").unwrap(),
            sense_id: None,
            capability: LexicalCapability::Listening,
            task_type,
            outcome,
            assistance,
            surface_form: None,
            sentence_id: None,
            media_id: None,
            origin: ObservationOrigin::PracticeTask,
            source_ref: None,
            occurred_at_ms,
        }
    }

    fn marking(outcome: ObservationOutcome, at: u64) -> LearningObservation {
        obs(
            ObservationTaskType::ContextMarking,
            outcome,
            AssistanceLevel::FullText,
            at,
        )
    }

    fn dictation(outcome: ObservationOutcome, at: u64) -> LearningObservation {
        obs(ObservationTaskType::Dictation, outcome, AssistanceLevel::None, at)
    }

    fn confirmation(at: u64) -> LearningObservation {
        obs(
            ObservationTaskType::UpgradeConfirmation,
            ObservationOutcome::Success,
            AssistanceLevel::None,
            at,
        )
    }

    fn project(mut observations: Vec<LearningObservation>) -> Option<CapabilityProjection> {
        // repository order: newest first
        observations.sort_by(|a, b| b.occurred_at_ms.cmp(&a.occurred_at_ms));
        listening_projection_v1(&observations, 99_999)
    }

    #[test]
    fn supporting_only_history_concludes_nothing() {
        assert_eq!(project(vec![]), None);
        // markings (both directions), assisted practice, partial outcomes,
        // and raw task successes are all supporting-only in v1
        assert_eq!(
            project(vec![
                marking(ObservationOutcome::Success, 10),
                marking(ObservationOutcome::Failure, 20),
                obs(
                    ObservationTaskType::Cloze,
                    ObservationOutcome::Success,
                    AssistanceLevel::FullText,
                    30,
                ),
                obs(
                    ObservationTaskType::ReviewRecall,
                    ObservationOutcome::Partial,
                    AssistanceLevel::None,
                    40,
                ),
                dictation(ObservationOutcome::Success, 50),
            ]),
            None
        );
    }

    #[test]
    fn upgrade_confirmation_is_the_acquisition_event() {
        let confirmed = project(vec![confirmation(10)]).unwrap();
        assert_eq!(confirmed.conclusion, CapabilityConclusion::Acquired);
        assert_eq!(confirmed.confidence, Some(LISTENING_CONFIDENCE_TASK));
        assert_eq!(confirmed.evidence_as_of_ms, Some(10));
        assert_eq!(
            confirmed.algorithm_version,
            LISTENING_PROJECTION_ALGORITHM_VERSION
        );
    }

    #[test]
    fn task_failure_flips_a_never_confirmed_word() {
        let flipped = project(vec![
            marking(ObservationOutcome::Success, 10),
            dictation(ObservationOutcome::Failure, 20),
        ])
        .unwrap();
        assert_eq!(flipped.conclusion, CapabilityConclusion::NotAcquired);
        assert_eq!(flipped.confidence, Some(LISTENING_CONFIDENCE_TASK));
        assert_eq!(flipped.evidence_as_of_ms, Some(20));

        // a later raw success does not restore acquisition on its own —
        // the suggestion pipeline owns that path
        let still_flipped = project(vec![
            dictation(ObservationOutcome::Failure, 20),
            dictation(ObservationOutcome::Success, 30),
        ])
        .unwrap();
        assert_eq!(still_flipped.conclusion, CapabilityConclusion::NotAcquired);
    }

    #[test]
    fn confirmed_word_survives_a_single_lapse_but_not_two() {
        let weakened = project(vec![
            confirmation(10),
            dictation(ObservationOutcome::Failure, 20),
        ])
        .unwrap();
        assert_eq!(weakened.conclusion, CapabilityConclusion::Acquired);
        assert_eq!(weakened.confidence, Some(LISTENING_CONFIDENCE_WEAKENED));

        let flipped = project(vec![
            confirmation(10),
            dictation(ObservationOutcome::Failure, 20),
            dictation(ObservationOutcome::Failure, 30),
        ])
        .unwrap();
        assert_eq!(flipped.conclusion, CapabilityConclusion::NotAcquired);
    }

    #[test]
    fn task_success_re_strengthens_a_confirmed_word() {
        // confirmed → lapse → success → lapse: the success broke the streak,
        // so the newest lapse is again a single lapse (weakened, not flipped)
        let weakened = project(vec![
            confirmation(10),
            dictation(ObservationOutcome::Failure, 20),
            dictation(ObservationOutcome::Success, 30),
            dictation(ObservationOutcome::Failure, 40),
        ])
        .unwrap();
        assert_eq!(weakened.conclusion, CapabilityConclusion::Acquired);
        assert_eq!(weakened.confidence, Some(LISTENING_CONFIDENCE_WEAKENED));

        let restored = project(vec![
            confirmation(10),
            dictation(ObservationOutcome::Failure, 20),
            dictation(ObservationOutcome::Success, 30),
        ])
        .unwrap();
        assert_eq!(restored.conclusion, CapabilityConclusion::Acquired);
        assert_eq!(restored.confidence, Some(LISTENING_CONFIDENCE_TASK));
    }

    #[test]
    fn non_listening_observations_are_ignored() {
        let mut shadowing = obs(
            ObservationTaskType::Shadowing,
            ObservationOutcome::Success,
            AssistanceLevel::None,
            30,
        );
        shadowing.capability = LexicalCapability::Speaking;
        assert_eq!(project(vec![shadowing]), None);
    }
}
