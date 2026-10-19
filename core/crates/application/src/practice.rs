use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::sync::Arc;

use domain::ReviewCardState;

use crate::evaluator::{PracticeAnswerEvaluator, practice_result, practice_score};
use crate::{
    AppServices, ApplicationError, CompleteListeningSessionInput, CorpusIndexRepository,
    CreatePracticeItem, CreatePracticeSession, CreateReviewItem, DifficultyRepository,
    DisabledLearningLoopRepository, HuntingCandidate, HuntingCandidateId, HuntingCandidateStatus,
    HuntingRepository, HuntingTarget, HuntingTargetId, HuntingTargetStatus, LearningEvent,
    LearningEventId, LearningEventKind, LearningEventRepository, LearningEventSubject,
    LearningEventSubjectKind, LearningObservationRepository, LexicalEntryId,
    LexicalLearningUseCases, LexicalNormalizationProvider, LexicalObservation,
    LexicalObservationId, ListeningComprehensionReport, ListeningInboxItem, ListeningInboxItemId,
    ListeningInboxRepository, ListeningInboxStatus, MediaRepository, ObservationContext,
    ObservationOrigin, ObservationResult, PracticeAnchorKind, PracticeAttempt, PracticeAttemptId,
    PracticeItem, PracticeItemId, PracticeMode, PracticeRepository, PracticeResult,
    PracticeSession, PracticeSessionId, RecognitionEvidence, RecognitionUpgradeRepository,
    ReviewAttempt, ReviewAttemptId, ReviewItem, ReviewItemId, ReviewItemStatus, ReviewQueueEntry,
    ReviewQueueRepository, ReviewRating, ReviewSchedule, ReviewSource, ReviewSourceKind,
    ReviewSubmission, SoundFitCalibration, SubmitPracticeAttempt, SubmitReviewAttempt,
    SubtitleSentenceId, SubtitleTrackRepository, UpgradeSuggestion, UpgradeSuggestionId,
    UpgradeSuggestionStatus, clean_required, now_ms, observation_spec_for_practice,
    observation_spec_for_review,
};

mod review;
mod upgrade;
use review::{
    REVIEW_ALGORITHM, migrate_legacy_schedule, next_review_schedule, preview_review_intervals,
    review_card,
};

/// Owns practice sessions, review scheduling, hunting targets, and listening
/// inbox processing. They share learning-event and queue transition invariants;
/// lexical evidence is delegated to the lexical module.
#[derive(Clone)]
pub struct PracticeUseCases {
    pub(crate) practice: Arc<dyn PracticeRepository>,
    pub(crate) review_queue: Arc<dyn ReviewQueueRepository>,
    pub(crate) hunting: Arc<dyn HuntingRepository>,
    pub(crate) learning_events: Arc<dyn LearningEventRepository>,
    pub(crate) learning_observations: Arc<dyn LearningObservationRepository>,
    pub(crate) listening_inbox: Arc<dyn ListeningInboxRepository>,
    pub(crate) difficulty: Arc<dyn DifficultyRepository>,
    pub(crate) subtitle_tracks: Arc<dyn SubtitleTrackRepository>,
    pub(crate) corpus: Arc<dyn CorpusIndexRepository>,
    pub(crate) media: Arc<dyn MediaRepository>,
    pub(crate) lexical_normalizers: Arc<Vec<Arc<dyn LexicalNormalizationProvider>>>,
    lexical_learning: LexicalLearningUseCases,
}

impl PracticeUseCases {
    pub(crate) fn from_services(services: &AppServices) -> Self {
        Self {
            practice: services.practice.clone(),
            review_queue: services.review_queue.clone(),
            hunting: services.hunting.clone(),
            learning_events: services.learning_events.clone(),
            learning_observations: services.learning_observations.clone(),
            listening_inbox: services.listening_inbox.clone(),
            difficulty: services.difficulty.clone(),
            subtitle_tracks: services.subtitle_tracks.clone(),
            corpus: services.corpus.clone(),
            media: services.media.clone(),
            lexical_normalizers: services.lexical_normalizers.clone(),
            lexical_learning: LexicalLearningUseCases::from_services(services),
        }
    }

    pub(crate) fn lexical_learning(&self) -> &LexicalLearningUseCases {
        &self.lexical_learning
    }

    pub fn create_practice_session(
        &self,
        input: CreatePracticeSession,
    ) -> Result<PracticeSession, ApplicationError> {
        let now = now_ms();
        let source = clean_required(
            input.source.unwrap_or_else(|| "user_started".into()),
            "practice session source",
        )?;
        let fingerprint = format!(
            "{:?}:{}:{}:{now}",
            input.mode,
            input
                .media_id
                .as_ref()
                .map(|value| value.as_str())
                .unwrap_or(""),
            input
                .track_id
                .as_ref()
                .map(|value| value.as_str())
                .unwrap_or("")
        );
        let session = PracticeSession {
            id: PracticeSessionId::from_fingerprint("practice-session", &fingerprint),
            mode: input.mode,
            media_id: input.media_id,
            track_id: input.track_id,
            source,
            started_at_ms: now,
            ended_at_ms: None,
        };
        let saved = self.practice.create_practice_session(&session)?;
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint(
                "learning-event",
                &format!("listening-started:{}:{now}", saved.id.as_str()),
            ),
            occurred_at_ms: now,
            kind: LearningEventKind::ListeningStarted,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::PracticeSession,
                id: saved.id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "mode": saved.mode,
                "media_id": saved.media_id.as_ref().map(|value| value.as_str()),
                "track_id": saved.track_id.as_ref().map(|value| value.as_str()),
                "source": saved.source.as_str(),
            }),
            session_id: Some(saved.id.clone()),
        })?;
        Ok(saved)
    }

    pub fn create_practice_item(
        &self,
        input: CreatePracticeItem,
    ) -> Result<PracticeItem, ApplicationError> {
        let prompt_snapshot = clean_required(input.prompt_snapshot, "practice prompt")?;
        let expected_text = clean_required(input.expected_text, "practice expected answer")?;
        let now = now_ms();
        let fingerprint = format!(
            "{:?}:{}:{}:{now}",
            input.kind, prompt_snapshot, expected_text
        );
        let item = PracticeItem {
            id: PracticeItemId::from_fingerprint("practice-item", &fingerprint),
            session_id: input.session_id,
            kind: input.kind,
            target: input.target,
            prompt_snapshot,
            expected_answer: serde_json::json!({ "text": expected_text }),
            anchors: input.anchors,
            created_at_ms: now,
        };
        self.practice.create_practice_item(&item)
    }

    pub fn practice_attempt(
        &self,
        id: &PracticeAttemptId,
    ) -> Result<Option<PracticeAttempt>, ApplicationError> {
        self.practice.get_practice_attempt(id)
    }

    pub fn submit_practice_attempt(
        &self,
        input: SubmitPracticeAttempt,
    ) -> Result<PracticeAttempt, ApplicationError> {
        let item = self
            .practice
            .get_practice_item(&input.item_id)?
            .ok_or(ApplicationError::NotFound("practice item"))?;
        let expected_text = item
            .expected_answer
            .get("text")
            .and_then(|value| value.as_str())
            .ok_or(ApplicationError::Validation("practice expected answer"))?;
        // Issue #98 baseline: use the authoritative learning language and
        // abort before writing learner evidence if a configured normalizer
        // fails.
        let language = self.practice_item_language(&item)?;
        let evaluator = PracticeAnswerEvaluator::new(self.lexical_normalizers.clone(), language);
        let evaluation = evaluator.evaluate(item.kind, expected_text, &input.text_answer)?;
        let result = practice_result(&evaluation);
        let now = now_ms();
        let id = PracticeAttemptId::from_fingerprint(
            "practice-attempt",
            &format!("{}:{}:{now}", item.id.as_str(), input.text_answer),
        );
        let mut attempt = PracticeAttempt {
            id,
            item_id: item.id.clone(),
            submitted_at_ms: now,
            input: serde_json::json!({ "text": input.text_answer }),
            result,
            score: practice_score(&evaluation),
            evaluation,
            generated_observation_ids: Vec::new(),
            generated_review_item_ids: Vec::new(),
        };

        // Channelized evidence records success and failure alike (ADR 0017
        // decision 3); the legacy failure-only block below is unchanged.
        if let Some(spec) = observation_spec_for_practice(item.kind, result) {
            for anchor in item
                .anchors
                .iter()
                .filter(|value| value.kind == PracticeAnchorKind::LexicalEntry)
            {
                let Some(lexical_entry_id) = &anchor.lexical_entry_id else {
                    continue;
                };
                self.lexical_learning().append_channelized_observation(
                    lexical_entry_id,
                    spec,
                    ObservationContext {
                        surface_form: anchor.label.clone(),
                        sentence_id: anchor.sentence_id.clone(),
                        media_id: None,
                    },
                    ObservationOrigin::PracticeTask,
                    Some(attempt.id.as_str().to_owned()),
                    now,
                )?;
            }
        }

        if result != PracticeResult::Correct && result != PracticeResult::Skipped {
            for anchor in item
                .anchors
                .iter()
                .filter(|value| value.kind == PracticeAnchorKind::LexicalEntry)
            {
                let (Some(lexical_entry_id), Some(sentence_id)) =
                    (&anchor.lexical_entry_id, &anchor.sentence_id)
                else {
                    continue;
                };
                let original_form = anchor
                    .label
                    .clone()
                    .unwrap_or_else(|| lexical_entry_id.as_str().to_owned());
                let observation = LexicalObservation {
                    id: domain::lexical_observation_id(lexical_entry_id, sentence_id),
                    lexical_entry_id: lexical_entry_id.clone(),
                    sentence_id: sentence_id.clone(),
                    original_form,
                    result: ObservationResult::NotRecognizedInContext,
                    created_at_ms: now,
                };
                let saved = self
                    .learning_observations
                    .create_lexical_observation(&observation)?;
                attempt.generated_observation_ids.push(saved.id);
            }
            if input.create_review_item_on_failure {
                let source_session = item
                    .session_id
                    .as_ref()
                    .map(|id| self.practice.get_practice_session(id))
                    .transpose()?
                    .flatten();
                let review = self.create_review_item(CreateReviewItem {
                    source: ReviewSource {
                        kind: ReviewSourceKind::PracticeFailure,
                        id: Some(attempt.id.as_str().to_owned()),
                        practice_attempt_id: Some(attempt.id.clone()),
                        lexical_entry_id: item
                            .anchors
                            .iter()
                            .find_map(|anchor| anchor.lexical_entry_id.clone()),
                        media_id: source_session
                            .as_ref()
                            .and_then(|session| session.media_id.clone()),
                        track_id: source_session
                            .as_ref()
                            .and_then(|session| session.track_id.clone()),
                    },
                    anchors: item.anchors.clone(),
                    prompt_snapshot: item.prompt_snapshot.clone(),
                })?;
                attempt.generated_review_item_ids.push(review.id);
            }
        }

        let saved = self.practice.create_practice_attempt(&attempt)?;
        if saved.result == PracticeResult::Correct {
            self.lexical_learning()
                .record_practice_recognition_evidence(&item, &saved, now)?;
        }
        // Usage-feedback calibration (Phase 3.5 Slice 7, revised after 3.5.6):
        // intensive sessions are never "completed" anymore, so scored attempts
        // fold into the media's sound-fit calibration at submission time. Best
        // effort by design — fit is decoration, a submission must not fail on it.
        let _ = self.record_practice_accuracy_feedback(item.session_id.as_ref(), saved.result);
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint(
                "learning-event",
                &format!("practice-completed:{}:{now}", saved.id.as_str()),
            ),
            occurred_at_ms: now,
            kind: LearningEventKind::PracticeCompleted,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::PracticeAttempt,
                id: saved.id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "item_id": saved.item_id.as_str(),
                "result": saved.result,
                "score": saved.score,
            }),
            session_id: item.session_id,
        })?;
        Ok(saved)
    }

    fn practice_item_language(
        &self,
        item: &PracticeItem,
    ) -> Result<domain::LanguageCode, ApplicationError> {
        let sentence_ids = item.target.sentence_id.iter().chain(
            item.anchors
                .iter()
                .filter_map(|anchor| anchor.sentence_id.as_ref()),
        );
        for sentence_id in sentence_ids {
            if let Some(language) = self.subtitle_tracks.sentence_track_language(sentence_id)? {
                return Ok(language);
            }
        }
        if let Some(session_id) = item.session_id.as_ref()
            && let Some(session) = self.practice.get_practice_session(session_id)?
            && let Some(track_id) = session.track_id.as_ref()
            && let Some(track) = self.subtitle_tracks.get_track(track_id)?
            && let Some(language) = track.language
        {
            return Ok(language);
        }
        Ok(domain::LanguageCode::parse("en")?)
    }

    pub fn create_review_item(
        &self,
        input: CreateReviewItem,
    ) -> Result<ReviewItem, ApplicationError> {
        let prompt_snapshot = clean_required(input.prompt_snapshot, "review prompt")?;
        if input.source.kind == ReviewSourceKind::LexicalEntry
            || input.source.kind == ReviewSourceKind::SpeakingAttempt
        {
            let existing = self
                .review_queue
                .list_review_items(Some(ReviewItemStatus::Active), 200, 0)?
                .into_iter()
                .find(|item| {
                    (input.source.kind == ReviewSourceKind::LexicalEntry
                        && item.source.lexical_entry_id == input.source.lexical_entry_id
                        && item.prompt_snapshot == prompt_snapshot)
                        || (input.source.kind == ReviewSourceKind::SpeakingAttempt
                            && item.source.id == input.source.id)
                });
            if let Some(existing) = existing {
                return Ok(existing);
            }
        }
        let now = now_ms();
        let fingerprint = format!(
            "{:?}:{}:{}:{now}",
            input.source.kind,
            input.source.id.as_deref().unwrap_or(""),
            prompt_snapshot
        );
        let item = ReviewItem {
            id: ReviewItemId::from_fingerprint("review-item", &fingerprint),
            source: input.source,
            anchors: input.anchors,
            prompt_snapshot,
            status: ReviewItemStatus::Active,
            created_at_ms: now,
            updated_at_ms: now,
        };
        let saved = self.review_queue.create_review_item(&item)?;
        self.review_queue.save_review_schedule(&ReviewSchedule {
            item_id: saved.id.clone(),
            algorithm: REVIEW_ALGORITHM.into(),
            due_at_ms: now,
            stability: None,
            difficulty: None,
            interval_days: None,
            lapse_count: 0,
            last_reviewed_at_ms: None,
            review_count: 0,
        })?;
        Ok(saved)
    }

    pub fn review_item(&self, id: &ReviewItemId) -> Result<Option<ReviewItem>, ApplicationError> {
        self.review_queue.get_review_item(id)
    }

    pub fn due_review_items(
        &self,
        at_ms: Option<u64>,
        limit: u32,
    ) -> Result<Vec<ReviewQueueEntry>, ApplicationError> {
        self.review_queue(at_ms, limit).map(|queue| queue.entries)
    }

    pub fn review_queue(
        &self,
        at_ms: Option<u64>,
        limit: u32,
    ) -> Result<crate::ReviewQueue, ApplicationError> {
        let at_ms = at_ms.unwrap_or_else(now_ms);
        let status = self.review_limit_status(at_ms)?;
        let remaining_new = status.limits.new_cards.saturating_sub(status.new_completed);
        let remaining_reviews = status
            .limits
            .reviews
            .saturating_sub(status.reviews_completed);
        let mut accepted_new = 0;
        let mut accepted_reviews = 0;
        let mut entries = Vec::new();
        let mut imported_origins = self
            .review_queue
            .list_imported_deck_schedules()?
            .into_iter()
            .map(|entry| {
                (
                    entry.item_id,
                    crate::ReviewItemOrigin {
                        kind: crate::ReviewOriginKind::ImportedAnki,
                        anki_guid: Some(entry.anki_guid),
                        deck_id: Some(entry.deck_id),
                        deck_name: Some(entry.name),
                        has_listening_enhancements: false,
                    },
                )
            })
            .collect::<HashMap<_, _>>();
        for (item, schedule) in self.review_queue.list_due_review_items(at_ms, 10_000)? {
            let schedule = migrate_legacy_schedule(&schedule);
            let accepted = match schedule.state() {
                ReviewCardState::New if accepted_new >= remaining_new => false,
                ReviewCardState::New => {
                    accepted_new += 1;
                    true
                }
                ReviewCardState::Review if accepted_reviews >= remaining_reviews => false,
                ReviewCardState::Review => {
                    accepted_reviews += 1;
                    true
                }
                // Intraday learning/relearning steps are already committed
                // work and do not consume a second daily new/review slot.
                ReviewCardState::Learning | ReviewCardState::Relearning => true,
            };
            if accepted {
                let origin = imported_origins.remove(&item.id);
                entries.push(review_queue_entry(item, schedule, origin));
            }
            if entries.len() >= limit.min(100) as usize {
                break;
            }
        }
        Ok(crate::ReviewQueue {
            entries,
            limit_status: status,
        })
    }

    pub fn review_daily_limits(&self) -> Result<crate::ReviewDailyLimits, ApplicationError> {
        self.review_queue.get_review_daily_limits()
    }

    pub fn update_review_daily_limits(
        &self,
        limits: crate::ReviewDailyLimits,
    ) -> Result<crate::ReviewDailyLimits, ApplicationError> {
        if limits.new_cards > 10_000 || limits.reviews > 10_000 {
            return Err(ApplicationError::Invalid(
                "daily review limits must be at most 10000".into(),
            ));
        }
        self.review_queue.save_review_daily_limits(limits)
    }

    pub fn review_deck_overview(
        &self,
        at_ms: Option<u64>,
    ) -> Result<crate::ReviewDeckOverview, ApplicationError> {
        let at_ms = at_ms.unwrap_or_else(now_ms);
        let imported = self.review_queue.list_imported_deck_schedules()?;
        let imported_ids = imported
            .iter()
            .map(|entry| entry.item_id.clone())
            .collect::<HashSet<_>>();
        let mut channels = [
            crate::ReviewChannel::Listening,
            crate::ReviewChannel::Speaking,
            crate::ReviewChannel::Reading,
            crate::ReviewChannel::Writing,
        ]
        .into_iter()
        .map(|channel| crate::ReviewChannelCounts {
            channel,
            counts: crate::ReviewStateCounts::default(),
        })
        .collect::<Vec<_>>();
        for (item, schedule) in self.review_queue.list_review_items_with_schedules(10_000)? {
            if imported_ids.contains(&item.id) {
                continue;
            }
            let channel = primary_review_channel(&item);
            let counts = &mut channels
                .iter_mut()
                .find(|entry| entry.channel == channel)
                .expect("all channels are initialized")
                .counts;
            add_schedule_count(counts, &migrate_legacy_schedule(&schedule), at_ms);
        }

        let mut decks =
            BTreeMap::<(String, String, Option<String>), crate::ReviewStateCounts>::new();
        for entry in imported {
            add_schedule_count(
                decks
                    .entry((entry.deck_id, entry.name, entry.parent_deck_id))
                    .or_default(),
                &migrate_legacy_schedule(&entry.schedule),
                at_ms,
            );
        }
        Ok(crate::ReviewDeckOverview {
            channels,
            imported_decks: decks
                .into_iter()
                .map(
                    |((deck_id, name, parent_deck_id), counts)| crate::ImportedDeckCounts {
                        deck_id,
                        name,
                        parent_deck_id,
                        counts,
                    },
                )
                .collect(),
            limit_status: self.review_limit_status(at_ms)?,
        })
    }

    pub fn custom_study(
        &self,
        request: crate::CustomStudyRequest,
    ) -> Result<crate::CustomStudyQueue, ApplicationError> {
        let at_ms = request.at_ms.unwrap_or_else(now_ms);
        let limit = request.limit.unwrap_or(20).min(100) as usize;
        let imported_origins = self
            .review_queue
            .list_imported_deck_schedules()?
            .into_iter()
            .map(|entry| {
                (
                    entry.item_id,
                    crate::ReviewItemOrigin {
                        kind: crate::ReviewOriginKind::ImportedAnki,
                        anki_guid: Some(entry.anki_guid),
                        deck_id: Some(entry.deck_id),
                        deck_name: Some(entry.name),
                        has_listening_enhancements: false,
                    },
                )
            })
            .collect::<HashMap<_, _>>();
        let mut entries = self
            .review_queue
            .list_review_items_with_schedules(10_000)?
            .into_iter()
            .filter_map(|(item, schedule)| {
                let schedule = migrate_legacy_schedule(&schedule);
                let selected = match &request.kind {
                    crate::CustomStudyKind::MoreNew => schedule.state() == ReviewCardState::New,
                    crate::CustomStudyKind::ReviewAhead => {
                        schedule.state() != ReviewCardState::New && schedule.due_at_ms > at_ms
                    }
                    crate::CustomStudyKind::Channel { channel } => {
                        !imported_origins.contains_key(&item.id)
                            && primary_review_channel(&item) == *channel
                    }
                    crate::CustomStudyKind::Forgotten { minimum_lapses } => {
                        schedule.lapse_count >= minimum_lapses.unwrap_or(2).max(1)
                    }
                };
                selected.then(|| {
                    let origin = imported_origins.get(&item.id).cloned();
                    review_queue_entry(item, schedule, origin)
                })
            })
            .collect::<Vec<_>>();
        if matches!(&request.kind, crate::CustomStudyKind::Forgotten { .. }) {
            entries.sort_by_key(|entry| std::cmp::Reverse(entry.schedule.lapse_count));
        }
        entries.truncate(limit);
        Ok(crate::CustomStudyQueue {
            entries,
            advances_normal_schedule: matches!(&request.kind, crate::CustomStudyKind::ReviewAhead),
        })
    }

    pub fn import_anki_package(
        &self,
        request: crate::AnkiPackageImportRequest,
    ) -> Result<crate::AnkiPackageImportSummary, ApplicationError> {
        if request.package_path.trim().is_empty() || request.media_directory.trim().is_empty() {
            return Err(ApplicationError::Validation("anki package paths"));
        }
        self.review_queue.import_anki_package(&request)
    }

    pub fn export_anki_package(
        &self,
        request: crate::AnkiPackageExportRequest,
    ) -> Result<crate::AnkiPackageExportSummary, ApplicationError> {
        if request.package_path.trim().is_empty() {
            return Err(ApplicationError::Validation("anki export path"));
        }
        self.review_queue.export_anki_package(&request)
    }

    /// Pure FSRS prediction. It reads the schedule once and performs no
    /// repository write.
    pub fn review_interval_preview(
        &self,
        id: &ReviewItemId,
        at_ms: Option<u64>,
    ) -> Result<Vec<crate::ReviewIntervalPreview>, ApplicationError> {
        self.review_queue
            .get_review_schedule(id)?
            .map(|schedule| preview_review_intervals(&schedule, at_ms.unwrap_or_else(now_ms)))
            .ok_or(ApplicationError::NotFound("review schedule"))
    }

    fn review_limit_status(
        &self,
        at_ms: u64,
    ) -> Result<crate::ReviewLimitStatus, ApplicationError> {
        let day_start = at_ms - at_ms % (24 * 60 * 60 * 1_000);
        let (new_completed, reviews_completed) = self
            .review_queue
            .review_attempt_counts_between(day_start, day_start + 24 * 60 * 60 * 1_000)?;
        let limits = self.review_queue.get_review_daily_limits()?;
        Ok(crate::ReviewLimitStatus {
            limits,
            new_completed,
            reviews_completed,
            new_limit_reached: new_completed >= limits.new_cards,
            review_limit_reached: reviews_completed >= limits.reviews,
        })
    }

    pub fn submit_review_attempt(
        &self,
        input: SubmitReviewAttempt,
    ) -> Result<ReviewSubmission, ApplicationError> {
        self.submit_review_attempt_internal(input, true)
    }

    pub fn submit_custom_study_attempt(
        &self,
        input: crate::SubmitCustomStudyAttempt,
    ) -> Result<ReviewSubmission, ApplicationError> {
        let advances_normal_schedule = matches!(&input.kind, crate::CustomStudyKind::ReviewAhead);
        self.submit_review_attempt_internal(
            SubmitReviewAttempt {
                item_id: input.item_id,
                rating: input.rating,
            },
            advances_normal_schedule,
        )
    }

    fn submit_review_attempt_internal(
        &self,
        input: SubmitReviewAttempt,
        advances_normal_schedule: bool,
    ) -> Result<ReviewSubmission, ApplicationError> {
        let item = self
            .review_queue
            .get_review_item(&input.item_id)?
            .ok_or(ApplicationError::NotFound("review item"))?;
        if item.status != ReviewItemStatus::Active {
            return Err(ApplicationError::Conflict("review item is not active"));
        }
        let now = now_ms();
        let current = self
            .review_queue
            .get_review_schedule(&item.id)?
            .unwrap_or(ReviewSchedule {
                item_id: item.id.clone(),
                algorithm: REVIEW_ALGORITHM.into(),
                due_at_ms: now,
                stability: None,
                difficulty: None,
                interval_days: None,
                lapse_count: 0,
                last_reviewed_at_ms: None,
                review_count: 0,
            });
        let proposed_schedule = next_review_schedule(&current, input.rating, now);
        let schedule = if advances_normal_schedule {
            proposed_schedule
        } else {
            migrate_legacy_schedule(&current)
        };
        let fingerprint = format!("{}:{now}:{:?}", item.id.as_str(), input.rating);
        let attempt = self.review_queue.create_review_attempt(&ReviewAttempt {
            id: ReviewAttemptId::from_fingerprint("review-attempt", &fingerprint),
            item_id: item.id.clone(),
            reviewed_at_ms: now,
            rating: input.rating,
            practice_attempt_id: None,
            next_due_at_ms: Some(schedule.due_at_ms),
            previous_state: Some(current.state()),
            advances_schedule: advances_normal_schedule,
        })?;
        let schedule = if advances_normal_schedule {
            self.review_queue.save_review_schedule(&schedule)?
        } else {
            schedule
        };
        {
            let spec = observation_spec_for_review(input.rating);
            let fallback_sentence = item
                .anchors
                .iter()
                .find_map(|anchor| anchor.sentence_id.clone());
            let mut observed = HashSet::new();
            for anchor in item
                .anchors
                .iter()
                .filter(|value| value.kind == PracticeAnchorKind::LexicalEntry)
            {
                let Some(lexical_entry_id) = &anchor.lexical_entry_id else {
                    continue;
                };
                if !observed.insert(lexical_entry_id.clone()) {
                    continue;
                }
                self.lexical_learning().append_channelized_observation(
                    lexical_entry_id,
                    spec,
                    ObservationContext {
                        surface_form: anchor.label.clone(),
                        sentence_id: anchor
                            .sentence_id
                            .clone()
                            .or_else(|| fallback_sentence.clone()),
                        media_id: item.source.media_id.clone(),
                    },
                    ObservationOrigin::ReviewTask,
                    Some(attempt.id.as_str().to_owned()),
                    now,
                )?;
            }
            if let Some(lexical_entry_id) = item.source.lexical_entry_id.as_ref()
                && observed.insert(lexical_entry_id.clone())
            {
                self.lexical_learning().append_channelized_observation(
                    lexical_entry_id,
                    spec,
                    ObservationContext {
                        surface_form: None,
                        sentence_id: fallback_sentence.clone(),
                        media_id: item.source.media_id.clone(),
                    },
                    ObservationOrigin::ReviewTask,
                    Some(attempt.id.as_str().to_owned()),
                    now,
                )?;
            }
        }
        let (generated_observation_ids, hunting_candidate_ids, upgrade_suggestions) =
            if input.rating == ReviewRating::Again {
                let (observations, candidates) = self.record_review_failure(&item, now)?;
                (observations, candidates, Vec::new())
            } else {
                let suggestions = if matches!(input.rating, ReviewRating::Good | ReviewRating::Easy)
                {
                    self.lexical_learning()
                        .record_review_recognition_evidence(&item, &attempt, now)?
                } else {
                    Vec::new()
                };
                (Vec::new(), Vec::new(), suggestions)
            };
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint("learning-event", &fingerprint),
            occurred_at_ms: now,
            kind: LearningEventKind::ReviewCompleted,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::ReviewItem,
                id: item.id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "rating": input.rating,
                "next_due_at_ms": schedule.due_at_ms,
                "algorithm": schedule.algorithm,
                "evidence_class": "fsrs_schedule",
                "custom_study_extra_practice": !advances_normal_schedule,
                "generated_observation_ids": generated_observation_ids
                    .iter()
                    .map(|id| id.as_str())
                    .collect::<Vec<_>>(),
                "hunting_candidate_ids": hunting_candidate_ids
                    .iter()
                    .map(|id| id.as_str())
                    .collect::<Vec<_>>(),
                "upgrade_suggestion_ids": upgrade_suggestions
                    .iter()
                    .map(|suggestion| suggestion.id.as_str())
                    .collect::<Vec<_>>(),
            }),
            session_id: None,
        })?;
        Ok(ReviewSubmission {
            attempt,
            schedule,
            generated_observation_ids,
            hunting_candidate_ids,
            upgrade_suggestions,
        })
    }

    pub fn hunting_candidates(
        &self,
        status: Option<HuntingCandidateStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<HuntingCandidate>, ApplicationError> {
        self.hunting
            .list_hunting_candidates(status, limit.min(500), offset)
    }

    fn record_review_failure(
        &self,
        item: &ReviewItem,
        failed_at_ms: u64,
    ) -> Result<(Vec<LexicalObservationId>, Vec<HuntingCandidateId>), ApplicationError> {
        let mut targets = Vec::<(LexicalEntryId, String, Option<SubtitleSentenceId>)>::new();
        if let Some(lexical_entry_id) = item.source.lexical_entry_id.clone() {
            let matching_anchor = item
                .anchors
                .iter()
                .find(|anchor| anchor.lexical_entry_id.as_ref() == Some(&lexical_entry_id));
            targets.push((
                lexical_entry_id,
                matching_anchor
                    .and_then(|anchor| anchor.label.clone())
                    .unwrap_or_else(|| item.prompt_snapshot.clone()),
                matching_anchor
                    .and_then(|anchor| anchor.sentence_id.clone())
                    .or_else(|| {
                        item.anchors
                            .iter()
                            .find_map(|anchor| anchor.sentence_id.clone())
                    }),
            ));
        }
        for anchor in &item.anchors {
            let Some(lexical_entry_id) = anchor.lexical_entry_id.clone() else {
                continue;
            };
            targets.push((
                lexical_entry_id,
                anchor
                    .label
                    .clone()
                    .unwrap_or_else(|| item.prompt_snapshot.clone()),
                anchor.sentence_id.clone(),
            ));
        }

        let mut seen = BTreeSet::new();
        let mut generated_observation_ids = Vec::new();
        let mut hunting_candidate_ids = Vec::new();
        for (lexical_entry_id, target_snapshot, sentence_id) in targets {
            if !seen.insert(lexical_entry_id.as_str().to_owned()) {
                continue;
            }
            if let Some(sentence_id) = sentence_id.as_ref()
                && self
                    .lexical_learning()
                    .lexical_entries
                    .lexical_details(&lexical_entry_id)?
                    .is_some()
                && self.subtitle_tracks.get_sentence(sentence_id)?.is_some()
            {
                let observation =
                    self.learning_observations
                        .create_lexical_observation(&LexicalObservation {
                            id: domain::lexical_observation_id(&lexical_entry_id, sentence_id),
                            lexical_entry_id: lexical_entry_id.clone(),
                            sentence_id: sentence_id.clone(),
                            original_form: target_snapshot.clone(),
                            result: ObservationResult::NotRecognizedInContext,
                            created_at_ms: failed_at_ms,
                        })?;
                generated_observation_ids.push(observation.id);
            }

            let id = HuntingCandidateId::from_fingerprint(
                "hunting-candidate",
                &format!("{}:{}", item.id.as_str(), lexical_entry_id.as_str()),
            );
            let existing = self.hunting.get_hunting_candidate(&id)?;
            let candidate = self.hunting.upsert_hunting_candidate(&HuntingCandidate {
                id,
                lexical_entry_id,
                review_item_id: item.id.clone(),
                sentence_id,
                media_id: item.source.media_id.clone(),
                track_id: item.source.track_id.clone(),
                target_snapshot,
                prompt_snapshot: item.prompt_snapshot.clone(),
                failure_count: existing
                    .as_ref()
                    .map_or(1, |value| value.failure_count.saturating_add(1)),
                status: HuntingCandidateStatus::Active,
                created_at_ms: existing
                    .as_ref()
                    .map_or(failed_at_ms, |value| value.created_at_ms),
                last_failed_at_ms: failed_at_ms,
            })?;
            hunting_candidate_ids.push(candidate.id);
        }
        Ok((generated_observation_ids, hunting_candidate_ids))
    }

    /// Completes an extensive-listening session without projecting obsolete
    /// intensive-listening session state from historical stuck-point events.
    pub fn complete_listening_session(
        &self,
        id: &PracticeSessionId,
        input: CompleteListeningSessionInput,
    ) -> Result<PracticeSession, ApplicationError> {
        if let Some(summary) = input.hunting_summary.as_ref() {
            let answered_count = summary
                .recognized_count
                .checked_add(summary.not_recognized_count)
                .and_then(|value| value.checked_add(summary.not_noticed_count))
                .ok_or(ApplicationError::Validation(
                    "hunting completion counts overflow",
                ))?;
            if summary.prompted_count > 5 || answered_count > summary.prompted_count {
                return Err(ApplicationError::Validation(
                    "hunting completion counts exceed the session prompt budget",
                ));
            }
        }
        let mut session = self
            .practice
            .get_practice_session(id)?
            .ok_or(ApplicationError::NotFound("practice session"))?;
        if session.mode != PracticeMode::Extensive {
            return Err(ApplicationError::Validation(
                "only extensive listening sessions can be completed",
            ));
        }
        let already_completed = session.ended_at_ms.is_some();
        let now = now_ms();
        session.ended_at_ms = Some(now);
        let session = self.practice.create_practice_session(&session)?;
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint(
                "learning-event",
                &format!("listening-completed:{}:{now}", session.id.as_str()),
            ),
            occurred_at_ms: now,
            kind: LearningEventKind::ListeningCompleted,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::PracticeSession,
                id: session.id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "mode": session.mode,
                "media_id": session.media_id.as_ref().map(|value| value.as_str()),
                "track_id": session.track_id.as_ref().map(|value| value.as_str()),
                "comprehension_report": input.comprehension_report,
                "hunting_summary": input.hunting_summary,
            }),
            session_id: Some(session.id.clone()),
        })?;
        // Usage-feedback calibration (Phase 3.5 Slice 7): fold this
        // session's comprehension self-report and practice accuracy into the
        // media's durable sound-fit calibration record. Best effort by
        // design — fit is decoration, so completing a session must never
        // fail because the calibration store is unavailable, and re-runs of
        // an already-completed session must not double count.
        if !already_completed {
            let _ = self.record_content_fit_feedback(&session, input.comprehension_report);
        }
        Ok(session)
    }

    /// Increments the media's recorded calibration counters from one
    /// completed extensive session's self-report. Scored practice attempts
    /// join the accuracy counters at submission time instead (see
    /// [`Self::record_practice_accuracy_feedback`]) because intensive
    /// sessions no longer complete. The record is durable evidence separate
    /// from the fit cache; its watermark invalidates cached profiles so the
    /// next fit read re-derives the band.
    fn record_content_fit_feedback(
        &self,
        session: &PracticeSession,
        report: Option<ListeningComprehensionReport>,
    ) -> Result<(), ApplicationError> {
        let Some(media_id) = session.media_id.as_ref() else {
            return Ok(());
        };
        let Some(report) = report else {
            return Ok(());
        };
        let mut calibration = self
            .difficulty
            .get_fit_calibration("media", media_id.as_str())?
            .unwrap_or_else(|| SoundFitCalibration::new("media", media_id.as_str()));
        match report {
            ListeningComprehensionReport::UnderstoodAll => calibration.reports_understood_all += 1,
            ListeningComprehensionReport::GotTheGist => calibration.reports_got_the_gist += 1,
            ListeningComprehensionReport::Unclear => calibration.reports_unclear += 1,
        }
        calibration.updated_at_ms = now_ms();
        self.difficulty.save_fit_calibration(&calibration)?;
        Ok(())
    }

    /// One scored practice attempt joins its media's calibration counters
    /// (skips excluded). Attempt-time accounting cannot double count: each
    /// attempt is folded exactly once, when it is created.
    fn record_practice_accuracy_feedback(
        &self,
        session_id: Option<&PracticeSessionId>,
        result: PracticeResult,
    ) -> Result<(), ApplicationError> {
        if matches!(result, PracticeResult::Completed | PracticeResult::Skipped) {
            return Ok(());
        }
        let Some(session_id) = session_id else {
            return Ok(());
        };
        let Some(session) = self.practice.get_practice_session(session_id)? else {
            return Ok(());
        };
        let Some(media_id) = session.media_id.as_ref() else {
            return Ok(());
        };
        let mut calibration = self
            .difficulty
            .get_fit_calibration("media", media_id.as_str())?
            .unwrap_or_else(|| SoundFitCalibration::new("media", media_id.as_str()));
        calibration.practice_attempts += 1;
        if result == PracticeResult::Correct {
            calibration.practice_correct += 1;
        }
        calibration.updated_at_ms = now_ms();
        self.difficulty.save_fit_calibration(&calibration)?;
        Ok(())
    }
}

fn review_queue_entry(
    item: ReviewItem,
    schedule: ReviewSchedule,
    origin: Option<crate::ReviewItemOrigin>,
) -> ReviewQueueEntry {
    let state = schedule.state();
    let card = review_card(&item);
    ReviewQueueEntry {
        item,
        schedule,
        state,
        card,
        origin: origin.unwrap_or_else(crate::ReviewItemOrigin::native),
    }
}

/// Native cards are assigned to one deterministic primary smart deck so a
/// multi-anchor card is never double-counted. Imported Anki cards are excluded
/// before this rule and remain in their original deck tree.
fn primary_review_channel(item: &ReviewItem) -> crate::ReviewChannel {
    match item.source.kind {
        ReviewSourceKind::SpeakingAttempt => crate::ReviewChannel::Speaking,
        ReviewSourceKind::Sentence => crate::ReviewChannel::Reading,
        ReviewSourceKind::PracticeFailure
            if item
                .anchors
                .iter()
                .all(|anchor| anchor.kind == PracticeAnchorKind::Sentence) =>
        {
            crate::ReviewChannel::Writing
        }
        ReviewSourceKind::LexicalEntry
        | ReviewSourceKind::PracticeFailure
        | ReviewSourceKind::ListeningInbox
        | ReviewSourceKind::Chunk
        | ReviewSourceKind::ConnectedSpeech => crate::ReviewChannel::Listening,
    }
}

fn add_schedule_count(
    counts: &mut crate::ReviewStateCounts,
    schedule: &ReviewSchedule,
    at_ms: u64,
) {
    match schedule.state() {
        ReviewCardState::New => counts.new += 1,
        ReviewCardState::Learning | ReviewCardState::Relearning => {
            counts.learning += 1;
        }
        ReviewCardState::Review if schedule.due_at_ms <= at_ms => counts.due += 1,
        ReviewCardState::Review => {}
    }
}

impl PracticeRepository for DisabledLearningLoopRepository {
    fn create_practice_session(
        &self,
        _session: &PracticeSession,
    ) -> Result<PracticeSession, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_practice_session(
        &self,
        _id: &PracticeSessionId,
    ) -> Result<Option<PracticeSession>, ApplicationError> {
        Err(Self::disabled())
    }

    fn create_practice_item(&self, _item: &PracticeItem) -> Result<PracticeItem, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_practice_item(
        &self,
        _id: &PracticeItemId,
    ) -> Result<Option<PracticeItem>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_practice_items_for_session(
        &self,
        _session_id: &PracticeSessionId,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<PracticeItem>, ApplicationError> {
        Err(Self::disabled())
    }

    fn create_practice_attempt(
        &self,
        _attempt: &PracticeAttempt,
    ) -> Result<PracticeAttempt, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_practice_attempt(
        &self,
        _id: &PracticeAttemptId,
    ) -> Result<Option<PracticeAttempt>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_practice_attempts_for_item(
        &self,
        _item_id: &PracticeItemId,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<PracticeAttempt>, ApplicationError> {
        Err(Self::disabled())
    }
}

impl ReviewQueueRepository for DisabledLearningLoopRepository {
    fn create_review_item(&self, _item: &ReviewItem) -> Result<ReviewItem, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_review_item(&self, _id: &ReviewItemId) -> Result<Option<ReviewItem>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_review_items(
        &self,
        _status: Option<ReviewItemStatus>,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<ReviewItem>, ApplicationError> {
        Err(Self::disabled())
    }

    fn create_review_attempt(
        &self,
        _attempt: &ReviewAttempt,
    ) -> Result<ReviewAttempt, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_review_attempt(
        &self,
        _id: &ReviewAttemptId,
    ) -> Result<Option<ReviewAttempt>, ApplicationError> {
        Err(Self::disabled())
    }

    fn save_review_schedule(
        &self,
        _schedule: &ReviewSchedule,
    ) -> Result<ReviewSchedule, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_review_schedule(
        &self,
        _item_id: &ReviewItemId,
    ) -> Result<Option<ReviewSchedule>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_due_review_items(
        &self,
        _due_at_or_before_ms: u64,
        _limit: u32,
    ) -> Result<Vec<(ReviewItem, ReviewSchedule)>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_review_items_with_schedules(
        &self,
        _limit: u32,
    ) -> Result<Vec<(ReviewItem, ReviewSchedule)>, ApplicationError> {
        Err(Self::disabled())
    }

    fn review_attempt_counts_between(
        &self,
        _start_ms: u64,
        _end_ms: u64,
    ) -> Result<(u32, u32), ApplicationError> {
        Err(Self::disabled())
    }

    fn get_review_daily_limits(&self) -> Result<crate::ReviewDailyLimits, ApplicationError> {
        Err(Self::disabled())
    }

    fn save_review_daily_limits(
        &self,
        _limits: crate::ReviewDailyLimits,
    ) -> Result<crate::ReviewDailyLimits, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_imported_deck_schedules(
        &self,
    ) -> Result<Vec<crate::ImportedDeckSchedule>, ApplicationError> {
        Err(Self::disabled())
    }

    fn import_anki_package(
        &self,
        _request: &crate::AnkiPackageImportRequest,
    ) -> Result<crate::AnkiPackageImportSummary, ApplicationError> {
        Err(Self::disabled())
    }

    fn export_anki_package(
        &self,
        _request: &crate::AnkiPackageExportRequest,
    ) -> Result<crate::AnkiPackageExportSummary, ApplicationError> {
        Err(Self::disabled())
    }
}

impl HuntingRepository for DisabledLearningLoopRepository {
    fn upsert_hunting_candidate(
        &self,
        _candidate: &HuntingCandidate,
    ) -> Result<HuntingCandidate, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_hunting_candidate(
        &self,
        _id: &HuntingCandidateId,
    ) -> Result<Option<HuntingCandidate>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_hunting_candidates(
        &self,
        _status: Option<HuntingCandidateStatus>,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<HuntingCandidate>, ApplicationError> {
        Err(Self::disabled())
    }

    fn upsert_hunting_target(
        &self,
        _target: &HuntingTarget,
    ) -> Result<HuntingTarget, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_hunting_target(
        &self,
        _id: &HuntingTargetId,
    ) -> Result<Option<HuntingTarget>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_hunting_targets(
        &self,
        _status: Option<HuntingTargetStatus>,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<HuntingTarget>, ApplicationError> {
        Err(Self::disabled())
    }
}

impl RecognitionUpgradeRepository for DisabledLearningLoopRepository {
    fn upsert_recognition_evidence(
        &self,
        evidence: &RecognitionEvidence,
    ) -> Result<RecognitionEvidence, ApplicationError> {
        Ok(evidence.clone())
    }

    fn list_recognition_evidence(
        &self,
        _lexical_entry_id: &LexicalEntryId,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<RecognitionEvidence>, ApplicationError> {
        Ok(Vec::new())
    }

    fn save_upgrade_suggestion(
        &self,
        suggestion: &UpgradeSuggestion,
    ) -> Result<UpgradeSuggestion, ApplicationError> {
        Ok(suggestion.clone())
    }

    fn get_upgrade_suggestion(
        &self,
        _id: &UpgradeSuggestionId,
    ) -> Result<Option<UpgradeSuggestion>, ApplicationError> {
        Ok(None)
    }

    fn list_upgrade_suggestions(
        &self,
        _lexical_entry_id: Option<&LexicalEntryId>,
        _status: Option<UpgradeSuggestionStatus>,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<UpgradeSuggestion>, ApplicationError> {
        Ok(Vec::new())
    }
}

impl LearningEventRepository for DisabledLearningLoopRepository {
    fn append_learning_event(
        &self,
        _event: &LearningEvent,
    ) -> Result<LearningEvent, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_learning_events(
        &self,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<LearningEvent>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_learning_events_for_session(
        &self,
        _session_id: &PracticeSessionId,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<LearningEvent>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_event_subject_ids(
        &self,
        _kind: LearningEventKind,
        _subject_kind: LearningEventSubjectKind,
    ) -> Result<Vec<String>, ApplicationError> {
        Err(Self::disabled())
    }
}

impl ListeningInboxRepository for DisabledLearningLoopRepository {
    fn upsert_listening_inbox_item(
        &self,
        _item: &ListeningInboxItem,
    ) -> Result<ListeningInboxItem, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_listening_inbox_item(
        &self,
        _id: &ListeningInboxItemId,
    ) -> Result<Option<ListeningInboxItem>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_listening_inbox_items(
        &self,
        _status: Option<ListeningInboxStatus>,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<ListeningInboxItem>, ApplicationError> {
        Err(Self::disabled())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::evaluator::PracticeAnswerEvaluator;
    use domain::PracticeTokenResult;

    #[test]
    fn text_evaluation_marks_partial_answers() {
        let evaluator = PracticeAnswerEvaluator::new(
            Arc::new(Vec::new()),
            domain::LanguageCode::parse("en").unwrap(),
        );
        let evaluation = evaluator
            .evaluate(
                domain::PracticeKind::Dictation,
                "I want to go",
                "I wanna go",
            )
            .unwrap();
        assert_eq!(practice_result(&evaluation), PracticeResult::Partial);
        // The key invariant is that the trailing exact token remains aligned.
        assert!(
            evaluation
                .token_results
                .iter()
                .any(|t| t.result == PracticeTokenResult::Correct)
        );
        assert!(
            !evaluation
                .token_results
                .iter()
                .all(|t| t.result == PracticeTokenResult::Mismatch)
        );
    }
}
