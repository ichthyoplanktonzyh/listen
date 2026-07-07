use crate::lexical::lexical_unit_for_entry;
use crate::*;

/// Marks capability projections inferred from a legacy linear status write,
/// as opposed to the one-shot v22 backfill
/// (`LEGACY_STATUS_MIGRATION_ALGORITHM_VERSION`).
pub(crate) const LEGACY_STATUS_COMPAT_ALGORITHM_VERSION: &str = "legacy-status-compat-v1";

/// Where a channelized observation happened (ADR 0017). Kept as a struct so
/// writer call sites stay within argument-count discipline.
pub(crate) struct ObservationContext {
    pub surface_form: Option<String>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub media_id: Option<MediaId>,
}

impl AppServices {
    pub fn lexical_capability_profile(
        &self,
        lexical_entry_id: &LexicalEntryId,
    ) -> Result<Option<LexicalCapabilityProfile>, ApplicationError> {
        self.learning_assets
            .lexical_capability_profile(lexical_entry_id, None)
    }

    pub fn set_lexical_capability_override(
        &self,
        lexical_entry_id: &LexicalEntryId,
        capability: LexicalCapability,
        conclusion: Option<CapabilityConclusion>,
    ) -> Result<LexicalCapabilityProfile, ApplicationError> {
        let now = now_ms();
        let user_override = conclusion.map(|conclusion| CapabilityOverride {
            conclusion,
            source: CapabilityOverrideSource::UserSelection,
            updated_at_ms: now,
        });
        let profile = self.learning_assets.set_lexical_capability_override(
            lexical_entry_id,
            None,
            capability,
            user_override,
            now,
        )?;
        self.sync_legacy_status_from_profile(lexical_entry_id, &profile)?;
        Ok(profile)
    }

    /// Projects a legacy linear status write into the capability profile.
    ///
    /// `source` must state where the legacy status came from
    /// (`LegacyLearningStatusMigration` for live compat syncs of user-facing
    /// legacy writes, `Import` for external vocabulary imports); the shared
    /// algorithm version marks the mapping as a compat inference either way.
    /// `EvidenceProjection` is reserved for real evidence-derived projections.
    pub(crate) fn sync_capability_from_legacy_status(
        &self,
        lexical_entry_id: &LexicalEntryId,
        status: Option<LearningStatus>,
        changed_at_ms: u64,
        source: CapabilityProjectionSource,
    ) -> Result<(), ApplicationError> {
        let target =
            LexicalCapabilityProfile::from_legacy_status(lexical_entry_id.clone(), status, changed_at_ms);
        for capability in [LexicalCapability::Reading, LexicalCapability::Listening] {
            let dim = target.dimension(capability);
            if let Some(proj) = &dim.projection {
                let current = self
                    .learning_assets
                    .lexical_capability_profile(lexical_entry_id, None)?;
                let current_dim = current
                    .as_ref()
                    .map(|p| p.dimension(capability))
                    .cloned()
                    .unwrap_or_default();
                if current_dim.user_override.is_some() {
                    continue;
                }
                self.learning_assets.set_lexical_capability_projection(
                    lexical_entry_id,
                    None,
                    capability,
                    Some(CapabilityProjection {
                        conclusion: proj.conclusion,
                        source,
                        algorithm_version: LEGACY_STATUS_COMPAT_ALGORITHM_VERSION.into(),
                        confidence: None,
                        evidence_as_of_ms: None,
                        updated_at_ms: changed_at_ms,
                    }),
                    changed_at_ms,
                )?;
            } else {
                let current = self
                    .learning_assets
                    .lexical_capability_profile(lexical_entry_id, None)?;
                let current_dim = current
                    .as_ref()
                    .map(|p| p.dimension(capability))
                    .cloned()
                    .unwrap_or_default();
                if current_dim.user_override.is_some() || current_dim.projection.is_none() {
                    continue;
                }
                self.learning_assets.set_lexical_capability_projection(
                    lexical_entry_id,
                    None,
                    capability,
                    None,
                    changed_at_ms,
                )?;
            }
        }
        Ok(())
    }

    pub(crate) fn sync_legacy_status_from_profile(
        &self,
        lexical_entry_id: &LexicalEntryId,
        profile: &LexicalCapabilityProfile,
    ) -> Result<(), ApplicationError> {
        let legacy = profile.legacy_status_view();
        let details = self.learning_assets.lexical_details(lexical_entry_id)?;
        if let Some(mut details) = details {
            if details.entry.status != legacy {
                details.entry.status = legacy;
                details.entry.updated_at_ms = now_ms();
                details.entry.learning_updated_at_ms = details.entry.updated_at_ms;
                self.learning_assets.upsert_lexical_entry(
                    &details.entry,
                    None,
                    LearningChangeSource::CapabilityOverrideSync,
                )?;
            }
        }
        Ok(())
    }

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

    /// Single writer entry for channelized evidence: builds the append-only
    /// identity and defers channel semantics to the domain mapping (ADR 0017
    /// guardrail: call sites must not inline channel judgments).
    pub(crate) fn append_channelized_observation(
        &self,
        lexical_entry_id: &LexicalEntryId,
        spec: ObservationSpec,
        context: ObservationContext,
        origin: ObservationOrigin,
        source_ref: Option<String>,
        occurred_at_ms: u64,
    ) -> Result<(), ApplicationError> {
        let observation = LearningObservation {
            id: learning_observation_id(
                lexical_entry_id,
                spec.task_type,
                spec.outcome,
                source_ref.as_deref(),
                occurred_at_ms,
            ),
            lexical_entry_id: lexical_entry_id.clone(),
            sense_id: None,
            capability: spec.capability,
            task_type: spec.task_type,
            outcome: spec.outcome,
            assistance: spec.assistance,
            surface_form: context.surface_form,
            sentence_id: context.sentence_id,
            media_id: context.media_id,
            origin,
            source_ref,
            occurred_at_ms,
        };
        self.learning_assets
            .append_learning_observation(&observation)?;
        Ok(())
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
        self.append_channelized_observation(
            &observation.lexical_entry_id,
            observation_spec_for_marking(observation.result),
            ObservationContext {
                surface_form: Some(observation.original_form.clone()),
                sentence_id: Some(observation.sentence_id.clone()),
                media_id: input
                    .source
                    .as_ref()
                    .and_then(|source| source.media_id.clone()),
            },
            ObservationOrigin::UserMarking,
            Some(observation.id.as_str().to_owned()),
            created_at_ms,
        )?;
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
        if bundle.version != 5 && bundle.version != 6 {
            return Err(ApplicationError::Validation(
                "unsupported asset bundle version",
            ));
        }
        let mut effective = bundle.clone();
        if bundle.version == 5 && bundle.capability_profiles.is_empty() {
            effective.capability_profiles = bundle
                .lexical_entries
                .iter()
                .filter(|e| e.status.is_some())
                .map(|e| {
                    LexicalCapabilityProfile::from_legacy_status(
                        e.id.clone(),
                        e.status,
                        e.learning_updated_at_ms,
                    )
                })
                .collect();
        }
        self.learning_assets.import_assets(&effective)
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
            if status.is_some() {
                self.sync_capability_from_legacy_status(
                    &entry.id,
                    status,
                    imported_at_ms,
                    CapabilityProjectionSource::Import,
                )?;
            }
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
