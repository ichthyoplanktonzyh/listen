use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use domain::{
    EmbeddingModelDescriptor, EmbeddingPurpose, NearSemanticProductionMatch, ProductionChannel,
    ProductionGapSemanticEnrichment, SemanticEmbeddingCapability, SemanticEmbeddingIndexRecord,
    SemanticEmbeddingSource, SemanticEmbeddingSourceKind, SemanticEmbeddingStatus,
    SemanticSearchHit, SemanticSearchResult, SemanticallyEnrichedProductionGapReview,
};
use sha2::{Digest, Sha256};

use crate::{
    AppServices, ApplicationError, CorpusIndexRepository, ProductionCorpusRepository,
    SemanticEmbeddingIndexRepository, now_ms,
};

#[async_trait]
pub trait EmbeddingProvider: Send + Sync {
    /// `None` means no installed/enabled model. Reading capability must not
    /// trigger network or model installation.
    fn descriptor(&self) -> Option<EmbeddingModelDescriptor>;
    fn status(&self) -> SemanticEmbeddingStatus {
        if self.descriptor().is_some() {
            SemanticEmbeddingStatus::Ready
        } else {
            SemanticEmbeddingStatus::NotInstalled
        }
    }
    async fn embed(
        &self,
        purpose: EmbeddingPurpose,
        texts: &[String],
    ) -> Result<Vec<Vec<f32>>, ApplicationError>;
}

pub struct UnavailableEmbeddingProvider;

#[async_trait]
impl EmbeddingProvider for UnavailableEmbeddingProvider {
    fn descriptor(&self) -> Option<EmbeddingModelDescriptor> {
        None
    }

    async fn embed(
        &self,
        _purpose: EmbeddingPurpose,
        _texts: &[String],
    ) -> Result<Vec<Vec<f32>>, ApplicationError> {
        Err(ApplicationError::Conflict(
            "semantic embedding model is not installed",
        ))
    }
}

#[derive(Clone)]
pub struct SemanticEmbeddingUseCases {
    corpus: Arc<dyn CorpusIndexRepository>,
    production: Arc<dyn ProductionCorpusRepository>,
    index: Arc<dyn SemanticEmbeddingIndexRepository>,
    provider: Arc<dyn EmbeddingProvider>,
    gap_review: crate::ProductionCorpusUseCases,
}

impl SemanticEmbeddingUseCases {
    pub(crate) fn from_services(services: &AppServices) -> Self {
        Self {
            corpus: services.corpus.clone(),
            production: services.production_corpus.clone(),
            index: services.semantic_embedding_index.clone(),
            provider: services.embedding_provider.clone(),
            gap_review: crate::ProductionCorpusUseCases::from_services(services),
        }
    }

    pub fn capability(&self) -> Result<SemanticEmbeddingCapability, ApplicationError> {
        let summary = self.index.semantic_embedding_index_summary()?;
        let Some(descriptor) = self.provider.descriptor() else {
            let status = self.provider.status();
            return Ok(SemanticEmbeddingCapability {
                status,
                descriptor: None,
                indexed_source_count: summary.iter().map(|(_, count)| count).sum(),
                indexed_fingerprint: summary.first().map(|(fingerprint, _)| fingerprint.clone()),
                reason: Some(match status {
                    SemanticEmbeddingStatus::Disabled => "Semantic embedding is disabled; exact search remains available.",
                    SemanticEmbeddingStatus::Failed => "The embedding model failed validation; reinstall it or keep using exact search.",
                    _ => "Install or explicitly configure an embedding model to enable semantic search.",
                }.into()),
            });
        };
        let current_count = summary
            .iter()
            .find(|(fingerprint, _)| fingerprint == &descriptor.model_fingerprint)
            .map_or(0, |(_, count)| *count);
        let stale = (!summary.is_empty() && current_count == 0)
            || (current_count > 0 && !self.current_sources_match(&descriptor)?);
        Ok(SemanticEmbeddingCapability {
            status: if stale {
                SemanticEmbeddingStatus::Stale
            } else {
                SemanticEmbeddingStatus::Ready
            },
            descriptor: Some(descriptor),
            indexed_source_count: current_count,
            indexed_fingerprint: summary.first().map(|(fingerprint, _)| fingerprint.clone()),
            reason: stale.then(|| "The installed model differs from the indexed vector space; rebuild is required.".into()),
        })
    }

    pub async fn rebuild(&self) -> Result<SemanticEmbeddingCapability, ApplicationError> {
        let descriptor = self
            .provider
            .descriptor()
            .ok_or(ApplicationError::Conflict(
                "semantic embedding model is not installed",
            ))?;
        let sources = self.sources()?;
        if sources.is_empty() {
            self.index
                .replace_semantic_embedding_index(&descriptor.model_fingerprint, &[])?;
            return self.capability();
        }
        let texts = sources
            .iter()
            .map(|source| source.text.clone())
            .collect::<Vec<_>>();
        let vectors = self
            .provider
            .embed(EmbeddingPurpose::Document, &texts)
            .await?;
        validate_vectors(&descriptor, texts.len(), &vectors)?;
        let indexed_at_ms = now_ms();
        let records = sources
            .iter()
            .zip(vectors)
            .map(|(source, vector)| SemanticEmbeddingIndexRecord {
                source_kind: source.kind,
                source_id: source.source_id.clone(),
                language: source.language.clone(),
                channel: source.channel,
                text_sha256: hex::encode(Sha256::digest(source.text.as_bytes())),
                model_fingerprint: descriptor.model_fingerprint.clone(),
                dimension: descriptor.dimension,
                vector,
                indexed_at_ms,
            })
            .collect::<Vec<_>>();
        self.index
            .replace_semantic_embedding_index(&descriptor.model_fingerprint, &records)?;
        self.capability()
    }

    pub async fn search(
        &self,
        query: &str,
        language: Option<&str>,
        source_kind: Option<SemanticEmbeddingSourceKind>,
        channel: Option<ProductionChannel>,
        limit: u32,
    ) -> Result<SemanticSearchResult, ApplicationError> {
        let query = query.trim();
        if query.is_empty() {
            return Err(ApplicationError::Validation("query"));
        }
        let capability = self.capability()?;
        let Some(descriptor) = capability.descriptor.clone() else {
            return Ok(SemanticSearchResult {
                capability,
                query: query.into(),
                hits: Vec::new(),
            });
        };
        if capability.status != SemanticEmbeddingStatus::Ready {
            return Ok(SemanticSearchResult {
                capability,
                query: query.into(),
                hits: Vec::new(),
            });
        }
        let query_vectors = self
            .provider
            .embed(EmbeddingPurpose::Query, &[query.to_owned()])
            .await?;
        validate_vectors(&descriptor, 1, &query_vectors)?;
        let query_vector = &query_vectors[0];
        let records = self
            .index
            .list_semantic_embedding_records(&descriptor.model_fingerprint)?;
        let sources = self
            .sources()?
            .into_iter()
            .map(|source| ((source.kind, source.source_id.clone()), source))
            .collect::<HashMap<_, _>>();
        let mut hits = records
            .into_iter()
            .filter(|record| language.is_none_or(|value| record.language.as_str() == value))
            .filter(|record| source_kind.is_none_or(|value| record.source_kind == value))
            .filter(|record| channel.is_none_or(|value| record.channel == Some(value)))
            .filter_map(|record| {
                let source = sources
                    .get(&(record.source_kind, record.source_id.clone()))?
                    .clone();
                Some(SemanticSearchHit {
                    source,
                    similarity: cosine(query_vector, &record.vector),
                    model_fingerprint: record.model_fingerprint,
                })
            })
            .collect::<Vec<_>>();
        hits.sort_by(|a, b| {
            b.similarity
                .total_cmp(&a.similarity)
                .then_with(|| a.source.source_id.cmp(&b.source.source_id))
        });
        hits.truncate(limit.clamp(1, 100) as usize);
        Ok(SemanticSearchResult {
            capability,
            query: query.into(),
            hits,
        })
    }

    pub async fn enrich_gap_review(
        &self,
        language: &str,
        channel: ProductionChannel,
        limit: u32,
    ) -> Result<SemanticallyEnrichedProductionGapReview, ApplicationError> {
        const THRESHOLD: f32 = 0.70;
        let review = self
            .gap_review
            .production_gap_review(language, channel, limit)?;
        let capability = self.capability()?;
        let Some(descriptor) = capability.descriptor.clone() else {
            return Ok(SemanticallyEnrichedProductionGapReview {
                review,
                semantic_capability: capability,
                enrichments: Vec::new(),
                threshold: THRESHOLD,
            });
        };
        if capability.status != SemanticEmbeddingStatus::Ready || review.targets.is_empty() {
            return Ok(SemanticallyEnrichedProductionGapReview {
                review,
                semantic_capability: capability,
                enrichments: Vec::new(),
                threshold: THRESHOLD,
            });
        }
        let target_texts = review
            .targets
            .iter()
            .map(|target| target.display_form.clone())
            .collect::<Vec<_>>();
        let target_vectors = self
            .provider
            .embed(EmbeddingPurpose::Query, &target_texts)
            .await?;
        validate_vectors(&descriptor, target_texts.len(), &target_vectors)?;
        let records = self
            .index
            .list_semantic_embedding_records(&descriptor.model_fingerprint)?;
        let source_lookup = self
            .sources()?
            .into_iter()
            .map(|source| ((source.kind, source.source_id.clone()), source))
            .collect::<HashMap<_, _>>();
        let lexeme_records = records
            .into_iter()
            .filter(|record| {
                record.source_kind == SemanticEmbeddingSourceKind::ProductionLexeme
                    && record.language.as_str() == language
                    && record.channel == Some(channel)
            })
            .collect::<Vec<_>>();
        let enrichments = review.targets.iter().zip(target_vectors).map(|(target, vector)| {
            let mut matches = lexeme_records.iter().filter_map(|record| {
                let similarity = cosine(&vector, &record.vector);
                (similarity >= THRESHOLD).then(|| NearSemanticProductionMatch {
                    normalized_key: source_lookup
                        .get(&(record.source_kind, record.source_id.clone()))
                        .map(|source| source.text.clone())
                        .unwrap_or_else(|| record.source_id.clone()),
                    similarity,
                    model_fingerprint: descriptor.model_fingerprint.clone(),
                    explanation: format!("Your corpus contains ‘{}’; this model ranks it semantically near ‘{}’ at {:.3}. This is a practice clue, not a synonym or capability claim.", source_lookup.get(&(record.source_kind, record.source_id.clone())).map(|source| source.text.as_str()).unwrap_or(&record.source_id), target.display_form, similarity),
                })
            }).collect::<Vec<_>>();
            matches.sort_by(|a, b| b.similarity.total_cmp(&a.similarity).then_with(|| a.normalized_key.cmp(&b.normalized_key)));
            matches.truncate(3);
            ProductionGapSemanticEnrichment {
                lexical_entry_id: target.lexical_entry_id.as_str().to_owned(),
                target_normalized_key: target.normalized_key.clone(),
                matches,
            }
        }).collect();
        Ok(SemanticallyEnrichedProductionGapReview {
            review,
            semantic_capability: capability,
            enrichments,
            threshold: THRESHOLD,
        })
    }

    pub fn delete_index(&self) -> Result<SemanticEmbeddingCapability, ApplicationError> {
        self.index.delete_semantic_embedding_index()?;
        self.capability()
    }

    fn sources(&self) -> Result<Vec<SemanticEmbeddingSource>, ApplicationError> {
        let mut sources = self
            .corpus
            .list_semantic_corpus_occurrences()?
            .into_iter()
            .map(|item| SemanticEmbeddingSource {
                kind: SemanticEmbeddingSourceKind::MediaCorpus,
                source_id: item.id.as_str().to_owned(),
                language: item.language,
                channel: None,
                text: item.display_text,
                media_id: item.media_id,
                track_id: item.track_id,
                sentence_id: item.sentence_id,
                start_ms: item.start_ms,
                end_ms: item.end_ms,
                produced_at_ms: None,
            })
            .collect::<Vec<_>>();
        let documents = self.production.list_production_documents()?;
        let mut languages_and_channels = Vec::new();
        for document in documents {
            if !languages_and_channels.contains(&(document.language.clone(), document.channel)) {
                languages_and_channels.push((document.language.clone(), document.channel));
            }
            sources.push(SemanticEmbeddingSource {
                kind: SemanticEmbeddingSourceKind::ProductionDocument,
                source_id: document.id.as_str().to_owned(),
                language: document.language,
                channel: Some(document.channel),
                text: document.response_text,
                media_id: document.media_id,
                track_id: None,
                sentence_id: None,
                start_ms: document.start_ms,
                end_ms: document.end_ms,
                produced_at_ms: Some(document.produced_at_ms),
            });
        }
        for (language, channel) in languages_and_channels {
            for lexeme in self
                .production
                .list_production_lexemes(&language, channel)?
            {
                sources.push(SemanticEmbeddingSource {
                    kind: SemanticEmbeddingSourceKind::ProductionLexeme,
                    source_id: format!(
                        "{}:{}:{}",
                        language.as_str(),
                        match channel {
                            ProductionChannel::Written => "written",
                            ProductionChannel::Spoken => "spoken",
                        },
                        lexeme
                    ),
                    language: language.clone(),
                    channel: Some(channel),
                    text: lexeme,
                    media_id: None,
                    track_id: None,
                    sentence_id: None,
                    start_ms: 0,
                    end_ms: 0,
                    produced_at_ms: None,
                });
            }
        }
        Ok(sources)
    }

    fn current_sources_match(
        &self,
        descriptor: &EmbeddingModelDescriptor,
    ) -> Result<bool, ApplicationError> {
        let records = self
            .index
            .list_semantic_embedding_records(&descriptor.model_fingerprint)?;
        let sources = self.sources()?;
        if records.len() != sources.len() {
            return Ok(false);
        }
        let hashes = sources
            .into_iter()
            .map(|source| {
                (
                    (source.kind, source.source_id),
                    hex::encode(Sha256::digest(source.text.as_bytes())),
                )
            })
            .collect::<HashMap<_, _>>();
        Ok(records.iter().all(|record| {
            hashes
                .get(&(record.source_kind, record.source_id.clone()))
                .is_some_and(|hash| hash == &record.text_sha256)
        }))
    }
}

fn validate_vectors(
    descriptor: &EmbeddingModelDescriptor,
    expected_count: usize,
    vectors: &[Vec<f32>],
) -> Result<(), ApplicationError> {
    if vectors.len() != expected_count {
        return Err(ApplicationError::Invalid(format!(
            "embedding provider returned {} vectors for {expected_count} texts",
            vectors.len()
        )));
    }
    if vectors.iter().any(|vector| {
        vector.len() != descriptor.dimension as usize
            || vector.iter().any(|value| !value.is_finite())
    }) {
        return Err(ApplicationError::Invalid(format!(
            "embedding provider returned a non-finite or non-{}-dimensional vector",
            descriptor.dimension
        )));
    }
    Ok(())
}

fn cosine(left: &[f32], right: &[f32]) -> f32 {
    if left.len() != right.len() || left.is_empty() {
        return f32::NEG_INFINITY;
    }
    let dot = left.iter().zip(right).map(|(a, b)| a * b).sum::<f32>();
    let left_norm = left.iter().map(|value| value * value).sum::<f32>().sqrt();
    let right_norm = right.iter().map(|value| value * value).sum::<f32>().sqrt();
    if left_norm == 0.0 || right_norm == 0.0 {
        f32::NEG_INFINITY
    } else {
        dot / (left_norm * right_norm)
    }
}
