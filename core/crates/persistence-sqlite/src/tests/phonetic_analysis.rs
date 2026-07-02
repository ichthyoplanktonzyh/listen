use super::*;

#[test]
fn phonetic_models_jobs_analyses_and_feedback_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    let media = MediaItem {
        id: MediaId::from_fingerprint("media", "phonetic"),
        path: "/tmp/phonetic.wav".into(),
        fingerprint: "phonetic-media".into(),
        title: "Phonetic".into(),
        kind: MediaKind::Audio,
        duration: Some(TimeMs::new(5_000)),
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    MediaRepository::upsert(&repo, &media).unwrap();
    let sentence_id = SubtitleSentenceId::from_fingerprint("sentence", "phonetic");
    let track = SubtitleTrack {
        id: SubtitleTrackId::from_fingerprint("track", "phonetic"),
        media_id: media.id.clone(),
        fingerprint: "phonetic-track".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "test".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: sentence_id.clone(),
            index: 0,
            start: TimeMs::new(100),
            end: TimeMs::new(500),
            original_text: "Hello".into(),
            display_text: "Hello".into(),
            tokens: vec![],
        }],
    };
    repo.save_track(&track).unwrap();
    let model_id = PhoneticAnalysisModelId::from_fingerprint("model", "fake");
    let model = PhoneticAnalysisModelDescriptor {
        id: model_id.clone(),
        provider_id: "fake".into(),
        display_name: "Fake".into(),
        family: "fake".into(),
        revision: "v1".into(),
        checksum_sha256: "abc".into(),
        download_url: None,
        local_path: None,
        size_bytes: 0,
        supported_languages: vec!["en".into()],
        supported_dialects: vec!["en-US".into()],
        phone_sets: vec!["arpabet".into()],
        supports_timestamps: true,
        expected_sample_rate_hz: 16_000,
        context_window_ms: None,
        state: PhoneticModelState::Custom,
        installed_bytes: 0,
        error: None,
        license: "test".into(),
        training_data_provenance: "synthetic".into(),
        distribution_allowed: false,
        application_verified: false,
        updated_at_ms: 1,
    };
    repo.upsert_phonetic_model(&model).unwrap();
    assert_eq!(repo.get_phonetic_model(&model_id).unwrap(), Some(model));

    let job_id = PhoneticAnalysisJobId::from_fingerprint("job", "fake");
    let mut job = PhoneticAnalysisJob {
        id: job_id.clone(),
        media_id: media.id.clone(),
        track_id: track.id.clone(),
        sentence_id: Some(sentence_id.clone()),
        scope: PhoneticAnalysisScope::Sentence,
        audio_start_ms: 100,
        audio_end_ms: 500,
        provider_id: "fake".into(),
        provider_version: "v1".into(),
        runtime_id: "fake".into(),
        runtime_version: "v1".into(),
        model_id: model_id.clone(),
        model_revision: "v1".into(),
        model_checksum_sha256: "abc".into(),
        requested_phone_set: "arpabet".into(),
        settings_json: "{}".into(),
        input_fingerprint: "input".into(),
        status: PhoneticAnalysisJobStatus::Queued,
        phase_progress: 0,
        error_code: None,
        error_message: None,
        retry_of_job_id: None,
        analysis_id: None,
        created_at_ms: 1,
        started_at_ms: None,
        completed_at_ms: None,
        updated_at_ms: 1,
    };
    repo.create_phonetic_job(&job).unwrap();
    repo.interrupt_active_phonetic_jobs(2).unwrap();
    job = repo.get_phonetic_job(&job_id).unwrap().unwrap();
    assert_eq!(job.status, PhoneticAnalysisJobStatus::Interrupted);

    job.status = PhoneticAnalysisJobStatus::Completed;
    job.updated_at_ms = 3;
    let analysis_id = PhoneticAnalysisId::from_fingerprint("analysis", "fake");
    job.analysis_id = Some(analysis_id.clone());
    repo.update_phonetic_job(&job).unwrap();
    let finding_id = PhoneticFindingId::from_fingerprint("finding", "fake");
    let analysis = PhoneticAnalysis {
        id: analysis_id.clone(),
        job_id,
        media_id: media.id,
        track_id: track.id.clone(),
        sentence_id: Some(sentence_id),
        audio_start_ms: 100,
        audio_end_ms: 500,
        provider_id: "fake".into(),
        provider_version: "v1".into(),
        model_id,
        model_revision: "v1".into(),
        model_checksum_sha256: "abc".into(),
        phone_set: "arpabet".into(),
        detected_phones: vec![DetectedPhone {
            symbol: "HH".into(),
            display_ipa: "h".into(),
            phone_set: "arpabet".into(),
            start_ms: 100,
            end_ms: 200,
            confidence: Some(0.9),
            token_index: Some(0),
            provider_id: "fake".into(),
            provider_version: "v1".into(),
            model_revision: "v1".into(),
        }],
        alignments: vec![],
        findings: vec![PhoneticFinding {
            id: finding_id.clone(),
            analysis_id: analysis_id.clone(),
            finding_type: "weak_form".into(),
            affected_token_start: 0,
            affected_token_end: 0,
            canonical_phones: vec!["HH".into()],
            detected_phones: vec!["HH".into()],
            aligned_phone_start: Some(0),
            aligned_phone_end: Some(0),
            audio_start_ms: 100,
            audio_end_ms: 200,
            confidence: 0.7,
            evidence: "fake".into(),
            status: PhoneticFindingStatus::SupportedByAlignment,
        }],
        sound_analysis: None,
        analyzer_version: "v1".into(),
        created_at_ms: 3,
    };
    repo.save_phonetic_analysis(&analysis).unwrap();
    assert_eq!(
        repo.list_track_phonetic_analyses(&track.id).unwrap(),
        vec![analysis.clone()]
    );
    repo.delete_phonetic_model(&analysis.model_id).unwrap();
    assert_eq!(
        repo.list_track_phonetic_analyses(&track.id).unwrap(),
        vec![analysis.clone()]
    );
    let mut revised_analysis = analysis.clone();
    revised_analysis.id = PhoneticAnalysisId::from_fingerprint("analysis", "fake-v2");
    for finding in &mut revised_analysis.findings {
        finding.id = PhoneticFindingId::from_fingerprint("finding", "fake-v2");
        finding.analysis_id = revised_analysis.id.clone();
    }
    revised_analysis.model_revision = "v2".into();
    revised_analysis.created_at_ms = 4;
    repo.save_phonetic_analysis(&revised_analysis).unwrap();
    let versions = repo.list_track_phonetic_analyses(&track.id).unwrap();
    assert_eq!(versions.len(), 2);
    assert!(versions.contains(&analysis));
    assert!(versions.contains(&revised_analysis));
    let feedback = PhoneticFindingFeedback {
        finding_id: finding_id.clone(),
        value: PhoneticFindingFeedbackValue::Rejected,
        note: Some("test".into()),
        updated_at_ms: 4,
    };
    repo.save_phonetic_feedback(&feedback).unwrap();
    assert_eq!(
        repo.get_phonetic_feedback(&finding_id).unwrap(),
        Some(feedback.clone())
    );
    let bundle = repo.export_assets().unwrap();
    assert_eq!(bundle.version, 5);
    assert_eq!(bundle.phonetic_finding_feedback, vec![feedback.clone()]);
    let restored = SqliteRepository::in_memory().unwrap();
    restored.import_assets(&bundle).unwrap();
    assert_eq!(
        restored.get_phonetic_feedback(&finding_id).unwrap(),
        Some(feedback)
    );
}
