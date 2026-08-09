use application::{
    ApplicationError, ContentPackageCandidateImport, ContentPackageImportRepository,
};
use domain::{LLTimelineArtifact, TimelineStatus};
use rusqlite::{Connection, OptionalExtension, Transaction, params};

use crate::{SqliteRepository, corpus::insert_occurrence, from_json, json, repo};

use super::{
    guard_timeline_ownership, lltimeline_resources::save_lltimeline_resource_in_connection,
    phone_timelines::save_phone_timeline_in_connection,
    prosody::save_prosody_analysis_in_connection,
    sense_groups::save_sense_group_analysis_in_connection,
    subtitle_tracks::save_track_in_transaction, word_timelines::save_word_timeline_in_connection,
};

fn row_exists(connection: &Connection, table: &str, id: &str) -> Result<bool, ApplicationError> {
    connection
        .query_row(&format!("SELECT 1 FROM {table} WHERE id=?1"), [id], |_| {
            Ok(())
        })
        .optional()
        .map(|value| value.is_some())
        .map_err(repo)
}

fn guard_track_identity(
    tx: &Transaction<'_>,
    import: &ContentPackageCandidateImport,
) -> Result<bool, ApplicationError> {
    let track = &import.track;
    let by_id = tx
        .query_row(
            "SELECT media_id,fingerprint FROM subtitle_tracks WHERE id=?1",
            [track.id.as_str()],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        )
        .optional()
        .map_err(repo)?;
    if by_id.as_ref().is_some_and(|(media_id, fingerprint)| {
        media_id != track.media_id.as_str() || fingerprint != &track.fingerprint
    }) {
        return Err(ApplicationError::Invalid(
            "content package track id already belongs to another source".into(),
        ));
    }
    let by_source = tx
        .query_row(
            "SELECT id FROM subtitle_tracks WHERE media_id=?1 AND fingerprint=?2",
            params![track.media_id.as_str(), track.fingerprint],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(repo)?;
    if by_source
        .as_deref()
        .is_some_and(|id| id != track.id.as_str())
    {
        return Err(ApplicationError::Invalid(
            "content package source already has another track id".into(),
        ));
    }
    Ok(by_id.is_some())
}

fn guard_sentence_ownership(
    tx: &Transaction<'_>,
    import: &ContentPackageCandidateImport,
) -> Result<(), ApplicationError> {
    for sentence in &import.track.sentences {
        let existing_track = tx
            .query_row(
                "SELECT track_id FROM subtitle_sentences WHERE id=?1",
                [sentence.id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?;
        if existing_track
            .as_deref()
            .is_some_and(|track_id| track_id != import.track.id.as_str())
        {
            return Err(ApplicationError::Invalid(
                "content package sentence id already belongs to another track".into(),
            ));
        }
    }
    Ok(())
}

fn artifact_identity(artifact: &LLTimelineArtifact) -> Result<String, ApplicationError> {
    if let Some(resource_id) = artifact
        .payload
        .get("resource_id")
        .and_then(serde_json::Value::as_str)
    {
        return Ok(format!("resource:{resource_id}"));
    }
    Ok(format!("content:{}", json(artifact)?))
}

fn merge_artifacts(
    tx: &Transaction<'_>,
    import: &ContentPackageCandidateImport,
) -> Result<(), ApplicationError> {
    if import.artifacts.is_empty() {
        return Ok(());
    }
    let existing_json = tx
        .query_row(
            "SELECT artifacts_json FROM lltimeline_resources WHERE track_id=?1",
            [import.track.id.as_str()],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(repo)?;
    let Some(existing_json) = existing_json else {
        return Err(ApplicationError::Invalid(
            "content package track is missing resource metadata".into(),
        ));
    };
    let mut artifacts: Vec<LLTimelineArtifact> = from_json(&existing_json).map_err(repo)?;
    let mut identities = artifacts
        .iter()
        .map(artifact_identity)
        .collect::<Result<std::collections::HashSet<_>, _>>()?;
    let mut changed = false;
    for artifact in &import.artifacts {
        if identities.insert(artifact_identity(artifact)?) {
            artifacts.push(artifact.clone());
            changed = true;
        }
    }
    if changed {
        tx.execute(
            "UPDATE lltimeline_resources
             SET artifacts_json=?2,updated_at_ms=unixepoch('subsec') * 1000
             WHERE track_id=?1",
            params![import.track.id.as_str(), json(&artifacts)?],
        )
        .map_err(repo)?;
    }
    Ok(())
}

impl ContentPackageImportRepository for SqliteRepository {
    fn import_content_package_candidates(
        &self,
        import: &ContentPackageCandidateImport,
    ) -> Result<(), ApplicationError> {
        if import
            .corpus_occurrences
            .iter()
            .any(|occurrence| occurrence.track_id.as_ref() != Some(&import.track.id))
        {
            return Err(ApplicationError::Invalid(
                "corpus occurrence does not belong to content package track".into(),
            ));
        }
        if import
            .word_timelines
            .iter()
            .any(|value| value.status != TimelineStatus::Candidate)
            || import
                .phone_timelines
                .iter()
                .any(|value| value.status != TimelineStatus::Candidate)
            || import
                .sense_group_analyses
                .iter()
                .any(|value| value.status != TimelineStatus::Candidate)
            || import
                .prosody_analyses
                .iter()
                .any(|value| value.status != TimelineStatus::Candidate)
        {
            return Err(ApplicationError::Invalid(
                "content package persistence accepts candidates only".into(),
            ));
        }

        let mut connection = self.connection.lock();
        let tx = connection.transaction().map_err(repo)?;
        let track_existed = guard_track_identity(&tx, import)?;
        guard_sentence_ownership(&tx, import)?;
        if !track_existed {
            save_track_in_transaction(&tx, &import.track)?;
            save_lltimeline_resource_in_connection(
                &tx,
                &import.track.id,
                &import.metadata,
                &import.artifacts,
            )?;
        } else {
            merge_artifacts(&tx, import)?;
        }

        for timeline in &import.word_timelines {
            guard_timeline_ownership(
                &tx,
                "word_timeline_runs",
                timeline.id.as_str(),
                &timeline.track_id,
                &timeline.media_id,
            )?;
            if !row_exists(&tx, "word_timeline_runs", timeline.id.as_str())? {
                save_word_timeline_in_connection(&tx, timeline)?;
            }
        }
        for timeline in &import.phone_timelines {
            guard_timeline_ownership(
                &tx,
                "phone_timeline_runs",
                timeline.id.as_str(),
                &timeline.track_id,
                &timeline.media_id,
            )?;
            if !row_exists(&tx, "phone_timeline_runs", timeline.id.as_str())? {
                save_phone_timeline_in_connection(&tx, timeline)?;
            }
        }
        for analysis in &import.sense_group_analyses {
            guard_timeline_ownership(
                &tx,
                "sense_group_analysis_runs",
                analysis.id.as_str(),
                &analysis.track_id,
                &analysis.media_id,
            )?;
            if !row_exists(&tx, "sense_group_analysis_runs", analysis.id.as_str())? {
                save_sense_group_analysis_in_connection(&tx, analysis)?;
            }
        }
        for analysis in &import.prosody_analyses {
            guard_timeline_ownership(
                &tx,
                "prosody_analysis_runs",
                analysis.id.as_str(),
                &analysis.track_id,
                &analysis.media_id,
            )?;
            if !row_exists(&tx, "prosody_analysis_runs", analysis.id.as_str())? {
                save_prosody_analysis_in_connection(&tx, analysis)?;
            }
        }

        if !track_existed {
            for occurrence in &import.corpus_occurrences {
                let existing_track = tx
                    .query_row(
                        "SELECT track_id FROM corpus_occurrences WHERE id=?1",
                        [occurrence.id.as_str()],
                        |row| row.get::<_, Option<String>>(0),
                    )
                    .optional()
                    .map_err(repo)?
                    .flatten();
                if existing_track
                    .as_deref()
                    .is_some_and(|track_id| track_id != import.track.id.as_str())
                {
                    return Err(ApplicationError::Invalid(
                        "corpus occurrence id already belongs to another track".into(),
                    ));
                }
            }
            for occurrence in &import.corpus_occurrences {
                insert_occurrence(&tx, occurrence)?;
            }
        }
        tx.commit().map_err(repo)
    }
}
