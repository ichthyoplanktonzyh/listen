use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde::Serialize;

use crate::ApplicationError;

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
    state: BatchExecutionState,
}

/// Owns account-scoped governors and the lifecycle of explicitly named batch
/// executions. The HTTP layer exposes only narrow start/cancel/status actions.
#[derive(Clone, Default)]
pub struct LlmBatchCoordinator {
    governors: Arc<Mutex<HashMap<String, GovernorEntry>>>,
    batches: Arc<Mutex<HashMap<String, BatchRecord>>>,
}

impl LlmBatchCoordinator {
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

        let token = BatchCancellationToken::new();
        let mut batches = self.batches.lock().unwrap();
        if batches.get(batch_id).is_some_and(|record| {
            matches!(
                record.state,
                BatchExecutionState::Running | BatchExecutionState::Cancelling
            )
        }) {
            return Err(ApplicationError::Conflict(
                "LLM batch identifier is already active",
            ));
        }
        batches.insert(
            batch_id.to_string(),
            BatchRecord {
                token: token.clone(),
                state: BatchExecutionState::Running,
            },
        );
        Ok((governor, token))
    }

    pub fn cancel(&self, batch_id: &str) -> Option<BatchProgress> {
        let mut batches = self.batches.lock().unwrap();
        let record = batches.get_mut(batch_id)?;
        if record.state == BatchExecutionState::Running && record.token.cancel() {
            record.state = BatchExecutionState::Cancelling;
        }
        Some(progress(batch_id, record))
    }

    pub fn finish(&self, batch_id: &str, succeeded: bool) -> Option<BatchProgress> {
        let mut batches = self.batches.lock().unwrap();
        let record = batches.get_mut(batch_id)?;
        record.state = if record.token.is_cancelled() {
            BatchExecutionState::Cancelled
        } else if succeeded {
            BatchExecutionState::Completed
        } else {
            BatchExecutionState::Failed
        };
        Some(progress(batch_id, record))
    }

    pub fn status(&self, batch_id: &str) -> Option<BatchProgress> {
        let batches = self.batches.lock().unwrap();
        batches
            .get(batch_id)
            .map(|record| progress(batch_id, record))
    }
}

fn progress(batch_id: &str, record: &BatchRecord) -> BatchProgress {
    BatchProgress {
        batch_id: batch_id.to_string(),
        state: record.state,
        completed_sentences: record.token.completed_count(),
        total_sentences: record.token.total_count(),
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
}
