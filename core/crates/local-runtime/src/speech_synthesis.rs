use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock, Weak};

use application::{
    ProviderSynthesisOutput, ProviderSynthesisRequest, SpeechSynthesisError,
    SpeechSynthesisLocality, SpeechSynthesisProvider, SpeechSynthesisProviderDescriptor,
    SpeechSynthesisVoice,
};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::process::Command;
use tokio::sync::Mutex;

const CONTRACT_VERSION: &str = "speech-synthesis-v1";
const DEFAULT_RATE: u16 = 180;
const MAX_TEXT_SCALARS: usize = 5_000;
static TEMPORARY_SEQUENCE: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpeechSynthesisCapabilityView {
    pub status: String,
    pub providers: Vec<SpeechSynthesisProviderDescriptor>,
    pub voices: Vec<SpeechSynthesisVoice>,
    pub cache_bytes: u64,
    pub cache_entries: u64,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpeechSynthesisRequest {
    pub text: String,
    pub language: String,
    #[serde(default)]
    pub provider_id: Option<String>,
    #[serde(default)]
    pub voice_id: Option<String>,
    #[serde(default = "default_rate")]
    pub rate_words_per_minute: u16,
    #[serde(default)]
    pub purpose: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpeechSynthesisAsset {
    pub audio_path: String,
    pub mime_type: String,
    pub provider_id: String,
    pub provider_version: String,
    pub voice_id: String,
    pub language: String,
    pub rate_words_per_minute: u16,
    pub purpose: Option<String>,
    pub content_hash: String,
    pub cache_hit: bool,
    pub synthetic: bool,
}

#[derive(Debug)]
pub struct SpeechSynthesisManager {
    cache_root: PathBuf,
    providers: Vec<Arc<dyn SpeechSynthesisProvider>>,
    flights: Mutex<HashMap<String, Weak<Mutex<()>>>>,
}

impl SpeechSynthesisManager {
    pub fn new(
        cache_root: impl Into<PathBuf>,
        providers: Vec<Arc<dyn SpeechSynthesisProvider>>,
    ) -> Arc<Self> {
        Arc::new(Self {
            cache_root: cache_root.into(),
            providers,
            flights: Mutex::new(HashMap::new()),
        })
    }

    pub fn system_default(cache_root: impl Into<PathBuf>) -> Arc<Self> {
        let providers: Vec<Arc<dyn SpeechSynthesisProvider>> = if cfg!(target_os = "macos") {
            vec![Arc::new(MacOsSystemSpeechProvider::default())]
        } else {
            Vec::new()
        };
        Self::new(cache_root, providers)
    }

    pub async fn capability(&self) -> SpeechSynthesisCapabilityView {
        let mut descriptors = Vec::new();
        let mut voices = Vec::new();
        let mut last_error = None;
        for provider in &self.providers {
            let descriptor = provider.descriptor();
            match provider.voices().await {
                Ok(mut available) if !available.is_empty() => {
                    available.retain(|voice| voice.provider_id == descriptor.id);
                    if available.is_empty() {
                        last_error =
                            Some("provider reported voices with mismatched identity".into());
                    } else {
                        descriptors.push(descriptor);
                        voices.append(&mut available);
                    }
                }
                Ok(_) => last_error = Some("provider reported no installed voices".into()),
                Err(error) => last_error = Some(error.to_string()),
            }
        }
        let (cache_entries, cache_bytes) = cache_stats(&self.cache_root);
        SpeechSynthesisCapabilityView {
            status: if descriptors.is_empty() {
                "unavailable".into()
            } else {
                "ready".into()
            },
            providers: descriptors,
            voices,
            cache_bytes,
            cache_entries,
            error: last_error,
        }
    }

    pub async fn synthesize(
        &self,
        request: SpeechSynthesisRequest,
    ) -> Result<SpeechSynthesisAsset, SpeechSynthesisError> {
        let text = request.text.trim();
        if text.is_empty() {
            return Err(SpeechSynthesisError::InvalidRequest(
                "text must not be empty".into(),
            ));
        }
        if text.chars().count() > MAX_TEXT_SCALARS {
            return Err(SpeechSynthesisError::InvalidRequest(format!(
                "text exceeds {MAX_TEXT_SCALARS} Unicode scalars"
            )));
        }
        let language = normalize_language(&request.language)?;
        if !(80..=450).contains(&request.rate_words_per_minute) {
            return Err(SpeechSynthesisError::InvalidRequest(
                "rate_words_per_minute must be between 80 and 450".into(),
            ));
        }
        let (provider, voice) = self
            .resolve_provider_voice(
                request.provider_id.as_deref(),
                request.voice_id.as_deref(),
                &language,
            )
            .await?;
        let descriptor = provider.descriptor();
        let content_hash = cache_key(
            &descriptor,
            &voice,
            &language,
            request.rate_words_per_minute,
            text,
        );
        let flight = {
            let mut flights = self.flights.lock().await;
            flights.retain(|_, flight| flight.strong_count() > 0);
            if let Some(active) = flights.get(&content_hash).and_then(Weak::upgrade) {
                active
            } else {
                let created = Arc::new(Mutex::new(()));
                flights.insert(content_hash.clone(), Arc::downgrade(&created));
                created
            }
        };
        let _guard = flight.lock().await;
        let base = self.cache_root.join(&content_hash);
        if let Some((path, mime_type)) = existing_asset(&base) {
            return Ok(asset_view(
                path,
                mime_type,
                descriptor,
                voice,
                language,
                request,
                content_hash,
                true,
            ));
        }
        let output = provider
            .synthesize(&ProviderSynthesisRequest {
                text: text.into(),
                language: language.clone(),
                voice_id: voice.id.clone(),
                rate_words_per_minute: request.rate_words_per_minute,
            })
            .await?;
        if output.bytes.is_empty() {
            return Err(SpeechSynthesisError::Provider(
                "provider returned an empty audio file".into(),
            ));
        }
        tokio::fs::create_dir_all(&self.cache_root)
            .await
            .map_err(|error| SpeechSynthesisError::Cache(error.to_string()))?;
        let path = base.with_extension(&output.file_extension);
        let temporary = base.with_extension(format!("{}.tmp", output.file_extension));
        tokio::fs::write(&temporary, &output.bytes)
            .await
            .map_err(|error| SpeechSynthesisError::Cache(error.to_string()))?;
        if let Err(error) = tokio::fs::rename(&temporary, &path).await {
            let _ = tokio::fs::remove_file(&temporary).await;
            return Err(SpeechSynthesisError::Cache(error.to_string()));
        }
        Ok(asset_view(
            path,
            output.mime_type,
            descriptor,
            voice,
            language,
            request,
            content_hash,
            false,
        ))
    }

    pub async fn clear_cache(&self) -> Result<SpeechSynthesisCapabilityView, SpeechSynthesisError> {
        if self.cache_root.exists() {
            tokio::fs::remove_dir_all(&self.cache_root)
                .await
                .map_err(|error| SpeechSynthesisError::Cache(error.to_string()))?;
        }
        Ok(self.capability().await)
    }

    async fn resolve_provider_voice(
        &self,
        provider_id: Option<&str>,
        voice_id: Option<&str>,
        language: &str,
    ) -> Result<(Arc<dyn SpeechSynthesisProvider>, SpeechSynthesisVoice), SpeechSynthesisError>
    {
        for provider in &self.providers {
            let descriptor = provider.descriptor();
            if provider_id.is_some_and(|id| id != descriptor.id) {
                continue;
            }
            let voices = provider
                .voices()
                .await?
                .into_iter()
                .filter(|voice| voice.provider_id == descriptor.id)
                .collect::<Vec<_>>();
            if let Some(id) = voice_id {
                if let Some(voice) = voices.into_iter().find(|voice| voice.id == id) {
                    if language_matches(&voice.language, language) {
                        return Ok((provider.clone(), voice));
                    }
                    return Err(SpeechSynthesisError::UnsupportedLanguage(language.into()));
                }
                return Err(SpeechSynthesisError::VoiceUnavailable(id.into()));
            }
            if let Some(voice) = voices
                .into_iter()
                .find(|voice| language_matches(&voice.language, language))
            {
                return Ok((provider.clone(), voice));
            }
        }
        if provider_id.is_some() {
            Err(SpeechSynthesisError::Unavailable(
                "requested provider is unavailable".into(),
            ))
        } else {
            Err(SpeechSynthesisError::UnsupportedLanguage(language.into()))
        }
    }
}

#[derive(Debug, Default)]
pub struct MacOsSystemSpeechProvider {
    voices: OnceLock<Vec<SpeechSynthesisVoice>>,
}

#[async_trait]
impl SpeechSynthesisProvider for MacOsSystemSpeechProvider {
    fn descriptor(&self) -> SpeechSynthesisProviderDescriptor {
        SpeechSynthesisProviderDescriptor {
            id: "macos-system-speech".into(),
            display_name: "macOS System Speech".into(),
            version: "say-v1".into(),
            locality: SpeechSynthesisLocality::Local,
        }
    }

    async fn voices(&self) -> Result<Vec<SpeechSynthesisVoice>, SpeechSynthesisError> {
        if let Some(voices) = self.voices.get() {
            return Ok(voices.clone());
        }
        if !Path::new("/usr/bin/say").is_file() {
            return Err(SpeechSynthesisError::Unavailable(
                "/usr/bin/say is missing".into(),
            ));
        }
        let output = Command::new("/usr/bin/say")
            .args(["-v", "?"])
            .kill_on_drop(true)
            .output()
            .await
            .map_err(|error| SpeechSynthesisError::Unavailable(error.to_string()))?;
        if !output.status.success() {
            return Err(SpeechSynthesisError::Unavailable(
                String::from_utf8_lossy(&output.stderr).trim().into(),
            ));
        }
        let parsed = parse_macos_voices(&String::from_utf8_lossy(&output.stdout));
        if parsed.is_empty() {
            return Err(SpeechSynthesisError::Unavailable(
                "macOS reported no installed voices".into(),
            ));
        }
        let _ = self.voices.set(parsed.clone());
        Ok(parsed)
    }

    async fn synthesize(
        &self,
        request: &ProviderSynthesisRequest,
    ) -> Result<ProviderSynthesisOutput, SpeechSynthesisError> {
        let temporary = std::env::temp_dir().join(format!(
            "llplayer-tts-{}-{}-{}.aiff",
            std::process::id(),
            TEMPORARY_SEQUENCE.fetch_add(1, Ordering::Relaxed),
            short_hash(request.text.as_bytes())
        ));
        let rate = request.rate_words_per_minute.to_string();
        let output = Command::new("/usr/bin/say")
            .args(["-v", &request.voice_id, "-r", &rate, "-o"])
            .arg(&temporary)
            .arg(&request.text)
            .kill_on_drop(true)
            .output()
            .await
            .map_err(|error| SpeechSynthesisError::Provider(error.to_string()))?;
        if !output.status.success() {
            let _ = tokio::fs::remove_file(&temporary).await;
            return Err(SpeechSynthesisError::Provider(
                String::from_utf8_lossy(&output.stderr)
                    .chars()
                    .take(800)
                    .collect(),
            ));
        }
        let bytes = tokio::fs::read(&temporary)
            .await
            .map_err(|error| SpeechSynthesisError::Provider(error.to_string()))?;
        let _ = tokio::fs::remove_file(&temporary).await;
        Ok(ProviderSynthesisOutput {
            bytes,
            file_extension: "aiff".into(),
            mime_type: "audio/aiff".into(),
        })
    }
}

fn default_rate() -> u16 {
    DEFAULT_RATE
}

fn normalize_language(value: &str) -> Result<String, SpeechSynthesisError> {
    let value = value.trim().replace('_', "-");
    if value.is_empty() || !value.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err(SpeechSynthesisError::InvalidRequest(
            "language must be a BCP-47-style tag".into(),
        ));
    }
    Ok(value)
}

fn language_matches(voice: &str, requested: &str) -> bool {
    let voice = voice.replace('_', "-").to_ascii_lowercase();
    let requested = requested.to_ascii_lowercase();
    voice == requested || voice.split('-').next() == requested.split('-').next()
}

fn parse_macos_voices(output: &str) -> Vec<SpeechSynthesisVoice> {
    output
        .lines()
        .filter_map(|line| {
            let before_sample = line.split('#').next()?.trim_end();
            let mut fields = before_sample.split_whitespace().collect::<Vec<_>>();
            let language = fields.pop()?;
            if !language.contains('_') || fields.is_empty() {
                return None;
            }
            let display_name = fields.join(" ");
            Some(SpeechSynthesisVoice {
                id: display_name.clone(),
                provider_id: "macos-system-speech".into(),
                display_name,
                language: language.replace('_', "-"),
            })
        })
        .collect()
}

fn cache_key(
    provider: &SpeechSynthesisProviderDescriptor,
    voice: &SpeechSynthesisVoice,
    language: &str,
    rate: u16,
    text: &str,
) -> String {
    let rate = rate.to_string();
    let mut digest = Sha256::new();
    for value in [
        CONTRACT_VERSION,
        &provider.id,
        &provider.version,
        &voice.id,
        language,
        &rate,
        text,
    ] {
        digest.update(value.as_bytes());
        digest.update(b"\0");
    }
    hex::encode(digest.finalize())
}

fn short_hash(value: &[u8]) -> String {
    hex::encode(Sha256::digest(value))[..16].to_string()
}

fn existing_asset(base: &Path) -> Option<(PathBuf, String)> {
    for (extension, mime) in [
        ("aiff", "audio/aiff"),
        ("wav", "audio/wav"),
        ("m4a", "audio/mp4"),
    ] {
        let path = base.with_extension(extension);
        if path.metadata().is_ok_and(|metadata| metadata.len() > 0) {
            return Some((path, mime.into()));
        }
    }
    None
}

#[allow(clippy::too_many_arguments)]
fn asset_view(
    path: PathBuf,
    mime_type: String,
    provider: SpeechSynthesisProviderDescriptor,
    voice: SpeechSynthesisVoice,
    language: String,
    request: SpeechSynthesisRequest,
    content_hash: String,
    cache_hit: bool,
) -> SpeechSynthesisAsset {
    SpeechSynthesisAsset {
        audio_path: path.to_string_lossy().into_owned(),
        mime_type,
        provider_id: provider.id,
        provider_version: provider.version,
        voice_id: voice.id,
        language,
        rate_words_per_minute: request.rate_words_per_minute,
        purpose: request.purpose,
        content_hash,
        cache_hit,
        synthetic: true,
    }
}

fn cache_stats(root: &Path) -> (u64, u64) {
    let Ok(entries) = std::fs::read_dir(root) else {
        return (0, 0);
    };
    entries
        .flatten()
        .fold((0, 0), |(count, bytes), entry| match entry.metadata() {
            Ok(metadata)
                if metadata.is_file()
                    && entry.path().extension().is_none_or(|ext| ext != "tmp") =>
            {
                (count + 1, bytes + metadata.len())
            }
            _ => (count, bytes),
        })
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;

    #[derive(Debug)]
    struct FakeProvider {
        calls: AtomicUsize,
        fail: bool,
    }

    #[async_trait]
    impl SpeechSynthesisProvider for FakeProvider {
        fn descriptor(&self) -> SpeechSynthesisProviderDescriptor {
            SpeechSynthesisProviderDescriptor {
                id: "fake-local".into(),
                display_name: "Fake".into(),
                version: "1".into(),
                locality: SpeechSynthesisLocality::Local,
            }
        }

        async fn voices(&self) -> Result<Vec<SpeechSynthesisVoice>, SpeechSynthesisError> {
            Ok(vec![SpeechSynthesisVoice {
                id: "voice-en".into(),
                provider_id: "fake-local".into(),
                display_name: "Voice".into(),
                language: "en-US".into(),
            }])
        }

        async fn synthesize(
            &self,
            _request: &ProviderSynthesisRequest,
        ) -> Result<ProviderSynthesisOutput, SpeechSynthesisError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            if self.fail {
                return Err(SpeechSynthesisError::Provider("boom".into()));
            }
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
            Ok(ProviderSynthesisOutput {
                bytes: b"FORMfake".to_vec(),
                file_extension: "aiff".into(),
                mime_type: "audio/aiff".into(),
            })
        }
    }

    fn request(text: &str) -> SpeechSynthesisRequest {
        SpeechSynthesisRequest {
            text: text.into(),
            language: "en-US".into(),
            provider_id: None,
            voice_id: None,
            rate_words_per_minute: 180,
            purpose: Some("test".into()),
        }
    }

    fn root(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "llplayer-tts-{name}-{}",
            short_hash(format!("{}-{name}", std::process::id()).as_bytes())
        ))
    }

    #[tokio::test]
    async fn cache_identity_hit_and_clear_are_observable_through_manager() {
        let root = root("cache");
        let provider = Arc::new(FakeProvider {
            calls: AtomicUsize::new(0),
            fail: false,
        });
        let manager = SpeechSynthesisManager::new(&root, vec![provider.clone()]);
        let first = manager.synthesize(request("hello")).await.unwrap();
        let second = manager.synthesize(request("hello")).await.unwrap();
        assert!(!first.cache_hit);
        assert!(second.cache_hit);
        assert_eq!(first.content_hash, second.content_hash);
        assert_eq!(provider.calls.load(Ordering::SeqCst), 1);
        assert_eq!(manager.capability().await.cache_entries, 1);
        assert_eq!(manager.clear_cache().await.unwrap().cache_entries, 0);
    }

    #[tokio::test]
    async fn concurrent_same_request_is_single_flight() {
        let root = root("flight");
        let provider = Arc::new(FakeProvider {
            calls: AtomicUsize::new(0),
            fail: false,
        });
        let manager = SpeechSynthesisManager::new(&root, vec![provider.clone()]);
        let (left, right) = tokio::join!(
            manager.synthesize(request("same")),
            manager.synthesize(request("same"))
        );
        assert!(left.is_ok() && right.is_ok());
        assert_eq!(provider.calls.load(Ordering::SeqCst), 1);
        assert_ne!(left.unwrap().cache_hit, right.unwrap().cache_hit);
    }

    #[tokio::test]
    async fn provider_failure_leaves_no_cache_asset() {
        let root = root("failure");
        let manager = SpeechSynthesisManager::new(
            &root,
            vec![Arc::new(FakeProvider {
                calls: AtomicUsize::new(0),
                fail: true,
            })],
        );
        assert!(manager.synthesize(request("failure")).await.is_err());
        assert_eq!(cache_stats(&root), (0, 0));
    }

    #[test]
    fn macos_voice_parser_preserves_names_with_spaces() {
        let voices = parse_macos_voices(
            "Samantha            en_US    # Hello\nEddy (英语（美国）)       en_US    # Hello\n",
        );
        assert_eq!(voices[0].id, "Samantha");
        assert_eq!(voices[1].id, "Eddy (英语（美国）)");
        assert_eq!(voices[1].language, "en-US");
    }

    #[cfg(target_os = "macos")]
    #[tokio::test]
    async fn macos_system_provider_produces_nonempty_offline_audio() {
        let root = root("macos-system");
        let manager = SpeechSynthesisManager::system_default(&root);
        let asset = manager
            .synthesize(SpeechSynthesisRequest {
                text: "Local speech synthesis smoke test.".into(),
                language: "en-US".into(),
                provider_id: Some("macos-system-speech".into()),
                voice_id: None,
                rate_words_per_minute: 180,
                purpose: Some("system_smoke_test".into()),
            })
            .await
            .unwrap();
        assert_eq!(asset.provider_id, "macos-system-speech");
        assert!(asset.synthetic);
        assert!(std::fs::metadata(&asset.audio_path).unwrap().len() > 1_000);
        manager.clear_cache().await.unwrap();
    }
}
