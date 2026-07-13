use std::collections::{BTreeMap, HashMap, HashSet};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

use crate::{LanguageCode, SubtitleSentence, SubtitleSentenceId, SubtitleTokenKind};

pub const SYNTACTIC_CONTRACT_VERSION: u32 = 1;
pub const DEFAULT_MIN_LEXICAL_ALIGNMENT_COVERAGE: f32 = 0.995;

#[derive(Debug, Clone, PartialEq, Eq, Error, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum SyntacticProviderError {
    #[error("syntactic runtime is not installed")]
    RuntimeMissing,
    #[error("syntactic model is not installed")]
    ModelMissing,
    #[error("syntactic model is corrupt")]
    ModelCorrupt,
    #[error("language is unsupported: {language}")]
    UnsupportedLanguage { language: String },
    #[error("syntactic provider timed out")]
    Timeout,
    #[error("syntactic sidecar protocol failed: {detail}")]
    Protocol { detail: String },
    #[error("syntactic provider output is invalid: {detail}")]
    InvalidOutput { detail: String },
    #[error("syntactic provider process failed: {detail}")]
    Process { detail: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyntacticProviderDescriptor {
    pub provider_id: String,
    pub provider_version: String,
    pub runtime_id: String,
    pub runtime_version: String,
    pub model_id: String,
    pub model_version: String,
    pub model_checksum_sha256: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyntacticAlignmentStatus {
    Exact,
    Split,
    Merged,
    NormalizedOverlap,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SyntacticToken {
    pub parser_token_index: u32,
    pub surface: String,
    pub lemma: String,
    pub upos: String,
    pub xpos: Option<String>,
    #[serde(default)]
    pub features: BTreeMap<String, String>,
    pub head_parser_token_index: Option<u32>,
    pub dependency_relation: String,
    pub start_char: u32,
    pub end_char: u32,
    #[serde(default)]
    pub subtitle_token_indices: Vec<u32>,
    pub alignment_status: SyntacticAlignmentStatus,
    pub confidence: Option<f32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SyntacticSentenceAnalysis {
    pub sentence_id: SubtitleSentenceId,
    pub source_text: String,
    pub source_char_count: u32,
    pub tokens: Vec<SyntacticToken>,
    #[serde(default)]
    pub unaligned_subtitle_token_indices: Vec<u32>,
    pub lexical_alignment_coverage: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SyntacticAnalysis {
    pub id: crate::SyntacticAnalysisId,
    pub contract_version: u32,
    pub descriptor: SyntacticProviderDescriptor,
    pub language: LanguageCode,
    pub source_fingerprint: String,
    pub profile_fingerprint: String,
    pub sentences: Vec<SyntacticSentenceAnalysis>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyntacticValidationStatus {
    Valid,
    Partial,
    Invalid,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyntacticValidationIssueKind {
    ContractVersion,
    Provenance,
    SourceFingerprint,
    MissingSentence,
    UnexpectedSentence,
    DuplicateSentence,
    SourceSnapshot,
    ParserTokenIndex,
    SpanOutOfBounds,
    MappingUnknownSubtitleToken,
    MappingWhitespace,
    MappingNonIntersecting,
    MappingIncomplete,
    UnalignedMismatch,
    CoverageMismatch,
    CoverageBelowThreshold,
    InvalidHead,
    SelfHead,
    RootCount,
    InvalidRootRelation,
    Cycle,
    InvalidUpos,
    EmptyDependencyRelation,
    InvalidConfidence,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyntacticValidationIssue {
    pub kind: SyntacticValidationIssueKind,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub parser_token_index: Option<u32>,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SyntacticValidationReport {
    pub status: SyntacticValidationStatus,
    pub lexical_alignment_coverage: f32,
    pub punctuation_alignment_coverage: f32,
    pub issues: Vec<SyntacticValidationIssue>,
}

impl SyntacticValidationReport {
    pub fn is_activatable(&self) -> bool {
        self.status == SyntacticValidationStatus::Valid
            && self.lexical_alignment_coverage >= DEFAULT_MIN_LEXICAL_ALIGNMENT_COVERAGE
    }
}

const VALID_UPOS: &[&str] = &[
    "ADJ", "ADP", "ADV", "AUX", "CCONJ", "DET", "INTJ", "NOUN", "NUM", "PART", "PRON", "PROPN",
    "PUNCT", "SCONJ", "SYM", "VERB", "X",
];

pub fn syntactic_source_fingerprint(
    language: &LanguageCode,
    sentences: &[SubtitleSentence],
) -> String {
    let mut hasher = Sha256::new();
    hash_part(&mut hasher, language.as_str());
    for sentence in sentences {
        hash_part(&mut hasher, sentence.id.as_str());
        hash_part(&mut hasher, &sentence.display_text);
        for token in &sentence.tokens {
            hash_part(&mut hasher, &token.index.to_string());
            hash_part(&mut hasher, &format!("{:?}", token.kind));
            hash_part(&mut hasher, &token.text);
            hash_part(&mut hasher, token.normalized.as_deref().unwrap_or(""));
            hash_part(&mut hasher, &token.start_char.to_string());
            hash_part(&mut hasher, &token.end_char.to_string());
        }
    }
    hex::encode(hasher.finalize())
}

pub fn syntactic_analysis_fingerprint(
    descriptor: &SyntacticProviderDescriptor,
    source_fingerprint: &str,
    profile_fingerprint: &str,
) -> String {
    let mut hasher = Sha256::new();
    hash_part(&mut hasher, &SYNTACTIC_CONTRACT_VERSION.to_string());
    hash_part(&mut hasher, source_fingerprint);
    hash_part(&mut hasher, profile_fingerprint);
    hash_part(&mut hasher, &descriptor.provider_id);
    hash_part(&mut hasher, &descriptor.provider_version);
    hash_part(&mut hasher, &descriptor.runtime_id);
    hash_part(&mut hasher, &descriptor.runtime_version);
    hash_part(&mut hasher, &descriptor.model_id);
    hash_part(&mut hasher, &descriptor.model_version);
    hash_part(&mut hasher, &descriptor.model_checksum_sha256);
    hex::encode(hasher.finalize())
}

fn hash_part(hasher: &mut Sha256, value: &str) {
    hasher.update((value.len() as u64).to_le_bytes());
    hasher.update(value.as_bytes());
}

pub fn validate_syntactic_analysis(
    analysis: &SyntacticAnalysis,
    source_sentences: &[SubtitleSentence],
) -> SyntacticValidationReport {
    let mut issues = Vec::new();
    if analysis.contract_version != SYNTACTIC_CONTRACT_VERSION {
        push_issue(
            &mut issues,
            SyntacticValidationIssueKind::ContractVersion,
            None,
            None,
            "unsupported syntactic contract version",
        );
    }
    validate_descriptor(&analysis.descriptor, &mut issues);
    let expected_fingerprint = syntactic_source_fingerprint(&analysis.language, source_sentences);
    if analysis.source_fingerprint != expected_fingerprint {
        push_issue(
            &mut issues,
            SyntacticValidationIssueKind::SourceFingerprint,
            None,
            None,
            "source fingerprint does not match sentence/token snapshot",
        );
    }

    let source_by_id: HashMap<_, _> = source_sentences
        .iter()
        .map(|sentence| (sentence.id.as_str(), sentence))
        .collect();
    let analysis_by_id: HashMap<_, _> = analysis
        .sentences
        .iter()
        .map(|sentence| (sentence.sentence_id.as_str(), sentence))
        .collect();
    if analysis_by_id.len() != analysis.sentences.len() {
        push_issue(
            &mut issues,
            SyntacticValidationIssueKind::DuplicateSentence,
            None,
            None,
            "provider returned more than one result for a source sentence",
        );
    }
    for source in source_sentences {
        if !analysis_by_id.contains_key(source.id.as_str()) {
            push_issue(
                &mut issues,
                SyntacticValidationIssueKind::MissingSentence,
                Some(source.id.clone()),
                None,
                "source sentence has no syntactic result",
            );
        }
    }
    for sentence in &analysis.sentences {
        let Some(source) = source_by_id.get(sentence.sentence_id.as_str()) else {
            push_issue(
                &mut issues,
                SyntacticValidationIssueKind::UnexpectedSentence,
                Some(sentence.sentence_id.clone()),
                None,
                "analysis sentence is not owned by the source request",
            );
            continue;
        };
        validate_sentence(sentence, source, &mut issues);
    }

    let (lexical_coverage, punctuation_coverage) = aggregate_coverage(analysis, source_sentences);
    if lexical_coverage < DEFAULT_MIN_LEXICAL_ALIGNMENT_COVERAGE {
        push_issue(
            &mut issues,
            SyntacticValidationIssueKind::CoverageBelowThreshold,
            None,
            None,
            format!(
                "lexical alignment coverage {lexical_coverage:.6} is below {:.6}",
                DEFAULT_MIN_LEXICAL_ALIGNMENT_COVERAGE
            ),
        );
    }
    let has_structural_failure = issues.iter().any(|issue| {
        !matches!(
            issue.kind,
            SyntacticValidationIssueKind::CoverageBelowThreshold
                | SyntacticValidationIssueKind::UnalignedMismatch
                | SyntacticValidationIssueKind::CoverageMismatch
        )
    });
    let status = if has_structural_failure {
        SyntacticValidationStatus::Invalid
    } else if issues.is_empty() {
        SyntacticValidationStatus::Valid
    } else {
        SyntacticValidationStatus::Partial
    };
    SyntacticValidationReport {
        status,
        lexical_alignment_coverage: lexical_coverage,
        punctuation_alignment_coverage: punctuation_coverage,
        issues,
    }
}

fn validate_descriptor(
    descriptor: &SyntacticProviderDescriptor,
    issues: &mut Vec<SyntacticValidationIssue>,
) {
    let required = [
        &descriptor.provider_id,
        &descriptor.provider_version,
        &descriptor.runtime_id,
        &descriptor.runtime_version,
        &descriptor.model_id,
        &descriptor.model_version,
        &descriptor.model_checksum_sha256,
    ];
    if required.iter().any(|value| value.trim().is_empty())
        || !is_sha256(&descriptor.model_checksum_sha256)
    {
        push_issue(
            issues,
            SyntacticValidationIssueKind::Provenance,
            None,
            None,
            "provider/runtime/model provenance is incomplete or checksum is invalid",
        );
    }
}

fn is_sha256(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn validate_sentence(
    analysis: &SyntacticSentenceAnalysis,
    source: &SubtitleSentence,
    issues: &mut Vec<SyntacticValidationIssue>,
) {
    let sentence_id = Some(analysis.sentence_id.clone());
    let char_count = source.display_text.chars().count() as u32;
    if analysis.source_text != source.display_text || analysis.source_char_count != char_count {
        push_issue(
            issues,
            SyntacticValidationIssueKind::SourceSnapshot,
            sentence_id.clone(),
            None,
            "source text or Unicode scalar count differs from SubtitleSentence",
        );
    }
    let source_tokens: HashMap<_, _> = source
        .tokens
        .iter()
        .map(|token| (token.index, token))
        .collect();
    let parser_indices: HashSet<_> = analysis
        .tokens
        .iter()
        .map(|token| token.parser_token_index)
        .collect();
    if parser_indices.len() != analysis.tokens.len()
        || analysis
            .tokens
            .iter()
            .enumerate()
            .any(|(position, token)| token.parser_token_index != position as u32)
    {
        push_issue(
            issues,
            SyntacticValidationIssueKind::ParserTokenIndex,
            sentence_id.clone(),
            None,
            "parser token indices must be unique and contiguous from zero",
        );
    }
    let mut mapped_words = HashSet::new();
    for token in &analysis.tokens {
        let parser_index = Some(token.parser_token_index);
        if token.start_char >= token.end_char || token.end_char > char_count {
            push_issue(
                issues,
                SyntacticValidationIssueKind::SpanOutOfBounds,
                sentence_id.clone(),
                parser_index,
                "syntactic token span is empty or out of bounds",
            );
        }
        if !VALID_UPOS.contains(&token.upos.as_str()) {
            push_issue(
                issues,
                SyntacticValidationIssueKind::InvalidUpos,
                sentence_id.clone(),
                parser_index,
                format!("unsupported UPOS {}", token.upos),
            );
        }
        if token.dependency_relation.trim().is_empty() {
            push_issue(
                issues,
                SyntacticValidationIssueKind::EmptyDependencyRelation,
                sentence_id.clone(),
                parser_index,
                "dependency relation must not be empty",
            );
        }
        if token.head_parser_token_index.is_none() && token.dependency_relation != "root"
            || token.head_parser_token_index.is_some() && token.dependency_relation == "root"
        {
            push_issue(
                issues,
                SyntacticValidationIssueKind::InvalidRootRelation,
                sentence_id.clone(),
                parser_index,
                "only the root token may use deprel=root",
            );
        }
        if token
            .confidence
            .is_some_and(|value| !value.is_finite() || !(0.0..=1.0).contains(&value))
        {
            push_issue(
                issues,
                SyntacticValidationIssueKind::InvalidConfidence,
                sentence_id.clone(),
                parser_index,
                "confidence must be absent or finite within [0, 1]",
            );
        }
        let mut declared = token.subtitle_token_indices.clone();
        declared.sort_unstable();
        declared.dedup();
        let mut intersecting = Vec::new();
        for source_token in &source.tokens {
            if source_token.kind != SubtitleTokenKind::Whitespace
                && token.start_char < source_token.end_char
                && source_token.start_char < token.end_char
            {
                intersecting.push(source_token.index);
            }
        }
        if declared != intersecting {
            push_issue(
                issues,
                SyntacticValidationIssueKind::MappingIncomplete,
                sentence_id.clone(),
                parser_index,
                format!("declared mapping {declared:?} differs from span overlap {intersecting:?}"),
            );
        }
        for subtitle_index in &token.subtitle_token_indices {
            let Some(source_token) = source_tokens.get(subtitle_index) else {
                push_issue(
                    issues,
                    SyntacticValidationIssueKind::MappingUnknownSubtitleToken,
                    sentence_id.clone(),
                    parser_index,
                    format!("unknown SubtitleToken index {subtitle_index}"),
                );
                continue;
            };
            if source_token.kind == SubtitleTokenKind::Whitespace {
                push_issue(
                    issues,
                    SyntacticValidationIssueKind::MappingWhitespace,
                    sentence_id.clone(),
                    parser_index,
                    "whitespace tokens are not part of the alignment relation",
                );
            } else if token.start_char >= source_token.end_char
                || source_token.start_char >= token.end_char
            {
                push_issue(
                    issues,
                    SyntacticValidationIssueKind::MappingNonIntersecting,
                    sentence_id.clone(),
                    parser_index,
                    "mapped parser/subtitle spans do not intersect",
                );
            }
            if source_token.kind == SubtitleTokenKind::Word {
                mapped_words.insert(source_token.index);
            }
        }
        if let Some(head) = token.head_parser_token_index {
            if head == token.parser_token_index {
                push_issue(
                    issues,
                    SyntacticValidationIssueKind::SelfHead,
                    sentence_id.clone(),
                    parser_index,
                    "syntactic token cannot head itself",
                );
            } else if !parser_indices.contains(&head) {
                push_issue(
                    issues,
                    SyntacticValidationIssueKind::InvalidHead,
                    sentence_id.clone(),
                    parser_index,
                    format!("head index {head} does not exist in sentence"),
                );
            }
        }
    }
    let root_count = analysis
        .tokens
        .iter()
        .filter(|token| token.head_parser_token_index.is_none())
        .count();
    if !analysis.tokens.is_empty() && root_count != 1 {
        push_issue(
            issues,
            SyntacticValidationIssueKind::RootCount,
            sentence_id.clone(),
            None,
            format!("expected one root, found {root_count}"),
        );
    }
    for token in &analysis.tokens {
        let mut seen = HashSet::new();
        let mut cursor = Some(token.parser_token_index);
        while let Some(index) = cursor {
            if !seen.insert(index) {
                push_issue(
                    issues,
                    SyntacticValidationIssueKind::Cycle,
                    sentence_id.clone(),
                    Some(token.parser_token_index),
                    "dependency heads contain a cycle",
                );
                break;
            }
            cursor = analysis
                .tokens
                .get(index as usize)
                .and_then(|candidate| candidate.head_parser_token_index);
        }
    }
    let mut declared_unaligned = analysis.unaligned_subtitle_token_indices.clone();
    declared_unaligned.sort_unstable();
    declared_unaligned.dedup();
    let actual_unaligned: Vec<_> = source
        .tokens
        .iter()
        .filter(|token| {
            token.kind == SubtitleTokenKind::Word && !mapped_words.contains(&token.index)
        })
        .map(|token| token.index)
        .collect();
    if declared_unaligned != actual_unaligned {
        push_issue(
            issues,
            SyntacticValidationIssueKind::UnalignedMismatch,
            sentence_id.clone(),
            None,
            format!("declared {declared_unaligned:?}, actual {actual_unaligned:?}"),
        );
    }
    let word_count = source
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .count();
    let coverage = if word_count == 0 {
        1.0
    } else {
        mapped_words.len() as f32 / word_count as f32
    };
    if (analysis.lexical_alignment_coverage - coverage).abs() > 0.000_001 {
        push_issue(
            issues,
            SyntacticValidationIssueKind::CoverageMismatch,
            sentence_id,
            None,
            format!(
                "declared coverage {:.6}, actual {coverage:.6}",
                analysis.lexical_alignment_coverage
            ),
        );
    }
}

fn aggregate_coverage(
    analysis: &SyntacticAnalysis,
    source_sentences: &[SubtitleSentence],
) -> (f32, f32) {
    let mut mapped = HashSet::new();
    for sentence in &analysis.sentences {
        for token in &sentence.tokens {
            for subtitle_index in &token.subtitle_token_indices {
                mapped.insert((sentence.sentence_id.as_str(), *subtitle_index));
            }
        }
    }
    let mut word_total = 0usize;
    let mut word_mapped = 0usize;
    let mut punctuation_total = 0usize;
    let mut punctuation_mapped = 0usize;
    for sentence in source_sentences {
        for token in &sentence.tokens {
            match token.kind {
                SubtitleTokenKind::Word => {
                    word_total += 1;
                    word_mapped +=
                        usize::from(mapped.contains(&(sentence.id.as_str(), token.index)));
                }
                SubtitleTokenKind::Punctuation => {
                    punctuation_total += 1;
                    punctuation_mapped +=
                        usize::from(mapped.contains(&(sentence.id.as_str(), token.index)));
                }
                SubtitleTokenKind::Whitespace | SubtitleTokenKind::Other => {}
            }
        }
    }
    (
        ratio(word_mapped, word_total),
        ratio(punctuation_mapped, punctuation_total),
    )
}

fn ratio(numerator: usize, denominator: usize) -> f32 {
    if denominator == 0 {
        1.0
    } else {
        numerator as f32 / denominator as f32
    }
}

fn push_issue(
    issues: &mut Vec<SyntacticValidationIssue>,
    kind: SyntacticValidationIssueKind,
    sentence_id: Option<SubtitleSentenceId>,
    parser_token_index: Option<u32>,
    detail: impl Into<String>,
) {
    issues.push(SyntacticValidationIssue {
        kind,
        sentence_id,
        parser_token_index,
        detail: detail.into(),
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{SubtitleSentenceId, TimeMs};

    fn sentence(text: &str) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse("sentence-1").unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(1000),
            original_text: text.into(),
            display_text: text.into(),
            tokens: subtitle_core_for_test(text),
        }
    }

    fn subtitle_core_for_test(text: &str) -> Vec<crate::SubtitleToken> {
        let mut tokens = Vec::new();
        let chars: Vec<_> = text.chars().collect();
        let mut start = 0usize;
        while start < chars.len() {
            let kind = if chars[start].is_alphanumeric() {
                SubtitleTokenKind::Word
            } else if chars[start].is_whitespace() {
                SubtitleTokenKind::Whitespace
            } else {
                SubtitleTokenKind::Punctuation
            };
            let mut end = start + 1;
            while end < chars.len()
                && match kind {
                    SubtitleTokenKind::Word => chars[end].is_alphanumeric(),
                    SubtitleTokenKind::Whitespace => chars[end].is_whitespace(),
                    SubtitleTokenKind::Punctuation => {
                        !chars[end].is_alphanumeric() && !chars[end].is_whitespace()
                    }
                    SubtitleTokenKind::Other => false,
                }
            {
                end += 1;
            }
            let value: String = chars[start..end].iter().collect();
            tokens.push(crate::SubtitleToken {
                index: tokens.len() as u32,
                kind,
                text: value.clone(),
                normalized: (kind == SubtitleTokenKind::Word).then(|| value.to_lowercase()),
                start_char: start as u32,
                end_char: end as u32,
            });
            start = end;
        }
        tokens
    }

    fn descriptor() -> SyntacticProviderDescriptor {
        SyntacticProviderDescriptor {
            provider_id: "fixture".into(),
            provider_version: "v1".into(),
            runtime_id: "fixture-runtime".into(),
            runtime_version: "v1".into(),
            model_id: "fixture-model".into(),
            model_version: "v1".into(),
            model_checksum_sha256: "a".repeat(64),
        }
    }

    fn valid_analysis(source: &SubtitleSentence) -> SyntacticAnalysis {
        let language = LanguageCode::parse("en").unwrap();
        let syntactic_tokens = vec![
            SyntacticToken {
                parser_token_index: 0,
                surface: "Cats".into(),
                lemma: "cat".into(),
                upos: "NOUN".into(),
                xpos: Some("NNS".into()),
                features: BTreeMap::new(),
                head_parser_token_index: Some(1),
                dependency_relation: "nsubj".into(),
                start_char: 0,
                end_char: 4,
                subtitle_token_indices: vec![0],
                alignment_status: SyntacticAlignmentStatus::Exact,
                confidence: None,
            },
            SyntacticToken {
                parser_token_index: 1,
                surface: "run".into(),
                lemma: "run".into(),
                upos: "VERB".into(),
                xpos: Some("VBP".into()),
                features: BTreeMap::new(),
                head_parser_token_index: None,
                dependency_relation: "root".into(),
                start_char: 5,
                end_char: 8,
                subtitle_token_indices: vec![2],
                alignment_status: SyntacticAlignmentStatus::Exact,
                confidence: None,
            },
            SyntacticToken {
                parser_token_index: 2,
                surface: ".".into(),
                lemma: ".".into(),
                upos: "PUNCT".into(),
                xpos: Some(".".into()),
                features: BTreeMap::new(),
                head_parser_token_index: Some(1),
                dependency_relation: "punct".into(),
                start_char: 8,
                end_char: 9,
                subtitle_token_indices: vec![3],
                alignment_status: SyntacticAlignmentStatus::Exact,
                confidence: None,
            },
        ];
        let source_fingerprint =
            syntactic_source_fingerprint(&language, std::slice::from_ref(source));
        let descriptor = descriptor();
        let profile_fingerprint = "profile-v1".to_owned();
        let fingerprint =
            syntactic_analysis_fingerprint(&descriptor, &source_fingerprint, &profile_fingerprint);
        SyntacticAnalysis {
            id: crate::SyntacticAnalysisId::from_fingerprint("syntactic-analysis", &fingerprint),
            contract_version: SYNTACTIC_CONTRACT_VERSION,
            descriptor,
            language,
            source_fingerprint,
            profile_fingerprint,
            sentences: vec![SyntacticSentenceAnalysis {
                sentence_id: source.id.clone(),
                source_text: source.display_text.clone(),
                source_char_count: source.display_text.chars().count() as u32,
                tokens: syntactic_tokens,
                unaligned_subtitle_token_indices: vec![],
                lexical_alignment_coverage: 1.0,
            }],
        }
    }

    #[test]
    fn valid_tree_and_alignment_are_activatable() {
        let source = sentence("Cats run.");
        let report = validate_syntactic_analysis(&valid_analysis(&source), &[source]);
        assert_eq!(report.status, SyntacticValidationStatus::Valid);
        assert!(report.is_activatable());
        assert_eq!(report.lexical_alignment_coverage, 1.0);
    }

    #[test]
    fn split_contraction_maps_many_parser_tokens_to_one_subtitle_token() {
        let mut source = sentence("Im ready.");
        source.tokens[0].text = "I'm".into();
        source.display_text = "I'm ready.".into();
        source.original_text = source.display_text.clone();
        source.tokens = vec![
            crate::SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "I'm".into(),
                normalized: Some("i'm".into()),
                start_char: 0,
                end_char: 3,
            },
            crate::SubtitleToken {
                index: 1,
                kind: SubtitleTokenKind::Whitespace,
                text: " ".into(),
                normalized: None,
                start_char: 3,
                end_char: 4,
            },
            crate::SubtitleToken {
                index: 2,
                kind: SubtitleTokenKind::Word,
                text: "ready".into(),
                normalized: Some("ready".into()),
                start_char: 4,
                end_char: 9,
            },
            crate::SubtitleToken {
                index: 3,
                kind: SubtitleTokenKind::Punctuation,
                text: ".".into(),
                normalized: None,
                start_char: 9,
                end_char: 10,
            },
        ];
        let mut analysis = valid_analysis(&sentence("Cats run."));
        analysis.language = LanguageCode::parse("en").unwrap();
        analysis.source_fingerprint =
            syntactic_source_fingerprint(&analysis.language, std::slice::from_ref(&source));
        analysis.sentences[0] = SyntacticSentenceAnalysis {
            sentence_id: source.id.clone(),
            source_text: source.display_text.clone(),
            source_char_count: 10,
            tokens: vec![
                SyntacticToken {
                    parser_token_index: 0,
                    surface: "I".into(),
                    lemma: "I".into(),
                    upos: "PRON".into(),
                    xpos: None,
                    features: BTreeMap::new(),
                    head_parser_token_index: Some(2),
                    dependency_relation: "nsubj".into(),
                    start_char: 0,
                    end_char: 1,
                    subtitle_token_indices: vec![0],
                    alignment_status: SyntacticAlignmentStatus::Split,
                    confidence: None,
                },
                SyntacticToken {
                    parser_token_index: 1,
                    surface: "'m".into(),
                    lemma: "be".into(),
                    upos: "AUX".into(),
                    xpos: None,
                    features: BTreeMap::new(),
                    head_parser_token_index: Some(2),
                    dependency_relation: "cop".into(),
                    start_char: 1,
                    end_char: 3,
                    subtitle_token_indices: vec![0],
                    alignment_status: SyntacticAlignmentStatus::Split,
                    confidence: None,
                },
                SyntacticToken {
                    parser_token_index: 2,
                    surface: "ready".into(),
                    lemma: "ready".into(),
                    upos: "ADJ".into(),
                    xpos: None,
                    features: BTreeMap::new(),
                    head_parser_token_index: None,
                    dependency_relation: "root".into(),
                    start_char: 4,
                    end_char: 9,
                    subtitle_token_indices: vec![2],
                    alignment_status: SyntacticAlignmentStatus::Exact,
                    confidence: None,
                },
                SyntacticToken {
                    parser_token_index: 3,
                    surface: ".".into(),
                    lemma: ".".into(),
                    upos: "PUNCT".into(),
                    xpos: None,
                    features: BTreeMap::new(),
                    head_parser_token_index: Some(2),
                    dependency_relation: "punct".into(),
                    start_char: 9,
                    end_char: 10,
                    subtitle_token_indices: vec![3],
                    alignment_status: SyntacticAlignmentStatus::Exact,
                    confidence: None,
                },
            ],
            unaligned_subtitle_token_indices: vec![],
            lexical_alignment_coverage: 1.0,
        };
        let fingerprint = syntactic_analysis_fingerprint(
            &analysis.descriptor,
            &analysis.source_fingerprint,
            &analysis.profile_fingerprint,
        );
        analysis.id =
            crate::SyntacticAnalysisId::from_fingerprint("syntactic-analysis", &fingerprint);
        let report = validate_syntactic_analysis(&analysis, &[source]);
        assert_eq!(
            report.status,
            SyntacticValidationStatus::Valid,
            "{:#?}",
            report.issues
        );
    }

    #[test]
    fn invalid_head_cycle_and_wrong_span_are_rejected() {
        let source = sentence("Cats run.");
        let mut analysis = valid_analysis(&source);
        analysis.sentences[0].tokens[0].head_parser_token_index = Some(0);
        analysis.sentences[0].tokens[1].start_char = 99;
        let report = validate_syntactic_analysis(&analysis, &[source]);
        assert_eq!(report.status, SyntacticValidationStatus::Invalid);
        assert!(
            report
                .issues
                .iter()
                .any(|issue| issue.kind == SyntacticValidationIssueKind::SelfHead)
        );
        assert!(
            report
                .issues
                .iter()
                .any(|issue| issue.kind == SyntacticValidationIssueKind::SpanOutOfBounds)
        );
    }

    #[test]
    fn unaligned_word_is_explicit_and_not_activatable() {
        let source = sentence("Cats run.");
        let mut analysis = valid_analysis(&source);
        analysis.sentences[0].tokens.remove(0);
        for (index, token) in analysis.sentences[0].tokens.iter_mut().enumerate() {
            token.parser_token_index = index as u32;
            token.head_parser_token_index = match index {
                0 => None,
                _ => Some(0),
            };
        }
        analysis.sentences[0].unaligned_subtitle_token_indices = vec![0];
        analysis.sentences[0].lexical_alignment_coverage = 0.5;
        let report = validate_syntactic_analysis(&analysis, &[source]);
        assert_eq!(report.status, SyntacticValidationStatus::Partial);
        assert!(!report.is_activatable());
    }

    #[test]
    fn provider_model_and_profile_change_artifact_fingerprint() {
        let descriptor = descriptor();
        let baseline = syntactic_analysis_fingerprint(&descriptor, "source", "profile");
        let mut changed = descriptor.clone();
        changed.model_version = "v2".into();
        assert_ne!(
            baseline,
            syntactic_analysis_fingerprint(&changed, "source", "profile")
        );
        assert_ne!(
            baseline,
            syntactic_analysis_fingerprint(&descriptor, "other", "profile")
        );
        assert_ne!(
            baseline,
            syntactic_analysis_fingerprint(&descriptor, "source", "other")
        );
    }
}
