use super::*;

fn observation(
    entry: &LexicalEntryId,
    capability: LexicalCapability,
    outcome: ObservationOutcome,
    source_ref: &str,
    at: u64,
) -> LearningObservation {
    LearningObservation {
        id: LearningObservationId::parse(format!("projection-observation-{at}")).unwrap(),
        lexical_entry_id: entry.clone(),
        sense_id: None,
        capability,
        task_type: ObservationTaskType::ReviewRecall,
        outcome,
        assistance: AssistanceLevel::None,
        surface_form: Some("make it work".into()),
        sentence_id: None,
        media_id: Some(MediaId::parse(format!("media-{at}")).unwrap()),
        origin: ObservationOrigin::ReviewTask,
        source_ref: Some(source_ref.into()),
        occurred_at_ms: at,
    }
}

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
}

#[test]
fn proposal_confirmation_is_the_only_evidence_projection_writer_and_preserves_override() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let entry = upsert_word_asset(&services, "en", "work", "work", None, None).entry;
    for at in [10, 20] {
        repo.append_learning_observation(&observation(
            &entry.id,
            LexicalCapability::Listening,
            ObservationOutcome::Failure,
            &format!("listening-attempt-{at}"),
            at,
        ))
        .unwrap();
    }
    let audit = services
        .projection_review()
        .audit_and_refresh(&entry.id)
        .unwrap();
    assert_eq!(audit.reports.len(), 1);
    assert_eq!(audit.reports[0].capability, LexicalCapability::Listening);
    let proposal = audit.proposals.first().unwrap();
    assert_eq!(proposal.capability, LexicalCapability::Listening);
    assert_eq!(
        proposal.proposed_conclusion,
        CapabilityConclusion::NotAcquired
    );
    assert_eq!(
        repo.lexical_capability_profile(&entry.id, None)
            .unwrap()
            .unwrap()
            .listening
            .effective_assessment(),
        CapabilityAssessment::Unassessed,
        "a proposal alone must not mutate the projection"
    );

    repo.set_lexical_capability_override(
        &entry.id,
        None,
        LexicalCapability::Listening,
        Some(CapabilityOverride {
            conclusion: CapabilityConclusion::Acquired,
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
        after.listening.projection.as_ref().unwrap().conclusion,
        CapabilityConclusion::NotAcquired
    );
    assert_eq!(
        after.listening.effective_assessment(),
        CapabilityAssessment::Acquired,
        "the learner's override remains authoritative"
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
fn reading_observations_do_not_create_listening_proposals() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let entry = upsert_word_asset(&services, "en", "work", "work", None, None).entry;
    for at in [10, 20] {
        repo.append_learning_observation(&observation(
            &entry.id,
            LexicalCapability::Reading,
            ObservationOutcome::Success,
            &format!("reading-attempt-{at}"),
            at,
        ))
        .unwrap();
    }

    let audit = services
        .projection_review()
        .audit_and_refresh(&entry.id)
        .unwrap();
    assert!(audit.proposals.is_empty());
    assert_eq!(audit.reports.len(), 1);
    assert_eq!(audit.reports[0].capability, LexicalCapability::Listening);
    assert_eq!(
        audit.reports[0].qualification,
        ProjectionQualification::InsufficientEvidence
    );
}

#[test]
fn superseded_projection_is_consistent_by_id_and_cannot_be_confirmed() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let entry = upsert_word_asset(&services, "en", "work", "work", None, None).entry;
    let older = ProjectionProposal {
        id: ProjectionProposalId::parse("projection-older").unwrap(),
        lexical_entry_id: entry.id.clone(),
        capability: LexicalCapability::Listening,
        proposed_conclusion: CapabilityConclusion::NotAcquired,
        algorithm_version: "listening-proposal-v1".into(),
        confidence: Some(0.85),
        evidence_as_of_ms: 10,
        evidence: vec![],
        rationale: "older evidence snapshot".into(),
        status: ProjectionProposalStatus::Pending,
        created_at_ms: 10,
    };
    let newer = ProjectionProposal {
        id: ProjectionProposalId::parse("projection-newer").unwrap(),
        evidence_as_of_ms: 20,
        created_at_ms: 20,
        rationale: "newer evidence snapshot".into(),
        ..older.clone()
    };
    repo.save_projection_proposal(&older).unwrap();
    repo.save_projection_proposal(&newer).unwrap();

    assert_eq!(
        repo.projection_proposal(&older.id).unwrap().unwrap().status,
        ProjectionProposalStatus::Superseded,
        "list and by-ID reads must report the same proposal lifecycle"
    );
    assert_eq!(
        repo.list_projection_proposals(&entry.id, Some(LexicalCapability::Listening))
            .unwrap()
            .iter()
            .find(|proposal| proposal.id == older.id)
            .unwrap()
            .status,
        ProjectionProposalStatus::Superseded
    );

    let decision = ProjectionDecision {
        id: ProjectionDecisionId::parse("decision-stale").unwrap(),
        proposal_id: older.id.clone(),
        decision: ProjectionDecisionKind::Confirm,
        note: None,
        decided_at_ms: 30,
    };
    let result =
        repo.resolve_projection_proposal(&decision, &older, Some(older.confirmed_projection(30)));
    assert!(matches!(
        result,
        Err(ApplicationError::Conflict(
            "projection proposal is already resolved or superseded"
        ))
    ));
    assert_eq!(
        repo.lexical_capability_profile(&entry.id, None)
            .unwrap()
            .unwrap()
            .listening
            .effective_assessment(),
        CapabilityAssessment::Unassessed,
        "a stale decision must not write the projection"
    );
}
