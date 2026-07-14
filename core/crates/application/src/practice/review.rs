use crate::{
    PracticeAnchorKind, ReviewCard, ReviewCardKind, ReviewItem, ReviewRating, ReviewSchedule,
    ReviewSourceKind,
};

pub(super) const REVIEW_ALGORITHM: &str = "listen_review_v1_heuristic_proxy";
const MINUTE_MS: u64 = 60_000;
const DAY_MS: u64 = 24 * 60 * MINUTE_MS;

pub(super) fn next_review_schedule(
    current: &ReviewSchedule,
    rating: ReviewRating,
    reviewed_at_ms: u64,
) -> ReviewSchedule {
    let previous_days = current.interval_days.unwrap_or(0.0);
    let (interval_days, delay_ms, lapse_count) = match rating {
        ReviewRating::Again => (0.0, 10 * MINUTE_MS, current.lapse_count.saturating_add(1)),
        ReviewRating::Hard => (1.0, DAY_MS, current.lapse_count),
        ReviewRating::Good => {
            let days = if previous_days < 1.0 {
                3.0
            } else if previous_days <= 3.0 {
                7.0
            } else {
                (previous_days * 2.0).min(60.0)
            };
            (days, (days * DAY_MS as f32) as u64, current.lapse_count)
        }
        ReviewRating::Easy => {
            let days = if previous_days < 1.0 {
                7.0
            } else {
                (previous_days * 2.5).clamp(7.0, 90.0)
            };
            (days, (days * DAY_MS as f32) as u64, current.lapse_count)
        }
    };
    ReviewSchedule {
        item_id: current.item_id.clone(),
        algorithm: REVIEW_ALGORITHM.into(),
        due_at_ms: reviewed_at_ms.saturating_add(delay_ms),
        stability: None,
        difficulty: None,
        interval_days: Some(interval_days),
        lapse_count,
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
        ReviewCardKind::WordRecognition | ReviewCardKind::SourceSentenceRecall => None,
    };
    let answer = match kind {
        ReviewCardKind::WordRecognition => target
            .clone()
            .unwrap_or_else(|| item.prompt_snapshot.clone()),
        ReviewCardKind::ChunkCloze
        | ReviewCardKind::PhrasePresence
        | ReviewCardKind::SourceSentenceRecall => item.prompt_snapshot.clone(),
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
        ReviewCardKind::SourceSentenceRecall => return None,
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
    use domain::{PracticeAnchor, ReviewItemId, ReviewItemStatus, ReviewSource};

    #[test]
    fn review_scheduler_uses_short_failure_and_growing_success_intervals() {
        let current = ReviewSchedule {
            item_id: ReviewItemId::parse("review-schedule-test").unwrap(),
            algorithm: REVIEW_ALGORITHM.into(),
            due_at_ms: 0,
            stability: None,
            difficulty: None,
            interval_days: None,
            lapse_count: 0,
        };
        let failed = next_review_schedule(&current, ReviewRating::Again, 1_000);
        assert_eq!(failed.due_at_ms, 1_000 + 10 * MINUTE_MS);
        assert_eq!(failed.lapse_count, 1);

        let first_success = next_review_schedule(&current, ReviewRating::Good, 1_000);
        assert_eq!(first_success.interval_days, Some(3.0));
        let later_success = next_review_schedule(&first_success, ReviewRating::Good, 1_000);
        assert_eq!(later_success.interval_days, Some(7.0));
    }

    #[test]
    fn review_cards_cover_the_four_audio_first_interactions() {
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
    }
}
