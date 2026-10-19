use domain::{SubtitleSentence, WordTiming};

use super::frame_cues::{AcousticFrameSample, SpeechActivitySpan};

pub struct SoundAnalysisConfig<'a> {
    pub provider_id: &'a str,
    pub provider_version: &'a str,
    pub model_revision: Option<String>,
    pub phone_set: &'a str,
    pub sentence: Option<&'a SubtitleSentence>,
    pub word_timings: Option<&'a [WordTiming]>,
    pub word_acoustic_cues: Option<&'a [RhythmWordAcousticCue]>,
    /// Frame-level AcousticTrack evidence for this sentence, if present. When
    /// `word_acoustic_cues` is absent, Core derives the cues from these frames;
    /// Gen-supplied cues take precedence over Core-derived ones.
    pub acoustic_frames: Option<&'a [AcousticFrameSample]>,
    /// Measured speech/silence spans for this sentence, if present. Read only as
    /// corroborating evidence for boundaries the detector already found.
    pub speech_activity: Option<&'a [SpeechActivitySpan]>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RhythmWordAcousticCue {
    pub token_index: u32,
    pub energy_prominence: Option<f32>,
    pub pitch_prominence: Option<f32>,
    pub pitch_reset_after: Option<f32>,
}
