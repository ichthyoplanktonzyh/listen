use crate::*;

#[derive(Clone)]
pub struct PronunciationUseCases {
    pronunciations: Arc<dyn PronunciationRepository>,
    subtitle_tracks: Arc<dyn SubtitleTrackRepository>,
    word_timelines: Arc<dyn WordTimelineRepository>,
    providers: Arc<Vec<Arc<dyn PronunciationProvider>>>,
}

impl PronunciationUseCases {
    pub(crate) fn new(
        pronunciations: Arc<dyn PronunciationRepository>,
        subtitle_tracks: Arc<dyn SubtitleTrackRepository>,
        word_timelines: Arc<dyn WordTimelineRepository>,
        providers: Arc<Vec<Arc<dyn PronunciationProvider>>>,
    ) -> Self {
        Self {
            pronunciations,
            subtitle_tracks,
            word_timelines,
            providers,
        }
    }

    pub fn pronunciation_providers(&self) -> Vec<PronunciationProviderInfo> {
        self.providers.iter().map(|p| p.info()).collect()
    }

    pub fn pronunciation_rules(&self, language: &str) -> serde_json::Value {
        let primary = language.split('-').next().unwrap_or(language);
        for provider in self.providers.iter() {
            let info = provider.info();
            if info.languages.iter().any(|l| l == primary || l == language) {
                let catalog = provider.rule_catalog();
                if catalog != serde_json::json!([]) {
                    return serde_json::json!({
                        "analyzer_id": info.id,
                        "version": info.version,
                        "evidence_source": "deterministic_text_rule",
                        "disclaimer": "Rule predictions are contextual possibilities, not detections from the audio.",
                        "rules": catalog,
                    });
                }
            }
        }
        serde_json::json!({"rules": []})
    }

    pub fn lookup_pronunciation(
        &self,
        language: &str,
        word: &str,
    ) -> Result<WordPronunciation, ApplicationError> {
        require_text(word, "word")?;
        let primary = language.split('-').next().unwrap_or(language);
        let normalized = normalize_lemma(word);
        for provider in self.providers.iter() {
            let info = provider.info();
            if !info.languages.iter().any(|l| l == primary || l == language) {
                continue;
            }
            if let Some(value) = self.pronunciations.get_word_pronunciation(
                primary,
                language,
                &normalized,
                &info.id,
                &info.version,
            )? {
                return Ok(value);
            }
            if let Some(value) = provider.lookup_word(word, 0) {
                self.pronunciations.save_word_pronunciation(
                    primary,
                    language,
                    &value,
                    &info.id,
                    &info.version,
                )?;
                return Ok(value);
            }
        }
        Err(ApplicationError::NotFound(
            "pronunciation provider for language",
        ))
    }

    pub fn analyze_pronunciation(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<SentencePronunciation, ApplicationError> {
        let language = self.sentence_language(sentence_id)?;
        let profile = domain::profile_for(&language);
        if profile.pronunciation == "core.none" {
            return Err(ApplicationError::NotFound("pronunciation for language"));
        }
        if let Some(value) = self.pronunciations.get_pronunciation(sentence_id)? {
            let still_valid = self.providers.iter().any(|p| {
                let info = p.info();
                info.id == value.provider_id && info.version == value.provider_version
            });
            if still_valid {
                return Ok(value);
            }
        }
        let sentence = self
            .subtitle_tracks
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let primary = language
            .as_str()
            .split('-')
            .next()
            .unwrap_or(language.as_str());
        for provider in self.providers.iter() {
            let info = provider.info();
            if !info
                .languages
                .iter()
                .any(|l| l == primary || l == language.as_str())
            {
                continue;
            }
            if let Some(value) = provider.analyze_sentence(&sentence) {
                self.pronunciations.save_pronunciation(&value)?;
                return Ok(value);
            }
        }
        Err(ApplicationError::NotFound(
            "pronunciation provider for language",
        ))
    }

    pub fn pronunciation_cache_state(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Option<bool>, ApplicationError> {
        Ok(self
            .pronunciations
            .get_pronunciation(sentence_id)?
            .map(|value| {
                self.providers.iter().any(|p| {
                    let info = p.info();
                    info.id == value.provider_id && info.version == value.provider_version
                })
            }))
    }

    pub fn word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        let existing = self.word_timelines.get_word_timings(sentence_id)?;
        if word_timing_cache_is_usable(&existing) {
            return Ok(existing);
        }
        let language = self.sentence_language(sentence_id)?;
        let profile = domain::profile_for(&language);
        if profile.word_timeline == CapabilitySupport::Unsupported {
            return Ok(Vec::new());
        }
        let sentence = self
            .subtitle_tracks
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let values = speech_analysis::estimate_word_timings_with_rhythm(
            &sentence,
            Some(profile.rhythm_prosody.as_str()),
        );
        self.word_timelines
            .save_word_timings(sentence_id, &values)?;
        Ok(values)
    }

    pub fn word_timing_cache_state(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Option<bool>, ApplicationError> {
        let values = self.word_timelines.get_word_timings(sentence_id)?;
        Ok(values.first().map(|_| word_timing_cache_is_usable(&values)))
    }

    pub fn analyze_pronunciation_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SentencePronunciation>, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        Ok(track
            .sentences
            .iter()
            .filter_map(|sentence| self.analyze_pronunciation(&sentence.id).ok())
            .collect())
    }

    pub fn word_timings_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        if let Some(timeline) = self.word_timelines.active_word_timeline(track_id)?
            && !timeline.words.is_empty()
        {
            return Ok(timeline.words);
        }
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let mut values = Vec::new();
        for sentence in track.sentences {
            values.extend(self.word_timings(&sentence.id)?);
        }
        Ok(values)
    }

    fn sentence_language(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<LanguageCode, ApplicationError> {
        match self.subtitle_tracks.sentence_track_language(sentence_id)? {
            Some(language) => Ok(language),
            None => Ok(LanguageCode::parse("en")?),
        }
    }
}
