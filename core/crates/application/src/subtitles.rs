use crate::*;

impl MediaAnalysisUseCases {
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
            .subtitle_tracks
            .get_by_media_fingerprint(&track.media_id, &track.fingerprint)?
        {
            return Ok(existing);
        }
        self.subtitle_tracks.save_track(&track)?;
        self.reindex_subtitle_track(&track)?;
        Ok(track)
    }

    pub fn update_track_language(
        &self,
        track_id: &SubtitleTrackId,
        language: &LanguageCode,
    ) -> Result<SubtitleTrack, ApplicationError> {
        let track = self
            .subtitle_tracks
            .set_track_language(track_id, language)?;
        self.reindex_subtitle_track(&track)?;
        Ok(track)
    }

    pub fn read_subtitle_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<SubtitleTrack>, ApplicationError> {
        self.subtitle_tracks.get_track(track_id)
    }

    pub fn read_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Option<SubtitleSentence>, ApplicationError> {
        self.subtitle_tracks.get_sentence(sentence_id)
    }

    /// Resolve the learning language for a sentence from its subtitle track,
    /// falling back to English when the track declares none. This keeps
    /// diagnosis and phrase detection language-aware instead of assuming `en`.
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
