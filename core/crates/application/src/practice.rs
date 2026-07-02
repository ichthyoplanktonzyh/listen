use crate::*;

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
        self.practice.create_practice_session(&session)
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
                let review = self.create_review_item(CreateReviewItem {
                    source: ReviewSource {
                        kind: ReviewSourceKind::PracticeFailure,
                        id: Some(attempt.id.as_str().to_owned()),
                        practice_attempt_id: Some(attempt.id.clone()),
                        lexical_entry_id: item
                            .anchors
                            .iter()
                            .find_map(|anchor| anchor.lexical_entry_id.clone()),
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
        self.review.create_review_item(&item)
    }

    pub fn review_item(&self, id: &ReviewItemId) -> Result<Option<ReviewItem>, ApplicationError> {
        self.review.get_review_item(id)
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
