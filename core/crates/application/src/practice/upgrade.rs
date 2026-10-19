use std::collections::HashMap;

use crate::{
    ApplicationError, CapabilityAssessment, LearningEvent, LearningEventId, LearningEventKind,
    LearningEventSubject, LearningEventSubjectKind, LearningStatus, LexicalCapability,
    LexicalEntryId, LexicalLearningUseCases, MediaId, ObservationContext, ObservationOrigin,
    PracticeAttempt, PracticeItem, RecognitionEvidence, RecognitionEvidenceId,
    RecognitionEvidenceSourceKind, ReviewAttempt, ReviewItem, SubtitleSentenceId,
    UpgradeSuggestion, UpgradeSuggestionId, UpgradeSuggestionStatus, now_ms,
    observation_spec_for_upgrade_confirmation,
};

const UPGRADE_EVIDENCE_THRESHOLD: u32 = 5;
const REJECTION_COOLDOWN_MS: u64 = 30 * 24 * 60 * 60 * 1000;
const UPGRADE_EVIDENCE_CLASS: &str = "heuristic_proxy";

impl LexicalLearningUseCases {
    pub(crate) fn record_context_recognition_evidence(
        &self,
        lexical_entry_id: LexicalEntryId,
        sentence_id: Option<SubtitleSentenceId>,
        media_id: Option<MediaId>,
        source_kind: RecognitionEvidenceSourceKind,
        source_id: &str,
        occurred_at_ms: u64,
    ) -> Result<Option<UpgradeSuggestion>, ApplicationError> {
        let Some(context_key) = recognition_context_key(sentence_id.as_ref(), media_id.as_ref())
        else {
            return Ok(None);
        };
        let id = RecognitionEvidenceId::from_fingerprint(
            "recognition-evidence",
            &format!("{}:{context_key}", lexical_entry_id.as_str()),
        );
        self.recognition_upgrades
            .upsert_recognition_evidence(&RecognitionEvidence {
                id,
                lexical_entry_id: lexical_entry_id.clone(),
                context_key,
                sentence_id,
                media_id,
                source_kind,
                source_id: source_id.to_owned(),
                occurred_at_ms,
            })?;
        self.evaluate_upgrade_suggestion(&lexical_entry_id, occurred_at_ms)
    }

    pub(crate) fn record_practice_recognition_evidence(
        &self,
        item: &PracticeItem,
        attempt: &PracticeAttempt,
        occurred_at_ms: u64,
    ) -> Result<Vec<UpgradeSuggestion>, ApplicationError> {
        let media_id = item
            .session_id
            .as_ref()
            .map(|id| self.practice.get_practice_session(id))
            .transpose()?
            .flatten()
            .and_then(|session| session.media_id);
        let mut contexts = HashMap::new();
        for anchor in &item.anchors {
            if let Some(lexical_entry_id) = anchor.lexical_entry_id.clone() {
                contexts.entry(lexical_entry_id).or_insert_with(|| {
                    (
                        anchor
                            .sentence_id
                            .clone()
                            .or_else(|| item.target.sentence_id.clone()),
                        media_id.clone(),
                    )
                });
            }
        }
        self.record_recognition_contexts(
            contexts,
            RecognitionEvidenceSourceKind::Practice,
            attempt.id.as_str(),
            occurred_at_ms,
        )
    }

    pub(crate) fn record_review_recognition_evidence(
        &self,
        item: &ReviewItem,
        attempt: &ReviewAttempt,
        occurred_at_ms: u64,
    ) -> Result<Vec<UpgradeSuggestion>, ApplicationError> {
        let fallback_sentence = item
            .anchors
            .iter()
            .find_map(|anchor| anchor.sentence_id.clone());
        let mut contexts = HashMap::new();
        if let Some(lexical_entry_id) = item.source.lexical_entry_id.clone() {
            contexts.insert(
                lexical_entry_id,
                (fallback_sentence.clone(), item.source.media_id.clone()),
            );
        }
        for anchor in &item.anchors {
            if let Some(lexical_entry_id) = anchor.lexical_entry_id.clone() {
                contexts.entry(lexical_entry_id).or_insert_with(|| {
                    (
                        anchor
                            .sentence_id
                            .clone()
                            .or_else(|| fallback_sentence.clone()),
                        item.source.media_id.clone(),
                    )
                });
            }
        }
        self.record_recognition_contexts(
            contexts,
            RecognitionEvidenceSourceKind::Review,
            attempt.id.as_str(),
            occurred_at_ms,
        )
    }

    fn record_recognition_contexts(
        &self,
        contexts: HashMap<LexicalEntryId, (Option<SubtitleSentenceId>, Option<MediaId>)>,
        source_kind: RecognitionEvidenceSourceKind,
        source_id: &str,
        occurred_at_ms: u64,
    ) -> Result<Vec<UpgradeSuggestion>, ApplicationError> {
        let mut suggestions = Vec::new();
        for (lexical_entry_id, (sentence_id, media_id)) in contexts {
            if let Some(suggestion) = self.record_context_recognition_evidence(
                lexical_entry_id,
                sentence_id,
                media_id,
                source_kind,
                source_id,
                occurred_at_ms,
            )? {
                suggestions.push(suggestion);
            }
        }
        Ok(suggestions)
    }

    fn evaluate_upgrade_suggestion(
        &self,
        lexical_entry_id: &LexicalEntryId,
        now: u64,
    ) -> Result<Option<UpgradeSuggestion>, ApplicationError> {
        let Some(details) = self.lexical_entries.lexical_details(lexical_entry_id)? else {
            return Ok(None);
        };
        let profile = self
            .lexical_capabilities
            .lexical_capability_profile(lexical_entry_id, None)?;
        let listening = profile
            .as_ref()
            .map(|p| p.effective_assessment(LexicalCapability::Listening))
            .unwrap_or(CapabilityAssessment::Unassessed);
        if listening != CapabilityAssessment::NotAcquired {
            return Ok(None);
        }
        let history = self.recognition_upgrades.list_upgrade_suggestions(
            Some(lexical_entry_id),
            None,
            1,
            0,
        )?;
        if let Some(latest) = history.first()
            && (latest.status == UpgradeSuggestionStatus::Pending
                || (latest.status == UpgradeSuggestionStatus::Rejected
                    && latest.cooldown_until_ms.is_some_and(|until| until > now)))
        {
            return Ok(None);
        }
        let evidence =
            self.recognition_upgrades
                .list_recognition_evidence(lexical_entry_id, 1000, 0)?;
        if evidence.len() < UPGRADE_EVIDENCE_THRESHOLD as usize {
            return Ok(None);
        }
        let suggestion = UpgradeSuggestion {
            id: UpgradeSuggestionId::from_fingerprint(
                "upgrade-suggestion",
                &format!("{}:{now}", lexical_entry_id.as_str()),
            ),
            lexical_entry_id: lexical_entry_id.clone(),
            lexical_display_form: details.entry.display_form,
            previous_status: LearningStatus::KnownNotRecognized,
            suggested_status: LearningStatus::KnownRecognized,
            status: UpgradeSuggestionStatus::Pending,
            evidence_context_count: evidence.len() as u32,
            evidence_ids: evidence.into_iter().map(|value| value.id).collect(),
            threshold: UPGRADE_EVIDENCE_THRESHOLD,
            evidence_class: UPGRADE_EVIDENCE_CLASS.into(),
            created_at_ms: now,
            resolved_at_ms: None,
            cooldown_until_ms: None,
            capability: Some(LexicalCapability::Listening),
            previous_assessment: Some(CapabilityAssessment::NotAcquired),
            suggested_assessment: Some(CapabilityAssessment::Acquired),
        };
        self.recognition_upgrades
            .save_upgrade_suggestion(&suggestion)
            .map(Some)
    }

    pub fn upgrade_suggestions(
        &self,
        lexical_entry_id: Option<&LexicalEntryId>,
        status: Option<UpgradeSuggestionStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<UpgradeSuggestion>, ApplicationError> {
        self.recognition_upgrades.list_upgrade_suggestions(
            lexical_entry_id,
            status,
            limit.min(500),
            offset,
        )
    }

    pub fn confirm_upgrade_suggestion(
        &self,
        id: &UpgradeSuggestionId,
    ) -> Result<UpgradeSuggestion, ApplicationError> {
        let mut suggestion = self
            .recognition_upgrades
            .get_upgrade_suggestion(id)?
            .ok_or(ApplicationError::NotFound("upgrade suggestion"))?;
        if suggestion.status == UpgradeSuggestionStatus::Accepted {
            return Ok(suggestion);
        }
        if suggestion.status != UpgradeSuggestionStatus::Pending {
            return Err(ApplicationError::Conflict(
                "upgrade suggestion is not pending",
            ));
        }
        let now = now_ms();
        let capability = suggestion
            .capability
            .unwrap_or(LexicalCapability::Listening);
        // This confirms the old upgrade suggestion as evidence only. Phase
        // 3.17 now owns the separate projection-proposal confirmation gate;
        // no channel may write a projection directly from this legacy flow.
        self.append_channelized_observation(
            &suggestion.lexical_entry_id,
            observation_spec_for_upgrade_confirmation(capability),
            ObservationContext {
                surface_form: Some(suggestion.lexical_display_form.clone()),
                sentence_id: None,
                media_id: None,
            },
            ObservationOrigin::UserMarking,
            Some(suggestion.id.as_str().to_owned()),
            now,
        )?;
        suggestion.status = UpgradeSuggestionStatus::Accepted;
        suggestion.resolved_at_ms = Some(now);
        suggestion.cooldown_until_ms = None;
        let saved = self
            .recognition_upgrades
            .save_upgrade_suggestion(&suggestion)?;
        self.append_upgrade_status_event(&saved, now)?;
        Ok(saved)
    }

    pub fn reject_upgrade_suggestion(
        &self,
        id: &UpgradeSuggestionId,
    ) -> Result<UpgradeSuggestion, ApplicationError> {
        let mut suggestion = self
            .recognition_upgrades
            .get_upgrade_suggestion(id)?
            .ok_or(ApplicationError::NotFound("upgrade suggestion"))?;
        if suggestion.status == UpgradeSuggestionStatus::Rejected {
            return Ok(suggestion);
        }
        if suggestion.status != UpgradeSuggestionStatus::Pending {
            return Err(ApplicationError::Conflict(
                "upgrade suggestion is not pending",
            ));
        }
        let now = now_ms();
        suggestion.status = UpgradeSuggestionStatus::Rejected;
        suggestion.resolved_at_ms = Some(now);
        suggestion.cooldown_until_ms = Some(now.saturating_add(REJECTION_COOLDOWN_MS));
        self.recognition_upgrades
            .save_upgrade_suggestion(&suggestion)
    }

    fn append_upgrade_status_event(
        &self,
        suggestion: &UpgradeSuggestion,
        occurred_at_ms: u64,
    ) -> Result<(), ApplicationError> {
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint(
                "learning-event",
                &format!(
                    "upgrade-confirmed:{}:{occurred_at_ms}",
                    suggestion.id.as_str()
                ),
            ),
            occurred_at_ms,
            kind: LearningEventKind::StatusChanged,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::LexicalEntry,
                id: suggestion.lexical_entry_id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "previous_status": suggestion.previous_status,
                "new_status": suggestion.suggested_status,
                "upgrade_suggestion_id": suggestion.id.as_str(),
                "evidence_context_count": suggestion.evidence_context_count,
                "evidence_class": suggestion.evidence_class,
                "confirmed_by_user": true,
            }),
            session_id: None,
        })?;
        Ok(())
    }
}

fn recognition_context_key(
    sentence_id: Option<&SubtitleSentenceId>,
    media_id: Option<&MediaId>,
) -> Option<String> {
    sentence_id
        .map(|id| format!("sentence:{}", id.as_str()))
        .or_else(|| media_id.map(|id| format!("media:{}", id.as_str())))
}
