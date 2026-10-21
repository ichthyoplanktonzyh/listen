//! Phase 3.11 minimal semantic-task surface: exactly the write/read paths the
//! 3.13+ Studios need to start, nothing more. All resources are append-only —
//! there are intentionally no update or delete routes.

use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, Json, LanguageCode, Path, Query,
    RecordSpeakingProduction, State, StatusCode,
};
use domain::{
    AsrReliability, AssistanceLevel, AttemptResponse, JudgmentAbstain, JudgmentAdjudication,
    LexicalEntryId, PointJudgment, PointVerdict, PracticeAnchor, PracticeTarget, RubricPoint,
    RubricRevisionNote, RubricSource, SemanticAttemptStatus, SemanticGeneratorProvenance,
    SemanticJudgment, SemanticJudgmentId, SemanticRubric, SemanticRubricId, SemanticTaskAttempt,
    SemanticTaskAttemptId, SemanticTaskConditions, SemanticTaskKind, SubtitleSentenceId,
    WritingDraft, WritingFeedbackFinding, WritingFeedbackFindingId, WritingFeedbackLayer,
    WritingFeedbackProvenance, WritingFindingDecision, WritingFindingDisposition,
    WritingFindingSeverity, WritingSourceSpan, judgment_adjudication_id, semantic_judgment_id,
    semantic_rubric_id, semantic_task_attempt_id, writing_feedback_finding_id,
    writing_finding_disposition_id,
};

#[derive(Debug, Deserialize)]
pub(crate) struct CreateSemanticRubricRequest {
    pub purpose: SemanticTaskKind,
    pub source: RubricSource,
    pub response_language: LanguageCode,
    pub points: Vec<RubricPoint>,
    #[serde(default = "default_rubric_version")]
    pub version: u32,
    pub provenance: SemanticGeneratorProvenance,
    #[serde(default)]
    pub revision: Option<RubricRevisionNote>,
}

fn default_rubric_version() -> u32 {
    1
}

pub(crate) async fn create_semantic_rubric(
    State(state): State<ApiState>,
    Json(request): Json<CreateSemanticRubricRequest>,
) -> Result<Json<SemanticRubric>, ApiError> {
    let id = semantic_rubric_id(
        request.source.media_id.as_ref(),
        request.source.start_ms,
        request.source.end_ms,
        request.purpose,
        &request.source.language,
        &request.response_language,
        &request.source.transcript_snapshot,
    );
    let rubric = SemanticRubric {
        id,
        purpose: request.purpose,
        source: request.source,
        response_language: request.response_language,
        points: request.points,
        version: request.version,
        provenance: request.provenance,
        revision: request.revision,
        created_at_ms: application::now_ms(),
    };
    state
        .application
        .execute("semantic.save_rubric", move |services| {
            services.semantic().save_semantic_rubric(rubric)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct SemanticRubricQuery {
    version: Option<u32>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct SemanticRubricLookupQuery {
    media_id: Option<String>,
    start_ms: u64,
    end_ms: u64,
    purpose: SemanticTaskKind,
    response_language: String,
    source_sha256: String,
}

/// Read-side rubric lookup by source identity (Phase 3.13): the client knows
/// the segment and snapshot hash but not the server-minted fingerprint id.
pub(crate) async fn lookup_semantic_rubric(
    State(state): State<ApiState>,
    Query(query): Query<SemanticRubricLookupQuery>,
) -> Result<Json<Option<SemanticRubric>>, ApiError> {
    let media_id = query.media_id;
    let response_language = query.response_language;
    let source_sha256 = query.source_sha256;
    state
        .application
        .execute("semantic.lookup_rubric", move |services| {
            services.semantic().find_rubric_for_source(
                media_id.as_deref(),
                query.start_ms,
                query.end_ms,
                query.purpose,
                &response_language,
                &source_sha256,
            )
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn semantic_rubric(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Query(query): Query<SemanticRubricQuery>,
) -> Result<Json<SemanticRubric>, ApiError> {
    let id = SemanticRubricId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("semantic.rubric", move |services| {
            services.semantic().semantic_rubric(&id, query.version)
        })
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("semantic rubric"))
}

pub(crate) async fn semantic_rubric_attempts(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<SemanticTaskAttempt>>, ApiError> {
    let id = SemanticRubricId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("semantic.rubric_attempts", move |services| {
            services.semantic().semantic_attempts_for_rubric(&id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateSemanticAttemptRequest {
    pub kind: SemanticTaskKind,
    pub target: PracticeTarget,
    #[serde(default)]
    pub anchors: Vec<PracticeAnchor>,
    pub rubric_id: String,
    pub rubric_version: u32,
    pub conditions: SemanticTaskConditions,
    pub responses: Vec<AttemptResponse>,
    pub status: SemanticAttemptStatus,
    pub started_at_ms: u64,
    #[serde(default)]
    pub ended_at_ms: Option<u64>,
}

pub(crate) async fn create_semantic_attempt(
    State(state): State<ApiState>,
    Json(request): Json<CreateSemanticAttemptRequest>,
) -> Result<Json<SemanticTaskAttempt>, ApiError> {
    let rubric_id = SemanticRubricId::parse(request.rubric_id).map_err(ApplicationError::from)?;
    let id = semantic_task_attempt_id(
        &rubric_id,
        request.rubric_version,
        request.kind,
        request.started_at_ms,
        &request.responses,
    );
    let attempt = SemanticTaskAttempt {
        id,
        kind: request.kind,
        target: request.target,
        anchors: request.anchors,
        rubric_id,
        rubric_version: request.rubric_version,
        conditions: request.conditions,
        responses: request.responses,
        status: request.status,
        started_at_ms: request.started_at_ms,
        ended_at_ms: request.ended_at_ms,
    };
    state
        .application
        .execute("semantic.create_attempt", move |services| {
            services
                .production_corpus()
                .record_semantic_attempt_and_index(attempt)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn semantic_attempt(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<SemanticTaskAttempt>, ApiError> {
    let id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("semantic.attempt", move |services| {
            services.semantic().semantic_attempt(&id)
        })
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("semantic attempt"))
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateWritingFindingRequest {
    pub response_revision: u32,
    pub layer: WritingFeedbackLayer,
    pub severity: WritingFindingSeverity,
    #[serde(default)]
    pub source_span: Option<WritingSourceSpan>,
    pub message: String,
    #[serde(default)]
    pub suggested_replacement: Option<String>,
    pub provenance: WritingFeedbackProvenance,
}

pub(crate) async fn create_writing_finding(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<CreateWritingFindingRequest>,
) -> Result<Json<WritingFeedbackFinding>, ApiError> {
    let attempt_id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    let created_at_ms = application::now_ms();
    state
        .application
        .execute("semantic.create_writing_finding", move |services| {
            let module = services.semantic();
            let attempt = module
                .semantic_attempt(&attempt_id)?
                .ok_or(ApplicationError::NotFound("semantic attempt"))?;
            let response = attempt
                .responses
                .iter()
                .find(|response| response.revision == request.response_revision)
                .ok_or(ApplicationError::NotFound("writing response revision"))?;
            let finding = WritingFeedbackFinding {
                id: writing_feedback_finding_id(
                    &attempt_id,
                    request.response_revision,
                    &response.transcript,
                    request.layer,
                    request.source_span,
                    &request.message,
                    &request.provenance,
                ),
                attempt_id,
                response_revision: request.response_revision,
                response_transcript_sha256: domain::transcript_sha256(&response.transcript),
                layer: request.layer,
                severity: request.severity,
                source_span: request.source_span,
                message: request.message,
                suggested_replacement: request.suggested_replacement,
                provenance: request.provenance,
                created_at_ms,
            };
            module.record_writing_feedback_finding(finding)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn writing_findings(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<WritingFeedbackFinding>>, ApiError> {
    let attempt_id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("semantic.writing_findings", move |services| {
            services.semantic().writing_feedback_findings(&attempt_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct GenerateLocalWritingFindingsRequest {
    pub response_revision: u32,
}

pub(crate) async fn generate_local_writing_findings(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<GenerateLocalWritingFindingsRequest>,
) -> Result<Json<Vec<WritingFeedbackFinding>>, ApiError> {
    let attempt_id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    let now = application::now_ms();
    state
        .application
        .execute("semantic.generate_local_findings", move |services| {
            services.semantic().generate_local_writing_findings(
                &attempt_id,
                request.response_revision,
                now,
            )
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateWritingDispositionRequest {
    pub decision: WritingFindingDecision,
    #[serde(default)]
    pub resulting_attempt_id: Option<String>,
    #[serde(default)]
    pub resulting_response_revision: Option<u32>,
    #[serde(default)]
    pub note: Option<String>,
}

pub(crate) async fn create_writing_disposition(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<CreateWritingDispositionRequest>,
) -> Result<Json<WritingFindingDisposition>, ApiError> {
    let finding_id = WritingFeedbackFindingId::parse(id).map_err(ApplicationError::from)?;
    let resulting_attempt_id = request
        .resulting_attempt_id
        .map(SemanticTaskAttemptId::parse)
        .transpose()
        .map_err(ApplicationError::from)?;
    let occurred_at_ms = application::now_ms();
    let disposition = WritingFindingDisposition {
        id: writing_finding_disposition_id(
            &finding_id,
            request.decision,
            resulting_attempt_id.as_ref(),
            request.resulting_response_revision,
            occurred_at_ms,
        ),
        finding_id: finding_id.clone(),
        decision: request.decision,
        resulting_attempt_id,
        resulting_response_revision: request.resulting_response_revision,
        note: request.note,
        occurred_at_ms,
    };
    state
        .application
        .execute("semantic.create_writing_disposition", move |services| {
            let module = services.semantic();
            module
                .writing_feedback_finding(&finding_id)?
                .ok_or(ApplicationError::NotFound("writing feedback finding"))?;
            module.record_writing_finding_disposition(disposition)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn writing_dispositions(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<WritingFindingDisposition>>, ApiError> {
    let finding_id = WritingFeedbackFindingId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("semantic.writing_dispositions", move |services| {
            services
                .semantic()
                .writing_finding_dispositions(&finding_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct SaveWritingDraftRequest {
    prompt_snapshot: String,
    transcript: String,
}

pub(crate) async fn writing_draft(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Option<WritingDraft>>, ApiError> {
    let rubric_id = SemanticRubricId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("semantic.writing_draft", move |services| {
            services.semantic().writing_draft(&rubric_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn save_writing_draft(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<SaveWritingDraftRequest>,
) -> Result<Json<WritingDraft>, ApiError> {
    let rubric_id = SemanticRubricId::parse(id).map_err(ApplicationError::from)?;
    let draft = WritingDraft {
        rubric_id,
        prompt_snapshot: request.prompt_snapshot,
        transcript: request.transcript,
        updated_at_ms: application::now_ms(),
    };
    state
        .application
        .execute("semantic.save_writing_draft", move |services| {
            services.semantic().save_writing_draft(draft)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_writing_draft(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<StatusCode, ApiError> {
    let rubric_id = SemanticRubricId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("semantic.delete_writing_draft", move |services| {
            services.semantic().delete_writing_draft(&rubric_id)
        })
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
pub(crate) struct ConfirmSpeakingTargetRequest {
    lexical_entry_id: String,
    surface_form: String,
    #[serde(default)]
    sentence_id: Option<String>,
}

pub(crate) async fn confirm_speaking_target(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<ConfirmSpeakingTargetRequest>,
) -> Result<StatusCode, ApiError> {
    let attempt_id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    let lexical_entry_id =
        LexicalEntryId::parse(request.lexical_entry_id).map_err(ApplicationError::from)?;
    let sentence_id = request
        .sentence_id
        .map(SubtitleSentenceId::parse)
        .transpose()
        .map_err(ApplicationError::from)?;
    let surface = request.surface_form.trim().to_owned();
    state
        .application
        .execute("semantic.confirm_speaking_target", move |services| {
            let attempt = services
                .semantic()
                .semantic_attempt(&attempt_id)?
                .ok_or(ApplicationError::NotFound("semantic attempt"))?;
            if attempt.kind != SemanticTaskKind::L2Retelling
                || attempt.status != SemanticAttemptStatus::Completed
            {
                return Err(ApplicationError::Validation("constructed speaking attempt"));
            }
            let response = attempt
                .responses
                .first()
                .ok_or(ApplicationError::Validation("speaking response"))?;
            if response.asr_reliability == Some(AsrReliability::Unreliable) {
                return Err(ApplicationError::Validation("reliable speaking transcript"));
            }
            if surface.is_empty() || !contains_literal_target(&response.transcript, &surface) {
                return Err(ApplicationError::Validation(
                    "literal target in speaking response",
                ));
            }
            let rubric = services
                .semantic()
                .semantic_rubric(&attempt.rubric_id, Some(attempt.rubric_version))?
                .ok_or(ApplicationError::NotFound("semantic rubric"))?;
            let source_ref = format!(
                "speaking:{}:{}",
                attempt.id.as_str(),
                lexical_entry_id.as_str()
            );
            services
                .lexical_learning()
                .record_speaking_production(RecordSpeakingProduction {
                    lexical_entry_id,
                    sentence_id,
                    surface_form: surface,
                    media_id: rubric.source.media_id,
                    assistance: AssistanceLevel::None,
                    source_ref,
                    occurred_at_ms: attempt.ended_at_ms.unwrap_or(attempt.started_at_ms),
                })
        })
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

fn contains_literal_target(transcript: &str, surface: &str) -> bool {
    let transcript = transcript.to_lowercase();
    let surface = surface.to_lowercase();
    if !surface.is_ascii() {
        return transcript.contains(&surface);
    }
    transcript.match_indices(&surface).any(|(start, value)| {
        let before = transcript[..start].chars().next_back();
        let after = transcript[start + value.len()..].chars().next();
        before.is_none_or(|character| !character.is_alphanumeric())
            && after.is_none_or(|character| !character.is_alphanumeric())
    })
}

pub(crate) async fn semantic_attempt_judgments(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<SemanticJudgment>>, ApiError> {
    let id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("semantic.attempt_judgments", move |services| {
            services.semantic().semantic_judgments_for_attempt(&id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateSemanticJudgmentRequest {
    pub attempt_id: String,
    pub response_revision: u32,
    pub rubric_id: String,
    pub rubric_version: u32,
    pub rubric_source_sha256: String,
    pub response_transcript_sha256: String,
    #[serde(default)]
    pub points: Vec<PointJudgment>,
    #[serde(default)]
    pub abstain: Option<JudgmentAbstain>,
    pub provenance: SemanticGeneratorProvenance,
    #[serde(default)]
    pub raw_output: serde_json::Value,
    pub evidence_class: String,
}

pub(crate) async fn create_semantic_judgment(
    State(state): State<ApiState>,
    Json(request): Json<CreateSemanticJudgmentRequest>,
) -> Result<Json<SemanticJudgment>, ApiError> {
    let attempt_id =
        SemanticTaskAttemptId::parse(request.attempt_id).map_err(ApplicationError::from)?;
    let rubric_id = SemanticRubricId::parse(request.rubric_id).map_err(ApplicationError::from)?;
    let created_at_ms = application::now_ms();
    let id = semantic_judgment_id(
        &attempt_id,
        request.response_revision,
        request.rubric_version,
        request.provenance.kind,
        created_at_ms,
    );
    let judgment = SemanticJudgment {
        id,
        attempt_id,
        response_revision: request.response_revision,
        rubric_id,
        rubric_version: request.rubric_version,
        rubric_source_sha256: request.rubric_source_sha256,
        response_transcript_sha256: request.response_transcript_sha256,
        points: request.points,
        abstain: request.abstain,
        provenance: request.provenance,
        raw_output: request.raw_output,
        evidence_class: request.evidence_class,
        created_at_ms,
    };
    state
        .application
        .execute("semantic.record_judgment", move |services| {
            services.semantic().record_semantic_judgment(judgment)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn semantic_judgment_adjudications(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<JudgmentAdjudication>>, ApiError> {
    let id = SemanticJudgmentId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("semantic.judgment_adjudications", move |services| {
            services.semantic().judgment_adjudications(&id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateJudgmentAdjudicationRequest {
    pub judgment_id: String,
    pub point_id: String,
    pub prior_verdict: PointVerdict,
    pub user_verdict: PointVerdict,
    #[serde(default)]
    pub note: Option<String>,
}

pub(crate) async fn create_judgment_adjudication(
    State(state): State<ApiState>,
    Json(request): Json<CreateJudgmentAdjudicationRequest>,
) -> Result<Json<JudgmentAdjudication>, ApiError> {
    let judgment_id =
        SemanticJudgmentId::parse(request.judgment_id).map_err(ApplicationError::from)?;
    let occurred_at_ms = application::now_ms();
    let id = judgment_adjudication_id(
        &judgment_id,
        &request.point_id,
        request.user_verdict,
        occurred_at_ms,
    );
    let adjudication = JudgmentAdjudication {
        id,
        judgment_id,
        point_id: request.point_id,
        prior_verdict: request.prior_verdict,
        user_verdict: request.user_verdict,
        note: request.note,
        occurred_at_ms,
    };
    state
        .application
        .execute("semantic.record_adjudication", move |services| {
            services
                .semantic()
                .record_judgment_adjudication(adjudication)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}
