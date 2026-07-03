use domain::{SubtitleSentence, WordTiming};

pub struct SoundAnalysisConfig<'a> {
    pub provider_id: &'a str,
    pub provider_version: &'a str,
    pub model_revision: Option<String>,
    pub phone_set: &'a str,
    pub sentence: Option<&'a SubtitleSentence>,
    pub word_timings: Option<&'a [WordTiming]>,
    pub word_acoustic_cues: Option<&'a [RhythmWordAcousticCue]>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RhythmWordAcousticCue {
    pub token_index: u32,
    pub energy_prominence: Option<f32>,
    pub pitch_prominence: Option<f32>,
    pub pitch_reset_after: Option<f32>,
}
