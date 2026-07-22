use serde::Serialize;

use domain::LanguageCode;

use crate::{
    ApplicationError, CoachChannelFacts, CoachDashboardFacts, MediaAnalysisUseCases, now_ms,
};

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CoachChannelStatus {
    Available,
    Unassessed,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CoachMetric {
    pub key: String,
    pub value: u64,
    pub source: String,
    pub authority_layer: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum CoachSuggestionDestination {
    ReviewQueue,
    HuntingList,
    CrossModalReview { language: String },
    PersonalExpression { language: String },
    ContentHome,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CoachSuggestion {
    pub id: String,
    pub kind: String,
    pub title_key: String,
    pub reason_key: String,
    pub destination: CoachSuggestionDestination,
    pub evidence_source: String,
    pub evidence_count: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct CoachAssessmentSummary {
    pub acquired: u64,
    pub not_acquired: u64,
    pub unassessed: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CoachChannelSummary {
    pub channel: String,
    pub status: CoachChannelStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unavailable_reason: Option<String>,
    pub metrics: Vec<CoachMetric>,
    pub effective_assessments: CoachAssessmentSummary,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CoachMaterialInsight {
    pub media_id: String,
    pub title: String,
    pub report_count: u64,
    pub first_report: Option<String>,
    pub latest_report: Option<String>,
    pub reports_understood_all: u64,
    pub reports_got_the_gist: u64,
    pub reports_unclear: u64,
    pub practice_attempts: u64,
    pub practice_correct: u64,
    pub triage_intent: Option<String>,
    pub graduation_candidate: bool,
    pub recommended_intent: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CoachEvidenceItem {
    pub id: String,
    pub occurred_at_ms: u64,
    pub result: String,
    pub source_kind: String,
    pub snapshot: String,
    pub source_available: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unavailable_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CoachFeatureAvailability {
    pub feature: String,
    pub status: String,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CoachDashboard {
    pub period_start_ms: u64,
    pub period_end_ms: u64,
    pub generated_at_ms: u64,
    pub channels: Vec<CoachChannelSummary>,
    pub suggestions: Vec<CoachSuggestion>,
    pub starter_checklist: Vec<String>,
    pub materials: Vec<CoachMaterialInsight>,
    pub features: Vec<CoachFeatureAvailability>,
}

impl MediaAnalysisUseCases {
    pub fn coach_dashboard(
        &self,
        language: &LanguageCode,
        days: u32,
    ) -> Result<CoachDashboard, ApplicationError> {
        let generated_at_ms = now_ms();
        let period_end_ms = generated_at_ms;
        let period_start_ms =
            period_end_ms.saturating_sub(u64::from(days.clamp(1, 365)) * 86_400_000);
        let facts = self.coach_dashboard.coach_dashboard_facts(
            language,
            period_start_ms,
            period_end_ms,
            generated_at_ms,
        )?;
        Ok(build_dashboard(
            period_start_ms,
            period_end_ms,
            generated_at_ms,
            language,
            facts,
        ))
    }

    pub fn graduate_coach_material(
        &self,
        media_id: &domain::MediaId,
    ) -> Result<crate::MediaLibraryEntry, ApplicationError> {
        let now = now_ms();
        let facts = self.coach_dashboard.coach_dashboard_facts(
            &LanguageCode::parse("en").expect("valid default learning language"),
            0,
            now,
            now,
        )?;
        let eligible = facts
            .materials
            .iter()
            .any(|fact| fact.media_id == media_id.as_str() && is_graduation_candidate(fact));
        if !eligible {
            return Err(ApplicationError::Validation(
                "material does not have enough improvement evidence to graduate",
            ));
        }
        self.set_media_triage_intent(media_id, Some(domain::MediaTriageIntent::Graduated))
    }

    pub fn coach_evidence(
        &self,
        metric: &str,
        days: u32,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<CoachEvidenceItem>, ApplicationError> {
        let end = now_ms();
        let start = end.saturating_sub(u64::from(days.clamp(1, 365)) * 86_400_000);
        self.coach_dashboard
            .coach_evidence(metric, start, end, limit.min(100), offset)
            .map(|facts| {
                facts
                    .into_iter()
                    .map(|fact| CoachEvidenceItem {
                        id: fact.id,
                        occurred_at_ms: fact.occurred_at_ms,
                        result: fact.result,
                        source_kind: fact.source_kind,
                        snapshot: fact.snapshot,
                        source_available: fact.source_available,
                        unavailable_reason: fact.unavailable_reason,
                    })
                    .collect()
            })
    }
}

fn is_graduation_candidate(fact: &crate::CoachMaterialFact) -> bool {
    fact.report_count >= 2
        && fact.latest_report.as_deref() == Some("understood_all")
        && fact.first_report.as_deref() != Some("understood_all")
        && (fact.practice_attempts == 0
            || fact.practice_correct.saturating_mul(10) >= fact.practice_attempts.saturating_mul(7))
        && fact.triage_intent.as_deref() != Some("graduated")
}

fn build_dashboard(
    start: u64,
    end: u64,
    generated: u64,
    language: &LanguageCode,
    facts: CoachDashboardFacts,
) -> CoachDashboard {
    let materials = facts
        .materials
        .iter()
        .map(|fact| CoachMaterialInsight {
            media_id: fact.media_id.clone(),
            title: fact.title.clone(),
            report_count: fact.report_count,
            first_report: fact.first_report.clone(),
            latest_report: fact.latest_report.clone(),
            reports_understood_all: fact.reports_understood_all,
            reports_got_the_gist: fact.reports_got_the_gist,
            reports_unclear: fact.reports_unclear,
            practice_attempts: fact.practice_attempts,
            practice_correct: fact.practice_correct,
            triage_intent: fact.triage_intent.clone(),
            graduation_candidate: is_graduation_candidate(fact),
            recommended_intent: if fact.report_count >= 2
                && fact.latest_report.as_deref() == Some("unclear")
            {
                Some("pin_intensive".into())
            } else if fact.report_count >= 2
                && fact.latest_report.as_deref() == Some("got_the_gist")
            {
                Some("pin_extensive".into())
            } else {
                None
            },
        })
        .collect();
    let metrics = vec![
        CoachMetric {
            key: "extensive_sessions".into(),
            value: facts.extensive_sessions,
            source: "practice_sessions".into(),
            authority_layer: "activity_fact".into(),
        },
        CoachMetric {
            key: "extensive_listening_ms".into(),
            value: facts.extensive_listening_ms,
            source: "practice_sessions".into(),
            authority_layer: "activity_fact".into(),
        },
        CoachMetric {
            key: "practice_attempts".into(),
            value: facts.practice_attempts,
            source: "practice_attempts".into(),
            authority_layer: "attempt".into(),
        },
        CoachMetric {
            key: "correct_practice_attempts".into(),
            value: facts.correct_practice_attempts,
            source: "practice_attempts".into(),
            authority_layer: "attempt".into(),
        },
        CoachMetric {
            key: "review_attempts".into(),
            value: facts.review_attempts,
            source: "review_attempts".into(),
            authority_layer: "review_fact".into(),
        },
        CoachMetric {
            key: "successful_review_attempts".into(),
            value: facts.successful_review_attempts,
            source: "review_attempts".into(),
            authority_layer: "review_fact".into(),
        },
        CoachMetric {
            key: "listening_capability_changes".into(),
            value: facts.listening_capability_changes,
            source: "lexical_capability_history".into(),
            authority_layer: "capability_history".into(),
        },
        CoachMetric {
            key: "l1_difficulty_hits".into(),
            value: facts.l1_difficulty_hits,
            source: "learning_events".into(),
            authority_layer: "activity_fact".into(),
        },
    ];
    let mut suggestions = Vec::new();
    if facts.due_review_items > 0 {
        suggestions.push(CoachSuggestion {
            id: "due-review".into(),
            kind: "due_review".into(),
            title_key: "coachSuggestionReview".into(),
            reason_key: "coachSuggestionReviewReason".into(),
            destination: CoachSuggestionDestination::ReviewQueue,
            evidence_source: "review_schedules".into(),
            evidence_count: facts.due_review_items,
        });
    }
    if facts.active_hunting_candidates > 0 {
        suggestions.push(CoachSuggestion {
            id: "hunting-candidates".into(),
            kind: "hunting_candidates".into(),
            title_key: "coachSuggestionHunting".into(),
            reason_key: "coachSuggestionHuntingReason".into(),
            destination: CoachSuggestionDestination::HuntingList,
            evidence_source: "hunting_candidates".into(),
            evidence_count: facts.active_hunting_candidates,
        });
    }
    if facts.cross_modal_gap_count > 0 {
        suggestions.push(CoachSuggestion {
            id: "cross-modal-review".into(),
            kind: "cross_modal_review".into(),
            title_key: "coachSuggestionCrossModal".into(),
            reason_key: "coachSuggestionCrossModalReason".into(),
            destination: CoachSuggestionDestination::CrossModalReview {
                language: language.as_str().into(),
            },
            evidence_source: "effective_capability_assessments".into(),
            evidence_count: facts.cross_modal_gap_count,
        });
    }
    if facts.personal_expression_asset_count > 0 {
        suggestions.push(CoachSuggestion {
            id: "personal-expression".into(),
            kind: "personal_expression".into(),
            title_key: "coachSuggestionPersonalExpression".into(),
            reason_key: "coachSuggestionPersonalExpressionReason".into(),
            destination: CoachSuggestionDestination::PersonalExpression {
                language: language.as_str().into(),
            },
            evidence_source: "user_sentence_patterns".into(),
            evidence_count: facts.personal_expression_asset_count,
        });
    }
    if facts.extensive_sessions > 0 {
        suggestions.push(CoachSuggestion {
            id: "continue-listening".into(),
            kind: "continue_listening".into(),
            title_key: "coachSuggestionContinue".into(),
            reason_key: "coachSuggestionContinueReason".into(),
            destination: CoachSuggestionDestination::ContentHome,
            evidence_source: "practice_sessions:extensive".into(),
            evidence_count: facts.extensive_sessions,
        });
    }
    let starter_checklist =
        if facts.practice_attempts + facts.review_attempts + facts.extensive_sessions == 0 {
            vec![
                "complete_extensive_listening".into(),
                "complete_active_practice".into(),
                "review_due_items".into(),
            ]
        } else {
            Vec::new()
        };
    let channels = ["listening", "reading", "speaking", "writing"]
        .into_iter()
        .map(|channel| {
            let channel_facts = facts.channels.iter().find(|value| value.channel == channel);
            let mut channel_metrics = if channel == "listening" {
                metrics.clone()
            } else {
                Vec::new()
            };
            if let Some(value) = channel_facts {
                channel_metrics.extend(channel_metrics_for(value));
            }
            let assessments = channel_facts
                .map(|value| CoachAssessmentSummary {
                    acquired: value.acquired_entries,
                    not_acquired: value.not_acquired_entries,
                    unassessed: value.unassessed_entries,
                })
                .unwrap_or_default();
            let has_facts = channel_metrics.iter().any(|metric| metric.value > 0)
                || assessments.acquired + assessments.not_acquired > 0;
            CoachChannelSummary {
                channel: channel.into(),
                status: if has_facts || channel == "listening" {
                    CoachChannelStatus::Available
                } else {
                    CoachChannelStatus::Unassessed
                },
                unavailable_reason: (!has_facts && channel != "listening")
                    .then(|| "no_active_validation".into()),
                metrics: channel_metrics,
                effective_assessments: assessments,
            }
        })
        .collect();
    CoachDashboard {
        period_start_ms: start,
        period_end_ms: end,
        generated_at_ms: generated,
        channels,
        suggestions,
        starter_checklist,
        materials,
        features: vec![CoachFeatureAvailability {
            feature: "llm_feedback".into(),
            status: if facts.llm_provider_profile_count > 0 {
                "configured".into()
            } else {
                "not_configured".into()
            },
            reason: "coach_core_is_provider_independent".into(),
        }],
    }
}

fn channel_metrics_for(facts: &CoachChannelFacts) -> Vec<CoachMetric> {
    [
        (
            "completed_attempts",
            facts.completed_attempts,
            "semantic_task_attempts",
            "attempt",
        ),
        (
            "supporting_judgments",
            facts.supporting_judgments,
            "semantic_judgments",
            "supporting_judgment",
        ),
        (
            "adjudications",
            facts.adjudications,
            "judgment_adjudications",
            "adjudication",
        ),
        (
            "observations",
            facts.observations,
            "learning_observations",
            "channel_evidence",
        ),
        (
            "projection_proposals",
            facts.projection_proposals,
            "projection_proposals",
            "proposal",
        ),
        (
            "confirmed_projections",
            facts.confirmed_projections,
            "projection_decisions",
            "confirmed_projection",
        ),
        (
            "capability_changes",
            facts.capability_changes,
            "lexical_capability_history",
            "capability_history",
        ),
        (
            "personal_expression_attempts",
            facts.personal_expression_attempts,
            "personal_expression_attempts",
            "durable_asset_attempt",
        ),
    ]
    .into_iter()
    .filter(|(_, value, _, _)| *value > 0)
    .map(|(key, value, source, authority_layer)| CoachMetric {
        key: format!("{}_{}", facts.channel, key),
        value,
        source: source.into(),
        authority_layer: authority_layer.into(),
    })
    .collect()
}

#[derive(Debug)]
pub struct DisabledCoachDashboardRepository;
impl crate::CoachDashboardRepository for DisabledCoachDashboardRepository {
    fn coach_dashboard_facts(
        &self,
        _: &LanguageCode,
        _: u64,
        _: u64,
        _: u64,
    ) -> Result<CoachDashboardFacts, ApplicationError> {
        Ok(CoachDashboardFacts::default())
    }
    fn coach_evidence(
        &self,
        _: &str,
        _: u64,
        _: u64,
        _: u32,
        _: u32,
    ) -> Result<Vec<crate::CoachEvidenceFact>, ApplicationError> {
        Ok(Vec::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn future_channels_are_unassessed_and_suggestions_are_traceable() {
        let dashboard = build_dashboard(
            1,
            2,
            2,
            &LanguageCode::parse("en").unwrap(),
            CoachDashboardFacts {
                due_review_items: 3,
                active_hunting_candidates: 2,
                ..Default::default()
            },
        );
        assert_eq!(dashboard.suggestions.len(), 2);
        assert_eq!(dashboard.channels[1].status, CoachChannelStatus::Unassessed);
        assert_eq!(dashboard.suggestions[0].evidence_source, "review_schedules");
    }

    #[test]
    fn graduation_requires_repeated_improvement_and_never_silently_changes_state() {
        let fact = crate::CoachMaterialFact {
            media_id: "m".into(),
            title: "Material".into(),
            report_count: 2,
            first_report: Some("got_the_gist".into()),
            latest_report: Some("understood_all".into()),
            reports_understood_all: 1,
            reports_got_the_gist: 1,
            practice_attempts: 3,
            practice_correct: 2,
            ..Default::default()
        };
        assert!(!is_graduation_candidate(&fact));
        assert!(is_graduation_candidate(&crate::CoachMaterialFact {
            practice_correct: 3,
            ..fact
        }));
    }
}
