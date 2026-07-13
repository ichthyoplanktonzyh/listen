use std::collections::HashMap;

use application::{
    SyntacticAnalysisRequest, SyntacticDependencyPattern, SyntacticProductQualification,
};

use crate::*;

#[derive(Debug, Default, Deserialize)]
pub(crate) struct RunSyntacticConsumersRequest {
    #[serde(default)]
    patterns: Vec<SyntacticDependencyPattern>,
}

pub(crate) async fn run_syntactic_consumers(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    request: Option<Json<RunSyntacticConsumersRequest>>,
) -> Result<Json<application::SyntacticConsumerBatch>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    let track = state
        .services
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
            state.services.phrase_candidates(&sentence.id)?,
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
