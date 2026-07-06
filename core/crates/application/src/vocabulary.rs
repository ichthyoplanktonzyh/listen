use crate::lexical::lexical_unit_for_entry;
use crate::*;

impl AppServices {
    pub fn read_lexical_entries_by_forms(
        &self,
        language: &str,
        kind: LexicalEntryKind,
        forms: &[String],
    ) -> Result<Vec<LexicalEntry>, ApplicationError> {
        let language = LanguageCode::parse(language.to_owned())?;
        let mut normalized = std::collections::BTreeSet::new();
        for form in forms {
            let value = match kind {
                LexicalEntryKind::Word => {
                    self.normalize_lexical_form(language.as_str(), form)?
                        .normalized
                }
                LexicalEntryKind::Phrase => normalize_phrase(form),
            };
            if !value.is_empty() {
                normalized.insert(value);
            }
        }
        let normalized = normalized.into_iter().collect::<Vec<_>>();
        self.learning_assets
            .lexical_entries_by_keys(&language, kind, &normalized)
    }

    pub fn create_lexical_observation(
        &self,
        input: CreateLexicalObservation,
    ) -> Result<LexicalObservation, ApplicationError> {
        require_text(&input.original_form, "original_form")?;
        let mut entry = self
            .learning_assets
            .lexical_details(&input.lexical_entry_id)?
            .map(|details| details.entry)
            .ok_or(ApplicationError::NotFound("lexical entry"))?;
        if let Some(source) = input.source.as_ref() {
            if source.end_ms < source.start_ms {
                return Err(ApplicationError::Validation("source context"));
            }
        }
        let created_at_ms = now_ms();
        let observation = self
            .learning_assets
            .create_lexical_observation(&LexicalObservation {
                id: domain::lexical_observation_id(&input.lexical_entry_id, &input.sentence_id),
                lexical_entry_id: input.lexical_entry_id,
                sentence_id: input.sentence_id,
                original_form: input.original_form,
                result: input.result,
                created_at_ms,
            })?;
        if let Some(source) = input.source.as_ref() {
            entry.updated_at_ms = created_at_ms;
            self.learning_assets.upsert_lexical_entry(
                &entry,
                Some(source),
                LearningChangeSource::UserSelection,
            )?;
        }
        if observation.result == ObservationResult::RecognizedInContext {
            self.record_context_recognition_evidence(
                observation.lexical_entry_id.clone(),
                Some(observation.sentence_id.clone()),
                input
                    .source
                    .as_ref()
                    .and_then(|source| source.media_id.clone()),
                RecognitionEvidenceSourceKind::LexicalObservation,
                observation.id.as_str(),
                created_at_ms,
            )?;
        }
        Ok(observation)
    }

    pub fn clear_lexical_observation(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<(), ApplicationError> {
        self.learning_assets
            .clear_lexical_observation(lexical_entry_id, sentence_id)
    }

    pub fn list_vocabulary(
        &self,
        language: &str,
        status: LearningStatus,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LexicalEntryDetails>, ApplicationError> {
        self.learning_assets.list_lexical_entries(
            &LanguageCode::parse(language)?,
            Some(LexicalEntryKind::Word),
            Some(status),
            search,
            limit.min(200),
            offset,
        )
    }

    pub fn export_vocabulary(&self) -> Result<VocabularyAssetBundle, ApplicationError> {
        self.learning_assets.export_assets()
    }

    pub fn import_vocabulary(
        &self,
        bundle: &VocabularyAssetBundle,
    ) -> Result<(), ApplicationError> {
        if bundle.version != 5 {
            return Err(ApplicationError::Validation(
                "unsupported asset bundle version",
            ));
        }
        self.learning_assets.import_assets(bundle)
    }

    pub fn update_lexical_learning_content(
        &self,
        id: &LexicalEntryId,
        user_definition: Option<String>,
        personal_note: Option<String>,
    ) -> Result<LexicalEntryDetails, ApplicationError> {
        self.learning_assets.update_lexical_learning_content(
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
        let language = LanguageCode::parse(input.language.clone())?;
        let mut summary = ExternalVocabularyImportSummary::default();
        let imported_at_ms = now_ms();
        for value in &input.entries {
            let word = normalize_lemma(&value.word);
            if word.is_empty() {
                summary.invalid += 1;
                continue;
            }
            let normalization = self.normalize_lexical_form(language.as_str(), &word)?;
            let existing = self.learning_assets.lexical_entry_by_key(
                &language,
                LexicalEntryKind::Word,
                &normalization.normalized,
            )?;
            if existing.is_some() && !input.overwrite_existing {
                summary.skipped += 1;
                continue;
            }
            let unit = lexical_unit_for_entry(
                &language,
                LexicalEntryKind::Word,
                &normalization.normalized,
                &word,
            );
            let status = value.status.or(input.default_status);
            let id = existing
                .as_ref()
                .map(|entry| entry.id.clone())
                .unwrap_or_else(|| {
                    LexicalEntryId::from_fingerprint("lexical-entry", &unit.identity())
                });
            let entry = LexicalEntry {
                id,
                unit,
                language: language.clone(),
                kind: LexicalEntryKind::Word,
                canonical_form: word.clone(),
                normalized_form: normalization.normalized,
                display_form: word,
                status,
                user_definition: existing
                    .as_ref()
                    .and_then(|entry| entry.user_definition.clone()),
                personal_note: existing
                    .as_ref()
                    .and_then(|entry| entry.personal_note.clone()),
                normalization_provider: normalization.provider,
                normalization_version: normalization.version,
                user_corrected: normalization.user_corrected,
                updated_at_ms: imported_at_ms,
                learning_updated_at_ms: existing
                    .as_ref()
                    .map_or(imported_at_ms, |entry| entry.learning_updated_at_ms),
            };
            self.learning_assets.upsert_lexical_entry(
                &entry,
                None,
                LearningChangeSource::Import,
            )?;
            if existing.is_some() {
                summary.overwritten += 1;
            } else if status.is_some() {
                summary.initialized += 1;
            } else {
                summary.created += 1;
            }
        }
        Ok(summary)
    }

    pub fn set_media_availability(
        &self,
        id: &MediaId,
        availability: MediaAvailability,
    ) -> Result<MediaItem, ApplicationError> {
        self.media.set_availability(id, availability)
    }
}
