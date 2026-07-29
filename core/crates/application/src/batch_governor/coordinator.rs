use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use domain::{BackgroundJob, BackgroundJobId, BackgroundJobKind, BackgroundJobStatus};
use serde::{Deserialize, Serialize};

use crate::{
    ApplicationError, BackgroundJobStore, BackgroundJobTransition, InMemoryBackgroundJobStore,
    now_ms,
};

use super::{BatchCancellationToken, RequestGovernor};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BatchExecutionState {
    Running,
    Cancelling,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct BatchProgress {
    pub batch_id: String,
    pub state: BatchExecutionState,
    pub completed_sentences: u64,
    pub total_sentences: u64,
}

#[derive(Clone)]
struct GovernorEntry {
    max_in_flight: usize,
    starts_per_second: Option<u32>,
    governor: RequestGovernor,
}

#[derive(Clone)]
struct BatchRecord {
    token: BatchCancellationToken,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LlmBatchPayload {
    account_scope: String,
    max_in_flight: usize,
    starts_per_second: Option<u32>,
}

/// Owns account-scoped governors and the lifecycle of explicitly named batch
/// executions. The HTTP layer exposes only narrow start/cancel/status actions.
#[derive(Clone)]
pub struct LlmBatchCoordinator {
    governors: Arc<Mutex<HashMap<String, GovernorEntry>>>,
    batches: Arc<Mutex<HashMap<String, BatchRecord>>>,
    jobs: Arc<dyn BackgroundJobStore>,
}

impl Default for LlmBatchCoordinator {
    fn default() -> Self {
        Self::new(Arc::new(InMemoryBackgroundJobStore::default()))
            .expect("in-memory background job recovery cannot fail")
    }
}

impl LlmBatchCoordinator {
    pub fn new(jobs: Arc<dyn BackgroundJobStore>) -> Result<Self, ApplicationError> {
        jobs.recover_startup(BackgroundJobKind::LlmBatch, now_ms())?;
        Ok(Self {
            governors: Arc::default(),
            batches: Arc::default(),
            jobs,
        })
    }

    pub fn begin(
        &self,
        batch_id: &str,
        account_scope: &str,
        max_in_flight: usize,
        starts_per_second: Option<u32>,
    ) -> Result<(RequestGovernor, BatchCancellationToken), ApplicationError> {
        if batch_id.trim().is_empty() {
            return Err(ApplicationError::Validation("batch_id"));
        }
        if account_scope.trim().is_empty() {
            return Err(ApplicationError::Validation("LLM account scope"));
        }

        let governor = {
            let mut governors = self.governors.lock().unwrap();
            let requested_max = max_in_flight.max(1);
            let requested_rate = starts_per_second.filter(|rate| *rate > 0);
            match governors.get(account_scope) {
                Some(existing)
                    if existing.max_in_flight == requested_max
                        && existing.starts_per_second == requested_rate =>
                {
                    existing.governor.clone()
                }
                Some(existing)
                    if existing.governor.available_permits() != existing.max_in_flight =>
                {
                    return Err(ApplicationError::Invalid(format!(
                        "LLM account scope {account_scope:?} cannot change batch limits while requests are active"
                    )));
                }
                Some(_) | None => {
                    let governor = RequestGovernor::with_start_rate(requested_max, requested_rate);
                    governors.insert(
                        account_scope.to_string(),
                        GovernorEntry {
                            max_in_flight: requested_max,
                            starts_per_second: requested_rate,
                            governor: governor.clone(),
                        },
                    );
                    governor
                }
            }
        };

        let id = BackgroundJobId::parse(batch_id)?;
        if self.jobs.get(&id)?.is_some() {
            return Err(ApplicationError::Conflict(
                "LLM batch identifier already exists",
            ));
        }
        let progress_jobs = self.jobs.clone();
        let progress_id = id.clone();
        let token = BatchCancellationToken::with_progress_observer(Arc::new(
            move |completed_units, total_units| {
                let Ok(Some(mut job)) = progress_jobs.get(&progress_id) else {
                    return;
                };
                if job.status != BackgroundJobStatus::Running {
                    return;
                }
                job.completed_units = completed_units;
                job.total_units = total_units;
                job.updated_at_ms = now_ms();
                let _ = progress_jobs.transition(BackgroundJobStatus::Running, &job);
            },
        ));
        let mut batches = self.batches.lock().unwrap();
        if batches.contains_key(batch_id) {
            return Err(ApplicationError::Conflict(
                "LLM batch identifier is already active",
            ));
        }
        let created_at_ms = now_ms();
        self.jobs.create(&BackgroundJob {
            id,
            kind: BackgroundJobKind::LlmBatch,
            status: BackgroundJobStatus::Running,
            payload_json: serde_json::to_string(&LlmBatchPayload {
                account_scope: account_scope.to_owned(),
                max_in_flight: max_in_flight.max(1),
                starts_per_second: starts_per_second.filter(|rate| *rate > 0),
            })
            .map_err(|error| ApplicationError::Repository(error.to_string()))?,
            completed_units: 0,
            total_units: 0,
            error: None,
            retry_of_job_id: None,
            created_at_ms,
            updated_at_ms: created_at_ms,
        })?;
        batches.insert(
            batch_id.to_string(),
            BatchRecord {
                token: token.clone(),
            },
        );
        Ok((governor, token))
    }

    pub fn cancel(&self, batch_id: &str) -> Option<BatchProgress> {
        let id = BackgroundJobId::parse(batch_id).ok()?;
        let mut job = self.jobs.get(&id).ok()??;
        let token = self
            .batches
            .lock()
            .unwrap()
            .get(batch_id)
            .map(|record| record.token.clone());
        let Some(token) = token else {
            return Some(progress(&job, None));
        };
        if job.status == BackgroundJobStatus::Running && token.cancel() {
            job.status = BackgroundJobStatus::Cancelling;
            job.completed_units = token.completed_count();
            job.total_units = token.total_count();
            job.updated_at_ms = now_ms();
            job = match self
                .jobs
                .transition(BackgroundJobStatus::Running, &job)
                .ok()?
            {
                BackgroundJobTransition::Applied(job) | BackgroundJobTransition::Rejected(job) => {
                    job
                }
            };
        }
        Some(progress(&job, Some(&token)))
    }

    pub fn finish(&self, batch_id: &str, succeeded: bool) -> Option<BatchProgress> {
        let id = BackgroundJobId::parse(batch_id).ok()?;
        let token = self.batches.lock().unwrap().get(batch_id)?.token.clone();
        let mut job = self.jobs.get(&id).ok()??;
        loop {
            if !matches!(
                job.status,
                BackgroundJobStatus::Running | BackgroundJobStatus::Cancelling
            ) {
                break;
            }
            let expected = job.status;
            job.status = if token.is_cancelled() {
                BackgroundJobStatus::Cancelled
            } else if succeeded {
                BackgroundJobStatus::Completed
            } else {
                BackgroundJobStatus::Failed
            };
            job.completed_units = token.completed_count();
            job.total_units = token.total_count();
            job.updated_at_ms = now_ms();
            match self.jobs.transition(expected, &job).ok()? {
                BackgroundJobTransition::Applied(updated) => {
                    job = updated;
                    break;
                }
                BackgroundJobTransition::Rejected(current) => job = current,
            }
        }
        self.batches.lock().unwrap().remove(batch_id);
        Some(progress(&job, Some(&token)))
    }

    pub fn status(&self, batch_id: &str) -> Option<BatchProgress> {
        let id = BackgroundJobId::parse(batch_id).ok()?;
        let job = self.jobs.get(&id).ok()??;
        let token = self
            .batches
            .lock()
            .unwrap()
            .get(batch_id)
            .map(|record| record.token.clone());
        Some(progress(&job, token.as_ref()))
    }
}

fn progress(job: &BackgroundJob, token: Option<&BatchCancellationToken>) -> BatchProgress {
    BatchProgress {
        batch_id: job.id.as_str().to_owned(),
        state: match job.status {
            BackgroundJobStatus::Queued | BackgroundJobStatus::Running => {
                BatchExecutionState::Running
            }
            BackgroundJobStatus::Cancelling => BatchExecutionState::Cancelling,
            BackgroundJobStatus::Completed => BatchExecutionState::Completed,
            BackgroundJobStatus::Cancelled => BatchExecutionState::Cancelled,
            BackgroundJobStatus::Failed | BackgroundJobStatus::Interrupted => {
                BatchExecutionState::Failed
            }
        },
        completed_sentences: token
            .map(BatchCancellationToken::completed_count)
            .unwrap_or(job.completed_units),
        total_sentences: token
            .map(BatchCancellationToken::total_count)
            .unwrap_or(job.total_units),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn account_scope_reuses_one_governor_and_allows_idle_reconfiguration() {
        let coordinator = LlmBatchCoordinator::default();
        let (first, _) = coordinator.begin("a", "account", 4, Some(10)).unwrap();
        coordinator.finish("a", true);
        let (second, _) = coordinator.begin("b", "account", 4, Some(10)).unwrap();
        assert_eq!(first.capacity(), second.capacity());
        coordinator.finish("b", true);
        let (reconfigured, _) = coordinator.begin("c", "account", 8, Some(10)).unwrap();
        assert_eq!(reconfigured.capacity(), 8);
    }

    #[tokio::test]
    async fn account_scope_rejects_limit_changes_while_requests_are_active() {
        let coordinator = LlmBatchCoordinator::default();
        let (governor, token) = coordinator.begin("a", "account", 1, None).unwrap();
        let _permit = governor
            .acquire(&token, &super::super::BatchMetrics::new())
            .await
            .unwrap();
        assert!(coordinator.begin("b", "account", 2, None).is_err());
    }

    #[test]
    fn cancellation_is_visible_in_status() {
        let coordinator = LlmBatchCoordinator::default();
        let (_, token) = coordinator.begin("batch", "account", 1, None).unwrap();
        token.set_total_count(3);
        token.record_completion();
        let progress = coordinator.cancel("batch").unwrap();
        assert_eq!(progress.state, BatchExecutionState::Cancelling);
        assert_eq!(progress.completed_sentences, 1);
        assert_eq!(progress.total_sentences, 3);
        let progress = coordinator.finish("batch", false).unwrap();
        assert_eq!(progress.state, BatchExecutionState::Cancelled);
    }

    #[test]
    fn restart_marks_an_unfinished_batch_failed_instead_of_losing_it() {
        let jobs = Arc::new(InMemoryBackgroundJobStore::default());
        let coordinator = LlmBatchCoordinator::new(jobs.clone()).unwrap();
        let (_, token) = coordinator.begin("batch", "account", 1, None).unwrap();
        token.set_total_count(3);
        token.record_completion();
        drop(coordinator);

        let restarted = LlmBatchCoordinator::new(jobs).unwrap();
        let progress = restarted.status("batch").unwrap();
        assert_eq!(progress.state, BatchExecutionState::Failed);
        assert_eq!(progress.completed_sentences, 1);
        assert_eq!(progress.total_sentences, 3);
    }
}
