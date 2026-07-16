//! Phase 3.15.5 personal production corpus use cases.
//!
//! This deep module owns derivation, idempotent replacement, normalization,
//! and lemma/FTS reads. Callers see learner-output facts; they never need to
//! know the projection schema and cannot write observations or capability.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;

use domain::{
    ProductionAssistance, ProductionChannel, ProductionCorpusDocument, ProductionCorpusDocumentId,
    ProductionCorpusEntry, ProductionCorpusEntryId, ProductionCorpusHit, SemanticAttemptStatus,
    SemanticRubricId, SemanticTaskAttempt, SemanticTaskKind, SubtitleTokenKind, transcript_sha256,
};

use crate::{
    AppServices, ApplicationError, LexicalLearningUseCases, ProductionCorpusRepository,
    SemanticTaskRepository, SemanticUseCases, clean_required,
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
    production_corpus: Arc<dyn ProductionCorpusRepository>,
    lexical_learning: LexicalLearningUseCases,
}

impl ProductionCorpusUseCases {
    pub(crate) fn from_services(services: &AppServices) -> Self {
        Self {
            semantic_tasks: services.semantic_tasks.clone(),
            production_corpus: services.production_corpus.clone(),
            lexical_learning: LexicalLearningUseCases::from_services(services),
        }
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
        self.production_corpus
            .replace_all_production_entries(&documents, &entries)?;
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
                attempt_id: attempt.id.clone(),
                rubric_id: attempt.rubric_id.clone(),
                response_revision: response.revision,
                task_kind: attempt.kind,
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
}
