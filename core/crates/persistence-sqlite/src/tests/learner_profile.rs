use application::LearnerProfileRepository;

use super::*;

#[test]
fn learner_profile_round_trips_and_upserts() {
    let repo = SqliteRepository::in_memory().unwrap();
    let id = LearnerProfileId::parse("local-learner").unwrap();
    assert_eq!(repo.get_learner_profile(&id).unwrap(), None);

    let profile = LearnerProfile {
        id: id.clone(),
        ui_language: LanguageCode::parse("zh").unwrap(),
        l1_language: Some(LanguageCode::parse("zh").unwrap()),
        active_l2_language: None,
        created_at_ms: 10,
        updated_at_ms: 10,
    };
    repo.save_learner_profile(&profile).unwrap();
    assert_eq!(repo.get_learner_profile(&id).unwrap(), Some(profile));

    // Upsert keeps the row a singleton and can clear L1 back to None.
    let cleared = LearnerProfile {
        id: id.clone(),
        ui_language: LanguageCode::parse("en").unwrap(),
        l1_language: None,
        active_l2_language: None,
        created_at_ms: 10,
        updated_at_ms: 20,
    };
    repo.save_learner_profile(&cleared).unwrap();
    assert_eq!(repo.get_learner_profile(&id).unwrap(), Some(cleared));
}
