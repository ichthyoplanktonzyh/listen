use std::collections::{BTreeMap, BTreeSet, HashMap};

use crate::*;

const REVIEW_ALGORITHM: &str = "listen_review_v1_heuristic_proxy";
const MINUTE_MS: u64 = 60_000;
const DAY_MS: u64 = 24 * 60 * MINUTE_MS;

fn next_review_schedule(
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

impl AppServices {
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
        let evaluation = evaluate_text_answer(expected_text, &input.text_answer);
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
                    .learning_assets
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

    pub fn create_review_item(
        &self,
        input: CreateReviewItem,
    ) -> Result<ReviewItem, ApplicationError> {
        let prompt_snapshot = clean_required(input.prompt_snapshot, "review prompt")?;
        if input.source.kind == ReviewSourceKind::LexicalEntry {
            let existing = self
                .review
                .list_review_items(Some(ReviewItemStatus::Active), 200, 0)?
                .into_iter()
                .find(|item| {
                    item.source.lexical_entry_id == input.source.lexical_entry_id
                        && item.prompt_snapshot == prompt_snapshot
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
        let saved = self.review.create_review_item(&item)?;
        self.review.save_review_schedule(&ReviewSchedule {
            item_id: saved.id.clone(),
            algorithm: REVIEW_ALGORITHM.into(),
            due_at_ms: now,
            stability: None,
            difficulty: None,
            interval_days: None,
            lapse_count: 0,
        })?;
        Ok(saved)
    }

    pub fn review_item(&self, id: &ReviewItemId) -> Result<Option<ReviewItem>, ApplicationError> {
        self.review.get_review_item(id)
    }

    pub fn due_review_items(
        &self,
        at_ms: Option<u64>,
        limit: u32,
    ) -> Result<Vec<ReviewQueueEntry>, ApplicationError> {
        self.review
            .list_due_review_items(at_ms.unwrap_or_else(now_ms), limit.min(100))
            .map(|entries| {
                entries
                    .into_iter()
                    .map(|(item, schedule)| ReviewQueueEntry { item, schedule })
                    .collect()
            })
    }

    pub fn submit_review_attempt(
        &self,
        input: SubmitReviewAttempt,
    ) -> Result<ReviewSubmission, ApplicationError> {
        let item = self
            .review
            .get_review_item(&input.item_id)?
            .ok_or(ApplicationError::NotFound("review item"))?;
        if item.status != ReviewItemStatus::Active {
            return Err(ApplicationError::Conflict("review item is not active"));
        }
        let now = now_ms();
        let current = self
            .review
            .get_review_schedule(&item.id)?
            .unwrap_or(ReviewSchedule {
                item_id: item.id.clone(),
                algorithm: REVIEW_ALGORITHM.into(),
                due_at_ms: now,
                stability: None,
                difficulty: None,
                interval_days: None,
                lapse_count: 0,
            });
        let schedule = next_review_schedule(&current, input.rating, now);
        let fingerprint = format!("{}:{now}:{:?}", item.id.as_str(), input.rating);
        let attempt = self.review.create_review_attempt(&ReviewAttempt {
            id: ReviewAttemptId::from_fingerprint("review-attempt", &fingerprint),
            item_id: item.id.clone(),
            reviewed_at_ms: now,
            rating: input.rating,
            practice_attempt_id: None,
            next_due_at_ms: Some(schedule.due_at_ms),
        })?;
        let schedule = self.review.save_review_schedule(&schedule)?;
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
                "evidence_class": "heuristic_proxy",
            }),
            session_id: None,
        })?;
        Ok(ReviewSubmission { attempt, schedule })
    }

    pub fn mark_stuck_point(
        &self,
        input: RecordStuckPointInput,
    ) -> Result<LearningEvent, ApplicationError> {
        self.append_stuck_point_event(
            input.session_id,
            input.target,
            input.anchors,
            input.label,
            input.diagnosis_hints,
            LearningEventKind::StuckPointMarked,
        )
    }

    pub fn skip_stuck_point(
        &self,
        input: RecordStuckPointInput,
    ) -> Result<LearningEvent, ApplicationError> {
        self.append_stuck_point_event(
            input.session_id,
            input.target,
            input.anchors,
            input.label,
            input.diagnosis_hints,
            LearningEventKind::StuckPointSkipped,
        )
    }

    pub fn record_diagnosis_view(
        &self,
        input: RecordDiagnosisViewInput,
    ) -> Result<LearningEvent, ApplicationError> {
        self.append_stuck_point_event(
            input.session_id,
            input.target,
            input.anchors,
            input.label,
            input.diagnosis_hints,
            LearningEventKind::DiagnosisViewed,
        )
    }

    pub fn close_stuck_point(
        &self,
        input: CloseStuckPointInput,
    ) -> Result<LearningEvent, ApplicationError> {
        let session = self
            .practice
            .get_practice_session(&input.session_id)?
            .ok_or(ApplicationError::NotFound("practice session"))?;
        let target_key = clean_required(input.target_key, "stuck point target")?;
        let now = now_ms();
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint(
                "learning-event",
                &format!(
                    "stuck-point-closed:{}:{target_key}:{now}",
                    session.id.as_str()
                ),
            ),
            occurred_at_ms: now,
            kind: LearningEventKind::StuckPointClosed,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::PracticeSession,
                id: session.id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "target_key": target_key,
                "reason": input.reason,
            }),
            session_id: Some(session.id),
        })
    }

    pub fn complete_practice_session(
        &self,
        id: &PracticeSessionId,
        input: CompletePracticeSessionInput,
    ) -> Result<PracticeSessionSummary, ApplicationError> {
        let mut session = self
            .practice
            .get_practice_session(id)?
            .ok_or(ApplicationError::NotFound("practice session"))?;
        let before = self.practice_session_summary(id)?;
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
                "open_count": before.open_count,
                "unexplained_count": before.unexplained_count,
                "comprehension_report": input.comprehension_report,
            }),
            session_id: Some(session.id.clone()),
        })?;
        if input.mark_familiar {
            let subject = session
                .media_id
                .as_ref()
                .map(|media_id| LearningEventSubject {
                    kind: LearningEventSubjectKind::Media,
                    id: media_id.as_str().to_owned(),
                })
                .unwrap_or_else(|| LearningEventSubject {
                    kind: LearningEventSubjectKind::PracticeSession,
                    id: session.id.as_str().to_owned(),
                });
            self.learning_events.append_learning_event(&LearningEvent {
                id: LearningEventId::from_fingerprint(
                    "learning-event",
                    &format!("familiar-material:{}:{now}", session.id.as_str()),
                ),
                occurred_at_ms: now,
                kind: LearningEventKind::FamiliarMaterialMarked,
                subject,
                payload: serde_json::json!({
                    "session_id": session.id.as_str(),
                    "media_id": session.media_id.as_ref().map(|value| value.as_str()),
                    "track_id": session.track_id.as_ref().map(|value| value.as_str()),
                }),
                session_id: Some(session.id.clone()),
            })?;
        }
        self.practice_session_summary(&session.id)
    }

    pub fn practice_session_summary(
        &self,
        id: &PracticeSessionId,
    ) -> Result<PracticeSessionSummary, ApplicationError> {
        let session = self
            .practice
            .get_practice_session(id)?
            .ok_or(ApplicationError::NotFound("practice session"))?;
        let events = self
            .learning_events
            .list_learning_events_for_session(id, 1000, 0)?;
        let items = self.practice.list_practice_items_for_session(id, 500, 0)?;
        let mut item_by_id = HashMap::new();
        let mut attempts = Vec::new();
        for item in items {
            let item_attempts = self
                .practice
                .list_practice_attempts_for_item(&item.id, 500, 0)?;
            attempts.extend(item_attempts);
            item_by_id.insert(item.id.as_str().to_owned(), item);
        }
        let attempt_by_id = attempts
            .iter()
            .map(|attempt| (attempt.id.as_str().to_owned(), attempt))
            .collect::<HashMap<_, _>>();
        let mut points = BTreeMap::<String, StuckPointBuilder>::new();
        let mut familiar_material_marked = false;

        for event in &events {
            familiar_material_marked |= event.kind == LearningEventKind::FamiliarMaterialMarked;
            apply_event_to_stuck_points(&mut points, event);
        }

        for attempt in &attempts {
            let Some(item) = item_by_id.get(attempt.item_id.as_str()) else {
                continue;
            };
            let key = practice_target_key(&item.target);
            let should_create =
                attempt.result != PracticeResult::Correct || points.contains_key(&key);
            if !should_create {
                continue;
            }
            let point = points
                .entry(key.clone())
                .or_insert_with(|| StuckPointBuilder::new(key, attempt.submitted_at_ms));
            point.merge_item(item);
            point.updated_at_ms = point.updated_at_ms.max(attempt.submitted_at_ms);
            push_unique(&mut point.practice_attempt_ids, attempt.id.clone());
            match attempt.result {
                PracticeResult::Correct => point.verified = true,
                PracticeResult::Skipped => point.skipped = true,
                PracticeResult::Partial | PracticeResult::Incorrect => {}
            }
        }

        let review_items = self.review.list_review_items(None, 500, 0)?;
        for review in review_items {
            let Some(attempt_id) = review.source.practice_attempt_id.as_ref() else {
                continue;
            };
            let Some(attempt) = attempt_by_id.get(attempt_id.as_str()) else {
                continue;
            };
            let Some(item) = item_by_id.get(attempt.item_id.as_str()) else {
                continue;
            };
            let key = practice_target_key(&item.target);
            let point = points
                .entry(key.clone())
                .or_insert_with(|| StuckPointBuilder::new(key, review.updated_at_ms));
            point.merge_item(item);
            point.updated_at_ms = point.updated_at_ms.max(review.updated_at_ms);
            point.added_review = true;
            push_unique(&mut point.review_item_ids, review.id);
        }

        let mut stuck_points = points
            .into_values()
            .map(StuckPointBuilder::into_summary)
            .collect::<Vec<_>>();
        stuck_points.sort_by_key(|point| {
            (
                point.marked_at_ms.unwrap_or(point.updated_at_ms),
                point.target_key.clone(),
            )
        });

        let mut attribution_map = BTreeMap::<(String, Option<String>), u32>::new();
        for point in &stuck_points {
            let mut seen = BTreeSet::<(String, Option<String>)>::new();
            for hint in &point.diagnosis_hints {
                if hint.reasons.is_empty() {
                    seen.insert((hint.kind.clone(), None));
                } else {
                    for reason in &hint.reasons {
                        seen.insert((hint.kind.clone(), Some(reason.clone())));
                    }
                }
            }
            for key in seen {
                *attribution_map.entry(key).or_default() += 1;
            }
        }
        let mut attribution_counts = attribution_map
            .into_iter()
            .map(|((kind, reason), count)| StuckPointAttribution {
                kind,
                reason,
                count,
            })
            .collect::<Vec<_>>();
        attribution_counts.sort_by(|left, right| {
            right
                .count
                .cmp(&left.count)
                .then_with(|| left.kind.cmp(&right.kind))
                .then_with(|| left.reason.cmp(&right.reason))
        });

        let status_count = |status| {
            stuck_points
                .iter()
                .filter(|point| point.status == status)
                .count() as u32
        };
        let active_verified_count = status_count(StuckPointStatus::ActivelyVerified);
        let resolved_with_hint_count = status_count(StuckPointStatus::ResolvedWithHint);
        let unexplained_count = status_count(StuckPointStatus::Unexplained);
        let marked_count = status_count(StuckPointStatus::Marked);
        Ok(PracticeSessionSummary {
            session,
            stuck_count: stuck_points.len() as u32,
            resolved_count: active_verified_count + resolved_with_hint_count,
            active_verified_count,
            review_count: status_count(StuckPointStatus::AddedToReview),
            unexplained_count,
            skipped_count: status_count(StuckPointStatus::Skipped),
            closed_count: status_count(StuckPointStatus::Closed),
            open_count: marked_count + unexplained_count,
            attribution_counts,
            familiar_material_marked,
            stuck_points,
        })
    }

    fn append_stuck_point_event(
        &self,
        session_id: PracticeSessionId,
        target: PracticeTarget,
        anchors: Vec<PracticeAnchor>,
        label: Option<String>,
        diagnosis_hints: Vec<DiagnosisHintEvidence>,
        kind: LearningEventKind,
    ) -> Result<LearningEvent, ApplicationError> {
        let session = self
            .practice
            .get_practice_session(&session_id)?
            .ok_or(ApplicationError::NotFound("practice session"))?;
        let target_key = practice_target_key(&target);
        let now = now_ms();
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint(
                "learning-event",
                &format!("{kind:?}:{}:{target_key}:{now}", session.id.as_str()),
            ),
            occurred_at_ms: now,
            kind,
            subject: subject_for_target(&target, &target_key),
            payload: serde_json::json!({
                "target_key": target_key,
                "target": target,
                "anchors": anchors,
                "label": label,
                "diagnosis_hints": diagnosis_hints,
                "media_id": session.media_id.as_ref().map(|value| value.as_str()),
                "track_id": session.track_id.as_ref().map(|value| value.as_str()),
            }),
            session_id: Some(session.id),
        })
    }
}

#[derive(Debug, Clone)]
struct StuckPointBuilder {
    target_key: String,
    target: Option<PracticeTarget>,
    anchors: Vec<PracticeAnchor>,
    label: Option<String>,
    marked_at_ms: Option<u64>,
    updated_at_ms: u64,
    playback_start_ms: Option<u64>,
    playback_end_ms: Option<u64>,
    practice_attempt_ids: Vec<PracticeAttemptId>,
    review_item_ids: Vec<ReviewItemId>,
    diagnosis_hints: Vec<DiagnosisHintEvidence>,
    diagnosis_viewed: bool,
    verified: bool,
    added_review: bool,
    skipped: bool,
    closed: bool,
}

impl StuckPointBuilder {
    fn new(target_key: String, occurred_at_ms: u64) -> Self {
        Self {
            target_key,
            target: None,
            anchors: Vec::new(),
            label: None,
            marked_at_ms: None,
            updated_at_ms: occurred_at_ms,
            playback_start_ms: None,
            playback_end_ms: None,
            practice_attempt_ids: Vec::new(),
            review_item_ids: Vec::new(),
            diagnosis_hints: Vec::new(),
            diagnosis_viewed: false,
            verified: false,
            added_review: false,
            skipped: false,
            closed: false,
        }
    }

    fn merge_item(&mut self, item: &PracticeItem) {
        if self.target.is_none() {
            self.target = Some(item.target.clone());
        }
        if self.anchors.is_empty() {
            self.anchors = item.anchors.clone();
        }
        if self.label.is_none() {
            self.label = item_label(item);
        }
        self.merge_playback(item.target.start_ms, item.target.end_ms);
        for anchor in &item.anchors {
            self.merge_playback(anchor.start_ms, anchor.end_ms);
        }
    }

    fn merge_event(
        &mut self,
        event: &LearningEvent,
        target: Option<PracticeTarget>,
        anchors: Vec<PracticeAnchor>,
        label: Option<String>,
        hints: Vec<DiagnosisHintEvidence>,
    ) {
        if self.marked_at_ms.is_none()
            && matches!(
                event.kind,
                LearningEventKind::StuckPointMarked
                    | LearningEventKind::StuckPointSkipped
                    | LearningEventKind::DiagnosisViewed
            )
        {
            self.marked_at_ms = Some(event.occurred_at_ms);
        }
        self.updated_at_ms = self.updated_at_ms.max(event.occurred_at_ms);
        if self.target.is_none() {
            self.target = target;
        }
        if self.anchors.is_empty() && !anchors.is_empty() {
            self.anchors = anchors;
        }
        if self.label.is_none() {
            self.label = label;
        }
        for hint in hints {
            if !self.diagnosis_hints.contains(&hint) {
                self.diagnosis_hints.push(hint);
            }
        }
        if let Some(target) = &self.target {
            self.merge_playback(target.start_ms, target.end_ms);
        }
        let anchors = self.anchors.clone();
        for anchor in anchors {
            self.merge_playback(anchor.start_ms, anchor.end_ms);
        }
    }

    fn merge_playback(&mut self, start_ms: Option<u64>, end_ms: Option<u64>) {
        let (Some(start), Some(end)) = (start_ms, end_ms) else {
            return;
        };
        self.playback_start_ms = Some(
            self.playback_start_ms
                .map_or(start, |value| value.min(start)),
        );
        self.playback_end_ms = Some(self.playback_end_ms.map_or(end, |value| value.max(end)));
    }

    fn into_summary(self) -> StuckPointSummary {
        let status = if self.closed {
            StuckPointStatus::Closed
        } else if self.skipped {
            StuckPointStatus::Skipped
        } else if self.added_review {
            StuckPointStatus::AddedToReview
        } else if self.verified {
            StuckPointStatus::ActivelyVerified
        } else if self.diagnosis_viewed && !self.diagnosis_hints.is_empty() {
            StuckPointStatus::ResolvedWithHint
        } else if self.diagnosis_viewed {
            StuckPointStatus::Unexplained
        } else {
            StuckPointStatus::Marked
        };
        StuckPointSummary {
            target_key: self.target_key,
            status,
            target: self.target,
            anchors: self.anchors,
            label: self.label,
            marked_at_ms: self.marked_at_ms,
            updated_at_ms: self.updated_at_ms,
            playback_start_ms: self.playback_start_ms,
            playback_end_ms: self.playback_end_ms,
            practice_attempt_ids: self.practice_attempt_ids,
            review_item_ids: self.review_item_ids,
            diagnosis_hints: self.diagnosis_hints,
        }
    }
}

fn apply_event_to_stuck_points(
    points: &mut BTreeMap<String, StuckPointBuilder>,
    event: &LearningEvent,
) {
    let is_stuck_event = matches!(
        event.kind,
        LearningEventKind::StuckPointMarked
            | LearningEventKind::StuckPointSkipped
            | LearningEventKind::DiagnosisViewed
            | LearningEventKind::StuckPointClosed
    );
    if !is_stuck_event {
        return;
    }
    let target = event_payload_target(&event.payload);
    let key = event
        .payload
        .get("target_key")
        .and_then(|value| value.as_str())
        .map(str::to_owned)
        .or_else(|| target.as_ref().map(practice_target_key));
    let Some(key) = key else {
        return;
    };
    let anchors = event_payload_anchors(&event.payload);
    let label = event
        .payload
        .get("label")
        .and_then(|value| value.as_str())
        .map(str::to_owned);
    let hints = event_payload_diagnosis_hints(&event.payload);
    let point = points
        .entry(key.clone())
        .or_insert_with(|| StuckPointBuilder::new(key, event.occurred_at_ms));
    point.merge_event(event, target, anchors, label, hints);
    match event.kind {
        LearningEventKind::StuckPointMarked => {}
        LearningEventKind::StuckPointSkipped => point.skipped = true,
        LearningEventKind::DiagnosisViewed => {
            point.diagnosis_viewed = true;
        }
        LearningEventKind::StuckPointClosed => point.closed = true,
        _ => {}
    }
}

fn event_payload_target(payload: &serde_json::Value) -> Option<PracticeTarget> {
    serde_json::from_value(payload.get("target")?.clone()).ok()
}

fn event_payload_anchors(payload: &serde_json::Value) -> Vec<PracticeAnchor> {
    payload
        .get("anchors")
        .cloned()
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn event_payload_diagnosis_hints(payload: &serde_json::Value) -> Vec<DiagnosisHintEvidence> {
    payload
        .get("diagnosis_hints")
        .cloned()
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn practice_target_key(target: &PracticeTarget) -> String {
    match target.kind {
        PracticeTargetKind::Sentence => target
            .sentence_id
            .as_ref()
            .map(|value| format!("sentence:{}", value.as_str()))
            .or_else(|| target.id.as_ref().map(|value| format!("sentence:{value}")))
            .unwrap_or_else(|| playback_target_key("sentence", target)),
        PracticeTargetKind::Chunk => target
            .chunk_id
            .as_ref()
            .map(|value| format!("chunk:{}", value.as_str()))
            .or_else(|| target.id.as_ref().map(|value| format!("chunk:{value}")))
            .unwrap_or_else(|| playback_target_key("chunk", target)),
        PracticeTargetKind::Lexical => target
            .id
            .as_ref()
            .map(|value| format!("lexical:{value}"))
            .unwrap_or_else(|| playback_target_key("lexical", target)),
        PracticeTargetKind::Segment => playback_target_key("segment", target),
        PracticeTargetKind::ConnectedSpeech => target
            .id
            .as_ref()
            .map(|value| format!("connected_speech:{value}"))
            .unwrap_or_else(|| playback_target_key("connected_speech", target)),
    }
}

fn playback_target_key(prefix: &str, target: &PracticeTarget) -> String {
    format!(
        "{}:{}:{}:{}",
        prefix,
        target
            .sentence_id
            .as_ref()
            .map(|value| value.as_str())
            .unwrap_or(""),
        target.start_ms.unwrap_or(0),
        target.end_ms.unwrap_or(0)
    )
}

fn subject_for_target(target: &PracticeTarget, target_key: &str) -> LearningEventSubject {
    match target.kind {
        PracticeTargetKind::Sentence => LearningEventSubject {
            kind: LearningEventSubjectKind::Sentence,
            id: target
                .sentence_id
                .as_ref()
                .map(|value| value.as_str().to_owned())
                .or_else(|| target.id.clone())
                .unwrap_or_else(|| target_key.to_owned()),
        },
        PracticeTargetKind::Chunk => LearningEventSubject {
            kind: LearningEventSubjectKind::Chunk,
            id: target
                .chunk_id
                .as_ref()
                .map(|value| value.as_str().to_owned())
                .or_else(|| target.id.clone())
                .unwrap_or_else(|| target_key.to_owned()),
        },
        PracticeTargetKind::Lexical => LearningEventSubject {
            kind: LearningEventSubjectKind::LexicalEntry,
            id: target.id.clone().unwrap_or_else(|| target_key.to_owned()),
        },
        PracticeTargetKind::Segment | PracticeTargetKind::ConnectedSpeech => LearningEventSubject {
            kind: LearningEventSubjectKind::PracticeSession,
            id: target_key.to_owned(),
        },
    }
}

fn item_label(item: &PracticeItem) -> Option<String> {
    item.anchors
        .iter()
        .find_map(|anchor| anchor.label.clone())
        .or_else(|| Some(item.prompt_snapshot.clone()))
}

fn push_unique<T: PartialEq>(values: &mut Vec<T>, value: T) {
    if !values.contains(&value) {
        values.push(value);
    }
}

fn evaluate_text_answer(expected: &str, actual: &str) -> PracticeEvaluation {
    let expected_tokens = normalize_answer_tokens(expected);
    let actual_tokens = normalize_answer_tokens(actual);
    let max_len = expected_tokens.len().max(actual_tokens.len());
    let mut token_results = Vec::with_capacity(max_len);
    for index in 0..max_len {
        let expected = expected_tokens.get(index).cloned();
        let actual = actual_tokens.get(index).cloned();
        let result = match (&expected, &actual) {
            (Some(left), Some(right)) if left == right => PracticeTokenResult::Correct,
            (Some(_), Some(_)) => PracticeTokenResult::Mismatch,
            (Some(_), None) => PracticeTokenResult::Missing,
            (None, Some(_)) => PracticeTokenResult::Extra,
            (None, None) => continue,
        };
        token_results.push(PracticeTokenEvaluation {
            expected,
            actual,
            result,
        });
    }
    let correct = token_results
        .iter()
        .filter(|value| value.result == PracticeTokenResult::Correct)
        .count();
    PracticeEvaluation {
        summary: format!("{correct}/{} tokens matched", expected_tokens.len()),
        token_results,
        extra: serde_json::json!({
            "expected_token_count": expected_tokens.len(),
            "actual_token_count": actual_tokens.len(),
        }),
    }
}

fn normalize_answer_tokens(value: &str) -> Vec<String> {
    value
        .split_whitespace()
        .map(|token| {
            token
                .trim_matches(|ch: char| !ch.is_alphanumeric() && ch != '\'')
                .to_ascii_lowercase()
        })
        .filter(|token| !token.is_empty())
        .collect()
}

fn practice_result(evaluation: &PracticeEvaluation) -> PracticeResult {
    if evaluation.token_results.is_empty() {
        return PracticeResult::Skipped;
    }
    if evaluation
        .token_results
        .iter()
        .all(|value| value.result == PracticeTokenResult::Correct)
    {
        PracticeResult::Correct
    } else if evaluation
        .token_results
        .iter()
        .any(|value| value.result == PracticeTokenResult::Correct)
    {
        PracticeResult::Partial
    } else {
        PracticeResult::Incorrect
    }
}

fn practice_score(evaluation: &PracticeEvaluation) -> Option<f32> {
    if evaluation.token_results.is_empty() {
        return None;
    }
    let correct = evaluation
        .token_results
        .iter()
        .filter(|value| value.result == PracticeTokenResult::Correct)
        .count();
    Some(correct as f32 / evaluation.token_results.len() as f32)
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

impl ReviewRepository for DisabledLearningLoopRepository {
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

    #[test]
    fn text_evaluation_marks_partial_answers() {
        let evaluation = evaluate_text_answer("I want to go", "I wanna go");
        assert_eq!(practice_result(&evaluation), PracticeResult::Partial);
        assert_eq!(evaluation.token_results.len(), 4);
        assert_eq!(
            evaluation.token_results[0].result,
            PracticeTokenResult::Correct
        );
        assert_eq!(
            evaluation.token_results[1].result,
            PracticeTokenResult::Mismatch
        );
    }

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
}
