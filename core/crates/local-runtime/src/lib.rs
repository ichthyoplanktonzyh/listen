//! Local-machine runtime capabilities.
//!
//! This crate owns background job state, model/resource installation, child
//! processes, tool discovery, and temporary workspaces. It deliberately has no
//! dependency on Axum or HTTP request/response types.

pub mod events;

mod download;
mod learning_resources;
mod phonetic_analysis;
mod process;
mod runtime_support;
mod sound_line;
mod speech_jobs;
mod speech_synthesis;
mod subtitle_search;
mod syntax_capability;
mod transcription;

pub use download::{
    ArtifactDownloader, DownloadProgress, FakeArtifactDownloader, ReqwestArtifactDownloader,
};
pub use learning_resources::{LearningResourceError, LearningResourceManager};
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
pub use speech_synthesis::{
    MacOsSystemSpeechProvider, SpeechSynthesisAsset, SpeechSynthesisCapabilityView,
    SpeechSynthesisManager, SpeechSynthesisRequest,
};
pub use subtitle_search::{
    SubtitleDownloadRequest, SubtitleOperation, SubtitleProviderError, SubtitleSearchCoordinator,
    SubtitleSearchRequest,
};
pub use syntax_capability::{
    SyntaxCapabilityManager, SyntaxCapabilityStatus, SyntaxCapabilityView,
};
pub use transcription::{
    CreateJobRequest, CreateRecordingTranscriptionRequest, TranscriptionCoordinator,
};
