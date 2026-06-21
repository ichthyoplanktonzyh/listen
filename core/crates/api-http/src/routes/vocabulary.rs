use crate::*;

pub(crate) async fn read_progress(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<ProgressResponse>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    Ok(Json(ProgressResponse {
        position_ms: state.services.read_progress(&id)?.map(domain::TimeMs::get),
    }))
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpdateProgressRequest {
    position_ms: u64,
}

#[derive(Debug, Serialize)]
pub(crate) struct ProgressResponse {
    position_ms: Option<u64>,
}

pub(crate) async fn update_progress(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<UpdateProgressRequest>,
) -> Result<Json<ProgressResponse>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    let position = state.services.update_progress(&id, request.position_ms)?;
    Ok(Json(ProgressResponse {
        position_ms: Some(position.get()),
    }))
}

#[derive(Debug, Deserialize)]
pub(crate) struct WordQuery {
    language: String,
    lemma: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct BatchWordRequest {
    language: String,
    lemmas: Vec<String>,
}

pub(crate) async fn read_words(
    State(state): State<ApiState>,
    Json(request): Json<BatchWordRequest>,
) -> Result<Json<Vec<domain::WordProfile>>, ApiError> {
    state
        .services
        .read_word_profiles(&request.language, &request.lemmas)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn read_word(
    State(state): State<ApiState>,
    Query(query): Query<WordQuery>,
) -> Result<Json<Option<domain::WordProfile>>, ApiError> {
    state
        .services
        .read_word_profile(&query.language, &query.lemma)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpdateWordRequest {
    language: String,
    lemma: String,
    display_form: String,
    status: Option<WordStatus>,
    source: Option<SourceRequest>,
}

pub(crate) async fn update_word(
    State(state): State<ApiState>,
    Json(request): Json<UpdateWordRequest>,
) -> Result<Json<domain::WordProfile>, ApiError> {
    let profile = state
        .services
        .update_word_profile(UpdateWordProfile {
            language: request.language,
            lemma: request.lemma,
            display_form: request.display_form,
            status: request.status,
            source: request
                .source
                .map(SourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::WordProfileChanged,
        serde_json::to_value(&profile).expect("word profile serializes"),
    ));
    Ok(Json(profile))
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateObservationRequest {
    word_profile_id: String,
    sentence_id: String,
    original_form: String,
    result: Option<ObservationResult>,
    clear: Option<bool>,
    source: Option<SourceRequest>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct SourceRequest {
    language: String,
    normalized_lemma: String,
    media_id: Option<String>,
    sentence_id: Option<String>,
    original_form: String,
    sentence_text: String,
    media_title: String,
    media_fingerprint: String,
    start_ms: u64,
    end_ms: u64,
}

impl SourceRequest {
    fn into_context(self) -> Result<SourceContext, ApplicationError> {
        Ok(SourceContext {
            language: LanguageCode::parse(self.language)?,
            normalized_lemma: self.normalized_lemma,
            media_id: self.media_id.map(MediaId::parse).transpose()?,
            sentence_id: self
                .sentence_id
                .map(SubtitleSentenceId::parse)
                .transpose()?,
            original_form: self.original_form,
            sentence_text: self.sentence_text,
            media_title: self.media_title,
            media_fingerprint: self.media_fingerprint,
            start_ms: self.start_ms,
            end_ms: self.end_ms,
        })
    }
}

pub(crate) async fn create_observation(
    State(state): State<ApiState>,
    Json(request): Json<CreateObservationRequest>,
) -> Result<Response, ApiError> {
    let word_profile_id =
        WordProfileId::parse(request.word_profile_id).map_err(ApplicationError::from)?;
    let sentence_id =
        SubtitleSentenceId::parse(request.sentence_id).map_err(ApplicationError::from)?;
    if request.clear.unwrap_or(false) {
        state
            .services
            .clear_observation(&word_profile_id, &sentence_id)?;
        let _ = state.events.send(EventEnvelope::v1(
            EventName::WordObservationCleared,
            serde_json::json!({
                "word_profile_id": word_profile_id,
                "sentence_id": sentence_id,
            }),
        ));
        return Ok(StatusCode::NO_CONTENT.into_response());
    }
    let observation = state
        .services
        .create_observation(CreateWordObservation {
            word_profile_id,
            sentence_id,
            original_form: request.original_form,
            result: request
                .result
                .ok_or(ApplicationError::Validation("result"))?,
            source: request
                .source
                .map(SourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::WordObservationCreated,
        serde_json::to_value(&observation).expect("word observation serializes"),
    ));
    Ok(Json(observation).into_response())
}

#[derive(Debug, Deserialize)]
pub(crate) struct VocabularyQuery {
    language: Option<String>,
    status: WordStatus,
    search: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub(crate) async fn list_vocabulary(
    State(state): State<ApiState>,
    Query(query): Query<VocabularyQuery>,
) -> Result<Json<Vec<domain::WordDetails>>, ApiError> {
    state
        .services
        .list_vocabulary(
            query.language.as_deref().unwrap_or("en"),
            query.status,
            query.search.as_deref().unwrap_or(""),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn word_details(
    State(state): State<ApiState>,
    Path(profile_id): Path<String>,
) -> Result<Json<domain::WordDetails>, ApiError> {
    let id = WordProfileId::parse(profile_id).map_err(ApplicationError::from)?;
    state
        .services
        .word_details(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("word profile"))
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpdateLearningContentRequest {
    user_definition: Option<String>,
    personal_note: Option<String>,
}

pub(crate) async fn update_learning_content(
    State(state): State<ApiState>,
    Path(profile_id): Path<String>,
    Json(request): Json<UpdateLearningContentRequest>,
) -> Result<Json<domain::WordDetails>, ApiError> {
    state
        .services
        .update_word_learning_content(
            &WordProfileId::parse(profile_id).map_err(ApplicationError::from)?,
            request.user_definition,
            request.personal_note,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn import_external_vocabulary(
    State(state): State<ApiState>,
    Json(request): Json<domain::ExternalVocabularyImport>,
) -> Result<Json<domain::ExternalVocabularyImportSummary>, ApiError> {
    state
        .services
        .import_external_vocabulary(&request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn export_vocabulary(
    State(state): State<ApiState>,
) -> Result<Json<VocabularyAssetBundle>, ApiError> {
    state
        .services
        .export_vocabulary()
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn import_vocabulary(
    State(state): State<ApiState>,
    Json(bundle): Json<VocabularyAssetBundle>,
) -> Result<Json<serde_json::Value>, ApiError> {
    state.services.import_vocabulary(&bundle)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::VocabularyAssetsImported,
        serde_json::json!({"profiles": bundle.profiles.len()}),
    ));
    Ok(Json(serde_json::json!({"imported": true})))
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpdateAvailabilityRequest {
    availability: MediaAvailability,
}

pub(crate) async fn update_media_availability(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<UpdateAvailabilityRequest>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    let media = state
        .services
        .set_media_availability(
            &MediaId::parse(media_id).map_err(ApplicationError::from)?,
            request.availability,
        )
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::MediaAvailabilityChanged,
        serde_json::to_value(&media).expect("media serializes"),
    ));
    Ok(Json(media))
}
