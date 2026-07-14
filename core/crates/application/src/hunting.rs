use domain::{
    CorpusOccurrence, CorpusOccurrenceKind, HuntingCandidate, HuntingCandidateId,
    HuntingCandidateStatus, HuntingCheckAnswer, HuntingOccurrence, HuntingOccurrenceQueryResult,
    HuntingTarget, HuntingTargetId, HuntingTargetSourceKind, HuntingTargetStatus, LearningEvent,
    LearningEventId, LearningEventKind, LearningEventSubject, LearningEventSubjectKind,
    LexicalEntry, LexicalEntryId, LexicalEntryKind, ListeningInboxItemId, MediaId,
    ObservationResult, PracticeMode, SubtitleTrackId,
};

use crate::{
    AppServices, ApplicationError, CreateHuntingTargetInput, CreateLexicalObservation,
    HuntingCheckResult, LexicalSourceContext, SubmitHuntingCheckInput, normalize_phrase, now_ms,
};

const MAX_ACTIVE_HUNTING_TARGETS: usize = 5;

impl AppServices {
    pub fn list_hunting_candidates(
        &self,
        status: Option<HuntingCandidateStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<HuntingCandidate>, ApplicationError> {
        self.hunting
            .list_hunting_candidates(status, limit.min(100), offset)
    }

    pub fn create_hunting_target(
        &self,
        input: CreateHuntingTargetInput,
    ) -> Result<HuntingTarget, ApplicationError> {
        let details = self
            .lexical_entries
            .lexical_details(&input.lexical_entry_id)?
            .ok_or(ApplicationError::NotFound("lexical entry"))?;
        let source_id = input
            .source_id
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_owned);

        match input.source_kind {
            HuntingTargetSourceKind::Manual => {
                if source_id.is_some() {
                    return Err(ApplicationError::Conflict(
                        "manual hunting target must not include source_id",
                    ));
                }
            }
            HuntingTargetSourceKind::ReviewCandidate => {
                let candidate_id = source_id.as_ref().ok_or(ApplicationError::Validation(
                    "review candidate hunting target source_id",
                ))?;
                let candidate_id = HuntingCandidateId::parse(candidate_id.clone())?;
                let candidate = self
                    .hunting
                    .get_hunting_candidate(&candidate_id)?
                    .ok_or(ApplicationError::NotFound("hunting candidate"))?;
                if candidate.lexical_entry_id != input.lexical_entry_id {
                    return Err(ApplicationError::Conflict(
                        "hunting candidate belongs to another lexical entry",
                    ));
                }
            }
            HuntingTargetSourceKind::ListeningInbox => {
                let item_id = source_id.as_ref().ok_or(ApplicationError::Validation(
                    "listening inbox hunting target source_id",
                ))?;
                let item_id = ListeningInboxItemId::parse(item_id.clone())?;
                let item = self
                    .listening_inbox
                    .get_listening_inbox_item(&item_id)?
                    .ok_or(ApplicationError::NotFound("listening inbox item"))?;
                if !item
                    .anchors
                    .iter()
                    .any(|anchor| anchor.lexical_entry_id.as_ref() == Some(&input.lexical_entry_id))
                {
                    return Err(ApplicationError::Conflict(
                        "listening inbox item does not reference lexical entry",
                    ));
                }
            }
        }

        let id =
            HuntingTargetId::from_fingerprint("hunting-target", input.lexical_entry_id.as_str());
        let existing = self.hunting.get_hunting_target(&id)?;
        if let Some(existing) = existing.as_ref()
            && existing.status == HuntingTargetStatus::Active
        {
            return Ok(existing.clone());
        }
        if self
            .hunting
            .list_hunting_targets(Some(HuntingTargetStatus::Active), 6, 0)?
            .len()
            >= MAX_ACTIVE_HUNTING_TARGETS
        {
            return Err(ApplicationError::Conflict(
                "hunting list already has the maximum of 5 active targets",
            ));
        }

        let now = now_ms();
        let target = self.hunting.upsert_hunting_target(&HuntingTarget {
            id,
            lexical_entry_id: input.lexical_entry_id,
            source_kind: input.source_kind,
            source_id: source_id.clone(),
            target_snapshot: details.entry.display_form,
            status: HuntingTargetStatus::Active,
            created_at_ms: existing.as_ref().map_or(now, |target| target.created_at_ms),
            updated_at_ms: now,
        })?;

        if input.source_kind == HuntingTargetSourceKind::ReviewCandidate {
            let candidate_id = HuntingCandidateId::parse(source_id.expect("validated source id"))?;
            let mut candidate = self
                .hunting
                .get_hunting_candidate(&candidate_id)?
                .ok_or(ApplicationError::NotFound("hunting candidate"))?;
            candidate.status = HuntingCandidateStatus::Consumed;
            self.hunting.upsert_hunting_candidate(&candidate)?;
        }

        Ok(target)
    }

    pub fn list_hunting_targets(
        &self,
        status: Option<HuntingTargetStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<HuntingTarget>, ApplicationError> {
        self.hunting
            .list_hunting_targets(status, limit.min(100), offset)
    }

    pub fn archive_hunting_target(
        &self,
        id: &HuntingTargetId,
    ) -> Result<HuntingTarget, ApplicationError> {
        let mut target = self
            .hunting
            .get_hunting_target(id)?
            .ok_or(ApplicationError::NotFound("hunting target"))?;
        if target.status != HuntingTargetStatus::Archived {
            target.status = HuntingTargetStatus::Archived;
            target.updated_at_ms = now_ms();
            target = self.hunting.upsert_hunting_target(&target)?;
        }
        Ok(target)
    }

    pub fn hunting_target_for_lexical_entry(
        &self,
        lexical_entry_id: &LexicalEntryId,
    ) -> Result<Option<HuntingTarget>, ApplicationError> {
        let id = HuntingTargetId::from_fingerprint("hunting-target", lexical_entry_id.as_str());
        self.hunting.get_hunting_target(&id)
    }

    pub fn hunting_occurrences(
        &self,
        media_id: &MediaId,
        track_id: Option<&SubtitleTrackId>,
    ) -> Result<HuntingOccurrenceQueryResult, ApplicationError> {
        if self.media.get(media_id)?.is_none() {
            return Err(ApplicationError::NotFound("media"));
        }
        let indexed = self
            .corpus
            .media_has_corpus_occurrences(media_id, track_id)?;
        if !indexed {
            return Ok(HuntingOccurrenceQueryResult {
                indexed: false,
                occurrences: Vec::new(),
            });
        }

        let targets = self.hunting.list_hunting_targets(
            Some(HuntingTargetStatus::Active),
            MAX_ACTIVE_HUNTING_TARGETS as u32,
            0,
        )?;
        let mut seen = std::collections::BTreeSet::new();
        let mut occurrences = Vec::new();
        for target in targets {
            let Some(details) = self
                .lexical_entries
                .lexical_details(&target.lexical_entry_id)?
            else {
                continue;
            };
            let query = match details.entry.kind {
                LexicalEntryKind::Word => details.entry.normalized_form.as_str(),
                LexicalEntryKind::Phrase => details.entry.display_form.as_str(),
            };
            for occurrence in self.corpus.search_corpus_occurrences_in_media(
                &details.entry.language,
                query,
                media_id,
                track_id,
                100,
            )? {
                let expected_kind = match details.entry.kind {
                    LexicalEntryKind::Word => CorpusOccurrenceKind::Lexical,
                    LexicalEntryKind::Phrase => CorpusOccurrenceKind::Phrase,
                };
                let Some(sentence_id) = occurrence.sentence_id.as_ref() else {
                    continue;
                };
                if occurrence.kind != expected_kind
                    || !seen.insert(format!("{}:{}", target.id.as_str(), sentence_id.as_str()))
                {
                    continue;
                }
                occurrences.push(HuntingOccurrence {
                    target_id: target.id.clone(),
                    lexical_entry_id: target.lexical_entry_id.clone(),
                    target_snapshot: target.target_snapshot.clone(),
                    occurrence,
                });
            }
        }
        occurrences.sort_by(|left, right| {
            left.occurrence
                .start_ms
                .cmp(&right.occurrence.start_ms)
                .then_with(|| left.target_id.as_str().cmp(right.target_id.as_str()))
        });
        Ok(HuntingOccurrenceQueryResult {
            indexed: true,
            occurrences,
        })
    }

    pub fn submit_hunting_check(
        &self,
        input: SubmitHuntingCheckInput,
    ) -> Result<HuntingCheckResult, ApplicationError> {
        let session = self
            .practice
            .get_practice_session(&input.session_id)?
            .ok_or(ApplicationError::NotFound("practice session"))?;
        if session.mode != PracticeMode::Extensive || session.ended_at_ms.is_some() {
            return Err(ApplicationError::Conflict(
                "hunting checks require an active extensive listening session",
            ));
        }
        let target = self
            .hunting
            .get_hunting_target(&input.target_id)?
            .ok_or(ApplicationError::NotFound("hunting target"))?;
        if target.status != HuntingTargetStatus::Active {
            return Err(ApplicationError::Conflict("hunting target is not active"));
        }
        let occurrence = self
            .corpus
            .get_corpus_occurrence(&input.occurrence_id)?
            .ok_or(ApplicationError::NotFound("corpus occurrence"))?;
        let media_id = occurrence
            .media_id
            .clone()
            .ok_or(ApplicationError::Conflict(
                "hunting occurrence has no media",
            ))?;
        if session.media_id.as_ref() != Some(&media_id) {
            return Err(ApplicationError::Conflict(
                "hunting occurrence belongs to another listening session",
            ));
        }
        let sentence_id = occurrence
            .sentence_id
            .clone()
            .ok_or(ApplicationError::Conflict(
                "hunting occurrence has no sentence",
            ))?;
        let entry = self
            .lexical_entries
            .lexical_details(&target.lexical_entry_id)?
            .map(|details| details.entry)
            .ok_or(ApplicationError::NotFound("lexical entry"))?;
        if !occurrence_matches_entry(&occurrence, &entry) {
            return Err(ApplicationError::Conflict(
                "hunting occurrence does not match target",
            ));
        }

        let now = now_ms();
        let observation_id = match input.answer {
            HuntingCheckAnswer::Recognized | HuntingCheckAnswer::NotRecognized => {
                let media = self
                    .media
                    .get(&media_id)?
                    .ok_or(ApplicationError::NotFound("media"))?;
                Some(
                    self.create_lexical_observation(CreateLexicalObservation {
                        lexical_entry_id: target.lexical_entry_id.clone(),
                        sentence_id: sentence_id.clone(),
                        original_form: occurrence.display_text.clone(),
                        result: if input.answer == HuntingCheckAnswer::Recognized {
                            ObservationResult::RecognizedInContext
                        } else {
                            ObservationResult::NotRecognizedInContext
                        },
                        source: Some(LexicalSourceContext {
                            media_id: Some(media_id.clone()),
                            sentence_id: Some(sentence_id.clone()),
                            original_form: occurrence.display_text.clone(),
                            sentence_text: occurrence.source_snapshot.clone(),
                            media_title: media.title,
                            media_fingerprint: media.fingerprint,
                            start_ms: occurrence.start_ms,
                            end_ms: occurrence.end_ms,
                            token_start: None,
                            token_end: None,
                        }),
                    })?
                    .id,
                )
            }
            HuntingCheckAnswer::NotNoticed => None,
        };
        let event_id = LearningEventId::from_fingerprint(
            "learning-event",
            &format!(
                "hunting-check:{}:{}:{}:{now}",
                input.session_id.as_str(),
                input.target_id.as_str(),
                input.occurrence_id.as_str()
            ),
        );
        self.learning_events.append_learning_event(&LearningEvent {
            id: event_id.clone(),
            occurred_at_ms: now,
            kind: LearningEventKind::HuntingCheckAnswered,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::HuntingTarget,
                id: target.id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "answer": input.answer,
                "lexical_entry_id": target.lexical_entry_id.as_str(),
                "occurrence_id": occurrence.id.as_str(),
                "sentence_id": sentence_id.as_str(),
                "media_id": media_id.as_str(),
            }),
            session_id: Some(input.session_id),
        })?;
        Ok(HuntingCheckResult {
            answer: input.answer,
            event_id,
            observation_id,
        })
    }
}

fn occurrence_matches_entry(occurrence: &CorpusOccurrence, entry: &LexicalEntry) -> bool {
    match entry.kind {
        LexicalEntryKind::Word => {
            occurrence.kind == CorpusOccurrenceKind::Lexical
                && occurrence.normalized_key.as_deref() == Some(entry.normalized_form.as_str())
        }
        LexicalEntryKind::Phrase => {
            occurrence.kind == CorpusOccurrenceKind::Phrase
                && normalize_phrase(&occurrence.source_snapshot)
                    .contains(&normalize_phrase(&entry.display_form))
        }
    }
}
