//! Construction-modeling spike contract (Phase 3.4.3).
//!
//! These types intentionally model only the boundaries proven by the committed
//! gold fixture. They are not a persistence, API, or automatic-analysis
//! contract. In particular, canonical constructions remain a manually curated
//! namespace and `UserSentencePattern` remains independently user-owned.

use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize};

use crate::{
    CapabilityAssessment, ConstructionId, ConstructionOccurrenceId, LanguageCode,
    SentenceExemplarId, UserSentencePatternId,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SentenceExemplar {
    pub id: SentenceExemplarId,
    pub language: LanguageCode,
    pub text: String,
    /// Immutable local/imported source reference, never a canonical construction key.
    pub source_snapshot_ref: String,
    pub token_count: u32,
}

/// Stable only when both the captured source snapshot and sentence text match.
/// The same wording from a different source remains a distinct exemplar.
pub fn sentence_exemplar_id(
    language: &LanguageCode,
    source_snapshot_ref: &str,
    text: &str,
) -> SentenceExemplarId {
    SentenceExemplarId::from_fingerprint(
        "sentence-exemplar",
        &format!("{}:{source_snapshot_ref}:{text}", language.as_str()),
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VariantTreatment {
    /// This dimension does not establish a different canonical construction.
    Collapsed,
    /// This construction accepts only its declared canonical value for this dimension.
    Separate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TenseVariant {
    Base,
    Present,
    Past,
    Future,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VoiceVariant {
    Active,
    Passive,
    NotApplicable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PolarityVariant {
    Affirmative,
    Negative,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClauseTypeVariant {
    Declarative,
    Interrogative,
    Imperative,
    Subordinate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConstructionVariantSignature {
    pub tense: TenseVariant,
    pub voice: VoiceVariant,
    pub polarity: PolarityVariant,
    pub clause_type: ClauseTypeVariant,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConstructionVariantPolicy {
    pub tense: VariantTreatment,
    pub voice: VariantTreatment,
    pub polarity: VariantTreatment,
    pub clause_type: VariantTreatment,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConstructionSlot {
    pub name: String,
    /// Human-curated, provider-neutral constraint label. It is intentionally
    /// not a parser-specific POS/feature schema at this spike stage.
    pub constraint: String,
    pub required: bool,
}

/// A manually curated, language-scoped abstraction. `key` is explicit rather
/// than inferred from sentence text; cross-language equivalence is deferred to
/// a future explanation/mapping layer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Construction {
    pub id: ConstructionId,
    pub language: LanguageCode,
    pub key: String,
    pub schema_version: u32,
    pub display_pattern: String,
    pub canonical_variant: ConstructionVariantSignature,
    pub variant_policy: ConstructionVariantPolicy,
    pub slots: Vec<ConstructionSlot>,
}

pub fn construction_id(language: &LanguageCode, key: &str, schema_version: u32) -> ConstructionId {
    ConstructionId::from_fingerprint(
        "construction",
        &format!("{}:{key}:{schema_version}", language.as_str()),
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct TokenSpan {
    /// Inclusive token index.
    pub start_token_index: u32,
    /// Exclusive token index.
    pub end_token_index: u32,
}

impl TokenSpan {
    fn is_valid_for(self, token_count: u32) -> bool {
        self.start_token_index < self.end_token_index && self.end_token_index <= token_count
    }

    fn contains(self, other: Self) -> bool {
        self.start_token_index <= other.start_token_index
            && other.end_token_index <= self.end_token_index
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConstructionSlotBinding {
    pub slot_name: String,
    pub token_span: TokenSpan,
    pub text_snapshot: String,
}

/// A rebuildable annotation. Overlap and nesting are intentionally allowed:
/// one exemplar can instantiate multiple constructions and a construction can
/// occur inside another construction.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConstructionOccurrence {
    pub id: ConstructionOccurrenceId,
    pub exemplar_id: SentenceExemplarId,
    pub construction_id: ConstructionId,
    pub token_span: TokenSpan,
    pub variant: ConstructionVariantSignature,
    pub slot_bindings: Vec<ConstructionSlotBinding>,
    pub provider_id: String,
    pub provider_version: String,
    pub evidence_class: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserSentencePattern {
    pub id: UserSentencePatternId,
    pub language: LanguageCode,
    pub pattern_text: String,
    pub source_exemplar_id: SentenceExemplarId,
    /// Retained when media/subtitles or automatic analyses later change.
    pub source_text_snapshot: String,
    /// An optional suggestion/link only. It is never required to create or own
    /// a personal pattern and must not replace `pattern_text`.
    pub system_construction_id: Option<ConstructionId>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConstructionCapabilityAxis {
    Recognition,
    Production,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConstructionEvidenceModality {
    Reading,
    Listening,
    Speaking,
    Writing,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConstructionCapabilityProfile {
    pub construction_id: ConstructionId,
    pub recognition: CapabilityAssessment,
    pub production: CapabilityAssessment,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConstructionEvidence {
    pub construction_id: ConstructionId,
    pub capability: ConstructionCapabilityAxis,
    pub modality: ConstructionEvidenceModality,
    pub outcome: String,
    pub source_exemplar_id: Option<SentenceExemplarId>,
    pub evidence_class: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConstructionSpikeFixture {
    pub fixture_version: u32,
    pub evidence_class: String,
    pub exemplars: Vec<SentenceExemplar>,
    pub constructions: Vec<Construction>,
    pub occurrences: Vec<ConstructionOccurrence>,
    pub user_sentence_patterns: Vec<UserSentencePattern>,
    pub capability_profiles: Vec<ConstructionCapabilityProfile>,
    pub evidence: Vec<ConstructionEvidence>,
}

/// Validates only the model invariants intentionally decided by Phase 3.4.3.
/// It does not judge linguistic correctness, infer constructions, or prescribe
/// storage/API/UI shape.
pub fn validate_construction_spike_fixture(
    fixture: &ConstructionSpikeFixture,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    if fixture.fixture_version != 1 {
        errors.push("fixture_version must be 1".into());
    }
    if fixture.evidence_class != "gold" {
        errors.push("fixture evidence_class must be gold".into());
    }

    let exemplars = unique_by(
        &fixture.exemplars,
        |value| value.id.as_str().to_owned(),
        "exemplar",
        &mut errors,
    );
    for exemplar in &fixture.exemplars {
        if exemplar.text.trim().is_empty()
            || exemplar.source_snapshot_ref.trim().is_empty()
            || exemplar.token_count == 0
        {
            errors.push(format!(
                "exemplar {} lacks text, source snapshot, or tokens",
                exemplar.id.as_str()
            ));
        }
    }

    let constructions = unique_by(
        &fixture.constructions,
        |value| value.id.as_str().to_owned(),
        "construction",
        &mut errors,
    );
    let mut canonical_keys = HashSet::new();
    for construction in &fixture.constructions {
        if construction.key.trim().is_empty()
            || construction.schema_version == 0
            || construction.display_pattern.trim().is_empty()
        {
            errors.push(format!(
                "construction {} has incomplete canonical identity",
                construction.id.as_str()
            ));
        }
        let canonical_key = format!(
            "{}:{}:{}",
            construction.language.as_str(),
            construction.key,
            construction.schema_version
        );
        if !canonical_keys.insert(canonical_key) {
            errors.push(format!(
                "duplicate canonical construction identity: {}",
                construction.id.as_str()
            ));
        }
        let mut slot_names = HashSet::new();
        for slot in &construction.slots {
            if slot.name.trim().is_empty()
                || slot.constraint.trim().is_empty()
                || !slot_names.insert(slot.name.as_str())
            {
                errors.push(format!(
                    "construction {} has an invalid or duplicate slot",
                    construction.id.as_str()
                ));
            }
        }
    }

    let mut occurrence_keys = HashSet::new();
    let mut occurrence_ids = HashSet::new();
    for occurrence in &fixture.occurrences {
        if !occurrence_ids.insert(occurrence.id.as_str()) {
            errors.push(format!(
                "duplicate occurrence id: {}",
                occurrence.id.as_str()
            ));
        }
        let Some(exemplar) = exemplars.get(occurrence.exemplar_id.as_str()) else {
            errors.push(format!(
                "occurrence {} references missing exemplar",
                occurrence.id.as_str()
            ));
            continue;
        };
        let Some(construction) = constructions.get(occurrence.construction_id.as_str()) else {
            errors.push(format!(
                "occurrence {} references missing construction",
                occurrence.id.as_str()
            ));
            continue;
        };
        if exemplar.language != construction.language {
            errors.push(format!(
                "occurrence {} crosses languages",
                occurrence.id.as_str()
            ));
        }
        if !occurrence.token_span.is_valid_for(exemplar.token_count) {
            errors.push(format!(
                "occurrence {} has an invalid token span",
                occurrence.id.as_str()
            ));
        }
        if occurrence.provider_id.trim().is_empty()
            || occurrence.provider_version.trim().is_empty()
            || occurrence.evidence_class != "gold"
        {
            errors.push(format!(
                "occurrence {} lacks gold-analysis provenance",
                occurrence.id.as_str()
            ));
        }
        let occurrence_key = format!(
            "{}:{}:{}:{}",
            occurrence.exemplar_id.as_str(),
            occurrence.construction_id.as_str(),
            occurrence.token_span.start_token_index,
            occurrence.token_span.end_token_index
        );
        if !occurrence_keys.insert(occurrence_key) {
            errors.push(format!(
                "duplicate occurrence identity: {}",
                occurrence.id.as_str()
            ));
        }
        validate_variant_policy(occurrence, construction, &mut errors);
        let slots: HashMap<_, _> = construction
            .slots
            .iter()
            .map(|slot| (slot.name.as_str(), slot))
            .collect();
        let mut bound_slots = HashSet::new();
        for binding in &occurrence.slot_bindings {
            if !slots.contains_key(binding.slot_name.as_str())
                || !bound_slots.insert(binding.slot_name.as_str())
                || !binding.token_span.is_valid_for(exemplar.token_count)
                || !occurrence.token_span.contains(binding.token_span)
                || binding.text_snapshot.trim().is_empty()
            {
                errors.push(format!(
                    "occurrence {} has an invalid slot binding",
                    occurrence.id.as_str()
                ));
            }
        }
        for slot in construction.slots.iter().filter(|slot| slot.required) {
            if !bound_slots.contains(slot.name.as_str()) {
                errors.push(format!(
                    "occurrence {} omits required slot {}",
                    occurrence.id.as_str(),
                    slot.name
                ));
            }
        }
    }

    let mut user_pattern_ids = HashSet::new();
    for pattern in &fixture.user_sentence_patterns {
        if !user_pattern_ids.insert(pattern.id.as_str()) {
            errors.push(format!(
                "duplicate user pattern id: {}",
                pattern.id.as_str()
            ));
        }
        let Some(exemplar) = exemplars.get(pattern.source_exemplar_id.as_str()) else {
            errors.push(format!(
                "user pattern {} lacks its source exemplar",
                pattern.id.as_str()
            ));
            continue;
        };
        if pattern.language != exemplar.language
            || pattern.pattern_text.trim().is_empty()
            || pattern.source_text_snapshot != exemplar.text
        {
            errors.push(format!(
                "user pattern {} does not preserve a matching source snapshot",
                pattern.id.as_str()
            ));
        }
        if let Some(construction_id) = &pattern.system_construction_id {
            match constructions.get(construction_id.as_str()) {
                Some(construction) if construction.language == pattern.language => {}
                _ => errors.push(format!(
                    "user pattern {} has an invalid system link",
                    pattern.id.as_str()
                )),
            }
        }
    }

    let mut profile_ids = HashSet::new();
    for profile in &fixture.capability_profiles {
        if !constructions.contains_key(profile.construction_id.as_str())
            || !profile_ids.insert(profile.construction_id.as_str())
        {
            errors.push("capability profile must uniquely reference a construction".into());
        }
    }
    for evidence in &fixture.evidence {
        if !constructions.contains_key(evidence.construction_id.as_str())
            || !profile_ids.contains(evidence.construction_id.as_str())
            || evidence.outcome.trim().is_empty()
            || evidence.evidence_class.trim().is_empty()
        {
            errors.push("construction evidence references an incomplete target".into());
        }
        if let Some(exemplar_id) = &evidence.source_exemplar_id {
            if !exemplars.contains_key(exemplar_id.as_str()) {
                errors.push("construction evidence references a missing exemplar".into());
            }
        }
        let valid_modality = matches!(
            (evidence.capability, evidence.modality),
            (
                ConstructionCapabilityAxis::Recognition,
                ConstructionEvidenceModality::Reading | ConstructionEvidenceModality::Listening
            ) | (
                ConstructionCapabilityAxis::Production,
                ConstructionEvidenceModality::Speaking | ConstructionEvidenceModality::Writing
            )
        );
        if !valid_modality {
            errors.push("construction evidence modality does not match its capability axis".into());
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

fn unique_by<'a, T>(
    values: &'a [T],
    key: impl Fn(&T) -> String,
    kind: &str,
    errors: &mut Vec<String>,
) -> HashMap<String, &'a T> {
    let mut result = HashMap::new();
    for value in values {
        let value_key = key(value);
        if result.insert(value_key.clone(), value).is_some() {
            errors.push(format!("duplicate {kind} id: {value_key}"));
        }
    }
    result
}

fn validate_variant_policy(
    occurrence: &ConstructionOccurrence,
    construction: &Construction,
    errors: &mut Vec<String>,
) {
    let canonical = construction.canonical_variant;
    let actual = occurrence.variant;
    let policy = construction.variant_policy;
    let is_valid = (policy.tense != VariantTreatment::Separate || actual.tense == canonical.tense)
        && (policy.voice != VariantTreatment::Separate || actual.voice == canonical.voice)
        && (policy.polarity != VariantTreatment::Separate || actual.polarity == canonical.polarity)
        && (policy.clause_type != VariantTreatment::Separate
            || actual.clause_type == canonical.clause_type);
    if !is_valid {
        errors.push(format!(
            "occurrence {} violates its construction variant policy",
            occurrence.id.as_str()
        ));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> ConstructionSpikeFixture {
        serde_json::from_str(include_str!(
            "../../../testdata/construction-spike/gold-fixture-v1.json"
        ))
        .expect("gold fixture deserializes")
    }

    #[test]
    fn gold_fixture_locks_identity_slots_variants_and_modality() {
        let fixture = fixture();
        assert_eq!(fixture.evidence_class, "gold");
        validate_construction_spike_fixture(&fixture).expect("fixture is valid");
        assert!(
            fixture
                .user_sentence_patterns
                .iter()
                .any(|pattern| pattern.system_construction_id.is_none())
        );
        let arbitrary_pattern = fixture
            .user_sentence_patterns
            .iter()
            .find(|pattern| pattern.id.as_str() == "up-ja-arbitrary")
            .expect("arbitrary personal pattern is present");
        assert!(arbitrary_pattern.system_construction_id.is_none());
        assert!(
            !fixture
                .occurrences
                .iter()
                .any(|occurrence| occurrence.exemplar_id == arbitrary_pattern.source_exemplar_id),
            "a user pattern may originate from an exemplar with no system occurrence"
        );
        assert!(fixture.evidence.iter().any(|evidence| {
            evidence.capability == ConstructionCapabilityAxis::Recognition
                && evidence.modality == ConstructionEvidenceModality::Listening
        }));
        assert!(fixture.evidence.iter().any(|evidence| {
            evidence.capability == ConstructionCapabilityAxis::Production
                && evidence.modality == ConstructionEvidenceModality::Writing
        }));
    }

    #[test]
    fn nested_and_multiple_occurrences_remain_valid_annotations() {
        let fixture = fixture();
        let parent = fixture
            .occurrences
            .iter()
            .find(|value| value.id.as_str() == "occ-en-comparative")
            .unwrap();
        let nested = fixture
            .occurrences
            .iter()
            .filter(|value| value.exemplar_id == parent.exemplar_id)
            .count();
        assert_eq!(
            nested, 3,
            "one exemplar has one outer and two nested occurrences"
        );
        validate_construction_spike_fixture(&fixture).expect("overlap is permitted");
    }

    #[test]
    fn separate_variant_policy_rejects_an_unlisted_variant() {
        let mut fixture = fixture();
        let construction = fixture
            .constructions
            .iter_mut()
            .find(|value| value.id.as_str() == "c-en-transitive")
            .unwrap();
        construction.variant_policy.voice = VariantTreatment::Separate;
        let errors = validate_construction_spike_fixture(&fixture)
            .expect_err("passive occurrence must split");
        assert!(errors.iter().any(|error| error.contains("variant policy")));
    }

    #[test]
    fn canonical_and_exemplar_identity_are_separate_and_stable() {
        let english = LanguageCode::parse("en").unwrap();
        assert_eq!(
            construction_id(&english, "transitive-clause", 1),
            construction_id(&english, "transitive-clause", 1)
        );
        assert_ne!(
            construction_id(&english, "transitive-clause", 1),
            construction_id(&english, "transitive-clause", 2)
        );
        assert_ne!(
            sentence_exemplar_id(&english, "media:a", "I practice."),
            sentence_exemplar_id(&english, "media:b", "I practice."),
        );
    }
}
