use crate::*;

pub(crate) async fn pronunciation_providers(
    State(state): State<ApiState>,
) -> Json<Vec<domain::PronunciationProviderInfo>> {
    let providers = state.services.pronunciation_providers();
    for provider in providers.iter().filter(|provider| !provider.available) {
        let _ = state.events.send(EventEnvelope::v1(
            EventName::PronunciationProviderUnavailable,
            serde_json::json!({
                "provider_id": provider.id,
                "provider_version": provider.version,
                "diagnostic": provider.diagnostic,
            }),
        ));
    }
    for provider in providers.iter().filter(|provider| provider.degraded) {
        let _ = state.events.send(EventEnvelope::v1(
            EventName::PronunciationProviderDegraded,
            serde_json::json!({
                "provider_id": provider.id,
                "provider_version": provider.version,
                "diagnostic": provider.diagnostic,
            }),
        ));
    }
    Json(providers)
}

#[derive(Debug, Deserialize)]
pub(crate) struct PronunciationLookupQuery {
    word: String,
    #[serde(default = "default_en")]
    language: String,
}

fn default_en() -> String {
    "en".into()
}

pub(crate) async fn pronunciation_lookup(
    State(state): State<ApiState>,
    Query(query): Query<PronunciationLookupQuery>,
) -> Result<Json<domain::WordPronunciation>, ApiError> {
    state
        .services
        .lookup_pronunciation(&query.language, &query.word)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct SentenceIdRequest {
    sentence_id: String,
}

pub(crate) async fn analyze_pronunciation_sentence(
    State(state): State<ApiState>,
    Json(request): Json<SentenceIdRequest>,
) -> Result<Json<domain::SentencePronunciation>, ApiError> {
    let sentence_id =
        SubtitleSentenceId::parse(request.sentence_id).map_err(ApplicationError::from)?;
    if state.services.pronunciation_cache_state(&sentence_id)? == Some(false) {
        let _ = state.events.send(
            crate::event_payloads::SpeechCacheInvalidatedPayload {
                job_id: None,
                track_id: None,
                kind: crate::speech_jobs::SpeechBatchKind::PronunciationAnalysis,
                sentence_id: sentence_id.as_str().to_owned(),
            }
            .envelope(),
        );
    }
    let value = state.services.analyze_pronunciation(&sentence_id)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PronunciationAnalysisCompleted,
        serde_json::json!({"sentence_id": value.sentence_id}),
    ));
    Ok(Json(value))
}

pub(crate) async fn track_pronunciation(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::SentencePronunciation>>, ApiError> {
    let parsed_track_id =
        SubtitleTrackId::parse(track_id.clone()).map_err(ApplicationError::from)?;
    let total = state
        .services
        .read_subtitle_track(&parsed_track_id)?
        .ok_or(ApplicationError::NotFound("subtitle track"))?
        .sentences
        .len();
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PronunciationAnalysisProgress,
        serde_json::json!({"track_id": track_id, "processed": 0, "total": total}),
    ));
    let values = state
        .services
        .analyze_pronunciation_track(&parsed_track_id)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PronunciationAnalysisProgress,
        serde_json::json!({"track_id": track_id, "processed": total, "total": total}),
    ));
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PronunciationAnalysisCompleted,
        serde_json::json!({"track_id": track_id, "count": values.len()}),
    ));
    Ok(Json(values))
}

pub(crate) async fn generate_track_pronunciation(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::SentencePronunciation>>, ApiError> {
    track_pronunciation(State(state), Path(track_id)).await
}
