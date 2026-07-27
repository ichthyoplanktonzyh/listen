use application::{ApplicationError, SenseGroupRepository, batch_governor::CachedPartition};
use domain::{
    SenseGroupAnalysis, SenseGroupAnalysisId, SubtitleTrackId, TimelineStatus, WordTimelineId,
};
use rusqlite::{OptionalExtension, params};

use crate::{SqliteRepository, from_json, json, repo};

impl SenseGroupRepository for SqliteRepository {
    fn get_llm_sentence_checkpoint(
        &self,
        fingerprint: &str,
    ) -> Result<Option<CachedPartition>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT partition_json
                 FROM llm_sense_group_sentence_checkpoints
                 WHERE fingerprint=?1",
                [fingerprint],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn save_llm_sentence_checkpoint(
        &self,
        fingerprint: &str,
        partition: &CachedPartition,
        updated_at_ms: u64,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO llm_sense_group_sentence_checkpoints
                 (fingerprint,partition_json,updated_at_ms)
                 VALUES (?1,?2,?3)
                 ON CONFLICT(fingerprint) DO UPDATE SET
                   partition_json=excluded.partition_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![fingerprint, json(partition)?, updated_at_ms],
            )
            .map_err(repo)?;
        Ok(())
    }

    fn save_sense_group_analysis(
        &self,
        analysis: &SenseGroupAnalysis,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO sense_group_analysis_runs
                 (id,track_id,media_id,parent_word_timeline_id,status,analysis_json,created_at_ms,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)
                 ON CONFLICT(id) DO UPDATE SET
                   parent_word_timeline_id=excluded.parent_word_timeline_id,
                   status=excluded.status,analysis_json=excluded.analysis_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    analysis.id.as_str(),
                    analysis.track_id.as_str(),
                    analysis.media_id.as_str(),
                    analysis.parent_word_timeline_id.as_ref().map(WordTimelineId::as_str),
                    json(&analysis.status)?,
                    json(analysis)?,
                    analysis.created_at_ms,
                    analysis.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(analysis.clone())
    }

    fn list_sense_group_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SenseGroupAnalysis>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare(
                "SELECT analysis_json FROM sense_group_analysis_runs
                 WHERE track_id=?1 ORDER BY created_at_ms DESC",
            )
            .map_err(repo)?;
        query
            .query_map([track_id.as_str()], |row| {
                from_json::<SenseGroupAnalysis>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<Option<SenseGroupAnalysis>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT analysis_json FROM sense_group_analysis_runs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn active_sense_group_analysis(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<SenseGroupAnalysis>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT analysis_json FROM sense_group_analysis_runs
                 WHERE track_id=?1 AND status=?2
                 ORDER BY updated_at_ms DESC LIMIT 1",
                params![track_id.as_str(), json(&TimelineStatus::Active)?],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn activate_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let selected_json = tx
            .query_row(
                "SELECT analysis_json FROM sense_group_analysis_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("sense group analysis"))?;
        let mut selected: SenseGroupAnalysis = from_json(&selected_json).map_err(repo)?;
        if selected.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation(
                "archived sense group analysis",
            ));
        }
        let now = application::now_ms();
        let mut active_query = tx
            .prepare(
                "SELECT analysis_json FROM sense_group_analysis_runs
                 WHERE track_id=?1 AND status=?2 AND id<>?3",
            )
            .map_err(repo)?;
        let active_analyses = active_query
            .query_map(
                params![
                    selected.track_id.as_str(),
                    json(&TimelineStatus::Active)?,
                    selected.id.as_str()
                ],
                |row| from_json::<SenseGroupAnalysis>(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        drop(active_query);
        for mut analysis in active_analyses {
            analysis.status = TimelineStatus::Candidate;
            analysis.updated_at_ms = now;
            tx.execute(
                "UPDATE sense_group_analysis_runs
                 SET status=?2,analysis_json=?3,updated_at_ms=?4 WHERE id=?1",
                params![
                    analysis.id.as_str(),
                    json(&analysis.status)?,
                    json(&analysis)?,
                    analysis.updated_at_ms
                ],
            )
            .map_err(repo)?;
        }

        selected.status = TimelineStatus::Active;
        selected.updated_at_ms = now;
        tx.execute(
            "UPDATE sense_group_analysis_runs
             SET status=?2,analysis_json=?3,updated_at_ms=?4 WHERE id=?1",
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

    fn archive_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        let mut analysis = self
            .get_sense_group_analysis(id)?
            .ok_or(ApplicationError::NotFound("sense group analysis"))?;
        analysis.status = TimelineStatus::Archived;
        analysis.updated_at_ms = application::now_ms();
        self.save_sense_group_analysis(&analysis)
    }

    fn delete_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let analysis_json = tx
            .query_row(
                "SELECT analysis_json FROM sense_group_analysis_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("sense group analysis"))?;
        let analysis: SenseGroupAnalysis = from_json(&analysis_json).map_err(repo)?;
        tx.execute(
            "DELETE FROM sense_group_analysis_runs WHERE id=?1",
            [id.as_str()],
        )
        .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(analysis)
    }
}
