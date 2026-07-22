//! Stable audible-structure capability interface.
//!
//! Reference-B prediction, syntax candidate matching, sense-group partitioning,
//! and RhythmFrame construction form one caller-facing analysis capability.

pub use crate::connected_speech_rules::{
    ConnectedSpeechContext, SyntacticProviderQualification, is_default_rule_explanation,
    predict_default_connected, predict_default_connected_with_context, rule_source,
};
pub use crate::dependency_patterns::{
    DependencyEdgeConstraint, DependencyMatchCandidate, DependencyNodeConstraint,
    DependencyPatternSpec, MATCHER_VERSION, SubtitleTokenSpanCandidate, match_dependency_patterns,
};
pub use crate::sense_group_partition::{
    ALGORITHM, PROVIDER_ID, PROVIDER_VERSION, SYNTAX_ALGORITHM, SYNTAX_PROVIDER_ID,
    SYNTAX_PROVIDER_VERSION, SenseGroupPartitionConfig, SenseGroupSpan, partition_sentence,
    partition_sentence_with_syntax,
};
pub use crate::sound_analysis::{
    RhythmWordAcousticCue, SoundAnalysisConfig, build_learning_phones,
    build_rhythm_frame_from_word_timeline, build_sound_analysis, detect_prosodic_phrases,
    explain_connected_speech, syllabify,
};
