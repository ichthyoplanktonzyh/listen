//! Concrete semantic-embedding adapters.
//!
//! This crate is the provider seam: application code never sees FastEmbed,
//! ONNX, Hugging Face cache layout, credentials, or vendor JSON. A descriptor
//! fingerprints the complete vector-space contract; wire compatibility never
//! implies vector compatibility.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, RwLock};

use application::{ApplicationError, EmbeddingProvider};
use async_trait::async_trait;
use domain::{
    EmbeddingModelDescriptor, EmbeddingPurpose, SEMANTIC_INDEX_SCHEMA_VERSION,
    SemanticEmbeddingStatus,
};
use fastembed::{EmbeddingModel, TextEmbedding, TextInitOptions};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const MODEL_REPOSITORY: &str = "models--Qdrant--all-MiniLM-L6-v2-onnx";
const DESCRIPTOR_FILE: &str = "llplayernext-descriptor.json";

pub struct FastEmbedProvider {
    descriptor: EmbeddingModelDescriptor,
    model: Arc<Mutex<TextEmbedding>>,
}

impl FastEmbedProvider {
    fn install(cache_dir: &Path) -> Result<Self, ApplicationError> {
        std::fs::create_dir_all(cache_dir).map_err(external)?;
        let model = TextEmbedding::try_new(
            TextInitOptions::new(EmbeddingModel::AllMiniLML6V2)
                .with_cache_dir(cache_dir.to_path_buf())
                .with_show_download_progress(false)
                .with_intra_threads(4),
        )
        .map_err(external)?;
        let descriptor = installed_descriptor(cache_dir)?;
        let bytes = serde_json::to_vec_pretty(&descriptor)
            .map_err(|error| ApplicationError::ExternalProcess(error.to_string()))?;
        std::fs::write(cache_dir.join(DESCRIPTOR_FILE), bytes).map_err(external)?;
        Ok(Self {
            descriptor,
            model: Arc::new(Mutex::new(model)),
        })
    }

    fn load(cache_dir: &Path) -> Result<Option<Self>, ApplicationError> {
        let descriptor_path = cache_dir.join(DESCRIPTOR_FILE);
        if !descriptor_path.is_file() {
            return Ok(None);
        }
        let descriptor: EmbeddingModelDescriptor =
            serde_json::from_slice(&std::fs::read(descriptor_path).map_err(external)?).map_err(
                |error| ApplicationError::Invalid(format!("invalid embedding descriptor: {error}")),
            )?;
        let current = installed_descriptor(cache_dir)?;
        if current != descriptor {
            return Err(ApplicationError::Conflict(
                "installed embedding artifacts no longer match their descriptor",
            ));
        }
        let model = TextEmbedding::try_new(
            TextInitOptions::new(EmbeddingModel::AllMiniLML6V2)
                .with_cache_dir(cache_dir.to_path_buf())
                .with_show_download_progress(false)
                .with_intra_threads(4),
        )
        .map_err(external)?;
        Ok(Some(Self {
            descriptor,
            model: Arc::new(Mutex::new(model)),
        }))
    }
}

#[async_trait]
impl EmbeddingProvider for FastEmbedProvider {
    fn descriptor(&self) -> Option<EmbeddingModelDescriptor> {
        Some(self.descriptor.clone())
    }

    async fn embed(
        &self,
        _purpose: EmbeddingPurpose,
        texts: &[String],
    ) -> Result<Vec<Vec<f32>>, ApplicationError> {
        if texts.iter().any(|text| text.trim().is_empty()) {
            return Err(ApplicationError::Validation("embedding text"));
        }
        let model = self.model.clone();
        let texts = texts.to_vec();
        tokio::task::spawn_blocking(move || {
            model
                .lock()
                .expect("embedding model mutex poisoned")
                .embed(texts, Some(32))
                .map_err(external)
        })
        .await
        .map_err(|error| ApplicationError::ExternalProcess(error.to_string()))?
    }
}

/// Opt-in local model lifecycle. Construction and capability reads never
/// download. Only `install` may access the network; `disable` preserves model
/// bytes and `uninstall` removes bytes without touching indexes or learning data.
pub struct ManagedFastEmbedProvider {
    cache_dir: PathBuf,
    provider: RwLock<Option<Arc<FastEmbedProvider>>>,
    status: RwLock<SemanticEmbeddingStatus>,
}

impl ManagedFastEmbedProvider {
    pub fn new(cache_dir: PathBuf) -> Self {
        match FastEmbedProvider::load(&cache_dir) {
            Ok(provider) => Self {
                cache_dir,
                status: RwLock::new(if provider.is_some() {
                    SemanticEmbeddingStatus::Ready
                } else {
                    SemanticEmbeddingStatus::NotInstalled
                }),
                provider: RwLock::new(provider.map(Arc::new)),
            },
            Err(_) => Self {
                cache_dir,
                provider: RwLock::new(None),
                status: RwLock::new(SemanticEmbeddingStatus::Failed),
            },
        }
    }

    pub async fn install(&self) -> Result<(), ApplicationError> {
        let cache_dir = self.cache_dir.clone();
        let result = tokio::task::spawn_blocking(move || FastEmbedProvider::install(&cache_dir))
            .await
            .map_err(|error| ApplicationError::ExternalProcess(error.to_string()))
            .and_then(|result| result);
        let provider = match result {
            Ok(provider) => provider,
            Err(error) => {
                *self.status.write().expect("embedding status lock poisoned") =
                    SemanticEmbeddingStatus::Failed;
                return Err(error);
            }
        };
        *self
            .provider
            .write()
            .expect("embedding provider lock poisoned") = Some(Arc::new(provider));
        *self.status.write().expect("embedding status lock poisoned") =
            SemanticEmbeddingStatus::Ready;
        Ok(())
    }

    pub fn disable(&self) {
        *self.status.write().expect("embedding status lock poisoned") =
            SemanticEmbeddingStatus::Disabled;
    }

    pub fn enable(&self) -> Result<(), ApplicationError> {
        if self
            .provider
            .read()
            .expect("embedding provider lock poisoned")
            .is_none()
        {
            let provider = match FastEmbedProvider::load(&self.cache_dir).and_then(|provider| {
                provider.ok_or(ApplicationError::Conflict(
                    "semantic embedding model is not installed",
                ))
            }) {
                Ok(provider) => provider,
                Err(error) => {
                    *self.status.write().expect("embedding status lock poisoned") =
                        SemanticEmbeddingStatus::Failed;
                    return Err(error);
                }
            };
            *self
                .provider
                .write()
                .expect("embedding provider lock poisoned") = Some(Arc::new(provider));
        }
        *self.status.write().expect("embedding status lock poisoned") =
            SemanticEmbeddingStatus::Ready;
        Ok(())
    }

    pub fn uninstall(&self) -> Result<(), ApplicationError> {
        *self
            .provider
            .write()
            .expect("embedding provider lock poisoned") = None;
        if self.cache_dir.exists() {
            std::fs::remove_dir_all(&self.cache_dir).map_err(external)?;
        }
        *self.status.write().expect("embedding status lock poisoned") =
            SemanticEmbeddingStatus::NotInstalled;
        Ok(())
    }
}

#[async_trait]
impl EmbeddingProvider for ManagedFastEmbedProvider {
    fn descriptor(&self) -> Option<EmbeddingModelDescriptor> {
        if self.status() != SemanticEmbeddingStatus::Ready {
            return None;
        }
        self.provider
            .read()
            .expect("embedding provider lock poisoned")
            .as_ref()
            .and_then(|provider| provider.descriptor())
    }

    fn status(&self) -> SemanticEmbeddingStatus {
        *self.status.read().expect("embedding status lock poisoned")
    }

    async fn embed(
        &self,
        purpose: EmbeddingPurpose,
        texts: &[String],
    ) -> Result<Vec<Vec<f32>>, ApplicationError> {
        if self.status() != SemanticEmbeddingStatus::Ready {
            return Err(ApplicationError::Conflict(
                "semantic embedding is not ready",
            ));
        }
        let provider = self
            .provider
            .read()
            .expect("embedding provider lock poisoned")
            .clone()
            .ok_or(ApplicationError::Conflict(
                "semantic embedding model is not installed",
            ))?;
        provider.embed(purpose, texts).await
    }
}

#[derive(Clone)]
pub struct OpenAiCompatibleEmbeddingProvider {
    client: reqwest::Client,
    endpoint: String,
    api_key: Option<String>,
    descriptor: EmbeddingModelDescriptor,
}

impl OpenAiCompatibleEmbeddingProvider {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        base_url: &str,
        api_key: Option<String>,
        model_id: &str,
        model_version: &str,
        runtime_version: &str,
        dimension: u32,
        normalization: &str,
    ) -> Result<Self, ApplicationError> {
        if dimension == 0 || model_id.trim().is_empty() || model_version.trim().is_empty() {
            return Err(ApplicationError::Invalid(
                "remote embedding descriptor is incomplete".into(),
            ));
        }
        let endpoint = format!("{}/embeddings", base_url.trim_end_matches('/'));
        let descriptor = make_descriptor(
            "openai-compatible-http",
            model_id,
            model_version,
            runtime_version,
            "remote-artifact-unavailable",
            dimension,
            normalization,
            "wire-compatible; symmetric input; no implicit purpose prefix",
            false,
        );
        Ok(Self {
            client: reqwest::Client::new(),
            endpoint,
            api_key,
            descriptor,
        })
    }
}

#[derive(Serialize)]
struct CompatibleRequest<'a> {
    model: &'a str,
    input: &'a [String],
    encoding_format: &'static str,
    dimensions: u32,
}

#[derive(Deserialize)]
struct CompatibleResponse {
    data: Vec<CompatibleEmbedding>,
}

#[derive(Deserialize)]
struct CompatibleEmbedding {
    index: usize,
    embedding: Vec<f32>,
}

#[async_trait]
impl EmbeddingProvider for OpenAiCompatibleEmbeddingProvider {
    fn descriptor(&self) -> Option<EmbeddingModelDescriptor> {
        Some(self.descriptor.clone())
    }

    async fn embed(
        &self,
        _purpose: EmbeddingPurpose,
        texts: &[String],
    ) -> Result<Vec<Vec<f32>>, ApplicationError> {
        if texts.is_empty() || texts.iter().any(|text| text.trim().is_empty()) {
            return Err(ApplicationError::Validation("embedding text"));
        }
        let mut request = self.client.post(&self.endpoint).json(&CompatibleRequest {
            model: &self.descriptor.model_id,
            input: texts,
            encoding_format: "float",
            dimensions: self.descriptor.dimension,
        });
        if let Some(api_key) = &self.api_key {
            request = request.bearer_auth(api_key);
        }
        let response = request.send().await.map_err(external)?;
        if !response.status().is_success() {
            return Err(ApplicationError::ExternalProcess(format!(
                "embedding provider returned HTTP {}",
                response.status()
            )));
        }
        let mut body: CompatibleResponse = response.json().await.map_err(external)?;
        body.data.sort_by_key(|item| item.index);
        Ok(body.data.into_iter().map(|item| item.embedding).collect())
    }
}

fn installed_descriptor(cache_dir: &Path) -> Result<EmbeddingModelDescriptor, ApplicationError> {
    let repository = cache_dir.join(MODEL_REPOSITORY);
    let revision = std::fs::read_to_string(repository.join("refs/main")).map_err(external)?;
    let revision = revision.trim();
    let model_link = repository
        .join("snapshots")
        .join(revision)
        .join("model.onnx");
    let artifact_sha256 = model_link
        .read_link()
        .ok()
        .and_then(|path| {
            path.file_name()
                .map(|name| name.to_string_lossy().into_owned())
        })
        .filter(|name| name.len() == 64 && name.chars().all(|ch| ch.is_ascii_hexdigit()))
        .ok_or_else(|| {
            ApplicationError::Invalid(
                "embedding model artifact has no verifiable SHA-256 cache identity".into(),
            )
        })?;
    Ok(make_descriptor(
        "fastembed-local",
        "sentence-transformers/all-MiniLM-L6-v2",
        revision,
        "fastembed-5.17.3/onnxruntime",
        &artifact_sha256,
        384,
        "mean-pooling; cosine-at-read; output-unit-norm-not-assumed",
        "symmetric input; no purpose prefix",
        true,
    ))
}

#[allow(clippy::too_many_arguments)]
fn make_descriptor(
    provider_id: &str,
    model_id: &str,
    model_version: &str,
    runtime_version: &str,
    artifact_sha256: &str,
    dimension: u32,
    normalization: &str,
    purpose_contract: &str,
    local: bool,
) -> EmbeddingModelDescriptor {
    let contract = format!(
        "{provider_id}\0{model_id}\0{model_version}\0{runtime_version}\0{artifact_sha256}\0{dimension}\0{normalization}\0{purpose_contract}\0{SEMANTIC_INDEX_SCHEMA_VERSION}"
    );
    EmbeddingModelDescriptor {
        provider_id: provider_id.into(),
        model_id: model_id.into(),
        model_version: model_version.into(),
        runtime_version: runtime_version.into(),
        artifact_sha256: artifact_sha256.into(),
        dimension,
        normalization: normalization.into(),
        purpose_contract: purpose_contract.into(),
        index_schema_version: SEMANTIC_INDEX_SCHEMA_VERSION,
        model_fingerprint: hex::encode(Sha256::digest(contract.as_bytes())),
        local,
    }
}

fn external(error: impl std::fmt::Display) -> ApplicationError {
    ApplicationError::ExternalProcess(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::{ManagedFastEmbedProvider, OpenAiCompatibleEmbeddingProvider};
    use application::EmbeddingProvider;
    use axum::{Json, Router, routing::post};
    use domain::{EmbeddingPurpose, SemanticEmbeddingStatus};
    use serde_json::{Value, json};

    #[tokio::test]
    async fn compatible_adapter_orders_vectors_and_keeps_space_explicit() {
        async fn embeddings(Json(body): Json<Value>) -> Json<Value> {
            assert_eq!(body["model"], "test-model");
            Json(json!({"data":[
                {"index":1,"embedding":[0.0,1.0]},
                {"index":0,"embedding":[1.0,0.0]}
            ]}))
        }
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(
                listener,
                Router::new().route("/v1/embeddings", post(embeddings)),
            )
            .await
            .unwrap();
        });
        let provider = OpenAiCompatibleEmbeddingProvider::new(
            &format!("http://{address}/v1"),
            None,
            "test-model",
            "revision-a",
            "fixture-1",
            2,
            "l2-normalized",
        )
        .unwrap();
        let vectors = provider
            .embed(EmbeddingPurpose::Document, &["a".into(), "b".into()])
            .await
            .unwrap();
        assert_eq!(vectors, vec![vec![1.0, 0.0], vec![0.0, 1.0]]);
        assert!(!provider.descriptor().unwrap().local);
    }

    #[test]
    fn enable_without_an_installed_model_reports_failed_capability() {
        let cache_dir =
            std::env::temp_dir().join(format!("llplayer-embedding-missing-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&cache_dir);
        let provider = ManagedFastEmbedProvider::new(cache_dir);

        assert!(provider.enable().is_err());
        assert_eq!(provider.status(), SemanticEmbeddingStatus::Failed);
    }
}
