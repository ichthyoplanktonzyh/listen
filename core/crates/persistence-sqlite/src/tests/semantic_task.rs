use std::sync::Arc;

use super::*;
use domain::{
    AttemptResponse, ResponseTranscriptSource, SemanticAttemptStatus, SemanticTaskConditions,
    WritingFeedbackGenerator, WritingFeedbackLayer, WritingFeedbackProvenance,
    WritingFindingDecision, WritingFindingSeverity, WritingSourceSpan, transcript_sha256,
    writing_feedback_finding_id, writing_finding_disposition_id,
};

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
        .semantic()
        .save_semantic_rubric(fixture.rubric.clone())
        .unwrap();
    for attempt in &fixture.attempts {
        services
            .semantic()
            .record_semantic_attempt(attempt.clone())
            .unwrap();
    }
    for judgment in &fixture.judgments {
        services
            .semantic()
            .record_semantic_judgment(judgment.clone())
            .unwrap();
    }
    for adjudication in &fixture.adjudications {
        services
            .semantic()
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
fn writing_findings_and_dispositions_are_append_only_and_user_revision_bound() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    let mut rubric = fixture.rubric.clone();
    rubric.purpose = SemanticTaskKind::OpinionResponse;
    rubric.response_language = LanguageCode::parse("en").unwrap();
    services
        .semantic()
        .save_semantic_rubric(rubric.clone())
        .unwrap();
    let draft = WritingDraft {
        rubric_id: rubric.id.clone(),
        prompt_snapshot: "Respond to the proposal.".into(),
        transcript: "unfinished".into(),
        updated_at_ms: 5,
    };
    services
        .semantic()
        .save_writing_draft(draft.clone())
        .unwrap();
    assert_eq!(
        services.semantic().writing_draft(&rubric.id).unwrap(),
        Some(draft)
    );
    services
        .semantic()
        .delete_writing_draft(&rubric.id)
        .unwrap();
    assert_eq!(services.semantic().writing_draft(&rubric.id).unwrap(), None);

    let first_text = "This is an useful proposal.";
    let second_text = "This is a useful proposal.";
    let attempt = SemanticTaskAttempt {
        id: SemanticTaskAttemptId::parse("writing-attempt-persistence").unwrap(),
        kind: SemanticTaskKind::OpinionResponse,
        target: fixture.attempts[0].target.clone(),
        anchors: fixture.attempts[0].anchors.clone(),
        rubric_id: rubric.id.clone(),
        rubric_version: rubric.version,
        conditions: SemanticTaskConditions {
            source_text_visible: true,
            audio_play_count: None,
            notes_allowed: true,
            l1_trigger: None,
            speaking_assistance: None,
            speaking_recall: None,
            prompt_snapshot: Some("Respond to the proposal.".into()),
        },
        responses: vec![AttemptResponse {
            revision: 1,
            raw_transcript: None,
            transcript: first_text.into(),
            source: ResponseTranscriptSource::Typed,
            recording_asset_id: None,
            asr_reliability: None,
            language: rubric.response_language.clone(),
            recorded_at_ms: 20,
        }],
        status: SemanticAttemptStatus::Completed,
        started_at_ms: 10,
        ended_at_ms: Some(25),
    };
    services
        .semantic()
        .record_semantic_attempt(attempt.clone())
        .unwrap();
    let mut revised_attempt = attempt.clone();
    revised_attempt.id = SemanticTaskAttemptId::parse("writing-attempt-revised").unwrap();
    revised_attempt.responses.push(AttemptResponse {
        revision: 2,
        raw_transcript: None,
        transcript: second_text.into(),
        source: ResponseTranscriptSource::Typed,
        recording_asset_id: None,
        asr_reliability: None,
        language: rubric.response_language.clone(),
        recorded_at_ms: 30,
    });
    revised_attempt.started_at_ms = 26;
    revised_attempt.ended_at_ms = Some(40);
    services
        .semantic()
        .record_semantic_attempt(revised_attempt.clone())
        .unwrap();

    let provenance = WritingFeedbackProvenance {
        generator: WritingFeedbackGenerator::LocalRule,
        provider_id: "harper".into(),
        provider_version: "0.40.0".into(),
        ruleset_version: Some("curated-american".into()),
        evidence_class: "heuristic_proxy".into(),
    };
    let span = Some(WritingSourceSpan {
        start_char: 8,
        end_char: 10,
    });
    let finding = WritingFeedbackFinding {
        id: writing_feedback_finding_id(
            &attempt.id,
            1,
            first_text,
            WritingFeedbackLayer::Grammar,
            span,
            "Use ‘a’ before a consonant sound.",
            &provenance,
        ),
        attempt_id: attempt.id.clone(),
        response_revision: 1,
        response_transcript_sha256: transcript_sha256(first_text),
        layer: WritingFeedbackLayer::Grammar,
        severity: WritingFindingSeverity::Suggestion,
        source_span: span,
        message: "Use ‘a’ before a consonant sound.".into(),
        suggested_replacement: Some("a".into()),
        provenance,
        created_at_ms: 50,
    };
    services
        .semantic()
        .record_writing_feedback_finding(finding.clone())
        .unwrap();

    let disposition = WritingFindingDisposition {
        id: writing_finding_disposition_id(
            &finding.id,
            WritingFindingDecision::Accepted,
            Some(&revised_attempt.id),
            Some(2),
            60,
        ),
        finding_id: finding.id.clone(),
        decision: WritingFindingDecision::Accepted,
        resulting_attempt_id: Some(revised_attempt.id.clone()),
        resulting_response_revision: Some(2),
        note: None,
        occurred_at_ms: 60,
    };
    services
        .semantic()
        .record_writing_finding_disposition(disposition.clone())
        .unwrap();

    assert_eq!(
        services
            .semantic()
            .writing_feedback_findings(&attempt.id)
            .unwrap(),
        vec![finding.clone()]
    );
    assert_eq!(
        services
            .semantic()
            .writing_finding_dispositions(&finding.id)
            .unwrap(),
        vec![disposition]
    );
    assert_eq!(count(&repo, "writing_feedback_findings"), 1);
    assert_eq!(count(&repo, "writing_finding_dispositions"), 1);

    let connection = repo.connection.lock().unwrap();
    assert!(
        connection
            .execute(
                "UPDATE writing_feedback_findings SET provider_id='mutated' WHERE id=?1",
                [finding.id.as_str()],
            )
            .is_err()
    );
    assert!(
        connection
            .execute(
                "DELETE FROM writing_feedback_findings WHERE id=?1",
                [finding.id.as_str()],
            )
            .is_err()
    );
}

#[test]
fn semantic_gold_fixture_round_trips_through_use_cases() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    save_gold_fixture(&services, &fixture);

    assert_eq!(
        services
            .semantic()
            .semantic_rubric(&fixture.rubric.id, None)
            .unwrap()
            .unwrap(),
        fixture.rubric
    );
    let attempts = services
        .semantic()
        .semantic_attempts_for_rubric(&fixture.rubric.id)
        .unwrap();
    assert_eq!(attempts, fixture.attempts);

    for judgment in &fixture.judgments {
        let listed = services
            .semantic()
            .semantic_judgments_for_attempt(&judgment.attempt_id)
            .unwrap();
        assert_eq!(listed, vec![judgment.clone()]);
    }

    let adjudications = services
        .semantic()
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
        .semantic()
        .semantic_rubric(&fixture.rubric.id, Some(1))
        .unwrap()
        .unwrap();
    assert!(!rubric.source.transcript_snapshot.is_empty());
    let attempts = services
        .semantic()
        .semantic_attempts_for_rubric(&fixture.rubric.id)
        .unwrap();
    assert_eq!(attempts.len(), 3);
    let judgments = services
        .semantic()
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
        .semantic()
        .save_semantic_rubric(fixture.rubric.clone())
        .unwrap();
    for attempt in &fixture.attempts {
        services
            .semantic()
            .record_semantic_attempt(attempt.clone())
            .unwrap();
    }
    for judgment in &fixture.judgments {
        services
            .semantic()
            .record_semantic_judgment(judgment.clone())
            .unwrap();
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
        .semantic()
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
            .semantic()
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
        services
            .semantic()
            .record_semantic_attempt(fixture.attempts[0].clone()),
        Err(ApplicationError::NotFound(_))
    ));

    services
        .semantic()
        .save_semantic_rubric(fixture.rubric.clone())
        .unwrap();
    assert!(matches!(
        services
            .semantic()
            .save_semantic_rubric(fixture.rubric.clone()),
        Err(ApplicationError::Conflict(_))
    ));

    services
        .semantic()
        .record_semantic_attempt(fixture.attempts[0].clone())
        .unwrap();
    assert!(matches!(
        services
            .semantic()
            .record_semantic_attempt(fixture.attempts[0].clone()),
        Err(ApplicationError::Conflict(_))
    ));

    let mut tampered = fixture.judgments[0].clone();
    tampered.rubric_source_sha256 = domain::transcript_sha256("tampered");
    assert!(matches!(
        services.semantic().record_semantic_judgment(tampered),
        Err(ApplicationError::Invalid(_))
    ));

    // Adjudication of a judgment that was never recorded.
    assert!(matches!(
        services
            .semantic()
            .record_judgment_adjudication(fixture.adjudications[0].clone()),
        Err(ApplicationError::NotFound(_))
    ));
}

#[test]
fn rubric_revision_appends_a_new_version_and_keeps_history() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    services
        .semantic()
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
    services
        .semantic()
        .save_semantic_rubric(revised.clone())
        .unwrap();

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
        services.semantic().save_semantic_rubric(snapshot_swap),
        Err(ApplicationError::Invalid(_))
    ));

    assert_eq!(
        services
            .semantic()
            .semantic_rubric(&fixture.rubric.id, None)
            .unwrap()
            .unwrap(),
        revised
    );
    assert_eq!(
        services
            .semantic()
            .semantic_rubric(&fixture.rubric.id, Some(1))
            .unwrap()
            .unwrap(),
        fixture.rubric
    );
}

// ---------------------------------------------------------------------------
// Phase 3.12: vendor draft -> validated judgment, with server-side identity,
// preserved four-layer separation, and honest degradation.
// ---------------------------------------------------------------------------

use application::{JudgeRequest, JudgmentDraft, SemanticJudgeProvider};

/// A fake judge returning a canned draft or a standardized provider error. It
/// stands in for any `LlmChatAdapter`-backed provider so the use-case guarantees
/// can be tested fully offline.
struct FakeJudge {
    result: Result<JudgmentDraft, LlmProviderError>,
}

#[async_trait]
impl SemanticJudgeProvider for FakeJudge {
    fn descriptor(&self) -> application::LlmProviderDescriptor {
        application::LlmProviderDescriptor {
            adapter_kind: LlmAdapterKind::OpenAiChatCompletions,
            model_id: "fake".into(),
            capability: ProviderCapability::unknown(),
        }
    }

    async fn judge(&self, _request: &JudgeRequest) -> Result<JudgmentDraft, LlmProviderError> {
        self.result.clone()
    }
}

fn save_rubric_and_attempts(services: &AppServices, fixture: &SemanticTaskGoldFixture) {
    services
        .semantic()
        .save_semantic_rubric(fixture.rubric.clone())
        .unwrap();
    for attempt in &fixture.attempts {
        services
            .semantic()
            .record_semantic_attempt(attempt.clone())
            .unwrap();
    }
}

fn draft_from(judgment: &SemanticJudgment) -> JudgmentDraft {
    JudgmentDraft {
        points: judgment.points.clone(),
        abstain: judgment.abstain.clone(),
        model_id: Some("fake-model-2026".into()),
        prompt_version: Some("judge/v1".into()),
        schema_version: Some("semantic/v1".into()),
        raw_output: judgment.raw_output.clone(),
    }
}

#[test]
fn llm_draft_becomes_validated_judgment_with_server_minted_identity() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    save_rubric_and_attempts(&services, &fixture);

    // Reuse a known-valid scored judgment's content as the vendor draft.
    let scored = fixture
        .judgments
        .iter()
        .find(|judgment| judgment.abstain.is_none())
        .expect("a scored fixture judgment");
    let draft = draft_from(scored);

    let recorded = services
        .semantic()
        .record_llm_judgment(
            &scored.attempt_id,
            scored.response_revision,
            draft,
            1_800_000_000_000,
        )
        .unwrap();

    // Identity is minted server-side, not carried from any client/vendor value.
    let expected_id = domain::semantic_judgment_id(
        &scored.attempt_id,
        scored.response_revision,
        recorded.rubric_version,
        SemanticGeneratorKind::Llm,
        1_800_000_000_000,
    );
    assert_eq!(recorded.id, expected_id);
    assert_ne!(recorded.id, scored.id);
    // Provenance and snapshot hashes are authoritative, evidence class honest.
    assert_eq!(recorded.provenance.kind, SemanticGeneratorKind::Llm);
    assert_eq!(
        recorded.provenance.model_id.as_deref(),
        Some("fake-model-2026")
    );
    assert_eq!(recorded.evidence_class, "heuristic_proxy");
    assert_eq!(
        recorded.rubric_source_sha256,
        domain::transcript_sha256(&fixture.rubric.source.transcript_snapshot)
    );

    // It is directly comparable to any other judgment on the same rubric version.
    let other_scored = fixture
        .judgments
        .iter()
        .find(|judgment| judgment.abstain.is_none() && judgment.id != scored.id);
    if let Some(other) = other_scored {
        // Same rubric identity/version/source hash => comparable scale.
        assert_eq!(recorded.rubric_id, other.rubric_id);
        assert_eq!(recorded.rubric_version, other.rubric_version);
        assert_eq!(recorded.rubric_source_sha256, other.rubric_source_sha256);
    }
}

#[test]
fn llm_judgment_path_writes_no_lexical_or_capability_evidence() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    save_rubric_and_attempts(&services, &fixture);

    let scored = fixture
        .judgments
        .iter()
        .find(|judgment| judgment.abstain.is_none())
        .unwrap();
    services
        .semantic()
        .record_llm_judgment(
            &scored.attempt_id,
            scored.response_revision,
            draft_from(scored),
            1_800_000_000_001,
        )
        .unwrap();

    // The vendor path is still structurally incapable of leaking into the
    // lexical evidence or capability channels (ADR 0021 holds through LLM).
    assert_eq!(count(&repo, "semantic_judgments"), 1);
    assert_eq!(count(&repo, "learning_observations"), 0);
    assert_eq!(count(&repo, "lexical_observations"), 0);
    assert_eq!(count(&repo, "lexical_capability_history"), 0);
    assert_eq!(count(&repo, "lexical_capability_states"), 0);
    assert_eq!(count(&repo, "upgrade_suggestions"), 0);
}

#[tokio::test]
async fn provider_failure_writes_no_judgment_honest_degradation() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    save_rubric_and_attempts(&services, &fixture);

    let attempt = &fixture.attempts[0];
    for error in [
        LlmProviderError::Offline,
        LlmProviderError::Auth,
        LlmProviderError::Truncated,
        LlmProviderError::Refusal {
            reason: "no".into(),
        },
        LlmProviderError::SchemaInvalid {
            detail: "bad".into(),
        },
    ] {
        let provider = FakeJudge { result: Err(error) };
        let outcome = services
            .semantic()
            .judge_semantic_attempt(&attempt.id, 1, &provider, 1_800_000_000_002)
            .await;
        assert!(matches!(outcome, Err(ApplicationError::Provider(_))));
    }
    // Not a single judgment row was written for any failure mode.
    assert_eq!(count(&repo, "semantic_judgments"), 0);
}

#[tokio::test]
async fn provider_success_orchestration_records_judgment() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = semantic_services(&repo);
    let fixture = gold_fixture();
    save_rubric_and_attempts(&services, &fixture);

    let scored = fixture
        .judgments
        .iter()
        .find(|judgment| judgment.abstain.is_none())
        .unwrap();
    let provider = FakeJudge {
        result: Ok(draft_from(scored)),
    };

    let recorded = services
        .semantic()
        .judge_semantic_attempt(
            &scored.attempt_id,
            scored.response_revision,
            &provider,
            1_800_000_000_003,
        )
        .await
        .unwrap();
    assert_eq!(recorded.provenance.kind, SemanticGeneratorKind::Llm);
    assert_eq!(count(&repo, "semantic_judgments"), 1);
}
