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
    Json(state.language.syntax_capability.view().await)
}

pub(crate) async fn install_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.language.syntax_capability.start_install().await)
}

pub(crate) async fn update_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.language.syntax_capability.start_install().await)
}

pub(crate) async fn cancel_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.language.syntax_capability.cancel().await)
}

pub(crate) async fn validate_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.language.syntax_capability.validate().await)
}

pub(crate) async fn enable_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.language.syntax_capability.set_enabled(true).await)
}

pub(crate) async fn disable_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.language.syntax_capability.set_enabled(false).await)
}

pub(crate) async fn uninstall_syntax_capability(
    State(state): State<ApiState>,
) -> Json<SyntaxCapabilityView> {
    Json(state.language.syntax_capability.uninstall().await)
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

async fn persist_sense_groups_from_batch(
    state: &ApiState,
    track_id: SubtitleTrackId,
    batch: SyntacticConsumerBatch,
) {
    if batch.sentences.is_empty() {
        return;
    }
    let diagnostic_track_id = track_id.clone();
    if let Err(error) = state
        .application
        .execute("syntax.persist_sense_groups", move |services| {
            services
                .media_analysis()
                .persist_sense_group_analysis_from_batch(&track_id, &batch)
        })
        .await
    {
        tracing::warn!(
            track_id = diagnostic_track_id.as_str(),
            error = ?error,
            "failed to persist sense group analysis from syntax batch"
        );
    }
}

pub(crate) async fn run_syntactic_consumers(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    request: Option<Json<RunSyntacticConsumersRequest>>,
) -> Result<Json<application::SyntacticConsumerBatch>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    let (track, phrases) = state
        .application
        .execute("syntax.load_track_and_phrases", {
            let track_id = track_id.clone();
            move |services| {
                let track = services
                    .media_analysis()
                    .read_subtitle_track(&track_id)?
                    .ok_or(ApplicationError::NotFound("subtitle track"))?;
                let module = services.lexical_learning();
                let mut phrases = HashMap::new();
                for sentence in &track.sentences {
                    phrases.insert(sentence.id.clone(), module.phrase_candidates(&sentence.id)?);
                }
                Ok((track, phrases))
            }
        })
        .await?;
    let language = track
        .language
        .clone()
        .unwrap_or(LanguageCode::parse("en").map_err(ApplicationError::from)?);
    let patterns = request
        .map(|Json(value)| value.patterns)
        .unwrap_or_default();
    let batch = state
        .language
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
        .application
        .execute("syntax.load_track", {
            let track_id = track_id.clone();
            move |services| services.media_analysis().read_subtitle_track(&track_id)
        })
        .await?
        .ok_or(ApplicationError::NotFound("subtitle track"))?;
    let language = track
        .language
        .clone()
        .unwrap_or(LanguageCode::parse("en").map_err(ApplicationError::from)?);
    let capability = state.language.syntax_capability.view().await;
    let fingerprint = track_syntax_fingerprint(
        &language,
        &track.sentences,
        &capability.delivery_checksum_sha256,
    );
    if !state.language.syntax_capability.is_ready().await {
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
    let _single_flight = state.language.syntax_analysis_lock.lock().await;
    if !request.force
        && let Some(cached) = state
            .language
            .syntax_capability
            .read_track_cache::<TrackSyntaxCacheEntry>(track_id.as_str())
            .await
        && cached.fingerprint == fingerprint
    {
        persist_sense_groups_from_batch(&state, track_id.clone(), cached.batch.clone()).await;
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
    let sentence_ids = track
        .sentences
        .iter()
        .map(|sentence| sentence.id.clone())
        .collect::<Vec<_>>();
    let phrases = state
        .application
        .execute("syntax.load_phrases", move |services| {
            let module = services.lexical_learning();
            let mut phrases = HashMap::new();
            for sentence_id in sentence_ids {
                phrases.insert(sentence_id.clone(), module.phrase_candidates(&sentence_id)?);
            }
            Ok(phrases)
        })
        .await?;
    let batch = state
        .language
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
            .language
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
            .language
            .syntax_capability
            .write_track_cache(track_id.as_str(), &cached)
            .await;
    }
    persist_sense_groups_from_batch(&state, track_id.clone(), batch.clone()).await;
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
        .application
        .execute("syntax.status_track", {
            let track_id = track_id.clone();
            move |services| services.media_analysis().read_subtitle_track(&track_id)
        })
        .await?
        .ok_or(ApplicationError::NotFound("subtitle track"))?;
    let language = track
        .language
        .clone()
        .unwrap_or(LanguageCode::parse("en").map_err(ApplicationError::from)?);
    let capability = state.language.syntax_capability.view().await;
    let fingerprint = track_syntax_fingerprint(
        &language,
        &track.sentences,
        &capability.delivery_checksum_sha256,
    );
    let unavailable = !state.language.syntax_capability.is_ready().await;
    let cached = state
        .language
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
