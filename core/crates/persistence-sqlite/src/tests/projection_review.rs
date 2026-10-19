use super::*;

fn observation(
    entry: &LexicalEntryId,
    capability: LexicalCapability,
    task_type: ObservationTaskType,
    at: u64,
) -> LearningObservation {
    LearningObservation {
        id: LearningObservationId::parse(format!("projection-observation-{at}")).unwrap(),
        lexical_entry_id: entry.clone(),
        sense_id: None,
        capability,
        task_type,
        outcome: ObservationOutcome::Success,
        assistance: AssistanceLevel::None,
        surface_form: Some("make it work".into()),
        sentence_id: None,
        media_id: None,
        origin: ObservationOrigin::UserMarking,
        source_ref: Some(format!("immutable-attempt-{at}")),
        occurred_at_ms: at,
    }
}

#[test]
fn proposal_confirmation_is_the_only_evidence_projection_writer_and_preserves_override() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    );
    let entry = upsert_word_asset(&services, "en", "work", "work", None, None).entry;
    for at in [10, 20] {
        repo.append_learning_observation(&observation(
            &entry.id,
            LexicalCapability::Speaking,
            ObservationTaskType::SpeakingProduction,
            at,
        ))
        .unwrap();
    }
    let audit = services
        .projection_review()
        .audit_and_refresh(&entry.id)
        .unwrap();
    let proposal = audit
        .proposals
        .iter()
        .find(|value| value.capability == LexicalCapability::Speaking)
        .unwrap();
    let before = repo
        .lexical_capability_profile(&entry.id, None)
        .unwrap()
        .unwrap();
    assert_eq!(
        before.speaking.effective_assessment(),
        CapabilityAssessment::Unassessed
    );

    repo.set_lexical_capability_override(
        &entry.id,
        None,
        LexicalCapability::Speaking,
        Some(CapabilityOverride {
            conclusion: CapabilityConclusion::NotAcquired,
            source: CapabilityOverrideSource::UserSelection,
            updated_at_ms: 25,
        }),
        25,
    )
    .unwrap();
    services
        .projection_review()
        .decide(
            &proposal.id,
            ProjectionDecisionKind::Confirm,
            Some("learner confirmed".into()),
        )
        .unwrap();

    let after = repo
        .lexical_capability_profile(&entry.id, None)
        .unwrap()
        .unwrap();
    assert_eq!(
        after.speaking.projection.as_ref().unwrap().conclusion,
        CapabilityConclusion::Acquired
    );
    assert_eq!(
        after.speaking.effective_assessment(),
        CapabilityAssessment::NotAcquired,
        "override remains the effective authority"
    );
    assert_eq!(
        repo.list_learning_observations(&entry.id, None, 20, 0)
            .unwrap()
            .len(),
        2,
        "confirmation never rewrites evidence"
    );
    assert!(
        !repo
            .lexical_capability_history(&entry.id, None)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn rebuild_is_idempotent_and_writing_remains_unassessed() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    );
    let entry = upsert_word_asset(&services, "en", "write", "write", None, None).entry;
    let first = services
        .projection_review()
        .audit_and_refresh(&entry.id)
        .unwrap();
    let second = services
        .projection_review()
        .audit_and_refresh(&entry.id)
        .unwrap();
    assert!(first.proposals.is_empty() && second.proposals.is_empty());
    let writing = second
        .reports
        .iter()
        .find(|value| value.capability == LexicalCapability::Writing)
        .unwrap();
    assert_eq!(
        writing.qualification,
        ProjectionQualification::InsufficientEvidence
    );
    assert_eq!(
        repo.lexical_capability_profile(&entry.id, None)
            .unwrap()
            .unwrap()
            .writing
            .effective_assessment(),
        CapabilityAssessment::Unassessed,
    );
}

#[test]
fn algorithm_upgrade_appends_and_supersedes_without_rewriting_old_proposal() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    );
    let entry = upsert_word_asset(&services, "en", "read", "read", None, None).entry;
    let make = |version: &str, created_at_ms| ProjectionProposal {
        id: ProjectionProposalId::from_fingerprint(
            "projection-proposal-test",
            &format!("{version}:{created_at_ms}"),
        ),
        lexical_entry_id: entry.id.clone(),
        capability: LexicalCapability::Reading,
        proposed_conclusion: CapabilityConclusion::Acquired,
        algorithm_version: version.into(),
        confidence: Some(0.8),
        evidence_as_of_ms: 10,
        evidence: vec![ProjectionEvidenceRef {
            observation_id: "observation-immutable".into(),
            source_ref: Some("attempt-immutable".into()),
            task_type: ObservationTaskType::ReadingContextMarking,
            outcome: ObservationOutcome::Success,
            occurred_at_ms: 10,
            snapshot: "read".into(),
        }],
        rationale: "test".into(),
        status: ProjectionProposalStatus::Pending,
        created_at_ms,
    };
    let old = repo
        .save_projection_proposal(&make("reading-proposal-v1", 20))
        .unwrap();
    repo.save_projection_proposal(&make("reading-proposal-v2", 30))
        .unwrap();
    let proposals = repo
        .list_projection_proposals(&entry.id, Some(LexicalCapability::Reading))
        .unwrap();
    assert_eq!(proposals.len(), 2);
    assert_eq!(
        proposals
            .iter()
            .find(|value| value.id == old.id)
            .unwrap()
            .status,
        ProjectionProposalStatus::Superseded
    );
    assert_eq!(
        proposals
            .iter()
            .find(|value| value.id == old.id)
            .unwrap()
            .algorithm_version,
        "reading-proposal-v1"
    );
}
