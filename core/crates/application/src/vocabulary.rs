use crate::*;

impl AppServices {
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
        if bundle.version != 1 && bundle.version != 2 && bundle.version != 3 && bundle.version != 4
        {
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
}
