use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, Json, Path, Query, State, SubtitleSentenceId,
};

#[derive(Debug, Deserialize)]
pub(crate) struct DictionaryQuery {
    language: String,
    lemma: String,
}

pub(crate) async fn dictionary_lookup(
    State(state): State<ApiState>,
    Query(query): Query<DictionaryQuery>,
) -> Result<Json<domain::DictionaryLookupBundle>, ApiError> {
    let dictionaries = state.language.dictionaries.clone();
    let language = query.language;
    let lemma = query.lemma;
    state
        .application
        .execute_async("dictionary.lookup", move |services| async move {
            services
                .dictionary()
                .lookup_dictionary(dictionaries.as_ref(), &language, &lemma)
                .await
        })
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
        .application
        .execute("dictionary.diagnose_sentence", move |services| {
            services.media_analysis().diagnose_sentence(&sentence_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}
