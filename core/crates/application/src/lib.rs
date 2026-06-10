use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use domain::*;
use thiserror::Error;

const DICTIONARY_CACHE_TTL_MS: u64 = 30 * 24 * 60 * 60 * 1000;

pub trait MediaRepository: Send + Sync {
    fn upsert(&self, media: &MediaItem) -> Result<MediaItem, ApplicationError>;
    fn get(&self, id: &MediaId) -> Result<Option<MediaItem>, ApplicationError>;
    fn set_availability(
        &self,
        id: &MediaId,
        availability: MediaAvailability,
    ) -> Result<MediaItem, ApplicationError>;
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
    fn clear(
        &self,
        word_profile_id: &WordProfileId,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<(), ApplicationError>;
}

pub trait VocabularyAssetRepository: Send + Sync {
    fn apply_status(
        &self,
        profile: &WordProfile,
        source: Option<&SourceContext>,
        change_source: WordChangeSource,
    ) -> Result<WordDetails, ApplicationError>;
    fn capture_occurrence(
        &self,
        profile: &WordProfile,
        source: &SourceContext,
    ) -> Result<WordOccurrence, ApplicationError>;
    fn list_vocabulary(
        &self,
        language: &LanguageCode,
        status: WordStatus,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<WordDetails>, ApplicationError>;
    fn details(&self, id: &WordProfileId) -> Result<Option<WordDetails>, ApplicationError>;
    fn export_assets(&self) -> Result<VocabularyAssetBundle, ApplicationError>;
    fn import_assets(&self, bundle: &VocabularyAssetBundle) -> Result<(), ApplicationError>;
    fn update_learning_content(
        &self,
        id: &WordProfileId,
        user_definition: Option<String>,
        personal_note: Option<String>,
        updated_at_ms: u64,
    ) -> Result<WordDetails, ApplicationError>;
    fn import_external(
        &self,
        input: &ExternalVocabularyImport,
        imported_at_ms: u64,
    ) -> Result<ExternalVocabularyImportSummary, ApplicationError>;
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

pub trait TranscriptionRepository: Send + Sync {
    fn upsert_model(
        &self,
        model: &TranscriptionModelDescriptor,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError>;
    fn list_models(&self) -> Result<Vec<TranscriptionModelDescriptor>, ApplicationError>;
    fn get_model(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<Option<TranscriptionModelDescriptor>, ApplicationError>;
    fn delete_model(&self, id: &TranscriptionModelId) -> Result<(), ApplicationError>;
    fn create_job(&self, job: &TranscriptionJob) -> Result<TranscriptionJob, ApplicationError>;
    fn update_job(&self, job: &TranscriptionJob) -> Result<TranscriptionJob, ApplicationError>;
    fn get_job(
        &self,
        id: &TranscriptionJobId,
    ) -> Result<Option<TranscriptionJob>, ApplicationError>;
    fn list_jobs(&self) -> Result<Vec<TranscriptionJob>, ApplicationError>;
    fn find_completed_job(
        &self,
        input_fingerprint: &str,
    ) -> Result<Option<TranscriptionJob>, ApplicationError>;
    fn interrupt_active_jobs(&self, updated_at_ms: u64) -> Result<(), ApplicationError>;
    fn save_provenance(&self, provenance: &SubtitleTrackProvenance)
    -> Result<(), ApplicationError>;
}

#[async_trait]
pub trait DictionaryProvider: Send + Sync {
    fn info(&self) -> DictionaryProviderInfo;
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
    vocabulary: Arc<dyn VocabularyAssetRepository>,
}

impl AppServices {
    pub fn new(
        media: Arc<dyn MediaRepository>,
        progress: Arc<dyn PlaybackProgressRepository>,
        words: Arc<dyn WordProfileRepository>,
        observations: Arc<dyn WordObservationRepository>,
        subtitles: Arc<dyn SubtitleRepository>,
        dictionary: Arc<dyn DictionaryCacheRepository>,
        vocabulary: Arc<dyn VocabularyAssetRepository>,
    ) -> Self {
        Self {
            media,
            progress,
            words,
            observations,
            subtitles,
            dictionary,
            vocabulary,
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
            availability: MediaAvailability::Available,
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
            user_definition: None,
            personal_note: None,
            learning_updated_at_ms: 0,
        };
        if let Some(source) = input.source.as_ref()
            && (source.language != profile.language
                || normalize_lemma(&source.normalized_lemma) != profile.normalized_lemma
                || source.end_ms < source.start_ms)
        {
            return Err(ApplicationError::Validation("source context"));
        }
        self.vocabulary
            .apply_status(
                &profile,
                input.source.as_ref(),
                WordChangeSource::UserSelection,
            )
            .map(|details| details.profile)
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
        let source_profile = input
            .source
            .as_ref()
            .map(|source| {
                let profile = self
                    .vocabulary
                    .details(&input.word_profile_id)?
                    .map(|details| details.profile)
                    .ok_or(ApplicationError::NotFound("word profile"))?;
                if source.language != profile.language
                    || normalize_lemma(&source.normalized_lemma) != profile.normalized_lemma
                    || source.end_ms < source.start_ms
                {
                    return Err(ApplicationError::Validation("source context"));
                }
                Ok(profile)
            })
            .transpose()?;
        let created_at_ms = now_ms();
        let observation = self.observations.create(&WordObservation {
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
        })?;
        if let (Some(source), Some(profile)) = (input.source.as_ref(), source_profile.as_ref()) {
            self.vocabulary.capture_occurrence(profile, source)?;
        }
        Ok(observation)
    }

    pub fn clear_observation(
        &self,
        word_profile_id: &WordProfileId,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<(), ApplicationError> {
        self.observations.clear(word_profile_id, sentence_id)
    }

    pub fn list_vocabulary(
        &self,
        language: &str,
        status: WordStatus,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<WordDetails>, ApplicationError> {
        self.vocabulary.list_vocabulary(
            &LanguageCode::parse(language)?,
            status,
            search,
            limit.min(200),
            offset,
        )
    }

    pub fn word_details(
        &self,
        id: &WordProfileId,
    ) -> Result<Option<WordDetails>, ApplicationError> {
        self.vocabulary.details(id)
    }

    pub fn export_vocabulary(&self) -> Result<VocabularyAssetBundle, ApplicationError> {
        self.vocabulary.export_assets()
    }

    pub fn import_vocabulary(
        &self,
        bundle: &VocabularyAssetBundle,
    ) -> Result<(), ApplicationError> {
        if bundle.version != 1 && bundle.version != 2 {
            return Err(ApplicationError::Validation(
                "unsupported asset bundle version",
            ));
        }
        self.vocabulary.import_assets(bundle)
    }

    pub fn set_media_availability(
        &self,
        id: &MediaId,
        availability: MediaAvailability,
    ) -> Result<MediaItem, ApplicationError> {
        self.media.set_availability(id, availability)
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
            identity_salt: input.identity_salt,
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
        providers: &[Arc<dyn DictionaryProvider>],
        language: &str,
        lemma: &str,
    ) -> Result<DictionaryLookupBundle, ApplicationError> {
        let language = LanguageCode::parse(language.to_owned())?;
        let normalized_lemma = normalize_lemma(lemma);
        require_text(&normalized_lemma, "lemma")?;
        let mut results = Vec::with_capacity(providers.len());
        for provider in providers {
            let info = provider.info();
            if !info
                .supported_languages
                .iter()
                .any(|value| value == language.as_str())
            {
                continue;
            }
            if let Some(entry) = self
                .dictionary
                .get(&language, &normalized_lemma, &info.id)?
                .filter(|entry| {
                    now_ms().saturating_sub(entry.cached_at_ms) < DICTIONARY_CACHE_TTL_MS
                })
            {
                let lookup = serde_json::from_str(&entry.payload_json)
                    .map_err(|error| ApplicationError::Repository(error.to_string()))?;
                results.push(DictionaryProviderResult {
                    provider: info,
                    lookup: Some(lookup),
                    error: None,
                });
                continue;
            }
            match provider.lookup(&language, &normalized_lemma).await {
                Ok(Some(mut lookup)) => {
                    lookup.cached_at_ms = now_ms();
                    self.dictionary.put(&DictionaryEntry {
                        id: DictionaryEntryId::from_fingerprint(
                            "dictionary",
                            &format!("{}:{normalized_lemma}:{}", language.as_str(), info.id),
                        ),
                        language: language.clone(),
                        normalized_lemma: normalized_lemma.clone(),
                        provider: info.id.clone(),
                        payload_json: serde_json::to_string(&lookup)
                            .map_err(|error| ApplicationError::Repository(error.to_string()))?,
                        cached_at_ms: lookup.cached_at_ms,
                    })?;
                    results.push(DictionaryProviderResult {
                        provider: info,
                        lookup: Some(lookup),
                        error: None,
                    });
                }
                Ok(None) => results.push(DictionaryProviderResult {
                    provider: info,
                    lookup: None,
                    error: None,
                }),
                Err(error) => results.push(DictionaryProviderResult {
                    provider: info,
                    lookup: None,
                    error: Some(error.to_string()),
                }),
            }
        }
        Ok(DictionaryLookupBundle {
            query: lemma.to_owned(),
            normalized_lemma,
            results,
        })
    }

    pub fn update_word_learning_content(
        &self,
        id: &WordProfileId,
        user_definition: Option<String>,
        personal_note: Option<String>,
    ) -> Result<WordDetails, ApplicationError> {
        self.vocabulary.update_learning_content(
            id,
            clean_optional(user_definition),
            clean_optional(personal_note),
            now_ms(),
        )
    }

    pub fn import_external_vocabulary(
        &self,
        input: &ExternalVocabularyImport,
    ) -> Result<ExternalVocabularyImportSummary, ApplicationError> {
        LanguageCode::parse(input.language.clone())?;
        self.vocabulary.import_external(input, now_ms())
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
    pub source: Option<SourceContext>,
}

#[derive(Debug, Clone)]
pub struct CreateWordObservation {
    pub word_profile_id: WordProfileId,
    pub sentence_id: SubtitleSentenceId,
    pub original_form: String,
    pub result: ObservationResult,
    pub source: Option<SourceContext>,
}

#[derive(Debug, Clone)]
pub struct SourceContext {
    pub language: LanguageCode,
    pub normalized_lemma: String,
    pub media_id: Option<MediaId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub original_form: String,
    pub sentence_text: String,
    pub media_title: String,
    pub media_fingerprint: String,
    pub start_ms: u64,
    pub end_ms: u64,
}

#[derive(Debug, Clone)]
pub struct ImportSubtitle {
    pub media_id: MediaId,
    pub source_name: String,
    pub content: Vec<u8>,
    pub language: Option<String>,
    pub identity_salt: Option<String>,
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

fn clean_optional(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let value = value.trim().to_owned();
        (!value.is_empty()).then_some(value)
    })
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock must be after UNIX epoch")
        .as_millis() as u64
}
