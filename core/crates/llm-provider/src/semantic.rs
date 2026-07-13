//! The one place semantic behavior lives.
//!
//! [`LlmSemanticProvider`] wraps *any* [`LlmChatAdapter`] and implements both
//! application seams. Because the prompt, the output schema, and the parsing
//! are written exactly once here — independent of protocol — swapping the
//! adapter cannot change what a rubric or judgment means. That invariant is
//! the Phase 3.12 neutrality proof.
//!
//! Providers return **drafts** only. Identity, versioning, snapshot hashing,
//! and the Phase 3.11 validators stay in the server-side use case, so this
//! vendor layer can never become a second identity or evidence writer.

use application::{
    JudgeRequest, JudgmentDraft, LlmChatAdapter, LlmProviderDescriptor, RubricDraft,
    RubricGenerationRequest, RubricPointDraft, SemanticJudgeProvider, SemanticRubricProvider,
    StructuredChatRequest,
};
use async_trait::async_trait;
use domain::{
    JudgmentAbstain, LlmProviderError, PointJudgment, RubricPoint, RubricPointImportance,
    SemanticTaskKind,
};
use serde::Deserialize;

const RUBRIC_PROMPT_VERSION: &str = "rubric-gen/v1";
const JUDGE_PROMPT_VERSION: &str = "judge/v1";
const SCHEMA_VERSION: &str = "semantic/v1";
const MAX_OUTPUT_TOKENS: u32 = 2048;

/// Turns a protocol adapter into semantic rubric/judge providers.
pub struct LlmSemanticProvider<A: LlmChatAdapter> {
    adapter: A,
}

impl<A: LlmChatAdapter> LlmSemanticProvider<A> {
    pub fn new(adapter: A) -> Self {
        Self { adapter }
    }

    pub fn adapter(&self) -> &A {
        &self.adapter
    }
}

fn purpose_label(kind: SemanticTaskKind) -> &'static str {
    match kind {
        SemanticTaskKind::ReadingComprehension => "reading comprehension",
        SemanticTaskKind::L1Retelling => "L1 (native-language) retelling",
        SemanticTaskKind::L2Retelling => "L2 (target-language) retelling",
        SemanticTaskKind::RoleReply => "role reply",
        SemanticTaskKind::Dictogloss => "dictogloss reconstruction",
        SemanticTaskKind::Summary => "summary",
        SemanticTaskKind::PatternProduction => "sentence-pattern production",
    }
}

// ---------------------------------------------------------------------------
// Rubric generation
// ---------------------------------------------------------------------------

fn rubric_schema() -> serde_json::Value {
    serde_json::json!({
        "type": "object",
        "additionalProperties": false,
        "properties": {
            "points": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "properties": {
                        "importance": { "type": "string", "enum": ["required", "optional"] },
                        "statement": { "type": "string" },
                        "accepted_paraphrase_notes": { "type": ["string", "null"] }
                    },
                    "required": ["importance", "statement", "accepted_paraphrase_notes"]
                }
            }
        },
        "required": ["points"]
    })
}

#[derive(Debug, Deserialize)]
struct RubricOutput {
    points: Vec<RubricPointOutput>,
}

#[derive(Debug, Deserialize)]
struct RubricPointOutput {
    importance: RubricPointImportance,
    statement: String,
    #[serde(default)]
    accepted_paraphrase_notes: Option<String>,
}

fn rubric_request(req: &RubricGenerationRequest) -> StructuredChatRequest {
    let system = format!(
        "You extract a fixed scoring rubric of information points for a {} task. \
         The source is in {} and the learner will respond in {}. \
         List the atomic information points a faithful response must convey. \
         Mark each point required or optional. Do not evaluate any response. \
         Return only JSON matching the schema.",
        purpose_label(req.purpose),
        req.source_language.as_str(),
        req.response_language.as_str(),
    );
    StructuredChatRequest {
        system,
        user: format!("Source segment transcript:\n{}", req.transcript_snapshot),
        json_schema: rubric_schema(),
        schema_name: "semantic_rubric".into(),
        max_output_tokens: MAX_OUTPUT_TOKENS,
        temperature: Some(0.0),
    }
}

#[async_trait]
impl<A: LlmChatAdapter> SemanticRubricProvider for LlmSemanticProvider<A> {
    fn descriptor(&self) -> LlmProviderDescriptor {
        self.adapter.descriptor()
    }

    async fn generate_rubric(
        &self,
        request: &RubricGenerationRequest,
    ) -> Result<RubricDraft, LlmProviderError> {
        let response = self
            .adapter
            .complete_structured(&rubric_request(request))
            .await?;
        let raw_output: serde_json::Value =
            serde_json::from_str(&response.json_text).map_err(|error| {
                LlmProviderError::SchemaInvalid {
                    detail: format!("output was not valid JSON: {error}"),
                }
            })?;
        let parsed: RubricOutput = serde_json::from_value(raw_output.clone()).map_err(|error| {
            LlmProviderError::SchemaInvalid {
                detail: format!("output did not match rubric schema: {error}"),
            }
        })?;
        Ok(RubricDraft {
            points: parsed
                .points
                .into_iter()
                .map(|point| RubricPointDraft {
                    importance: point.importance,
                    statement: point.statement,
                    accepted_paraphrase_notes: point.accepted_paraphrase_notes,
                })
                .collect(),
            model_id: response.model_id,
            prompt_version: Some(RUBRIC_PROMPT_VERSION.into()),
            schema_version: Some(SCHEMA_VERSION.into()),
            raw_output,
        })
    }
}

// ---------------------------------------------------------------------------
// Judgment
// ---------------------------------------------------------------------------

fn judgment_schema() -> serde_json::Value {
    serde_json::json!({
        "type": "object",
        "additionalProperties": false,
        "properties": {
            "abstain": {
                "type": ["object", "null"],
                "additionalProperties": false,
                "properties": {
                    "reason": {
                        "type": "string",
                        "enum": [
                            "unreliable_transcript",
                            "empty_response",
                            "generator_refused",
                            "other"
                        ]
                    },
                    "note": { "type": ["string", "null"] }
                },
                "required": ["reason", "note"]
            },
            "points": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "properties": {
                        "point_id": { "type": "string" },
                        "verdict": {
                            "type": "string",
                            "enum": ["covered", "partial", "missing", "uncertain"]
                        },
                        "supporting_spans": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "additionalProperties": false,
                                "properties": {
                                    "start_char": { "type": "integer", "minimum": 0 },
                                    "end_char": { "type": "integer", "minimum": 0 }
                                },
                                "required": ["start_char", "end_char"]
                            }
                        }
                    },
                    "required": ["point_id", "verdict", "supporting_spans"]
                }
            }
        },
        "required": ["abstain", "points"]
    })
}

#[derive(Debug, Deserialize)]
struct JudgmentOutput {
    #[serde(default)]
    abstain: Option<JudgmentAbstain>,
    #[serde(default)]
    points: Vec<PointJudgment>,
}

fn point_lines(points: &[RubricPoint]) -> String {
    points
        .iter()
        .map(|point| {
            format!(
                "- {} [{}]: {}",
                point.point_id,
                match point.importance {
                    RubricPointImportance::Required => "required",
                    RubricPointImportance::Optional => "optional",
                },
                point.statement,
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn judge_request(req: &JudgeRequest) -> StructuredChatRequest {
    let asr_note = match req.asr_reliability {
        Some(domain::AsrReliability::Unreliable) => {
            " The response transcript is flagged UNRELIABLE; if you cannot judge \
             faithfully, abstain with reason unreliable_transcript."
        }
        Some(domain::AsrReliability::Suspect) => {
            " The response transcript may contain ASR errors; weigh spans cautiously."
        }
        _ => "",
    };
    let system = format!(
        "You judge one learner response against a FIXED rubric. For every rubric \
         point return covered, partial, missing, or uncertain, with response \
         character spans [start_char, end_char) that support your verdict. Cite \
         only spans that exist in the response text. Do not invent points. If the \
         response is empty or the transcript is unusable, abstain instead of \
         guessing.{asr_note} Return only JSON matching the schema."
    );
    let user = format!(
        "Rubric ({} -> {}), points:\n{}\n\nLearner response ({}):\n{}",
        req.rubric.source.language.as_str(),
        req.rubric.response_language.as_str(),
        point_lines(&req.rubric.points),
        req.response_language.as_str(),
        req.response_transcript,
    );
    StructuredChatRequest {
        system,
        user,
        json_schema: judgment_schema(),
        schema_name: "semantic_judgment".into(),
        max_output_tokens: MAX_OUTPUT_TOKENS,
        temperature: Some(0.0),
    }
}

#[async_trait]
impl<A: LlmChatAdapter> SemanticJudgeProvider for LlmSemanticProvider<A> {
    fn descriptor(&self) -> LlmProviderDescriptor {
        self.adapter.descriptor()
    }

    async fn judge(&self, request: &JudgeRequest) -> Result<JudgmentDraft, LlmProviderError> {
        let response = self.adapter.complete_structured(&judge_request(request)).await?;
        let raw_output: serde_json::Value =
            serde_json::from_str(&response.json_text).map_err(|error| {
                LlmProviderError::SchemaInvalid {
                    detail: format!("output was not valid JSON: {error}"),
                }
            })?;
        let parsed: JudgmentOutput = serde_json::from_value(raw_output.clone()).map_err(|error| {
            LlmProviderError::SchemaInvalid {
                detail: format!("output did not match judgment schema: {error}"),
            }
        })?;
        // Structural sanity the use case also enforces, surfaced early as a
        // schema error: abstain and per-point verdicts are mutually exclusive.
        if parsed.abstain.is_some() && !parsed.points.is_empty() {
            return Err(LlmProviderError::SchemaInvalid {
                detail: "judgment cannot both abstain and return points".into(),
            });
        }
        Ok(JudgmentDraft {
            points: parsed.points,
            abstain: parsed.abstain,
            model_id: response.model_id,
            prompt_version: Some(JUDGE_PROMPT_VERSION.into()),
            schema_version: Some(SCHEMA_VERSION.into()),
            raw_output,
        })
    }
}
