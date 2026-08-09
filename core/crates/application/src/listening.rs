use crate::{
    ApplicationError, CaptureListeningInboxItemInput, CreatePracticeItem, CreateReviewItem,
    LearningEvent, LearningEventId, LearningEventKind, LearningEventSubject,
    LearningEventSubjectKind, ListeningInboxItem, ListeningInboxItemId, ListeningInboxResolution,
    ListeningInboxStatus, PracticeKind, PracticeTarget, PracticeTargetKind, PracticeUseCases,
    ProcessListeningInboxItemInput, ReviewSource, ReviewSourceKind, clean_optional, clean_required,
    now_ms,
};

const DEFAULT_INBOX_EXPIRY_DAYS: u64 = 7;
const DAY_MS: u64 = 24 * 60 * 60 * 1000;

impl PracticeUseCases {
    pub fn capture_listening_inbox_item(
        &self,
        input: CaptureListeningInboxItemInput,
    ) -> Result<ListeningInboxItem, ApplicationError> {
        let session = self
            .practice
            .get_practice_session(&input.session_id)?
            .ok_or(ApplicationError::NotFound("practice session"))?;
        let subtitle_snapshot = clean_required(input.subtitle_snapshot, "subtitle snapshot")?;
        let now = now_ms();
        let target_key = listening_target_key(&input.target);
        let expires_in_days = u64::from(
            input.expires_in_days.unwrap_or(
                DEFAULT_INBOX_EXPIRY_DAYS
                    .try_into()
                    .expect("default expiry days fits u32"),
            ),
        );
        let item = ListeningInboxItem {
            id: ListeningInboxItemId::from_fingerprint(
                "listening-inbox-item",
                &format!("{}:{target_key}:{now}", session.id.as_str()),
            ),
            session_id: Some(session.id.clone()),
            media_id: session.media_id.clone(),
            track_id: session.track_id.clone(),
            target: input.target,
            anchors: input.anchors,
            label: clean_optional(input.label),
            subtitle_snapshot,
            context_before: clean_optional(input.context_before),
            context_after: clean_optional(input.context_after),
            captured_at_ms: now,
            expires_at_ms: Some(now + expires_in_days.saturating_mul(DAY_MS)),
            status: ListeningInboxStatus::Active,
            resolution: None,
            review_item_ids: Vec::new(),
            practice_item_id: None,
            updated_at_ms: now,
        };
        let saved = self.listening_inbox.upsert_listening_inbox_item(&item)?;
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint(
                "learning-event",
                &format!("listening-inbox-captured:{}:{now}", saved.id.as_str()),
            ),
            occurred_at_ms: now,
            kind: LearningEventKind::ListeningInboxCaptured,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::ListeningInboxItem,
                id: saved.id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "target_key": target_key,
                "target": saved.target,
                "anchors": saved.anchors,
                "label": saved.label,
                "subtitle_snapshot": saved.subtitle_snapshot,
                "media_id": saved.media_id.as_ref().map(|value| value.as_str()),
                "track_id": saved.track_id.as_ref().map(|value| value.as_str()),
                "expires_at_ms": saved.expires_at_ms,
            }),
            session_id: saved.session_id.clone(),
        })?;
        Ok(saved)
    }

    pub fn list_listening_inbox_items(
        &self,
        status: Option<ListeningInboxStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ListeningInboxItem>, ApplicationError> {
        if status != Some(ListeningInboxStatus::Archived) {
            self.expire_listening_inbox_items(now_ms())?;
        }
        self.listening_inbox
            .list_listening_inbox_items(status, limit, offset)
    }

    pub fn process_listening_inbox_item(
        &self,
        id: &ListeningInboxItemId,
        input: ProcessListeningInboxItemInput,
    ) -> Result<ListeningInboxItem, ApplicationError> {
        let mut item = self
            .listening_inbox
            .get_listening_inbox_item(id)?
            .ok_or(ApplicationError::NotFound("listening inbox item"))?;
        if item.status == ListeningInboxStatus::Archived {
            return Ok(item);
        }
        let now = now_ms();
        match input.resolution {
            ListeningInboxResolution::ReviewItem => {
                let review = self.create_review_item(CreateReviewItem {
                    source: ReviewSource {
                        kind: ReviewSourceKind::ListeningInbox,
                        id: Some(item.id.as_str().to_owned()),
                        practice_attempt_id: None,
                        lexical_entry_id: item
                            .anchors
                            .iter()
                            .find_map(|anchor| anchor.lexical_entry_id.clone()),
                        media_id: item.media_id.clone(),
                        track_id: item.track_id.clone(),
                    },
                    anchors: item.anchors.clone(),
                    prompt_snapshot: item.subtitle_snapshot.clone(),
                })?;
                item.review_item_ids.push(review.id);
            }
            ListeningInboxResolution::MicroIntensive => {
                let practice_item = self.create_practice_item(CreatePracticeItem {
                    session_id: item.session_id.clone(),
                    kind: PracticeKind::Dictation,
                    target: item.target.clone(),
                    prompt_snapshot: item.subtitle_snapshot.clone(),
                    expected_text: item.subtitle_snapshot.clone(),
                    anchors: item.anchors.clone(),
                })?;
                item.practice_item_id = Some(practice_item.id);
            }
            ListeningInboxResolution::Favorite
            | ListeningInboxResolution::Dismissed
            | ListeningInboxResolution::Expired => {}
        }
        item.status = ListeningInboxStatus::Archived;
        item.resolution = Some(input.resolution);
        item.updated_at_ms = now;
        let saved = self.listening_inbox.upsert_listening_inbox_item(&item)?;
        self.append_inbox_processed_event(&saved, input.resolution, now)?;
        Ok(saved)
    }

    fn expire_listening_inbox_items(&self, now: u64) -> Result<(), ApplicationError> {
        let active = self.listening_inbox.list_listening_inbox_items(
            Some(ListeningInboxStatus::Active),
            500,
            0,
        )?;
        for mut item in active {
            if item.expires_at_ms.is_none_or(|expires_at| expires_at > now) {
                continue;
            }
            item.status = ListeningInboxStatus::Archived;
            item.resolution = Some(ListeningInboxResolution::Expired);
            item.updated_at_ms = now;
            let saved = self.listening_inbox.upsert_listening_inbox_item(&item)?;
            self.append_inbox_processed_event(&saved, ListeningInboxResolution::Expired, now)?;
        }
        Ok(())
    }

    fn append_inbox_processed_event(
        &self,
        item: &ListeningInboxItem,
        resolution: ListeningInboxResolution,
        now: u64,
    ) -> Result<LearningEvent, ApplicationError> {
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint(
                "learning-event",
                &format!(
                    "listening-inbox-processed:{}:{resolution:?}:{now}",
                    item.id.as_str()
                ),
            ),
            occurred_at_ms: now,
            kind: LearningEventKind::ListeningInboxProcessed,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::ListeningInboxItem,
                id: item.id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "resolution": resolution,
                "review_item_ids": item
                    .review_item_ids
                    .iter()
                    .map(|value| value.as_str())
                    .collect::<Vec<_>>(),
                "practice_item_id": item.practice_item_id.as_ref().map(|value| value.as_str()),
                "media_id": item.media_id.as_ref().map(|value| value.as_str()),
                "track_id": item.track_id.as_ref().map(|value| value.as_str()),
            }),
            session_id: item.session_id.clone(),
        })
    }
}

fn listening_target_key(target: &PracticeTarget) -> String {
    match target.kind {
        PracticeTargetKind::Sentence => target
            .sentence_id
            .as_ref()
            .map(|value| format!("sentence:{}", value.as_str()))
            .or_else(|| target.id.as_ref().map(|value| format!("sentence:{value}")))
            .unwrap_or_else(|| playback_target_key("sentence", target)),
        PracticeTargetKind::Chunk => target
            .id
            .as_ref()
            .map(|value| format!("chunk:{value}"))
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
