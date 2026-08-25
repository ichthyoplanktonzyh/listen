//! Stable phonetic and shadowing capability interface.

pub use crate::phone_recognition::{
    PROVIDER_ID as PHONE_PROVIDER_ID, PROVIDER_VERSION as PHONE_PROVIDER_VERSION,
};
pub use crate::phone_recognition::{
    PROVIDER_ID, PROVIDER_VERSION, RecognizedPhones, map_ipa_symbol_to_arpabet, recognize_phones,
};
pub use crate::phonetic_alignment::{CanonicalPhone, align_phones};
pub use crate::phonetic_findings::findings_from_alignments;
pub use crate::shadowing_comparison::{
    CanonicalPhoneWithTime, RecordingAudioAnalysis, ShadowingAudioAnalysis,
    ShadowingComparisonError, analyze_pcm16_wav_path, compare_pcm16_wav_paths,
    compare_shadowing_v2,
};
