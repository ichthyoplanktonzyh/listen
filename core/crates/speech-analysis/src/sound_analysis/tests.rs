use super::boundaries::detect_phrase_boundaries;
use super::tokens::{RhythmToken, is_audio_backed_word_timing};
use super::*;
use crate::phonetic_alignment::{CanonicalPhone, align_phones};
use domain::{
    ConnectedSpeechExplanationStatus, ConnectedSpeechFamily, DetectedPhone, ListeningHotspotKind,
    PhoneAlignment, PhoneAlignmentKind, ProsodicBoundaryEvidence, RhythmClaimStatus,
    RhythmDivergenceKind, RhythmSignalSource, SoundLearningPhone, SoundPhoneEvidence,
    SubtitleSentence, SubtitleTokenKind, TimingSource, WordTiming,
};

#[test]
fn keeps_expected_label_when_observed_label_mismatches() {
    let canonical = vec![CanonicalPhone {
        symbol: "S".into(),
        token_index: 0,
        stress: None,
    }];
    let observed = observed(&[("K", 100, 180)]);
    let alignments = align_phones(&canonical, &observed);
    let analysis = build_sound_analysis(&canonical, &observed, &alignments, config(None));

    assert_eq!(analysis.learning_phones[0].symbol, "S");
    assert_eq!(
        analysis.learning_phones[0].observed_symbol.as_deref(),
        Some("K")
    );
    assert_eq!(
        analysis.learning_phones[0].evidence,
        SoundPhoneEvidence::Substitution
    );
    assert_eq!(analysis.learning_phones[0].start_ms, 100);
    assert!(analysis.connected_speech.is_empty());
    assert!(
        analysis
            .rhythm_frame
            .as_ref()
            .unwrap()
            .listening_hotspots
            .is_empty()
    );
}

#[test]
fn syllabifies_with_onset_maximization_and_pause_phrases() {
    let phones = vec![
        learning("S", 0, 50),
        learning("T", 50, 100),
        learning("R", 100, 150),
        learning("IY", 150, 220),
        learning("T", 220, 260),
        learning("AE", 420, 500),
    ];
    let syllables = syllabify(&phones);
    assert_eq!(syllables.len(), 2);
    assert_eq!(syllables[0].onset, vec![0, 1, 2]);
    assert_eq!(syllables[0].nucleus, vec![3]);
    assert_eq!(syllables[0].coda, vec![4]);
    assert_eq!(syllables[1].onset, Vec::<u32>::new());

    let phrases = detect_prosodic_phrases(&syllables);
    assert_eq!(phrases.len(), 2);
    assert_eq!(
        phrases[1].boundary_evidence,
        ProsodicBoundaryEvidence::Pause
    );
}

#[test]
fn detects_phrase_boundary_from_pre_boundary_lengthening_without_pause() {
    let tokens = rhythm_token_fixtures(&[120, 130, 125, 430, 120, 135]);

    let boundaries = detect_phrase_boundaries(&tokens, &[], &[]);

    assert_eq!(boundaries.len(), 1);
    assert_eq!(boundaries[0].after_token_index, Some(3));
    assert_eq!(boundaries[0].before_token_index, Some(4));
    assert_eq!(boundaries[0].cues, vec!["final_lengthening"]);
    assert!(boundaries[0].confidence >= 0.7);
}

#[test]
fn explains_required_connected_speech_families_without_changing_labels() {
    let canonical = canonical(&["AH", "T", "D", "Y", "N", "T"]);
    let observed = observed(&[
        ("AX", 0, 40),
        ("DX", 40, 80),
        ("JH", 80, 130),
        ("R", 130, 150),
    ]);
    let alignments = vec![
        alignment(
            PhoneAlignmentKind::Substitution,
            &["AH"],
            Some(0),
            Some(0),
            0,
            0.84,
        ),
        alignment(
            PhoneAlignmentKind::Substitution,
            &["T"],
            Some(1),
            Some(1),
            1,
            0.88,
        ),
        alignment(
            PhoneAlignmentKind::Merge,
            &["D", "Y"],
            Some(2),
            Some(2),
            2,
            0.81,
        ),
        alignment(PhoneAlignmentKind::Insertion, &[], Some(3), Some(3), 3, 0.7),
        alignment(
            PhoneAlignmentKind::Deletion,
            &["N", "T"],
            None,
            None,
            4,
            0.0,
        ),
    ];

    let analysis = build_sound_analysis(&canonical, &observed, &alignments, config(None));

    assert_eq!(
        analysis
            .connected_speech
            .iter()
            .map(|value| value.family)
            .collect::<Vec<_>>(),
        vec![
            ConnectedSpeechFamily::WeakForm,
            ConnectedSpeechFamily::Flapping,
            ConnectedSpeechFamily::Assimilation,
            ConnectedSpeechFamily::Contraction,
        ]
    );
    assert_eq!(analysis.learning_phones[0].symbol, "AH");
    assert_eq!(
        analysis.connected_speech[0].status,
        ConnectedSpeechExplanationStatus::DetectedInAudio
    );
    assert_eq!(analysis.connected_speech[3].confidence, 0.62);
    assert_eq!(analysis.connected_speech[3].label, "possible contraction");
}

#[test]
fn builds_rhythm_frame_from_stress_function_words_and_duration() {
    let sentence = sentence(&["I", "could", "have", "checked", "the", "market"]);
    let canonical = canonical_with_stress(&[
        (0, "AY", Some(1)),
        (1, "K", None),
        (1, "UH", Some(0)),
        (1, "D", None),
        (2, "HH", None),
        (2, "AE", Some(0)),
        (2, "V", None),
        (3, "CH", None),
        (3, "EH", Some(1)),
        (3, "K", None),
        (3, "T", None),
        (4, "DH", None),
        (4, "AH", Some(0)),
        (5, "M", None),
        (5, "AA", Some(1)),
        (5, "R", None),
        (5, "K", None),
        (5, "AH", Some(0)),
        (5, "T", None),
    ]);
    let observed = observed(&[
        ("AY", 0, 40),
        ("K", 45, 70),
        ("UH", 70, 95),
        ("D", 95, 115),
        ("HH", 115, 135),
        ("AE", 135, 160),
        ("V", 160, 185),
        ("CH", 185, 230),
        ("EH", 230, 290),
        ("K", 290, 330),
        ("T", 330, 360),
        ("DH", 365, 382),
        ("AH", 382, 402),
        ("M", 540, 585),
        ("AA", 585, 670),
        ("R", 670, 705),
        ("K", 705, 740),
        ("AH", 740, 780),
        ("T", 780, 820),
    ]);
    let alignments = align_phones(&canonical, &observed);

    let analysis =
        build_sound_analysis(&canonical, &observed, &alignments, config(Some(&sentence)));
    let frame = analysis.rhythm_frame.as_ref().unwrap();

    assert!(
        frame
            .stress_anchors
            .iter()
            .any(|anchor| anchor.label == "checked")
    );
    assert!(
        frame
            .stress_anchors
            .iter()
            .any(|anchor| anchor.label == "market")
    );
    assert!(
        frame
            .weak_groups
            .iter()
            .any(|group| group.label == "I could have")
    );
    assert!(!frame.compression_spans.is_empty());
    assert_eq!(frame.phrase_boundaries.len(), 1);
    assert!(
        frame
            .listening_hotspots
            .iter()
            .any(|hotspot| hotspot.kind == ListeningHotspotKind::WeakGroup)
    );
    assert!(frame.quality.phone_evidence_coverage > 0.9);
}

#[test]
fn builds_rhythm_frame_l1_l3_from_word_timeline_without_phone_evidence() {
    let sentence = sentence(&["I", "could", "have", "checked", "the", "market"]);
    let canonical = canonical_with_stress(&[
        (0, "AY", Some(1)),
        (1, "K", None),
        (1, "UH", Some(0)),
        (1, "D", None),
        (2, "HH", None),
        (2, "AE", Some(0)),
        (2, "V", None),
        (3, "CH", None),
        (3, "EH", Some(1)),
        (3, "K", None),
        (3, "T", None),
        (4, "DH", None),
        (4, "AH", Some(0)),
        (5, "M", None),
        (5, "AA", Some(1)),
        (5, "R", None),
        (5, "K", None),
        (5, "AH", Some(0)),
        (5, "T", None),
    ]);
    let word_timings = word_timings(
        &sentence,
        &[
            (0, "I", 0, 40),
            (1, "could", 45, 110),
            (2, "have", 110, 170),
            (3, "checked", 170, 370),
            (4, "the", 560, 620),
            (5, "market", 620, 980),
        ],
    );

    let analysis = build_sound_analysis(
        &canonical,
        &[],
        &[],
        SoundAnalysisConfig {
            provider_id: "word-rhythm-fixture",
            provider_version: "v1",
            model_revision: Some("model".into()),
            phone_set: "arpabet",
            sentence: Some(&sentence),
            word_timings: Some(&word_timings),
            word_acoustic_cues: None,
        },
    );
    let frame = analysis.rhythm_frame.as_ref().unwrap();

    assert!(
        analysis
            .learning_phones
            .iter()
            .all(|phone| phone.observed_phone_index.is_none())
    );
    assert_eq!(frame.generated_from, "wordtimeline_timing_prominence_v1");
    assert_eq!(frame.quality.timing_source, "word_timeline");
    assert_eq!(frame.quality.phone_evidence_coverage, 0.0);
    assert!(
        frame
            .quality
            .prominence_sources
            .contains(&RhythmSignalSource::Timing)
    );
    assert!(
        frame
            .stress_anchors
            .iter()
            .any(|anchor| anchor.label == "checked"
                && anchor.phone_start.is_none()
                && anchor.claim_status == RhythmClaimStatus::AudioSupported
                && anchor.signal_sources.contains(&RhythmSignalSource::Timing))
    );
    assert!(
        frame
            .stress_anchors
            .iter()
            .any(|anchor| anchor.label == "market" && anchor.is_nucleus)
    );
    assert!(
        frame
            .nuclei
            .iter()
            .any(|nucleus| nucleus.label == "checked")
    );
    assert!(frame.nuclei.iter().any(|nucleus| nucleus.label == "market"));
    assert!(
        frame
            .weak_groups
            .iter()
            .any(|group| group.label == "I could have")
    );
    assert!(!frame.compression_spans.is_empty());
    assert_eq!(frame.phrase_boundaries.len(), 1);
    let could_have_ref = frame
        .connected_speech_refs
        .iter()
        .find(|value| value.token_start == Some(1) && value.token_end == Some(2))
        .expect("could have connected-speech reference");
    assert_eq!(
        could_have_ref.divergence,
        RhythmDivergenceKind::TeachableRule
    );
    assert_eq!(
        could_have_ref.signal_sources,
        [RhythmSignalSource::TextPrior]
    );
    assert_eq!(could_have_ref.surface_text, "could have");
    assert_eq!(could_have_ref.expected_display_ipa, "kʊdhæv");
    assert_eq!(could_have_ref.default_symbols, ["K", "UH", "D", "AH", "V"]);
    assert_eq!(could_have_ref.default_display_ipa, "kʊdəv");
    assert!(analysis.connected_speech.iter().any(|value| {
        value.learning_symbols == ["K", "UH", "D", "AH", "V"]
            && value.status == ConnectedSpeechExplanationStatus::PossibleByRule
    }));
}

#[test]
fn estimated_word_timing_stays_predicted_and_does_not_select_nuclei() {
    let sentence = sentence(&["I", "could", "have", "checked", "the", "market"]);
    let canonical = canonical_with_stress(&[
        (0, "AY", Some(1)),
        (1, "K", None),
        (1, "UH", Some(0)),
        (1, "D", None),
        (2, "HH", None),
        (2, "AE", Some(0)),
        (2, "V", None),
        (3, "CH", None),
        (3, "EH", Some(1)),
        (3, "K", None),
        (3, "T", None),
        (4, "DH", None),
        (4, "AH", Some(0)),
        (5, "M", None),
        (5, "AA", Some(1)),
        (5, "R", None),
        (5, "K", None),
        (5, "AH", Some(0)),
        (5, "T", None),
    ]);
    let word_timings = word_timings_with_source(
        &sentence,
        &[
            (0, "I", 0, 40),
            (1, "could", 45, 110),
            (2, "have", 110, 170),
            (3, "checked", 170, 370),
            (4, "the", 560, 620),
            (5, "market", 620, 980),
        ],
        TimingSource::Estimated,
    );

    let analysis = build_sound_analysis(
        &canonical,
        &[],
        &[],
        SoundAnalysisConfig {
            provider_id: "word-rhythm-fixture",
            provider_version: "v1",
            model_revision: Some("model".into()),
            phone_set: "arpabet",
            sentence: Some(&sentence),
            word_timings: Some(&word_timings),
            word_acoustic_cues: None,
        },
    );
    let frame = analysis.rhythm_frame.as_ref().unwrap();

    assert_eq!(frame.generated_from, "wordtimeline_estimated_prominence_v1");
    assert_eq!(frame.quality.timing_source, "word_timeline_estimated");
    assert_eq!(
        frame.quality.prominence_sources,
        vec![RhythmSignalSource::TextPrior]
    );
    assert!(!frame.stress_anchors.is_empty());
    assert!(
        frame
            .stress_anchors
            .iter()
            .all(|anchor| anchor.claim_status == RhythmClaimStatus::Predicted
                && !anchor.signal_sources.contains(&RhythmSignalSource::Timing))
    );
    assert!(frame.nuclei.is_empty());
    assert!(
        frame
            .weak_groups
            .iter()
            .all(|group| group.claim_status == RhythmClaimStatus::Predicted
                && !group.signal_sources.contains(&RhythmSignalSource::Timing))
    );
    assert!(
        frame
            .compression_spans
            .iter()
            .all(|span| span.claim_status == RhythmClaimStatus::Predicted
                && !span.signal_sources.contains(&RhythmSignalSource::Timing))
    );
    assert!(frame.phrase_boundaries.is_empty());
    assert!(
        frame
            .listening_hotspots
            .iter()
            .all(
                |hotspot| hotspot.claim_status == RhythmClaimStatus::Predicted
                    && !hotspot.signal_sources.contains(&RhythmSignalSource::Timing)
            )
    );
}

#[test]
fn short_timed_content_sound_can_be_audible_anchor() {
    let sentence = sentence(&["go", "now"]);
    let canonical = canonical_with_stress(&[
        (0, "G", None),
        (0, "OW", None),
        (1, "N", None),
        (1, "AW", Some(1)),
    ]);
    let word_timings = word_timings(&sentence, &[(0, "go", 0, 80), (1, "now", 100, 260)]);

    let frame = build_rhythm_frame_from_word_timeline(&sentence, &canonical, &word_timings, None);
    let go_anchor = frame
        .stress_anchors
        .iter()
        .find(|anchor| anchor.label == "go")
        .expect("go should be retained as a listening anchor");

    assert_eq!(go_anchor.claim_status, RhythmClaimStatus::AudioSupported);
    assert!(
        go_anchor
            .signal_sources
            .contains(&RhythmSignalSource::Timing)
    );
    assert!(go_anchor.reason.contains("clearly timed"));
    let info_anchor = frame
        .information_anchors
        .iter()
        .find(|anchor| anchor.label == "go")
        .expect("go should have a phoneme-level information anchor");
    assert_eq!(info_anchor.sound, "goʊ");
    assert_eq!(info_anchor.claim_status, RhythmClaimStatus::AudioSupported);
    assert!(
        info_anchor
            .signal_sources
            .contains(&RhythmSignalSource::Timing)
    );
    assert!(frame.nuclei.iter().any(|nucleus| nucleus.label == "now"));
}

#[test]
fn word_acoustic_energy_cues_drive_prominence_provenance() {
    let sentence = sentence(&["we", "saw", "tiny", "market"]);
    let canonical = canonical_with_stress(&[
        (0, "W", None),
        (0, "IY", Some(0)),
        (1, "S", None),
        (1, "AO", Some(1)),
        (2, "T", None),
        (2, "AY", Some(1)),
        (2, "N", None),
        (2, "IY", Some(0)),
        (3, "M", None),
        (3, "AA", Some(1)),
        (3, "R", None),
        (3, "K", None),
        (3, "AH", Some(0)),
        (3, "T", None),
    ]);
    let word_timings = word_timings(
        &sentence,
        &[
            (0, "we", 0, 70),
            (1, "saw", 80, 190),
            (2, "tiny", 200, 320),
            (3, "market", 330, 500),
        ],
    );
    let acoustic_cues = vec![RhythmWordAcousticCue {
        token_index: 2,
        energy_prominence: Some(0.96),
        pitch_prominence: None,
        pitch_reset_after: None,
    }];

    let analysis = build_sound_analysis(
        &canonical,
        &[],
        &[],
        SoundAnalysisConfig {
            provider_id: "word-rhythm-fixture",
            provider_version: "v1",
            model_revision: Some("model".into()),
            phone_set: "arpabet",
            sentence: Some(&sentence),
            word_timings: Some(&word_timings),
            word_acoustic_cues: Some(&acoustic_cues),
        },
    );
    let frame = analysis.rhythm_frame.as_ref().unwrap();
    let tiny_anchor = frame
        .stress_anchors
        .iter()
        .find(|anchor| anchor.label == "tiny")
        .unwrap();

    assert_eq!(
        frame.generated_from,
        "wordtimeline_timing_acoustic_prominence_v1"
    );
    assert_eq!(
        frame.references.actual.source,
        "word_timeline_duration_energy"
    );
    assert!(
        frame
            .quality
            .prominence_sources
            .contains(&RhythmSignalSource::Energy)
    );
    assert!(
        tiny_anchor
            .prominence_cues
            .contains(&RhythmSignalSource::Energy)
    );
    assert!(
        tiny_anchor
            .signal_sources
            .contains(&RhythmSignalSource::Energy)
    );
    assert_eq!(tiny_anchor.claim_status, RhythmClaimStatus::AudioSupported);
    assert!(tiny_anchor.is_nucleus);
}

#[test]
fn word_acoustic_pitch_cues_drive_prominence_and_boundary_provenance() {
    let sentence = sentence(&["we", "hear", "new", "focus"]);
    let canonical = canonical_with_stress(&[
        (0, "W", None),
        (0, "IY", Some(0)),
        (1, "HH", None),
        (1, "IH", Some(1)),
        (2, "N", None),
        (2, "UW", Some(1)),
        (3, "F", None),
        (3, "OW", Some(1)),
    ]);
    let word_timings = word_timings(
        &sentence,
        &[
            (0, "we", 0, 100),
            (1, "hear", 110, 260),
            (2, "new", 270, 390),
            (3, "focus", 400, 570),
        ],
    );
    let acoustic_cues = vec![
        RhythmWordAcousticCue {
            token_index: 1,
            energy_prominence: None,
            pitch_prominence: Some(0.91),
            pitch_reset_after: Some(0.82),
        },
        RhythmWordAcousticCue {
            token_index: 3,
            energy_prominence: None,
            pitch_prominence: Some(0.35),
            pitch_reset_after: None,
        },
    ];

    let frame = build_rhythm_frame_from_word_timeline(
        &sentence,
        &canonical,
        &word_timings,
        Some(&acoustic_cues),
    );
    let hear_anchor = frame
        .stress_anchors
        .iter()
        .find(|anchor| anchor.label == "hear")
        .unwrap();

    assert!(
        frame
            .quality
            .prominence_sources
            .contains(&RhythmSignalSource::Pitch)
    );
    assert!(
        hear_anchor
            .prominence_cues
            .contains(&RhythmSignalSource::Pitch)
    );
    assert_eq!(hear_anchor.claim_status, RhythmClaimStatus::AudioSupported);
    assert!(frame.phrase_boundaries.iter().any(|boundary| {
        boundary.after_token_index == Some(1)
            && boundary.signal_sources.contains(&RhythmSignalSource::Pitch)
    }));
}

#[test]
fn asr_reported_word_timing_is_audio_backed_but_estimated_timing_is_not() {
    assert!(is_audio_backed_word_timing(TimingSource::AsrReported));
    assert!(!is_audio_backed_word_timing(TimingSource::Estimated));
}

#[test]
fn information_structure_prior_downweights_repeated_content() {
    let sentence = sentence(&["market", "market", "opens"]);
    let canonical = canonical_with_stress(&[
        (0, "M", None),
        (0, "AA", Some(1)),
        (0, "R", None),
        (1, "M", None),
        (1, "AA", Some(1)),
        (1, "R", None),
        (2, "OW", Some(1)),
        (2, "P", None),
    ]);
    let word_timings = word_timings(
        &sentence,
        &[
            (0, "market", 0, 240),
            (1, "market", 260, 500),
            (2, "opens", 520, 760),
        ],
    );

    let analysis = build_sound_analysis(
        &canonical,
        &[],
        &[],
        SoundAnalysisConfig {
            provider_id: "word-rhythm-fixture",
            provider_version: "v1",
            model_revision: Some("model".into()),
            phone_set: "arpabet",
            sentence: Some(&sentence),
            word_timings: Some(&word_timings),
            word_acoustic_cues: None,
        },
    );
    let frame = analysis.rhythm_frame.as_ref().unwrap();
    let anchor = |token_index| {
        frame
            .stress_anchors
            .iter()
            .find(|anchor| anchor.token_index == Some(token_index))
            .unwrap()
    };

    assert!(anchor(0).prominence > anchor(1).prominence);
    assert!(anchor(2).prominence > anchor(0).prominence);
    assert!(anchor(1).reason.contains("Repeated content"));
    assert!(anchor(2).reason.contains("focus"));
}

#[test]
fn raw_insertion_does_not_become_linking_without_boundary_context() {
    let canonical = canonical(&["AH"]);
    let observed = observed(&[("AH", 0, 40), ("R", 40, 60)]);
    let alignments = vec![
        alignment(PhoneAlignmentKind::Match, &["AH"], Some(0), Some(0), 0, 0.9),
        alignment(PhoneAlignmentKind::Insertion, &[], Some(1), Some(1), 0, 0.9),
    ];

    let analysis = build_sound_analysis(&canonical, &observed, &alignments, config(None));

    assert!(analysis.connected_speech.is_empty());
}

#[test]
fn explains_single_phone_deletion_as_low_confidence_hint() {
    let canonical = canonical(&["T"]);
    let observed = observed(&[("S", 0, 40)]);
    let alignments = vec![alignment(
        PhoneAlignmentKind::Deletion,
        &["T"],
        None,
        None,
        0,
        0.0,
    )];

    let analysis = build_sound_analysis(&canonical, &observed, &alignments, config(None));

    assert_eq!(
        analysis.connected_speech[0].family,
        ConnectedSpeechFamily::Deletion
    );
    assert_eq!(
        analysis.connected_speech[0].status,
        ConnectedSpeechExplanationStatus::PossibleByRule
    );
    assert_eq!(analysis.connected_speech[0].label, "possible deletion");
}

fn observed(values: &[(&str, u64, u64)]) -> Vec<DetectedPhone> {
    values
        .iter()
        .map(|(symbol, start_ms, end_ms)| DetectedPhone {
            symbol: (*symbol).into(),
            display_ipa: (*symbol).into(),
            phone_set: "arpabet".into(),
            start_ms: *start_ms,
            end_ms: *end_ms,
            confidence: Some(0.4),
            token_index: None,
            provider_id: "ctc".into(),
            provider_version: "v1".into(),
            model_revision: "model".into(),
        })
        .collect()
}

fn canonical(symbols: &[&str]) -> Vec<CanonicalPhone> {
    symbols
        .iter()
        .enumerate()
        .map(|(index, symbol)| CanonicalPhone {
            symbol: (*symbol).into(),
            token_index: index as u32,
            stress: None,
        })
        .collect()
}

fn config(sentence: Option<&SubtitleSentence>) -> SoundAnalysisConfig<'_> {
    SoundAnalysisConfig {
        provider_id: "ctc",
        provider_version: "v1",
        model_revision: Some("model".into()),
        phone_set: "arpabet",
        sentence,
        word_timings: None,
        word_acoustic_cues: None,
    }
}

fn canonical_with_stress(values: &[(u32, &str, Option<u8>)]) -> Vec<CanonicalPhone> {
    values
        .iter()
        .map(|(token_index, symbol, stress)| CanonicalPhone {
            symbol: (*symbol).into(),
            token_index: *token_index,
            stress: *stress,
        })
        .collect()
}

fn sentence(words: &[&str]) -> SubtitleSentence {
    let display_text = words.join(" ");
    SubtitleSentence {
        id: domain::SubtitleSentenceId::parse("sentence-rhythm").unwrap(),
        index: 0,
        start: domain::TimeMs::new(0),
        end: domain::TimeMs::new(1000),
        original_text: display_text.clone(),
        display_text,
        tokens: words
            .iter()
            .enumerate()
            .map(|(index, word)| domain::SubtitleToken {
                index: index as u32,
                kind: SubtitleTokenKind::Word,
                text: (*word).into(),
                normalized: Some(word.to_ascii_lowercase()),
                start_char: index as u32,
                end_char: index as u32 + word.len() as u32,
            })
            .collect(),
    }
}

fn word_timings(sentence: &SubtitleSentence, values: &[(u32, &str, u64, u64)]) -> Vec<WordTiming> {
    word_timings_with_source(sentence, values, TimingSource::ForcedAligned)
}

fn word_timings_with_source(
    sentence: &SubtitleSentence,
    values: &[(u32, &str, u64, u64)],
    timing_source: TimingSource,
) -> Vec<WordTiming> {
    values
        .iter()
        .map(|(token_index, text, start_ms, end_ms)| WordTiming {
            sentence_id: sentence.id.clone(),
            token_index: *token_index,
            text: (*text).into(),
            start_ms: *start_ms,
            end_ms: *end_ms,
            confidence: Some(0.92),
            timing_source,
            provider_id: "mfa".into(),
            provider_version: "fixture".into(),
        })
        .collect()
}

fn rhythm_token_fixtures(durations: &[u64]) -> Vec<RhythmToken> {
    let mut cursor = 0;
    durations
        .iter()
        .enumerate()
        .map(|(index, duration)| {
            let start_ms = cursor;
            let end_ms = start_ms + duration;
            cursor = end_ms + 20;
            RhythmToken {
                index: index as u32,
                text: format!("w{index}"),
                normalized: format!("w{index}"),
                start_ms,
                end_ms,
                phone_start: Some(index as u32),
                phone_end: Some(index as u32),
                phone_count: 1,
                syllable_index: Some(index as u32),
                syllable_count: 1,
                has_primary_stress: false,
                has_secondary_stress: false,
                average_confidence: Some(0.9),
                energy_prominence: None,
                pitch_prominence: None,
                pitch_reset_after: None,
                timing_audio_supported: true,
                from_word_timeline: false,
            }
        })
        .collect()
}

fn alignment(
    kind: PhoneAlignmentKind,
    canonical: &[&str],
    detected_start: Option<u32>,
    detected_end: Option<u32>,
    token_start: u32,
    confidence: f32,
) -> PhoneAlignment {
    PhoneAlignment {
        kind,
        token_start: Some(token_start),
        token_end: Some(token_start + canonical.len().saturating_sub(1) as u32),
        canonical_phones: canonical.iter().map(|value| (*value).into()).collect(),
        detected_phone_start: detected_start,
        detected_phone_end: detected_end,
        confidence,
    }
}

fn learning(symbol: &str, start_ms: u64, end_ms: u64) -> SoundLearningPhone {
    SoundLearningPhone {
        symbol: symbol.into(),
        display_ipa: symbol.into(),
        phone_set: "arpabet".into(),
        start_ms,
        end_ms,
        confidence: Some(0.9),
        token_index: None,
        stress: None,
        observed_phone_index: None,
        observed_symbol: None,
        evidence: SoundPhoneEvidence::Match,
    }
}
