use serde::{Deserialize, Serialize};

use crate::{LearningStatus, LexicalCapabilityHistoryId, LexicalEntryId, LexicalSenseId};

pub const LEGACY_STATUS_MIGRATION_ALGORITHM_VERSION: &str = "legacy-learning-status-migration-v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LexicalCapability {
    Reading,
    Listening,
    Speaking,
    Writing,
}

impl LexicalCapability {
    pub const ALL: [Self; 4] = [
        Self::Reading,
        Self::Listening,
        Self::Speaking,
        Self::Writing,
    ];
}

/// The effective read-side assessment for one capability.
///
/// `Unassessed` is deliberately distinct from `NotAcquired`: absence of a
/// projection or user override must never become negative learning data.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityAssessment {
    Unassessed,
    NotAcquired,
    Acquired,
}

/// A concrete conclusion stored by a projection or user override.
///
/// Unassessed is represented by the absence of that record, which prevents a
/// persisted override from ambiguously meaning either "cleared" or "unknown".
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityConclusion {
    NotAcquired,
    Acquired,
}

impl From<CapabilityConclusion> for CapabilityAssessment {
    fn from(value: CapabilityConclusion) -> Self {
        match value {
            CapabilityConclusion::NotAcquired => Self::NotAcquired,
            CapabilityConclusion::Acquired => Self::Acquired,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityProjectionSource {
    LegacyLearningStatusMigration,
    EvidenceProjection,
    Import,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CapabilityProjection {
    pub conclusion: CapabilityConclusion,
    pub source: CapabilityProjectionSource,
    pub algorithm_version: String,
    /// Reserved seam: graded strength of the conclusion (0.0..=1.0). Stays
    /// `None` until a real evidence-projection algorithm writes it; the
    /// tri-state effective assessment remains the product read model.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub confidence: Option<f32>,
    /// Reserved seam: end of the evidence window this projection was derived
    /// from, for recency-aware consumers and recomputation. `None` for
    /// legacy/compat/import projections.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub evidence_as_of_ms: Option<u64>,
    pub updated_at_ms: u64,
}

impl CapabilityProjection {
    pub fn legacy(conclusion: CapabilityConclusion, migrated_at_ms: u64) -> Self {
        Self {
            conclusion,
            source: CapabilityProjectionSource::LegacyLearningStatusMigration,
            algorithm_version: LEGACY_STATUS_MIGRATION_ALGORITHM_VERSION.into(),
            confidence: None,
            evidence_as_of_ms: None,
            updated_at_ms: migrated_at_ms,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityOverrideSource {
    UserSelection,
    Import,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityOverride {
    pub conclusion: CapabilityConclusion,
    pub source: CapabilityOverrideSource,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct CapabilityDimensionState {
    pub projection: Option<CapabilityProjection>,
    pub user_override: Option<CapabilityOverride>,
}

impl CapabilityDimensionState {
    pub fn effective_assessment(&self) -> CapabilityAssessment {
        self.user_override
            .as_ref()
            .map(|value| value.conclusion)
            .or_else(|| self.projection.as_ref().map(|value| value.conclusion))
            .map(CapabilityAssessment::from)
            .unwrap_or(CapabilityAssessment::Unassessed)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LexicalCapabilityProfile {
    pub lexical_entry_id: LexicalEntryId,
    /// Reserved identity seam. Phase 3.4.1 does not create lexical senses, so
    /// migrated and newly created profiles use `None`.
    pub sense_id: Option<LexicalSenseId>,
    pub reading: CapabilityDimensionState,
    pub listening: CapabilityDimensionState,
    pub speaking: CapabilityDimensionState,
    pub writing: CapabilityDimensionState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityStateChangeKind {
    ProjectionUpdated,
    OverrideSet,
    OverrideCleared,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LexicalCapabilityHistory {
    pub id: LexicalCapabilityHistoryId,
    pub lexical_entry_id: LexicalEntryId,
    pub sense_id: Option<LexicalSenseId>,
    pub capability: LexicalCapability,
    pub previous_state: CapabilityDimensionState,
    pub new_state: CapabilityDimensionState,
    pub change_kind: CapabilityStateChangeKind,
    pub changed_at_ms: u64,
}

impl LexicalCapabilityProfile {
    pub fn unassessed(lexical_entry_id: LexicalEntryId) -> Self {
        Self {
            lexical_entry_id,
            sense_id: None,
            reading: CapabilityDimensionState::default(),
            listening: CapabilityDimensionState::default(),
            speaking: CapabilityDimensionState::default(),
            writing: CapabilityDimensionState::default(),
        }
    }

    pub fn from_legacy_status(
        lexical_entry_id: LexicalEntryId,
        status: Option<LearningStatus>,
        migrated_at_ms: u64,
    ) -> Self {
        let mut profile = Self::unassessed(lexical_entry_id);
        match status {
            None => {}
            Some(LearningStatus::UnknownMeaning) => {
                profile.reading.projection = Some(CapabilityProjection::legacy(
                    CapabilityConclusion::NotAcquired,
                    migrated_at_ms,
                ));
            }
            Some(LearningStatus::KnownNotRecognized) => {
                profile.reading.projection = Some(CapabilityProjection::legacy(
                    CapabilityConclusion::Acquired,
                    migrated_at_ms,
                ));
                profile.listening.projection = Some(CapabilityProjection::legacy(
                    CapabilityConclusion::NotAcquired,
                    migrated_at_ms,
                ));
            }
            Some(LearningStatus::KnownRecognized) => {
                profile.reading.projection = Some(CapabilityProjection::legacy(
                    CapabilityConclusion::Acquired,
                    migrated_at_ms,
                ));
                profile.listening.projection = Some(CapabilityProjection::legacy(
                    CapabilityConclusion::Acquired,
                    migrated_at_ms,
                ));
            }
        }
        profile
    }

    pub fn dimension(&self, capability: LexicalCapability) -> &CapabilityDimensionState {
        match capability {
            LexicalCapability::Reading => &self.reading,
            LexicalCapability::Listening => &self.listening,
            LexicalCapability::Speaking => &self.speaking,
            LexicalCapability::Writing => &self.writing,
        }
    }

    pub fn dimension_mut(
        &mut self,
        capability: LexicalCapability,
    ) -> &mut CapabilityDimensionState {
        match capability {
            LexicalCapability::Reading => &mut self.reading,
            LexicalCapability::Listening => &mut self.listening,
            LexicalCapability::Speaking => &mut self.speaking,
            LexicalCapability::Writing => &mut self.writing,
        }
    }

    pub fn effective_assessment(&self, capability: LexicalCapability) -> CapabilityAssessment {
        self.dimension(capability).effective_assessment()
    }

    /// Conservative compatibility projection for consumers that only
    /// understand the legacy linear status.
    pub fn legacy_status_view(&self) -> Option<LearningStatus> {
        match (
            self.reading.effective_assessment(),
            self.listening.effective_assessment(),
        ) {
            (CapabilityAssessment::NotAcquired, _) => Some(LearningStatus::UnknownMeaning),
            (CapabilityAssessment::Acquired, CapabilityAssessment::NotAcquired) => {
                Some(LearningStatus::KnownNotRecognized)
            }
            (CapabilityAssessment::Acquired, CapabilityAssessment::Acquired) => {
                Some(LearningStatus::KnownRecognized)
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry_id() -> LexicalEntryId {
        LexicalEntryId::parse("entry").unwrap()
    }

    #[test]
    fn a_new_profile_is_unassessed_in_every_capability() {
        let profile = LexicalCapabilityProfile::unassessed(entry_id());

        for capability in LexicalCapability::ALL {
            assert_eq!(
                profile.effective_assessment(capability),
                CapabilityAssessment::Unassessed
            );
        }
        assert_eq!(profile.legacy_status_view(), None);
    }

    #[test]
    fn a_user_override_takes_precedence_without_deleting_projection() {
        let projection = CapabilityProjection {
            conclusion: CapabilityConclusion::Acquired,
            source: CapabilityProjectionSource::EvidenceProjection,
            algorithm_version: "projection-v1".into(),
            confidence: None,
            evidence_as_of_ms: None,
            updated_at_ms: 10,
        };
        let mut state = CapabilityDimensionState {
            projection: Some(projection.clone()),
            user_override: Some(CapabilityOverride {
                conclusion: CapabilityConclusion::NotAcquired,
                source: CapabilityOverrideSource::UserSelection,
                updated_at_ms: 20,
            }),
        };

        assert_eq!(
            state.effective_assessment(),
            CapabilityAssessment::NotAcquired
        );
        assert_eq!(state.projection, Some(projection));

        state.user_override = None;
        assert_eq!(state.effective_assessment(), CapabilityAssessment::Acquired);
    }

    #[test]
    fn legacy_status_mapping_is_explicit_and_leaves_productive_channels_unassessed() {
        let cases = [
            (
                None,
                CapabilityAssessment::Unassessed,
                CapabilityAssessment::Unassessed,
            ),
            (
                Some(LearningStatus::UnknownMeaning),
                CapabilityAssessment::NotAcquired,
                CapabilityAssessment::Unassessed,
            ),
            (
                Some(LearningStatus::KnownNotRecognized),
                CapabilityAssessment::Acquired,
                CapabilityAssessment::NotAcquired,
            ),
            (
                Some(LearningStatus::KnownRecognized),
                CapabilityAssessment::Acquired,
                CapabilityAssessment::Acquired,
            ),
        ];

        for (legacy, reading, listening) in cases {
            let profile = LexicalCapabilityProfile::from_legacy_status(entry_id(), legacy, 42);
            assert_eq!(
                profile.effective_assessment(LexicalCapability::Reading),
                reading
            );
            assert_eq!(
                profile.effective_assessment(LexicalCapability::Listening),
                listening
            );
            assert_eq!(
                profile.effective_assessment(LexicalCapability::Speaking),
                CapabilityAssessment::Unassessed
            );
            assert_eq!(
                profile.effective_assessment(LexicalCapability::Writing),
                CapabilityAssessment::Unassessed
            );
            assert_eq!(profile.legacy_status_view(), legacy);
        }
    }

    #[test]
    fn migrated_values_have_explicit_provenance() {
        let profile = LexicalCapabilityProfile::from_legacy_status(
            entry_id(),
            Some(LearningStatus::KnownRecognized),
            42,
        );
        let projection = profile.reading.projection.unwrap();

        assert_eq!(
            projection.source,
            CapabilityProjectionSource::LegacyLearningStatusMigration
        );
        assert_eq!(
            projection.algorithm_version,
            LEGACY_STATUS_MIGRATION_ALGORITHM_VERSION
        );
        assert_eq!(projection.updated_at_ms, 42);
    }

    #[test]
    fn legacy_view_is_conservative_for_inexpressible_profiles() {
        let mut profile = LexicalCapabilityProfile::unassessed(entry_id());
        profile.listening.user_override = Some(CapabilityOverride {
            conclusion: CapabilityConclusion::Acquired,
            source: CapabilityOverrideSource::UserSelection,
            updated_at_ms: 1,
        });
        assert_eq!(profile.legacy_status_view(), None);

        profile.speaking.user_override = Some(CapabilityOverride {
            conclusion: CapabilityConclusion::NotAcquired,
            source: CapabilityOverrideSource::UserSelection,
            updated_at_ms: 2,
        });
        assert_eq!(profile.legacy_status_view(), None);
    }

    #[test]
    fn projection_seam_fields_default_to_none_and_stay_out_of_json() {
        let legacy_json = r#"{"conclusion":"acquired","source":"evidence_projection","algorithm_version":"v1","updated_at_ms":5}"#;
        let projection: CapabilityProjection = serde_json::from_str(legacy_json).unwrap();
        assert_eq!(projection.confidence, None);
        assert_eq!(projection.evidence_as_of_ms, None);

        let serialized = serde_json::to_string(&projection).unwrap();
        assert!(!serialized.contains("confidence"));
        assert!(!serialized.contains("evidence_as_of_ms"));

        let populated = CapabilityProjection {
            confidence: Some(0.85),
            evidence_as_of_ms: Some(99),
            ..projection
        };
        let roundtrip: CapabilityProjection =
            serde_json::from_str(&serde_json::to_string(&populated).unwrap()).unwrap();
        assert_eq!(roundtrip, populated);
    }

    #[test]
    fn serialized_contract_uses_named_snake_case_values() {
        assert_eq!(
            serde_json::to_string(&LexicalCapability::Listening).unwrap(),
            "\"listening\""
        );
        assert_eq!(
            serde_json::to_string(&CapabilityAssessment::NotAcquired).unwrap(),
            "\"not_acquired\""
        );
        assert_eq!(
            serde_json::to_string(&CapabilityProjectionSource::LegacyLearningStatusMigration)
                .unwrap(),
            "\"legacy_learning_status_migration\""
        );
    }
}
