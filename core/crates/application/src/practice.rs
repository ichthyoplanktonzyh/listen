use std::collections::{BTreeSet, HashSet};

use crate::*;

mod review;
mod upgrade;
use review::{REVIEW_ALGORITHM, next_review_schedule, review_card};

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
                self.append_channelized_observation(
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
        if saved.result == PracticeResult::Correct {
            self.record_practice_recognition_evidence(&item, &saved, now)?;
        }
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
                    .map(|(item, schedule)| {
                        let card = review_card(&item);
                        ReviewQueueEntry {
                            item,
                            schedule,
                            card,
                        }
                    })
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
                self.append_channelized_observation(
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
                self.append_channelized_observation(
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
                    self.record_review_recognition_evidence(&item, &attempt, now)?
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
                "evidence_class": "heuristic_proxy",
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
        self.review
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
                    .learning_assets
                    .lexical_details(&lexical_entry_id)?
                    .is_some()
                && self.subtitle_tracks.get_sentence(sentence_id)?.is_some()
            {
                let observation =
                    self.learning_assets
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
            let existing = self.review.get_hunting_candidate(&id)?;
            let candidate = self.review.upsert_hunting_candidate(&HuntingCandidate {
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
    /// completed session: the self-report joins the report counters, scored
    /// practice attempts join the accuracy counters (skips excluded). The
    /// record is durable evidence separate from the fit cache; its watermark
    /// invalidates cached profiles so the next fit read re-derives the band.
    fn record_content_fit_feedback(
        &self,
        session: &PracticeSession,
        report: Option<ListeningComprehensionReport>,
    ) -> Result<(), ApplicationError> {
        let Some(media_id) = session.media_id.as_ref() else {
            return Ok(());
        };
        let mut attempts_total: u32 = 0;
        let mut attempts_correct: u32 = 0;
        for item in self
            .practice
            .list_practice_items_for_session(&session.id, 500, 0)?
        {
            for attempt in self
                .practice
                .list_practice_attempts_for_item(&item.id, 500, 0)?
            {
                match attempt.result {
                    PracticeResult::Correct => {
                        attempts_total += 1;
                        attempts_correct += 1;
                    }
                    PracticeResult::Partial | PracticeResult::Incorrect => attempts_total += 1,
                    PracticeResult::Skipped => {}
                }
            }
        }
        if report.is_none() && attempts_total == 0 {
            return Ok(());
        }
        let mut calibration = self
            .difficulty
            .get_fit_calibration("media", media_id.as_str())?
            .unwrap_or_else(|| SoundFitCalibration::new("media", media_id.as_str()));
        match report {
            Some(ListeningComprehensionReport::UnderstoodAll) => {
                calibration.reports_understood_all += 1
            }
            Some(ListeningComprehensionReport::GotTheGist) => calibration.reports_got_the_gist += 1,
            Some(ListeningComprehensionReport::Unclear) => calibration.reports_unclear += 1,
            None => {}
        }
        calibration.practice_attempts += attempts_total;
        calibration.practice_correct += attempts_correct;
        calibration.updated_at_ms = now_ms();
        self.difficulty.save_fit_calibration(&calibration)?;
        Ok(())
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
}
