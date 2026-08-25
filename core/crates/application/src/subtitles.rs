use content_package::SubtitleTextTrack;
use domain::{MediaId, SubtitleToken, SubtitleTokenKind, SubtitleTrackStatus, TimeMs};

use crate::{
    ApplicationError, ImportSubtitle, LanguageCode, MediaAnalysisUseCases, SubtitleSentence,
    SubtitleSentenceId, SubtitleTrack, SubtitleTrackId, require_text,
};

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
            // A previous version could commit the source track before corpus
            // indexing failed. Existing identity is therefore a recovery
            // signal, not permission to skip projection repair.
            self.reindex_subtitle_track(&existing)?;
            return Ok(existing);
        }
        let occurrences = self.build_subtitle_corpus_occurrences(&track)?;
        self.subtitle_tracks
            .save_track_and_replace_corpus(&track, &occurrences)?;
        Ok(track)
    }

    pub fn update_track_language(
        &self,
        track_id: &SubtitleTrackId,
        language: &LanguageCode,
    ) -> Result<SubtitleTrack, ApplicationError> {
        let mut track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        track.language = Some(language.clone());
        for sentence in &mut track.sentences {
            sentence.tokens = subtitle_core::tokenize(Some(language), &sentence.display_text);
        }
        let occurrences = self.build_subtitle_corpus_occurrences(&track)?;
        self.subtitle_tracks
            .save_track_and_replace_corpus(&track, &occurrences)?;
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

    /// Projects a package `subtitle_text_track` resource into the same subtitle
    /// identity space the media workbench already consumes, then persists it.
    ///
    /// A gen-produced learning package carries timed sentences whose ids are
    /// only stable inside that package. Reading them straight from the package
    /// (as the app's old projection did) made each `cue.id` a package-local id
    /// that Core's sentence-scoped endpoints (`diagnosis`, phrase candidates,
    /// lexical-occurrence source evidence) could never resolve. This method is
    /// the single authority that lands those sentences as real
    /// `subtitle_sentences`: the track and each sentence get a deterministic
    /// global id derived from the material identity, so adopting the same
    /// package is idempotent and the workbench faces one sentence identity
    /// space regardless of whether the text came from a subtitle file or a
    /// package.
    ///
    /// [identity_fingerprint] must be stable for the (material, package
    /// resource) pair — the caller derives it from content-addressed ids, never
    /// from a path or an install timestamp.
    pub(crate) fn adopt_package_subtitle_track(
        &self,
        media_id: &MediaId,
        identity_fingerprint: &str,
        language: &LanguageCode,
        payload: &SubtitleTextTrack,
    ) -> Result<SubtitleTrack, ApplicationError> {
        let track =
            project_package_subtitle_track(media_id, identity_fingerprint, language, payload);
        // The package's own tokens are authoritative; rebuild the corpus
        // projection from them so a word clicked inside the adopted material
        // resolves against the same sent ids diagnosis uses.
        let occurrences = self.build_subtitle_corpus_occurrences(&track)?;
        self.subtitle_tracks
            .save_track_and_replace_corpus(&track, &occurrences)?;
        Ok(track)
    }
}

/// The deterministic projection of a package `subtitle_text_track` into the
/// subtitle identity space. Pure: no repository or clock is involved, so the
/// same (media, fingerprint, payload) always yields the same track id and
/// sentence ids.
fn project_package_subtitle_track(
    media_id: &MediaId,
    identity_fingerprint: &str,
    language: &LanguageCode,
    payload: &SubtitleTextTrack,
) -> SubtitleTrack {
    let track_id = SubtitleTrackId::from_fingerprint(
        "package-subtitle-track",
        &format!("{}:{identity_fingerprint}", media_id.as_str()),
    );
    // Re-adopting the same package reconstructs the same sentence ids, so
    // the `ON CONFLICT(id)` upsert in the repository is idempotent.
    let sentences = payload
        .sentences
        .iter()
        .map(|sentence| {
            let sentence_id = SubtitleSentenceId::from_fingerprint(
                "package-subtitle-sentence",
                &format!(
                    "{}:{}:{}:{}:{}",
                    track_id.as_str(),
                    sentence.index,
                    sentence.start_ms,
                    sentence.end_ms,
                    sentence.display_text
                ),
            );
            SubtitleSentence {
                id: sentence_id,
                index: sentence.index,
                start: TimeMs::new(sentence.start_ms),
                end: TimeMs::new(sentence.end_ms),
                original_text: sentence.original_text.clone(),
                display_text: sentence.display_text.clone(),
                tokens: sentence
                    .tokens
                    .iter()
                    .map(|token| SubtitleToken {
                        index: token.index,
                        kind: match token.kind {
                            content_package::TokenKind::Word => SubtitleTokenKind::Word,
                            content_package::TokenKind::Whitespace => SubtitleTokenKind::Whitespace,
                            content_package::TokenKind::Punctuation => {
                                SubtitleTokenKind::Punctuation
                            }
                            content_package::TokenKind::Other => SubtitleTokenKind::Other,
                        },
                        text: token.text.clone(),
                        normalized: token.normalized.clone(),
                        start_char: token.start_char,
                        end_char: token.end_char,
                    })
                    .collect(),
            }
        })
        .collect();
    SubtitleTrack {
        id: track_id,
        media_id: media_id.clone(),
        fingerprint: identity_fingerprint.to_owned(),
        language: Some(language.clone()),
        source: "package:subtitle_text_track".to_owned(),
        status: SubtitleTrackStatus::Available,
        sentences,
    }
}

#[cfg(test)]
mod tests {
    use super::project_package_subtitle_track;
    use content_package::{SubtitleSentence as PkgSentence, SubtitleSourceKind};
    use domain::MediaId;

    fn payload() -> content_package::SubtitleTextTrack {
        content_package::SubtitleTextTrack {
            language: "en".to_owned(),
            source_kind: SubtitleSourceKind::Asr,
            sentences: vec![PkgSentence {
                id: "local-0".to_owned(),
                index: 0,
                start_ms: 0,
                end_ms: 1200,
                original_text: "Pandas eat bamboo.".to_owned(),
                display_text: "Pandas eat bamboo.".to_owned(),
                tokens: vec![
                    content_package::SubtitleToken {
                        index: 0,
                        kind: content_package::TokenKind::Word,
                        text: "Pandas".to_owned(),
                        normalized: Some("panda".to_owned()),
                        start_char: 0,
                        end_char: 6,
                    },
                    content_package::SubtitleToken {
                        index: 1,
                        kind: content_package::TokenKind::Punctuation,
                        text: ".".to_owned(),
                        normalized: None,
                        start_char: 16,
                        end_char: 17,
                    },
                ],
            }],
        }
    }

    #[test]
    fn projection_replaces_package_local_ids_with_global_subtitle_ids() {
        let media_id = MediaId::from_fingerprint("media", "audio-a");
        let language = domain::LanguageCode::parse("en").unwrap();
        let track = project_package_subtitle_track(
            &media_id,
            "material:rev:resource",
            &language,
            &payload(),
        );

        assert_eq!(track.source, "package:subtitle_text_track");
        assert_eq!(track.media_id, media_id);
        assert_eq!(track.sentences.len(), 1);
        // The package-local id ("local-0") must never leak as the sentence id.
        assert_ne!(
            track.sentences[0].id.as_str(),
            "local-0",
            "package-local ids must be replaced by global subtitle ids"
        );
        assert_eq!(track.sentences[0].index, 0);
        assert_eq!(track.sentences[0].tokens.len(), 2);
        assert_eq!(
            track.sentences[0].tokens[0].kind,
            domain::SubtitleTokenKind::Word
        );
        assert_eq!(
            track.sentences[0].tokens[0].normalized.as_deref(),
            Some("panda")
        );
    }

    #[test]
    fn projection_is_deterministic_and_idempotent() {
        let media_id = MediaId::from_fingerprint("media", "audio-a");
        let language = domain::LanguageCode::parse("en").unwrap();
        let first = project_package_subtitle_track(
            &media_id,
            "material:rev:resource",
            &language,
            &payload(),
        );
        let second = project_package_subtitle_track(
            &media_id,
            "material:rev:resource",
            &language,
            &payload(),
        );
        assert_eq!(first.id, second.id);
        assert_eq!(first.sentences[0].id, second.sentences[0].id);
        assert_eq!(first, second);
    }

    #[test]
    fn different_identity_fingerprint_yields_distinct_track() {
        let media_id = MediaId::from_fingerprint("media", "audio-a");
        let language = domain::LanguageCode::parse("en").unwrap();
        let a = project_package_subtitle_track(&media_id, "m:r:one", &language, &payload());
        let b = project_package_subtitle_track(&media_id, "m:r:two", &language, &payload());
        assert_ne!(a.id, b.id);
        assert_ne!(a.sentences[0].id, b.sentences[0].id);
    }
}
