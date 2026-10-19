use crate::{
    AppServices, ApplicationError, CapabilityProjectionSource, LanguageCode, LearningChangeSource,
    LearningEventRepository, LearningObservationRepository, LearningStatus,
    LexicalCapabilityRepository, LexicalContentRepository, LexicalEntry, LexicalEntryDetails,
    LexicalEntryId, LexicalEntryKind, LexicalEntryRepository, LexicalNormalization,
    LexicalNormalizationProvider, LexicalUnit, MediaRepository, PhraseCandidate,
    PracticeRepository, RecognitionUpgradeRepository, SubtitleSentenceId, SubtitleTrackRepository,
    UpsertLexicalEntry, VocabularyAssetRepository, normalize_american_english, normalize_lemma,
    normalize_phrase, now_ms, phrase_candidates, require_text,
};
use std::sync::Arc;

/// Lexical learning owns normalization, durable lexical assets, capability
/// evidence, sense organization, and vocabulary transfer as one consistency
/// boundary. It deliberately excludes practice scheduling and media analysis.
#[derive(Clone)]
pub struct LexicalLearningUseCases {
    pub(crate) media: Arc<dyn MediaRepository>,
    pub(crate) subtitle_tracks: Arc<dyn SubtitleTrackRepository>,
    pub(crate) lexical_capabilities: Arc<dyn LexicalCapabilityRepository>,
    pub(crate) lexical_entries: Arc<dyn LexicalEntryRepository>,
    pub(crate) learning_observations: Arc<dyn LearningObservationRepository>,
    pub(crate) lexical_content: Arc<dyn LexicalContentRepository>,
    pub(crate) vocabulary_assets: Arc<dyn VocabularyAssetRepository>,
    pub(crate) practice: Arc<dyn PracticeRepository>,
    pub(crate) recognition_upgrades: Arc<dyn RecognitionUpgradeRepository>,
    pub(crate) learning_events: Arc<dyn LearningEventRepository>,
    pub(crate) lexical_normalizers: Arc<Vec<Arc<dyn LexicalNormalizationProvider>>>,
}

impl LexicalLearningUseCases {
    pub(crate) fn frequency_rank(
        &self,
        language: &domain::LanguageCode,
        lemma: &str,
    ) -> Option<u32> {
        self.lexical_normalizers
            .iter()
            .find_map(|provider| provider.frequency_rank(language, lemma))
    }
    pub(crate) fn from_services(services: &AppServices) -> Self {
        Self {
            media: services.media.clone(),
            subtitle_tracks: services.subtitle_tracks.clone(),
            lexical_capabilities: services.lexical_capabilities.clone(),
            lexical_entries: services.lexical_entries.clone(),
            learning_observations: services.learning_observations.clone(),
            lexical_content: services.lexical_content.clone(),
            vocabulary_assets: services.vocabulary_assets.clone(),
            practice: services.practice.clone(),
            recognition_upgrades: services.recognition_upgrades.clone(),
            learning_events: services.learning_events.clone(),
            lexical_normalizers: services.lexical_normalizers.clone(),
        }
    }

    pub fn normalize_lexical_form(
        &self,
        language: &str,
        value: &str,
    ) -> Result<LexicalNormalization, ApplicationError> {
        let language = LanguageCode::parse(language)?;
        let original = normalize_lemma(value);
        require_text(&original, "value")?;
        if let Some(corrected) = self.lexical_entries.lemma_override(&language, &original)? {
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
        let original_entry = self.lexical_entries.lexical_entry_by_key(
            &language,
            LexicalEntryKind::Word,
            &original,
        )?;
        let corrected_entry = self.lexical_entries.lexical_entry_by_key(
            &language,
            LexicalEntryKind::Word,
            &corrected,
        )?;
        if let (Some(original_entry), Some(corrected_entry)) = (original_entry, corrected_entry)
            && original_entry.id != corrected_entry.id
        {
            return Err(ApplicationError::Conflict(
                "lemma correction target already has a separate word asset",
            ));
        }
        self.lexical_entries
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
        let unit =
            lexical_unit_for_entry(&language, input.kind, &normalized_form, &input.display_form);
        let id = LexicalEntryId::from_fingerprint("lexical-entry", &unit.identity());
        let now = now_ms();
        let details = self.lexical_entries.upsert_lexical_entry(
            &LexicalEntry {
                id,
                unit,
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
                updated_at_ms: now,
                learning_updated_at_ms: now,
            },
            input.source.as_ref(),
            LearningChangeSource::UserSelection,
        )?;
        if input.status.is_some() {
            self.sync_capability_from_legacy_status(
                &details.entry.id,
                details.entry.status,
                now,
                CapabilityProjectionSource::LegacyLearningStatusMigration,
            )?;
            // The writer ladder may have kept a task-grade evidence
            // conclusion; return the effective view, not the raw write.
            return self
                .lexical_entries
                .lexical_details(&details.entry.id)?
                .ok_or(ApplicationError::NotFound("lexical entry"));
        }
        Ok(details)
    }

    pub fn lexical_details(
        &self,
        id: &LexicalEntryId,
    ) -> Result<Option<LexicalEntryDetails>, ApplicationError> {
        self.lexical_entries.lexical_details(id)
    }

    pub fn list_lexical_entries(
        &self,
        language: &str,
        kind: Option<LexicalEntryKind>,
        status: Option<LearningStatus>,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LexicalEntryDetails>, ApplicationError> {
        self.lexical_entries.list_lexical_entries(
            &LanguageCode::parse(language)?,
            kind,
            status,
            None,
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
            .subtitle_tracks
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let language = self.sentence_language(sentence_id)?;
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

    pub(crate) fn sentence_language(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<LanguageCode, ApplicationError> {
        match self.subtitle_tracks.sentence_track_language(sentence_id)? {
            Some(language) => Ok(language),
            None => Ok(LanguageCode::parse("en")?),
        }
    }
}

pub(crate) fn lexical_unit_for_entry(
    language: &LanguageCode,
    kind: LexicalEntryKind,
    normalized_form: &str,
    display_form: &str,
) -> LexicalUnit {
    let profile = domain::profile_for(language);
    LexicalUnit::new(
        language.clone(),
        kind.granularity(),
        profile.lexical_normalization,
        normalized_form,
        display_form,
    )
}
