use crate::*;

impl AppServices {
    /// Rebuild the local corpus projection for one subtitle track. The Slice 3
    /// shape indexes exact word forms, sentence-level text for confirmed phrase
    /// lookup, and — when an active chunk timeline exists — precise chunk spans;
    /// connected-speech kinds can join this same projection when their
    /// providers become queryable.
    pub(crate) fn reindex_subtitle_track(
        &self,
        track: &SubtitleTrack,
    ) -> Result<(), ApplicationError> {
        let language = track.language.clone().unwrap_or(LanguageCode::parse("en")?);
        let mut occurrences = Vec::new();
        for sentence in &track.sentences {
            let sentence_id = sentence.id.clone();
            let source_snapshot = sentence.display_text.clone();
            occurrences.push(CorpusOccurrence {
                id: CorpusOccurrenceId::from_fingerprint(
                    "corpus-occurrence",
                    &format!("{}:sentence", sentence_id.as_str()),
                ),
                language: language.clone(),
                kind: CorpusOccurrenceKind::Phrase,
                normalized_key: Some(normalize_phrase(&sentence.display_text)),
                display_text: sentence.display_text.clone(),
                media_id: Some(track.media_id.clone()),
                track_id: Some(track.id.clone()),
                sentence_id: Some(sentence_id.clone()),
                start_ms: sentence.start.get(),
                end_ms: sentence.end.get(),
                source_snapshot: source_snapshot.clone(),
            });
            for token in sentence
                .tokens
                .iter()
                .filter(|token| token.kind == SubtitleTokenKind::Word && token.normalized.is_some())
            {
                occurrences.push(CorpusOccurrence {
                    id: CorpusOccurrenceId::from_fingerprint(
                        "corpus-occurrence",
                        &format!("{}:token:{}", sentence_id.as_str(), token.index),
                    ),
                    language: language.clone(),
                    kind: CorpusOccurrenceKind::Lexical,
                    normalized_key: token.normalized.clone(),
                    display_text: token.text.clone(),
                    media_id: Some(track.media_id.clone()),
                    track_id: Some(track.id.clone()),
                    sentence_id: Some(sentence_id.clone()),
                    start_ms: sentence.start.get(),
                    end_ms: sentence.end.get(),
                    source_snapshot: source_snapshot.clone(),
                });
            }
        }
        if let Some(timeline) = self.timelines.active_chunk_timeline(&track.id)? {
            for chunk in &timeline.chunks {
                occurrences.push(CorpusOccurrence {
                    id: CorpusOccurrenceId::from_fingerprint(
                        "corpus-occurrence",
                        &format!("{}:chunk:{}", chunk.sentence_id.as_str(), chunk.chunk_index),
                    ),
                    language: language.clone(),
                    kind: CorpusOccurrenceKind::Chunk,
                    normalized_key: Some(normalize_phrase(&chunk.text)),
                    display_text: chunk.text.clone(),
                    media_id: Some(track.media_id.clone()),
                    track_id: Some(track.id.clone()),
                    sentence_id: Some(chunk.sentence_id.clone()),
                    start_ms: chunk.start_ms,
                    end_ms: chunk.end_ms,
                    source_snapshot: chunk.text.clone(),
                });
            }
        }
        self.corpus
            .replace_corpus_occurrences_for_track(&track.id, &occurrences)
    }

    /// Reindex after a lifecycle change that only knows the track id (chunk
    /// timeline activation/retirement). A missing track is not an error: the
    /// projection is rebuildable and the cascade already dropped its rows.
    pub(crate) fn reindex_track_corpus(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<(), ApplicationError> {
        if let Some(track) = self.subtitle_tracks.get_track(track_id)? {
            self.reindex_subtitle_track(&track)?;
        }
        Ok(())
    }

    /// Full rebuild over every imported media's subtitle tracks — the recovery
    /// entry for libraries imported before the corpus projection existed.
    /// Returns the number of tracks reindexed.
    pub fn rebuild_corpus_index(&self) -> Result<u32, ApplicationError> {
        let mut indexed_tracks = 0u32;
        for media in self.media.list()? {
            for track in self.subtitle_tracks.list_tracks_for_media(&media.id)? {
                self.reindex_subtitle_track(&track)?;
                indexed_tracks += 1;
            }
        }
        Ok(indexed_tracks)
    }

    pub fn search_corpus(
        &self,
        language: &str,
        query: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        let language = LanguageCode::parse(language)?;
        let query = clean_required(query.to_owned(), "query")?;
        self.corpus
            .search_corpus_occurrences(&language, &query, limit.clamp(1, 100), offset)
    }
}
