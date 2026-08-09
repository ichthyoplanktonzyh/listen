use std::collections::HashMap;

use crate::{
    ApplicationError, CorpusOccurrence, CorpusOccurrenceId, CorpusOccurrenceKind,
    L1SpecialtyOccurrences, LLTimelineRhythmFrame, LanguageCode, MediaAnalysisUseCases,
    ProsodicChunkProjection, SubtitleTokenKind, SubtitleTrack, SubtitleTrackId, clean_required,
    normalize_phrase,
};

impl MediaAnalysisUseCases {
    /// Rebuild the local corpus projection for one subtitle track. The Slice 3
    /// shape indexes lemma-keyed word forms, sentence-level text for confirmed
    /// phrase lookup, and — when an active Prosody Analysis exists — precise
    /// prosodic chunk spans (the R5 successor of the retired ChunkTimeline
    /// chunk projection); connected-speech kinds can join this same projection
    /// when their providers become queryable.
    ///
    /// Word keys go through [`Self::normalize_lexical_form`] (user override →
    /// provider lemma → baseline), the same path lexical entries use, so an
    /// entry-driven or free-text lemma query matches inflected tokens. Tracks
    /// indexed before this rule need one manual rebuild to gain lemma keys.
    pub(crate) fn build_subtitle_corpus_occurrences(
        &self,
        track: &SubtitleTrack,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        let rhythm_frames = self
            .export_lltimeline_document(&track.id)
            .map(|document| document.rhythm_frames)
            .unwrap_or_default();
        let prosody_chunks = self.prosody_chunk_projections_for_track(&track.id)?;
        self.build_subtitle_corpus_occurrences_from_resources(
            track,
            &prosody_chunks,
            &rhythm_frames,
        )
    }

    /// Builds the projection from an already validated import snapshot.
    ///
    /// Unlike the ordinary rebuild path, this does not read resources that
    /// have not been committed yet. The resulting rows can therefore join the
    /// source track and all imported resources in one persistence transaction.
    pub(crate) fn build_subtitle_corpus_occurrences_from_resources(
        &self,
        track: &SubtitleTrack,
        prosody_chunks: &[ProsodicChunkProjection],
        rhythm_frames: &[LLTimelineRhythmFrame],
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
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
                            .lexical_learning()
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
        for chunk in prosody_chunks {
            let Some(sentence) = track
                .sentences
                .iter()
                .find(|sentence| sentence.id == chunk.sentence_id)
            else {
                continue;
            };
            let text = chunk_text_from_projection(sentence, chunk);
            if text.is_empty() {
                continue;
            }
            occurrences.push(CorpusOccurrence {
                id: CorpusOccurrenceId::from_fingerprint(
                    "corpus-occurrence",
                    &format!("{}:chunk:{}", chunk.sentence_id.as_str(), chunk.chunk_index),
                ),
                language: language.clone(),
                kind: CorpusOccurrenceKind::Chunk,
                normalized_key: Some(normalize_phrase(&text)),
                display_text: text.clone(),
                media_id: Some(track.media_id.clone()),
                track_id: Some(track.id.clone()),
                sentence_id: Some(chunk.sentence_id.clone()),
                start_ms: chunk.start_ms.unwrap_or_else(|| sentence.start.get()),
                end_ms: chunk.end_ms.unwrap_or_else(|| sentence.end.get()),
                source_snapshot: text,
            });
        }
        self.append_family_occurrences(track, &language, rhythm_frames, &mut occurrences);
        Ok(occurrences)
    }

    pub(crate) fn reindex_subtitle_track(
        &self,
        track: &SubtitleTrack,
    ) -> Result<(), ApplicationError> {
        let occurrences = self.build_subtitle_corpus_occurrences(track)?;
        self.corpus
            .replace_corpus_occurrences_for_track(&track.id, &occurrences)
    }

    /// Connected-speech family annotation projection (Phase 3.9). One
    /// `connected_speech` occurrence per replayable rhythm-frame span, keyed
    /// by the family (`rhythm.weak_group`, `cs.deletion`, ...), so specialty
    /// aggregation can pull same-family clips from the whole library.
    ///
    /// Rebuildable read-side data on the v28 terms: rows are replaced with
    /// the rest of the track's projection on every reindex, and a track with
    /// no word timeline (hence no rhythm frames) simply contributes none.
    fn append_family_occurrences(
        &self,
        track: &SubtitleTrack,
        language: &LanguageCode,
        rhythm_frames: &[LLTimelineRhythmFrame],
        occurrences: &mut Vec<CorpusOccurrence>,
    ) {
        let text_by_sentence = track
            .sentences
            .iter()
            .map(|sentence| (sentence.id.clone(), sentence.display_text.clone()))
            .collect::<HashMap<_, _>>();
        for frame in rhythm_frames {
            let Some(snapshot) = text_by_sentence.get(&frame.sentence_id) else {
                continue;
            };
            for (index, span) in diagnosis_core::rhythm_family_spans(&frame.rhythm_frame)
                .into_iter()
                .enumerate()
            {
                occurrences.push(CorpusOccurrence {
                    id: CorpusOccurrenceId::from_fingerprint(
                        "corpus-occurrence",
                        &format!(
                            "{}:family:{}:{}",
                            frame.sentence_id.as_str(),
                            span.family,
                            index
                        ),
                    ),
                    language: language.clone(),
                    kind: CorpusOccurrenceKind::ConnectedSpeech,
                    normalized_key: Some(span.family.clone()),
                    display_text: if span.surface_text.is_empty() {
                        span.label.clone()
                    } else {
                        span.surface_text.clone()
                    },
                    media_id: Some(track.media_id.clone()),
                    track_id: Some(track.id.clone()),
                    sentence_id: Some(frame.sentence_id.clone()),
                    start_ms: span.start_ms,
                    end_ms: span.end_ms,
                    source_snapshot: snapshot.clone(),
                });
            }
        }
    }

    /// Reindex after a lifecycle change that only knows the track id (prosody
    /// analysis activation/retirement). A missing track is not an error: the
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

    /// Aggregate same-family clips for one L1 difficulty category (Phase
    /// 3.9). Primary path reads the corpus family projection across the
    /// whole library; when the projection has no rows (unindexed library)
    /// and a track is provided, it degrades to aggregating the current
    /// track's rhythm frames in memory (`indexed: false`).
    pub fn l1_specialty_occurrences(
        &self,
        difficulty_kind: &str,
        language: &str,
        track_id: Option<&str>,
        limit: u32,
    ) -> Result<L1SpecialtyOccurrences, ApplicationError> {
        let l2 = LanguageCode::parse(language)?;
        let difficulty_kind = clean_required(difficulty_kind.to_owned(), "difficulty_kind")?;
        let Some(l1) = self.learner_profile().learner_l1()? else {
            return Err(ApplicationError::Validation("learner L1 setting"));
        };
        let Some(rules) = diagnosis_core::l1l2_difficulty_rules(&l1, &l2) else {
            return Err(ApplicationError::NotFound("l1/l2 difficulty profile"));
        };
        let Some(rule) = rules.iter().find(|rule| rule.kind == difficulty_kind) else {
            return Err(ApplicationError::NotFound("difficulty kind"));
        };
        let families = rule
            .families
            .iter()
            .map(|family| (*family).to_owned())
            .collect::<Vec<_>>();
        let limit = limit.clamp(1, 100);
        let occurrences = self
            .corpus
            .search_corpus_family_occurrences(&l2, &families, None, limit, 0)?;
        if !occurrences.is_empty() {
            return Ok(L1SpecialtyOccurrences {
                difficulty_kind,
                families,
                indexed: true,
                occurrences,
            });
        }
        let Some(track_id) = track_id else {
            return Ok(L1SpecialtyOccurrences {
                difficulty_kind,
                families,
                indexed: false,
                occurrences: Vec::new(),
            });
        };
        let track_id = SubtitleTrackId::parse(track_id)?;
        let occurrences = self
            .current_track_family_occurrences(&track_id, &l2, &families, limit)
            .unwrap_or_default();
        Ok(L1SpecialtyOccurrences {
            difficulty_kind,
            families,
            indexed: false,
            occurrences,
        })
    }

    /// Degraded aggregation over one track's rhythm frames, mirroring the
    /// projection rows the reindex would have written for it.
    fn current_track_family_occurrences(
        &self,
        track_id: &SubtitleTrackId,
        language: &LanguageCode,
        families: &[String],
        limit: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let mut occurrences = Vec::new();
        let rhythm_frames = self
            .export_lltimeline_document(&track.id)
            .map(|document| document.rhythm_frames)
            .unwrap_or_default();
        self.append_family_occurrences(&track, language, &rhythm_frames, &mut occurrences);
        occurrences.retain(|occurrence| {
            occurrence
                .normalized_key
                .as_deref()
                .is_some_and(|key| families.iter().any(|family| family == key))
        });
        occurrences.truncate(limit as usize);
        Ok(occurrences)
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
            self.lexical_learning()
                .normalize_lexical_form(language.as_str(), &query)
                .map(|normalization| normalization.normalized)
                .unwrap_or(query)
        };
        self.corpus
            .search_corpus_occurrences(&language, &query, limit.clamp(1, 100), offset)
    }
}

/// Derives the playback-oriented prosodic chunk projections for the *active*
/// prosody analysis inside an imported LLTimeline document, without touching
/// committed resources. Used by the interchange import path so the corpus
/// chunk rows can join the import transaction. The candidate-only package
/// import passes no active analysis and therefore contributes no chunk rows.
pub(crate) fn prosody_chunk_projections_from_document(
    document: &domain::LLTimelineDocument,
) -> Vec<ProsodicChunkProjection> {
    let Some(active_id) = document.active_prosody_analysis_id.as_ref() else {
        return Vec::new();
    };
    let Some(analysis) = document
        .prosody_analyses
        .iter()
        .find(|analysis| &analysis.id == active_id)
    else {
        return Vec::new();
    };
    let timings = match analysis.parent_word_timeline_id.as_ref() {
        Some(parent_id) => document
            .word_timelines
            .iter()
            .find(|timeline| &timeline.id == parent_id)
            .map(|timeline| timeline.words.to_vec())
            .unwrap_or_default(),
        None => Vec::new(),
    };
    domain::prosody_chunk_projections(analysis, &timings)
}

/// Chunk display text for one prosodic chunk projection, mirroring the chunk
/// partitioner's text rule: word-kind tokens in the declared span joined by a
/// space, or with no separator when every token is CJK.
fn chunk_text_from_projection(
    sentence: &domain::SubtitleSentence,
    chunk: &ProsodicChunkProjection,
) -> String {
    let words = sentence
        .tokens
        .iter()
        .filter(|token| {
            token.kind == SubtitleTokenKind::Word
                && token.index >= chunk.start_token_index
                && token.index <= chunk.end_token_index
        })
        .collect::<Vec<_>>();
    if words.is_empty() {
        return String::new();
    }
    let all_cjk = words
        .iter()
        .all(|token| token.text.chars().all(is_cjk_char));
    let separator = if all_cjk { "" } else { " " };
    words
        .iter()
        .map(|token| token.text.as_str())
        .collect::<Vec<_>>()
        .join(separator)
}

fn is_cjk_char(ch: char) -> bool {
    matches!(ch,
        '\u{4E00}'..='\u{9FFF}'
        | '\u{3400}'..='\u{4DBF}'
        | '\u{20000}'..='\u{2A6DF}'
        | '\u{F900}'..='\u{FAFF}'
        | '\u{3040}'..='\u{309F}'
        | '\u{30A0}'..='\u{30FF}'
        | '\u{31F0}'..='\u{31FF}'
        | '\u{FF66}'..='\u{FF9D}'
    )
}
