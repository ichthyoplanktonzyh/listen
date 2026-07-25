use fsrs::{FSRS, ItemState, MemoryState, NextStates};

use crate::{
    PracticeAnchorKind, ReviewCard, ReviewCardKind, ReviewIntervalPreview, ReviewItem,
    ReviewRating, ReviewSchedule, ReviewSourceKind,
};

/// The identifier intentionally names both the algorithm generation and the
/// default parameter generation. Imported/custom parameters can use a
/// different suffix without changing the durable schedule shape.
pub(super) const REVIEW_ALGORITHM: &str = "fsrs_6_default_v1";
const DESIRED_RETENTION: f32 = 0.9;
const MINUTE_MS: u64 = 60_000;
const DAY_MS: u64 = 24 * 60 * MINUTE_MS;
const AGAIN_DELAY_MS: u64 = 10 * MINUTE_MS;

pub(super) fn migrate_legacy_schedule(current: &ReviewSchedule) -> ReviewSchedule {
    if current.stability.is_some()
        && current.difficulty.is_some()
        && current.last_reviewed_at_ms.is_some()
    {
        return current.clone();
    }

    let Some(interval_days) = current.interval_days.filter(|days| *days > 0.0) else {
        return ReviewSchedule {
            algorithm: REVIEW_ALGORITHM.into(),
            ..current.clone()
        };
    };

    // Existing Listen schedules are an SM-2-like heuristic. FSRS exposes an
    // explicit SM-2 migration function; using the existing interval and a
    // lapse-adjusted ease preserves progress instead of resetting the card.
    let ease = (2.5 - current.lapse_count as f32 * 0.15).clamp(1.3, 2.5);
    let memory = FSRS::default()
        .memory_state_from_sm2(ease, interval_days.max(1.0), DESIRED_RETENTION)
        .unwrap_or(MemoryState {
            stability: interval_days.max(0.1),
            difficulty: (5.0 + current.lapse_count as f32 * 0.5).clamp(1.0, 10.0),
        });
    let interval_ms = (interval_days * DAY_MS as f32) as u64;
    ReviewSchedule {
        algorithm: REVIEW_ALGORITHM.into(),
        stability: Some(memory.stability),
        difficulty: Some(memory.difficulty),
        last_reviewed_at_ms: current
            .last_reviewed_at_ms
            .or_else(|| Some(current.due_at_ms.saturating_sub(interval_ms))),
        review_count: current.review_count.max(1),
        ..current.clone()
    }
}

pub(super) fn next_review_schedule(
    current: &ReviewSchedule,
    rating: ReviewRating,
    reviewed_at_ms: u64,
) -> ReviewSchedule {
    schedule_for_rating(current, rating, reviewed_at_ms)
}

pub(super) fn preview_review_intervals(
    current: &ReviewSchedule,
    reviewed_at_ms: u64,
) -> Vec<ReviewIntervalPreview> {
    [
        ReviewRating::Again,
        ReviewRating::Hard,
        ReviewRating::Good,
        ReviewRating::Easy,
    ]
    .into_iter()
    .map(|rating| {
        let schedule = schedule_for_rating(current, rating, reviewed_at_ms);
        ReviewIntervalPreview {
            rating,
            due_at_ms: schedule.due_at_ms,
            interval_days: schedule.interval_days.unwrap_or_default(),
            state: schedule.state(),
        }
    })
    .collect()
}

fn schedule_for_rating(
    current: &ReviewSchedule,
    rating: ReviewRating,
    reviewed_at_ms: u64,
) -> ReviewSchedule {
    let current = migrate_legacy_schedule(current);
    let previous_state = current.state();
    let memory = current
        .stability
        .zip(current.difficulty)
        .map(|(stability, difficulty)| MemoryState {
            stability,
            difficulty,
        });
    let elapsed_days = current
        .last_reviewed_at_ms
        .map(|last| reviewed_at_ms.saturating_sub(last) / DAY_MS)
        .unwrap_or_default()
        .min(u32::MAX as u64) as u32;
    let states = FSRS::default()
        .next_states(memory, DESIRED_RETENTION, elapsed_days)
        .expect("stored FSRS memory state is finite");
    let selected = select_state(&states, rating);
    let is_learning_step = rating == ReviewRating::Again;
    let interval_days = if is_learning_step {
        0.0
    } else {
        selected.interval.round().max(1.0)
    };
    let delay_ms = if is_learning_step {
        AGAIN_DELAY_MS
    } else {
        (interval_days * DAY_MS as f32) as u64
    };

    ReviewSchedule {
        item_id: current.item_id,
        algorithm: REVIEW_ALGORITHM.into(),
        due_at_ms: reviewed_at_ms.saturating_add(delay_ms),
        stability: Some(selected.memory.stability),
        difficulty: Some(selected.memory.difficulty),
        interval_days: Some(interval_days),
        lapse_count: current.lapse_count.saturating_add(u32::from(
            rating == ReviewRating::Again
                && matches!(
                    previous_state,
                    domain::ReviewCardState::Review | domain::ReviewCardState::Relearning
                ),
        )),
        last_reviewed_at_ms: Some(reviewed_at_ms),
        review_count: current.review_count.saturating_add(1),
    }
}

fn select_state(states: &NextStates, rating: ReviewRating) -> ItemState {
    match rating {
        ReviewRating::Again => states.again.clone(),
        ReviewRating::Hard => states.hard.clone(),
        ReviewRating::Good => states.good.clone(),
        ReviewRating::Easy => states.easy.clone(),
    }
}

pub(super) fn review_card(item: &ReviewItem) -> ReviewCard {
    let kind = review_card_kind(item);
    let target = review_card_target(item, kind);
    let cue = match kind {
        ReviewCardKind::ChunkCloze => Some(cloze_prompt(
            &item.prompt_snapshot,
            target.as_deref().unwrap_or_default(),
        )),
        ReviewCardKind::PhrasePresence => target.clone(),
        ReviewCardKind::WordRecognition
        | ReviewCardKind::SourceSentenceRecall
        | ReviewCardKind::DelayedRetelling => None,
    };
    let answer = match kind {
        ReviewCardKind::WordRecognition => target
            .clone()
            .unwrap_or_else(|| item.prompt_snapshot.clone()),
        ReviewCardKind::ChunkCloze
        | ReviewCardKind::PhrasePresence
        | ReviewCardKind::SourceSentenceRecall
        | ReviewCardKind::DelayedRetelling => item.prompt_snapshot.clone(),
    };
    ReviewCard {
        kind,
        cue,
        answer,
        target,
    }
}

fn review_card_kind(item: &ReviewItem) -> ReviewCardKind {
    match item.source.kind {
        ReviewSourceKind::LexicalEntry => ReviewCardKind::WordRecognition,
        ReviewSourceKind::Chunk => ReviewCardKind::ChunkCloze,
        ReviewSourceKind::ConnectedSpeech => ReviewCardKind::PhrasePresence,
        ReviewSourceKind::Sentence => ReviewCardKind::SourceSentenceRecall,
        ReviewSourceKind::SpeakingAttempt => ReviewCardKind::DelayedRetelling,
        ReviewSourceKind::PracticeFailure | ReviewSourceKind::ListeningInbox => {
            if item
                .anchors
                .iter()
                .any(|anchor| anchor.kind == PracticeAnchorKind::ConnectedSpeech)
            {
                ReviewCardKind::PhrasePresence
            } else if item
                .anchors
                .iter()
                .any(|anchor| anchor.kind == PracticeAnchorKind::Chunk)
            {
                ReviewCardKind::ChunkCloze
            } else if item
                .anchors
                .iter()
                .any(|anchor| anchor.kind == PracticeAnchorKind::LexicalEntry)
            {
                ReviewCardKind::WordRecognition
            } else {
                ReviewCardKind::SourceSentenceRecall
            }
        }
    }
}

fn review_card_target(item: &ReviewItem, kind: ReviewCardKind) -> Option<String> {
    let anchor_kind = match kind {
        ReviewCardKind::WordRecognition => PracticeAnchorKind::LexicalEntry,
        ReviewCardKind::ChunkCloze => PracticeAnchorKind::Chunk,
        ReviewCardKind::PhrasePresence => PracticeAnchorKind::ConnectedSpeech,
        ReviewCardKind::SourceSentenceRecall | ReviewCardKind::DelayedRetelling => return None,
    };
    item.anchors
        .iter()
        .find(|anchor| anchor.kind == anchor_kind)
        .and_then(|anchor| anchor.label.as_deref())
        .map(str::trim)
        .filter(|label| !label.is_empty())
        .map(str::to_owned)
        .or_else(|| {
            (kind == ReviewCardKind::WordRecognition
                || item.source.kind == ReviewSourceKind::Chunk
                || item.source.kind == ReviewSourceKind::ConnectedSpeech)
                .then(|| item.prompt_snapshot.clone())
        })
}

fn cloze_prompt(snapshot: &str, target: &str) -> String {
    if target.is_empty() {
        return "____".into();
    }
    if let Some(start) = snapshot.find(target) {
        let mut prompt = snapshot.to_owned();
        prompt.replace_range(start..start + target.len(), "____");
        prompt
    } else {
        format!("{snapshot}\n____")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{PracticeAnchor, ReviewCardState, ReviewItemId, ReviewItemStatus, ReviewSource};

    fn new_schedule() -> ReviewSchedule {
        ReviewSchedule {
            item_id: ReviewItemId::parse("review-schedule-test").unwrap(),
            algorithm: REVIEW_ALGORITHM.into(),
            due_at_ms: 0,
            stability: None,
            difficulty: None,
            interval_days: None,
            lapse_count: 0,
            last_reviewed_at_ms: None,
            review_count: 0,
        }
    }

    #[test]
    fn fsrs_writes_memory_state_and_preserves_anki_learning_states() {
        let current = new_schedule();
        assert_eq!(current.state(), ReviewCardState::New);

        let failed = next_review_schedule(&current, ReviewRating::Again, 1_000);
        assert_eq!(failed.due_at_ms, 1_000 + AGAIN_DELAY_MS);
        assert_eq!(failed.state(), ReviewCardState::Learning);
        assert!(failed.stability.unwrap() > 0.0);
        assert!((1.0..=10.0).contains(&failed.difficulty.unwrap()));

        let first_success = next_review_schedule(&current, ReviewRating::Good, 1_000);
        assert_eq!(first_success.state(), ReviewCardState::Review);
        assert!(first_success.interval_days.unwrap() >= 1.0);
        assert_eq!(first_success.algorithm, REVIEW_ALGORITHM);

        let failed_review =
            next_review_schedule(&first_success, ReviewRating::Again, DAY_MS + 1_000);
        assert_eq!(failed_review.state(), ReviewCardState::Relearning);
        assert_eq!(failed_review.lapse_count, 1);
    }

    #[test]
    fn four_state_boundaries_are_derived_from_schedule_facts() {
        let mut schedule = new_schedule();
        assert_eq!(schedule.state(), ReviewCardState::New);
        schedule.review_count = 1;
        schedule.stability = Some(0.4);
        schedule.interval_days = Some(0.0);
        assert_eq!(schedule.state(), ReviewCardState::Learning);
        schedule.lapse_count = 1;
        assert_eq!(schedule.state(), ReviewCardState::Relearning);
        schedule.interval_days = Some(1.0);
        assert_eq!(schedule.state(), ReviewCardState::Review);
    }

    #[test]
    fn legacy_migration_preserves_interval_and_lapses() {
        let mut legacy = new_schedule();
        legacy.algorithm = "listen_review_v1_heuristic_proxy".into();
        legacy.interval_days = Some(30.0);
        legacy.due_at_ms = 100 * DAY_MS;
        legacy.lapse_count = 3;
        let migrated = migrate_legacy_schedule(&legacy);
        assert_eq!(migrated.interval_days, Some(30.0));
        assert_eq!(migrated.lapse_count, 3);
        assert_eq!(migrated.review_count, 1);
        assert!(migrated.stability.unwrap() > 0.0);
        assert!(migrated.last_reviewed_at_ms.is_some());
    }

    #[test]
    fn interval_preview_does_not_mutate_the_input() {
        let current = new_schedule();
        let snapshot = current.clone();
        let previews = preview_review_intervals(&current, 42);
        assert_eq!(previews.len(), 4);
        assert_eq!(current, snapshot);
    }

    #[test]
    fn review_cards_cover_audio_first_and_delayed_speaking_interactions() {
        let item = |source_kind, anchor_kind, label: Option<&str>, snapshot: &str| ReviewItem {
            id: ReviewItemId::parse(format!("review-{source_kind:?}")).unwrap(),
            source: ReviewSource {
                kind: source_kind,
                id: None,
                practice_attempt_id: None,
                lexical_entry_id: None,
                media_id: None,
                track_id: None,
            },
            anchors: label
                .map(|label| {
                    vec![PracticeAnchor {
                        kind: anchor_kind,
                        id: "anchor-1".into(),
                        label: Some(label.into()),
                        lexical_entry_id: None,
                        sentence_id: None,
                        token_start: None,
                        token_end: None,
                        start_ms: Some(100),
                        end_ms: Some(900),
                    }]
                })
                .unwrap_or_default(),
            prompt_snapshot: snapshot.into(),
            status: ReviewItemStatus::Active,
            created_at_ms: 1,
            updated_at_ms: 1,
        };

        let word = review_card(&item(
            ReviewSourceKind::LexicalEntry,
            PracticeAnchorKind::LexicalEntry,
            None,
            "would",
        ));
        assert_eq!(word.kind, ReviewCardKind::WordRecognition);
        assert_eq!(word.answer, "would");

        let chunk = review_card(&item(
            ReviewSourceKind::PracticeFailure,
            PracticeAnchorKind::Chunk,
            Some("would have"),
            "I would have gone",
        ));
        assert_eq!(chunk.kind, ReviewCardKind::ChunkCloze);
        assert_eq!(chunk.cue.as_deref(), Some("I ____ gone"));
        assert_eq!(chunk.target.as_deref(), Some("would have"));

        let phrase = review_card(&item(
            ReviewSourceKind::ConnectedSpeech,
            PracticeAnchorKind::ConnectedSpeech,
            Some("would have"),
            "I would have gone",
        ));
        assert_eq!(phrase.kind, ReviewCardKind::PhrasePresence);
        assert_eq!(phrase.cue.as_deref(), Some("would have"));

        let sentence = review_card(&item(
            ReviewSourceKind::Sentence,
            PracticeAnchorKind::Sentence,
            Some("I would have gone"),
            "I would have gone",
        ));
        assert_eq!(sentence.kind, ReviewCardKind::SourceSentenceRecall);
        assert_eq!(sentence.answer, "I would have gone");

        let delayed = review_card(&item(
            ReviewSourceKind::SpeakingAttempt,
            PracticeAnchorKind::Sentence,
            Some("en"),
            "The ferry leaves on Tuesday.",
        ));
        assert_eq!(delayed.kind, ReviewCardKind::DelayedRetelling);
        assert_eq!(delayed.answer, "The ferry leaves on Tuesday.");
        assert!(delayed.cue.is_none());
        assert!(delayed.target.is_none());
    }
}
