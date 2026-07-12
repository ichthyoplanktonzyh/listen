use std::sync::Arc;

use super::*;

fn semantic_services(repo: &Arc<SqliteRepository>) -> AppServices {
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
}

fn gold_fixture() -> SemanticTaskGoldFixture {
    serde_json::from_str(include_str!(
        "../../../../testdata/semantic-task/gold-fixture-v1.json"
    ))
    .expect("gold fixture parses")
}

fn save_gold_fixture(services: &AppServices, fixture: &SemanticTaskGoldFixture) {
    services
        .save_semantic_rubric(fixture.rubric.clone())
        .unwrap();
    for attempt in &fixture.attempts {
        services.record_semantic_attempt(attempt.clone()).unwrap();
    }
    for judgment in &fixture.judgments {
        services.record_semantic_judgment(judgment.clone()).unwrap();
    }
    for adjudication in &fixture.adjudications {
        services
            .record_judgment_adjudication(adjudication.clone())
            .unwrap();
    }
}

fn count(repo: &SqliteRepository, table: &str) -> i64 {
    repo.connection
        .lock()
        .unwrap()
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .unwrap()
}

#[test]
fn semantic_gold_fixture_round_trips_through_use_cases() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    save_gold_fixture(&services, &fixture);

    assert_eq!(
        services
            .semantic_rubric(&fixture.rubric.id, None)
            .unwrap()
            .unwrap(),
        fixture.rubric
    );
    let attempts = services
        .semantic_attempts_for_rubric(&fixture.rubric.id)
        .unwrap();
    assert_eq!(attempts, fixture.attempts);

    for judgment in &fixture.judgments {
        let listed = services
            .semantic_judgments_for_attempt(&judgment.attempt_id)
            .unwrap();
        assert_eq!(listed, vec![judgment.clone()]);
    }

    let adjudications = services
        .judgment_adjudications(&fixture.adjudications[0].judgment_id)
        .unwrap();
    assert_eq!(adjudications, fixture.adjudications);

    // The exit-signal comparability property survives persistence.
    let scored: Vec<_> = fixture
        .judgments
        .iter()
        .filter(|judgment| judgment.abstain.is_none())
        .collect();
    assert!(domain::judgments_directly_comparable(scored[0], scored[1]));
}

#[test]
fn semantic_flow_writes_no_lexical_evidence_and_no_capability_changes() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    save_gold_fixture(&services, &gold_fixture());

    // L1 retelling stayed a clip-level fact: nothing leaked into the lexical
    // evidence channel, capability history, or upgrade machinery.
    assert_eq!(count(&repo, "learning_observations"), 0);
    assert_eq!(count(&repo, "lexical_observations"), 0);
    assert_eq!(count(&repo, "lexical_capability_history"), 0);
    assert_eq!(count(&repo, "lexical_capability_states"), 0);
    assert_eq!(count(&repo, "upgrade_suggestions"), 0);
}

#[test]
fn semantic_tables_are_append_only() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    save_gold_fixture(&services, &gold_fixture());

    let conn = repo.connection.lock().unwrap();
    let statements = [
        "UPDATE semantic_rubrics SET version = 99",
        "DELETE FROM semantic_rubrics",
        "UPDATE semantic_task_attempts SET status = '\"abandoned\"'",
        "DELETE FROM semantic_task_attempts",
        "UPDATE semantic_judgments SET abstained = 1",
        "DELETE FROM semantic_judgments",
        "UPDATE judgment_adjudications SET point_id = 'p9'",
        "DELETE FROM judgment_adjudications",
    ];
    for statement in statements {
        let error = conn.execute(statement, []).unwrap_err().to_string();
        assert!(
            error.contains("append-only"),
            "{statement} should be blocked, got: {error}"
        );
    }
}

#[test]
fn semantic_snapshots_survive_media_deletion() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    let media_id = fixture.rubric.source.media_id.clone().unwrap();
    repo.connection
        .lock()
        .unwrap()
        .execute(
            "INSERT INTO media_items (id,path,fingerprint,title,kind,duration_ms,created_at_ms,updated_at_ms)
             VALUES (?1,'/tmp/x.mp4','fp-1','CNN10','video',600000,1,1)",
            [media_id.as_str()],
        )
        .unwrap();
    save_gold_fixture(&services, &fixture);

    repo.connection
        .lock()
        .unwrap()
        .execute("DELETE FROM media_items WHERE id=?1", [media_id.as_str()])
        .unwrap();

    // No foreign key ties the fact layer to media: the full chain still
    // loads and still explains itself via its own snapshots.
    let rubric = services
        .semantic_rubric(&fixture.rubric.id, Some(1))
        .unwrap()
        .unwrap();
    assert!(!rubric.source.transcript_snapshot.is_empty());
    let attempts = services
        .semantic_attempts_for_rubric(&fixture.rubric.id)
        .unwrap();
    assert_eq!(attempts.len(), 3);
    let judgments = services
        .semantic_judgments_for_attempt(&fixture.attempts[0].id)
        .unwrap();
    assert_eq!(judgments.len(), 1);
}

#[test]
fn adjudication_never_rewrites_the_original_judgment() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    services
        .save_semantic_rubric(fixture.rubric.clone())
        .unwrap();
    for attempt in &fixture.attempts {
        services.record_semantic_attempt(attempt.clone()).unwrap();
    }
    for judgment in &fixture.judgments {
        services.record_semantic_judgment(judgment.clone()).unwrap();
    }

    let adjudication = fixture.adjudications[0].clone();
    let raw_before: String = repo
        .connection
        .lock()
        .unwrap()
        .query_row(
            "SELECT judgment_json FROM semantic_judgments WHERE id=?1",
            [adjudication.judgment_id.as_str()],
            |row| row.get(0),
        )
        .unwrap();

    services
        .record_judgment_adjudication(adjudication.clone())
        .unwrap();

    let raw_after: String = repo
        .connection
        .lock()
        .unwrap()
        .query_row(
            "SELECT judgment_json FROM semantic_judgments WHERE id=?1",
            [adjudication.judgment_id.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(raw_before, raw_after);
    assert_eq!(
        services
            .judgment_adjudications(&adjudication.judgment_id)
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn use_cases_reject_missing_targets_duplicates_and_tampered_hashes() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();

    // Attempt before its rubric exists.
    assert!(matches!(
        services.record_semantic_attempt(fixture.attempts[0].clone()),
        Err(ApplicationError::NotFound(_))
    ));

    services
        .save_semantic_rubric(fixture.rubric.clone())
        .unwrap();
    assert!(matches!(
        services.save_semantic_rubric(fixture.rubric.clone()),
        Err(ApplicationError::Conflict(_))
    ));

    services
        .record_semantic_attempt(fixture.attempts[0].clone())
        .unwrap();
    assert!(matches!(
        services.record_semantic_attempt(fixture.attempts[0].clone()),
        Err(ApplicationError::Conflict(_))
    ));

    let mut tampered = fixture.judgments[0].clone();
    tampered.rubric_source_sha256 = domain::transcript_sha256("tampered");
    assert!(matches!(
        services.record_semantic_judgment(tampered),
        Err(ApplicationError::Invalid(_))
    ));

    // Adjudication of a judgment that was never recorded.
    assert!(matches!(
        services.record_judgment_adjudication(fixture.adjudications[0].clone()),
        Err(ApplicationError::NotFound(_))
    ));
}

#[test]
fn rubric_revision_appends_a_new_version_and_keeps_history() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    services
        .save_semantic_rubric(fixture.rubric.clone())
        .unwrap();

    let mut revised = fixture.rubric.clone();
    revised.version = 2;
    revised.points[3].statement = "时间：周一早晨（当地时间 7:30 前后）".into();
    revised.revision = Some(RubricRevisionNote {
        revised_from_version: 1,
        note: "细化 P4 的时间表述".into(),
        revised_at_ms: 1781222700000,
    });
    services.save_semantic_rubric(revised.clone()).unwrap();

    // A revision with a different source snapshot is a different segment and
    // must be rejected instead of silently rebasing history.
    let mut snapshot_swap = revised.clone();
    snapshot_swap.version = 3;
    snapshot_swap.revision = Some(RubricRevisionNote {
        revised_from_version: 2,
        note: "swap".into(),
        revised_at_ms: 1781222800000,
    });
    snapshot_swap.source.transcript_snapshot = "a different segment".into();
    assert!(matches!(
        services.save_semantic_rubric(snapshot_swap),
        Err(ApplicationError::Invalid(_))
    ));

    assert_eq!(
        services
            .semantic_rubric(&fixture.rubric.id, None)
            .unwrap()
            .unwrap(),
        revised
    );
    assert_eq!(
        services
            .semantic_rubric(&fixture.rubric.id, Some(1))
            .unwrap()
            .unwrap(),
        fixture.rubric
    );
}
