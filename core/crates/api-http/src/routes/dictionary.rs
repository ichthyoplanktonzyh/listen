use crate::*;

#[derive(Debug, Deserialize)]
pub(crate) struct DictionaryQuery {
    language: String,
    lemma: String,
}

pub(crate) async fn dictionary_lookup(
    State(state): State<ApiState>,
    Query(query): Query<DictionaryQuery>,
) -> Result<Json<domain::DictionaryLookupBundle>, ApiError> {
    state
        .services
        .dictionary()
        .lookup_dictionary(state.dictionaries.as_ref(), &query.language, &query.lemma)
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn diagnose_sentence(
    State(state): State<ApiState>,
    Path(sentence_id): Path<String>,
) -> Result<Json<domain::SentenceDiagnosis>, ApiError> {
    let sentence_id = SubtitleSentenceId::parse(sentence_id).map_err(ApplicationError::from)?;
    state
        .services.media_analysis().diagnose_sentence(&sentence_id)
        .map(Json)
        .map_err(ApiError::from)
}
