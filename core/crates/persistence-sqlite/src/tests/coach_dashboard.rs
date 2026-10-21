use super::*;
use application::CoachDashboardRepository;

#[test]
fn empty_database_returns_only_zeroed_listening_facts() {
    let repo = SqliteRepository::in_memory().unwrap();
    let facts = repo.coach_dashboard_facts(0, 10, 10).unwrap();

    assert_eq!(facts.practice_attempts, 0);
    assert_eq!(facts.review_attempts, 0);
    assert_eq!(facts.extensive_sessions, 0);
    assert_eq!(facts.active_hunting_candidates, 0);
    assert!(facts.materials.is_empty());
}

#[test]
fn coach_evidence_rejects_metrics_outside_the_listening_dashboard() {
    let repo = SqliteRepository::in_memory().unwrap();
    assert!(
        repo.coach_evidence("writing_attempts", 0, 10, 10, 0)
            .is_err()
    );
}

#[test]
fn graduation_display_and_confirmation_use_the_same_lifetime_material_facts() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let media = MediaItem {
        id: MediaId::parse("coach-lifetime-media").unwrap(),
        path: "/tmp/coach-lifetime.mp4".into(),
        fingerprint: "coach-lifetime-fingerprint".into(),
        title: "Lifetime listening evidence".into(),
        kind: MediaKind::Video,
        duration: Some(TimeMs::new(1_000)),
        availability: MediaAvailability::Available,
        retained_at_ms: None,
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    MediaRepository::upsert(repo.as_ref(), &media).unwrap();
    {
        let conn = repo.connection.lock();
        for (session_id, event_id, occurred_at_ms, report) in [
            ("coach-lifetime-a", "coach-event-a", 100_u64, "got_the_gist"),
            (
                "coach-lifetime-b",
                "coach-event-b",
                200_u64,
                "understood_all",
            ),
        ] {
            conn.execute(
                "INSERT INTO practice_sessions
                 (id,mode,media_id,started_at_ms,ended_at_ms,session_json)
                 VALUES (?1,'\"extensive\"',?2,?3,?4,'{}')",
                params![
                    session_id,
                    media.id.as_str(),
                    occurred_at_ms,
                    occurred_at_ms + 50
                ],
            )
            .unwrap();
            conn.execute(
                "INSERT INTO learning_events
                 (id,occurred_at_ms,kind,subject_kind,subject_id,session_id,event_json)
                 VALUES (?1,?2,'\"listening_completed\"','\"practice_session\"',?3,?3,?4)",
                params![
                    event_id,
                    occurred_at_ms,
                    session_id,
                    serde_json::json!({
                        "payload": {"comprehension_report": report}
                    })
                    .to_string()
                ],
            )
            .unwrap();
        }
    }

    let windowed = repo.coach_dashboard_facts(900, 1_000, 1_000).unwrap();
    assert_eq!(windowed.extensive_sessions, 0);
    assert_eq!(windowed.materials[0].report_count, 2);

    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_coach_dashboard_repository(repo.clone());
    let dashboard = services.media_analysis().coach_dashboard(1).unwrap();
    assert!(dashboard.materials[0].graduation_candidate);
    assert_eq!(dashboard.materials[0].report_count, 2);

    let graduated = services
        .media_analysis()
        .graduate_coach_material(&media.id)
        .unwrap();
    assert_eq!(graduated.triage_intent, Some(MediaTriageIntent::Graduated));
}
