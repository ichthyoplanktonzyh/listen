use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, EventName, Json, Path, Query, State,
    SubtitleSentenceId, SubtitleTrackId,
};

pub(crate) async fn pronunciation_providers(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::PronunciationProviderInfo>>, ApiError> {
    let providers = state
        .application
        .execute("pronunciation.providers", move |services| {
            Ok(services.pronunciation().pronunciation_providers())
        })
        .await?;
    for provider in providers.iter().filter(|provider| !provider.available) {
        let _ = state.infrastructure.events.send(
            crate::event_payloads::PronunciationProviderDiagnosticPayload {
                provider_id: provider.id.clone(),
                provider_version: provider.version.clone(),
                diagnostic: provider.diagnostic.clone(),
            }
            .envelope(EventName::PronunciationProviderUnavailable),
        );
    }
    for provider in providers.iter().filter(|provider| provider.degraded) {
        let _ = state.infrastructure.events.send(
            crate::event_payloads::PronunciationProviderDiagnosticPayload {
                provider_id: provider.id.clone(),
                provider_version: provider.version.clone(),
                diagnostic: provider.diagnostic.clone(),
            }
            .envelope(EventName::PronunciationProviderDegraded),
        );
    }
    Ok(Json(providers))
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
    let language = query.language;
    let word = query.word;
    state
        .application
        .execute("pronunciation.lookup", move |services| {
            services
                .pronunciation()
                .lookup_pronunciation(&language, &word)
        })
        .await
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
    let (cache_state, value) = state
        .application
        .execute("pronunciation.analyze_sentence", {
            let sentence_id = sentence_id.clone();
            move |services| {
                let module = services.pronunciation();
                let cache_state = module.pronunciation_cache_state(&sentence_id)?;
                let value = module.analyze_pronunciation(&sentence_id)?;
                Ok((cache_state, value))
            }
        })
        .await?;
    if cache_state == Some(false) {
        let _ = state.infrastructure.events.send(
            crate::event_payloads::SpeechCacheInvalidatedPayload {
                job_id: None,
                track_id: None,
                kind: local_runtime::SpeechBatchKind::PronunciationAnalysis,
                sentence_id: sentence_id.as_str().to_owned(),
            }
            .envelope(),
        );
    }
    let _ = state.infrastructure.events.send(
        crate::event_payloads::PronunciationAnalysisCompletedPayload {
            job_id: None,
            track_id: None,
            sentence_id: Some(value.sentence_id.as_str().to_owned()),
            count: None,
        }
        .envelope(),
    );
    Ok(Json(value))
}

pub(crate) async fn track_pronunciation(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::SentencePronunciation>>, ApiError> {
    let parsed_track_id =
        SubtitleTrackId::parse(track_id.clone()).map_err(ApplicationError::from)?;
    let total = state
        .application
        .execute("pronunciation.track_size", {
            let parsed_track_id = parsed_track_id.clone();
            move |services| {
                services
                    .media_analysis()
                    .read_subtitle_track(&parsed_track_id)
            }
        })
        .await?
        .ok_or(ApplicationError::NotFound("subtitle track"))?
        .sentences
        .len();
    let _ = state.infrastructure.events.send(
        crate::event_payloads::SpeechBatchProgressPayload {
            job_id: None,
            track_id: track_id.clone(),
            processed: 0,
            total,
        }
        .envelope(EventName::PronunciationAnalysisProgress),
    );
    let values = state
        .application
        .execute("pronunciation.analyze_track", move |services| {
            services
                .pronunciation()
                .analyze_pronunciation_track(&parsed_track_id)
        })
        .await?;
    let _ = state.infrastructure.events.send(
        crate::event_payloads::SpeechBatchProgressPayload {
            job_id: None,
            track_id: track_id.clone(),
            processed: total,
            total,
        }
        .envelope(EventName::PronunciationAnalysisProgress),
    );
    let _ = state.infrastructure.events.send(
        crate::event_payloads::PronunciationAnalysisCompletedPayload {
            job_id: None,
            track_id: Some(track_id),
            sentence_id: None,
            count: Some(values.len()),
        }
        .envelope(),
    );
    Ok(Json(values))
}

pub(crate) async fn generate_track_pronunciation(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::SentencePronunciation>>, ApiError> {
    track_pronunciation(State(state), Path(track_id)).await
}
