mod anchors;
mod boundaries;
mod build;
mod config;
mod connected;
mod constants;
mod grouping;
mod helpers;
mod hotspots;
mod nuclei;
mod phones;
mod quality;
mod references;
mod tokens;

pub use build::{build_rhythm_frame_from_word_timeline, build_sound_analysis};
pub use config::{RhythmWordAcousticCue, SoundAnalysisConfig};
pub use connected::explain_connected_speech;
pub use phones::{build_learning_phones, detect_prosodic_phrases, syllabify};

#[cfg(test)]
mod tests;
