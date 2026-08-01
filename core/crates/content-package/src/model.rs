use serde::{Deserialize, Deserializer, Serialize};

fn deserialize_required_option<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    Option::<T>::deserialize(deserializer)
}

pub const PACKAGE_SCHEMA_V1: &str = "listen.resource-package.v1";
pub const SUBTITLE_TEXT_TRACK_SCHEMA_V1: &str = "listen.resource.subtitle-text-track.v1";
pub const WORD_TIMELINE_SCHEMA_V1: &str = "listen.resource.word-timeline.v1";
pub const PHONE_TIMELINE_SCHEMA_V1: &str = "listen.resource.phone-timeline.v1";
pub const SENSE_GROUP_ANALYSIS_SCHEMA_V1: &str = "listen.resource.sense-group-analysis.v1";
pub const WORD_ACOUSTICS_SCHEMA_V1: &str = "listen.resource.word-acoustics.v1";
pub const PROSODY_ANALYSIS_SCHEMA_V1: &str = "listen.resource.prosody-analysis.v1";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PackageManifest {
    pub schema: String,
    pub created_at_ms: u64,
    pub content_document: ContentDocument,
    pub resources: Vec<ResourceManifestEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ContentDocument {
    pub media_fingerprint: String,
    pub title: String,
    pub media_kind: MediaKind,
    pub duration_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaKind {
    Audio,
    Video,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResourceManifestEntry {
    pub resource_id: String,
    pub path: String,
    pub kind: String,
    pub schema: String,
    pub size_bytes: u64,
    pub required: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResourceSubject {
    pub media_fingerprint: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResourceEnvelope<P> {
    pub schema: String,
    pub kind: String,
    pub subject: ResourceSubject,
    pub dependencies: Vec<ResourceDependency>,
    pub provenance: Provenance,
    pub quality: Quality,
    pub payload: P,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResourceDependency {
    pub resource_id: String,
    pub kind: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Provenance {
    pub created_at_ms: u64,
    pub tool: VersionedProducer,
    #[serde(default)]
    pub provider: Option<VersionedProducer>,
    #[serde(default)]
    pub model: Option<VersionedProducer>,
    #[serde(default)]
    pub config_sha256: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VersionedProducer {
    pub id: String,
    pub version: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Quality {
    pub review_status: ReviewStatus,
    #[serde(default)]
    pub confidence: Option<f64>,
    #[serde(default)]
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReviewStatus {
    Unreviewed,
    MachineChecked,
    HumanReviewed,
}

#[derive(Debug, Clone, PartialEq)]
pub enum KnownResource {
    SubtitleTextTrack(ResourceEnvelope<SubtitleTextTrack>),
    WordTimeline(ResourceEnvelope<WordTimeline>),
    PhoneTimeline(ResourceEnvelope<PhoneTimeline>),
    SenseGroupAnalysis(ResourceEnvelope<SenseGroupAnalysis>),
    WordAcoustics(ResourceEnvelope<WordAcoustics>),
    ProsodyAnalysis(ResourceEnvelope<ProsodyAnalysis>),
}

impl KnownResource {
    pub fn schema(&self) -> &str {
        match self {
            Self::SubtitleTextTrack(value) => &value.schema,
            Self::WordTimeline(value) => &value.schema,
            Self::PhoneTimeline(value) => &value.schema,
            Self::SenseGroupAnalysis(value) => &value.schema,
            Self::WordAcoustics(value) => &value.schema,
            Self::ProsodyAnalysis(value) => &value.schema,
        }
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Self::SubtitleTextTrack(_) => "subtitle_text_track",
            Self::WordTimeline(_) => "word_timeline",
            Self::PhoneTimeline(_) => "phone_timeline",
            Self::SenseGroupAnalysis(_) => "sense_group_analysis",
            Self::WordAcoustics(_) => "word_acoustics",
            Self::ProsodyAnalysis(_) => "prosody_analysis",
        }
    }

    pub fn subject(&self) -> &ResourceSubject {
        match self {
            Self::SubtitleTextTrack(value) => &value.subject,
            Self::WordTimeline(value) => &value.subject,
            Self::PhoneTimeline(value) => &value.subject,
            Self::SenseGroupAnalysis(value) => &value.subject,
            Self::WordAcoustics(value) => &value.subject,
            Self::ProsodyAnalysis(value) => &value.subject,
        }
    }

    pub fn dependencies(&self) -> &[ResourceDependency] {
        match self {
            Self::SubtitleTextTrack(value) => &value.dependencies,
            Self::WordTimeline(value) => &value.dependencies,
            Self::PhoneTimeline(value) => &value.dependencies,
            Self::SenseGroupAnalysis(value) => &value.dependencies,
            Self::WordAcoustics(value) => &value.dependencies,
            Self::ProsodyAnalysis(value) => &value.dependencies,
        }
    }

    pub fn quality(&self) -> &Quality {
        match self {
            Self::SubtitleTextTrack(value) => &value.quality,
            Self::WordTimeline(value) => &value.quality,
            Self::PhoneTimeline(value) => &value.quality,
            Self::SenseGroupAnalysis(value) => &value.quality,
            Self::WordAcoustics(value) => &value.quality,
            Self::ProsodyAnalysis(value) => &value.quality,
        }
    }

    pub fn provenance(&self) -> &Provenance {
        match self {
            Self::SubtitleTextTrack(value) => &value.provenance,
            Self::WordTimeline(value) => &value.provenance,
            Self::PhoneTimeline(value) => &value.provenance,
            Self::SenseGroupAnalysis(value) => &value.provenance,
            Self::WordAcoustics(value) => &value.provenance,
            Self::ProsodyAnalysis(value) => &value.provenance,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SubtitleTextTrack {
    pub language: String,
    pub source_kind: SubtitleSourceKind,
    pub sentences: Vec<SubtitleSentence>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SubtitleSourceKind {
    Asr,
    EmbeddedSubtitle,
    SidecarSubtitle,
    Manual,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SubtitleSentence {
    pub id: String,
    pub index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    pub original_text: String,
    pub display_text: String,
    pub tokens: Vec<SubtitleToken>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SubtitleToken {
    pub index: u32,
    pub kind: TokenKind,
    pub text: String,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub normalized: Option<String>,
    pub start_char: u32,
    pub end_char: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TokenKind {
    Word,
    Whitespace,
    Punctuation,
    Other,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WordTimeline {
    pub words: Vec<WordTiming>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WordTiming {
    pub sentence_id: String,
    pub token_index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    #[serde(default)]
    pub confidence: Option<f64>,
    pub timing_source: TimingSource,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimingSource {
    AsrReported,
    AsrAligned,
    ForcedAligned,
    Estimated,
    UserAdjusted,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TokenRef {
    pub sentence_id: String,
    pub token_index: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PhoneTimeline {
    pub phone_set: String,
    pub precision: PhoneTimelinePrecision,
    pub phones: Vec<Phone>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PhoneTimelinePrecision {
    Detected,
    Aligned,
    Approximate,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Phone {
    pub symbol: String,
    #[serde(default)]
    pub display_ipa: Option<String>,
    pub start_ms: u64,
    pub end_ms: u64,
    #[serde(default)]
    pub confidence: Option<f64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub word_ref: Option<TokenRef>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SenseGroupAnalysis {
    pub groups: Vec<SenseGroup>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SenseGroup {
    pub sentence_id: String,
    pub group_index: u32,
    pub start_token_index: u32,
    pub end_token_index_exclusive: u32,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub label: Option<String>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub head_token_index: Option<u32>,
    pub confidence: f64,
    pub sources: Vec<SenseGroupSource>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SenseGroupSource {
    DependencyParse,
    PhraseStructure,
    LanguageModel,
    Punctuation,
    LengthLimit,
    Rule,
    User,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WordAcoustics {
    pub sample_rate_hz: u32,
    pub energy_baseline: EnergyBaseline,
    pub pitch_baseline: PitchBaseline,
    pub measurements: Vec<WordAcousticMeasurement>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EnergyBaseline {
    #[serde(rename = "sentence_median_dbfs")]
    SentenceMedianDbfs,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PitchBaseline {
    #[serde(rename = "sentence_median_f0_hz")]
    SentenceMedianF0Hz,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WordAcousticMeasurement {
    pub word_ref: TokenRef,
    pub energy: EnergyMeasurement,
    pub pitch: PitchMeasurement,
    pub duration: DurationMeasurement,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub voiced_frame_ratio: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EnergyMeasurement {
    #[serde(deserialize_with = "deserialize_required_option")]
    pub rms_dbfs: Option<f64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub local_baseline_dbfs: Option<f64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub delta_db: Option<f64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub prominence: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PitchMeasurement {
    #[serde(deserialize_with = "deserialize_required_option")]
    pub median_f0_hz: Option<f64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub local_baseline_f0_hz: Option<f64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub delta_semitones: Option<f64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub range_semitones: Option<f64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub prominence: Option<f64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub reset_after: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DurationMeasurement {
    pub duration_ms: u64,
    #[serde(deserialize_with = "deserialize_required_option")]
    pub local_ratio: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProsodyAnalysis {
    pub anchors: Vec<ProsodyAnchor>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProsodyAnchor {
    pub word_ref: TokenRef,
    #[serde(default)]
    pub syllable_index: Option<u32>,
    pub lexical_stress: LexicalStress,
    pub realized_prominence: f64,
    pub utterance_role: UtteranceRole,
    pub evidence: Vec<ProsodyEvidence>,
    pub confidence: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LexicalStress {
    Primary,
    Secondary,
    Unstressed,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UtteranceRole {
    Nucleus,
    Prenuclear,
    Postnuclear,
    Unmarked,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProsodyEvidence {
    Energy,
    Pitch,
    Duration,
    LexicalStress,
    Context,
}
