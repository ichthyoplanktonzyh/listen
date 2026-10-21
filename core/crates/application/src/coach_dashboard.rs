use serde::Serialize;

use domain::{MediaId, MediaTriageIntent};

use crate::{
    ApplicationError, CoachDashboardFacts, CoachEvidenceFact, MediaAnalysisUseCases, now_ms,
};

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

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CoachDashboard {
    pub period_start_ms: u64,
    pub period_end_ms: u64,
    pub generated_at_ms: u64,
    /// This branch reports listening facts only. Other activity dimensions
    /// are absent until their implementations return.
    pub listening_metrics: Vec<CoachMetric>,
    pub suggestions: Vec<CoachSuggestion>,
    pub starter_checklist: Vec<String>,
    pub materials: Vec<CoachMaterialInsight>,
}

impl MediaAnalysisUseCases {
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
        media_id: &MediaId,
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
        self.set_media_triage_intent(media_id, Some(MediaTriageIntent::Graduated))
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
            .map(|facts| facts.into_iter().map(CoachEvidenceItem::from).collect())
    }
}

impl From<CoachEvidenceFact> for CoachEvidenceItem {
    fn from(fact: CoachEvidenceFact) -> Self {
        Self {
            id: fact.id,
            occurred_at_ms: fact.occurred_at_ms,
            result: fact.result,
            source_kind: fact.source_kind,
            snapshot: fact.snapshot,
            source_available: fact.source_available,
            unavailable_reason: fact.unavailable_reason,
        }
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

    let listening_metrics = [
        metric(
            "extensive_sessions",
            facts.extensive_sessions,
            "practice_sessions",
            "activity_fact",
        ),
        metric(
            "extensive_listening_ms",
            facts.extensive_listening_ms,
            "practice_sessions",
            "activity_fact",
        ),
        metric(
            "practice_attempts",
            facts.practice_attempts,
            "practice_attempts",
            "attempt",
        ),
        metric(
            "correct_practice_attempts",
            facts.correct_practice_attempts,
            "practice_attempts",
            "attempt",
        ),
        metric(
            "review_attempts",
            facts.review_attempts,
            "review_attempts",
            "review_fact",
        ),
        metric(
            "successful_review_attempts",
            facts.successful_review_attempts,
            "review_attempts",
            "review_fact",
        ),
        metric(
            "listening_capability_changes",
            facts.listening_capability_changes,
            "lexical_capability_history",
            "capability_history",
        ),
        metric(
            "l1_difficulty_hits",
            facts.l1_difficulty_hits,
            "learning_events",
            "activity_fact",
        ),
    ]
    .into_iter()
    .filter(|value| value.value > 0)
    .collect();

    let mut suggestions = Vec::new();
    if facts.due_review_items > 0 {
        suggestions.push(suggestion(
            "due-review",
            "due_review",
            "coachSuggestionReview",
            "coachSuggestionReviewReason",
            CoachSuggestionDestination::ReviewQueue,
            "review_schedules",
            facts.due_review_items,
        ));
    }
    if facts.active_hunting_candidates > 0 {
        suggestions.push(suggestion(
            "hunting-candidates",
            "hunting_candidates",
            "coachSuggestionHunting",
            "coachSuggestionHuntingReason",
            CoachSuggestionDestination::HuntingList,
            "hunting_candidates",
            facts.active_hunting_candidates,
        ));
    }
    if facts.extensive_sessions > 0 {
        suggestions.push(suggestion(
            "continue-listening",
            "continue_listening",
            "coachSuggestionContinue",
            "coachSuggestionContinueReason",
            CoachSuggestionDestination::ContentHome,
            "practice_sessions:extensive",
            facts.extensive_sessions,
        ));
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

    CoachDashboard {
        period_start_ms: start,
        period_end_ms: end,
        generated_at_ms: generated,
        listening_metrics,
        suggestions,
        starter_checklist,
        materials,
    }
}

fn metric(key: &str, value: u64, source: &str, authority_layer: &str) -> CoachMetric {
    CoachMetric {
        key: key.into(),
        value,
        source: source.into(),
        authority_layer: authority_layer.into(),
    }
}

fn suggestion(
    id: &str,
    kind: &str,
    title_key: &str,
    reason_key: &str,
    destination: CoachSuggestionDestination,
    evidence_source: &str,
    evidence_count: u64,
) -> CoachSuggestion {
    CoachSuggestion {
        id: id.into(),
        kind: kind.into(),
        title_key: title_key.into(),
        reason_key: reason_key.into(),
        destination,
        evidence_source: evidence_source.into(),
        evidence_count,
    }
}

#[derive(Debug)]
pub(crate) struct DisabledCoachDashboardRepository;
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
    ) -> Result<Vec<CoachEvidenceFact>, ApplicationError> {
        Ok(Vec::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn suggestions_are_derived_only_from_listening_facts() {
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
        assert_eq!(dashboard.suggestions[0].evidence_source, "review_schedules");
        assert!(dashboard.listening_metrics.is_empty());
    }

    #[test]
    fn material_graduation_requires_repeated_improvement_and_confirmation() {
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
