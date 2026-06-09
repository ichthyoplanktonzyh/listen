use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use domain::*;
use thiserror::Error;

const DICTIONARY_CACHE_TTL_MS: u64 = 30 * 24 * 60 * 60 * 1000;

pub trait MediaRepository: Send + Sync {
    fn upsert(&self, media: &MediaItem) -> Result<MediaItem, ApplicationError>;
    fn get(&self, id: &MediaId) -> Result<Option<MediaItem>, ApplicationError>;
}

pub trait SubtitleRepository: Send + Sync {
    fn save_track(&self, track: &SubtitleTrack) -> Result<(), ApplicationError>;
    fn get_track(&self, id: &SubtitleTrackId) -> Result<Option<SubtitleTrack>, ApplicationError>;
    fn get_by_media_fingerprint(
        &self,
        media_id: &MediaId,
        fingerprint: &str,
    ) -> Result<Option<SubtitleTrack>, ApplicationError>;
    fn get_sentence(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SubtitleSentence>, ApplicationError>;
}

pub trait WordProfileRepository: Send + Sync {
    fn upsert(&self, profile: &WordProfile) -> Result<WordProfile, ApplicationError>;
    fn get_by_key(
        &self,
        language: &LanguageCode,
        normalized_lemma: &str,
    ) -> Result<Option<WordProfile>, ApplicationError>;
    fn get_many(
        &self,
        language: &LanguageCode,
        normalized_lemmas: &[String],
    ) -> Result<Vec<WordProfile>, ApplicationError>;
}

pub trait WordObservationRepository: Send + Sync {
    fn create(&self, observation: &WordObservation) -> Result<WordObservation, ApplicationError>;
    fn list_by_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordObservation>, ApplicationError>;
}

pub trait DictionaryCacheRepository: Send + Sync {
    fn put(&self, entry: &DictionaryEntry) -> Result<(), ApplicationError>;
    fn get(
        &self,
        language: &LanguageCode,
        normalized_lemma: &str,
        provider: &str,
    ) -> Result<Option<DictionaryEntry>, ApplicationError>;
}

pub trait PlaybackProgressRepository: Send + Sync {
    fn load(&self, media_id: &MediaId) -> Result<Option<TimeMs>, ApplicationError>;
    fn save(&self, media_id: &MediaId, position: TimeMs) -> Result<(), ApplicationError>;
}

#[async_trait]
pub trait DictionaryProvider: Send + Sync {
    fn name(&self) -> &'static str;
    async fn lookup(
        &self,
        language: &LanguageCode,
        lemma: &str,
    ) -> Result<Option<DictionaryLookup>, DictionaryProviderError>;
}

#[derive(Debug, Error)]
#[error("dictionary provider failed: {0}")]
pub struct DictionaryProviderError(pub String);

#[derive(Clone)]
pub struct AppServices {
    media: Arc<dyn MediaRepository>,
    progress: Arc<dyn PlaybackProgressRepository>,
    words: Arc<dyn WordProfileRepository>,
    observations: Arc<dyn WordObservationRepository>,
    subtitles: Arc<dyn SubtitleRepository>,
    dictionary: Arc<dyn DictionaryCacheRepository>,
}

impl AppServices {
    pub fn new(
        media: Arc<dyn MediaRepository>,
        progress: Arc<dyn PlaybackProgressRepository>,
        words: Arc<dyn WordProfileRepository>,
        observations: Arc<dyn WordObservationRepository>,
        subtitles: Arc<dyn SubtitleRepository>,
        dictionary: Arc<dyn DictionaryCacheRepository>,
    ) -> Self {
        Self {
            media,
            progress,
            words,
            observations,
            subtitles,
            dictionary,
        }
    }

    pub fn register_media(&self, input: RegisterMedia) -> Result<MediaItem, ApplicationError> {
        require_text(&input.path, "path")?;
        require_text(&input.fingerprint, "fingerprint")?;
        let now = now_ms();
        let id = MediaId::from_fingerprint("media", &input.fingerprint);
        let created_at_ms = self.media.get(&id)?.map_or(now, |m| m.created_at_ms);
        self.media.upsert(&MediaItem {
            id,
            path: input.path,
            fingerprint: input.fingerprint,
            title: input.title,
            kind: input.kind,
            duration: input.duration_ms.map(TimeMs::new),
            created_at_ms,
            updated_at_ms: now,
        })
    }

    pub fn read_media(&self, media_id: &MediaId) -> Result<Option<MediaItem>, ApplicationError> {
        self.media.get(media_id)
    }

    pub fn read_progress(&self, media_id: &MediaId) -> Result<Option<TimeMs>, ApplicationError> {
        self.progress.load(media_id)
    }

    pub fn update_progress(
        &self,
        media_id: &MediaId,
        position_ms: u64,
    ) -> Result<TimeMs, ApplicationError> {
        if self.media.get(media_id)?.is_none() {
            return Err(ApplicationError::NotFound("media"));
        }
        let position = TimeMs::new(position_ms);
        self.progress.save(media_id, position)?;
        Ok(position)
    }

    pub fn update_word_profile(
        &self,
        input: UpdateWordProfile,
    ) -> Result<WordProfile, ApplicationError> {
        let language = LanguageCode::parse(input.language)?;
        let normalized_lemma = normalize_lemma(&input.lemma);
        require_text(&normalized_lemma, "lemma")?;
        let profile = WordProfile {
            id: WordProfileId::from_fingerprint(
                "word-profile",
                &format!("{}:{normalized_lemma}", language.as_str()),
            ),
            language,
            lemma: input.lemma,
            normalized_lemma,
            display_form: input.display_form,
            status: input.status,
            updated_at_ms: now_ms(),
        };
        self.words.upsert(&profile)
    }

    pub fn read_word_profile(
        &self,
        language: &str,
        lemma: &str,
    ) -> Result<Option<WordProfile>, ApplicationError> {
        let language = LanguageCode::parse(language.to_owned())?;
        self.words.get_by_key(&language, &normalize_lemma(lemma))
    }

    pub fn read_word_profiles(
        &self,
        language: &str,
        lemmas: &[String],
    ) -> Result<Vec<WordProfile>, ApplicationError> {
        let language = LanguageCode::parse(language.to_owned())?;
        let normalized = lemmas
            .iter()
            .map(|lemma| normalize_lemma(lemma))
            .filter(|lemma| !lemma.is_empty())
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        self.words.get_many(&language, &normalized)
    }

    pub fn create_observation(
        &self,
        input: CreateWordObservation,
    ) -> Result<WordObservation, ApplicationError> {
        require_text(&input.original_form, "original_form")?;
        let created_at_ms = now_ms();
        self.observations.create(&WordObservation {
            id: WordObservationId::from_fingerprint(
                "word-observation",
                &format!(
                    "{}:{}:{created_at_ms}",
                    input.word_profile_id.as_str(),
                    input.sentence_id.as_str()
                ),
            ),
            word_profile_id: input.word_profile_id,
            sentence_id: input.sentence_id,
            original_form: input.original_form,
            result: input.result,
            created_at_ms,
        })
    }

    pub fn import_subtitle(
        &self,
        input: ImportSubtitle,
    ) -> Result<SubtitleTrack, ApplicationError> {
        if self.media.get(&input.media_id)?.is_none() {
            return Err(ApplicationError::NotFound("media"));
        }
        require_text(&input.source_name, "source_name")?;
        let language = input.language.map(LanguageCode::parse).transpose()?;
        let track = subtitle_core::import(subtitle_core::ImportSubtitle {
            media_id: input.media_id,
            source_name: input.source_name,
            content: input.content,
            language,
        })?;
        if let Some(existing) = self
            .subtitles
            .get_by_media_fingerprint(&track.media_id, &track.fingerprint)?
        {
            return Ok(existing);
        }
        self.subtitles.save_track(&track)?;
        Ok(track)
    }

    pub fn read_subtitle_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<SubtitleTrack>, ApplicationError> {
        self.subtitles.get_track(track_id)
    }

    pub async fn lookup_dictionary(
        &self,
        provider: &dyn DictionaryProvider,
        language: &str,
        lemma: &str,
    ) -> Result<Option<DictionaryLookup>, ApplicationError> {
        let language = LanguageCode::parse(language.to_owned())?;
        let normalized_lemma = normalize_lemma(lemma);
        require_text(&normalized_lemma, "lemma")?;
        if let Some(entry) = self
            .dictionary
            .get(&language, &normalized_lemma, provider.name())?
            .filter(|entry| now_ms().saturating_sub(entry.cached_at_ms) < DICTIONARY_CACHE_TTL_MS)
        {
            return serde_json::from_str(&entry.payload_json)
                .map(Some)
                .map_err(|error| ApplicationError::Repository(error.to_string()));
        }
        let Some(mut result) = provider.lookup(&language, &normalized_lemma).await? else {
            return Ok(None);
        };
        result.cached_at_ms = now_ms();
        self.dictionary.put(&DictionaryEntry {
            id: DictionaryEntryId::from_fingerprint(
                "dictionary",
                &format!(
                    "{}:{normalized_lemma}:{}",
                    language.as_str(),
                    provider.name()
                ),
            ),
            language,
            normalized_lemma,
            provider: provider.name().into(),
            payload_json: serde_json::to_string(&result)
                .map_err(|error| ApplicationError::Repository(error.to_string()))?,
            cached_at_ms: result.cached_at_ms,
        })?;
        Ok(Some(result))
    }

    pub fn diagnose_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<SentenceDiagnosis, ApplicationError> {
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let lemmas = sentence
            .tokens
            .iter()
            .filter_map(|token| token.normalized.clone())
            .collect::<Vec<_>>();
        let profiles = self.read_word_profiles("en", &lemmas)?;
        let observations = self.observations.list_by_sentence(sentence_id)?;
        Ok(diagnosis_core::diagnose(
            &sentence,
            &profiles,
            &observations,
        ))
    }
}

#[derive(Debug, Clone)]
pub struct RegisterMedia {
    pub path: String,
    pub fingerprint: String,
    pub title: String,
    pub kind: MediaKind,
    pub duration_ms: Option<u64>,
}

#[derive(Debug, Clone)]
pub struct UpdateWordProfile {
    pub language: String,
    pub lemma: String,
    pub display_form: String,
    pub status: Option<WordStatus>,
}

#[derive(Debug, Clone)]
pub struct CreateWordObservation {
    pub word_profile_id: WordProfileId,
    pub sentence_id: SubtitleSentenceId,
    pub original_form: String,
    pub result: ObservationResult,
}

#[derive(Debug, Clone)]
pub struct ImportSubtitle {
    pub media_id: MediaId,
    pub source_name: String,
    pub content: Vec<u8>,
    pub language: Option<String>,
}

#[derive(Debug, Error)]
pub enum ApplicationError {
    #[error("repository failure: {0}")]
    Repository(String),
    #[error("{0} was not found")]
    NotFound(&'static str),
    #[error("{0} must not be empty")]
    Validation(&'static str),
    #[error(transparent)]
    Domain(#[from] DomainError),
    #[error(transparent)]
    Subtitle(#[from] subtitle_core::SubtitleError),
    #[error(transparent)]
    DictionaryProvider(#[from] DictionaryProviderError),
}

fn require_text(value: &str, field: &'static str) -> Result<(), ApplicationError> {
    if value.trim().is_empty() {
        return Err(ApplicationError::Validation(field));
    }
    Ok(())
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock must be after UNIX epoch")
        .as_millis() as u64
}
