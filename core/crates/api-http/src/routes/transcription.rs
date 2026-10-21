use crate::{ApiError, ApiState, Deserialize, Json, Query, State};

#[derive(Debug, Deserialize)]
pub(crate) struct PronunciationRulesQuery {
    #[serde(default = "default_language")]
    language: String,
}

fn default_language() -> String {
    "en".into()
}

pub(crate) async fn pronunciation_rules(
    State(state): State<ApiState>,
    Query(query): Query<PronunciationRulesQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    state
        .application
        .execute("pronunciation.rules", move |services| {
            Ok(services
                .pronunciation()
                .pronunciation_rules(&query.language))
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct ModelIdRequest {
    pub(crate) model_id: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct RegisterCustomModelRequest {
    pub(crate) path: String,
}
