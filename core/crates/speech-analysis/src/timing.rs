//! Stable timing capability interface.
//!
//! Implementation modules stay private so ASR parsing, forced alignment,
//! pause refinement, and acoustic measurement can evolve without leaking their
//! file layout to application callers.

pub use crate::asr_timing::{
    ExtractError, align_timings_to_tokens, extract_word_timings_from_json,
};
pub use crate::forced_align::{
    AlignOutput, AlignedWord, PROVIDER_ID as FORCED_ALIGN_PROVIDER_ID,
    PROVIDER_VERSION as FORCED_ALIGN_PROVIDER_VERSION, count_lexical_words, merge_alignments,
};
pub use crate::pause_refinement::{
    DetectedPause, PROVIDER_ID as PAUSE_REFINEMENT_PROVIDER_ID,
    PROVIDER_VERSION as PAUSE_REFINEMENT_PROVIDER_VERSION, PauseRefinementConfig,
    PauseRefinementError, PauseRefinementResult, refine_word_timings_from_pcm_wav,
};
pub use crate::word_acoustics::{
    PROVIDER_ID as WORD_ACOUSTICS_PROVIDER_ID, PROVIDER_VERSION as WORD_ACOUSTICS_PROVIDER_VERSION,
    WordAcousticAnalysis, WordAcousticError, WordAcousticMeasurement,
    analyze_word_acoustics_from_pcm_wav,
};
