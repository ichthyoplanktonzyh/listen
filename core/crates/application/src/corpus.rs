use crate::*;

impl AppServices {
    /// Rebuild the local corpus projection for one subtitle track. The Slice 3
    /// shape indexes lemma-keyed word forms, sentence-level text for confirmed
    /// phrase lookup, and — when an active chunk timeline exists — precise
    /// chunk spans; connected-speech kinds can join this same projection when
    /// their providers become queryable.
    ///
    /// Word keys go through [`Self::normalize_lexical_form`] (user override →
    /// provider lemma → baseline), the same path lexical entries use, so an
    /// entry-driven or free-text lemma query matches inflected tokens. Tracks
    /// indexed before this rule need one manual rebuild to gain lemma keys.
    pub(crate) fn reindex_subtitle_track(
        &self,
        track: &SubtitleTrack,
    ) -> Result<(), ApplicationError> {
        let language = track.language.clone().unwrap_or(LanguageCode::parse("en")?);
        // One provider round per distinct surface per track; provider failure
        // degrades to the tokenizer's baseline key instead of failing import.
        let mut lemma_cache: std::collections::HashMap<String, String> =
            std::collections::HashMap::new();
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
                let surface_key = token.normalized.clone().expect("filtered to Some");
                let normalized_key = match lemma_cache.get(&surface_key) {
                    Some(hit) => hit.clone(),
                    None => {
                        let key = self
                            .normalize_lexical_form(language.as_str(), &surface_key)
                            .map(|normalization| normalization.normalized)
                            .unwrap_or_else(|_| surface_key.clone());
                        lemma_cache.insert(surface_key.clone(), key.clone());
                        key
                    }
                };
                occurrences.push(CorpusOccurrence {
                    id: CorpusOccurrenceId::from_fingerprint(
                        "corpus-occurrence",
                        &format!("{}:token:{}", sentence_id.as_str(), token.index),
                    ),
                    language: language.clone(),
                    kind: CorpusOccurrenceKind::Lexical,
                    normalized_key: Some(normalized_key),
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
        // A single-word query goes through the same normalization path as
        // lexical entries and the index's token keys, so "Running" finds the
        // lemma-keyed "run" rows; provider failure degrades to the raw query.
        let query = if query.contains(char::is_whitespace) {
            query
        } else {
            self.normalize_lexical_form(language.as_str(), &query)
                .map(|normalization| normalization.normalized)
                .unwrap_or(query)
        };
        self.corpus
            .search_corpus_occurrences(&language, &query, limit.clamp(1, 100), offset)
    }
}
