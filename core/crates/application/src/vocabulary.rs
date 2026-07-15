use crate::lexical::lexical_unit_for_entry;
use crate::{
    ApplicationError, CapabilityConclusion, CapabilityFilter, CapabilityOverride,
    CapabilityOverrideSource, CapabilityProjection, CapabilityProjectionSource,
    CreateLexicalObservation, ExternalVocabularyImport, ExternalVocabularyImportSummary,
    LISTENING_CONFIDENCE_TASK, LanguageCode, LearningChangeSource, LearningObservation,
    LearningStatus, LexicalCapability, LexicalCapabilityProfile, LexicalEntry, LexicalEntryDetails,
    LexicalEntryId, LexicalEntryKind, LexicalLearningUseCases, LexicalObservation,
    LexicalOccurrenceId, LexicalSenseFolder, LexicalSenseId, MediaAvailability, MediaId, MediaItem,
    ObservationOrigin, ObservationResult, ObservationSpec, RecognitionEvidenceSourceKind,
    SubtitleSentenceId, VocabularyAssetBundle, clean_optional, clean_required,
    learning_observation_id, listening_projection_v1, normalize_lemma, normalize_phrase, now_ms,
    observation_spec_for_marking, observation_spec_for_reading_marking, require_text,
};

/// Marks capability projections inferred from a legacy linear status write,
/// as opposed to the one-shot v22 backfill
/// (`LEGACY_STATUS_MIGRATION_ALGORITHM_VERSION`).
pub(crate) const LEGACY_STATUS_COMPAT_ALGORITHM_VERSION: &str = "legacy-status-compat-v1";

/// Bounded evidence read for `listening-projection-v1` recomputes (ADR 0019).
/// The rule only inspects recent decisive events; 200 newest rows is ample.
pub(crate) const LISTENING_PROJECTION_EVIDENCE_LIMIT: u32 = 200;

/// Where a channelized observation happened (ADR 0017). Kept as a struct so
/// writer call sites stay within argument-count discipline.
pub(crate) struct ObservationContext {
    pub surface_form: Option<String>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub media_id: Option<MediaId>,
}

impl LexicalLearningUseCases {
    pub fn create_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        label: String,
        definition: Option<String>,
        gloss: Option<String>,
        external_ref: Option<String>,
    ) -> Result<LexicalSenseFolder, ApplicationError> {
        if self
            .lexical_entries
            .lexical_details(lexical_entry_id)?
            .is_none()
        {
            return Err(ApplicationError::NotFound("lexical entry"));
        }
        let label = clean_required(label, "sense folder label")?;
        let now = now_ms();
        let folder = LexicalSenseFolder {
            id: LexicalSenseId::from_fingerprint(
                "lexical-sense-folder",
                &format!("{}:{label}:{now}", lexical_entry_id.as_str()),
            ),
            lexical_entry_id: lexical_entry_id.clone(),
            label,
            definition: clean_optional(definition),
            gloss: clean_optional(gloss),
            external_ref: clean_optional(external_ref),
            created_at_ms: now,
            updated_at_ms: now,
        };
        self.lexical_content.create_lexical_sense_folder(&folder)
    }

    pub fn update_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
        label: String,
        definition: Option<String>,
        gloss: Option<String>,
        external_ref: Option<String>,
    ) -> Result<LexicalSenseFolder, ApplicationError> {
        let folder = LexicalSenseFolder {
            id: sense_id.clone(),
            lexical_entry_id: lexical_entry_id.clone(),
            label: clean_required(label, "sense folder label")?,
            definition: clean_optional(definition),
            gloss: clean_optional(gloss),
            external_ref: clean_optional(external_ref),
            created_at_ms: 0,
            updated_at_ms: now_ms(),
        };
        self.lexical_content.update_lexical_sense_folder(&folder)
    }

    pub fn delete_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
    ) -> Result<(), ApplicationError> {
        self.lexical_content
            .delete_lexical_sense_folder(lexical_entry_id, sense_id)
    }

    pub fn assign_occurrence_to_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
        occurrence_id: &LexicalOccurrenceId,
    ) -> Result<(), ApplicationError> {
        self.lexical_content
            .assign_occurrence_to_lexical_sense_folder(lexical_entry_id, sense_id, occurrence_id)
    }

    pub fn unassign_occurrence_from_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
        occurrence_id: &LexicalOccurrenceId,
    ) -> Result<(), ApplicationError> {
        self.lexical_content
            .unassign_occurrence_from_lexical_sense_folder(
                lexical_entry_id,
                sense_id,
                occurrence_id,
            )
    }

    pub fn lexical_capability_profile(
        &self,
        lexical_entry_id: &LexicalEntryId,
    ) -> Result<Option<LexicalCapabilityProfile>, ApplicationError> {
        self.lexical_capabilities
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
        let profile = self.lexical_capabilities.set_lexical_capability_override(
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
        let target = LexicalCapabilityProfile::from_legacy_status(
            lexical_entry_id.clone(),
            status,
            changed_at_ms,
        );
        for capability in [LexicalCapability::Reading, LexicalCapability::Listening] {
            let dim = target.dimension(capability);
            if let Some(proj) = &dim.projection {
                let current = self
                    .lexical_capabilities
                    .lexical_capability_profile(lexical_entry_id, None)?;
                let current_dim = current
                    .as_ref()
                    .map(|p| p.dimension(capability))
                    .cloned()
                    .unwrap_or_default();
                if current_dim.user_override.is_some() {
                    continue;
                }
                // Writer ladder (ADR 0019 decision 3): compat may not upgrade
                // over a task-grade evidence conclusion (a self-reported
                // "认识" cannot overturn task failure). Downgrades and clears
                // stay allowed, and weakened evidence conclusions may be
                // overwritten by explicit user judgment.
                if proj.conclusion == CapabilityConclusion::Acquired
                    && current_dim.projection.as_ref().is_some_and(|value| {
                        value.source == CapabilityProjectionSource::EvidenceProjection
                            && value
                                .confidence
                                .is_some_and(|c| c >= LISTENING_CONFIDENCE_TASK)
                    })
                {
                    continue;
                }
                self.lexical_capabilities
                    .set_lexical_capability_projection(
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
                    .lexical_capabilities
                    .lexical_capability_profile(lexical_entry_id, None)?;
                let current_dim = current
                    .as_ref()
                    .map(|p| p.dimension(capability))
                    .cloned()
                    .unwrap_or_default();
                if current_dim.user_override.is_some() || current_dim.projection.is_none() {
                    continue;
                }
                self.lexical_capabilities
                    .set_lexical_capability_projection(
                        lexical_entry_id,
                        None,
                        capability,
                        None,
                        changed_at_ms,
                    )?;
            }
        }
        // Re-derive the legacy status column from the profile: the writer
        // ladder may have kept a task-grade evidence conclusion, and callers
        // write the raw status onto the entry row before syncing.
        if let Some(profile) = self
            .lexical_capabilities
            .lexical_capability_profile(lexical_entry_id, None)?
        {
            self.sync_legacy_status_from_profile(lexical_entry_id, &profile)?;
        }
        Ok(())
    }

    pub(crate) fn sync_legacy_status_from_profile(
        &self,
        lexical_entry_id: &LexicalEntryId,
        profile: &LexicalCapabilityProfile,
    ) -> Result<(), ApplicationError> {
        let legacy = profile.legacy_status_view();
        let details = self.lexical_entries.lexical_details(lexical_entry_id)?;
        if let Some(mut details) = details
            && details.entry.status != legacy
        {
            details.entry.status = legacy;
            details.entry.updated_at_ms = now_ms();
            details.entry.learning_updated_at_ms = details.entry.updated_at_ms;
            self.lexical_entries.upsert_lexical_entry(
                &details.entry,
                None,
                LearningChangeSource::CapabilityOverrideSync,
            )?;
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
        self.lexical_entries
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
        self.learning_observations
            .append_learning_observation(&observation)?;
        if spec.capability == LexicalCapability::Listening {
            self.reproject_listening_from_evidence(lexical_entry_id, occurred_at_ms)?;
        }
        Ok(())
    }

    /// Recomputes the listening projection from the channelized evidence
    /// stream (ADR 0019, `listening-projection-v1`) and refreshes the legacy
    /// status compat view. Runs after every listening observation append —
    /// all writers funnel through [`Self::append_channelized_observation`].
    pub(crate) fn reproject_listening_from_evidence(
        &self,
        lexical_entry_id: &LexicalEntryId,
        now: u64,
    ) -> Result<(), ApplicationError> {
        let observations = self.learning_observations.list_learning_observations(
            lexical_entry_id,
            Some(LexicalCapability::Listening),
            LISTENING_PROJECTION_EVIDENCE_LIMIT,
            0,
        )?;
        let Some(projection) = listening_projection_v1(&observations, now) else {
            return Ok(());
        };
        // Recency guard (ADR 0019 decision 2): a non-evidence writer (compat
        // downgrade, import) newer than our newest decisive evidence wins
        // until newer evidence arrives.
        let current = self
            .lexical_capabilities
            .lexical_capability_profile(lexical_entry_id, None)?;
        if let Some(existing) = current.as_ref().and_then(|profile| {
            profile
                .dimension(LexicalCapability::Listening)
                .projection
                .as_ref()
        }) && existing.source != CapabilityProjectionSource::EvidenceProjection
            && projection
                .evidence_as_of_ms
                .is_some_and(|as_of| existing.updated_at_ms > as_of)
        {
            return Ok(());
        }
        let profile = self
            .lexical_capabilities
            .set_lexical_capability_projection(
                lexical_entry_id,
                None,
                LexicalCapability::Listening,
                Some(projection),
                now,
            )?;
        self.sync_legacy_status_from_profile(lexical_entry_id, &profile)?;
        Ok(())
    }

    /// Reading-posture word marking (Phase 3.13 Slice 5): one explicit user
    /// act on one word writes exactly one reading-channel observation.
    /// Deliberately narrower than the listening marking path — no legacy
    /// `LexicalObservation` row, no recognition evidence, and no projection
    /// (reading has no qualified automatic projection until 3.17; the
    /// channelized writer only reprojects the listening channel).
    pub fn record_reading_marking(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sentence_id: Option<&SubtitleSentenceId>,
        surface_form: &str,
        media_id: Option<MediaId>,
        translation_visible: bool,
        understood: bool,
    ) -> Result<(), ApplicationError> {
        require_text(surface_form, "surface_form")?;
        self.lexical_entries
            .lexical_details(lexical_entry_id)?
            .ok_or(ApplicationError::NotFound("lexical entry"))?;
        let occurred_at_ms = now_ms();
        self.append_channelized_observation(
            lexical_entry_id,
            observation_spec_for_reading_marking(understood, translation_visible),
            ObservationContext {
                surface_form: Some(surface_form.to_owned()),
                sentence_id: sentence_id.cloned(),
                media_id,
            },
            ObservationOrigin::UserMarking,
            sentence_id.map(|id| format!("reading-marking:{}", id.as_str())),
            occurred_at_ms,
        )
    }

    pub fn create_lexical_observation(
        &self,
        input: CreateLexicalObservation,
    ) -> Result<LexicalObservation, ApplicationError> {
        require_text(&input.original_form, "original_form")?;
        let mut entry = self
            .lexical_entries
            .lexical_details(&input.lexical_entry_id)?
            .map(|details| details.entry)
            .ok_or(ApplicationError::NotFound("lexical entry"))?;
        if let Some(source) = input.source.as_ref()
            && source.end_ms < source.start_ms
        {
            return Err(ApplicationError::Validation("source context"));
        }
        let created_at_ms = now_ms();
        let observation =
            self.learning_observations
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
            self.lexical_entries.upsert_lexical_entry(
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
        self.learning_observations
            .clear_lexical_observation(lexical_entry_id, sentence_id)
    }

    /// Lists the vocabulary book. `kind` `None` returns both words and phrases;
    /// `status` and `capability_filter` are optional, additive filters (the
    /// legacy status axis stays available while the four-channel capability axis
    /// becomes the primary lens).
    // Mirrors the repository's validated query axes at the HTTP use-case seam.
    #[allow(clippy::too_many_arguments)]
    pub fn list_vocabulary(
        &self,
        language: &str,
        kind: Option<LexicalEntryKind>,
        status: Option<LearningStatus>,
        capability_filter: Option<CapabilityFilter>,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LexicalEntryDetails>, ApplicationError> {
        self.lexical_entries.list_lexical_entries(
            &LanguageCode::parse(language)?,
            kind,
            status,
            capability_filter,
            search,
            limit.min(200),
            offset,
        )
    }

    pub fn export_vocabulary(&self) -> Result<VocabularyAssetBundle, ApplicationError> {
        self.vocabulary_assets.export_assets()
    }

    pub fn import_vocabulary(
        &self,
        bundle: &VocabularyAssetBundle,
    ) -> Result<(), ApplicationError> {
        if bundle.version != 5 && bundle.version != 6 && bundle.version != 7 {
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
        self.vocabulary_assets.import_assets(&effective)
    }

    pub fn update_lexical_learning_content(
        &self,
        id: &LexicalEntryId,
        user_definition: Option<String>,
        personal_note: Option<String>,
    ) -> Result<LexicalEntryDetails, ApplicationError> {
        self.lexical_content.update_lexical_learning_content(
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
            let existing = self.lexical_entries.lexical_entry_by_key(
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
            self.lexical_entries.upsert_lexical_entry(
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
