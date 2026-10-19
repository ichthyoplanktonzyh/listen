use serde::{Deserialize, Serialize};

use crate::BackgroundJobId;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BackgroundJobKind {
    SpeechBatch,
    SoundLine,
    LlmBatch,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BackgroundJobStatus {
    Queued,
    Running,
    Cancelling,
    Completed,
    Cancelled,
    Failed,
    Interrupted,
}

impl BackgroundJobStatus {
    pub fn is_active(self) -> bool {
        matches!(self, Self::Queued | Self::Running | Self::Cancelling)
    }
}

/// Durable, workflow-neutral lifecycle record. Workflow-specific request and
/// result fields stay in `payload_json`; lifecycle, progress, retry lineage,
/// and recovery semantics remain queryable without interpreting that payload.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BackgroundJob {
    pub id: BackgroundJobId,
    pub kind: BackgroundJobKind,
    pub status: BackgroundJobStatus,
    pub payload_json: String,
    pub completed_units: u64,
    pub total_units: u64,
    pub error: Option<String>,
    pub retry_of_job_id: Option<BackgroundJobId>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}
