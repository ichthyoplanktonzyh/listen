use super::*;
use application::MaterialRepository;

#[test]
fn activating_word_timeline_updates_active_resource_and_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let older = word_timeline(
        "timeline-1",
        &track,
        TimelineStatus::Active,
        "whisper-dtw",
        120,
        300,
    );
    let newer = word_timeline(
        "timeline-2",
        &track,
        TimelineStatus::Candidate,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&older).unwrap();
    repo.save_word_timeline(&newer).unwrap();

    let active = repo.activate_word_timeline(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_word_timeline(&track.id).unwrap().unwrap().id,
        newer.id
    );
    assert_eq!(
        repo.get_word_timeline(&older.id).unwrap().unwrap().status,
        TimelineStatus::Candidate
    );

    let compatibility_timings = repo.get_word_timings(&sentence_id).unwrap();
    assert_eq!(compatibility_timings.len(), 1);
    assert_eq!(compatibility_timings[0].provider_id, "mms-fa");
    assert_eq!(compatibility_timings[0].start_ms, 150);
    assert_eq!(compatibility_timings[0].end_ms, 260);
}

#[test]
fn activating_word_timeline_if_absent_activates_candidate_and_updates_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let candidate = word_timeline(
        "timeline-if-absent",
        &track,
        TimelineStatus::Candidate,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&candidate).unwrap();

    let active = repo
        .activate_word_timeline_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, candidate.id);
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_word_timeline(&track.id).unwrap().unwrap().id,
        candidate.id
    );
    let compatibility_timings = repo.get_word_timings(&sentence_id).unwrap();
    assert_eq!(compatibility_timings.len(), 1);
    assert_eq!(compatibility_timings[0].provider_id, "mms-fa");
}

#[test]
fn activating_word_timeline_if_absent_preserves_existing_active_and_legacy_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let existing = word_timeline(
        "timeline-existing-active",
        &track,
        TimelineStatus::Candidate,
        "user-selected",
        120,
        300,
    );
    let candidate = word_timeline(
        "timeline-foundation-candidate",
        &track,
        TimelineStatus::Candidate,
        "foundation",
        150,
        260,
    );
    repo.save_word_timeline(&existing).unwrap();
    repo.activate_word_timeline(&existing.id).unwrap();
    repo.save_word_timeline(&candidate).unwrap();

    let active = repo
        .activate_word_timeline_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, existing.id);
    assert_eq!(
        repo.get_word_timeline(&candidate.id)
            .unwrap()
            .unwrap()
            .status,
        TimelineStatus::Candidate
    );
    let compatibility_timings = repo.get_word_timings(&sentence_id).unwrap();
    assert_eq!(compatibility_timings.len(), 1);
    assert_eq!(compatibility_timings[0].provider_id, "user-selected");
}

#[test]
fn timeline_active_uniqueness_is_schema_enforced() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();

    let word_active = word_timeline(
        "timeline-active-unique-1",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    let word_duplicate = word_timeline(
        "timeline-active-unique-2",
        &track,
        TimelineStatus::Active,
        "whisper-dtw",
        180,
        290,
    );
    repo.save_word_timeline(&word_active).unwrap();
    assert!(repo.save_word_timeline(&word_duplicate).is_err());

    let phone_active = phone_timeline(
        "phone-active-unique-1",
        &track,
        &word_active,
        TimelineStatus::Active,
    );
    let phone_duplicate = phone_timeline(
        "phone-active-unique-2",
        &track,
        &word_active,
        TimelineStatus::Active,
    );
    repo.save_phone_timeline(&phone_active).unwrap();
    assert!(repo.save_phone_timeline(&phone_duplicate).is_err());

    let sg_active = sense_group_analysis("sg-active-unique-1", &track, TimelineStatus::Active);
    let sg_duplicate = sense_group_analysis("sg-active-unique-2", &track, TimelineStatus::Active);
    repo.save_sense_group_analysis(&sg_active).unwrap();
    assert!(repo.save_sense_group_analysis(&sg_duplicate).is_err());

    let prosody_active =
        prosody_analysis("prosody-active-unique-1", &track, TimelineStatus::Active);
    let prosody_duplicate =
        prosody_analysis("prosody-active-unique-2", &track, TimelineStatus::Active);
    repo.save_prosody_analysis(&prosody_active).unwrap();
    assert!(repo.save_prosody_analysis(&prosody_duplicate).is_err());
}

#[test]
fn archiving_active_word_timeline_clears_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let timeline = word_timeline(
        "timeline-archive-active",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&timeline).unwrap();
    repo.activate_word_timeline(&timeline.id).unwrap();

    let archived = repo.archive_word_timeline(&timeline.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    assert!(repo.active_word_timeline(&track.id).unwrap().is_none());
    assert!(repo.get_word_timings(&sentence_id).unwrap().is_empty());
}

#[test]
fn deleting_active_word_timeline_clears_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let timeline = word_timeline(
        "timeline-delete-active",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&timeline).unwrap();
    repo.activate_word_timeline(&timeline.id).unwrap();

    let deleted = repo.delete_word_timeline(&timeline.id).unwrap();
    assert_eq!(deleted.id, timeline.id);
    assert!(repo.get_word_timeline(&timeline.id).unwrap().is_none());
    assert!(repo.active_word_timeline(&track.id).unwrap().is_none());
    assert!(repo.get_word_timings(&sentence_id).unwrap().is_empty());
}

#[test]
fn activating_phone_timeline_updates_active_resource() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let parent = word_timeline(
        "timeline-parent-phone",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&parent).unwrap();
    let older = phone_timeline("phone-timeline-1", &track, &parent, TimelineStatus::Active);
    let newer = phone_timeline(
        "phone-timeline-2",
        &track,
        &parent,
        TimelineStatus::Candidate,
    );
    repo.save_phone_timeline(&older).unwrap();
    repo.save_phone_timeline(&newer).unwrap();

    let active = repo.activate_phone_timeline(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_phone_timeline(&track.id).unwrap().unwrap().id,
        newer.id
    );
    assert_eq!(
        repo.get_phone_timeline(&older.id).unwrap().unwrap().status,
        TimelineStatus::Candidate
    );
    assert_eq!(repo.list_phone_timelines(&track.id).unwrap().len(), 2);
}

#[test]
fn archiving_and_deleting_phone_timeline_updates_repository() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let parent = word_timeline(
        "timeline-parent-phone-delete",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&parent).unwrap();
    let timeline = phone_timeline(
        "phone-timeline-delete",
        &track,
        &parent,
        TimelineStatus::Candidate,
    );
    repo.save_phone_timeline(&timeline).unwrap();

    let archived = repo.archive_phone_timeline(&timeline.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    let deleted = repo.delete_phone_timeline(&timeline.id).unwrap();
    assert_eq!(deleted.id, timeline.id);
    assert!(repo.get_phone_timeline(&timeline.id).unwrap().is_none());
}

#[test]
fn lltimeline_resource_metadata_and_artifacts_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let metadata = LLTimelineMetadata {
        created_at_ms: 42,
        generator: LLTimelineGenerator {
            id: "fixture-production-engine".into(),
            version: "v2".into(),
            mode: "production_engine".into(),
        },
        media: LLTimelineMedia {
            id: track.media_id.clone(),
            fingerprint: "media-fingerprint".into(),
            path: None,
            title: "Fixture".into(),
            duration_ms: Some(1200),
        },
        language: track.language.clone(),
        human_reviewed: true,
        extra: serde_json::json!({"track_source": "fixture.lltimeline.json"}),
    };
    let artifacts = vec![LLTimelineArtifact {
        kind: "production_report".into(),
        provider_id: Some("fixture-production-engine".into()),
        provider_version: Some("v2".into()),
        payload: serde_json::json!({"readiness": "ready"}),
    }];

    repo.save_lltimeline_resource(&track.id, &metadata, &artifacts)
        .unwrap();

    let (saved_metadata, saved_artifacts) = repo
        .get_lltimeline_resource(&track.id)
        .unwrap()
        .expect("resource metadata should be saved");
    assert_eq!(saved_metadata.generator.id, "fixture-production-engine");
    assert!(saved_metadata.human_reviewed);
    assert_eq!(saved_artifacts.len(), 1);
    assert_eq!(saved_artifacts[0].kind, "production_report");
}

// End-to-end for the C / Audible-Structure ingest -> interpret chain: a package's
// observed phones, frame-level acoustic track, and speech-activity spans, once
// persisted the way `project_package_candidates` lands them, must flow through
// `export_lltimeline_document` into each sentence's RhythmFrame:
//   * observed phones light phone evidence (Reference C plumbing),
//   * frame-level energy (with no Gen cues) derives a prominence cue,
//   * a measured silence corroborates a boundary the detector already found,
// while a sentence with no observed phones stays on the phone-less path with zero
// phone-evidence coverage. This guards the whole projection+interpretation seam,
// not just the unit-level builders.
#[test]
fn export_lltimeline_lights_audible_structure_evidence_from_ingested_package() {
    let (repo, media) = lltimeline_import_services();
    MediaRepository::upsert(repo.as_ref(), &transcription_media()).unwrap();

    // sentence-a "go now": a 120 ms pause gap (80..200) yields one boundary at
    // 200 ms. sentence-b "again": the control, with no observed phones.
    let track = SubtitleTrack {
        id: SubtitleTrackId::parse("track-1").unwrap(),
        media_id: MediaId::parse("media-1").unwrap(),
        fingerprint: "track-fp".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "test".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![
            SubtitleSentence {
                id: SubtitleSentenceId::parse("sentence-a").unwrap(),
                index: 0,
                start: TimeMs::new(0),
                end: TimeMs::new(400),
                original_text: "go now".into(),
                display_text: "go now".into(),
                tokens: vec![
                    SubtitleToken {
                        index: 0,
                        kind: SubtitleTokenKind::Word,
                        text: "go".into(),
                        normalized: Some("go".into()),
                        start_char: 0,
                        end_char: 2,
                    },
                    SubtitleToken {
                        index: 1,
                        kind: SubtitleTokenKind::Word,
                        text: "now".into(),
                        normalized: Some("now".into()),
                        start_char: 3,
                        end_char: 6,
                    },
                ],
            },
            SubtitleSentence {
                id: SubtitleSentenceId::parse("sentence-b").unwrap(),
                index: 1,
                start: TimeMs::new(1000),
                end: TimeMs::new(1400),
                original_text: "again".into(),
                display_text: "again".into(),
                tokens: vec![SubtitleToken {
                    index: 0,
                    kind: SubtitleTokenKind::Word,
                    text: "again".into(),
                    normalized: Some("again".into()),
                    start_char: 0,
                    end_char: 5,
                }],
            },
        ],
    };
    repo.save_track(&track).unwrap();

    let word_timing = |sentence: &str, token_index: u32, text: &str, start_ms: u64, end_ms: u64| {
        WordTiming {
            sentence_id: SubtitleSentenceId::parse(sentence).unwrap(),
            token_index,
            text: text.into(),
            start_ms,
            end_ms,
            confidence: Some(0.9),
            timing_source: TimingSource::ForcedAligned,
            provider_id: "forced-aligner".into(),
            provider_version: "v1".into(),
        }
    };
    let word_timeline = WordTimeline {
        id: WordTimelineId::parse("word-timeline-1").unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        algorithm_id: "forced-aligner".into(),
        algorithm_version: "v1".into(),
        config_hash: "cfg".into(),
        parent_timeline_id: None,
        created_by: TimelineCreator::Algorithm,
        status: TimelineStatus::Active,
        metrics_json: serde_json::json!({}).into(),
        words: vec![
            word_timing("sentence-a", 0, "go", 0, 80),
            word_timing("sentence-a", 1, "now", 200, 360),
            word_timing("sentence-b", 0, "again", 1000, 1300),
        ],
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    repo.save_word_timeline(&word_timeline).unwrap();

    // Observed phones for sentence-a only, shipped as IPA the way Gen's wav2vec2
    // phone adapter does; Core maps them to its ARPABET-internal pipeline.
    let ipa = |symbol: &str, token_index: u32, start_ms: u64, end_ms: u64| DetectedPhone {
        symbol: symbol.into(),
        display_ipa: symbol.into(),
        phone_set: "ipa".into(),
        start_ms,
        end_ms,
        confidence: Some(0.8),
        token_index: Some(token_index),
        provider_id: "wav2vec2-ctc-phoneme".into(),
        provider_version: "fb-espeak-v1".into(),
        model_revision: "main".into(),
    };
    let phone_timeline = PhoneTimeline {
        id: PhoneTimelineId::parse("phone-timeline-1").unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        sentence_id: Some(SubtitleSentenceId::parse("sentence-a").unwrap()),
        parent_word_timeline_id: Some(word_timeline.id.clone()),
        parent_phonetic_analysis_id: None,
        provider_id: "wav2vec2-ctc-phoneme".into(),
        provider_version: "fb-espeak-v1".into(),
        model_id: Some(PhoneticAnalysisModelId::parse("wav2vec2-ctc-phoneme:espeak@v1").unwrap()),
        model_revision: Some("main".into()),
        phone_set: "ipa".into(),
        precision: PhoneTimelinePrecision::Approximate,
        created_by: TimelineCreator::Algorithm,
        status: TimelineStatus::Active,
        metrics_json: serde_json::json!({}).into(),
        phones: vec![
            ipa("g", 0, 0, 40),
            ipa("oʊ", 0, 40, 80),
            ipa("n", 1, 200, 260),
            ipa("aʊ", 1, 260, 360),
        ],
        alignments: Vec::new(),
        findings: Vec::new(),
        sound_analysis: None,
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    repo.save_phone_timeline(&phone_timeline).unwrap();

    // Frame-level acoustic track (energy only, F0 absent — exactly what the
    // baseline adapter ships without praat) and speech/silence spans, sliced to
    // sentence-a the way `project_acoustic_track` / `project_speech_activity` do.
    let mut frames = Vec::new();
    for time_ms in [0, 20, 40, 60] {
        frames.push(serde_json::json!({"time_ms": time_ms, "energy_rel_db": -6.0}));
    }
    for time_ms in [200, 220, 240, 260, 300, 340] {
        frames.push(serde_json::json!({"time_ms": time_ms, "energy_rel_db": 6.0}));
    }
    let metadata = LLTimelineMetadata {
        created_at_ms: 1,
        generator: LLTimelineGenerator {
            id: "test".into(),
            version: "v1".into(),
            mode: "production_engine".into(),
        },
        media: LLTimelineMedia {
            id: track.media_id.clone(),
            fingerprint: "media-fp".into(),
            path: None,
            title: "Media".into(),
            duration_ms: Some(1400),
        },
        language: track.language.clone(),
        human_reviewed: false,
        extra: serde_json::json!({}),
    };
    let artifacts = vec![
        LLTimelineArtifact {
            kind: "rhythm_acoustic_track".into(),
            provider_id: Some("gen-baseline".into()),
            provider_version: Some("v1".into()),
            payload: serde_json::json!({
                "sentences": [{"sentence_id": "sentence-a", "frames": frames}]
            }),
        },
        LLTimelineArtifact {
            kind: "rhythm_speech_activity".into(),
            provider_id: Some("gen-baseline".into()),
            provider_version: Some("v1".into()),
            payload: serde_json::json!({
                "sentences": [{"sentence_id": "sentence-a", "spans": [
                    {"start_ms": 0, "end_ms": 80, "activity": "speech"},
                    {"start_ms": 80, "end_ms": 200, "activity": "silence"},
                    {"start_ms": 200, "end_ms": 360, "activity": "speech"}
                ]}]
            }),
        },
    ];
    repo.save_lltimeline_resource(&track.id, &metadata, &artifacts)
        .unwrap();

    let document = media.export_lltimeline_document(&track.id).unwrap();
    let frame_a = document
        .rhythm_frames
        .iter()
        .find(|frame| frame.sentence_id.as_str() == "sentence-a")
        .expect("sentence-a rhythm frame")
        .rhythm_frame
        .clone();
    let frame_b = document
        .rhythm_frames
        .iter()
        .find(|frame| frame.sentence_id.as_str() == "sentence-b")
        .expect("sentence-b rhythm frame")
        .rhythm_frame
        .clone();

    // Observed phones flowed through build_sound_analysis: sentence-a carries
    // phone evidence; sentence-b, with none ingested, stays on the phone-less
    // path with zero coverage.
    assert!(
        frame_a.quality.phone_evidence_coverage > 0.0,
        "ingested observed phones must light phone evidence for sentence-a"
    );
    assert_eq!(
        frame_b.quality.phone_evidence_coverage, 0.0,
        "a sentence with no observed phones must keep zero phone coverage"
    );

    // Frame-level energy (no Gen cues present) derived a prominence cue.
    assert!(
        frame_a
            .quality
            .prominence_sources
            .contains(&domain::RhythmSignalSource::Energy),
        "acoustic-track energy must derive an energy prominence source"
    );

    // The measured silence corroborated the one detected pause boundary, adding a
    // `measured_silence` cue and Timing provenance — never inventing a boundary.
    let corroborated = frame_a
        .phrase_boundaries
        .iter()
        .find(|boundary| boundary.cues.iter().any(|cue| cue == "measured_silence"))
        .expect("a boundary must gain the measured_silence cue");
    assert!(
        corroborated
            .signal_sources
            .contains(&domain::RhythmSignalSource::Timing),
        "a measured-silence boundary must record Timing provenance"
    );
}

fn sense_group_analysis(
    id: &str,
    track: &SubtitleTrack,
    status: TimelineStatus,
) -> SenseGroupAnalysis {
    SenseGroupAnalysis {
        id: SenseGroupAnalysisId::parse(id).unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        parent_word_timeline_id: None,
        provider_id: "rule-based-sense-group".into(),
        provider_version: "v1".into(),
        algorithm: "punctuation_length_rule_v1".into(),
        status,
        created_by: TimelineCreator::Algorithm,
        metrics_json: serde_json::json!({}).into(),
        groups: vec![SenseGroup {
            id: SenseGroupId::parse(format!("{id}-sg-1")).unwrap(),
            sentence_id: track.sentences[0].id.clone(),
            group_index: 0,
            start_token_index: 0,
            end_token_index: 0,
            text: "hello".into(),
            label: None,
            head_token_index: None,
            confidence: 0.5,
            sources: vec![SenseGroupSource::Rule],
        }],
        created_at_ms: 1,
        updated_at_ms: 1,
    }
}

#[test]
fn activating_sense_group_analysis_updates_active_resource() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let older = sense_group_analysis("sg-analysis-1", &track, TimelineStatus::Active);
    let newer = sense_group_analysis("sg-analysis-2", &track, TimelineStatus::Candidate);
    repo.save_sense_group_analysis(&older).unwrap();
    repo.save_sense_group_analysis(&newer).unwrap();

    let active = repo.activate_sense_group_analysis(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_sense_group_analysis(&track.id)
            .unwrap()
            .unwrap()
            .id,
        newer.id
    );
    assert_eq!(
        repo.get_sense_group_analysis(&older.id)
            .unwrap()
            .unwrap()
            .status,
        TimelineStatus::Candidate
    );
    assert_eq!(repo.list_sense_group_analyses(&track.id).unwrap().len(), 2);
}

#[test]
fn activating_sense_group_analysis_if_absent_activates_candidate() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let candidate =
        sense_group_analysis("sg-analysis-if-absent", &track, TimelineStatus::Candidate);
    repo.save_sense_group_analysis(&candidate).unwrap();

    let active = repo
        .activate_sense_group_analysis_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, candidate.id);
    assert_eq!(active.status, TimelineStatus::Active);
}

#[test]
fn activating_sense_group_analysis_if_absent_preserves_existing_active() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let existing = sense_group_analysis(
        "sg-analysis-existing-active",
        &track,
        TimelineStatus::Active,
    );
    let candidate = sense_group_analysis(
        "sg-analysis-foundation-candidate",
        &track,
        TimelineStatus::Candidate,
    );
    repo.save_sense_group_analysis(&existing).unwrap();
    repo.save_sense_group_analysis(&candidate).unwrap();

    let active = repo
        .activate_sense_group_analysis_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, existing.id);
    assert_eq!(
        repo.get_sense_group_analysis(&candidate.id)
            .unwrap()
            .unwrap()
            .status,
        TimelineStatus::Candidate
    );
}

#[test]
fn rule_and_syntax_sense_group_providers_keep_independent_runs() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let rule = sense_group_analysis("sg-rule-v1", &track, TimelineStatus::Candidate);
    let mut syntax = sense_group_analysis("sg-syntax-v1", &track, TimelineStatus::Candidate);
    syntax.provider_id = "syntax-aware-sense-group".into();
    syntax.provider_version = "v1".into();
    syntax.algorithm = "dependency_teaching_partition_v1".into();
    syntax.metrics_json = serde_json::json!({
        "syntactic_analysis_id": "syntax-artifact-1",
        "chunk_timeline_dependency": false
    })
    .into();
    repo.save_sense_group_analysis(&rule).unwrap();
    repo.save_sense_group_analysis(&syntax).unwrap();

    let runs = repo.list_sense_group_analyses(&track.id).unwrap();
    assert_eq!(runs.len(), 2);
    assert!(
        runs.iter()
            .any(|run| run.provider_id == "rule-based-sense-group")
    );
    assert!(runs.iter().any(|run| {
        let metrics = run.metrics_json.as_object();
        run.provider_id == "syntax-aware-sense-group"
            && metrics
                .get("syntactic_analysis_id")
                .and_then(|value| value.as_str())
                == Some("syntax-artifact-1")
            && metrics
                .get("chunk_timeline_dependency")
                .and_then(|value| value.as_bool())
                == Some(false)
    }));
}

#[test]
fn archiving_and_deleting_sense_group_analysis_updates_repository() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let analysis = sense_group_analysis("sg-analysis-delete", &track, TimelineStatus::Candidate);
    repo.save_sense_group_analysis(&analysis).unwrap();

    let archived = repo.archive_sense_group_analysis(&analysis.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    let deleted = repo.delete_sense_group_analysis(&analysis.id).unwrap();
    assert_eq!(deleted.id, analysis.id);
    assert!(
        repo.get_sense_group_analysis(&analysis.id)
            .unwrap()
            .is_none()
    );
}

#[test]
fn sense_group_analysis_json_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();

    let mut analysis = sense_group_analysis("sg-roundtrip", &track, TimelineStatus::Candidate);
    analysis.groups.push(SenseGroup {
        id: SenseGroupId::parse("sg-roundtrip-sg-2").unwrap(),
        sentence_id: track.sentences[0].id.clone(),
        group_index: 1,
        start_token_index: 1,
        end_token_index: 3,
        text: "round trip test".into(),
        label: Some("NP".into()),
        head_token_index: Some(2),
        confidence: 0.8,
        sources: vec![SenseGroupSource::Punctuation, SenseGroupSource::LengthLimit],
    });
    repo.save_sense_group_analysis(&analysis).unwrap();

    let loaded = repo
        .get_sense_group_analysis(&analysis.id)
        .unwrap()
        .expect("analysis should be saved");
    assert_eq!(loaded.id, analysis.id);
    assert_eq!(loaded.provider_id, "rule-based-sense-group");
    assert_eq!(loaded.algorithm, "punctuation_length_rule_v1");
    assert_eq!(loaded.groups.len(), 2);
    assert_eq!(loaded.groups[0].text, "hello");
    assert_eq!(loaded.groups[1].text, "round trip test");
    assert_eq!(loaded.groups[1].label, Some("NP".into()));
    assert_eq!(
        loaded.groups[1].sources,
        vec![SenseGroupSource::Punctuation, SenseGroupSource::LengthLimit]
    );
}

fn prosody_analysis(id: &str, track: &SubtitleTrack, status: TimelineStatus) -> ProsodyAnalysis {
    ProsodyAnalysis {
        id: ProsodyAnalysisId::parse(id).unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        parent_word_timeline_id: None,
        provider_id: "listen-gen".into(),
        provider_version: "0.1.0".into(),
        algorithm: "prosody-v1".into(),
        status,
        created_by: TimelineCreator::Algorithm,
        metrics_json: serde_json::json!({}).into(),
        chunks: vec![domain::ProsodicChunk {
            sentence_id: track.sentences[0].id.clone(),
            chunk_index: 0,
            start_token_index: 0,
            end_token_index: 0,
            nucleus_token_index: Some(0),
            confidence: 0.9,
        }],
        anchors: vec![ProsodyAnchor {
            word_ref: ProsodyWordRef {
                sentence_id: track.sentences[0].id.clone(),
                token_index: 0,
            },
            syllable_index: None,
            lexical_stress: LexicalStress::Primary,
            realized_prominence: 0.8,
            utterance_role: UtteranceRole::Nucleus,
            evidence: vec![ProsodyEvidence::Energy, ProsodyEvidence::Pitch],
            confidence: 0.9,
        }],
        created_at_ms: 1,
        updated_at_ms: 1,
    }
}

#[test]
fn activating_prosody_analysis_updates_active_resource() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let older = prosody_analysis("prosody-analysis-1", &track, TimelineStatus::Active);
    let newer = prosody_analysis("prosody-analysis-2", &track, TimelineStatus::Candidate);
    repo.save_prosody_analysis(&older).unwrap();
    repo.save_prosody_analysis(&newer).unwrap();

    let active = repo.activate_prosody_analysis(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_prosody_analysis(&track.id).unwrap().unwrap().id,
        newer.id
    );
    assert_eq!(
        repo.get_prosody_analysis(&older.id)
            .unwrap()
            .unwrap()
            .status,
        TimelineStatus::Candidate
    );
    assert_eq!(repo.list_prosody_analyses(&track.id).unwrap().len(), 2);
}

#[test]
fn archiving_and_deleting_prosody_analysis_updates_repository() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let analysis = prosody_analysis("prosody-analysis-delete", &track, TimelineStatus::Candidate);
    repo.save_prosody_analysis(&analysis).unwrap();

    let archived = repo.archive_prosody_analysis(&analysis.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    assert!(repo.activate_prosody_analysis(&analysis.id).is_err());
    let deleted = repo.delete_prosody_analysis(&analysis.id).unwrap();
    assert_eq!(deleted.id, analysis.id);
    assert!(repo.get_prosody_analysis(&analysis.id).unwrap().is_none());
}

#[test]
fn prosody_analysis_json_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();

    let mut analysis = prosody_analysis("prosody-roundtrip", &track, TimelineStatus::Candidate);
    analysis.anchors.push(ProsodyAnchor {
        word_ref: ProsodyWordRef {
            sentence_id: track.sentences[0].id.clone(),
            token_index: 1,
        },
        syllable_index: Some(0),
        lexical_stress: LexicalStress::Secondary,
        realized_prominence: 0.4,
        utterance_role: UtteranceRole::Prenuclear,
        evidence: vec![ProsodyEvidence::Duration],
        confidence: 0.7,
    });
    repo.save_prosody_analysis(&analysis).unwrap();

    let loaded = repo
        .get_prosody_analysis(&analysis.id)
        .unwrap()
        .expect("analysis should be saved");
    assert_eq!(loaded.id, analysis.id);
    assert_eq!(loaded.provider_id, "listen-gen");
    assert_eq!(loaded.anchors.len(), 2);
    assert_eq!(loaded.anchors[0].utterance_role, UtteranceRole::Nucleus);
    assert_eq!(
        loaded.anchors[0].evidence,
        vec![ProsodyEvidence::Energy, ProsodyEvidence::Pitch]
    );
    assert_eq!(loaded.anchors[1].lexical_stress, LexicalStress::Secondary);
    assert_eq!(loaded.anchors[1].syllable_index, Some(0));
}

fn lltimeline_fixture() -> LLTimelineDocument {
    serde_json::from_str(include_str!(
        "../../../../testdata/lltimeline/v1-minimal.lltimeline.json"
    ))
    .unwrap()
}

fn lltimeline_import_services() -> (Arc<SqliteRepository>, application::MediaAnalysisUseCases) {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
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
    .with_corpus_index_repository(repo.clone());
    (repo, services.media_analysis())
}

fn assert_no_lltimeline_import_rows(repo: &SqliteRepository) {
    let connection = repo.connection.lock();
    for table in [
        "media_items",
        "subtitle_tracks",
        "subtitle_sentences",
        "lltimeline_resources",
        "word_timeline_runs",
        "phone_timeline_runs",
        "sense_group_analysis_runs",
        "prosody_analysis_runs",
        "corpus_occurrences",
        // The media registration and its canonical material graph commit with
        // the import: a failed import leaves no graph rows either.
        "learning_materials",
        "material_revisions",
        "material_media_renditions",
        "material_media_bindings",
    ] {
        let count = connection
            .query_row(&format!("SELECT count(*) FROM {table}"), [], |row| {
                row.get::<_, u64>(0)
            })
            .unwrap();
        assert_eq!(count, 0, "{table} must remain empty after failed import");
    }
}

fn table_count(repo: &SqliteRepository, table: &str) -> u64 {
    repo.connection
        .lock()
        .query_row(&format!("SELECT count(*) FROM {table}"), [], |row| {
            row.get::<_, u64>(0)
        })
        .unwrap()
}

#[test]
fn lltimeline_import_creates_media_and_its_material_graph_atomically() {
    let (repo, media) = lltimeline_import_services();
    media
        .import_lltimeline_document(lltimeline_fixture())
        .unwrap();

    // The detached media creation and its canonical material graph commit in
    // the same transaction, resolving through the public media->material query
    // immediately after import.
    let media_item = repo
        .get(&MediaId::parse("media-fixture").unwrap())
        .unwrap()
        .expect("import creates the media row");
    let material = repo
        .material_for_media(&media_item.id)
        .unwrap()
        .expect("import creates the material graph");
    assert_eq!(material.retained_at_ms, media_item.retained_at_ms);
    assert_eq!(material.created_at_ms, media_item.created_at_ms);
    assert_eq!(material.updated_at_ms, media_item.updated_at_ms);

    // Exactly one deterministic graph: one material, one initial revision, one
    // rendition, one binding, and the stored rendition never carries a path.
    assert_eq!(table_count(&repo, "learning_materials"), 1);
    assert_eq!(table_count(&repo, "material_revisions"), 1);
    assert_eq!(table_count(&repo, "material_media_renditions"), 1);
    assert_eq!(table_count(&repo, "material_media_bindings"), 1);
    let revision = repo
        .get_revision(&material.current_revision_id)
        .unwrap()
        .expect("initial revision stored");
    let assets = revision.renditions;
    assert_eq!(assets.len(), 1);
    assert!(matches!(assets.first(), Some(domain::Rendition::Media(_))));
    let asset_json = serde_json::to_string(&assets[0]).unwrap();
    assert!(
        !asset_json.contains("\"path\""),
        "the rendition asset must never carry a path: {asset_json}"
    );
}

#[test]
fn lltimeline_media_graph_failure_rolls_back_the_whole_import() {
    let (repo, media) = lltimeline_import_services();
    // Fail the material graph write inside the import's transaction: the media
    // row, subtitle resources, timelines, and corpus projection must all roll
    // back together with the graph.
    repo.connection
        .lock()
        .execute_batch(
            "CREATE TRIGGER fail_import BEFORE INSERT ON learning_materials
             BEGIN SELECT RAISE(ABORT, 'injected LLTimeline graph failure'); END;",
        )
        .unwrap();

    assert!(
        media
            .import_lltimeline_document(lltimeline_fixture())
            .is_err(),
        "a material graph failure must reach the caller"
    );
    assert_no_lltimeline_import_rows(&repo);
}

#[test]
fn lltimeline_validation_failures_happen_before_any_durable_write() {
    let mut cases = Vec::new();

    let mut wrong_source = lltimeline_fixture();
    wrong_source.word_timelines[0].track_id = SubtitleTrackId::parse("wrong-track").unwrap();
    cases.push(wrong_source);

    let mut missing_parent = lltimeline_fixture();
    missing_parent.word_timelines[0].parent_timeline_id =
        Some(WordTimelineId::parse("missing-parent").unwrap());
    cases.push(missing_parent);

    let mut missing_active = lltimeline_fixture();
    missing_active.active_word_timeline_id = Some(WordTimelineId::parse("missing-active").unwrap());
    cases.push(missing_active);

    for document in cases {
        let (repo, media) = lltimeline_import_services();
        assert!(media.import_lltimeline_document(document).is_err());
        assert_no_lltimeline_import_rows(&repo);
    }
}

#[test]
fn lltimeline_repository_and_reindex_failures_roll_back_the_whole_import() {
    for (table, operation) in [
        ("lltimeline_resources", "INSERT"),
        ("word_timeline_runs", "INSERT"),
        ("corpus_occurrences", "INSERT"),
    ] {
        let (repo, media) = lltimeline_import_services();
        repo.connection
            .lock()
            .execute_batch(&format!(
                "CREATE TRIGGER fail_import BEFORE {operation} ON {table}
                 BEGIN SELECT RAISE(ABORT, 'injected LLTimeline import failure'); END;"
            ))
            .unwrap();

        assert!(
            media
                .import_lltimeline_document(lltimeline_fixture())
                .is_err(),
            "{table} failure must reach the caller"
        );
        assert_no_lltimeline_import_rows(&repo);
    }
}

fn corpus_snapshot(repo: &SqliteRepository) -> Vec<String> {
    let connection = repo.connection.lock();
    let mut statement = connection
        .prepare(
            "SELECT json_object(
               'id',id,'language',language,'kind',kind,'normalized_key',normalized_key,
               'display_text',display_text,'media_id',media_id,'track_id',track_id,
               'sentence_id',sentence_id,'start_ms',start_ms,'end_ms',end_ms,
               'source_snapshot',source_snapshot
             )
             FROM corpus_occurrences ORDER BY id",
        )
        .unwrap();
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
}

#[test]
fn lltimeline_import_rebuilds_legacy_word_timings_and_canonical_corpus() {
    let (repo, media) = lltimeline_import_services();
    let track = media
        .import_lltimeline_document(lltimeline_fixture())
        .unwrap();
    let active = repo
        .active_word_timeline(&track.id)
        .unwrap()
        .expect("fixture has an active word timeline");
    let sentence_id = track.sentences[0].id.clone();
    assert_eq!(
        repo.get_word_timings(&sentence_id).unwrap(),
        active
            .words
            .iter()
            .filter(|word| word.sentence_id == sentence_id)
            .cloned()
            .collect::<Vec<_>>()
    );

    let mut reimport = media.export_lltimeline_document(&track.id).unwrap();
    let mut duplicate = reimport.rhythm_frames[0].clone();
    duplicate.id = RhythmFrameId::parse("untrusted-duplicate-frame").unwrap();
    duplicate.status = TimelineStatus::Archived;
    reimport.rhythm_frames.push(duplicate);
    media.import_lltimeline_document(reimport).unwrap();

    let imported = corpus_snapshot(&repo);
    media.rebuild_corpus_index().unwrap();
    assert_eq!(
        corpus_snapshot(&repo),
        imported,
        "import projection must equal the canonical subsequent rebuild"
    );

    let mut without_active = media.export_lltimeline_document(&track.id).unwrap();
    without_active.active_word_timeline_id = None;
    for timeline in &mut without_active.word_timelines {
        timeline.status = TimelineStatus::Candidate;
    }
    media.import_lltimeline_document(without_active).unwrap();
    assert!(
        repo.get_word_timings(&sentence_id).unwrap().is_empty(),
        "removing the active word timeline clears legacy compatibility rows"
    );
}

#[test]
fn lltimeline_cross_source_resource_id_reuse_rolls_back() {
    let (repo, media) = lltimeline_import_services();
    let original = media
        .import_lltimeline_document(lltimeline_fixture())
        .unwrap();
    let original_timeline = repo
        .active_word_timeline(&original.id)
        .unwrap()
        .expect("fixture active timeline");

    let mut conflicting = lltimeline_fixture();
    let other_media_id = MediaId::parse("other-media").unwrap();
    let other_track_id = SubtitleTrackId::parse("other-track").unwrap();
    conflicting.metadata.media.id = other_media_id.clone();
    conflicting.metadata.media.fingerprint = "other-media-fingerprint".into();
    conflicting.metadata.extra["track_id"] = serde_json::json!(other_track_id.as_str());
    conflicting.metadata.extra["track_fingerprint"] = serde_json::json!("other-track-fingerprint");
    conflicting.word_timelines[0].media_id = other_media_id.clone();
    conflicting.word_timelines[0].track_id = other_track_id;

    assert!(media.import_lltimeline_document(conflicting).is_err());
    assert!(
        repo.get(&other_media_id).unwrap().is_none(),
        "the conflicting import media write must roll back"
    );
    assert_eq!(
        repo.get_word_timeline(&original_timeline.id)
            .unwrap()
            .expect("original resource remains")
            .track_id,
        original.id
    );
}

fn content_package_candidate_fixture(
    track: &SubtitleTrack,
    media: &MediaItem,
) -> ContentPackageCandidateImport {
    let mut document = lltimeline_fixture();
    let timeline = word_timeline(
        "package-word-candidate",
        track,
        TimelineStatus::Candidate,
        "package-aligner",
        120,
        400,
    );
    document.metadata.media = LLTimelineMedia {
        id: media.id.clone(),
        fingerprint: media.fingerprint.clone(),
        path: None,
        title: media.title.clone(),
        duration_ms: media.duration.map(TimeMs::get),
    };
    document.metadata.language = track.language.clone();
    document.metadata.extra = serde_json::json!({
        "track_id": track.id.as_str(),
        "track_fingerprint": track.fingerprint,
        "track_source": "package:subtitle_text_track",
    });
    document.artifacts = vec![LLTimelineArtifact {
        kind: "rhythm_word_acoustic_cues".into(),
        provider_id: Some("package-acoustics".into()),
        provider_version: Some("v1".into()),
        payload: serde_json::json!({
            "resource_id": "package-acoustics-1",
            "timeline_id": timeline.id.as_str(),
            "cues": [{
                "sentence_id": track.sentences[0].id.as_str(),
                "token_index": 0
            }]
        }),
    }];
    ContentPackageCandidateImport {
        track: track.clone(),
        metadata: document.metadata,
        artifacts: document.artifacts,
        word_timelines: vec![timeline],
        phone_timelines: Vec::new(),
        sense_group_analyses: Vec::new(),
        prosody_analyses: Vec::new(),
        corpus_occurrences: Vec::new(),
    }
}

#[test]
fn content_package_candidate_import_is_idempotent_and_never_activates() {
    let repo = SqliteRepository::in_memory().unwrap();
    let media = transcription_media();
    MediaRepository::upsert(&repo, &media).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let import = content_package_candidate_fixture(&track, &media);

    repo.import_content_package_candidates(&import).unwrap();
    repo.import_content_package_candidates(&import).unwrap();

    assert_eq!(repo.list_word_timelines(&track.id).unwrap().len(), 1);
    assert_eq!(
        repo.list_word_timelines(&track.id).unwrap()[0].status,
        TimelineStatus::Candidate
    );
    assert!(repo.active_word_timeline(&track.id).unwrap().is_none());
    let (metadata, artifacts) = repo
        .get_lltimeline_resource(&track.id)
        .unwrap()
        .expect("metadata attached to the already landed track");
    assert_eq!(
        metadata.extra["track_source"],
        serde_json::json!("package:subtitle_text_track")
    );
    assert_eq!(artifacts.len(), 1);
}

#[test]
fn content_package_candidate_import_rejects_non_candidate_status() {
    let repo = SqliteRepository::in_memory().unwrap();
    let media = transcription_media();
    MediaRepository::upsert(&repo, &media).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let mut import = content_package_candidate_fixture(&track, &media);
    import.word_timelines[0].status = TimelineStatus::Active;

    let result = repo.import_content_package_candidates(&import);
    assert!(result.is_err());
    assert!(
        repo.list_word_timelines(&track.id).unwrap().is_empty(),
        "a rejected import must not write any candidate row"
    );
}

#[test]
fn content_package_candidate_import_rolls_back_on_cross_source_conflict() {
    let repo = SqliteRepository::in_memory().unwrap();
    let media = transcription_media();
    MediaRepository::upsert(&repo, &media).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let import = content_package_candidate_fixture(&track, &media);
    repo.import_content_package_candidates(&import).unwrap();

    let other_media = MediaItem {
        id: MediaId::parse("media-other").unwrap(),
        path: "/tmp/other.mp4".into(),
        fingerprint: "other-fp".into(),
        title: "Other".into(),
        kind: MediaKind::Video,
        duration: None,
        availability: MediaAvailability::Available,
        retained_at_ms: None,
        created_at_ms: 2,
        updated_at_ms: 2,
    };
    MediaRepository::upsert(&repo, &other_media).unwrap();
    let other_track = SubtitleTrack {
        id: SubtitleTrackId::parse("track-other").unwrap(),
        media_id: other_media.id.clone(),
        fingerprint: "other-track-fp".into(),
        language: None,
        source: "test".into(),
        status: SubtitleTrackStatus::Available,
        sentences: Vec::new(),
    };
    let mut conflicting = import;
    conflicting.track = other_track;
    conflicting.word_timelines[0].track_id = conflicting.track.id.clone();
    conflicting.word_timelines[0].media_id = other_media.id.clone();

    assert!(
        repo.import_content_package_candidates(&conflicting)
            .is_err()
    );
    assert!(
        repo.get_track(&conflicting.track.id).unwrap().is_none(),
        "the conflicting track write must roll back"
    );
    assert_eq!(repo.list_word_timelines(&track.id).unwrap().len(), 1);
}
