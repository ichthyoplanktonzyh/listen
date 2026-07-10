use domain::{
    CapabilityAssessment, CapabilityConclusion, CapabilityFilter, LexicalCapability,
    LexicalCapabilityProfile, LexicalEntryKind, LexicalEntryDetails, LexicalOccurrenceId,
    LexicalSenseId,
};

use crate::*;

#[derive(Debug, Deserialize)]
pub(crate) struct SetCapabilityOverrideRequest {
    conclusion: Option<String>,
}

pub(crate) async fn set_capability_override(
    State(state): State<ApiState>,
    Path((entry_id, capability_str)): Path<(String, String)>,
    Json(request): Json<SetCapabilityOverrideRequest>,
) -> Result<Json<LexicalCapabilityProfile>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let capability = parse_capability(&capability_str)?;
    let conclusion = request
        .conclusion
        .as_deref()
        .map(parse_conclusion)
        .transpose()?;
    let profile = state
        .services
        .set_lexical_capability_override(&entry_id, capability, conclusion)?;
    let effective = profile.effective_assessment(capability);
    let _ = state.events.send(
        crate::event_payloads::LexicalCapabilityChangedPayload {
            lexical_entry_id: entry_id.as_str().to_owned(),
            capability: capability_str,
            effective_assessment: serde_json::to_value(effective)
                .unwrap()
                .as_str()
                .unwrap()
                .to_owned(),
        }
        .envelope(),
    );
    if let Ok(Some(details)) = state.services.lexical_details(&entry_id) {
        let _ = state.events.send(EventEnvelope::v1(
            EventName::LexicalEntryChanged,
            serde_json::to_value(&details).expect("lexical details serializes"),
        ));
    }
    Ok(Json(profile))
}

pub(crate) async fn get_capability_profile(
    State(state): State<ApiState>,
    Path(entry_id): Path<String>,
) -> Result<Json<LexicalCapabilityProfile>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    state
        .services
        .lexical_capability_profile(&entry_id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("capability profile"))
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpsertSenseFolderRequest {
    label: String,
    definition: Option<String>,
    gloss: Option<String>,
    external_ref: Option<String>,
}

pub(crate) async fn create_sense_folder(
    State(state): State<ApiState>,
    Path(entry_id): Path<String>,
    Json(request): Json<UpsertSenseFolderRequest>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    state.services.create_lexical_sense_folder(
        &entry_id,
        request.label,
        request.definition,
        request.gloss,
        request.external_ref,
    )?;
    lexical_details_after_sense_folder_change(&state, &entry_id)
}

pub(crate) async fn update_sense_folder(
    State(state): State<ApiState>,
    Path((entry_id, sense_id)): Path<(String, String)>,
    Json(request): Json<UpsertSenseFolderRequest>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let sense_id = LexicalSenseId::parse(sense_id).map_err(ApplicationError::from)?;
    state.services.update_lexical_sense_folder(
        &entry_id,
        &sense_id,
        request.label,
        request.definition,
        request.gloss,
        request.external_ref,
    )?;
    lexical_details_after_sense_folder_change(&state, &entry_id)
}

pub(crate) async fn delete_sense_folder(
    State(state): State<ApiState>,
    Path((entry_id, sense_id)): Path<(String, String)>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let sense_id = LexicalSenseId::parse(sense_id).map_err(ApplicationError::from)?;
    state.services.delete_lexical_sense_folder(&entry_id, &sense_id)?;
    lexical_details_after_sense_folder_change(&state, &entry_id)
}

pub(crate) async fn assign_sense_folder_occurrence(
    State(state): State<ApiState>,
    Path((entry_id, sense_id, occurrence_id)): Path<(String, String, String)>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let sense_id = LexicalSenseId::parse(sense_id).map_err(ApplicationError::from)?;
    let occurrence_id = LexicalOccurrenceId::parse(occurrence_id).map_err(ApplicationError::from)?;
    state.services.assign_occurrence_to_lexical_sense_folder(
        &entry_id,
        &sense_id,
        &occurrence_id,
    )?;
    lexical_details_after_sense_folder_change(&state, &entry_id)
}

pub(crate) async fn unassign_sense_folder_occurrence(
    State(state): State<ApiState>,
    Path((entry_id, sense_id, occurrence_id)): Path<(String, String, String)>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let sense_id = LexicalSenseId::parse(sense_id).map_err(ApplicationError::from)?;
    let occurrence_id = LexicalOccurrenceId::parse(occurrence_id).map_err(ApplicationError::from)?;
    state.services.unassign_occurrence_from_lexical_sense_folder(
        &entry_id,
        &sense_id,
        &occurrence_id,
    )?;
    lexical_details_after_sense_folder_change(&state, &entry_id)
}

fn lexical_details_after_sense_folder_change(
    state: &ApiState,
    entry_id: &LexicalEntryId,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let details = state
        .services
        .lexical_details(entry_id)?
        .ok_or_else(|| ApiError::not_found("lexical entry"))?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::LexicalEntryChanged,
        serde_json::to_value(&details).expect("lexical details serializes"),
    ));
    Ok(Json(details))
}

fn parse_capability(value: &str) -> Result<LexicalCapability, ApiError> {
    match value {
        "reading" => Ok(LexicalCapability::Reading),
        "listening" => Ok(LexicalCapability::Listening),
        "speaking" => Ok(LexicalCapability::Speaking),
        "writing" => Ok(LexicalCapability::Writing),
        _ => Err(ApplicationError::Validation("capability").into()),
    }
}

fn parse_conclusion(value: &str) -> Result<CapabilityConclusion, ApiError> {
    match value {
        "not_acquired" => Ok(CapabilityConclusion::NotAcquired),
        "acquired" => Ok(CapabilityConclusion::Acquired),
        _ => Err(ApplicationError::Validation("conclusion").into()),
    }
}

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
pub(crate) struct VocabularyQuery {
    language: Option<String>,
    /// None returns both words and phrases.
    kind: Option<LexicalEntryKind>,
    /// Legacy status axis; optional so the capability axis can be primary.
    status: Option<LearningStatus>,
    /// Capability-dimension filter; `capability` and `assessment` must both be
    /// present to take effect (otherwise ignored).
    capability: Option<LexicalCapability>,
    assessment: Option<CapabilityAssessment>,
    search: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub(crate) async fn list_vocabulary(
    State(state): State<ApiState>,
    Query(query): Query<VocabularyQuery>,
) -> Result<Json<Vec<domain::LexicalEntryDetails>>, ApiError> {
    let capability_filter = match (query.capability, query.assessment) {
        (Some(capability), Some(assessment)) => Some(CapabilityFilter {
            capability,
            assessment,
        }),
        _ => None,
    };
    state
        .services
        .list_vocabulary(
            query.language.as_deref().unwrap_or("en"),
            query.kind,
            query.status,
            capability_filter,
            query.search.as_deref().unwrap_or(""),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
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
    let _ = state.events.send(
        crate::event_payloads::VocabularyAssetsImportedPayload {
            lexical_entries: bundle.lexical_entries.len(),
        }
        .envelope(),
    );
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
