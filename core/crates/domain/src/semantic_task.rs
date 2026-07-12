//! Phase 3.11 semantic task fact layer: clip-level attempts, versioned
//! rubrics, per-point judgments, and user adjudications.
//!
//! Layer separation (shared context §3.1 / evidence matrix):
//! attempt != judgment != target-level observation != projection/override.
//! Nothing in this module writes or references `LearningObservation`; semantic
//! tasks are structurally incapable of batch lexical evidence.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{
    JudgmentAdjudicationId, LanguageCode, MediaId, PracticeAnchor, PracticeTarget,
    RecordingAssetId, SemanticJudgmentId, SemanticRubricId, SemanticTaskAttemptId, SubtitleTrackId,
};

/// Closed on purpose: a task kind may only exist after it has an evidence
/// matrix row deciding its channel, assistance, and write boundary. Extending
/// this enum requires a matrix row and an ADR 0021 version note, mirroring the
/// ADR 0017 mapping discipline.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticTaskKind {
    ReadingComprehension,
    L1Retelling,
    L2Retelling,
    RoleReply,
    Dictogloss,
    Summary,
    PatternProduction,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RubricPointImportance {
    Required,
    Optional,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RubricPoint {
    /// Stable within one rubric version; judgments address points by this id.
    pub point_id: String,
    pub importance: RubricPointImportance,
    pub statement: String,
    pub accepted_paraphrase_notes: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticGeneratorKind {
    Fixture,
    Manual,
    Llm,
}

/// Who/what produced a rubric or judgment. Model/prompt/schema stay optional
/// because fixture and manual generators have none, but an `llm` generator
/// with them absent is recorded as incomplete provenance, never invented.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SemanticGeneratorProvenance {
    pub kind: SemanticGeneratorKind,
    pub detail: Option<String>,
    pub model_id: Option<String>,
    pub prompt_version: Option<String>,
    pub schema_version: Option<String>,
}

/// Self-sufficient source snapshot: media/track references are optional
/// context that may dangle after deletion, while the transcript snapshot and
/// time range keep the rubric explainable forever.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RubricSource {
    pub media_id: Option<MediaId>,
    pub track_id: Option<SubtitleTrackId>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub language: LanguageCode,
    pub transcript_snapshot: String,
}

/// Manual revision provenance for rubric versions above 1. Revisions append a
/// new version; earlier versions are never rewritten.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RubricRevisionNote {
    pub revised_from_version: u32,
    pub note: String,
    pub revised_at_ms: u64,
}

/// Rubric identity is (source segment, purpose); `version` increments on
/// manual revision. Judgments are directly comparable only when they cite the
/// same (id, version, source hash) — see [`judgments_directly_comparable`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SemanticRubric {
    pub id: SemanticRubricId,
    /// Same segment, different purpose (retelling vs summary) is a different
    /// rubric identity; their judgments are never comparable.
    pub purpose: SemanticTaskKind,
    pub source: RubricSource,
    /// Language pair = `source.language` -> `response_language`.
    pub response_language: LanguageCode,
    pub points: Vec<RubricPoint>,
    pub version: u32,
    pub provenance: SemanticGeneratorProvenance,
    pub revision: Option<RubricRevisionNote>,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticAttemptStatus {
    Completed,
    Abandoned,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResponseTranscriptSource {
    Typed,
    Asr,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AsrReliability {
    Reliable,
    Suspect,
    Unreliable,
}

/// Why the learner entered L1 retelling. L1 is an attribution tool, not a
/// fixed pre-step (final discussion §3.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum L1RetellingTrigger {
    UserRequested,
    L2Failed,
    Diagnosis,
}

/// What the learner could access besides the assessed channel's input. The
/// per-kind legality rules live in [`validate_semantic_attempt`], sourced from
/// the evidence matrix §1/§2.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SemanticTaskConditions {
    pub source_text_visible: bool,
    pub audio_play_count: Option<u32>,
    pub notes_allowed: bool,
    pub l1_trigger: Option<L1RetellingTrigger>,
}

/// One versioned learner response inside an attempt. Multiple revisions exist
/// only for dictogloss (draft 1 / draft 2 against the same rubric).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttemptResponse {
    /// 1-based, contiguous.
    pub revision: u32,
    pub transcript: String,
    pub source: ResponseTranscriptSource,
    pub recording_asset_id: Option<RecordingAssetId>,
    /// Required when `source == Asr`, forbidden for typed input.
    pub asr_reliability: Option<AsrReliability>,
    pub language: LanguageCode,
    pub recorded_at_ms: u64,
}

/// A clip-level semantic task fact. Outcome lives in [`SemanticJudgment`];
/// the attempt itself only completes or is abandoned — there is no
/// correct/incorrect at this layer.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SemanticTaskAttempt {
    pub id: SemanticTaskAttemptId,
    pub kind: SemanticTaskKind,
    pub target: PracticeTarget,
    pub anchors: Vec<PracticeAnchor>,
    pub rubric_id: SemanticRubricId,
    pub rubric_version: u32,
    pub conditions: SemanticTaskConditions,
    pub responses: Vec<AttemptResponse>,
    pub status: SemanticAttemptStatus,
    pub started_at_ms: u64,
    pub ended_at_ms: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PointVerdict {
    Covered,
    Partial,
    Missing,
    Uncertain,
}

/// Half-open `[start_char, end_char)` range in Unicode scalar values over the
/// judged response transcript. Judgment citations must locate exactly.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResponseSpan {
    pub start_char: u32,
    pub end_char: u32,
}

impl ResponseSpan {
    fn is_valid_for(self, char_count: u32) -> bool {
        self.start_char < self.end_char && self.end_char <= char_count
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PointJudgment {
    pub point_id: String,
    pub verdict: PointVerdict,
    pub supporting_spans: Vec<ResponseSpan>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AbstainReason {
    UnreliableTranscript,
    EmptyResponse,
    GeneratorRefused,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct JudgmentAbstain {
    pub reason: AbstainReason,
    pub note: Option<String>,
}

/// One automatic (or fixture/manual) verdict over one response revision.
/// Append-only: adjudication never mutates this record, and re-judging after
/// a model upgrade creates a new row.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SemanticJudgment {
    pub id: SemanticJudgmentId,
    pub attempt_id: SemanticTaskAttemptId,
    pub response_revision: u32,
    pub rubric_id: SemanticRubricId,
    pub rubric_version: u32,
    /// sha256 of the rubric's source transcript snapshot at judgment time.
    pub rubric_source_sha256: String,
    /// sha256 of the judged response transcript.
    pub response_transcript_sha256: String,
    /// Empty exactly when `abstain` is set; otherwise covers every rubric
    /// point exactly once.
    pub points: Vec<PointJudgment>,
    pub abstain: Option<JudgmentAbstain>,
    pub provenance: SemanticGeneratorProvenance,
    pub raw_output: serde_json::Value,
    /// AGENT.md evidence class of this judgment (orthogonal to generator
    /// kind): fixture gold, manual_product_qa, heuristic_proxy, ...
    pub evidence_class: String,
    pub created_at_ms: u64,
}

/// A user confirming or correcting one point of one judgment. This is not a
/// capability override and never rewrites the judgment row.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct JudgmentAdjudication {
    pub id: JudgmentAdjudicationId,
    pub judgment_id: SemanticJudgmentId,
    pub point_id: String,
    pub prior_verdict: PointVerdict,
    pub user_verdict: PointVerdict,
    pub note: Option<String>,
    pub occurred_at_ms: u64,
}

pub fn transcript_sha256(transcript: &str) -> String {
    hex::encode(Sha256::digest(transcript.as_bytes()))
}

/// Rubric identity: source segment + purpose + language pair. Media identity
/// participates when present so two media with identical transcripts stay
/// distinct; the snapshot hash keeps identity meaningful after deletion.
pub fn semantic_rubric_id(
    media_id: Option<&MediaId>,
    start_ms: u64,
    end_ms: u64,
    purpose: SemanticTaskKind,
    source_language: &LanguageCode,
    response_language: &LanguageCode,
    transcript_snapshot: &str,
) -> SemanticRubricId {
    SemanticRubricId::from_fingerprint(
        "semantic-rubric",
        &format!(
            "{}:{start_ms}:{end_ms}:{}:{}:{}:{}",
            media_id.map(MediaId::as_str).unwrap_or(""),
            serde_json::to_string(&purpose).expect("kind serializes"),
            source_language.as_str(),
            response_language.as_str(),
            transcript_sha256(transcript_snapshot),
        ),
    )
}

/// Attempt identity: the rubric it answers, when it started, and what was
/// actually said — two different responses in the same millisecond stay two
/// attempts, while a byte-identical replay stays idempotent.
pub fn semantic_task_attempt_id(
    rubric_id: &SemanticRubricId,
    rubric_version: u32,
    kind: SemanticTaskKind,
    started_at_ms: u64,
    responses: &[AttemptResponse],
) -> SemanticTaskAttemptId {
    let response_fingerprint = transcript_sha256(
        &responses
            .iter()
            .map(|response| response.transcript.as_str())
            .collect::<Vec<_>>()
            .join("\u{1f}"),
    );
    SemanticTaskAttemptId::from_fingerprint(
        "semantic-attempt",
        &format!(
            "{}:{rubric_version}:{}:{started_at_ms}:{response_fingerprint}",
            rubric_id.as_str(),
            serde_json::to_string(&kind).expect("kind serializes"),
        ),
    )
}

pub fn semantic_judgment_id(
    attempt_id: &SemanticTaskAttemptId,
    response_revision: u32,
    rubric_version: u32,
    generator: SemanticGeneratorKind,
    created_at_ms: u64,
) -> SemanticJudgmentId {
    SemanticJudgmentId::from_fingerprint(
        "semantic-judgment",
        &format!(
            "{}:{response_revision}:{rubric_version}:{}:{created_at_ms}",
            attempt_id.as_str(),
            serde_json::to_string(&generator).expect("kind serializes"),
        ),
    )
}

pub fn judgment_adjudication_id(
    judgment_id: &SemanticJudgmentId,
    point_id: &str,
    user_verdict: PointVerdict,
    occurred_at_ms: u64,
) -> JudgmentAdjudicationId {
    JudgmentAdjudicationId::from_fingerprint(
        "judgment-adjudication",
        &format!(
            "{}:{point_id}:{}:{occurred_at_ms}",
            judgment_id.as_str(),
            serde_json::to_string(&user_verdict).expect("verdict serializes"),
        ),
    )
}

pub fn validate_semantic_rubric(rubric: &SemanticRubric) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    if rubric.version == 0 {
        errors.push("rubric version must be >= 1".into());
    }
    match (&rubric.revision, rubric.version) {
        (None, v) if v > 1 => {
            errors.push("rubric versions above 1 must carry a revision note".into());
        }
        (Some(_), 1) => errors.push("rubric version 1 must not carry a revision note".into()),
        (Some(note), v) if note.revised_from_version >= v => {
            errors.push("revision must come from an earlier version".into());
        }
        _ => {}
    }
    if rubric.source.transcript_snapshot.trim().is_empty() {
        errors.push("rubric source transcript snapshot must not be empty".into());
    }
    if rubric.source.start_ms >= rubric.source.end_ms {
        errors.push("rubric source range must be non-empty".into());
    }
    if rubric.points.is_empty() {
        errors.push("rubric must declare at least one point".into());
    }
    if !rubric
        .points
        .iter()
        .any(|point| point.importance == RubricPointImportance::Required)
    {
        errors.push("rubric must declare at least one required point".into());
    }
    let mut seen = std::collections::HashSet::new();
    for point in &rubric.points {
        if point.point_id.trim().is_empty() {
            errors.push("rubric point_id must not be empty".into());
        }
        if !seen.insert(point.point_id.as_str()) {
            errors.push(format!("duplicate rubric point_id {}", point.point_id));
        }
        if point.statement.trim().is_empty() {
            errors.push(format!(
                "rubric point {} statement is empty",
                point.point_id
            ));
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

/// Per-kind legality from the evidence matrix. This is where "the original
/// sentence must be hidden for constructed output" becomes a type-level fact.
pub fn validate_semantic_attempt(
    attempt: &SemanticTaskAttempt,
    rubric: &SemanticRubric,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    if attempt.rubric_id != rubric.id {
        errors.push("attempt must reference its rubric id".into());
    }
    if attempt.rubric_version != rubric.version {
        errors.push("attempt must reference its rubric version".into());
    }
    if attempt.kind != rubric.purpose {
        errors.push("attempt kind must match rubric purpose".into());
    }
    let hidden_source_kinds = [
        SemanticTaskKind::L1Retelling,
        SemanticTaskKind::L2Retelling,
        SemanticTaskKind::RoleReply,
        SemanticTaskKind::Dictogloss,
    ];
    if hidden_source_kinds.contains(&attempt.kind) && attempt.conditions.source_text_visible {
        errors.push(format!(
            "{:?} requires the source text to be hidden",
            attempt.kind
        ));
    }
    if attempt.kind == SemanticTaskKind::ReadingComprehension
        && !attempt.conditions.source_text_visible
    {
        errors.push("reading comprehension requires the source text to be visible".into());
    }
    match (attempt.kind, attempt.conditions.l1_trigger) {
        (SemanticTaskKind::L1Retelling, None) => {
            errors.push("l1_retelling must record its trigger".into());
        }
        (kind, Some(_)) if kind != SemanticTaskKind::L1Retelling => {
            errors.push("l1_trigger is only valid on l1_retelling".into());
        }
        _ => {}
    }
    if attempt.responses.len() > 1 && attempt.kind != SemanticTaskKind::Dictogloss {
        errors.push("multiple response revisions are only defined for dictogloss".into());
    }
    if attempt.status == SemanticAttemptStatus::Completed && attempt.responses.is_empty() {
        errors.push("a completed attempt must carry at least one response".into());
    }
    for (index, response) in attempt.responses.iter().enumerate() {
        if response.revision as usize != index + 1 {
            errors.push("response revisions must be contiguous starting at 1".into());
        }
        if response.language != rubric.response_language {
            errors.push("response language must match the rubric response language".into());
        }
        match response.source {
            ResponseTranscriptSource::Asr if response.asr_reliability.is_none() => {
                errors.push("asr responses must record reliability".into());
            }
            ResponseTranscriptSource::Typed
                if response.asr_reliability.is_some() || response.recording_asset_id.is_some() =>
            {
                errors.push("typed responses carry no asr reliability or recording".into());
            }
            _ => {}
        }
    }
    if let Some(ended) = attempt.ended_at_ms
        && ended < attempt.started_at_ms
    {
        errors.push("attempt cannot end before it starts".into());
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

pub fn validate_semantic_judgment(
    judgment: &SemanticJudgment,
    rubric: &SemanticRubric,
    attempt: &SemanticTaskAttempt,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    if judgment.attempt_id != attempt.id {
        errors.push("judgment must reference its attempt".into());
    }
    if judgment.rubric_id != rubric.id
        || judgment.rubric_version != rubric.version
        || attempt.rubric_id != rubric.id
        || attempt.rubric_version != rubric.version
    {
        errors.push("judgment, attempt, and rubric must agree on rubric identity".into());
    }
    if judgment.rubric_source_sha256 != transcript_sha256(&rubric.source.transcript_snapshot) {
        errors.push("judgment rubric source hash does not match the rubric snapshot".into());
    }
    let response = attempt
        .responses
        .iter()
        .find(|response| response.revision == judgment.response_revision);
    let Some(response) = response else {
        errors.push("judgment must reference an existing response revision".into());
        return Err(errors);
    };
    if judgment.response_transcript_sha256 != transcript_sha256(&response.transcript) {
        errors.push("judgment response hash does not match the response transcript".into());
    }
    match &judgment.abstain {
        Some(_) => {
            if !judgment.points.is_empty() {
                errors.push("an abstaining judgment must not carry point verdicts".into());
            }
        }
        None => {
            let rubric_ids: std::collections::HashSet<&str> = rubric
                .points
                .iter()
                .map(|point| point.point_id.as_str())
                .collect();
            let mut judged = std::collections::HashSet::new();
            for point in &judgment.points {
                if !rubric_ids.contains(point.point_id.as_str()) {
                    errors.push(format!(
                        "judged point {} is not in the rubric",
                        point.point_id
                    ));
                }
                if !judged.insert(point.point_id.as_str()) {
                    errors.push(format!("point {} judged more than once", point.point_id));
                }
            }
            if judged.len() != rubric_ids.len() {
                errors.push("a non-abstaining judgment must judge every rubric point".into());
            }
            let char_count = response.transcript.chars().count() as u32;
            for point in &judgment.points {
                for span in &point.supporting_spans {
                    if !span.is_valid_for(char_count) {
                        errors.push(format!(
                            "span {}..{} of point {} falls outside the response transcript",
                            span.start_char, span.end_char, point.point_id
                        ));
                    }
                }
                match point.verdict {
                    PointVerdict::Missing if !point.supporting_spans.is_empty() => {
                        errors.push(format!(
                            "missing point {} must not cite supporting spans",
                            point.point_id
                        ));
                    }
                    PointVerdict::Covered | PointVerdict::Partial
                        if point.supporting_spans.is_empty() =>
                    {
                        errors.push(format!(
                            "point {} verdict requires at least one supporting span",
                            point.point_id
                        ));
                    }
                    _ => {}
                }
            }
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

/// Two judgments may be compared point-by-point only when they cite the same
/// rubric identity, version, and source snapshot, and neither abstained.
pub fn judgments_directly_comparable(a: &SemanticJudgment, b: &SemanticJudgment) -> bool {
    a.rubric_id == b.rubric_id
        && a.rubric_version == b.rubric_version
        && a.rubric_source_sha256 == b.rubric_source_sha256
        && a.abstain.is_none()
        && b.abstain.is_none()
}

pub fn validate_judgment_adjudication(
    adjudication: &JudgmentAdjudication,
    judgment: &SemanticJudgment,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    if adjudication.judgment_id != judgment.id {
        errors.push("adjudication must reference its judgment".into());
    }
    if judgment.abstain.is_some() {
        errors.push("an abstaining judgment has no point verdicts to adjudicate".into());
    }
    match judgment
        .points
        .iter()
        .find(|point| point.point_id == adjudication.point_id)
    {
        None => errors.push(format!(
            "adjudicated point {} is not in the judgment",
            adjudication.point_id
        )),
        Some(point) if point.verdict != adjudication.prior_verdict => {
            errors.push("adjudication prior verdict must match the recorded verdict".into());
        }
        Some(_) => {}
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

/// Committed gold fixture for contract tests across domain, persistence, and
/// HTTP layers. Works fully offline: no network, no model.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SemanticTaskGoldFixture {
    pub fixture_version: u32,
    pub evidence_class: String,
    pub rubric: SemanticRubric,
    pub attempts: Vec<SemanticTaskAttempt>,
    pub judgments: Vec<SemanticJudgment>,
    pub adjudications: Vec<JudgmentAdjudication>,
}

/// Validates model invariants plus the phase exit-signal properties: at least
/// two directly comparable judgments and one first-class abstain.
pub fn validate_semantic_task_gold_fixture(
    fixture: &SemanticTaskGoldFixture,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    if fixture.fixture_version != 1 {
        errors.push("fixture_version must be 1".into());
    }
    if fixture.evidence_class != "gold" {
        errors.push("fixture evidence_class must be gold".into());
    }
    if let Err(mut rubric_errors) = validate_semantic_rubric(&fixture.rubric) {
        errors.append(&mut rubric_errors);
    }
    for attempt in &fixture.attempts {
        if let Err(mut attempt_errors) = validate_semantic_attempt(attempt, &fixture.rubric) {
            errors.append(&mut attempt_errors);
        }
    }
    for judgment in &fixture.judgments {
        match fixture
            .attempts
            .iter()
            .find(|attempt| attempt.id == judgment.attempt_id)
        {
            Some(attempt) => {
                if let Err(mut judgment_errors) =
                    validate_semantic_judgment(judgment, &fixture.rubric, attempt)
                {
                    errors.append(&mut judgment_errors);
                }
            }
            None => errors.push("judgment references an unknown attempt".into()),
        }
    }
    for adjudication in &fixture.adjudications {
        match fixture
            .judgments
            .iter()
            .find(|judgment| judgment.id == adjudication.judgment_id)
        {
            Some(judgment) => {
                if let Err(mut adjudication_errors) =
                    validate_judgment_adjudication(adjudication, judgment)
                {
                    errors.append(&mut adjudication_errors);
                }
            }
            None => errors.push("adjudication references an unknown judgment".into()),
        }
    }
    let comparable_pair = fixture.judgments.iter().enumerate().any(|(index, a)| {
        fixture.judgments[index + 1..]
            .iter()
            .any(|b| judgments_directly_comparable(a, b))
    });
    if !comparable_pair {
        errors.push("fixture must contain two directly comparable judgments".into());
    }
    if !fixture
        .judgments
        .iter()
        .any(|judgment| judgment.abstain.is_some())
    {
        errors.push("fixture must contain a first-class abstain judgment".into());
    }
    if fixture.adjudications.is_empty() {
        errors.push("fixture must contain at least one adjudication".into());
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> SemanticTaskGoldFixture {
        serde_json::from_str(include_str!(
            "../../../testdata/semantic-task/gold-fixture-v1.json"
        ))
        .expect("gold fixture parses")
    }

    #[test]
    fn gold_fixture_is_valid_offline() {
        let fixture = fixture();
        validate_semantic_task_gold_fixture(&fixture).expect("gold fixture validates");
    }

    #[test]
    fn same_rubric_judgments_compare_and_abstain_never_does() {
        let fixture = fixture();
        let scored: Vec<_> = fixture
            .judgments
            .iter()
            .filter(|judgment| judgment.abstain.is_none())
            .collect();
        let abstained: Vec<_> = fixture
            .judgments
            .iter()
            .filter(|judgment| judgment.abstain.is_some())
            .collect();
        assert!(scored.len() >= 2);
        assert!(judgments_directly_comparable(scored[0], scored[1]));
        assert!(!judgments_directly_comparable(scored[0], abstained[0]));
    }

    #[test]
    fn adjudication_leaves_the_original_judgment_untouched() {
        let fixture = fixture();
        let adjudication = &fixture.adjudications[0];
        let judgment = fixture
            .judgments
            .iter()
            .find(|judgment| judgment.id == adjudication.judgment_id)
            .unwrap();
        let point = judgment
            .points
            .iter()
            .find(|point| point.point_id == adjudication.point_id)
            .unwrap();
        // The judgment still records the prior verdict; the correction lives
        // only in the adjudication row.
        assert_eq!(point.verdict, adjudication.prior_verdict);
        assert_ne!(adjudication.user_verdict, adjudication.prior_verdict);
        validate_judgment_adjudication(adjudication, judgment).unwrap();
    }

    #[test]
    fn spans_must_stay_inside_the_response_transcript() {
        let fixture = fixture();
        let mut judgment = fixture.judgments[0].clone();
        let attempt = fixture
            .attempts
            .iter()
            .find(|attempt| attempt.id == judgment.attempt_id)
            .unwrap();
        judgment.points[0].supporting_spans[0].end_char = 10_000;
        let errors = validate_semantic_judgment(&judgment, &fixture.rubric, attempt).unwrap_err();
        assert!(errors.iter().any(|error| error.contains("outside")));

        let mut inverted = fixture.judgments[0].clone();
        inverted.points[0].supporting_spans[0] = ResponseSpan {
            start_char: 5,
            end_char: 5,
        };
        assert!(validate_semantic_judgment(&inverted, &fixture.rubric, attempt).is_err());
    }

    #[test]
    fn verdict_span_contract_is_enforced() {
        let fixture = fixture();
        let attempt = fixture
            .attempts
            .iter()
            .find(|attempt| attempt.id == fixture.judgments[0].attempt_id)
            .unwrap();

        let mut missing_with_span = fixture.judgments[0].clone();
        let span = missing_with_span.points[0].supporting_spans[0];
        missing_with_span
            .points
            .iter_mut()
            .find(|point| point.verdict == PointVerdict::Missing)
            .unwrap()
            .supporting_spans
            .push(span);
        assert!(validate_semantic_judgment(&missing_with_span, &fixture.rubric, attempt).is_err());

        let mut covered_without_span = fixture.judgments[0].clone();
        covered_without_span.points[0].supporting_spans.clear();
        assert!(
            validate_semantic_judgment(&covered_without_span, &fixture.rubric, attempt).is_err()
        );
    }

    #[test]
    fn judgment_must_cite_matching_rubric_version_and_snapshots() {
        let fixture = fixture();
        let attempt = fixture
            .attempts
            .iter()
            .find(|attempt| attempt.id == fixture.judgments[0].attempt_id)
            .unwrap();

        let mut wrong_version = fixture.judgments[0].clone();
        wrong_version.rubric_version = 2;
        assert!(validate_semantic_judgment(&wrong_version, &fixture.rubric, attempt).is_err());

        let mut wrong_source = fixture.judgments[0].clone();
        wrong_source.rubric_source_sha256 = transcript_sha256("tampered");
        assert!(validate_semantic_judgment(&wrong_source, &fixture.rubric, attempt).is_err());

        let mut wrong_response = fixture.judgments[0].clone();
        wrong_response.response_transcript_sha256 = transcript_sha256("tampered");
        assert!(validate_semantic_judgment(&wrong_response, &fixture.rubric, attempt).is_err());

        let mut incomplete = fixture.judgments[0].clone();
        incomplete.points.pop();
        assert!(validate_semantic_judgment(&incomplete, &fixture.rubric, attempt).is_err());

        let mut abstain_with_points = fixture.judgments[0].clone();
        abstain_with_points.abstain = Some(JudgmentAbstain {
            reason: AbstainReason::Other,
            note: None,
        });
        assert!(
            validate_semantic_judgment(&abstain_with_points, &fixture.rubric, attempt).is_err()
        );
    }

    #[test]
    fn rubric_point_identity_and_versioning_are_enforced() {
        let fixture = fixture();

        let mut duplicated = fixture.rubric.clone();
        duplicated.points.push(duplicated.points[0].clone());
        assert!(validate_semantic_rubric(&duplicated).is_err());

        let mut unrevised_v2 = fixture.rubric.clone();
        unrevised_v2.version = 2;
        assert!(validate_semantic_rubric(&unrevised_v2).is_err());

        let mut revised_v1 = fixture.rubric.clone();
        revised_v1.revision = Some(RubricRevisionNote {
            revised_from_version: 1,
            note: "edit".into(),
            revised_at_ms: 1,
        });
        assert!(validate_semantic_rubric(&revised_v1).is_err());

        let mut no_required = fixture.rubric.clone();
        for point in &mut no_required.points {
            point.importance = RubricPointImportance::Optional;
        }
        assert!(validate_semantic_rubric(&no_required).is_err());
    }

    #[test]
    fn attempt_conditions_follow_the_evidence_matrix() {
        let fixture = fixture();
        let attempt = fixture.attempts[0].clone();

        let mut visible_source = attempt.clone();
        visible_source.conditions.source_text_visible = true;
        assert!(validate_semantic_attempt(&visible_source, &fixture.rubric).is_err());

        let mut missing_trigger = attempt.clone();
        missing_trigger.conditions.l1_trigger = None;
        assert!(validate_semantic_attempt(&missing_trigger, &fixture.rubric).is_err());

        let mut extra_revision = attempt.clone();
        let mut second = extra_revision.responses[0].clone();
        second.revision = 2;
        extra_revision.responses.push(second);
        assert!(validate_semantic_attempt(&extra_revision, &fixture.rubric).is_err());

        let mut asr_without_reliability = attempt.clone();
        asr_without_reliability.responses[0].source = ResponseTranscriptSource::Asr;
        asr_without_reliability.responses[0].asr_reliability = None;
        assert!(validate_semantic_attempt(&asr_without_reliability, &fixture.rubric).is_err());
    }

    #[test]
    fn adjudication_target_must_exist_and_match() {
        let fixture = fixture();
        let adjudication = fixture.adjudications[0].clone();
        let judgment = fixture
            .judgments
            .iter()
            .find(|judgment| judgment.id == adjudication.judgment_id)
            .unwrap();

        let mut unknown_point = adjudication.clone();
        unknown_point.point_id = "p99".into();
        assert!(validate_judgment_adjudication(&unknown_point, judgment).is_err());

        let mut wrong_prior = adjudication.clone();
        wrong_prior.prior_verdict = PointVerdict::Uncertain;
        assert!(validate_judgment_adjudication(&wrong_prior, judgment).is_err());

        let abstained = fixture
            .judgments
            .iter()
            .find(|judgment| judgment.abstain.is_some())
            .unwrap();
        let mut on_abstain = adjudication.clone();
        on_abstain.judgment_id = abstained.id.clone();
        assert!(validate_judgment_adjudication(&on_abstain, abstained).is_err());
    }

    #[test]
    fn serialized_contract_uses_named_snake_case_values() {
        assert_eq!(
            serde_json::to_string(&SemanticTaskKind::L1Retelling).unwrap(),
            "\"l1_retelling\""
        );
        assert_eq!(
            serde_json::to_string(&SemanticTaskKind::PatternProduction).unwrap(),
            "\"pattern_production\""
        );
        assert_eq!(
            serde_json::to_string(&PointVerdict::Uncertain).unwrap(),
            "\"uncertain\""
        );
        assert_eq!(
            serde_json::to_string(&AbstainReason::UnreliableTranscript).unwrap(),
            "\"unreliable_transcript\""
        );
        assert_eq!(
            serde_json::to_string(&L1RetellingTrigger::L2Failed).unwrap(),
            "\"l2_failed\""
        );
    }

    #[test]
    fn fingerprint_ids_are_stable_and_distinct() {
        let attempt_id = SemanticTaskAttemptId::parse("attempt-a").unwrap();
        let a = semantic_judgment_id(&attempt_id, 1, 1, SemanticGeneratorKind::Fixture, 100);
        let b = semantic_judgment_id(&attempt_id, 2, 1, SemanticGeneratorKind::Fixture, 100);
        let c = semantic_judgment_id(&attempt_id, 1, 1, SemanticGeneratorKind::Fixture, 100);
        assert_ne!(a, b);
        assert_eq!(a, c);

        let media = MediaId::parse("media-1").unwrap();
        let en = LanguageCode::parse("en").unwrap();
        let zh = LanguageCode::parse("zh").unwrap();
        let retelling = semantic_rubric_id(
            Some(&media),
            0,
            1000,
            SemanticTaskKind::L1Retelling,
            &en,
            &zh,
            "text",
        );
        let summary = semantic_rubric_id(
            Some(&media),
            0,
            1000,
            SemanticTaskKind::Summary,
            &en,
            &zh,
            "text",
        );
        // Same segment, different purpose: different rubric identity (§2.6).
        assert_ne!(retelling, summary);
    }
}
