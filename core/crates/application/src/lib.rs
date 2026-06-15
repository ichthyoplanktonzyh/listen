use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use domain::*;
use serde::{Deserialize, Serialize};
use thiserror::Error;

const DICTIONARY_CACHE_TTL_MS: u64 = 30 * 24 * 60 * 60 * 1000;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SentenceWordTimingDiagnostics {
    pub sentence_id: SubtitleSentenceId,
    pub boundaries: Vec<WordTimingBoundaryDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WordTimingBoundaryDiagnostic {
    pub left_token_index: u32,
    pub right_token_index: u32,
    pub left_end_ms: u64,
    pub right_start_ms: u64,
    pub gap_ms: u64,
    pub left_timing_source: TimingSource,
    pub right_timing_source: TimingSource,
    pub left_provider_id: String,
    pub left_provider_version: String,
    pub right_provider_id: String,
    pub right_provider_version: String,
}

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
    fn save_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        pronunciation: &WordPronunciation,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<(), ApplicationError>;
    fn get_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        normalized_text: &str,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<Option<WordPronunciation>, ApplicationError>;
    fn save_pronunciation(&self, analysis: &SentencePronunciation) -> Result<(), ApplicationError>;
    fn get_pronunciation(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SentencePronunciation>, ApplicationError>;
    fn save_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
        timings: &[WordTiming],
    ) -> Result<(), ApplicationError>;
    fn get_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordTiming>, ApplicationError>;
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

    pub fn pronunciation_providers(&self) -> Vec<PronunciationProviderInfo> {
        vec![speech_analysis::provider_info()]
    }

    pub fn pronunciation_rules(&self) -> serde_json::Value {
        serde_json::json!({
            "analyzer_id": "en-us-rules",
            "version": speech_analysis::ANALYZER_VERSION,
            "evidence_source": "deterministic_text_rule",
            "disclaimer": "Rule predictions are contextual possibilities, not detections from the audio.",
            "rules": speech_analysis::rule_catalog(),
        })
    }

    pub fn lookup_pronunciation(&self, word: &str) -> Result<WordPronunciation, ApplicationError> {
        require_text(word, "word")?;
        let normalized = normalize_lemma(word);
        if let Some(value) = self.subtitles.get_word_pronunciation(
            "en",
            "en-US",
            &normalized,
            speech_analysis::PROVIDER_ID,
            speech_analysis::PROVIDER_VERSION,
        )? {
            return Ok(value);
        }
        let value = speech_analysis::lookup(word, 0);
        self.subtitles.save_word_pronunciation(
            "en",
            "en-US",
            &value,
            speech_analysis::PROVIDER_ID,
            speech_analysis::PROVIDER_VERSION,
        )?;
        Ok(value)
    }

    pub fn analyze_pronunciation(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<SentencePronunciation, ApplicationError> {
        if let Some(value) = self.subtitles.get_pronunciation(sentence_id)?
            && value.provider_id == speech_analysis::PROVIDER_ID
            && value.provider_version == speech_analysis::PROVIDER_VERSION
        {
            return Ok(value);
        }
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let value = speech_analysis::analyze_sentence(&sentence);
        self.subtitles.save_pronunciation(&value)?;
        Ok(value)
    }

    pub fn pronunciation_cache_state(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Option<bool>, ApplicationError> {
        Ok(self.subtitles.get_pronunciation(sentence_id)?.map(|value| {
            value.provider_id == speech_analysis::PROVIDER_ID
                && value.provider_version == speech_analysis::PROVIDER_VERSION
        }))
    }

    pub fn word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        let existing = self.subtitles.get_word_timings(sentence_id)?;
        if let Some(first) = existing.first()
            && (first.timing_source != TimingSource::Estimated
                || (first.provider_id == "subtitle-weighted-estimator"
                    && first.provider_version == "v1"))
        {
            return Ok(existing);
        }
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let values = speech_analysis::estimate_word_timings(&sentence);
        self.subtitles.save_word_timings(sentence_id, &values)?;
        Ok(values)
    }

    pub fn word_timing_cache_state(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Option<bool>, ApplicationError> {
        let values = self.subtitles.get_word_timings(sentence_id)?;
        Ok(values.first().map(|first| {
            first.timing_source != TimingSource::Estimated
                || (first.provider_id == "subtitle-weighted-estimator"
                    && first.provider_version == "v1")
        }))
    }

    pub fn analyze_pronunciation_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SentencePronunciation>, ApplicationError> {
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        track
            .sentences
            .iter()
            .map(|sentence| self.analyze_pronunciation(&sentence.id))
            .collect()
    }

    pub fn word_timings_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let mut values = Vec::new();
        for sentence in track.sentences {
            values.extend(self.word_timings(&sentence.id)?);
        }
        Ok(values)
    }

    pub fn word_timing_diagnostics_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SentenceWordTimingDiagnostics>, ApplicationError> {
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        track
            .sentences
            .iter()
            .filter_map(|sentence| {
                let timings = match self.word_timings(&sentence.id) {
                    Ok(timings) => timings,
                    Err(error) => return Some(Err(error)),
                };
                if timings.is_empty() {
                    return None;
                }
                Some(Ok(SentenceWordTimingDiagnostics {
                    sentence_id: sentence.id.clone(),
                    boundaries: timings
                        .windows(2)
                        .map(|pair| WordTimingBoundaryDiagnostic {
                            left_token_index: pair[0].token_index,
                            right_token_index: pair[1].token_index,
                            left_end_ms: pair[0].end_ms,
                            right_start_ms: pair[1].start_ms,
                            gap_ms: pair[1].start_ms.saturating_sub(pair[0].end_ms),
                            left_timing_source: pair[0].timing_source,
                            right_timing_source: pair[1].timing_source,
                            left_provider_id: pair[0].provider_id.clone(),
                            left_provider_version: pair[0].provider_version.clone(),
                            right_provider_id: pair[1].provider_id.clone(),
                            right_provider_version: pair[1].provider_version.clone(),
                        })
                        .collect(),
                }))
            })
            .collect()
    }

    /// Detect acoustic chunk boundaries for every sentence in a subtitle track.
    ///
    /// Uses gap-based detection on existing word timings. Each sentence is
    /// processed independently; cross-sentence boundaries are never created.
    pub fn detect_track_chunks(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<
        std::collections::HashMap<SubtitleSentenceId, speech_analysis::chunk_detection::ChunkDetectionResult>,
        ApplicationError,
    > {
        use speech_analysis::chunk_detection::{detect_chunk_boundaries, ChunkDetectionConfig};
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = ChunkDetectionConfig::default();
        let mut results = std::collections::HashMap::new();
        for sentence in track.sentences {
            let timings = self.word_timings(&sentence.id)?;
            let mut result = detect_chunk_boundaries(&timings, &config);
            result.sentence_id = sentence.id.clone();
            results.insert(sentence.id.clone(), result);
        }
        Ok(results)
    }

    /// Detect acoustic chunk boundaries for a single sentence.
    pub fn detect_sentence_chunks(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::chunk_detection::ChunkDetectionResult, ApplicationError> {
        use speech_analysis::chunk_detection::{detect_chunk_boundaries, ChunkDetectionConfig};
        let timings = self.word_timings(sentence_id)?;
        let mut result = detect_chunk_boundaries(&timings, &ChunkDetectionConfig::default());
        result.sentence_id = sentence_id.clone();
        Ok(result)
    }

    /// Detect text-level chunks for a single sentence.
    ///
    /// Uses embedded COCA n-gram, PHRASE List, and external phrase candidates
    /// (ECDICT + built-in rules) to partition the sentence into lexical chunks.
    /// Every word token is covered by exactly one chunk.
    pub fn detect_text_chunks(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::text_chunk_detection::TextChunkDetectionResult, ApplicationError>
    {
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let candidates = self.phrase_candidates(sentence_id)?;
        Ok(speech_analysis::text_chunk_detection::detect_text_chunks(
            &sentence,
            &candidates,
        ))
    }

    /// Detect text-level chunks for every sentence in a subtitle track.
    pub fn detect_text_chunks_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<
        std::collections::HashMap<
            SubtitleSentenceId,
            speech_analysis::text_chunk_detection::TextChunkDetectionResult,
        >,
        ApplicationError,
    > {
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let mut results = std::collections::HashMap::new();
        for sentence in track.sentences {
            let result = self.detect_text_chunks(&sentence.id)?;
            results.insert(sentence.id.clone(), result);
        }
        Ok(results)
    }

    /// Detect chunks using combined acoustic + text-level evidence.
    ///
    /// Uses the text partition as the structural basis and overlays acoustic
    /// boundary evidence where available. See
    /// [`speech_analysis::chunk_detection::combine_chunks`] for the combination
    /// confidence logic.
    pub fn detect_combined_sentence_chunks(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::chunk_detection::CombinedChunkResult, ApplicationError>
    {
        use speech_analysis::chunk_detection::{
            combine_chunks, detect_chunk_boundaries, ChunkDetectionConfig,
        };
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let timings = self.word_timings(sentence_id)?;
        let candidates = self.phrase_candidates(sentence_id)?;

        let acoustic =
            detect_chunk_boundaries(&timings, &ChunkDetectionConfig::default());
        let text = speech_analysis::text_chunk_detection::detect_text_chunks(
            &sentence,
            &candidates,
        );

        Ok(combine_chunks(&acoustic, &text))
    }

    /// Produce the product-facing, complete chunk partition for one sentence.
    pub fn chunk_partition(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::chunk_partition::SentenceChunkPartition, ApplicationError> {
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let timings = self.word_timings(sentence_id)?;
        let candidates = self.phrase_candidates(sentence_id)?;
        Ok(speech_analysis::chunk_partition::partition_sentence(
            &sentence,
            &timings,
            &candidates,
            &speech_analysis::chunk_partition::ChunkPartitionConfig::default(),
        ))
    }

    /// Produce developer-facing scores for selected and rejected chunk boundaries.
    pub fn chunk_partition_diagnostics(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::chunk_partition::SentenceChunkDiagnostics, ApplicationError> {
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let timings = self.word_timings(sentence_id)?;
        let candidates = self.phrase_candidates(sentence_id)?;
        Ok(
            speech_analysis::chunk_partition::partition_sentence_with_diagnostics(
                &sentence,
                &timings,
                &candidates,
                &speech_analysis::chunk_partition::ChunkPartitionConfig::default(),
            ),
        )
    }

    /// Produce product-facing chunk partitions for every sentence in a track.
    pub fn chunk_partitions_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<speech_analysis::chunk_partition::SentenceChunkPartition>, ApplicationError>
    {
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = chunk_partition_config_for_track_source(&track.source);
        track
            .sentences
            .iter()
            .map(|sentence| {
                let timings = self.word_timings(&sentence.id)?;
                let candidates = self.phrase_candidates(&sentence.id)?;
                Ok(speech_analysis::chunk_partition::partition_sentence(
                    sentence,
                    &timings,
                    &candidates,
                    &config,
                ))
            })
            .collect()
    }

    /// Produce developer-facing chunk diagnostics using the same track-source
    /// configuration as the product-facing partitions.
    pub fn chunk_diagnostics_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<speech_analysis::chunk_partition::SentenceChunkDiagnostics>, ApplicationError>
    {
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = chunk_partition_config_for_track_source(&track.source);
        track
            .sentences
            .iter()
            .map(|sentence| {
                let timings = self.word_timings(&sentence.id)?;
                let candidates = self.phrase_candidates(&sentence.id)?;
                Ok(
                    speech_analysis::chunk_partition::partition_sentence_with_diagnostics(
                        sentence,
                        &timings,
                        &candidates,
                        &config,
                    ),
                )
            })
            .collect()
    }

    pub fn store_word_timings(
        &self,
        track_id: &SubtitleTrackId,
        timings: &[WordTiming],
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let sentences = track
            .sentences
            .iter()
            .map(|sentence| (sentence.id.clone(), sentence))
            .collect::<std::collections::HashMap<_, _>>();
        let mut grouped = std::collections::HashMap::<SubtitleSentenceId, Vec<WordTiming>>::new();
        for timing in timings {
            let sentence = sentences
                .get(&timing.sentence_id)
                .ok_or(ApplicationError::Validation("word timing sentence"))?;
            if timing.end_ms < timing.start_ms
                || timing.start_ms < sentence.start.get()
                || timing.end_ms > sentence.end.get()
                || !sentence.tokens.iter().any(|token| {
                    token.index == timing.token_index && token.kind == SubtitleTokenKind::Word
                })
            {
                return Err(ApplicationError::Validation("word timing boundary"));
            }
            grouped
                .entry(timing.sentence_id.clone())
                .or_default()
                .push(timing.clone());
        }
        for (sentence_id, values) in grouped.iter_mut() {
            values.sort_by_key(|value| (value.start_ms, value.end_ms, value.token_index));
            if values
                .windows(2)
                .any(|pair| pair[0].end_ms > pair[1].start_ms)
            {
                return Err(ApplicationError::Validation("word timing monotonicity"));
            }
            let existing = self.subtitles.get_word_timings(sentence_id)?;
            if existing.first().is_some_and(|current| {
                values.first().is_some_and(|incoming| {
                    timing_priority(current.timing_source) > timing_priority(incoming.timing_source)
                })
            }) {
                continue;
            }
            self.subtitles.save_word_timings(sentence_id, values)?;
        }
        Ok(timings.to_vec())
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

fn timing_priority(source: TimingSource) -> u8 {
    match source {
        TimingSource::Estimated => 1,
        TimingSource::AsrReported => 2,
        TimingSource::ForcedAligned => 3,
        TimingSource::UserAdjusted => 4,
    }
}

fn chunk_partition_config_for_track_source(
    source: &str,
) -> speech_analysis::chunk_partition::ChunkPartitionConfig {
    if source.starts_with("ASR-") {
        speech_analysis::chunk_partition::ChunkPartitionConfig::for_asr_generated_subtitle()
    } else {
        speech_analysis::chunk_partition::ChunkPartitionConfig::default()
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
        for start in 0..normalized.len().saturating_sub(parts.len().saturating_sub(1)) {
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

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{
        LanguageCode, LexicalEntryId, LexicalEntryKind, SubtitleSentence, SubtitleSentenceId,
        SubtitleToken, SubtitleTokenKind, TimeMs, TimingSource, WordProfile, WordProfileId,
        WordStatus,
    };

    // ── require_text ────────────────────────────────────────────────────────

    #[test]
    fn require_text_rejects_empty() {
        let err = require_text("", "field_name").unwrap_err();
        assert!(matches!(err, ApplicationError::Validation("field_name")));
    }

    #[test]
    fn require_text_rejects_whitespace_only() {
        let err = require_text("   ", "field_name").unwrap_err();
        assert!(matches!(err, ApplicationError::Validation("field_name")));
    }

    #[test]
    fn require_text_accepts_valid_string() {
        assert!(require_text("hello", "field_name").is_ok());
    }

    #[test]
    fn require_text_accepts_text_with_whitespace_padding() {
        assert!(require_text("  hello  ", "field_name").is_ok());
    }

    // ── clean_optional ──────────────────────────────────────────────────────

    #[test]
    fn clean_optional_none_is_none() {
        assert_eq!(clean_optional(None), None);
    }

    #[test]
    fn clean_optional_empty_string_is_none() {
        assert_eq!(clean_optional(Some("".into())), None);
    }

    #[test]
    fn clean_optional_whitespace_only_is_none() {
        assert_eq!(clean_optional(Some("   ".into())), None);
    }

    #[test]
    fn clean_optional_trims_whitespace() {
        assert_eq!(
            clean_optional(Some("  hello  ".into())),
            Some("hello".into())
        );
    }

    // ── normalize_american_english ──────────────────────────────────────────

    #[test]
    fn normalize_went_to_go() {
        assert_eq!(normalize_american_english("went"), "go");
    }

    #[test]
    fn normalize_gone_to_go() {
        assert_eq!(normalize_american_english("gone"), "go");
    }

    #[test]
    fn normalize_going_to_go() {
        assert_eq!(normalize_american_english("going"), "go");
    }

    #[test]
    fn normalize_goes_to_go() {
        assert_eq!(normalize_american_english("goes"), "go");
    }

    #[test]
    fn normalize_was_to_be() {
        assert_eq!(normalize_american_english("was"), "be");
    }

    #[test]
    fn normalize_were_to_be() {
        assert_eq!(normalize_american_english("were"), "be");
    }

    #[test]
    fn normalize_am_is_are() {
        assert_eq!(normalize_american_english("am"), "be");
        assert_eq!(normalize_american_english("is"), "be");
        assert_eq!(normalize_american_english("are"), "be");
    }

    #[test]
    fn normalize_do_variants() {
        assert_eq!(normalize_american_english("did"), "do");
        assert_eq!(normalize_american_english("done"), "do");
        assert_eq!(normalize_american_english("does"), "do");
    }

    #[test]
    fn normalize_have_variants() {
        assert_eq!(normalize_american_english("had"), "have");
        assert_eq!(normalize_american_english("has"), "have");
    }

    #[test]
    fn normalize_ies_suffix() {
        // words ending with "ies" and len > 4 → replace with "y"
        assert_eq!(normalize_american_english("stories"), "story");
        assert_eq!(normalize_american_english("families"), "family");
    }

    #[test]
    fn normalize_ing_suffix() {
        assert_eq!(normalize_american_english("playing"), "play");
        assert_eq!(normalize_american_english("running"), "runn");
    }

    #[test]
    fn normalize_ed_suffix() {
        assert_eq!(normalize_american_english("played"), "play");
        assert_eq!(normalize_american_english("walked"), "walk");
    }

    #[test]
    fn normalize_s_suffix() {
        assert_eq!(normalize_american_english("words"), "word");
    }

    #[test]
    fn normalize_preserves_ss_ending() {
        assert_eq!(normalize_american_english("pass"), "pass");
        assert_eq!(normalize_american_english("class"), "class");
    }

    #[test]
    fn normalize_unchanged_for_short_words() {
        // "go" and "cat" are len <= 3, no suffix rules apply
        assert_eq!(normalize_american_english("go"), "go");
        assert_eq!(normalize_american_english("cat"), "cat");
        // "lies" is len 4: ies needs >4 (no), s-rule needs >3 (yes) → "lie"
        assert_eq!(normalize_american_english("lies"), "lie");
    }

    #[test]
    fn normalize_ing_short_word() {
        // "doing" is in the exact match list (did/done/doing/does → do)
        assert_eq!(normalize_american_english("doing"), "do");
    }

    #[test]
    fn normalize_rule_precedence() {
        // "being" should match the exact "been"/"being" list before suffix rules
        assert_eq!(normalize_american_english("being"), "be");
        // "having" matches exact "having" *check: "had" | "having" | "has" → "have"
        assert_eq!(normalize_american_english("having"), "have");
    }

    // ── normalize_phrase ────────────────────────────────────────────────────

    #[test]
    fn normalize_phrase_single_word() {
        // normalize_phrase uses domain::normalize_lemma (trim + lowercase only)
        assert_eq!(normalize_phrase("running"), "running");
    }

    #[test]
    fn normalize_phrase_multi_word() {
        assert_eq!(normalize_phrase("take care of"), "take care of");
    }

    #[test]
    fn normalize_phrase_with_irregulars() {
        // normalize_phrase uses domain::normalize_lemma (only trims and lowercases)
        assert_eq!(normalize_phrase("was going"), "was going");
    }

    // ── lexical_from_word ───────────────────────────────────────────────────

    #[test]
    fn lexical_from_word_maps_core_fields() {
        let profile = WordProfile {
            id: WordProfileId::from_fingerprint("test", "en:hello"),
            language: LanguageCode::parse("en").unwrap(),
            lemma: "Hello".into(),
            normalized_lemma: "hello".into(),
            display_form: "Hello".into(),
            status: Some(WordStatus::KnownRecognized),
            updated_at_ms: 1000,
            user_definition: Some("a greeting".into()),
            personal_note: Some("common".into()),
            learning_updated_at_ms: 2000,
        };
        let entry = lexical_from_word(&profile);
        assert_eq!(entry.language.as_str(), "en");
        assert_eq!(entry.kind, LexicalEntryKind::Word);
        assert_eq!(entry.canonical_form, "Hello");
        assert_eq!(entry.normalized_form, "hello");
        assert_eq!(entry.display_form, "Hello");
        assert_eq!(entry.status, Some(WordStatus::KnownRecognized));
        assert_eq!(entry.user_definition, Some("a greeting".into()));
        assert_eq!(entry.personal_note, Some("common".into()));
        assert_eq!(entry.normalization_provider, "legacy-word-api");
        assert_eq!(entry.normalization_version, "v1");
        assert!(!entry.user_corrected);
        assert_eq!(entry.updated_at_ms, 1000);
        assert_eq!(entry.learning_updated_at_ms, 2000);
    }

    #[test]
    fn lexical_from_word_id_is_parseable() {
        let profile = WordProfile {
            id: WordProfileId::from_fingerprint("test", "en:test"),
            language: LanguageCode::parse("en").unwrap(),
            lemma: "test".into(),
            normalized_lemma: "test".into(),
            display_form: "test".into(),
            status: None,
            updated_at_ms: 0,
            user_definition: None,
            personal_note: None,
            learning_updated_at_ms: 0,
        };
        let entry = lexical_from_word(&profile);
        // The id should be parseable as a LexicalEntryId (uses the same string
        // format from WordProfileId)
        let parsed = LexicalEntryId::parse(entry.id.as_str().to_owned());
        assert!(parsed.is_ok());
    }

    // ── lexical_source_from_word ────────────────────────────────────────────

    #[test]
    fn lexical_source_maps_all_fields() {
        let source = SourceContext {
            language: LanguageCode::parse("en").unwrap(),
            normalized_lemma: "hello".into(),
            media_id: None,
            sentence_id: None,
            original_form: "Hello".into(),
            sentence_text: "Hello world".into(),
            media_title: "Test".into(),
            media_fingerprint: "fp1".into(),
            start_ms: 100,
            end_ms: 500,
        };
        let lex_source = lexical_source_from_word(&source);
        assert_eq!(lex_source.original_form, "Hello");
        assert_eq!(lex_source.sentence_text, "Hello world");
        assert_eq!(lex_source.media_title, "Test");
        assert_eq!(lex_source.media_fingerprint, "fp1");
        assert_eq!(lex_source.start_ms, 100);
        assert_eq!(lex_source.end_ms, 500);
        assert_eq!(lex_source.token_start, None);
        assert_eq!(lex_source.token_end, None);
    }

    #[test]
    fn lexical_source_preserves_media_and_sentence_ids() {
        let media_id = domain::MediaId::from_fingerprint("test", "media1");
        let sentence_id = SubtitleSentenceId::from_fingerprint("test", "sent1");
        let source = SourceContext {
            language: LanguageCode::parse("en").unwrap(),
            normalized_lemma: "test".into(),
            media_id: Some(media_id.clone()),
            sentence_id: Some(sentence_id.clone()),
            original_form: "test".into(),
            sentence_text: "test".into(),
            media_title: "title".into(),
            media_fingerprint: "fp".into(),
            start_ms: 0,
            end_ms: 100,
        };
        let lex_source = lexical_source_from_word(&source);
        assert_eq!(lex_source.media_id, Some(media_id));
        assert_eq!(lex_source.sentence_id, Some(sentence_id));
    }

    // ── timing_priority ─────────────────────────────────────────────────────

    #[test]
    fn timing_priority_ordering() {
        assert_eq!(timing_priority(TimingSource::Estimated), 1);
        assert_eq!(timing_priority(TimingSource::AsrReported), 2);
        assert_eq!(timing_priority(TimingSource::ForcedAligned), 3);
        assert_eq!(timing_priority(TimingSource::UserAdjusted), 4);
    }

    #[test]
    fn timing_priority_user_overrides_all() {
        assert!(
            timing_priority(TimingSource::UserAdjusted)
                > timing_priority(TimingSource::AsrReported)
        );
        assert!(
            timing_priority(TimingSource::UserAdjusted)
                > timing_priority(TimingSource::ForcedAligned)
        );
        assert!(
            timing_priority(TimingSource::UserAdjusted) > timing_priority(TimingSource::Estimated)
        );
    }

    #[test]
    fn forced_alignment_overrides_coarse_asr_timing() {
        assert!(
            timing_priority(TimingSource::ForcedAligned)
                > timing_priority(TimingSource::AsrReported)
        );
    }

    #[test]
    fn asr_track_source_uses_inferred_punctuation_config() {
        assert_eq!(
            chunk_partition_config_for_track_source("ASR-Whisper Large.srt")
                .punctuation_reliability,
            speech_analysis::chunk_partition::PunctuationReliability::Inferred
        );
        assert_eq!(
            chunk_partition_config_for_track_source("official-subtitles.srt")
                .punctuation_reliability,
            speech_analysis::chunk_partition::PunctuationReliability::Trusted
        );
    }

    // ── phrase_candidates ───────────────────────────────────────────────────

    fn make_sentence(tokens: Vec<SubtitleToken>) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::from_fingerprint("test", "sent1"),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(5000),
            original_text: tokens.iter().map(|t| t.text.as_str()).collect::<Vec<_>>().join(" "),
            display_text: tokens
                .iter()
                .map(|t| t.text.as_str())
                .collect::<Vec<_>>()
                .join(" "),
            tokens,
        }
    }

    fn word_token(index: u32, text: &str) -> SubtitleToken {
        SubtitleToken {
            index,
            kind: SubtitleTokenKind::Word,
            text: text.into(),
            normalized: Some(text.to_ascii_lowercase()),
            start_char: 0,
            end_char: text.len() as u32,
        }
    }

    #[test]
    fn phrase_candidates_finds_known_phrase() {
        let sentence = make_sentence(vec![
            word_token(0, "give"),
            word_token(1, "up"),
            word_token(2, "now"),
        ]);
        let candidates = phrase_candidates(&sentence);
        assert!(
            candidates.iter().any(|c| c.normalized_form == "give up"),
            "should find 'give up' phrase"
        );
        let give_up = candidates.iter().find(|c| c.normalized_form == "give up").unwrap();
        assert_eq!(give_up.token_start, 0);
        assert_eq!(give_up.token_end, 1);
        assert_eq!(give_up.canonical_form, "give up");
    }

    #[test]
    fn phrase_candidates_finds_phrase_mid_sentence() {
        let sentence = make_sentence(vec![
            word_token(0, "we"),
            word_token(1, "need"),
            word_token(2, "to"),
            word_token(3, "figure"),
            word_token(4, "out"),
            word_token(5, "the"),
            word_token(6, "problem"),
        ]);
        let candidates = phrase_candidates(&sentence);
        assert!(candidates.iter().any(|c| c.normalized_form == "figure out"));
        let fo = candidates.iter().find(|c| c.normalized_form == "figure out").unwrap();
        assert_eq!(fo.token_start, 3);
        assert_eq!(fo.token_end, 4);
    }

    #[test]
    fn phrase_candidates_empty_for_no_match() {
        let sentence = make_sentence(vec![
            word_token(0, "hello"),
            word_token(1, "world"),
        ]);
        let candidates = phrase_candidates(&sentence);
        assert!(
            !candidates.iter().any(|c| c.normalized_form == "give up"),
            "should not find phrases in unrelated text"
        );
    }

    #[test]
    fn phrase_candidates_finds_multiple_phrases() {
        let sentence = make_sentence(vec![
            word_token(0, "make"),
            word_token(1, "sure"),
            word_token(2, "you"),
            word_token(3, "pick"),
            word_token(4, "up"),
        ]);
        let candidates = phrase_candidates(&sentence);
        assert!(candidates.iter().any(|c| c.normalized_form == "make sure"));
        assert!(candidates.iter().any(|c| c.normalized_form == "pick up"));
    }

    #[test]
    fn phrase_candidates_respects_token_boundaries() {
        // "in front of" should match correctly
        let sentence = make_sentence(vec![
            word_token(0, "stand"),
            word_token(1, "in"),
            word_token(2, "front"),
            word_token(3, "of"),
            word_token(4, "the"),
            word_token(5, "door"),
        ]);
        let candidates = phrase_candidates(&sentence);
        let fo = candidates.iter().find(|c| c.normalized_form == "in front of").unwrap();
        assert_eq!(fo.token_start, 1);
        assert_eq!(fo.token_end, 3);
    }

    #[test]
    fn phrase_candidates_skips_non_word_tokens() {
        let sentence = SubtitleSentence {
            id: SubtitleSentenceId::from_fingerprint("test", "sent"),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(1000),
            original_text: "give up.".into(),
            display_text: "give up.".into(),
            tokens: vec![
                word_token(0, "give"),
                word_token(1, "up"),
                SubtitleToken {
                    index: 2,
                    kind: SubtitleTokenKind::Punctuation,
                    text: ".".into(),
                    normalized: None,
                    start_char: 0,
                    end_char: 1,
                },
            ],
        };
        let candidates = phrase_candidates(&sentence);
        assert!(candidates.iter().any(|c| c.normalized_form == "give up"));
    }

    #[test]
    fn phrase_candidates_with_normalized_matching() {
        // "Used to" should match "used to" phrase even with capitalization
        let sentence = make_sentence(vec![
            word_token(0, "I"),
            word_token(1, "used"),
            word_token(2, "to"),
            word_token(3, "swim"),
        ]);
        let candidates = phrase_candidates(&sentence);
        assert!(candidates.iter().any(|c| c.normalized_form == "used to"));
    }

    // ── now_ms ──────────────────────────────────────────────────────────────

    #[test]
    fn now_ms_returns_plausible_timestamp() {
        let ts = now_ms();
        // After year 2020 in milliseconds
        assert!(ts > 1_577_836_800_000);
        // Should be increasing
        let ts2 = now_ms();
        assert!(ts2 >= ts);
    }
}
