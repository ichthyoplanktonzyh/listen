use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use api_events::{EventEnvelope, EventName};
use application::{
    ApplicationError, CreateLexicalObservation, LexicalSourceContext, UpsertLexicalEntry,
};
use async_trait::async_trait;
use axum::Json;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use domain::{
    LearningResourceDescriptor, LearningResourceId, LearningResourceState, LearningStatus,
    LexicalEntry, LexicalEntryDetails, LexicalEntryId, LexicalEntryKind, ObservationResult,
    PhraseCandidate, SubtitleSearchResult, SubtitleSentenceId,
};
use reqwest::Client;
use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::{ApiError, ApiState};

#[derive(Clone)]
pub struct M18Coordinator {
    client: Client,
    resources: Arc<Mutex<Vec<LearningResourceDescriptor>>>,
    resource_dir: PathBuf,
    subtitle_providers: Arc<Vec<Arc<dyn SubtitleSearchProvider>>>,
}

impl M18Coordinator {
    pub fn new() -> Self {
        let resource_dir = Self::default_resources_dir();
        let opensubtitles = Arc::new(OpenSubtitlesProvider::new(
            std::env::var("LLPLAYERNEXT_OPENSUBTITLES_BASE_URL")
                .unwrap_or_else(|_| "https://api.opensubtitles.com/api/v1".into()),
        ));
        Self::with_configuration(resource_catalog(), resource_dir, vec![opensubtitles])
    }

    fn with_configuration(
        mut resources: Vec<LearningResourceDescriptor>,
        resource_dir: PathBuf,
        subtitle_providers: Vec<Arc<dyn SubtitleSearchProvider>>,
    ) -> Self {
        for descriptor in &mut resources {
            let path = resource_dir.join(format!("{}.data", descriptor.id.as_str()));
            if let Ok(metadata) = std::fs::metadata(&path) {
                if metadata.is_file() && metadata.len() == descriptor.size_bytes {
                    descriptor.local_path = Some(path.to_string_lossy().into_owned());
                    descriptor.installed_bytes = metadata.len();
                    descriptor.state = LearningResourceState::Installed;
                } else {
                    descriptor.state = LearningResourceState::Failed;
                    descriptor.error = Some("installed resource size mismatch".into());
                }
            }
        }
        Self {
            client: Client::new(),
            resources: Arc::new(Mutex::new(resources)),
            resource_dir,
            subtitle_providers: Arc::new(subtitle_providers),
        }
    }

    fn default_resources_dir() -> PathBuf {
        std::env::var_os("LLPLAYERNEXT_RESOURCES_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
                    .join("Library/Application Support/LLPlayerNext/resources/learning")
            })
    }

    pub fn list_resources(&self) -> Vec<LearningResourceDescriptor> {
        self.resources
            .lock()
            .expect("resource mutex poisoned")
            .clone()
    }

    pub async fn install_resource(
        &self,
        id: &LearningResourceId,
    ) -> Result<LearningResourceDescriptor, ApiError> {
        let mut descriptor = self
            .resources
            .lock()
            .expect("resource mutex poisoned")
            .iter()
            .find(|value| value.id == *id)
            .cloned()
            .ok_or_else(|| ApiError::not_found("learning resource"))?;
        descriptor.state = LearningResourceState::Installing;
        replace_resource(&self.resources, descriptor.clone());
        let response = match self.client.get(&descriptor.source_url).send().await {
            Ok(response) => response,
            Err(error) => {
                descriptor.state = LearningResourceState::Failed;
                descriptor.error = Some(error.to_string());
                replace_resource(&self.resources, descriptor);
                return Err(ApiError::gateway(
                    "resource_download_failed",
                    error.to_string(),
                ));
            }
        };
        if !response.status().is_success() {
            descriptor.state = LearningResourceState::Failed;
            descriptor.error = Some(format!("resource server returned {}", response.status()));
            replace_resource(&self.resources, descriptor);
            return Err(ApiError::gateway(
                "resource_download_failed",
                format!("resource server returned {}", response.status()),
            ));
        }
        let bytes = match response.bytes().await {
            Ok(bytes) => bytes,
            Err(error) => {
                descriptor.state = LearningResourceState::Failed;
                descriptor.error = Some(error.to_string());
                replace_resource(&self.resources, descriptor);
                return Err(ApiError::gateway(
                    "resource_download_failed",
                    error.to_string(),
                ));
            }
        };
        let checksum = hex::encode(Sha256::digest(&bytes));
        if !descriptor.checksum_sha256.is_empty() && descriptor.checksum_sha256 != checksum {
            descriptor.state = LearningResourceState::Failed;
            descriptor.error = Some("checksum mismatch".into());
            replace_resource(&self.resources, descriptor.clone());
            return Err(ApiError::new(
                StatusCode::UNPROCESSABLE_ENTITY,
                "checksum_mismatch",
                "learning resource checksum mismatch",
                false,
            ));
        }
        let directory = &self.resource_dir;
        if let Err(error) = tokio::fs::create_dir_all(&directory).await {
            descriptor.state = LearningResourceState::Failed;
            descriptor.error = Some(error.to_string());
            replace_resource(&self.resources, descriptor);
            return Err(ApiError::from(ApplicationError::Repository(
                error.to_string(),
            )));
        }
        let path = directory.join(format!("{}.data", id.as_str()));
        let temporary_path = directory.join(format!("{}.data.download", id.as_str()));
        if let Err(error) = tokio::fs::write(&temporary_path, &bytes).await {
            let _ = tokio::fs::remove_file(&temporary_path).await;
            descriptor.state = LearningResourceState::Failed;
            descriptor.error = Some(error.to_string());
            replace_resource(&self.resources, descriptor);
            return Err(ApiError::from(ApplicationError::Repository(
                error.to_string(),
            )));
        }
        if let Err(error) = tokio::fs::rename(&temporary_path, &path).await {
            let _ = tokio::fs::remove_file(&temporary_path).await;
            descriptor.state = LearningResourceState::Failed;
            descriptor.error = Some(error.to_string());
            replace_resource(&self.resources, descriptor);
            return Err(ApiError::from(ApplicationError::Repository(
                error.to_string(),
            )));
        }
        descriptor.checksum_sha256 = checksum;
        descriptor.size_bytes = bytes.len() as u64;
        descriptor.installed_bytes = bytes.len() as u64;
        descriptor.local_path = Some(path.to_string_lossy().into_owned());
        descriptor.state = LearningResourceState::Installed;
        descriptor.error = None;
        descriptor.updated_at_ms = application::now_ms();
        replace_resource(&self.resources, descriptor.clone());
        Ok(descriptor)
    }

    pub async fn remove_resource(
        &self,
        id: &LearningResourceId,
    ) -> Result<LearningResourceDescriptor, ApiError> {
        let mut descriptor = self
            .resources
            .lock()
            .expect("resource mutex poisoned")
            .iter()
            .find(|value| value.id == *id)
            .cloned()
            .ok_or_else(|| ApiError::not_found("learning resource"))?;
        if let Some(path) = descriptor.local_path.take() {
            let _ = tokio::fs::remove_file(path).await;
        }
        descriptor.state = LearningResourceState::Available;
        descriptor.installed_bytes = 0;
        descriptor.error = None;
        descriptor.updated_at_ms = application::now_ms();
        replace_resource(&self.resources, descriptor.clone());
        Ok(descriptor)
    }

    async fn search_subtitles(
        &self,
        request: &SubtitleSearchRequest,
    ) -> Result<Vec<SubtitleSearchResult>, ApiError> {
        self.subtitle_provider(request.provider.as_deref())?
            .search(request)
            .await
    }

    async fn download_subtitle(
        &self,
        request: &SubtitleDownloadRequest,
    ) -> Result<Vec<u8>, ApiError> {
        self.subtitle_provider(request.provider.as_deref())?
            .download(request)
            .await
    }

    fn subtitle_provider(
        &self,
        id: Option<&str>,
    ) -> Result<&Arc<dyn SubtitleSearchProvider>, ApiError> {
        let id = id.unwrap_or("opensubtitles");
        self.subtitle_providers
            .iter()
            .find(|provider| provider.id() == id)
            .ok_or_else(|| ApiError::not_found("subtitle search provider"))
    }
}

#[async_trait]
trait SubtitleSearchProvider: Send + Sync {
    fn id(&self) -> &'static str;
    async fn search(
        &self,
        request: &SubtitleSearchRequest,
    ) -> Result<Vec<SubtitleSearchResult>, ApiError>;
    async fn download(&self, request: &SubtitleDownloadRequest) -> Result<Vec<u8>, ApiError>;
}

struct OpenSubtitlesProvider {
    client: Client,
    base_url: String,
}

impl OpenSubtitlesProvider {
    fn new(base_url: String) -> Self {
        Self {
            client: Client::new(),
            base_url,
        }
    }
}

#[async_trait]
impl SubtitleSearchProvider for OpenSubtitlesProvider {
    fn id(&self) -> &'static str {
        "opensubtitles"
    }

    async fn search(
        &self,
        request: &SubtitleSearchRequest,
    ) -> Result<Vec<SubtitleSearchResult>, ApiError> {
        if request.api_key.trim().is_empty() {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "subtitle_credentials_required",
                "subtitle provider credentials are required",
                false,
            ));
        }
        if request.query.as_deref().is_none_or(str::is_empty)
            && request.moviehash.as_deref().is_none_or(str::is_empty)
        {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "subtitle_search_query_required",
                "a title, filename, or media hash is required",
                false,
            ));
        }
        let mut query = vec![("languages", request.language.as_str())];
        if let Some(value) = request.query.as_deref() {
            query.push(("query", value));
        }
        if let Some(value) = request.moviehash.as_deref() {
            query.push(("moviehash", value));
        }
        let response = self
            .client
            .get(format!("{}/subtitles", self.base_url))
            .header("Api-Key", &request.api_key)
            .header("User-Agent", "LLPlayerNext v0.6")
            .query(&query)
            .send()
            .await
            .map_err(|error| ApiError::gateway("subtitle_search_failed", error.to_string()))?;
        if !response.status().is_success() {
            return Err(subtitle_service_error(response.status(), "search"));
        }
        let payload: serde_json::Value = response
            .json()
            .await
            .map_err(|error| ApiError::gateway("subtitle_search_failed", error.to_string()))?;
        Ok(payload["data"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|value| {
                let attributes = &value["attributes"];
                let file_id = attributes["files"].as_array()?.first()?["file_id"].as_u64()?;
                Some(SubtitleSearchResult {
                    id: value["id"].as_str()?.into(),
                    file_id,
                    language: attributes["language"].as_str().unwrap_or_default().into(),
                    release: attributes["release"].as_str().unwrap_or_default().into(),
                    source: "OpenSubtitles".into(),
                    rating: attributes["ratings"].as_f64().unwrap_or_default(),
                    download_count: attributes["download_count"].as_u64().unwrap_or_default(),
                })
            })
            .collect())
    }

    async fn download(&self, request: &SubtitleDownloadRequest) -> Result<Vec<u8>, ApiError> {
        if request.api_key.trim().is_empty() {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "subtitle_credentials_required",
                "subtitle provider credentials are required",
                false,
            ));
        }
        let response = self
            .client
            .post(format!("{}/download", self.base_url))
            .header("Api-Key", &request.api_key)
            .header("User-Agent", "LLPlayerNext v0.6")
            .json(&serde_json::json!({"file_id": request.file_id}))
            .send()
            .await
            .map_err(|error| ApiError::gateway("subtitle_download_failed", error.to_string()))?;
        if !response.status().is_success() {
            return Err(subtitle_service_error(response.status(), "download"));
        }
        let payload: serde_json::Value = response
            .json()
            .await
            .map_err(|error| ApiError::gateway("subtitle_download_failed", error.to_string()))?;
        let link = payload["link"].as_str().ok_or_else(|| {
            ApiError::gateway("subtitle_download_failed", "missing download link")
        })?;
        let response =
            self.client.get(link).send().await.map_err(|error| {
                ApiError::gateway("subtitle_download_failed", error.to_string())
            })?;
        if !response.status().is_success() {
            return Err(subtitle_service_error(response.status(), "download"));
        }
        response
            .bytes()
            .await
            .map(|bytes| bytes.to_vec())
            .map_err(|error| ApiError::gateway("subtitle_download_failed", error.to_string()))
    }
}

fn subtitle_service_error(status: reqwest::StatusCode, operation: &'static str) -> ApiError {
    match status {
        reqwest::StatusCode::UNAUTHORIZED | reqwest::StatusCode::FORBIDDEN => ApiError::new(
            StatusCode::UNAUTHORIZED,
            "subtitle_authentication_failed",
            "subtitle provider rejected the configured credentials",
            false,
        ),
        reqwest::StatusCode::TOO_MANY_REQUESTS => ApiError::new(
            StatusCode::TOO_MANY_REQUESTS,
            "subtitle_rate_limited",
            "subtitle provider rate limit reached",
            true,
        ),
        status if status.is_server_error() => ApiError::gateway(
            "subtitle_service_unavailable",
            format!("subtitle provider {operation} is unavailable"),
        ),
        _ => ApiError::new(
            StatusCode::BAD_REQUEST,
            "subtitle_request_rejected",
            format!("subtitle provider rejected the {operation} request"),
            false,
        ),
    }
}

fn resource_catalog() -> Vec<LearningResourceDescriptor> {
    [
        (
            "ecdict",
            "ECDICT",
            "bc015ed2",
            "https://raw.githubusercontent.com/skywind3000/ECDICT/bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b/ecdict.csv",
            "MIT",
            "1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf",
            65_933_428,
        ),
        (
            "cmudict",
            "CMU Pronouncing Dictionary",
            "74790861",
            "https://raw.githubusercontent.com/cmusphinx/cmudict/74790861f652b15e4ac49015a90074ad62a27690/cmudict.dict",
            "BSD-style CMUdict license",
            "81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22",
            3_618_488,
        ),
        (
            "cc-cedict",
            "CC-CEDICT",
            "61e2794c",
            "https://raw.githubusercontent.com/ueda-keisuke/CC-CEDICT-MeCab/61e2794c475313adf241b739fcde8acb4520c1ea/cedict_ts.u8",
            "CC-BY-SA 4.0",
            "09ec3a583100088c4f7db2d65643bb9134df5174a4bca7592f50fe2bc5686957",
            9_151_648,
        ),
    ]
    .into_iter()
    .map(|(id, name, version, url, license, checksum, size)| LearningResourceDescriptor {
        id: LearningResourceId::from_fingerprint("learning-resource", id),
        display_name: name.into(),
        version: version.into(),
        source_url: url.into(),
        license: license.into(),
        checksum_sha256: checksum.into(),
        size_bytes: size,
        local_path: None,
        state: LearningResourceState::Available,
        installed_bytes: 0,
        error: None,
        updated_at_ms: 0,
    })
    .collect()
}

fn replace_resource(
    resources: &Mutex<Vec<LearningResourceDescriptor>>,
    replacement: LearningResourceDescriptor,
) {
    let mut values = resources.lock().expect("resource mutex poisoned");
    if let Some(value) = values.iter_mut().find(|value| value.id == replacement.id) {
        *value = replacement;
    }
}

#[derive(Debug, Deserialize)]
pub struct LexicalQuery {
    language: Option<String>,
    kind: Option<LexicalEntryKind>,
    status: Option<LearningStatus>,
    search: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub async fn list_lexical_entries(
    State(state): State<ApiState>,
    Query(query): Query<LexicalQuery>,
) -> Result<Json<Vec<LexicalEntryDetails>>, ApiError> {
    state
        .services
        .list_lexical_entries(
            query.language.as_deref().unwrap_or("en"),
            query.kind,
            query.status,
            query.search.as_deref().unwrap_or(""),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub struct BatchLexicalRequest {
    language: String,
    kind: LexicalEntryKind,
    forms: Vec<String>,
}

pub async fn read_lexical_entries(
    State(state): State<ApiState>,
    Json(request): Json<BatchLexicalRequest>,
) -> Result<Json<Vec<LexicalEntry>>, ApiError> {
    state
        .services
        .read_lexical_entries_by_forms(&request.language, request.kind, &request.forms)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub struct LexicalSourceRequest {
    media_id: Option<String>,
    sentence_id: Option<String>,
    original_form: String,
    sentence_text: String,
    media_title: String,
    media_fingerprint: String,
    start_ms: u64,
    end_ms: u64,
    token_start: Option<u32>,
    token_end: Option<u32>,
}

impl LexicalSourceRequest {
    fn into_context(self) -> Result<LexicalSourceContext, ApplicationError> {
        Ok(LexicalSourceContext {
            media_id: self.media_id.map(domain::MediaId::parse).transpose()?,
            sentence_id: self
                .sentence_id
                .map(SubtitleSentenceId::parse)
                .transpose()?,
            original_form: self.original_form,
            sentence_text: self.sentence_text,
            media_title: self.media_title,
            media_fingerprint: self.media_fingerprint,
            start_ms: self.start_ms,
            end_ms: self.end_ms,
            token_start: self.token_start,
            token_end: self.token_end,
        })
    }
}

#[derive(Debug, Deserialize)]
pub struct UpsertLexicalRequest {
    language: String,
    kind: LexicalEntryKind,
    canonical_form: String,
    display_form: String,
    status: Option<LearningStatus>,
    user_definition: Option<String>,
    personal_note: Option<String>,
    source: Option<LexicalSourceRequest>,
}

pub async fn upsert_lexical_entry(
    State(state): State<ApiState>,
    Json(request): Json<UpsertLexicalRequest>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let details = state
        .services
        .create_lexical_entry(UpsertLexicalEntry {
            language: request.language,
            kind: request.kind,
            canonical_form: request.canonical_form,
            display_form: request.display_form,
            status: request.status,
            user_definition: request.user_definition,
            personal_note: request.personal_note,
            source: request
                .source
                .map(LexicalSourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::LexicalEntryChanged,
        serde_json::to_value(&details).expect("lexical details serializes"),
    ));
    Ok(Json(details))
}

pub async fn lexical_details(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    state
        .services
        .lexical_details(&LexicalEntryId::parse(id).map_err(ApplicationError::from)?)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("lexical entry"))
}

#[derive(Debug, Deserialize)]
pub struct UpdateLearningContentRequest {
    user_definition: Option<String>,
    personal_note: Option<String>,
}

pub async fn update_lexical_learning_content(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<UpdateLearningContentRequest>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let details = state
        .services
        .update_lexical_learning_content(
            &LexicalEntryId::parse(id).map_err(ApplicationError::from)?,
            request.user_definition,
            request.personal_note,
        )
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::LexicalEntryChanged,
        serde_json::to_value(&details).expect("lexical details serializes"),
    ));
    Ok(Json(details))
}

#[derive(Debug, Deserialize)]
pub struct CreateLexicalObservationRequest {
    lexical_entry_id: String,
    sentence_id: String,
    original_form: String,
    result: Option<ObservationResult>,
    clear: Option<bool>,
    source: Option<LexicalSourceRequest>,
}

pub async fn create_lexical_observation(
    State(state): State<ApiState>,
    Json(request): Json<CreateLexicalObservationRequest>,
) -> Result<Response, ApiError> {
    let lexical_entry_id =
        LexicalEntryId::parse(request.lexical_entry_id).map_err(ApplicationError::from)?;
    let sentence_id =
        SubtitleSentenceId::parse(request.sentence_id).map_err(ApplicationError::from)?;
    if request.clear.unwrap_or(false) {
        state
            .services
            .clear_lexical_observation(&lexical_entry_id, &sentence_id)?;
        let _ = state.events.send(
            crate::event_payloads::LexicalObservationClearedPayload {
                lexical_entry_id: lexical_entry_id.as_str().to_owned(),
                sentence_id: sentence_id.as_str().to_owned(),
            }
            .envelope(),
        );
        return Ok(StatusCode::NO_CONTENT.into_response());
    }
    let observation = state
        .services
        .create_lexical_observation(CreateLexicalObservation {
            lexical_entry_id,
            sentence_id,
            original_form: request.original_form,
            result: request
                .result
                .ok_or(ApplicationError::Validation("result"))?,
            source: request
                .source
                .map(LexicalSourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::LexicalObservationCreated,
        serde_json::to_value(&observation).expect("lexical observation serializes"),
    ));
    Ok(Json(observation).into_response())
}

#[derive(Debug, Deserialize)]
pub struct NormalizeRequest {
    language: String,
    value: String,
}

pub async fn normalize_lexical(
    State(state): State<ApiState>,
    Json(request): Json<NormalizeRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let value = state
        .services
        .normalize_lexical_form(&request.language, &request.value)?;
    Ok(Json(serde_json::json!({
        "original": value.original,
        "normalized": value.normalized,
        "provider": value.provider,
        "version": value.version,
        "user_corrected": value.user_corrected
    })))
}

#[derive(Debug, Deserialize)]
pub struct CorrectLemmaRequest {
    language: String,
    original: String,
    corrected: String,
}

pub async fn correct_lemma(
    State(state): State<ApiState>,
    Json(request): Json<CorrectLemmaRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let value =
        state
            .services
            .correct_lemma(&request.language, &request.original, &request.corrected)?;
    Ok(Json(serde_json::json!({
        "original": value.original,
        "normalized": value.normalized,
        "provider": value.provider,
        "version": value.version,
        "user_corrected": value.user_corrected
    })))
}

pub async fn phrase_candidates(
    State(state): State<ApiState>,
    Path(sentence_id): Path<String>,
) -> Result<Json<Vec<PhraseCandidate>>, ApiError> {
    state
        .services
        .phrase_candidates(&SubtitleSentenceId::parse(sentence_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub async fn resources(State(state): State<ApiState>) -> Json<Vec<LearningResourceDescriptor>> {
    Json(state.m18.list_resources())
}

pub async fn install_resource(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<LearningResourceDescriptor>, ApiError> {
    state
        .m18
        .install_resource(&LearningResourceId::parse(id).map_err(ApplicationError::from)?)
        .await
        .map(Json)
}

pub async fn remove_resource(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<LearningResourceDescriptor>, ApiError> {
    state
        .m18
        .remove_resource(&LearningResourceId::parse(id).map_err(ApplicationError::from)?)
        .await
        .map(Json)
}

#[derive(Debug, Deserialize)]
pub struct SubtitleSearchRequest {
    provider: Option<String>,
    api_key: String,
    language: String,
    query: Option<String>,
    moviehash: Option<String>,
}

pub async fn search_subtitles(
    State(state): State<ApiState>,
    Json(request): Json<SubtitleSearchRequest>,
) -> Result<Json<Vec<SubtitleSearchResult>>, ApiError> {
    state.m18.search_subtitles(&request).await.map(Json)
}

#[derive(Debug, Deserialize)]
pub struct SubtitleDownloadRequest {
    provider: Option<String>,
    api_key: String,
    file_id: u64,
}

pub async fn download_subtitle(
    State(state): State<ApiState>,
    Json(request): Json<SubtitleDownloadRequest>,
) -> Result<Response, ApiError> {
    state.m18.download_subtitle(&request).await.map(|bytes| {
        (
            [(axum::http::header::CONTENT_TYPE, "application/x-subrip")],
            bytes,
        )
            .into_response()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    fn temp_dir(label: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "llplayernext-m18-{label}-{}-{}",
            std::process::id(),
            application::now_ms()
        ))
    }

    fn descriptor(url: String, checksum: String) -> LearningResourceDescriptor {
        LearningResourceDescriptor {
            id: LearningResourceId::from_fingerprint("learning-resource", "fixture"),
            display_name: "Fixture".into(),
            version: "v1".into(),
            source_url: url,
            license: "MIT".into(),
            checksum_sha256: checksum,
            size_bytes: 7,
            local_path: None,
            state: LearningResourceState::Available,
            installed_bytes: 0,
            error: None,
            updated_at_ms: 0,
        }
    }

    async fn serve_once(body: &'static [u8]) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = [0_u8; 2048];
            let _ = stream.read(&mut request).await;
            let headers = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            );
            stream.write_all(headers.as_bytes()).await.unwrap();
            stream.write_all(body).await.unwrap();
        });
        format!("http://{address}/resource")
    }

    async fn serve_truncated(body: &'static [u8]) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = [0_u8; 2048];
            let _ = stream.read(&mut request).await;
            let headers = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len() + 10
            );
            stream.write_all(headers.as_bytes()).await.unwrap();
            stream.write_all(body).await.unwrap();
        });
        format!("http://{address}/resource")
    }

    #[tokio::test]
    async fn learning_resource_verifies_checksum_and_removes_installed_file() {
        let body = b"fixture";
        let url = serve_once(body).await;
        let checksum = hex::encode(Sha256::digest(body));
        let resource = descriptor(url, checksum);
        let id = resource.id.clone();
        let directory = temp_dir("install");
        let coordinator =
            M18Coordinator::with_configuration(vec![resource], directory.clone(), Vec::new());
        let installed = coordinator.install_resource(&id).await.unwrap();
        assert_eq!(installed.state, LearningResourceState::Installed);
        let path = installed.local_path.clone().unwrap();
        assert!(std::path::Path::new(&path).exists());
        let removed = coordinator.remove_resource(&id).await.unwrap();
        assert_eq!(removed.state, LearningResourceState::Available);
        assert!(!std::path::Path::new(&path).exists());
        let _ = std::fs::remove_dir_all(directory);
    }

    #[tokio::test]
    async fn learning_resource_checksum_failure_never_publishes_file() {
        let url = serve_once(b"wrong").await;
        let resource = descriptor(url, "expected".into());
        let id = resource.id.clone();
        let directory = temp_dir("checksum");
        let coordinator =
            M18Coordinator::with_configuration(vec![resource], directory.clone(), Vec::new());
        let error = coordinator.install_resource(&id).await.unwrap_err();
        assert_eq!(error.body.code, "checksum_mismatch");
        assert_eq!(
            coordinator.list_resources()[0].state,
            LearningResourceState::Failed
        );
        assert!(!directory.join(format!("{}.data", id.as_str())).exists());
    }

    #[tokio::test]
    async fn learning_resource_network_failure_is_retryable_and_safe() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        drop(listener);
        let resource = descriptor(format!("http://{address}/missing"), String::new());
        let id = resource.id.clone();
        let directory = temp_dir("offline");
        let coordinator =
            M18Coordinator::with_configuration(vec![resource], directory.clone(), Vec::new());
        let error = coordinator.install_resource(&id).await.unwrap_err();
        assert!(error.body.retryable);
        assert_eq!(
            coordinator.list_resources()[0].state,
            LearningResourceState::Failed
        );
        assert!(!directory.join(format!("{}.data", id.as_str())).exists());
    }

    #[tokio::test]
    async fn interrupted_learning_resource_download_leaves_no_partial_file() {
        let url = serve_truncated(b"partial").await;
        let resource = descriptor(url, String::new());
        let id = resource.id.clone();
        let directory = temp_dir("interrupted");
        let coordinator =
            M18Coordinator::with_configuration(vec![resource], directory.clone(), Vec::new());
        let error = coordinator.install_resource(&id).await.unwrap_err();
        assert!(error.body.retryable);
        assert_eq!(
            coordinator.list_resources()[0].state,
            LearningResourceState::Failed
        );
        assert!(!directory.join(format!("{}.data", id.as_str())).exists());
        assert!(
            !directory
                .join(format!("{}.data.download", id.as_str()))
                .exists()
        );
    }
}
