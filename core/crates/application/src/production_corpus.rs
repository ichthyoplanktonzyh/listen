//! Phase 3.15.5 personal production corpus use cases.
//!
//! This deep module owns derivation, idempotent replacement, normalization,
//! and lemma/FTS reads. Callers see learner-output facts; they never need to
//! know the projection schema and cannot write observations or capability.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;

use domain::{
    ProductionAssistance, ProductionChannel, ProductionCorpusDocument, ProductionCorpusDocumentId,
    ProductionCorpusEntry, ProductionCorpusEntryId, ProductionCorpusHit, ProductionGapReadiness,
    ProductionGapReview, ProductionGapTarget, SemanticAttemptStatus, SemanticRubricId,
    SemanticTaskAttempt, SemanticTaskKind, SubtitleTokenKind, transcript_sha256,
};

use crate::{
    AppServices, ApplicationError, LexicalLearningUseCases, ProductionCorpusRepository,
    SemanticTaskRepository, SemanticUseCases, clean_required, now_ms,
};

const WRITING_KINDS: [SemanticTaskKind; 4] = [
    SemanticTaskKind::Dictogloss,
    SemanticTaskKind::OneSentenceSummary,
    SemanticTaskKind::Summary,
    SemanticTaskKind::OpinionResponse,
];

fn assistance_for(kind: SemanticTaskKind, revision: u32) -> ProductionAssistance {
    if revision > 1 {
        ProductionAssistance::LearnerRevision
    } else if kind == SemanticTaskKind::Dictogloss {
        ProductionAssistance::SourceReconstruction
    } else {
        ProductionAssistance::ContentAnchored
    }
}

#[derive(Clone)]
pub struct ProductionCorpusUseCases {
    semantic_tasks: Arc<dyn SemanticTaskRepository>,
    realtime_conversations: Arc<dyn crate::RealtimeConversationRepository>,
    production_corpus: Arc<dyn ProductionCorpusRepository>,
    lexical_learning: LexicalLearningUseCases,
}

impl ProductionCorpusUseCases {
    pub(crate) fn from_services(services: &AppServices) -> Self {
        Self {
            semantic_tasks: services.semantic_tasks.clone(),
            realtime_conversations: services.realtime_conversations.clone(),
            production_corpus: services.production_corpus.clone(),
            lexical_learning: LexicalLearningUseCases::from_services(services),
        }
    }

    /// Records the immutable/local-authoritative realtime turn first, then
    /// best-effort refreshes only its spoken projection. Provider transcript
    /// alone and interrupted/failed turns yield no document.
    pub fn record_realtime_turn_and_index(
        &self,
        turn: domain::RealtimeConversationTurn,
    ) -> Result<domain::RealtimeConversationTurn, ApplicationError> {
        let saved = self.realtime_conversations.save_realtime_turn(&turn)?;
        let session = self
            .realtime_conversations
            .get_realtime_session(&saved.session_id)?
            .ok_or(ApplicationError::NotFound("realtime conversation session"))?;
        let (documents, entries) = self.derive_realtime_entries(&session, &saved)?;
        let _ = self
            .production_corpus
            .replace_production_entries_for_realtime_turn(&saved.id, &documents, &entries);
        Ok(saved)
    }

    /// Records the authoritative attempt first, then best-effort refreshes its
    /// rubric projection. A projection failure cannot roll back learner work;
    /// the atomic full rebuild is the recovery path.
    pub fn record_semantic_attempt_and_index(
        &self,
        attempt: SemanticTaskAttempt,
    ) -> Result<SemanticTaskAttempt, ApplicationError> {
        let saved =
            SemanticUseCases::new(self.semantic_tasks.clone()).record_semantic_attempt(attempt)?;
        if WRITING_KINDS.contains(&saved.kind) {
            let _ = self.reindex_rubric_production(&saved.rubric_id);
        }
        Ok(saved)
    }

    pub fn reindex_rubric_production(
        &self,
        rubric_id: &SemanticRubricId,
    ) -> Result<(), ApplicationError> {
        let attempts = self
            .semantic_tasks
            .list_semantic_attempts_for_rubric(rubric_id)?;
        let (documents, entries) = self.derive_entries(&attempts)?;
        self.production_corpus
            .replace_production_entries_for_rubric(rubric_id, &documents, &entries)
    }

    /// Builds every row before entering one replacement transaction. If any
    /// source/normalization read fails, the previous projection stays intact.
    pub fn rebuild_production_corpus(&self) -> Result<u32, ApplicationError> {
        let attempts = self
            .semantic_tasks
            .list_semantic_attempts_by_kinds(&WRITING_KINDS)?;
        let mut by_rubric: BTreeMap<String, Vec<SemanticTaskAttempt>> = BTreeMap::new();
        for attempt in attempts {
            by_rubric
                .entry(attempt.rubric_id.as_str().to_owned())
                .or_default()
                .push(attempt);
        }
        let mut documents = Vec::new();
        let mut entries = Vec::new();
        for attempts in by_rubric.values() {
            let (mut derived_documents, mut derived_entries) = self.derive_entries(attempts)?;
            documents.append(&mut derived_documents);
            entries.append(&mut derived_entries);
        }
        for session in self.realtime_conversations.list_realtime_sessions()? {
            for turn in self
                .realtime_conversations
                .list_realtime_turns(&session.id)?
            {
                let (mut derived_documents, mut derived_entries) =
                    self.derive_realtime_entries(&session, &turn)?;
                documents.append(&mut derived_documents);
                entries.append(&mut derived_entries);
            }
        }
        self.production_corpus
            .replace_all_production_entries(&documents, &entries)?;
        // Preserve the existing endpoint contract: this count reports indexed
        // semantic rubrics, while realtime turns are an additional projection
        // source rather than synthetic rubrics.
        Ok(by_rubric.len() as u32)
    }

    /// Single words use the lexical normalization path; multi-word queries use
    /// FTS phrase matching over response documents.
    pub fn search_production_corpus(
        &self,
        language: &str,
        query: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ProductionCorpusHit>, ApplicationError> {
        let language = domain::LanguageCode::parse(language)?;
        let query = clean_required(query.to_owned(), "query")?;
        let limit = limit.clamp(1, 100);
        if query.contains(char::is_whitespace) {
            return self
                .production_corpus
                .search_production_documents(&language, &query, limit, offset);
        }
        let key = self
            .lexical_learning
            .normalize_lexical_form(language.as_str(), &query)
            .map(|normalization| normalization.normalized)
            .unwrap_or_else(|_| query.to_lowercase());
        self.production_corpus
            .list_production_entries_by_key(&language, &key, limit, offset)
    }

    /// Produces a descriptive gap-(c) review. Absence from a small corpus is
    /// never converted into capability evidence; readiness only controls how
    /// strongly the read model may describe its distribution.
    pub fn production_gap_review(
        &self,
        language: &str,
        channel: ProductionChannel,
        limit: u32,
    ) -> Result<ProductionGapReview, ApplicationError> {
        let language = domain::LanguageCode::parse(language)?;
        let summary = self
            .production_corpus
            .production_corpus_summary(&language, channel)?;
        let readiness = if summary.document_count == 0 {
            ProductionGapReadiness::Empty
        } else if summary.document_count < 10
            || summary.token_count < 100
            || summary.lemma_count < 20
        {
            ProductionGapReadiness::Starter
        } else {
            ProductionGapReadiness::Ready
        };
        let mut facts = if readiness == ProductionGapReadiness::Empty {
            Vec::new()
        } else {
            self.production_corpus
                .list_production_gap_candidates(&language, channel)?
        };
        let candidate_count = facts.len() as u32;
        let now = now_ms();
        let mut targets = facts
            .drain(..)
            .map(|fact| {
                let frequency_rank = self
                    .lexical_learning
                    .frequency_rank(&language, &fact.normalized_key);
                let frequency_band = frequency_rank.map(|rank| match rank {
                    1..=1_000 => 1,
                    1_001..=3_000 => 2,
                    3_001..=10_000 => 3,
                    _ => 4,
                });
                let evidence_strength = u32::from(fact.reading_acquired) * 3
                    + u32::from(fact.listening_acquired) * 3
                    + fact.reading_successes.min(3)
                    + fact.listening_successes.min(3)
                    + fact.recognition_contexts.min(5);
                let age = now.saturating_sub(fact.latest_receptive_at_ms);
                let day = 86_400_000;
                let recency_band = if age <= 30 * day {
                    3
                } else if age <= 90 * day {
                    2
                } else if age <= 365 * day {
                    1
                } else {
                    0
                };
                let mut explanation = Vec::new();
                if let Some(rank) = frequency_rank {
                    explanation.push(format!("BNC frequency rank {rank}"));
                } else {
                    explanation.push("general frequency rank unavailable".into());
                }
                if fact.reading_acquired {
                    explanation.push("reading profile acquired".into());
                }
                if fact.listening_acquired {
                    explanation.push("listening profile acquired".into());
                }
                if fact.reading_successes > 0 {
                    explanation.push(format!("{} reading success marks", fact.reading_successes));
                }
                if fact.listening_successes > 0 {
                    explanation.push(format!(
                        "{} listening success marks",
                        fact.listening_successes
                    ));
                }
                if fact.recognition_contexts > 0 {
                    explanation.push(format!(
                        "{} recognition contexts",
                        fact.recognition_contexts
                    ));
                }
                explanation.push(match recency_band {
                    3 => "receptive evidence within 30 days".into(),
                    2 => "receptive evidence within 90 days".into(),
                    1 => "receptive evidence within one year".into(),
                    _ => "receptive evidence older than one year".into(),
                });
                ProductionGapTarget {
                    lexical_entry_id: fact.lexical_entry_id,
                    normalized_key: fact.normalized_key,
                    display_form: fact.display_form,
                    frequency_rank,
                    frequency_band,
                    evidence_strength,
                    recency_band,
                    reading_acquired: fact.reading_acquired,
                    listening_acquired: fact.listening_acquired,
                    reading_successes: fact.reading_successes,
                    listening_successes: fact.listening_successes,
                    recognition_contexts: fact.recognition_contexts,
                    latest_receptive_at_ms: fact.latest_receptive_at_ms,
                    explanation,
                }
            })
            .collect::<Vec<_>>();
        targets.sort_by(|a, b| {
            a.frequency_band
                .unwrap_or(u8::MAX)
                .cmp(&b.frequency_band.unwrap_or(u8::MAX))
                .then_with(|| b.evidence_strength.cmp(&a.evidence_strength))
                .then_with(|| b.recency_band.cmp(&a.recency_band))
                .then_with(|| b.latest_receptive_at_ms.cmp(&a.latest_receptive_at_ms))
                .then_with(|| a.normalized_key.cmp(&b.normalized_key))
        });
        targets.truncate(limit.clamp(1, 20) as usize);
        Ok(ProductionGapReview {
            language,
            channel,
            readiness,
            document_count: summary.document_count,
            token_count: summary.token_count,
            lemma_count: summary.lemma_count,
            candidate_count,
            targets,
            ranking_version: "production-gap-ranking-v1".into(),
        })
    }

    /// Derives one document per final response of each completed attempt. The
    /// Writing Studio may copy an earlier revision into a later attempt; equal
    /// `(language, transcript)` values within one rubric are indexed once.
    fn derive_entries(
        &self,
        attempts: &[SemanticTaskAttempt],
    ) -> Result<(Vec<ProductionCorpusDocument>, Vec<ProductionCorpusEntry>), ApplicationError> {
        let mut documents = Vec::new();
        let mut entries = Vec::new();
        let mut seen_responses = HashSet::new();
        let mut lemma_cache: HashMap<(String, String), String> = HashMap::new();

        for attempt in attempts {
            if !WRITING_KINDS.contains(&attempt.kind)
                || attempt.status != SemanticAttemptStatus::Completed
            {
                continue;
            }
            let Some(response) = attempt.responses.last() else {
                continue;
            };
            let response_key = format!(
                "{}:{}",
                response.language.as_str(),
                transcript_sha256(&response.transcript)
            );
            if !seen_responses.insert(response_key) {
                continue;
            }
            let rubric = self
                .semantic_tasks
                .get_semantic_rubric(&attempt.rubric_id, attempt.rubric_version)?
                .ok_or(ApplicationError::NotFound("semantic rubric"))?;
            let document_id = ProductionCorpusDocumentId::from_fingerprint(
                "production-corpus-document",
                &format!("{}:{}", attempt.id.as_str(), response.revision),
            );
            documents.push(ProductionCorpusDocument {
                id: document_id.clone(),
                language: response.language.clone(),
                channel: ProductionChannel::Written,
                assistance: assistance_for(attempt.kind, response.revision),
                attempt_id: Some(attempt.id.clone()),
                rubric_id: Some(attempt.rubric_id.clone()),
                realtime_turn_id: None,
                realtime_session_id: None,
                response_revision: response.revision,
                activity_kind: serde_json::to_value(attempt.kind)
                    .ok()
                    .and_then(|value| value.as_str().map(ToOwned::to_owned))
                    .unwrap_or_else(|| "semantic_task".into()),
                media_id: rubric.source.media_id.clone(),
                start_ms: rubric.source.start_ms,
                end_ms: rubric.source.end_ms,
                response_text: response.transcript.clone(),
                produced_at_ms: response.recorded_at_ms,
            });

            for token in subtitle_core::tokenize(Some(&response.language), &response.transcript)
                .into_iter()
                .filter(|token| token.kind == SubtitleTokenKind::Word && token.normalized.is_some())
            {
                let surface_key = token.normalized.expect("filtered to Some");
                let cache_key = (response.language.as_str().to_owned(), surface_key.clone());
                let normalized_key = match lemma_cache.get(&cache_key) {
                    Some(hit) => hit.clone(),
                    None => {
                        let key = self
                            .lexical_learning
                            .normalize_lexical_form(response.language.as_str(), &surface_key)
                            .map(|normalization| normalization.normalized)
                            .unwrap_or_else(|_| surface_key.clone());
                        lemma_cache.insert(cache_key, key.clone());
                        key
                    }
                };
                entries.push(ProductionCorpusEntry {
                    id: ProductionCorpusEntryId::from_fingerprint(
                        "production-corpus-entry",
                        &format!("{}:token:{}", document_id.as_str(), token.index),
                    ),
                    document_id: document_id.clone(),
                    normalized_key,
                    display_text: token.text,
                    start_char: token.start_char,
                    end_char: token.end_char,
                });
            }
        }
        Ok((documents, entries))
    }

    fn derive_realtime_entries(
        &self,
        session: &domain::RealtimeConversationSession,
        turn: &domain::RealtimeConversationTurn,
    ) -> Result<(Vec<ProductionCorpusDocument>, Vec<ProductionCorpusEntry>), ApplicationError> {
        if !turn.is_authoritative_learner_output() {
            return Ok((Vec::new(), Vec::new()));
        }
        let transcript = turn
            .local_transcript
            .as_ref()
            .expect("authority predicate requires local transcript");
        let anchor = session
            .context
            .as_ref()
            .and_then(|context| context.content_anchor.as_ref());
        let document_id = ProductionCorpusDocumentId::from_fingerprint(
            "production-corpus-document",
            &format!("realtime:{}", turn.id.as_str()),
        );
        let documents = vec![ProductionCorpusDocument {
            id: document_id.clone(),
            language: session.language.clone(),
            channel: ProductionChannel::Spoken,
            assistance: turn.assistance,
            attempt_id: None,
            rubric_id: None,
            realtime_turn_id: Some(turn.id.clone()),
            realtime_session_id: Some(turn.session_id.clone()),
            response_revision: 1,
            activity_kind: "realtime_conversation".into(),
            media_id: anchor.map(|value| value.media_id.clone()),
            start_ms: anchor.map_or(0, |value| value.start_ms),
            end_ms: anchor.map_or(0, |value| value.end_ms),
            response_text: transcript.text.clone(),
            produced_at_ms: transcript.completed_at_ms,
        }];
        let mut entries = Vec::new();
        for token in subtitle_core::tokenize(Some(&session.language), &transcript.text)
            .into_iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word && token.normalized.is_some())
        {
            let surface = token.normalized.expect("filtered to Some");
            let normalized_key = self
                .lexical_learning
                .normalize_lexical_form(session.language.as_str(), &surface)
                .map(|normalization| normalization.normalized)
                .unwrap_or(surface);
            entries.push(ProductionCorpusEntry {
                id: ProductionCorpusEntryId::from_fingerprint(
                    "production-corpus-entry",
                    &format!("{}:token:{}", document_id.as_str(), token.index),
                ),
                document_id: document_id.clone(),
                normalized_key,
                display_text: token.text,
                start_char: token.start_char,
                end_char: token.end_char,
            });
        }
        Ok((documents, entries))
    }
}
