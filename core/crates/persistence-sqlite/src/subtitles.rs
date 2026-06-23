use application::{ApplicationError, SubtitleRepository};
use domain::*;
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, domain_sql, from_json, json, repo};

impl SubtitleRepository for SqliteRepository {
    fn save_track(&self, track: &SubtitleTrack) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        tx.execute(
            "INSERT INTO subtitle_tracks(id, media_id, fingerprint, language, source, status)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(media_id, fingerprint) DO UPDATE SET
               language=excluded.language, source=excluded.source, status=excluded.status",
            params![
                track.id.as_str(),
                track.media_id.as_str(),
                track.fingerprint,
                track.language.as_ref().map(LanguageCode::as_str),
                track.source,
                json(&track.status)?
            ],
        )
        .map_err(repo)?;
        tx.execute(
            "DELETE FROM subtitle_sentences WHERE track_id=?1",
            [track.id.as_str()],
        )
        .map_err(repo)?;
        for sentence in &track.sentences {
            tx.execute(
                "INSERT INTO subtitle_sentences
                 (id, track_id, cue_index, start_ms, end_ms, original_text, display_text, tokens_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                params![
                    sentence.id.as_str(),
                    track.id.as_str(),
                    sentence.index,
                    sentence.start.get(),
                    sentence.end.get(),
                    sentence.original_text,
                    sentence.display_text,
                    json(&sentence.tokens)?
                ],
            )
            .map_err(repo)?;
            tx.execute(
                "UPDATE word_occurrences SET sentence_id=?1
                 WHERE sentence_id IS NULL
                   AND media_id=?2
                   AND start_ms_snapshot=?3
                   AND end_ms_snapshot=?4
                   AND sentence_text_snapshot=?5",
                params![
                    sentence.id.as_str(),
                    track.media_id.as_str(),
                    sentence.start.get(),
                    sentence.end.get(),
                    sentence.display_text
                ],
            )
            .map_err(repo)?;
            tx.execute(
                "UPDATE word_observations SET sentence_id=?1
                 WHERE sentence_id IS NULL AND sentence_id_snapshot=?1",
                [sentence.id.as_str()],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    fn get_track(&self, id: &SubtitleTrackId) -> Result<Option<SubtitleTrack>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut track = conn
            .query_row(
                "SELECT id, media_id, fingerprint, language, source, status FROM subtitle_tracks WHERE id=?1",
                [id.as_str()],
                |r| {
                    Ok(SubtitleTrack {
                        id: SubtitleTrackId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                        media_id: MediaId::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
                        fingerprint: r.get(2)?,
                        language: r
                            .get::<_, Option<String>>(3)?
                            .map(LanguageCode::parse)
                            .transpose()
                            .map_err(domain_sql)?,
                        source: r.get(4)?,
                        status: from_json(&r.get::<_, String>(5)?)?,
                        sentences: vec![],
                    })
                },
            )
            .optional()
            .map_err(repo)?;
        let Some(track_value) = track.as_mut() else {
            return Ok(None);
        };
        let mut query = conn
            .prepare(
                "SELECT id, cue_index, start_ms, end_ms, original_text, display_text, tokens_json
                 FROM subtitle_sentences WHERE track_id=?1 ORDER BY cue_index",
            )
            .map_err(repo)?;
        track_value.sentences = query
            .query_map([id.as_str()], |r| {
                Ok(SubtitleSentence {
                    id: SubtitleSentenceId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                    index: r.get(1)?,
                    start: TimeMs::new(r.get(2)?),
                    end: TimeMs::new(r.get(3)?),
                    original_text: r.get(4)?,
                    display_text: r.get(5)?,
                    tokens: from_json(&r.get::<_, String>(6)?)?,
                })
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(track)
    }

    fn list_tracks_for_media(
        &self,
        media_id: &MediaId,
    ) -> Result<Vec<SubtitleTrack>, ApplicationError> {
        let ids = {
            let conn = self.connection.lock().expect("sqlite mutex poisoned");
            let mut query = conn
                .prepare("SELECT id FROM subtitle_tracks WHERE media_id=?1 ORDER BY rowid DESC")
                .map_err(repo)?;
            query
                .query_map([media_id.as_str()], |row| row.get::<_, String>(0))
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        ids.into_iter()
            .map(SubtitleTrackId::parse)
            .map(|id| id.map_err(ApplicationError::from))
            .map(|id| id.and_then(|id| self.get_track(&id)))
            .collect::<Result<Vec<_>, _>>()
            .map(|tracks| tracks.into_iter().flatten().collect())
    }

    fn set_track_status(
        &self,
        id: &SubtitleTrackId,
        status: SubtitleTrackStatus,
    ) -> Result<SubtitleTrack, ApplicationError> {
        let updated = self
            .connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE subtitle_tracks SET status=?2 WHERE id=?1",
                params![id.as_str(), json(&status)?],
            )
            .map_err(repo)?;
        if updated == 0 {
            return Err(ApplicationError::NotFound("subtitle track"));
        }
        self.get_track(id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))
    }

    fn set_track_language(
        &self,
        id: &SubtitleTrackId,
        language: &LanguageCode,
    ) -> Result<SubtitleTrack, ApplicationError> {
        let updated = self
            .connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE subtitle_tracks SET language=?2 WHERE id=?1",
                params![id.as_str(), language.as_str()],
            )
            .map_err(repo)?;
        if updated == 0 {
            return Err(ApplicationError::NotFound("subtitle track"));
        }
        self.get_track(id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))
    }

    fn delete_track(
        &self,
        id: &SubtitleTrackId,
    ) -> Result<Option<SubtitleTrack>, ApplicationError> {
        let existing = self.get_track(id)?;
        if existing.is_none() {
            return Ok(None);
        }
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute("DELETE FROM subtitle_tracks WHERE id=?1", [id.as_str()])
            .map_err(repo)?;
        Ok(existing)
    }

    fn get_by_media_fingerprint(
        &self,
        media_id: &MediaId,
        fingerprint: &str,
    ) -> Result<Option<SubtitleTrack>, ApplicationError> {
        let id = {
            let conn = self.connection.lock().expect("sqlite mutex poisoned");
            conn.query_row(
                "SELECT id FROM subtitle_tracks WHERE media_id=?1 AND fingerprint=?2",
                params![media_id.as_str(), fingerprint],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
        };
        id.map(SubtitleTrackId::parse)
            .transpose()?
            .map(|id| self.get_track(&id))
            .transpose()
            .map(Option::flatten)
    }

    fn save_lltimeline_resource(
        &self,
        track_id: &SubtitleTrackId,
        metadata: &LLTimelineMetadata,
        artifacts: &[LLTimelineArtifact],
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO lltimeline_resources
                 (track_id,metadata_json,artifacts_json,updated_at_ms)
                 VALUES (?1,?2,?3,unixepoch('subsec') * 1000)
                 ON CONFLICT(track_id) DO UPDATE SET
                   metadata_json=excluded.metadata_json,
                   artifacts_json=excluded.artifacts_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![track_id.as_str(), json(metadata)?, json(artifacts)?],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn get_lltimeline_resource(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<(LLTimelineMetadata, Vec<LLTimelineArtifact>)>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT metadata_json, artifacts_json FROM lltimeline_resources
                 WHERE track_id=?1",
                [track_id.as_str()],
                |row| {
                    Ok((
                        from_json(&row.get::<_, String>(0)?)?,
                        from_json(&row.get::<_, String>(1)?)?,
                    ))
                },
            )
            .optional()
            .map_err(repo)
    }

    fn get_sentence(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SubtitleSentence>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT id, cue_index, start_ms, end_ms, original_text, display_text, tokens_json
                 FROM subtitle_sentences WHERE id=?1",
                [id.as_str()],
                |row| {
                    Ok(SubtitleSentence {
                        id: SubtitleSentenceId::parse(row.get::<_, String>(0)?)
                            .map_err(domain_sql)?,
                        index: row.get(1)?,
                        start: TimeMs::new(row.get(2)?),
                        end: TimeMs::new(row.get(3)?),
                        original_text: row.get(4)?,
                        display_text: row.get(5)?,
                        tokens: from_json(&row.get::<_, String>(6)?)?,
                    })
                },
            )
            .optional()
            .map_err(repo)
    }

    fn sentence_track_language(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<LanguageCode>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT t.language FROM subtitle_sentences s
                 JOIN subtitle_tracks t ON t.id = s.track_id
                 WHERE s.id = ?1",
                [id.as_str()],
                |row| row.get::<_, Option<String>>(0),
            )
            .optional()
            .map_err(repo)?
            .flatten()
            .map(LanguageCode::parse)
            .transpose()
            .map_err(ApplicationError::from)
    }

    fn save_pronunciation(&self, analysis: &SentencePronunciation) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO pronunciation_analysis
                 (sentence_id,provider_id,provider_version,analysis_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,unixepoch('subsec') * 1000)
                 ON CONFLICT(sentence_id) DO UPDATE SET
                   provider_id=excluded.provider_id,provider_version=excluded.provider_version,
                   analysis_json=excluded.analysis_json,updated_at_ms=excluded.updated_at_ms",
                params![
                    analysis.sentence_id.as_str(),
                    analysis.provider_id,
                    analysis.provider_version,
                    json(analysis)?
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn save_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        pronunciation: &WordPronunciation,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO pronunciation_cache
                 (language,accent,normalized_text,provider_id,provider_version,
                  pronunciation_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,unixepoch('subsec') * 1000)
                 ON CONFLICT(language,accent,normalized_text,provider_id,provider_version)
                 DO UPDATE SET pronunciation_json=excluded.pronunciation_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    language,
                    accent,
                    pronunciation.normalized,
                    provider_id,
                    provider_version,
                    json(pronunciation)?,
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn get_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        normalized_text: &str,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<Option<WordPronunciation>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT pronunciation_json FROM pronunciation_cache
                 WHERE language=?1 AND accent=?2 AND normalized_text=?3
                   AND provider_id=?4 AND provider_version=?5",
                params![
                    language,
                    accent,
                    normalized_text,
                    provider_id,
                    provider_version
                ],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn get_pronunciation(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SentencePronunciation>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT analysis_json FROM pronunciation_analysis WHERE sentence_id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn save_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
        timings: &[WordTiming],
    ) -> Result<(), ApplicationError> {
        let Some(first) = timings.first() else {
            return Ok(());
        };
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO word_timings
                 (sentence_id,timing_source,provider_id,provider_version,timings_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,unixepoch('subsec') * 1000)
                 ON CONFLICT(sentence_id) DO UPDATE SET
                   timing_source=excluded.timing_source,provider_id=excluded.provider_id,
                   provider_version=excluded.provider_version,timings_json=excluded.timings_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    sentence_id.as_str(),
                    json(&first.timing_source)?,
                    first.provider_id,
                    first.provider_version,
                    json(&timings)?
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn get_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT timings_json FROM word_timings WHERE sentence_id=?1",
                [sentence_id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map(|value| value.unwrap_or_default())
            .map_err(repo)
    }

    fn save_word_timeline(
        &self,
        timeline: &WordTimeline,
    ) -> Result<WordTimeline, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO word_timeline_runs
                 (id,track_id,media_id,status,timeline_json,created_at_ms,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7)
                 ON CONFLICT(id) DO UPDATE SET
                   status=excluded.status,timeline_json=excluded.timeline_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    timeline.id.as_str(),
                    timeline.track_id.as_str(),
                    timeline.media_id.as_str(),
                    json(&timeline.status)?,
                    json(timeline)?,
                    timeline.created_at_ms,
                    timeline.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(timeline.clone())
    }

    fn list_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimeline>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare(
                "SELECT timeline_json FROM word_timeline_runs
                 WHERE track_id=?1 ORDER BY created_at_ms DESC",
            )
            .map_err(repo)?;
        query
            .query_map([track_id.as_str()], |row| {
                from_json::<WordTimeline>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<Option<WordTimeline>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT timeline_json FROM word_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn active_word_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<WordTimeline>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT timeline_json FROM word_timeline_runs
                 WHERE track_id=?1 AND status=?2
                 ORDER BY updated_at_ms DESC LIMIT 1",
                params![track_id.as_str(), json(&TimelineStatus::Active)?],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn activate_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let selected_json = tx
            .query_row(
                "SELECT timeline_json FROM word_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("word timeline"))?;
        let mut selected: WordTimeline = from_json(&selected_json).map_err(repo)?;
        if selected.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation("archived word timeline"));
        }
        let now = application::now_ms();
        let mut active_query = tx
            .prepare(
                "SELECT timeline_json FROM word_timeline_runs
                 WHERE track_id=?1 AND status=?2 AND id<>?3",
            )
            .map_err(repo)?;
        let active_timelines = active_query
            .query_map(
                params![
                    selected.track_id.as_str(),
                    json(&TimelineStatus::Active)?,
                    selected.id.as_str()
                ],
                |row| from_json::<WordTimeline>(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        drop(active_query);
        for mut timeline in active_timelines {
            timeline.status = TimelineStatus::Candidate;
            timeline.updated_at_ms = now;
            tx.execute(
                "UPDATE word_timeline_runs
                 SET status=?2,timeline_json=?3,updated_at_ms=?4 WHERE id=?1",
                params![
                    timeline.id.as_str(),
                    json(&timeline.status)?,
                    json(&timeline)?,
                    timeline.updated_at_ms
                ],
            )
            .map_err(repo)?;
        }

        selected.status = TimelineStatus::Active;
        selected.updated_at_ms = now;
        tx.execute(
            "UPDATE word_timeline_runs
             SET status=?2,timeline_json=?3,updated_at_ms=?4 WHERE id=?1",
            params![
                selected.id.as_str(),
                json(&selected.status)?,
                json(&selected)?,
                selected.updated_at_ms
            ],
        )
        .map_err(repo)?;
        tx.execute(
            "DELETE FROM word_timings
             WHERE sentence_id IN (
               SELECT id FROM subtitle_sentences WHERE track_id=?1
             )",
            [selected.track_id.as_str()],
        )
        .map_err(repo)?;
        let mut grouped = std::collections::HashMap::<SubtitleSentenceId, Vec<WordTiming>>::new();
        for word in &selected.words {
            grouped
                .entry(word.sentence_id.clone())
                .or_default()
                .push(word.clone());
        }
        for (sentence_id, mut timings) in grouped {
            timings.sort_by_key(|value| (value.start_ms, value.end_ms, value.token_index));
            if let Some(first) = timings.first() {
                tx.execute(
                    "INSERT INTO word_timings
                     (sentence_id,timing_source,provider_id,provider_version,timings_json,updated_at_ms)
                     VALUES (?1,?2,?3,?4,?5,?6)
                     ON CONFLICT(sentence_id) DO UPDATE SET
                       timing_source=excluded.timing_source,provider_id=excluded.provider_id,
                       provider_version=excluded.provider_version,timings_json=excluded.timings_json,
                       updated_at_ms=excluded.updated_at_ms",
                    params![
                        sentence_id.as_str(),
                        json(&first.timing_source)?,
                        first.provider_id,
                        first.provider_version,
                        json(&timings)?,
                        now
                    ],
                )
                .map_err(repo)?;
            }
        }
        tx.commit().map_err(repo)?;
        Ok(selected)
    }

    fn archive_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError> {
        let mut timeline = self
            .get_word_timeline(id)?
            .ok_or(ApplicationError::NotFound("word timeline"))?;
        let was_active = timeline.status == TimelineStatus::Active;
        timeline.status = TimelineStatus::Archived;
        timeline.updated_at_ms = application::now_ms();
        let timeline = self.save_word_timeline(&timeline)?;
        if was_active {
            self.connection
                .lock()
                .expect("sqlite mutex poisoned")
                .execute(
                    "DELETE FROM word_timings
                     WHERE sentence_id IN (
                       SELECT id FROM subtitle_sentences WHERE track_id=?1
                     )",
                    [timeline.track_id.as_str()],
                )
                .map_err(repo)?;
        }
        Ok(timeline)
    }

    fn delete_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let timeline_json = tx
            .query_row(
                "SELECT timeline_json FROM word_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("word timeline"))?;
        let timeline: WordTimeline = from_json(&timeline_json).map_err(repo)?;
        tx.execute("DELETE FROM word_timeline_runs WHERE id=?1", [id.as_str()])
            .map_err(repo)?;
        if timeline.status == TimelineStatus::Active {
            tx.execute(
                "DELETE FROM word_timings
                 WHERE sentence_id IN (
                   SELECT id FROM subtitle_sentences WHERE track_id=?1
                 )",
                [timeline.track_id.as_str()],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        Ok(timeline)
    }

    fn save_chunk_timeline(
        &self,
        timeline: &ChunkTimeline,
    ) -> Result<ChunkTimeline, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO chunk_timeline_runs
                 (id,track_id,media_id,parent_word_timeline_id,status,timeline_json,created_at_ms,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)
                 ON CONFLICT(id) DO UPDATE SET
                   parent_word_timeline_id=excluded.parent_word_timeline_id,
                   status=excluded.status,timeline_json=excluded.timeline_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    timeline.id.as_str(),
                    timeline.track_id.as_str(),
                    timeline.media_id.as_str(),
                    timeline.parent_word_timeline_id.as_ref().map(WordTimelineId::as_str),
                    json(&timeline.status)?,
                    json(timeline)?,
                    timeline.created_at_ms,
                    timeline.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(timeline.clone())
    }

    fn list_chunk_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ChunkTimeline>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare(
                "SELECT timeline_json FROM chunk_timeline_runs
                 WHERE track_id=?1 ORDER BY created_at_ms DESC",
            )
            .map_err(repo)?;
        query
            .query_map([track_id.as_str()], |row| {
                from_json::<ChunkTimeline>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<Option<ChunkTimeline>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT timeline_json FROM chunk_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn active_chunk_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<ChunkTimeline>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT timeline_json FROM chunk_timeline_runs
                 WHERE track_id=?1 AND status=?2
                 ORDER BY updated_at_ms DESC LIMIT 1",
                params![track_id.as_str(), json(&TimelineStatus::Active)?],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn activate_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let selected_json = tx
            .query_row(
                "SELECT timeline_json FROM chunk_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("chunk timeline"))?;
        let mut selected: ChunkTimeline = from_json(&selected_json).map_err(repo)?;
        if selected.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation("archived chunk timeline"));
        }
        let now = application::now_ms();
        let mut active_query = tx
            .prepare(
                "SELECT timeline_json FROM chunk_timeline_runs
                 WHERE track_id=?1 AND status=?2 AND id<>?3",
            )
            .map_err(repo)?;
        let active_timelines = active_query
            .query_map(
                params![
                    selected.track_id.as_str(),
                    json(&TimelineStatus::Active)?,
                    selected.id.as_str()
                ],
                |row| from_json::<ChunkTimeline>(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        drop(active_query);
        for mut timeline in active_timelines {
            timeline.status = TimelineStatus::Candidate;
            timeline.updated_at_ms = now;
            tx.execute(
                "UPDATE chunk_timeline_runs
                 SET status=?2,timeline_json=?3,updated_at_ms=?4 WHERE id=?1",
                params![
                    timeline.id.as_str(),
                    json(&timeline.status)?,
                    json(&timeline)?,
                    timeline.updated_at_ms
                ],
            )
            .map_err(repo)?;
        }

        selected.status = TimelineStatus::Active;
        selected.updated_at_ms = now;
        tx.execute(
            "UPDATE chunk_timeline_runs
             SET status=?2,timeline_json=?3,updated_at_ms=?4 WHERE id=?1",
            params![
                selected.id.as_str(),
                json(&selected.status)?,
                json(&selected)?,
                selected.updated_at_ms
            ],
        )
        .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(selected)
    }

    fn archive_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let mut timeline = self
            .get_chunk_timeline(id)?
            .ok_or(ApplicationError::NotFound("chunk timeline"))?;
        timeline.status = TimelineStatus::Archived;
        timeline.updated_at_ms = application::now_ms();
        self.save_chunk_timeline(&timeline)
    }

    fn delete_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let timeline_json = tx
            .query_row(
                "SELECT timeline_json FROM chunk_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("chunk timeline"))?;
        let timeline: ChunkTimeline = from_json(&timeline_json).map_err(repo)?;
        tx.execute("DELETE FROM chunk_timeline_runs WHERE id=?1", [id.as_str()])
            .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(timeline)
    }

    fn save_phone_timeline(
        &self,
        timeline: &PhoneTimeline,
    ) -> Result<PhoneTimeline, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO phone_timeline_runs
                 (id,track_id,media_id,sentence_id,parent_word_timeline_id,
                  parent_phonetic_analysis_id,status,timeline_json,created_at_ms,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)
                 ON CONFLICT(id) DO UPDATE SET
                   sentence_id=excluded.sentence_id,
                   parent_word_timeline_id=excluded.parent_word_timeline_id,
                   parent_phonetic_analysis_id=excluded.parent_phonetic_analysis_id,
                   status=excluded.status,timeline_json=excluded.timeline_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    timeline.id.as_str(),
                    timeline.track_id.as_str(),
                    timeline.media_id.as_str(),
                    timeline
                        .sentence_id
                        .as_ref()
                        .map(SubtitleSentenceId::as_str),
                    timeline
                        .parent_word_timeline_id
                        .as_ref()
                        .map(WordTimelineId::as_str),
                    timeline
                        .parent_phonetic_analysis_id
                        .as_ref()
                        .map(PhoneticAnalysisId::as_str),
                    json(&timeline.status)?,
                    json(timeline)?,
                    timeline.created_at_ms,
                    timeline.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(timeline.clone())
    }

    fn list_phone_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneTimeline>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare(
                "SELECT timeline_json FROM phone_timeline_runs
                 WHERE track_id=?1 ORDER BY created_at_ms DESC",
            )
            .map_err(repo)?;
        query
            .query_map([track_id.as_str()], |row| {
                from_json::<PhoneTimeline>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<Option<PhoneTimeline>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT timeline_json FROM phone_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn active_phone_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<PhoneTimeline>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT timeline_json FROM phone_timeline_runs
                 WHERE track_id=?1 AND status=?2
                 ORDER BY updated_at_ms DESC LIMIT 1",
                params![track_id.as_str(), json(&TimelineStatus::Active)?],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn activate_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let selected_json = tx
            .query_row(
                "SELECT timeline_json FROM phone_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("phone timeline"))?;
        let mut selected: PhoneTimeline = from_json(&selected_json).map_err(repo)?;
        if selected.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation("archived phone timeline"));
        }
        let now = application::now_ms();
        let mut active_query = tx
            .prepare(
                "SELECT timeline_json FROM phone_timeline_runs
                 WHERE track_id=?1 AND status=?2 AND id<>?3",
            )
            .map_err(repo)?;
        let active_timelines = active_query
            .query_map(
                params![
                    selected.track_id.as_str(),
                    json(&TimelineStatus::Active)?,
                    selected.id.as_str()
                ],
                |row| from_json::<PhoneTimeline>(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        drop(active_query);
        for mut timeline in active_timelines {
            timeline.status = TimelineStatus::Candidate;
            timeline.updated_at_ms = now;
            tx.execute(
                "UPDATE phone_timeline_runs
                 SET status=?2,timeline_json=?3,updated_at_ms=?4 WHERE id=?1",
                params![
                    timeline.id.as_str(),
                    json(&timeline.status)?,
                    json(&timeline)?,
                    timeline.updated_at_ms
                ],
            )
            .map_err(repo)?;
        }

        selected.status = TimelineStatus::Active;
        selected.updated_at_ms = now;
        tx.execute(
            "UPDATE phone_timeline_runs
             SET status=?2,timeline_json=?3,updated_at_ms=?4 WHERE id=?1",
            params![
                selected.id.as_str(),
                json(&selected.status)?,
                json(&selected)?,
                selected.updated_at_ms
            ],
        )
        .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(selected)
    }

    fn archive_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        let mut timeline = self
            .get_phone_timeline(id)?
            .ok_or(ApplicationError::NotFound("phone timeline"))?;
        timeline.status = TimelineStatus::Archived;
        timeline.updated_at_ms = application::now_ms();
        self.save_phone_timeline(&timeline)
    }

    fn delete_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let timeline_json = tx
            .query_row(
                "SELECT timeline_json FROM phone_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("phone timeline"))?;
        let timeline: PhoneTimeline = from_json(&timeline_json).map_err(repo)?;
        tx.execute("DELETE FROM phone_timeline_runs WHERE id=?1", [id.as_str()])
            .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(timeline)
    }
}
