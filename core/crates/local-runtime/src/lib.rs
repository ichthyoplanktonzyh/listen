//! Local-machine runtime capabilities.
//!
//! This crate owns background job state, model/resource installation, child
//! processes, tool discovery, and temporary workspaces. It deliberately has no
//! dependency on Axum or HTTP request/response types.

pub mod events;

mod download;
mod phonetic_analysis;
mod process;
mod runtime_support;
mod sound_line;
mod speech_jobs;
mod transcription;

pub use download::{
    ArtifactDownloader, DownloadProgress, FakeArtifactDownloader, ReqwestArtifactDownloader,
};
pub use phonetic_analysis::{CreatePhoneticJobRequest, PhoneticAnalysisCoordinator, finding_id};
pub use process::{
    CancellationProbe, FakeProcessRunner, IgnoreProcessOutput, NeverCancelled,
    ProcessOutputObserver, ProcessRunner, ProcessSpec, TokioProcessRunner,
};
pub use sound_line::{CreateSoundLineJob, SoundLineCoordinator, SoundLineJob, SoundLineStatus};
pub use speech_jobs::{
    CreateSpeechBatchJob, SpeechBatchCoordinator, SpeechBatchJob, SpeechBatchKind,
    SpeechBatchStatus,
};
pub use transcription::{CreateJobRequest, TranscriptionCoordinator};
