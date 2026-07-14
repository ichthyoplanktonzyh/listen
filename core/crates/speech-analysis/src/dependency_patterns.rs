//! Provider-neutral dependency-pattern candidate matching.
//!
//! Matches are rebuildable occurrence *candidates*. This module deliberately
//! has no `ConstructionId`, canonical key, capability, persistence, or user-
//! asset API; a later curated layer may review/link a candidate.

use std::collections::{BTreeMap, HashMap, HashSet};

use domain::{
    SubtitleSentenceId, SyntacticAnalysis, SyntacticAnalysisId, SyntacticToken,
    SyntacticValidationReport,
};
use serde::{Deserialize, Serialize};

use crate::connected_speech_rules::SyntacticProviderQualification;

pub const MATCHER_VERSION: &str = "dependency-pattern-candidate-v1";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DependencyNodeConstraint {
    pub binding: String,
    pub lemma: Option<String>,
    pub upos: Option<String>,
    pub dependency_relation: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DependencyEdgeConstraint {
    pub head_binding: String,
    pub dependent_binding: String,
    pub dependency_relation: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DependencyPatternSpec {
    /// Matcher-local diagnostic key, never a canonical Construction key/ID.
    pub matcher_key: String,
    pub nodes: Vec<DependencyNodeConstraint>,
    #[serde(default)]
    pub edges: Vec<DependencyEdgeConstraint>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleTokenSpanCandidate {
    /// Inclusive SubtitleToken index.
    pub start_token_index: u32,
    /// Exclusive SubtitleToken index.
    pub end_token_index: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DependencyMatchCandidate {
    pub matcher_version: String,
    pub matcher_key: String,
    pub syntactic_analysis_id: SyntacticAnalysisId,
    pub sentence_id: SubtitleSentenceId,
    pub token_span: SubtitleTokenSpanCandidate,
    pub bindings: BTreeMap<String, Vec<u32>>,
    pub evidence_class: String,
}

pub fn match_dependency_patterns(
    analysis: &SyntacticAnalysis,
    validation: &SyntacticValidationReport,
    qualification: SyntacticProviderQualification,
    patterns: &[DependencyPatternSpec],
) -> Vec<DependencyMatchCandidate> {
    if qualification != SyntacticProviderQualification::Qualified || !validation.is_activatable() {
        return Vec::new();
    }
    let mut candidates = Vec::new();
    for sentence in &analysis.sentences {
        for pattern in patterns {
            if !valid_pattern(pattern) {
                continue;
            }
            let mut assignments = Vec::new();
            assign_nodes(
                pattern,
                &sentence.tokens,
                0,
                &mut HashMap::new(),
                &mut HashSet::new(),
                &mut assignments,
            );
            for assignment in assignments {
                if !edges_match(pattern, &sentence.tokens, &assignment) {
                    continue;
                }
                let bindings = assignment
                    .iter()
                    .map(|(binding, parser_index)| {
                        (
                            binding.clone(),
                            sentence.tokens[*parser_index as usize]
                                .subtitle_token_indices
                                .clone(),
                        )
                    })
                    .collect::<BTreeMap<_, _>>();
                let mapped = bindings
                    .values()
                    .flat_map(|indices| indices.iter().copied())
                    .collect::<Vec<_>>();
                let (Some(start), Some(end)) = (mapped.iter().min(), mapped.iter().max()) else {
                    continue;
                };
                candidates.push(DependencyMatchCandidate {
                    matcher_version: MATCHER_VERSION.into(),
                    matcher_key: pattern.matcher_key.clone(),
                    syntactic_analysis_id: analysis.id.clone(),
                    sentence_id: sentence.sentence_id.clone(),
                    token_span: SubtitleTokenSpanCandidate {
                        start_token_index: *start,
                        end_token_index: end.saturating_add(1),
                    },
                    bindings,
                    evidence_class: "dependency_pattern_candidate".into(),
                });
            }
        }
    }
    candidates.sort_by(|left, right| {
        (
            left.sentence_id.as_str(),
            left.token_span.start_token_index,
            left.token_span.end_token_index,
            left.matcher_key.as_str(),
        )
            .cmp(&(
                right.sentence_id.as_str(),
                right.token_span.start_token_index,
                right.token_span.end_token_index,
                right.matcher_key.as_str(),
            ))
    });
    candidates
}

fn valid_pattern(pattern: &DependencyPatternSpec) -> bool {
    if pattern.matcher_key.trim().is_empty() || pattern.nodes.is_empty() {
        return false;
    }
    let bindings = pattern
        .nodes
        .iter()
        .map(|node| node.binding.as_str())
        .collect::<HashSet<_>>();
    bindings.len() == pattern.nodes.len()
        && !bindings.contains("")
        && pattern.edges.iter().all(|edge| {
            bindings.contains(edge.head_binding.as_str())
                && bindings.contains(edge.dependent_binding.as_str())
                && edge.head_binding != edge.dependent_binding
        })
}

fn assign_nodes(
    pattern: &DependencyPatternSpec,
    tokens: &[SyntacticToken],
    node_index: usize,
    current: &mut HashMap<String, u32>,
    used: &mut HashSet<u32>,
    assignments: &mut Vec<HashMap<String, u32>>,
) {
    let Some(node) = pattern.nodes.get(node_index) else {
        assignments.push(current.clone());
        return;
    };
    for token in tokens.iter().filter(|token| node_matches(node, token)) {
        if !used.insert(token.parser_token_index) {
            continue;
        }
        current.insert(node.binding.clone(), token.parser_token_index);
        assign_nodes(pattern, tokens, node_index + 1, current, used, assignments);
        current.remove(&node.binding);
        used.remove(&token.parser_token_index);
    }
}

fn node_matches(constraint: &DependencyNodeConstraint, token: &SyntacticToken) -> bool {
    constraint
        .lemma
        .as_ref()
        .is_none_or(|lemma| token.lemma.eq_ignore_ascii_case(lemma))
        && constraint
            .upos
            .as_ref()
            .is_none_or(|upos| token.upos == *upos)
        && constraint
            .dependency_relation
            .as_ref()
            .is_none_or(|relation| token.dependency_relation == *relation)
        && !token.subtitle_token_indices.is_empty()
}

fn edges_match(
    pattern: &DependencyPatternSpec,
    tokens: &[SyntacticToken],
    assignment: &HashMap<String, u32>,
) -> bool {
    pattern.edges.iter().all(|edge| {
        let Some(&head) = assignment.get(&edge.head_binding) else {
            return false;
        };
        let Some(&dependent) = assignment.get(&edge.dependent_binding) else {
            return false;
        };
        let token = &tokens[dependent as usize];
        token.head_parser_token_index == Some(head)
            && edge
                .dependency_relation
                .as_ref()
                .is_none_or(|relation| token.dependency_relation == *relation)
    })
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use domain::{
        LanguageCode, SYNTACTIC_CONTRACT_VERSION, SubtitleSentenceId, SyntacticAlignmentStatus,
        SyntacticProviderDescriptor, SyntacticSentenceAnalysis, SyntacticValidationStatus,
    };

    use super::*;

    fn token(
        index: u32,
        surface: &str,
        lemma: &str,
        upos: &str,
        head: Option<u32>,
        relation: &str,
        subtitle_index: u32,
    ) -> SyntacticToken {
        SyntacticToken {
            parser_token_index: index,
            surface: surface.into(),
            lemma: lemma.into(),
            upos: upos.into(),
            xpos: None,
            features: BTreeMap::new(),
            head_parser_token_index: head,
            dependency_relation: relation.into(),
            start_char: subtitle_index,
            end_char: subtitle_index + 1,
            subtitle_token_indices: vec![subtitle_index],
            alignment_status: SyntacticAlignmentStatus::Exact,
            confidence: None,
        }
    }

    fn analysis() -> SyntacticAnalysis {
        SyntacticAnalysis {
            id: SyntacticAnalysisId::parse("shared-syntax-artifact").unwrap(),
            contract_version: SYNTACTIC_CONTRACT_VERSION,
            descriptor: SyntacticProviderDescriptor {
                provider_id: "qualified-neutral-fixture".into(),
                provider_version: "1".into(),
                runtime_id: "fixture".into(),
                runtime_version: "1".into(),
                model_id: "fixture".into(),
                model_version: "1".into(),
                model_checksum_sha256: "a".repeat(64),
            },
            language: LanguageCode::parse("en").unwrap(),
            source_fingerprint: "source".into(),
            profile_fingerprint: "profile".into(),
            sentences: vec![SyntacticSentenceAnalysis {
                sentence_id: SubtitleSentenceId::parse("sentence-1").unwrap(),
                source_text: "They have to leave".into(),
                source_char_count: 18,
                tokens: vec![
                    token(0, "They", "they", "PRON", Some(3), "nsubj", 0),
                    token(1, "have", "have", "AUX", Some(3), "aux", 2),
                    token(2, "to", "to", "PART", Some(3), "mark", 4),
                    token(3, "leave", "leave", "VERB", None, "root", 6),
                ],
                unaligned_subtitle_token_indices: Vec::new(),
                lexical_alignment_coverage: 1.0,
            }],
        }
    }

    fn report() -> SyntacticValidationReport {
        SyntacticValidationReport {
            status: SyntacticValidationStatus::Valid,
            lexical_alignment_coverage: 1.0,
            punctuation_alignment_coverage: 1.0,
            issues: Vec::new(),
        }
    }

    fn have_to_pattern() -> DependencyPatternSpec {
        DependencyPatternSpec {
            matcher_key: "have-to-infinitive-candidate".into(),
            nodes: vec![
                DependencyNodeConstraint {
                    binding: "predicate".into(),
                    lemma: None,
                    upos: Some("VERB".into()),
                    dependency_relation: None,
                },
                DependencyNodeConstraint {
                    binding: "have".into(),
                    lemma: Some("have".into()),
                    upos: None,
                    dependency_relation: None,
                },
                DependencyNodeConstraint {
                    binding: "to".into(),
                    lemma: Some("to".into()),
                    upos: None,
                    dependency_relation: None,
                },
            ],
            edges: vec![
                DependencyEdgeConstraint {
                    head_binding: "predicate".into(),
                    dependent_binding: "have".into(),
                    dependency_relation: Some("aux".into()),
                },
                DependencyEdgeConstraint {
                    head_binding: "predicate".into(),
                    dependent_binding: "to".into(),
                    dependency_relation: Some("mark".into()),
                },
            ],
        }
    }

    #[test]
    fn qualified_artifact_yields_candidate_with_source_identity_and_bindings() {
        let values = match_dependency_patterns(
            &analysis(),
            &report(),
            SyntacticProviderQualification::Qualified,
            &[have_to_pattern()],
        );
        assert_eq!(values.len(), 1);
        assert_eq!(
            values[0].syntactic_analysis_id.as_str(),
            "shared-syntax-artifact"
        );
        assert_eq!(values[0].token_span.start_token_index, 2);
        assert_eq!(values[0].token_span.end_token_index, 7);
        assert_eq!(values[0].bindings["predicate"], vec![6]);
    }

    #[test]
    fn unqualified_artifact_and_wrong_edge_abstain() {
        assert!(
            match_dependency_patterns(
                &analysis(),
                &report(),
                SyntacticProviderQualification::Unqualified,
                &[have_to_pattern()],
            )
            .is_empty()
        );
        let mut wrong = have_to_pattern();
        wrong.edges[0].dependency_relation = Some("cop".into());
        assert!(
            match_dependency_patterns(
                &analysis(),
                &report(),
                SyntacticProviderQualification::Qualified,
                &[wrong],
            )
            .is_empty()
        );
    }

    #[test]
    fn candidate_schema_cannot_mint_construction_or_capability_identity() {
        let value = match_dependency_patterns(
            &analysis(),
            &report(),
            SyntacticProviderQualification::Qualified,
            &[have_to_pattern()],
        )
        .pop()
        .unwrap();
        let json = serde_json::to_value(value).unwrap();
        let object = json.as_object().unwrap();
        for forbidden in [
            "construction_id",
            "construction_occurrence_id",
            "capability",
            "canonical_key",
        ] {
            assert!(!object.contains_key(forbidden));
        }
        assert_eq!(object["evidence_class"], "dependency_pattern_candidate");
    }
}
