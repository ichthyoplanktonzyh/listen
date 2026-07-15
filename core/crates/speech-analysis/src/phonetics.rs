//! Stable phonetic and shadowing capability interface.

pub use crate::phone_recognition::{
    PROVIDER_ID, PROVIDER_VERSION, RecognizedPhones, recognize_phones,
};
pub use crate::phonetic_alignment::{CanonicalPhone, align_phones};
pub use crate::phonetic_findings::findings_from_alignments;
pub use crate::shadowing_comparison::{
    RecordingAudioAnalysis, ShadowingAudioAnalysis, ShadowingComparisonError,
    analyze_pcm16_wav_path, compare_pcm16_wav_paths,
};
