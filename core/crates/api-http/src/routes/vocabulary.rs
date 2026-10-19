use domain::{
    CapabilityAssessment, CapabilityConclusion, CapabilityFilter, LexicalCapability,
    LexicalCapabilityProfile, LexicalEntryDetails, LexicalEntryKind, LexicalOccurrenceId,
    LexicalSenseId,
};

use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, EventEnvelope, EventName, Json,
    LearningStatus, LexicalEntryId, MediaAvailability, MediaId, Path, Query, Serialize, State,
    VocabularyAssetBundle,
};

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
    let (profile, details) = state
        .application
        .execute("vocabulary.set_capability_override", {
            let entry_id = entry_id.clone();
            move |services| {
                let module = services.lexical_learning();
                let profile =
                    module.set_lexical_capability_override(&entry_id, capability, conclusion)?;
                let details = module.lexical_details(&entry_id).ok().flatten();
                Ok((profile, details))
            }
        })
        .await?;
    let effective = profile.effective_assessment(capability);
    let _ = state.infrastructure.events.send(
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
    if let Some(details) = details {
        let _ = state.infrastructure.events.send(EventEnvelope::v1(
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
        .application
        .execute("vocabulary.capability_profile", move |services| {
            services
                .lexical_learning()
                .lexical_capability_profile(&entry_id)
        })
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("capability profile"))
}

#[derive(Debug, Deserialize)]
pub(crate) struct ObservationHistoryQuery {
    capability: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
}

/// Newest-first page size when the client does not ask for one; capped so a
/// long history cannot balloon a single response.
const OBSERVATION_HISTORY_DEFAULT_LIMIT: u32 = 50;
const OBSERVATION_HISTORY_MAX_LIMIT: u32 = 200;

pub(crate) async fn list_learning_observation_history(
    State(state): State<ApiState>,
    Path(entry_id): Path<String>,
    Query(query): Query<ObservationHistoryQuery>,
) -> Result<Json<Vec<domain::LearningObservation>>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let capability = query
        .capability
        .as_deref()
        .map(parse_capability)
        .transpose()?;
    let limit = query
        .limit
        .unwrap_or(OBSERVATION_HISTORY_DEFAULT_LIMIT)
        .min(OBSERVATION_HISTORY_MAX_LIMIT);
    let offset = query.offset.unwrap_or(0);
    let observations = state
        .application
        .execute("vocabulary.observation_history", move |services| {
            services
                .lexical_learning()
                .learning_observation_history(&entry_id, capability, limit, offset)
        })
        .await?;
    Ok(Json(observations))
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
    state
        .application
        .execute("vocabulary.create_sense_folder", {
            let entry_id = entry_id.clone();
            move |services| {
                services.lexical_learning().create_lexical_sense_folder(
                    &entry_id,
                    request.label,
                    request.definition,
                    request.gloss,
                    request.external_ref,
                )
            }
        })
        .await?;
    lexical_details_after_sense_folder_change(state, entry_id).await
}

pub(crate) async fn update_sense_folder(
    State(state): State<ApiState>,
    Path((entry_id, sense_id)): Path<(String, String)>,
    Json(request): Json<UpsertSenseFolderRequest>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let sense_id = LexicalSenseId::parse(sense_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("vocabulary.update_sense_folder", {
            let entry_id = entry_id.clone();
            move |services| {
                services.lexical_learning().update_lexical_sense_folder(
                    &entry_id,
                    &sense_id,
                    request.label,
                    request.definition,
                    request.gloss,
                    request.external_ref,
                )
            }
        })
        .await?;
    lexical_details_after_sense_folder_change(state, entry_id).await
}

pub(crate) async fn delete_sense_folder(
    State(state): State<ApiState>,
    Path((entry_id, sense_id)): Path<(String, String)>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let sense_id = LexicalSenseId::parse(sense_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("vocabulary.delete_sense_folder", {
            let entry_id = entry_id.clone();
            move |services| {
                services
                    .lexical_learning()
                    .delete_lexical_sense_folder(&entry_id, &sense_id)
            }
        })
        .await?;
    lexical_details_after_sense_folder_change(state, entry_id).await
}

pub(crate) async fn assign_sense_folder_occurrence(
    State(state): State<ApiState>,
    Path((entry_id, sense_id, occurrence_id)): Path<(String, String, String)>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let sense_id = LexicalSenseId::parse(sense_id).map_err(ApplicationError::from)?;
    let occurrence_id =
        LexicalOccurrenceId::parse(occurrence_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("vocabulary.assign_sense_occurrence", {
            let entry_id = entry_id.clone();
            move |services| {
                services
                    .lexical_learning()
                    .assign_occurrence_to_lexical_sense_folder(&entry_id, &sense_id, &occurrence_id)
            }
        })
        .await?;
    lexical_details_after_sense_folder_change(state, entry_id).await
}

pub(crate) async fn unassign_sense_folder_occurrence(
    State(state): State<ApiState>,
    Path((entry_id, sense_id, occurrence_id)): Path<(String, String, String)>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let entry_id = LexicalEntryId::parse(entry_id).map_err(ApplicationError::from)?;
    let sense_id = LexicalSenseId::parse(sense_id).map_err(ApplicationError::from)?;
    let occurrence_id =
        LexicalOccurrenceId::parse(occurrence_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("vocabulary.unassign_sense_occurrence", {
            let entry_id = entry_id.clone();
            move |services| {
                services
                    .lexical_learning()
                    .unassign_occurrence_from_lexical_sense_folder(
                        &entry_id,
                        &sense_id,
                        &occurrence_id,
                    )
            }
        })
        .await?;
    lexical_details_after_sense_folder_change(state, entry_id).await
}

async fn lexical_details_after_sense_folder_change(
    state: ApiState,
    entry_id: LexicalEntryId,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let details = state
        .application
        .execute("vocabulary.details_after_sense_change", move |services| {
            services.lexical_learning().lexical_details(&entry_id)
        })
        .await?
        .ok_or_else(|| ApiError::not_found("lexical entry"))?;
    let _ = state.infrastructure.events.send(EventEnvelope::v1(
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
    let position_ms = state
        .application
        .execute("media.read_progress", move |services| {
            services.media_analysis().read_progress(&id)
        })
        .await?
        .map(domain::TimeMs::get);
    Ok(Json(ProgressResponse { position_ms }))
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
    let position = state
        .application
        .execute("media.update_progress", move |services| {
            services
                .media_analysis()
                .update_progress(&id, request.position_ms)
        })
        .await?;
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
    let language = query.language.unwrap_or_else(|| "en".to_owned());
    let search = query.search.unwrap_or_default();
    let kind = query.kind;
    let status = query.status;
    let limit = query.limit.unwrap_or(100);
    let offset = query.offset.unwrap_or(0);
    state
        .application
        .execute("vocabulary.list", move |services| {
            services.lexical_learning().list_vocabulary(
                &language,
                kind,
                status,
                capability_filter,
                &search,
                limit,
                offset,
            )
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn import_external_vocabulary(
    State(state): State<ApiState>,
    Json(request): Json<domain::ExternalVocabularyImport>,
) -> Result<Json<domain::ExternalVocabularyImportSummary>, ApiError> {
    state
        .application
        .execute("vocabulary.import_external", move |services| {
            services
                .lexical_learning()
                .import_external_vocabulary(&request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn export_vocabulary(
    State(state): State<ApiState>,
) -> Result<Json<VocabularyAssetBundle>, ApiError> {
    state
        .application
        .execute("vocabulary.export", move |services| {
            services.lexical_learning().export_vocabulary()
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn import_vocabulary(
    State(state): State<ApiState>,
    Json(bundle): Json<VocabularyAssetBundle>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let imported = bundle.lexical_entries.len();
    state
        .application
        .execute("vocabulary.import", move |services| {
            services.lexical_learning().import_vocabulary(&bundle)
        })
        .await?;
    let _ = state.infrastructure.events.send(
        crate::event_payloads::VocabularyAssetsImportedPayload {
            lexical_entries: imported,
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
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    let media = state
        .application
        .execute("media.update_availability", move |services| {
            services
                .lexical_learning()
                .set_media_availability(&media_id, request.availability)
        })
        .await
        .map_err(ApiError::from)?;
    let _ = state.infrastructure.events.send(EventEnvelope::v1(
        EventName::MediaAvailabilityChanged,
        serde_json::to_value(&media).expect("media serializes"),
    ));
    Ok(Json(media))
}
