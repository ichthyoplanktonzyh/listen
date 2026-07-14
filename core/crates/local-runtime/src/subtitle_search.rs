use std::sync::Arc;

use async_trait::async_trait;
use domain::SubtitleSearchResult;
use reqwest::Client;
use serde::Deserialize;
use thiserror::Error;

#[derive(Debug, Clone, Deserialize)]
pub struct SubtitleSearchRequest {
    pub provider: Option<String>,
    pub api_key: String,
    pub language: String,
    pub query: Option<String>,
    pub moviehash: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SubtitleDownloadRequest {
    pub provider: Option<String>,
    pub api_key: String,
    pub file_id: u64,
}

#[derive(Debug, Clone, Copy)]
pub enum SubtitleOperation {
    Search,
    Download,
}

impl SubtitleOperation {
    pub fn wire_name(self) -> &'static str {
        match self {
            Self::Search => "search",
            Self::Download => "download",
        }
    }
}

impl std::fmt::Display for SubtitleOperation {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.wire_name())
    }
}

#[derive(Debug, Error)]
pub enum SubtitleProviderError {
    #[error("subtitle search provider was not found")]
    ProviderNotFound,
    #[error("subtitle provider credentials are required")]
    CredentialsRequired,
    #[error("a title, filename, or media hash is required")]
    QueryRequired,
    #[error("subtitle provider rejected the configured credentials")]
    Authentication,
    #[error("subtitle provider rate limit reached")]
    RateLimited,
    #[error("subtitle provider {0} is unavailable")]
    Unavailable(SubtitleOperation),
    #[error("subtitle provider rejected the {0}")]
    Rejected(SubtitleOperation),
    #[error("subtitle provider {operation:?} failed: {detail}")]
    Network {
        operation: SubtitleOperation,
        detail: String,
    },
    #[error("subtitle provider response had no download link")]
    MissingDownloadLink,
}

#[derive(Clone)]
pub struct SubtitleSearchCoordinator {
    providers: Arc<Vec<Arc<dyn SubtitleSearchProvider>>>,
}

impl SubtitleSearchCoordinator {
    pub fn new() -> Self {
        Self {
            providers: Arc::new(vec![Arc::new(OpenSubtitlesProvider::new(
                std::env::var("LLPLAYERNEXT_OPENSUBTITLES_BASE_URL")
                    .unwrap_or_else(|_| "https://api.opensubtitles.com/api/v1".into()),
            ))]),
        }
    }

    pub async fn search(
        &self,
        request: &SubtitleSearchRequest,
    ) -> Result<Vec<SubtitleSearchResult>, SubtitleProviderError> {
        self.provider(request.provider.as_deref())?
            .search(request)
            .await
    }

    pub async fn download(
        &self,
        request: &SubtitleDownloadRequest,
    ) -> Result<Vec<u8>, SubtitleProviderError> {
        self.provider(request.provider.as_deref())?
            .download(request)
            .await
    }

    fn provider(
        &self,
        id: Option<&str>,
    ) -> Result<&Arc<dyn SubtitleSearchProvider>, SubtitleProviderError> {
        let id = id.unwrap_or("opensubtitles");
        self.providers
            .iter()
            .find(|provider| provider.id() == id)
            .ok_or(SubtitleProviderError::ProviderNotFound)
    }
}

impl Default for SubtitleSearchCoordinator {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
trait SubtitleSearchProvider: Send + Sync {
    fn id(&self) -> &'static str;
    async fn search(
        &self,
        request: &SubtitleSearchRequest,
    ) -> Result<Vec<SubtitleSearchResult>, SubtitleProviderError>;
    async fn download(
        &self,
        request: &SubtitleDownloadRequest,
    ) -> Result<Vec<u8>, SubtitleProviderError>;
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
    ) -> Result<Vec<SubtitleSearchResult>, SubtitleProviderError> {
        if request.api_key.trim().is_empty() {
            return Err(SubtitleProviderError::CredentialsRequired);
        }
        if request.query.as_deref().is_none_or(str::is_empty)
            && request.moviehash.as_deref().is_none_or(str::is_empty)
        {
            return Err(SubtitleProviderError::QueryRequired);
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
            .map_err(|error| SubtitleProviderError::Network {
                operation: SubtitleOperation::Search,
                detail: error.to_string(),
            })?;
        ensure_status(response.status(), SubtitleOperation::Search)?;
        let payload: serde_json::Value =
            response
                .json()
                .await
                .map_err(|error| SubtitleProviderError::Network {
                    operation: SubtitleOperation::Search,
                    detail: error.to_string(),
                })?;
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

    async fn download(
        &self,
        request: &SubtitleDownloadRequest,
    ) -> Result<Vec<u8>, SubtitleProviderError> {
        if request.api_key.trim().is_empty() {
            return Err(SubtitleProviderError::CredentialsRequired);
        }
        let response = self
            .client
            .post(format!("{}/download", self.base_url))
            .header("Api-Key", &request.api_key)
            .header("User-Agent", "LLPlayerNext v0.6")
            .json(&serde_json::json!({"file_id": request.file_id}))
            .send()
            .await
            .map_err(|error| SubtitleProviderError::Network {
                operation: SubtitleOperation::Download,
                detail: error.to_string(),
            })?;
        ensure_status(response.status(), SubtitleOperation::Download)?;
        let payload: serde_json::Value =
            response
                .json()
                .await
                .map_err(|error| SubtitleProviderError::Network {
                    operation: SubtitleOperation::Download,
                    detail: error.to_string(),
                })?;
        let link = payload["link"]
            .as_str()
            .ok_or(SubtitleProviderError::MissingDownloadLink)?;
        let response =
            self.client
                .get(link)
                .send()
                .await
                .map_err(|error| SubtitleProviderError::Network {
                    operation: SubtitleOperation::Download,
                    detail: error.to_string(),
                })?;
        ensure_status(response.status(), SubtitleOperation::Download)?;
        response
            .bytes()
            .await
            .map(|bytes| bytes.to_vec())
            .map_err(|error| SubtitleProviderError::Network {
                operation: SubtitleOperation::Download,
                detail: error.to_string(),
            })
    }
}

fn ensure_status(
    status: reqwest::StatusCode,
    operation: SubtitleOperation,
) -> Result<(), SubtitleProviderError> {
    match status {
        status if status.is_success() => Ok(()),
        reqwest::StatusCode::UNAUTHORIZED | reqwest::StatusCode::FORBIDDEN => {
            Err(SubtitleProviderError::Authentication)
        }
        reqwest::StatusCode::TOO_MANY_REQUESTS => Err(SubtitleProviderError::RateLimited),
        status if status.is_server_error() => Err(SubtitleProviderError::Unavailable(operation)),
        _ => Err(SubtitleProviderError::Rejected(operation)),
    }
}
