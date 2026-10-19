use application::{
    ApplicationError, CreateLearningPreparationRun, LearningPreparationRun,
    LearningPreparationRunId, LearningPreparationRunRepository, LearningPreparationRunStatus,
    LearningPreparationRunTransition,
};
use rusqlite::{OptionalExtension, params};

use crate::{SqliteRepository, from_json, json, repo};

const RUN_COLUMNS: &str = "id,target_key,input_fingerprint,plan_fingerprint,status,revision,retry_of_run_id,created_at_ms,updated_at_ms,run_json";

impl LearningPreparationRunRepository for SqliteRepository {
    fn create_active(
        &self,
        run: &LearningPreparationRun,
    ) -> Result<CreateLearningPreparationRun, ApplicationError> {
        validate_target_identity(run)?;
        if !run.status.is_active() {
            return Err(ApplicationError::Invalid(
                "a newly created learning preparation run must be active".into(),
            ));
        }
        let mut connection = self.connection.lock();
        let tx = connection.transaction().map_err(repo)?;
        let existing = select_active(&tx, &run.target_key)?;
        if let Some(existing) = existing {
            tx.commit().map_err(repo)?;
            return Ok(
                if existing.input_fingerprint == run.input_fingerprint
                    && existing.plan_fingerprint == run.plan_fingerprint
                {
                    CreateLearningPreparationRun::Existing(existing)
                } else {
                    CreateLearningPreparationRun::InputChanged(existing)
                },
            );
        }
        tx.execute(
            "INSERT INTO learning_preparation_runs
             (id,target_key,input_fingerprint,plan_fingerprint,status,revision,
              retry_of_run_id,created_at_ms,updated_at_ms,run_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)",
            params![
                run.id.as_str(),
                run.target_key,
                run.input_fingerprint,
                run.plan_fingerprint,
                status(run.status),
                run.revision,
                run.retry_of_run_id.as_ref().map(|id| id.as_str()),
                run.created_at_ms,
                run.updated_at_ms,
                json(run)?,
            ],
        )
        .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(CreateLearningPreparationRun::Created(run.clone()))
    }

    fn get(
        &self,
        id: &LearningPreparationRunId,
    ) -> Result<Option<LearningPreparationRun>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                &format!("SELECT {RUN_COLUMNS} FROM learning_preparation_runs WHERE id=?1"),
                [id.as_str()],
                read_run,
            )
            .optional()
            .map_err(repo)
    }

    fn transition(
        &self,
        expected_revision: u64,
        run: &LearningPreparationRun,
    ) -> Result<LearningPreparationRunTransition, ApplicationError> {
        validate_target_identity(run)?;
        let connection = self.connection.lock();
        let changed = connection
            .execute(
                "UPDATE learning_preparation_runs
                 SET status=?1,revision=?2,updated_at_ms=?3,run_json=?4
                 WHERE id=?5 AND revision=?6
                   AND target_key=?7 AND input_fingerprint=?8 AND plan_fingerprint=?9",
                params![
                    status(run.status),
                    run.revision,
                    run.updated_at_ms,
                    json(run)?,
                    run.id.as_str(),
                    expected_revision,
                    run.target_key,
                    run.input_fingerprint,
                    run.plan_fingerprint,
                ],
            )
            .map_err(repo)?;
        if changed == 1 {
            return Ok(LearningPreparationRunTransition::Applied(run.clone()));
        }
        let current = connection
            .query_row(
                &format!("SELECT {RUN_COLUMNS} FROM learning_preparation_runs WHERE id=?1"),
                [run.id.as_str()],
                read_run,
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("learning preparation run"))?;
        Ok(LearningPreparationRunTransition::Rejected(current))
    }

    fn recover_active(&self, now_ms: u64) -> Result<Vec<LearningPreparationRun>, ApplicationError> {
        let mut connection = self.connection.lock();
        let tx = connection.transaction().map_err(repo)?;
        let mut active = {
            let mut statement = tx
                .prepare(&format!(
                    "SELECT {RUN_COLUMNS} FROM learning_preparation_runs
                     WHERE status IN ('queued','running','cancelling')
                     ORDER BY created_at_ms,id"
                ))
                .map_err(repo)?;
            statement
                .query_map([], read_run)
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        for run in &mut active {
            let expected_revision = run.revision;
            run.recover_after_restart(now_ms);
            if run.revision != expected_revision {
                tx.execute(
                    "UPDATE learning_preparation_runs
                     SET status=?1,revision=?2,updated_at_ms=?3,run_json=?4
                     WHERE id=?5 AND revision=?6",
                    params![
                        status(run.status),
                        run.revision,
                        run.updated_at_ms,
                        json(run)?,
                        run.id.as_str(),
                        expected_revision,
                    ],
                )
                .map_err(repo)?;
            }
        }
        tx.commit().map_err(repo)?;
        Ok(active)
    }
}

fn select_active(
    connection: &rusqlite::Connection,
    target_key: &str,
) -> Result<Option<LearningPreparationRun>, ApplicationError> {
    connection
        .query_row(
            &format!(
                "SELECT {RUN_COLUMNS} FROM learning_preparation_runs
                 WHERE target_key=?1 AND status IN ('queued','running','cancelling')"
            ),
            [target_key],
            read_run,
        )
        .optional()
        .map_err(repo)
}

fn read_run(row: &rusqlite::Row<'_>) -> rusqlite::Result<LearningPreparationRun> {
    let stored_id: String = row.get(0)?;
    let stored_target_key: String = row.get(1)?;
    let stored_input_fingerprint: String = row.get(2)?;
    let stored_plan_fingerprint: String = row.get(3)?;
    let stored_status: String = row.get(4)?;
    let stored_revision: u64 = row.get(5)?;
    let stored_retry_of_run_id: Option<String> = row.get(6)?;
    let stored_created_at_ms: u64 = row.get(7)?;
    let stored_updated_at_ms: u64 = row.get(8)?;
    let run: LearningPreparationRun = from_json(&row.get::<_, String>(9)?)?;
    if run.id.as_str() != stored_id
        || run.target_key != stored_target_key
        || run.input_fingerprint != stored_input_fingerprint
        || run.plan_fingerprint != stored_plan_fingerprint
        || status(run.status) != stored_status
        || run.revision != stored_revision
        || run.retry_of_run_id.as_ref().map(|id| id.as_str()) != stored_retry_of_run_id.as_deref()
        || run.created_at_ms != stored_created_at_ms
        || run.updated_at_ms != stored_updated_at_ms
    {
        return Err(rusqlite::Error::InvalidQuery);
    }
    Ok(run)
}

fn validate_target_identity(run: &LearningPreparationRun) -> Result<(), ApplicationError> {
    if run.target_key != run.target.target_key()
        || run.input_fingerprint != run.target.input_fingerprint()
    {
        return Err(ApplicationError::Invalid(
            "learning preparation target identity changed".into(),
        ));
    }
    Ok(())
}

fn status(value: LearningPreparationRunStatus) -> &'static str {
    match value {
        LearningPreparationRunStatus::Queued => "queued",
        LearningPreparationRunStatus::Running => "running",
        LearningPreparationRunStatus::Cancelling => "cancelling",
        LearningPreparationRunStatus::Completed => "completed",
        LearningPreparationRunStatus::Failed => "failed",
        LearningPreparationRunStatus::Cancelled => "cancelled",
    }
}
