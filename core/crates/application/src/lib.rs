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

pub trait LexicalEntryRepository: Send + Sync {
    fn upsert_lexical_entry(
        &self,
        entry: &LexicalEntry,
        source: Option<&LexicalSourceContext>,
        change_source: WordChangeSource,
    ) -> Result<LexicalEntryDetails, ApplicationError>;
    fn lexical_details(
        &self,
        id: &LexicalEntryId,
    ) -> Result<Option<LexicalEntryDetails>, ApplicationError>;
    fn list_lexical_entries(
        &self,
        language: &LanguageCode,
        kind: Option<LexicalEntryKind>,
        status: Option<WordStatus>,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LexicalEntryDetails>, ApplicationError>;
    fn set_lemma_override(
        &self,
        language: &LanguageCode,
        original_normalized: &str,
        corrected_normalized: &str,
        updated_at_ms: u64,
    ) -> Result<(), ApplicationError>;
    fn lemma_override(
        &self,
        language: &LanguageCode,
        original_normalized: &str,
    ) -> Result<Option<String>, ApplicationError>;
    fn lexical_entry_by_key(
        &self,
        language: &LanguageCode,
        kind: LexicalEntryKind,
        normalized_form: &str,
    ) -> Result<Option<LexicalEntry>, ApplicationError>;
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

pub trait LexicalNormalizationProvider: Send + Sync {
    fn provider_id(&self) -> &'static str;
    fn version(&self) -> &str;
    fn normalize(
        &self,
        language: &LanguageCode,
        value: &str,
    ) -> Result<Option<String>, LexicalNormalizationProviderError>;
    fn phrase_candidates(
        &self,
        language: &LanguageCode,
        sentence: &SubtitleSentence,
    ) -> Result<Vec<PhraseCandidate>, LexicalNormalizationProviderError>;
}

#[derive(Debug, Error)]
#[error("lexical normalization provider failed: {0}")]
pub struct LexicalNormalizationProviderError(pub String);

#[derive(Clone)]
pub struct AppServices {
    media: Arc<dyn MediaRepository>,
    progress: Arc<dyn PlaybackProgressRepository>,
    words: Arc<dyn WordProfileRepository>,
    observations: Arc<dyn WordObservationRepository>,
    subtitles: Arc<dyn SubtitleRepository>,
    dictionary: Arc<dyn DictionaryCacheRepository>,
    vocabulary: Arc<dyn VocabularyAssetRepository>,
    lexical: Arc<dyn LexicalEntryRepository>,
    lexical_normalizers: Arc<Vec<Arc<dyn LexicalNormalizationProvider>>>,
}

impl AppServices {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        media: Arc<dyn MediaRepository>,
        progress: Arc<dyn PlaybackProgressRepository>,
        words: Arc<dyn WordProfileRepository>,
        observations: Arc<dyn WordObservationRepository>,
        subtitles: Arc<dyn SubtitleRepository>,
        dictionary: Arc<dyn DictionaryCacheRepository>,
        vocabulary: Arc<dyn VocabularyAssetRepository>,
        lexical: Arc<dyn LexicalEntryRepository>,
    ) -> Self {
        Self {
            media,
            progress,
            words,
            observations,
            subtitles,
            dictionary,
            vocabulary,
            lexical,
            lexical_normalizers: Arc::new(Vec::new()),
        }
    }

    pub fn with_lexical_normalizers(
        mut self,
        providers: Vec<Arc<dyn LexicalNormalizationProvider>>,
    ) -> Self {
        self.lexical_normalizers = Arc::new(providers);
        self
    }

    pub fn normalize_lexical_form(
        &self,
        language: &str,
        value: &str,
    ) -> Result<LexicalNormalization, ApplicationError> {
        let language = LanguageCode::parse(language)?;
        let original = normalize_lemma(value);
        require_text(&original, "value")?;
        if let Some(corrected) = self.lexical.lemma_override(&language, &original)? {
            return Ok(LexicalNormalization {
                original,
                normalized: corrected,
                provider: "user".into(),
                version: "v1".into(),
                user_corrected: true,
            });
        }
        for provider in self.lexical_normalizers.iter() {
            if let Some(normalized) = provider
                .normalize(&language, &original)
                .map_err(ApplicationError::LexicalNormalizationProvider)?
            {
                return Ok(LexicalNormalization {
                    original,
                    normalized,
                    provider: provider.provider_id().into(),
                    version: provider.version().into(),
                    user_corrected: false,
                });
            }
        }
        let normalized = normalize_american_english(&original);
        Ok(LexicalNormalization {
            original,
            normalized,
            provider: "en-us-rules".into(),
            version: "v1".into(),
            user_corrected: false,
        })
    }

    pub fn correct_lemma(
        &self,
        language: &str,
        original: &str,
        corrected: &str,
    ) -> Result<LexicalNormalization, ApplicationError> {
        let language = LanguageCode::parse(language)?;
        let original = normalize_lemma(original);
        let corrected = normalize_lemma(corrected);
        require_text(&original, "original")?;
        require_text(&corrected, "corrected")?;
        let original_entry =
            self.lexical
                .lexical_entry_by_key(&language, LexicalEntryKind::Word, &original)?;
        let corrected_entry =
            self.lexical
                .lexical_entry_by_key(&language, LexicalEntryKind::Word, &corrected)?;
        if let (Some(original_entry), Some(corrected_entry)) = (original_entry, corrected_entry)
            && original_entry.id != corrected_entry.id
        {
            return Err(ApplicationError::Conflict(
                "lemma correction target already has a separate word asset",
            ));
        }
        self.lexical
            .set_lemma_override(&language, &original, &corrected, now_ms())?;
        Ok(LexicalNormalization {
            original,
            normalized: corrected,
            provider: "user".into(),
            version: "v1".into(),
            user_corrected: true,
        })
    }

    pub fn create_lexical_entry(
        &self,
        input: UpsertLexicalEntry,
    ) -> Result<LexicalEntryDetails, ApplicationError> {
        let language = LanguageCode::parse(input.language)?;
        let normalization =
            self.normalize_lexical_form(language.as_str(), &input.canonical_form)?;
        let normalized_form = if input.kind == LexicalEntryKind::Phrase {
            normalize_phrase(&input.canonical_form)
        } else {
            normalization.normalized.clone()
        };
        require_text(&normalized_form, "canonical_form")?;
        let id = LexicalEntryId::from_fingerprint(
            "lexical-entry",
            &format!("{}:{:?}:{normalized_form}", language.as_str(), input.kind),
        );
        self.lexical.upsert_lexical_entry(
            &LexicalEntry {
                id,
                language,
                kind: input.kind,
                canonical_form: input.canonical_form,
                normalized_form,
                display_form: input.display_form,
                status: input.status,
                user_definition: input.user_definition,
                personal_note: input.personal_note,
                normalization_provider: normalization.provider,
                normalization_version: normalization.version,
                user_corrected: normalization.user_corrected,
                updated_at_ms: now_ms(),
                learning_updated_at_ms: now_ms(),
            },
            input.source.as_ref(),
            WordChangeSource::UserSelection,
        )
    }

    pub fn lexical_details(
        &self,
        id: &LexicalEntryId,
    ) -> Result<Option<LexicalEntryDetails>, ApplicationError> {
        self.lexical.lexical_details(id)
    }

    pub fn list_lexical_entries(
        &self,
        language: &str,
        kind: Option<LexicalEntryKind>,
        status: Option<WordStatus>,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LexicalEntryDetails>, ApplicationError> {
        self.lexical.list_lexical_entries(
            &LanguageCode::parse(language)?,
            kind,
            status,
            search,
            limit.min(200),
            offset,
        )
    }

    pub fn phrase_candidates(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<PhraseCandidate>, ApplicationError> {
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let language = LanguageCode::parse("en")?;
        let mut candidates = Vec::new();
        for provider in self.lexical_normalizers.iter() {
            candidates.extend(
                provider
                    .phrase_candidates(&language, &sentence)
                    .map_err(ApplicationError::LexicalNormalizationProvider)?,
            );
        }
        candidates.extend(phrase_candidates(&sentence));
        candidates.sort_by_key(|value| (value.token_start, value.token_end));
        candidates.dedup_by(|left, right| {
            left.normalized_form == right.normalized_form
                && left.token_start == right.token_start
                && left.token_end == right.token_end
        });
        Ok(candidates)
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
        let normalized_lemma = self
            .normalize_lexical_form(language.as_str(), &input.lemma)?
            .normalized;
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
                || self
                    .normalize_lexical_form(profile.language.as_str(), &source.normalized_lemma)?
                    .normalized
                    != profile.normalized_lemma
                || source.end_ms < source.start_ms)
        {
            return Err(ApplicationError::Validation("source context"));
        }
        let updated = self
            .vocabulary
            .apply_status(
                &profile,
                input.source.as_ref(),
                WordChangeSource::UserSelection,
            )
            .map(|details| details.profile)?;
        let lexical_source = input.source.as_ref().map(lexical_source_from_word);
        self.lexical.upsert_lexical_entry(
            &lexical_from_word(&updated),
            lexical_source.as_ref(),
            WordChangeSource::UserSelection,
        )?;
        Ok(updated)
    }

    pub fn read_word_profile(
        &self,
        language: &str,
        lemma: &str,
    ) -> Result<Option<WordProfile>, ApplicationError> {
        let language = LanguageCode::parse(language.to_owned())?;
        let raw = normalize_lemma(lemma);
        let normalized = self
            .normalize_lexical_form(language.as_str(), lemma)?
            .normalized;
        if let Some(value) = self.words.get_by_key(&language, &normalized)? {
            return Ok(Some(value));
        }
        self.words.get_by_key(&language, &raw)
    }

    pub fn read_word_profiles(
        &self,
        language: &str,
        lemmas: &[String],
    ) -> Result<Vec<WordProfile>, ApplicationError> {
        let language = LanguageCode::parse(language.to_owned())?;
        let mut normalized = std::collections::BTreeSet::new();
        for lemma in lemmas {
            let normalized_lemma = self
                .normalize_lexical_form(language.as_str(), lemma)?
                .normalized;
            if !normalized_lemma.is_empty() {
                normalized.insert(normalized_lemma);
            }
        }
        let normalized = normalized.into_iter().collect::<Vec<_>>();
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
                    || self
                        .normalize_lexical_form(
                            profile.language.as_str(),
                            &source.normalized_lemma,
                        )?
                        .normalized
                        != profile.normalized_lemma
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
        if bundle.version != 1 && bundle.version != 2 && bundle.version != 3 {
            return Err(ApplicationError::Validation(
                "unsupported asset bundle version",
            ));
        }
        self.vocabulary.import_assets(bundle).and_then(|_| {
            for profile in &bundle.profiles {
                self.lexical.upsert_lexical_entry(
                    &lexical_from_word(profile),
                    None,
                    WordChangeSource::Import,
                )?;
            }
            Ok(())
        })
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
        let details = self.vocabulary.update_learning_content(
            id,
            clean_optional(user_definition),
            clean_optional(personal_note),
            now_ms(),
        )?;
        self.lexical.upsert_lexical_entry(
            &lexical_from_word(&details.profile),
            None,
            WordChangeSource::UserSelection,
        )?;
        Ok(details)
    }

    pub fn import_external_vocabulary(
        &self,
        input: &ExternalVocabularyImport,
    ) -> Result<ExternalVocabularyImportSummary, ApplicationError> {
        LanguageCode::parse(input.language.clone())?;
        let summary = self.vocabulary.import_external(input, now_ms())?;
        for entry in &input.entries {
            if let Some(profile) = self.read_word_profile(&input.language, &entry.word)? {
                self.lexical.upsert_lexical_entry(
                    &lexical_from_word(&profile),
                    None,
                    WordChangeSource::Import,
                )?;
            }
        }
        Ok(summary)
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
pub struct LexicalSourceContext {
    pub media_id: Option<MediaId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub original_form: String,
    pub sentence_text: String,
    pub media_title: String,
    pub media_fingerprint: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct UpsertLexicalEntry {
    pub language: String,
    pub kind: LexicalEntryKind,
    pub canonical_form: String,
    pub display_form: String,
    pub status: Option<WordStatus>,
    pub user_definition: Option<String>,
    pub personal_note: Option<String>,
    pub source: Option<LexicalSourceContext>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LexicalNormalization {
    pub original: String,
    pub normalized: String,
    pub provider: String,
    pub version: String,
    pub user_corrected: bool,
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
    #[error(transparent)]
    LexicalNormalizationProvider(#[from] LexicalNormalizationProviderError),
    #[error("{0}")]
    Conflict(&'static str),
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

fn normalize_phrase(value: &str) -> String {
    value
        .split_whitespace()
        .map(normalize_lemma)
        .collect::<Vec<_>>()
        .join(" ")
}

fn lexical_from_word(profile: &WordProfile) -> LexicalEntry {
    LexicalEntry {
        id: LexicalEntryId::parse(profile.id.as_str().to_owned())
            .expect("word profile id is a valid lexical id"),
        language: profile.language.clone(),
        kind: LexicalEntryKind::Word,
        canonical_form: profile.lemma.clone(),
        normalized_form: profile.normalized_lemma.clone(),
        display_form: profile.display_form.clone(),
        status: profile.status,
        user_definition: profile.user_definition.clone(),
        personal_note: profile.personal_note.clone(),
        normalization_provider: "legacy-word-api".into(),
        normalization_version: "v1".into(),
        user_corrected: false,
        updated_at_ms: profile.updated_at_ms,
        learning_updated_at_ms: profile.learning_updated_at_ms,
    }
}

fn lexical_source_from_word(source: &SourceContext) -> LexicalSourceContext {
    LexicalSourceContext {
        media_id: source.media_id.clone(),
        sentence_id: source.sentence_id.clone(),
        original_form: source.original_form.clone(),
        sentence_text: source.sentence_text.clone(),
        media_title: source.media_title.clone(),
        media_fingerprint: source.media_fingerprint.clone(),
        start_ms: source.start_ms,
        end_ms: source.end_ms,
        token_start: None,
        token_end: None,
    }
}

fn normalize_american_english(value: &str) -> String {
    match value {
        "went" | "gone" | "going" | "goes" => "go".into(),
        "was" | "were" | "been" | "being" | "am" | "is" | "are" => "be".into(),
        "did" | "done" | "doing" | "does" => "do".into(),
        "had" | "having" | "has" => "have".into(),
        _ if value.len() > 4 && value.ends_with("ies") => {
            format!("{}y", &value[..value.len() - 3])
        }
        _ if value.len() > 5 && value.ends_with("ing") => value[..value.len() - 3].into(),
        _ if value.len() > 4 && value.ends_with("ed") => value[..value.len() - 2].into(),
        _ if value.len() > 3 && value.ends_with('s') && !value.ends_with("ss") => {
            value[..value.len() - 1].into()
        }
        _ => value.into(),
    }
}

fn phrase_candidates(sentence: &SubtitleSentence) -> Vec<PhraseCandidate> {
    const PHRASES: &[&str] = &[
        "according to",
        "as well as",
        "because of",
        "come up with",
        "figure out",
        "get along",
        "give up",
        "in front of",
        "in order to",
        "look forward to",
        "make sure",
        "pick up",
        "take care of",
        "turn out",
        "used to",
    ];
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    let normalized = words
        .iter()
        .map(|token| normalize_lemma(&token.text))
        .collect::<Vec<_>>();
    let mut values = Vec::new();
    for phrase in PHRASES {
        let parts = phrase.split_whitespace().collect::<Vec<_>>();
        for start in 0..normalized
            .len()
            .saturating_sub(parts.len())
            .saturating_add(1)
        {
            if normalized[start..start + parts.len()] == parts {
                values.push(PhraseCandidate {
                    canonical_form: (*phrase).into(),
                    display_form: words[start..start + parts.len()]
                        .iter()
                        .map(|token| token.text.as_str())
                        .collect::<Vec<_>>()
                        .join(" "),
                    normalized_form: (*phrase).into(),
                    token_start: words[start].index,
                    token_end: words[start + parts.len() - 1].index,
                    reason: "built-in en-US phrase rule".into(),
                });
            }
        }
    }
    values
}
