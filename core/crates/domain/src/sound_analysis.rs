use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SoundPhoneEvidence {
    ExpectedOnly,
    ObservedOnly,
    Match,
    Substitution,
    Merge,
    Deletion,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SoundLearningPhone {
    pub symbol: String,
    pub display_ipa: String,
    pub phone_set: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub confidence: Option<f32>,
    pub token_index: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stress: Option<u8>,
    pub observed_phone_index: Option<u32>,
    pub observed_symbol: Option<String>,
    pub evidence: SoundPhoneEvidence,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectedSpeechFamily {
    WeakForm,
    Deletion,
    Linking,
    Assimilation,
    Contraction,
    Flapping,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectedSpeechExplanationStatus {
    PossibleByRule,
    SupportedByAudio,
    DetectedInAudio,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ConnectedSpeechExplanation {
    pub family: ConnectedSpeechFamily,
    pub label: String,
    pub hint: String,
    pub phone_start: Option<u32>,
    pub phone_end: Option<u32>,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub confidence: f32,
    pub status: ConnectedSpeechExplanationStatus,
    pub expected_symbols: Vec<String>,
    pub learning_symbols: Vec<String>,
    pub observed_symbols: Vec<String>,
    pub evidence: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyllableStress {
    Primary,
    Secondary,
    Unstressed,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SoundSyllable {
    pub phones: Vec<u32>,
    pub onset: Vec<u32>,
    pub nucleus: Vec<u32>,
    pub coda: Vec<u32>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub stress: SyllableStress,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProsodicBoundaryEvidence {
    SentenceStart,
    Pause,
    TentativeLengthening,
    SentenceEnd,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SoundProsodicPhrase {
    pub syllables: Vec<u32>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub boundary_evidence: ProsodicBoundaryEvidence,
    pub confidence: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RhythmAnchorImportance {
    Primary,
    Secondary,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RhythmSignalSource {
    TextPrior,
    Timing,
    Energy,
    Pitch,
    PhoneSegmental,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RhythmEvidenceClass {
    Gold,
    SilverLabel,
    HeuristicProxy,
    ManualProductQa,
    Coverage,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RhythmClaimStatus {
    Predicted,
    AudioSupported,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RhythmDivergenceKind {
    TeachableRule,
    ClipSpecific,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmReference {
    pub label: String,
    pub source: String,
    pub evidence_class: RhythmEvidenceClass,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmFrameReferences {
    pub citation: RhythmReference,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_connected: Option<RhythmReference>,
    pub actual: RhythmReference,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmStressAnchor {
    pub token_index: Option<u32>,
    pub syllable_index: Option<u32>,
    pub phone_start: Option<u32>,
    pub phone_end: Option<u32>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub label: String,
    pub reason: String,
    pub importance: RhythmAnchorImportance,
    pub is_nucleus: bool,
    pub prominence: f32,
    pub prominence_cues: Vec<RhythmSignalSource>,
    pub signal_sources: Vec<RhythmSignalSource>,
    pub evidence_class: RhythmEvidenceClass,
    pub claim_status: RhythmClaimStatus,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmNucleus {
    pub phrase_index: u32,
    pub token_index: Option<u32>,
    pub syllable_index: Option<u32>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub label: String,
    pub reason: String,
    pub cues: Vec<RhythmSignalSource>,
    pub evidence_class: RhythmEvidenceClass,
    pub claim_status: RhythmClaimStatus,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmWeakGroup {
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub phone_start: Option<u32>,
    pub phone_end: Option<u32>,
    pub anchor_token_index: Option<u32>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub label: String,
    pub reason: String,
    #[serde(default)]
    pub reduction_refs: Vec<String>,
    pub signal_sources: Vec<RhythmSignalSource>,
    pub evidence_class: RhythmEvidenceClass,
    pub claim_status: RhythmClaimStatus,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmCompressionSpan {
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub phone_start: Option<u32>,
    pub phone_end: Option<u32>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub expected_units: u32,
    pub duration_ms: u64,
    pub unit_rate_per_second: f32,
    pub label: String,
    pub reason: String,
    pub signal_sources: Vec<RhythmSignalSource>,
    pub evidence_class: RhythmEvidenceClass,
    pub claim_status: RhythmClaimStatus,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmPhraseBoundary {
    pub after_token_index: Option<u32>,
    pub before_token_index: Option<u32>,
    pub at_ms: u64,
    pub reason: String,
    pub cues: Vec<String>,
    pub signal_sources: Vec<RhythmSignalSource>,
    pub evidence_class: RhythmEvidenceClass,
    pub claim_status: RhythmClaimStatus,
    pub is_final: bool,
    pub confidence: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ListeningHotspotKind {
    WeakGroup,
    CompressedSpan,
    PhraseBoundary,
    ConnectedSpeech,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ListeningHotspot {
    pub id: String,
    pub kind: ListeningHotspotKind,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub phone_start: Option<u32>,
    pub phone_end: Option<u32>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub label: String,
    pub hint: String,
    pub signal_sources: Vec<RhythmSignalSource>,
    pub evidence_class: RhythmEvidenceClass,
    pub claim_status: RhythmClaimStatus,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmConnectedSpeechRef {
    pub id: String,
    pub connected_speech_index: Option<u32>,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub phone_start: Option<u32>,
    pub phone_end: Option<u32>,
    pub label: String,
    pub divergence: RhythmDivergenceKind,
    pub signal_sources: Vec<RhythmSignalSource>,
    pub evidence_class: RhythmEvidenceClass,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmFrameQuality {
    pub timing_source: String,
    pub prominence_sources: Vec<RhythmSignalSource>,
    pub boundary_sources: Vec<RhythmSignalSource>,
    pub connected_speech_source: RhythmSignalSource,
    pub phone_evidence_coverage: f32,
    pub rhythm_confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RhythmFrame {
    pub generated_from: String,
    pub references: RhythmFrameReferences,
    pub stress_anchors: Vec<RhythmStressAnchor>,
    pub nuclei: Vec<RhythmNucleus>,
    pub weak_groups: Vec<RhythmWeakGroup>,
    pub compression_spans: Vec<RhythmCompressionSpan>,
    pub phrase_boundaries: Vec<RhythmPhraseBoundary>,
    pub connected_speech_refs: Vec<RhythmConnectedSpeechRef>,
    pub listening_hotspots: Vec<ListeningHotspot>,
    pub quality: RhythmFrameQuality,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SoundAnalysis {
    pub provider_id: String,
    pub provider_version: String,
    pub model_revision: Option<String>,
    pub phone_set: String,
    pub generated_from: String,
    pub learning_phones: Vec<SoundLearningPhone>,
    #[serde(default)]
    pub connected_speech: Vec<ConnectedSpeechExplanation>,
    pub syllables: Vec<SoundSyllable>,
    pub prosodic_phrases: Vec<SoundProsodicPhrase>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rhythm_frame: Option<RhythmFrame>,
}
