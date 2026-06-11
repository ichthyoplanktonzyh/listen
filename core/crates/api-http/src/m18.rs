use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use application::{ApplicationError, LexicalSourceContext, UpsertLexicalEntry};
use axum::Json;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use domain::{
    LearningResourceDescriptor, LearningResourceId, LearningResourceState, LexicalEntryDetails,
    LexicalEntryId, LexicalEntryKind, PhraseCandidate, SubtitleSearchResult, SubtitleSentenceId,
    WordStatus,
};
use reqwest::Client;
use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::{ApiError, ApiState};

#[derive(Clone)]
pub struct M18Coordinator {
    client: Client,
    resources: Arc<Mutex<Vec<LearningResourceDescriptor>>>,
    opensubtitles_base_url: String,
}

impl M18Coordinator {
    pub fn new() -> Self {
        let mut resources = resource_catalog();
        for descriptor in &mut resources {
            let path = Self::resources_dir().join(format!("{}.data", descriptor.id.as_str()));
            if let Ok(bytes) = std::fs::read(&path) {
                let checksum = hex::encode(Sha256::digest(&bytes));
                if descriptor.checksum_sha256 == checksum {
                    descriptor.local_path = Some(path.to_string_lossy().into_owned());
                    descriptor.installed_bytes = bytes.len() as u64;
                    descriptor.size_bytes = bytes.len() as u64;
                    descriptor.state = LearningResourceState::Installed;
                } else {
                    descriptor.state = LearningResourceState::Failed;
                    descriptor.error = Some("checksum mismatch".into());
                }
            }
        }
        Self {
            client: Client::new(),
            resources: Arc::new(Mutex::new(resources)),
            opensubtitles_base_url: std::env::var("LLPLAYERNEXT_OPENSUBTITLES_BASE_URL")
                .unwrap_or_else(|_| "https://api.opensubtitles.com/api/v1".into()),
        }
    }

    fn resources_dir() -> PathBuf {
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
        let bytes = response
            .bytes()
            .await
            .map_err(|error| ApiError::gateway("resource_download_failed", error.to_string()))?;
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
        let directory = Self::resources_dir();
        tokio::fs::create_dir_all(&directory)
            .await
            .map_err(|error| ApiError::from(ApplicationError::Repository(error.to_string())))?;
        let path = directory.join(format!("{}.data", id.as_str()));
        tokio::fs::write(&path, &bytes)
            .await
            .map_err(|error| ApiError::from(ApplicationError::Repository(error.to_string())))?;
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
        let mut query = vec![("languages", request.language.as_str())];
        if let Some(value) = request.query.as_deref() {
            query.push(("query", value));
        }
        if let Some(value) = request.moviehash.as_deref() {
            query.push(("moviehash", value));
        }
        let response = self
            .client
            .get(format!("{}/subtitles", self.opensubtitles_base_url))
            .header("Api-Key", &request.api_key)
            .header("User-Agent", "LLPlayerNext v0.6")
            .query(&query)
            .send()
            .await
            .map_err(|error| ApiError::gateway("subtitle_search_failed", error.to_string()))?;
        if !response.status().is_success() {
            return Err(ApiError::gateway(
                "subtitle_search_failed",
                format!("OpenSubtitles returned {}", response.status()),
            ));
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

    async fn download_subtitle(
        &self,
        request: &SubtitleDownloadRequest,
    ) -> Result<Vec<u8>, ApiError> {
        let response = self
            .client
            .post(format!("{}/download", self.opensubtitles_base_url))
            .header("Api-Key", &request.api_key)
            .header("User-Agent", "LLPlayerNext v0.6")
            .json(&serde_json::json!({"file_id": request.file_id}))
            .send()
            .await
            .map_err(|error| ApiError::gateway("subtitle_download_failed", error.to_string()))?;
        if !response.status().is_success() {
            return Err(ApiError::gateway(
                "subtitle_download_failed",
                format!("OpenSubtitles returned {}", response.status()),
            ));
        }
        let payload: serde_json::Value = response
            .json()
            .await
            .map_err(|error| ApiError::gateway("subtitle_download_failed", error.to_string()))?;
        let link = payload["link"].as_str().ok_or_else(|| {
            ApiError::gateway("subtitle_download_failed", "missing download link")
        })?;
        let bytes = self
            .client
            .get(link)
            .send()
            .await
            .map_err(|error| ApiError::gateway("subtitle_download_failed", error.to_string()))?
            .bytes()
            .await
            .map_err(|error| ApiError::gateway("subtitle_download_failed", error.to_string()))?;
        Ok(bytes.to_vec())
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
    status: Option<WordStatus>,
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

#[derive(Debug, Deserialize)]
pub struct UpsertLexicalRequest {
    language: String,
    kind: LexicalEntryKind,
    canonical_form: String,
    display_form: String,
    status: Option<WordStatus>,
    user_definition: Option<String>,
    personal_note: Option<String>,
    source: Option<LexicalSourceRequest>,
}

pub async fn upsert_lexical_entry(
    State(state): State<ApiState>,
    Json(request): Json<UpsertLexicalRequest>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    state
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
                .map(|source| {
                    Ok::<LexicalSourceContext, application::ApplicationError>(
                        LexicalSourceContext {
                            media_id: source.media_id.map(domain::MediaId::parse).transpose()?,
                            sentence_id: source
                                .sentence_id
                                .map(SubtitleSentenceId::parse)
                                .transpose()?,
                            original_form: source.original_form,
                            sentence_text: source.sentence_text,
                            media_title: source.media_title,
                            media_fingerprint: source.media_fingerprint,
                            start_ms: source.start_ms,
                            end_ms: source.end_ms,
                            token_start: source.token_start,
                            token_end: source.token_end,
                        },
                    )
                })
                .transpose()?,
        })
        .map(Json)
        .map_err(ApiError::from)
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
