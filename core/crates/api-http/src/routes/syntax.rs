use std::collections::HashMap;

use application::{
    SyntacticAnalysisRequest, SyntacticConsumerBatch, SyntacticDependencyPattern,
    SyntacticProductQualification,
};
use serde::Serialize;
use sha2::{Digest, Sha256};

use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, Json, LanguageCode, Path, State,
    SubtitleTrackId, SyntaxCapabilityView,
};

pub(crate) async fn syntax_capability(State(state): State<ApiState>) -> Json<SyntaxCapabilityView> {
    Json(state.syntax_capability.view().await)
}

pub(crate) async fn install_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.syntax_capability.start_install().await)
}

pub(crate) async fn update_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.syntax_capability.start_install().await)
}

pub(crate) async fn cancel_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.syntax_capability.cancel().await)
}

pub(crate) async fn validate_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.syntax_capability.validate().await)
}

pub(crate) async fn enable_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.syntax_capability.set_enabled(true).await)
}

pub(crate) async fn disable_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.syntax_capability.set_enabled(false).await)
}

pub(crate) async fn uninstall_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.syntax_capability.uninstall().await)
}

#[derive(Debug, Default, Deserialize)]
pub(crate) struct RunSyntacticConsumersRequest {
    #[serde(default)]
    patterns: Vec<SyntacticDependencyPattern>,
}

#[derive(Debug, Default, Deserialize)]
pub(crate) struct RunTrackSyntaxRequest {
    #[serde(default)]
    force: bool,
    #[serde(default)]
    patterns: Vec<SyntacticDependencyPattern>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum TrackSyntaxStatus {
    Unavailable,
    Analyzing,
    Ready,
    Partial,
    Failed,
    Stale,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct TrackSyntaxAnalysisView {
    status: TrackSyntaxStatus,
    fingerprint: String,
    cache_hit: bool,
    sentence_count: usize,
    analyzed_sentence_count: usize,
    fallback_sentence_count: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    batch: Option<SyntacticConsumerBatch>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TrackSyntaxCacheEntry {
    fingerprint: String,
    status: TrackSyntaxStatus,
    sentence_count: usize,
    analyzed_sentence_count: usize,
    fallback_sentence_count: usize,
    batch: SyntacticConsumerBatch,
}

pub(crate) async fn run_syntactic_consumers(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    request: Option<Json<RunSyntacticConsumersRequest>>,
) -> Result<Json<application::SyntacticConsumerBatch>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    let track = state
        .services
        .media_analysis()
        .read_subtitle_track(&track_id)?
        .ok_or(ApplicationError::NotFound("subtitle track"))?;
    let language = track
        .language
        .clone()
        .unwrap_or(LanguageCode::parse("en").map_err(ApplicationError::from)?);
    let mut phrases = HashMap::new();
    for sentence in &track.sentences {
        phrases.insert(
            sentence.id.clone(),
            state
                .services
                .lexical_learning()
                .phrase_candidates(&sentence.id)?,
        );
    }
    let patterns = request
        .map(|Json(value)| value.patterns)
        .unwrap_or_default();
    let batch = state
        .syntactic_consumers
        .consume(
            SyntacticAnalysisRequest {
                language,
                sentences: track.sentences,
                profile_fingerprint: "syntax-product-corrected-v2".into(),
            },
            &phrases,
            &patterns,
        )
        .await;
    debug_assert_eq!(
        batch.qualification,
        SyntacticProductQualification::corrected_v2()
    );
    Ok(Json(batch))
}

pub(crate) async fn run_track_syntax_analysis(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    request: Option<Json<RunTrackSyntaxRequest>>,
) -> Result<Json<TrackSyntaxAnalysisView>, ApiError> {
    let request = request.map(|Json(value)| value).unwrap_or_default();
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    let track = state
        .services
        .media_analysis()
        .read_subtitle_track(&track_id)?
        .ok_or(ApplicationError::NotFound("subtitle track"))?;
    let language = track
        .language
        .clone()
        .unwrap_or(LanguageCode::parse("en").map_err(ApplicationError::from)?);
    let capability = state.syntax_capability.view().await;
    let fingerprint = track_syntax_fingerprint(
        &language,
        &track.sentences,
        &capability.delivery_checksum_sha256,
    );
    if !state.syntax_capability.is_ready().await {
        return Ok(Json(TrackSyntaxAnalysisView {
            status: TrackSyntaxStatus::Unavailable,
            fingerprint,
            cache_hit: false,
            sentence_count: track.sentences.len(),
            analyzed_sentence_count: 0,
            fallback_sentence_count: track.sentences.len(),
            batch: None,
        }));
    }
    let _single_flight = state.syntax_analysis_lock.lock().await;
    if !request.force
        && let Some(cached) = state
            .syntax_capability
            .read_track_cache::<TrackSyntaxCacheEntry>(track_id.as_str())
            .await
        && cached.fingerprint == fingerprint
    {
        return Ok(Json(TrackSyntaxAnalysisView {
            status: cached.status,
            fingerprint: cached.fingerprint,
            cache_hit: true,
            sentence_count: cached.sentence_count,
            analyzed_sentence_count: cached.analyzed_sentence_count,
            fallback_sentence_count: cached.fallback_sentence_count,
            batch: Some(cached.batch),
        }));
    }
    let mut phrases = HashMap::new();
    for sentence in &track.sentences {
        phrases.insert(
            sentence.id.clone(),
            state
                .services
                .lexical_learning()
                .phrase_candidates(&sentence.id)?,
        );
    }
    let batch = state
        .syntactic_consumers
        .consume(
            SyntacticAnalysisRequest {
                language,
                sentences: track.sentences,
                profile_fingerprint: "syntax-product-corrected-v2".into(),
            },
            &phrases,
            &request.patterns,
        )
        .await;
    let sentence_count = batch.sentences.len();
    let analyzed_sentence_count = batch
        .sentences
        .iter()
        .filter(|sentence| sentence.analysis.is_some())
        .count();
    let fallback_sentence_count = sentence_count.saturating_sub(analyzed_sentence_count);
    let status = if analyzed_sentence_count == sentence_count {
        TrackSyntaxStatus::Ready
    } else if analyzed_sentence_count > 0 {
        TrackSyntaxStatus::Partial
    } else {
        TrackSyntaxStatus::Failed
    };
    if analyzed_sentence_count == 0
        && let Some(reason) = batch
            .sentences
            .first()
            .and_then(|sentence| sentence.fallback_reason.as_ref())
        && matches!(
            reason,
            application::SyntacticFallbackReason::RuntimeMissing
                | application::SyntacticFallbackReason::ModelMissing
                | application::SyntacticFallbackReason::ModelCorrupt
                | application::SyntacticFallbackReason::ProcessFailure
                | application::SyntacticFallbackReason::ProtocolFailure
        )
    {
        state
            .syntax_capability
            .mark_partial(format!("syntax runtime unavailable: {reason:?}"))
            .await;
    }
    let cached = TrackSyntaxCacheEntry {
        fingerprint: fingerprint.clone(),
        status: status.clone(),
        sentence_count,
        analyzed_sentence_count,
        fallback_sentence_count,
        batch: batch.clone(),
    };
    if analyzed_sentence_count > 0 {
        state
            .syntax_capability
            .write_track_cache(track_id.as_str(), &cached)
            .await;
    }
    Ok(Json(TrackSyntaxAnalysisView {
        status,
        fingerprint,
        cache_hit: false,
        sentence_count,
        analyzed_sentence_count,
        fallback_sentence_count,
        batch: Some(batch),
    }))
}

pub(crate) async fn track_syntax_analysis_status(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<TrackSyntaxAnalysisView>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    let track = state
        .services
        .media_analysis()
        .read_subtitle_track(&track_id)?
        .ok_or(ApplicationError::NotFound("subtitle track"))?;
    let language = track
        .language
        .clone()
        .unwrap_or(LanguageCode::parse("en").map_err(ApplicationError::from)?);
    let capability = state.syntax_capability.view().await;
    let fingerprint = track_syntax_fingerprint(
        &language,
        &track.sentences,
        &capability.delivery_checksum_sha256,
    );
    let unavailable = !state.syntax_capability.is_ready().await;
    let cached = state
        .syntax_capability
        .read_track_cache::<TrackSyntaxCacheEntry>(track_id.as_str())
        .await;
    if !unavailable
        && let Some(cached) = cached
        && cached.fingerprint == fingerprint
    {
        return Ok(Json(TrackSyntaxAnalysisView {
            status: cached.status,
            fingerprint,
            cache_hit: true,
            sentence_count: cached.sentence_count,
            analyzed_sentence_count: cached.analyzed_sentence_count,
            fallback_sentence_count: cached.fallback_sentence_count,
            batch: None,
        }));
    }
    Ok(Json(TrackSyntaxAnalysisView {
        status: if unavailable {
            TrackSyntaxStatus::Unavailable
        } else {
            TrackSyntaxStatus::Stale
        },
        fingerprint,
        cache_hit: false,
        sentence_count: track.sentences.len(),
        analyzed_sentence_count: 0,
        fallback_sentence_count: track.sentences.len(),
        batch: None,
    }))
}

fn track_syntax_fingerprint(
    language: &LanguageCode,
    sentences: &[domain::SubtitleSentence],
    model_checksum: &str,
) -> String {
    let mut digest = Sha256::new();
    digest.update(b"syntax-track-cache-v1\0");
    digest.update(language.as_str().as_bytes());
    digest.update(b"\0syntax-product-corrected-v2\0");
    digest.update(model_checksum.as_bytes());
    digest.update(b"\0");
    digest.update(serde_json::to_vec(sentences).unwrap_or_default());
    hex::encode(digest.finalize())
}
