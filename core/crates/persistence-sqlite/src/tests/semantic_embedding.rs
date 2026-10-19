use std::sync::Arc;

use application::{AppServices, ApplicationError, EmbeddingProvider};
use async_trait::async_trait;
use domain::*;

use super::*;

struct FixtureProvider {
    fingerprint: &'static str,
}

#[async_trait]
impl EmbeddingProvider for FixtureProvider {
    fn descriptor(&self) -> Option<EmbeddingModelDescriptor> {
        Some(EmbeddingModelDescriptor {
            provider_id: "fixture".into(),
            model_id: "semantic-fixture".into(),
            model_version: "1".into(),
            runtime_version: "test".into(),
            artifact_sha256: "fixture".into(),
            dimension: 3,
            normalization: "unit-fixture".into(),
            purpose_contract: "symmetric".into(),
            index_schema_version: SEMANTIC_INDEX_SCHEMA_VERSION,
            model_fingerprint: self.fingerprint.into(),
            local: true,
        })
    }

    async fn embed(
        &self,
        _purpose: EmbeddingPurpose,
        texts: &[String],
    ) -> Result<Vec<Vec<f32>>, ApplicationError> {
        Ok(texts
            .iter()
            .map(|text| {
                let lower = text.to_ascii_lowercase();
                if lower.contains("large") || lower.contains("enormous") || lower == "big" {
                    vec![1.0, 0.0, 0.0]
                } else if lower.contains("coffee") {
                    vec![0.0, 1.0, 0.0]
                } else {
                    vec![0.0, 0.0, 1.0]
                }
            })
            .collect())
    }
}

fn services(repo: &Arc<SqliteRepository>, fingerprint: &'static str) -> AppServices {
    AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_corpus_index_repository(repo.clone())
    .with_production_corpus_repository(repo.clone())
    .with_semantic_embedding(repo.clone(), Arc::new(FixtureProvider { fingerprint }))
}

#[tokio::test]
async fn semantic_index_rebuild_search_and_model_stale_are_read_only() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let language = LanguageCode::parse("en").unwrap();
    {
        let connection = repo.connection.lock();
        connection.execute("INSERT INTO media_items (id,path,fingerprint,title,kind,created_at_ms,updated_at_ms) VALUES ('media-semantic','/tmp/semantic.mp4','semantic-fp','Semantic fixture','\"video\"',1,1)", []).unwrap();
        connection.execute("INSERT INTO subtitle_tracks (id,media_id,fingerprint,language,source) VALUES ('track-semantic','media-semantic','track-fp','en','\"embedded\"')", []).unwrap();
    }
    let occurrence = CorpusOccurrence {
        id: CorpusOccurrenceId::parse("media-large").unwrap(),
        language: language.clone(),
        kind: CorpusOccurrenceKind::Phrase,
        normalized_key: Some("large room".into()),
        display_text: "A large room with tall windows.".into(),
        media_id: Some(MediaId::parse("media-semantic").unwrap()),
        track_id: Some(SubtitleTrackId::parse("track-semantic").unwrap()),
        sentence_id: None,
        start_ms: 10,
        end_ms: 20,
        source_snapshot: "A large room with tall windows.".into(),
    };
    application::CorpusIndexRepository::upsert_corpus_occurrence(repo.as_ref(), &occurrence)
        .unwrap();
    let before = writer_counts(repo.as_ref());
    let semantic = services(&repo, "space-a").semantic_embedding();
    let capability = semantic.rebuild().await.unwrap();
    assert_eq!(capability.status, SemanticEmbeddingStatus::Ready);
    assert_eq!(capability.indexed_source_count, 1);

    let result = semantic
        .search("an enormous interior", Some("en"), None, None, 5)
        .await
        .unwrap();
    assert_eq!(result.hits[0].source.source_id, "media-large");
    assert_eq!(writer_counts(repo.as_ref()), before);

    let mut changed_source = occurrence;
    changed_source.display_text = "A small room with short windows.".into();
    application::CorpusIndexRepository::upsert_corpus_occurrence(repo.as_ref(), &changed_source)
        .unwrap();
    assert_eq!(
        semantic.capability().unwrap().status,
        SemanticEmbeddingStatus::Stale
    );

    let changed = services(&repo, "space-b")
        .semantic_embedding()
        .capability()
        .unwrap();
    assert_eq!(changed.status, SemanticEmbeddingStatus::Stale);
    assert_eq!(changed.indexed_source_count, 0);
}

#[test]
fn semantic_index_replacement_is_atomic_and_rejects_mixed_spaces() {
    let repo = SqliteRepository::in_memory().unwrap();
    let record = SemanticEmbeddingIndexRecord {
        source_kind: SemanticEmbeddingSourceKind::MediaCorpus,
        source_id: "source".into(),
        language: LanguageCode::parse("en").unwrap(),
        channel: None,
        text_sha256: "text".into(),
        model_fingerprint: "space-a".into(),
        dimension: 2,
        vector: vec![1.0, 0.0],
        indexed_at_ms: 1,
    };
    application::SemanticEmbeddingIndexRepository::replace_semantic_embedding_index(
        &repo,
        "space-a",
        std::slice::from_ref(&record),
    )
    .unwrap();
    assert!(
        application::SemanticEmbeddingIndexRepository::replace_semantic_embedding_index(
            &repo,
            "space-b",
            &[record]
        )
        .is_err()
    );
    assert_eq!(
        application::SemanticEmbeddingIndexRepository::semantic_embedding_index_summary(&repo)
            .unwrap(),
        vec![("space-a".into(), 1)]
    );
}

fn writer_counts(repo: &SqliteRepository) -> Vec<u32> {
    let connection = repo.connection.lock();
    [
        "learning_observations",
        "recognition_evidence",
        "capability_proposals",
        "review_items",
        "production_corpus_documents",
    ]
    .into_iter()
    .map(|table| {
        connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .unwrap_or(0)
    })
    .collect()
}
