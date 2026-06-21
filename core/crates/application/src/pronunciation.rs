use crate::*;

impl AppServices {
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
        if word_timing_cache_is_usable(&existing) {
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
        Ok(values.first().map(|_| word_timing_cache_is_usable(&values)))
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
        if let Some(timeline) = self.subtitles.active_word_timeline(track_id)?
            && !timeline.words.is_empty()
        {
            return Ok(timeline.words);
        }
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
}
