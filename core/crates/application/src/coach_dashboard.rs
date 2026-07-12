use serde::Serialize;

use crate::{AppServices, ApplicationError, CoachDashboardFacts, now_ms};

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
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CoachSuggestion {
    pub kind: String,
    pub title_key: String,
    pub reason_key: String,
    pub action: String,
    pub evidence_source: String,
    pub evidence_count: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CoachChannelSummary {
    pub channel: String,
    pub status: CoachChannelStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unavailable_reason: Option<String>,
    pub metrics: Vec<CoachMetric>,
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
}

impl AppServices {
    pub fn coach_dashboard(&self, days: u32) -> Result<CoachDashboard, ApplicationError> {
        let generated_at_ms = now_ms();
        let period_end_ms = generated_at_ms;
        let period_start_ms =
            period_end_ms.saturating_sub(u64::from(days.clamp(1, 365)) * 86_400_000);
        let facts = self.coach_dashboard.coach_dashboard_facts(
            period_start_ms,
            period_end_ms,
            generated_at_ms,
        )?;
        Ok(build_dashboard(
            period_start_ms,
            period_end_ms,
            generated_at_ms,
            facts,
        ))
    }

    pub fn graduate_coach_material(
        &self,
        media_id: &domain::MediaId,
    ) -> Result<crate::MediaLibraryEntry, ApplicationError> {
        let now = now_ms();
        let facts = self.coach_dashboard.coach_dashboard_facts(0, now, now)?;
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
        },
        CoachMetric {
            key: "extensive_listening_ms".into(),
            value: facts.extensive_listening_ms,
            source: "practice_sessions".into(),
        },
        CoachMetric {
            key: "practice_attempts".into(),
            value: facts.practice_attempts,
            source: "practice_attempts".into(),
        },
        CoachMetric {
            key: "correct_practice_attempts".into(),
            value: facts.correct_practice_attempts,
            source: "practice_attempts".into(),
        },
        CoachMetric {
            key: "review_attempts".into(),
            value: facts.review_attempts,
            source: "review_attempts".into(),
        },
        CoachMetric {
            key: "successful_review_attempts".into(),
            value: facts.successful_review_attempts,
            source: "review_attempts".into(),
        },
        CoachMetric {
            key: "listening_capability_changes".into(),
            value: facts.listening_capability_changes,
            source: "lexical_capability_history".into(),
        },
        CoachMetric {
            key: "l1_difficulty_hits".into(),
            value: facts.l1_difficulty_hits,
            source: "learning_events".into(),
        },
    ];
    let mut suggestions = Vec::new();
    if facts.due_review_items > 0 {
        suggestions.push(CoachSuggestion {
            kind: "due_review".into(),
            title_key: "coachSuggestionReview".into(),
            reason_key: "coachSuggestionReviewReason".into(),
            action: "open_review".into(),
            evidence_source: "review_schedules".into(),
            evidence_count: facts.due_review_items,
        });
    }
    if facts.active_hunting_candidates > 0 {
        suggestions.push(CoachSuggestion {
            kind: "hunting_candidates".into(),
            title_key: "coachSuggestionHunting".into(),
            reason_key: "coachSuggestionHuntingReason".into(),
            action: "open_hunting".into(),
            evidence_source: "hunting_candidates".into(),
            evidence_count: facts.active_hunting_candidates,
        });
    }
    if facts.extensive_sessions > 0 {
        suggestions.push(CoachSuggestion {
            kind: "continue_listening".into(),
            title_key: "coachSuggestionContinue".into(),
            reason_key: "coachSuggestionContinueReason".into(),
            action: "close_dashboard".into(),
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
    let mut channels = vec![CoachChannelSummary {
        channel: "listening".into(),
        status: CoachChannelStatus::Available,
        unavailable_reason: None,
        metrics,
    }];
    for channel in ["reading", "speaking", "writing"] {
        channels.push(CoachChannelSummary {
            channel: channel.into(),
            status: CoachChannelStatus::Unassessed,
            unavailable_reason: Some("no_active_validation".into()),
            metrics: Vec::new(),
        });
    }
    CoachDashboard {
        period_start_ms: start,
        period_end_ms: end,
        generated_at_ms: generated,
        channels,
        suggestions,
        starter_checklist,
        materials,
    }
}

#[derive(Debug)]
pub struct DisabledCoachDashboardRepository;
impl crate::CoachDashboardRepository for DisabledCoachDashboardRepository {
    fn coach_dashboard_facts(
        &self,
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
