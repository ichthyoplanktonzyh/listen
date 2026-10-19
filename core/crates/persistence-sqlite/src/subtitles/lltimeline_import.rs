use application::{ApplicationError, LLTimelineImport, LLTimelineImportRepository};
use domain::{PhoneTimeline, ProsodyAnalysis, SenseGroupAnalysis, TimelineStatus, WordTimeline};
use rusqlite::{OptionalExtension, Transaction, params};
use serde::Serialize;
use serde::de::DeserializeOwned;

use crate::{
    SqliteRepository, corpus::insert_occurrence, from_json, json,
    media::upsert_media_in_transaction, repo,
};

use super::{
    lltimeline_resources::save_lltimeline_resource_in_connection,
    phone_timelines::save_phone_timeline_in_connection,
    prosody::save_prosody_analysis_in_connection,
    sense_groups::save_sense_group_analysis_in_connection,
    subtitle_tracks::save_track_in_transaction,
    word_timelines::{replace_legacy_word_timings_in_connection, save_word_timeline_in_connection},
};

trait StatusRecord {
    fn status_mut(&mut self) -> &mut TimelineStatus;
    fn id(&self) -> &str;
    fn updated_at_ms(&self) -> u64;
}

impl StatusRecord for WordTimeline {
    fn status_mut(&mut self) -> &mut TimelineStatus {
        &mut self.status
    }

    fn id(&self) -> &str {
        self.id.as_str()
    }

    fn updated_at_ms(&self) -> u64 {
        self.updated_at_ms
    }
}

impl StatusRecord for PhoneTimeline {
    fn status_mut(&mut self) -> &mut TimelineStatus {
        &mut self.status
    }

    fn id(&self) -> &str {
        self.id.as_str()
    }

    fn updated_at_ms(&self) -> u64 {
        self.updated_at_ms
    }
}

impl StatusRecord for SenseGroupAnalysis {
    fn status_mut(&mut self) -> &mut TimelineStatus {
        &mut self.status
    }

    fn id(&self) -> &str {
        self.id.as_str()
    }

    fn updated_at_ms(&self) -> u64 {
        self.updated_at_ms
    }
}

impl StatusRecord for ProsodyAnalysis {
    fn status_mut(&mut self) -> &mut TimelineStatus {
        &mut self.status
    }

    fn id(&self) -> &str {
        self.id.as_str()
    }

    fn updated_at_ms(&self) -> u64 {
        self.updated_at_ms
    }
}

fn demote_active<T>(
    tx: &Transaction<'_>,
    table: &str,
    json_column: &str,
    track_id: &str,
) -> Result<(), ApplicationError>
where
    T: DeserializeOwned + Serialize + StatusRecord,
{
    let sql = format!("SELECT {json_column} FROM {table} WHERE track_id=?1 AND status=?2");
    let mut statement = tx.prepare(&sql).map_err(repo)?;
    let mut records = statement
        .query_map(params![track_id, json(&TimelineStatus::Active)?], |row| {
            from_json::<T>(&row.get::<_, String>(0)?)
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)?;
    drop(statement);
    let update =
        format!("UPDATE {table} SET status=?2,{json_column}=?3,updated_at_ms=?4 WHERE id=?1");
    for record in &mut records {
        *record.status_mut() = TimelineStatus::Candidate;
        tx.execute(
            &update,
            params![
                record.id(),
                json(&TimelineStatus::Candidate)?,
                json(record)?,
                record.updated_at_ms()
            ],
        )
        .map_err(repo)?;
    }
    Ok(())
}

impl LLTimelineImportRepository for SqliteRepository {
    fn import_lltimeline(&self, import: &LLTimelineImport) -> Result<(), ApplicationError> {
        if import
            .corpus_occurrences
            .iter()
            .any(|occurrence| occurrence.track_id.as_ref() != Some(&import.track.id))
        {
            return Err(ApplicationError::Invalid(
                "corpus occurrence does not belong to LLTimeline track".into(),
            ));
        }

        let mut connection = self.connection.lock();
        let tx = connection.transaction().map_err(repo)?;
        if let Some(media) = &import.media_to_create {
            upsert_media_in_transaction(&tx, media)?;
        }
        save_track_in_transaction(&tx, &import.track)?;
        save_lltimeline_resource_in_connection(
            &tx,
            &import.track.id,
            &import.metadata,
            &import.artifacts,
        )?;

        demote_active::<WordTimeline>(
            &tx,
            "word_timeline_runs",
            "timeline_json",
            import.track.id.as_str(),
        )?;
        for timeline in &import.word_timelines {
            save_word_timeline_in_connection(&tx, timeline)?;
        }
        let active_word_timeline = import
            .word_timelines
            .iter()
            .find(|timeline| timeline.status == TimelineStatus::Active);
        replace_legacy_word_timings_in_connection(
            &tx,
            &import.track.id,
            active_word_timeline,
            application::now_ms(),
        )?;

        demote_active::<PhoneTimeline>(
            &tx,
            "phone_timeline_runs",
            "timeline_json",
            import.track.id.as_str(),
        )?;
        for timeline in &import.phone_timelines {
            save_phone_timeline_in_connection(&tx, timeline)?;
        }

        demote_active::<SenseGroupAnalysis>(
            &tx,
            "sense_group_analysis_runs",
            "analysis_json",
            import.track.id.as_str(),
        )?;
        for analysis in &import.sense_group_analyses {
            save_sense_group_analysis_in_connection(&tx, analysis)?;
        }

        demote_active::<ProsodyAnalysis>(
            &tx,
            "prosody_analysis_runs",
            "analysis_json",
            import.track.id.as_str(),
        )?;
        for analysis in &import.prosody_analyses {
            save_prosody_analysis_in_connection(&tx, analysis)?;
        }

        for occurrence in &import.corpus_occurrences {
            let existing_track = tx
                .query_row(
                    "SELECT track_id FROM corpus_occurrences WHERE id=?1",
                    [occurrence.id.as_str()],
                    |row| row.get::<_, String>(0),
                )
                .optional()
                .map_err(repo)?;
            if existing_track
                .as_deref()
                .is_some_and(|track_id| track_id != import.track.id.as_str())
            {
                return Err(ApplicationError::Invalid(
                    "corpus occurrence id already belongs to another track".into(),
                ));
            }
        }
        tx.execute(
            "DELETE FROM corpus_occurrences WHERE track_id=?1",
            [import.track.id.as_str()],
        )
        .map_err(repo)?;
        for occurrence in &import.corpus_occurrences {
            insert_occurrence(&tx, occurrence)?;
        }
        tx.commit().map_err(repo)
    }
}
