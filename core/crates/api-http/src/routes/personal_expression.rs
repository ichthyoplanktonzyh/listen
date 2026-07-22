use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use domain::{
    ConstructionId, LanguageCode, MediaId, PatternSourceKind, PatternSourceSnapshot,
    PersonalExpressionAssistance, PersonalExpressionAttempt, PersonalExpressionAttemptId,
    PersonalExpressionChannel, PersonalExpressionSelfAssessment, RecordingAssetId,
    SemanticTaskAttemptId, SemanticTaskKind, SubtitleSentenceId, SubtitleTrackId,
    UserSentencePatternAsset, UserSentencePatternId, UserSentencePatternSlot,
    UserSentencePatternVersion, UserSentencePatternVersionId,
};
use serde::Deserialize;

use crate::{ApiError, ApiState};

#[derive(Debug, Deserialize)]
pub(crate) struct PatternQuery {
    language: Option<String>,
    query: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct SourceInput {
    kind: PatternSourceKind,
    text: String,
    title: Option<String>,
    media_id: Option<String>,
    media_fingerprint: Option<String>,
    track_id: Option<String>,
    sentence_id: Option<String>,
    semantic_attempt_id: Option<String>,
    start_ms: Option<u64>,
    end_ms: Option<u64>,
    candidate_ref: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct PatternVersionInput {
    name: String,
    pattern_text: String,
    #[serde(default)]
    slots: Vec<UserSentencePatternSlot>,
    note: Option<String>,
    system_construction_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreatePatternRequest {
    language: String,
    source: SourceInput,
    #[serde(flatten)]
    version: PatternVersionInput,
}

#[derive(Debug, Deserialize)]
pub(crate) struct RecordAttemptRequest {
    pattern_version_id: String,
    channel: PersonalExpressionChannel,
    assistance: PersonalExpressionAssistance,
    response_text: String,
    raw_transcript: Option<String>,
    recording_asset_id: Option<String>,
    semantic_attempt_id: Option<String>,
    self_assessment: PersonalExpressionSelfAssessment,
    context_note: Option<String>,
}

fn optional_id<T>(
    value: Option<String>,
    parse: impl Fn(String) -> Result<T, domain::DomainError>,
) -> Result<Option<T>, ApiError> {
    value
        .map(parse)
        .transpose()
        .map_err(application::ApplicationError::from)
        .map_err(ApiError::from)
}

fn source(input: SourceInput) -> Result<PatternSourceSnapshot, ApiError> {
    Ok(PatternSourceSnapshot {
        kind: input.kind,
        text: input.text,
        title: input.title,
        media_id: optional_id(input.media_id, MediaId::parse)?,
        media_fingerprint: input.media_fingerprint,
        track_id: optional_id(input.track_id, SubtitleTrackId::parse)?,
        sentence_id: optional_id(input.sentence_id, SubtitleSentenceId::parse)?,
        semantic_attempt_id: optional_id(input.semantic_attempt_id, SemanticTaskAttemptId::parse)?,
        start_ms: input.start_ms,
        end_ms: input.end_ms,
        candidate_ref: input.candidate_ref,
    })
}

fn version(
    pattern_id: UserSentencePatternId,
    number: u32,
    input: PatternVersionInput,
    now: u64,
) -> Result<UserSentencePatternVersion, ApiError> {
    let fingerprint = format!("{}:{number}:{now}", pattern_id.as_str());
    Ok(UserSentencePatternVersion {
        id: UserSentencePatternVersionId::from_fingerprint("user-pattern-version", &fingerprint),
        pattern_id,
        version: number,
        name: input.name,
        pattern_text: input.pattern_text,
        slots: input.slots,
        note: input.note,
        system_construction_id: optional_id(input.system_construction_id, ConstructionId::parse)?,
        created_at_ms: now,
    })
}

pub(crate) async fn create_pattern(
    State(state): State<ApiState>,
    Json(request): Json<CreatePatternRequest>,
) -> Result<(StatusCode, Json<UserSentencePatternAsset>), ApiError> {
    let now = application::now_ms();
    let language =
        LanguageCode::parse(request.language).map_err(application::ApplicationError::from)?;
    let snapshot = source(request.source)?;
    let id = UserSentencePatternId::from_fingerprint(
        "user-sentence-pattern",
        &format!("{}:{now}:{}", language.as_str(), snapshot.text),
    );
    let current_version = version(id.clone(), 1, request.version, now)?;
    let asset = state
        .services
        .personal_expression()
        .create(UserSentencePatternAsset {
            id,
            language,
            source: snapshot,
            current_version,
            created_at_ms: now,
            updated_at_ms: now,
        })?;
    Ok((StatusCode::CREATED, Json(asset)))
}

pub(crate) async fn list_patterns(
    State(state): State<ApiState>,
    Query(query): Query<PatternQuery>,
) -> Result<Json<Vec<UserSentencePatternAsset>>, ApiError> {
    let language = query
        .language
        .map(LanguageCode::parse)
        .transpose()
        .map_err(application::ApplicationError::from)?;
    state
        .services
        .personal_expression()
        .list(language.as_ref(), query.query.as_deref())
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn export_patterns(
    State(state): State<ApiState>,
    Query(query): Query<PatternQuery>,
) -> Result<Json<domain::PersonalExpressionExportBundle>, ApiError> {
    let language = query
        .language
        .map(LanguageCode::parse)
        .transpose()
        .map_err(application::ApplicationError::from)?;
    state
        .services
        .personal_expression()
        .export(language.as_ref(), application::now_ms())
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn get_pattern(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<UserSentencePatternAsset>, ApiError> {
    let id = UserSentencePatternId::parse(id).map_err(application::ApplicationError::from)?;
    state
        .services
        .personal_expression()
        .get(&id)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn revise_pattern(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<PatternVersionInput>,
) -> Result<Json<UserSentencePatternAsset>, ApiError> {
    let id = UserSentencePatternId::parse(id).map_err(application::ApplicationError::from)?;
    let current = state.services.personal_expression().get(&id)?;
    let now = application::now_ms();
    let next = version(
        id.clone(),
        current.current_version.version + 1,
        request,
        now,
    )?;
    state
        .services
        .personal_expression()
        .revise(&id, next, now)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_pattern(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<StatusCode, ApiError> {
    let id = UserSentencePatternId::parse(id).map_err(application::ApplicationError::from)?;
    state.services.personal_expression().delete(&id)?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn list_pattern_versions(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<UserSentencePatternVersion>>, ApiError> {
    let id = UserSentencePatternId::parse(id).map_err(application::ApplicationError::from)?;
    state
        .services
        .personal_expression()
        .versions(&id)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn record_pattern_attempt(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<RecordAttemptRequest>,
) -> Result<(StatusCode, Json<PersonalExpressionAttempt>), ApiError> {
    let pattern_id =
        UserSentencePatternId::parse(id).map_err(application::ApplicationError::from)?;
    let now = application::now_ms();
    let attempt = PersonalExpressionAttempt {
        id: PersonalExpressionAttemptId::from_fingerprint(
            "personal-expression-attempt",
            &format!("{}:{now}:{}", pattern_id.as_str(), request.response_text),
        ),
        pattern_id,
        pattern_version_id: UserSentencePatternVersionId::parse(request.pattern_version_id)
            .map_err(application::ApplicationError::from)?,
        channel: request.channel,
        assistance: request.assistance,
        response_text: request.response_text,
        raw_transcript: request.raw_transcript,
        recording_asset_id: optional_id(request.recording_asset_id, RecordingAssetId::parse)?,
        semantic_attempt_id: optional_id(
            request.semantic_attempt_id,
            SemanticTaskAttemptId::parse,
        )?,
        self_assessment: request.self_assessment,
        context_note: request.context_note,
        completed_at_ms: now,
    };
    if attempt.channel == PersonalExpressionChannel::Speaking {
        let semantic_attempt_id = attempt.semantic_attempt_id.as_ref().ok_or_else(|| {
            application::ApplicationError::Invalid(
                "speaking use requires a semantic attempt".into(),
            )
        })?;
        let source_attempt = state
            .services
            .semantic()
            .semantic_attempt(semantic_attempt_id)?
            .ok_or(application::ApplicationError::NotFound("semantic attempt"))?;
        let source_response = source_attempt.responses.last().ok_or_else(|| {
            application::ApplicationError::Invalid(
                "linked semantic attempt has no learner response".into(),
            )
        })?;
        if source_attempt.kind != SemanticTaskKind::PatternProduction
            || source_response.transcript.trim() != attempt.response_text.trim()
            || source_response.recording_asset_id != attempt.recording_asset_id
        {
            return Err(application::ApplicationError::Invalid(
                "speaking use must summarize its linked pattern-production attempt".into(),
            )
            .into());
        }
    }
    let saved = state
        .services
        .personal_expression()
        .record_attempt(attempt)?;
    Ok((StatusCode::CREATED, Json(saved)))
}

pub(crate) async fn list_pattern_attempts(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<PersonalExpressionAttempt>>, ApiError> {
    let id = UserSentencePatternId::parse(id).map_err(application::ApplicationError::from)?;
    state
        .services
        .personal_expression()
        .attempts(&id)
        .map(Json)
        .map_err(ApiError::from)
}
