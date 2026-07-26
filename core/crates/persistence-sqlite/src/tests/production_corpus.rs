use std::sync::Arc;

use application::{AppServices, ProductionCorpusRepository};
use domain::{
    AttemptResponse, LanguageCode, ProductionAssistance, ProductionCorpusEntry,
    ProductionCorpusEntryId, ResponseTranscriptSource, SemanticAttemptStatus, SemanticRubricId,
    SemanticTaskAttemptId, SemanticTaskGoldFixture, SemanticTaskKind,
};

use super::*;

fn services(repo: &Arc<SqliteRepository>) -> AppServices {
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
    .with_semantic_task_repository(repo.clone())
    .with_production_corpus_repository(repo.clone())
}

fn writing_fixture() -> (domain::SemanticRubric, domain::SemanticTaskAttempt) {
    let fixture: SemanticTaskGoldFixture = serde_json::from_str(include_str!(
        "../../../../testdata/semantic-task/gold-fixture-v1.json"
    ))
    .unwrap();
    let mut rubric = fixture.rubric;
    rubric.id = SemanticRubricId::parse("production-rubric").unwrap();
    rubric.purpose = SemanticTaskKind::OpinionResponse;
    rubric.response_language = LanguageCode::parse("en").unwrap();
    let mut attempt = fixture.attempts[0].clone();
    attempt.id = SemanticTaskAttemptId::parse("production-attempt-v1").unwrap();
    attempt.kind = SemanticTaskKind::OpinionResponse;
    attempt.rubric_id = rubric.id.clone();
    attempt.conditions.l1_trigger = None;
    attempt.conditions.audio_play_count = None;
    attempt.conditions.prompt_snapshot = Some("Respond to the proposal.".into());
    attempt.responses = vec![AttemptResponse {
        revision: 1,
        raw_transcript: None,
        transcript: "This proposal works well.".into(),
        source: ResponseTranscriptSource::Typed,
        recording_asset_id: None,
        asr_reliability: None,
        language: LanguageCode::parse("en").unwrap(),
        recorded_at_ms: 100,
    }];
    attempt.status = SemanticAttemptStatus::Completed;
    attempt.started_at_ms = 90;
    attempt.ended_at_ms = Some(100);
    (rubric, attempt)
}

#[test]
fn writing_attempt_incrementally_indexes_lemma_and_phrase_without_evidence_writes() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let (rubric, attempt) = writing_fixture();
    services.semantic().save_semantic_rubric(rubric).unwrap();
    services
        .production_corpus()
        .record_semantic_attempt_and_index(attempt)
        .unwrap();

    let lemma = services
        .production_corpus()
        .search_production_corpus("en", "proposal", 10, 0)
        .unwrap();
    assert_eq!(lemma.len(), 1);
    assert_eq!(lemma[0].document.response_text, "This proposal works well.");
    assert_eq!(
        lemma[0].document.assistance,
        ProductionAssistance::ContentAnchored
    );
    let entry = lemma[0].entry.as_ref().unwrap();
    assert_eq!(entry.display_text, "proposal");
    assert_eq!(
        &lemma[0].document.response_text[entry.start_char as usize..entry.end_char as usize],
        "proposal"
    );

    let phrase = services
        .production_corpus()
        .search_production_corpus("en", "proposal works", 10, 0)
        .unwrap();
    assert_eq!(phrase.len(), 1);
    assert!(phrase[0].entry.is_none());

    let connection = repo.connection.lock();
    let observations: i64 = connection
        .query_row("SELECT COUNT(*) FROM lexical_observations", [], |row| {
            row.get(0)
        })
        .unwrap();
    let capability_history: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM lexical_capability_history",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!((observations, capability_history), (0, 0));
}

#[test]
fn gap_review_is_ranked_read_only_and_small_n_stays_starter() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let (rubric, attempt) = writing_fixture();
    services.semantic().save_semantic_rubric(rubric).unwrap();
    services
        .production_corpus()
        .record_semantic_attempt_and_index(attempt)
        .unwrap();
    let connection = repo.connection.lock();
    connection.execute(
        "INSERT INTO lexical_entries
         (id,language,kind,granularity,normalization,normalized_key,canonical_form,normalized_form,display_form,status,normalization_provider,normalization_version,updated_at_ms,learning_updated_at_ms)
         VALUES ('enjoy-id','en','\"word\"','\"word\"','\"lemma\"','enjoy','enjoy','enjoy','enjoy','\"known_recognized\"','test','v1',10,10)", []).unwrap();
    connection.execute(
        "INSERT INTO lexical_capability_states
         (lexical_entry_id,sense_id,capability,projection_json,updated_at_ms)
         VALUES ('enjoy-id','','\"reading\"',?1,10)",
        [serde_json::json!({"conclusion":"acquired","source":"legacy_learning_status_migration","algorithm_version":"test","updated_at_ms":10}).to_string()],
    ).unwrap();
    drop(connection);

    let review = services
        .production_corpus()
        .production_gap_review("en", domain::ProductionChannel::Written, 10)
        .unwrap();
    assert_eq!(review.readiness, domain::ProductionGapReadiness::Starter);
    assert_eq!(
        (
            review.document_count,
            review.token_count,
            review.lemma_count
        ),
        (1, 4, 4)
    );
    assert_eq!(review.targets.len(), 1);
    assert_eq!(review.targets[0].normalized_key, "enjoy");
    assert!(review.targets[0].reading_acquired);

    let connection = repo.connection.lock();
    let writes: i64 = connection
        .query_row(
            "SELECT (SELECT COUNT(*) FROM learning_observations) +
                (SELECT COUNT(*) FROM lexical_capability_history)",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(writes, 0);
}

#[test]
fn rebuild_is_idempotent_and_keeps_one_response_copy_per_document() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let (rubric, attempt) = writing_fixture();
    services.semantic().save_semantic_rubric(rubric).unwrap();
    services
        .production_corpus()
        .record_semantic_attempt_and_index(attempt)
        .unwrap();

    let before = services
        .production_corpus()
        .search_production_corpus("en", "proposal", 10, 0)
        .unwrap();
    assert_eq!(
        services
            .production_corpus()
            .rebuild_production_corpus()
            .unwrap(),
        1
    );
    let after = services
        .production_corpus()
        .search_production_corpus("en", "proposal", 10, 0)
        .unwrap();
    assert_eq!(before, after);

    let connection = repo.connection.lock();
    let documents: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM production_corpus_documents",
            [],
            |row| row.get(0),
        )
        .unwrap();
    let response_columns: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM pragma_table_info('production_corpus_entries') WHERE name='response_text'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(documents, 1);
    assert_eq!(response_columns, 0);
}

#[test]
fn failed_atomic_rebuild_preserves_previous_projection() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let (rubric, attempt) = writing_fixture();
    services.semantic().save_semantic_rubric(rubric).unwrap();
    services
        .production_corpus()
        .record_semantic_attempt_and_index(attempt)
        .unwrap();
    let before = services
        .production_corpus()
        .search_production_corpus("en", "proposal", 10, 0)
        .unwrap();

    let dangling = ProductionCorpusEntry {
        id: ProductionCorpusEntryId::parse("dangling-entry").unwrap(),
        document_id: domain::ProductionCorpusDocumentId::parse("missing-document").unwrap(),
        normalized_key: "proposal".into(),
        display_text: "proposal".into(),
        start_char: 0,
        end_char: 8,
    };
    assert!(
        repo.replace_all_production_entries(&[], &[dangling])
            .is_err()
    );
    let after = services
        .production_corpus()
        .search_production_corpus("en", "proposal", 10, 0)
        .unwrap();
    assert_eq!(before, after);
}
