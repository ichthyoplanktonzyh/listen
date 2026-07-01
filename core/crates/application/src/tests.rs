use super::*;
use domain::{
    LexicalEntryKind, SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind,
    TimeMs, TimingSource,
};

// ── require_text ────────────────────────────────────────────────────────

#[test]
fn require_text_rejects_empty() {
    let err = require_text("", "field_name").unwrap_err();
    assert!(matches!(err, ApplicationError::Validation("field_name")));
}

#[test]
fn require_text_rejects_whitespace_only() {
    let err = require_text("   ", "field_name").unwrap_err();
    assert!(matches!(err, ApplicationError::Validation("field_name")));
}

#[test]
fn require_text_accepts_valid_string() {
    assert!(require_text("hello", "field_name").is_ok());
}

#[test]
fn require_text_accepts_text_with_whitespace_padding() {
    assert!(require_text("  hello  ", "field_name").is_ok());
}

// ── clean_optional ──────────────────────────────────────────────────────

#[test]
fn clean_optional_none_is_none() {
    assert_eq!(clean_optional(None), None);
}

#[test]
fn clean_optional_empty_string_is_none() {
    assert_eq!(clean_optional(Some("".into())), None);
}

#[test]
fn clean_optional_whitespace_only_is_none() {
    assert_eq!(clean_optional(Some("   ".into())), None);
}

#[test]
fn clean_optional_trims_whitespace() {
    assert_eq!(
        clean_optional(Some("  hello  ".into())),
        Some("hello".into())
    );
}

// ── normalize_american_english ──────────────────────────────────────────

#[test]
fn normalize_went_to_go() {
    assert_eq!(normalize_american_english("went"), "go");
}

#[test]
fn normalize_gone_to_go() {
    assert_eq!(normalize_american_english("gone"), "go");
}

#[test]
fn normalize_going_to_go() {
    assert_eq!(normalize_american_english("going"), "go");
}

#[test]
fn normalize_goes_to_go() {
    assert_eq!(normalize_american_english("goes"), "go");
}

#[test]
fn normalize_was_to_be() {
    assert_eq!(normalize_american_english("was"), "be");
}

#[test]
fn normalize_were_to_be() {
    assert_eq!(normalize_american_english("were"), "be");
}

#[test]
fn normalize_am_is_are() {
    assert_eq!(normalize_american_english("am"), "be");
    assert_eq!(normalize_american_english("is"), "be");
    assert_eq!(normalize_american_english("are"), "be");
}

#[test]
fn normalize_do_variants() {
    assert_eq!(normalize_american_english("did"), "do");
    assert_eq!(normalize_american_english("done"), "do");
    assert_eq!(normalize_american_english("does"), "do");
}

#[test]
fn normalize_have_variants() {
    assert_eq!(normalize_american_english("had"), "have");
    assert_eq!(normalize_american_english("has"), "have");
}

#[test]
fn normalize_ies_suffix() {
    // words ending with "ies" and len > 4 → replace with "y"
    assert_eq!(normalize_american_english("stories"), "story");
    assert_eq!(normalize_american_english("families"), "family");
}

#[test]
fn normalize_ing_suffix() {
    assert_eq!(normalize_american_english("playing"), "play");
    assert_eq!(normalize_american_english("running"), "runn");
}

#[test]
fn normalize_ed_suffix() {
    assert_eq!(normalize_american_english("played"), "play");
    assert_eq!(normalize_american_english("walked"), "walk");
}

#[test]
fn normalize_s_suffix() {
    assert_eq!(normalize_american_english("words"), "word");
}

#[test]
fn normalize_preserves_ss_ending() {
    assert_eq!(normalize_american_english("pass"), "pass");
    assert_eq!(normalize_american_english("class"), "class");
}

#[test]
fn normalize_unchanged_for_short_words() {
    // "go" and "cat" are len <= 3, no suffix rules apply
    assert_eq!(normalize_american_english("go"), "go");
    assert_eq!(normalize_american_english("cat"), "cat");
    // "lies" is len 4: ies needs >4 (no), s-rule needs >3 (yes) → "lie"
    assert_eq!(normalize_american_english("lies"), "lie");
}

#[test]
fn normalize_ing_short_word() {
    // "doing" is in the exact match list (did/done/doing/does → do)
    assert_eq!(normalize_american_english("doing"), "do");
}

#[test]
fn normalize_rule_precedence() {
    // "being" should match the exact "been"/"being" list before suffix rules
    assert_eq!(normalize_american_english("being"), "be");
    // "having" matches exact "having" *check: "had" | "having" | "has" → "have"
    assert_eq!(normalize_american_english("having"), "have");
}

// ── normalize_phrase ────────────────────────────────────────────────────

#[test]
fn normalize_phrase_single_word() {
    // normalize_phrase uses domain::normalize_lemma (trim + lowercase only)
    assert_eq!(normalize_phrase("running"), "running");
}

#[test]
fn normalize_phrase_multi_word() {
    assert_eq!(normalize_phrase("take care of"), "take care of");
}

#[test]
fn normalize_phrase_with_irregulars() {
    // normalize_phrase uses domain::normalize_lemma (only trims and lowercases)
    assert_eq!(normalize_phrase("was going"), "was going");
}

// ── lexical identity ────────────────────────────────────────────────────

#[test]
fn lexical_unit_for_word_uses_language_profile_normalization() {
    let language = domain::LanguageCode::parse("en").unwrap();
    let unit =
        crate::lexical::lexical_unit_for_entry(&language, LexicalEntryKind::Word, "hello", "Hello");
    assert_eq!(unit.language.as_str(), "en");
    assert_eq!(unit.granularity, domain::LexicalUnit::GRANULARITY_WORD);
    assert_eq!(unit.normalization, "core.lemma");
    assert_eq!(unit.normalized_key, "hello");
}

#[test]
fn lexical_unit_distinguishes_word_and_phrase_assets() {
    let language = domain::LanguageCode::parse("en").unwrap();
    let word = crate::lexical::lexical_unit_for_entry(
        &language,
        LexicalEntryKind::Word,
        "take care",
        "take care",
    );
    let phrase = crate::lexical::lexical_unit_for_entry(
        &language,
        LexicalEntryKind::Phrase,
        "take care",
        "take care",
    );
    assert_ne!(word.identity(), phrase.identity());
    assert_eq!(phrase.granularity, domain::LexicalUnit::GRANULARITY_PHRASE);
}

// ── timing_priority ─────────────────────────────────────────────────────

#[test]
pub(crate) fn timing_priority_ordering() {
    assert_eq!(timing_priority(TimingSource::Estimated), 1);
    assert_eq!(timing_priority(TimingSource::AsrReported), 2);
    assert_eq!(timing_priority(TimingSource::ForcedAligned), 3);
    assert_eq!(timing_priority(TimingSource::UserAdjusted), 4);
}

#[test]
pub(crate) fn timing_priority_user_overrides_all() {
    assert!(
        timing_priority(TimingSource::UserAdjusted) > timing_priority(TimingSource::AsrReported)
    );
    assert!(
        timing_priority(TimingSource::UserAdjusted) > timing_priority(TimingSource::ForcedAligned)
    );
    assert!(timing_priority(TimingSource::UserAdjusted) > timing_priority(TimingSource::Estimated));
}

#[test]
fn remap_lltimeline_ids_rewrites_rhythm_word_acoustic_cues_artifact() {
    let media_id = MediaId::parse("media-old").unwrap();
    let old_track_id = SubtitleTrackId::parse("track-old").unwrap();
    let new_track_id = SubtitleTrackId::parse("track-new").unwrap();
    let old_sentence_id = SubtitleSentenceId::parse("sentence-old").unwrap();
    let old_timeline_id = WordTimelineId::parse("timeline-old").unwrap();
    let mut document = LLTimelineDocument {
        schema: LLTIMELINE_SCHEMA_V1.to_owned(),
        metadata: LLTimelineMetadata {
            created_at_ms: 1,
            generator: LLTimelineGenerator {
                id: "test".into(),
                version: "test".into(),
                mode: "test".into(),
            },
            media: LLTimelineMedia {
                id: media_id.clone(),
                fingerprint: "fingerprint".into(),
                path: None,
                title: "Media".into(),
                duration_ms: None,
            },
            language: None,
            human_reviewed: false,
            extra: serde_json::json!({}),
        },
        segments: vec![LLTimelineSegment {
            id: old_sentence_id.clone(),
            index: 0,
            start_ms: 0,
            end_ms: 500,
            text: "Hello".into(),
            display_text: "Hello".into(),
            tokens: vec![LLTimelineToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "Hello".into(),
                normalized: Some("hello".into()),
                start_char: 0,
                end_char: 5,
            }],
        }],
        word_timelines: vec![WordTimeline {
            id: old_timeline_id.clone(),
            track_id: old_track_id,
            media_id,
            algorithm_id: "fixture".into(),
            algorithm_version: "v1".into(),
            config_hash: "default".into(),
            parent_timeline_id: None,
            created_by: TimelineCreator::Algorithm,
            status: TimelineStatus::Active,
            metrics_json: TimelineMetrics::empty(),
            words: vec![WordTiming {
                sentence_id: old_sentence_id.clone(),
                token_index: 0,
                text: "Hello".into(),
                start_ms: 0,
                end_ms: 500,
                confidence: Some(1.0),
                timing_source: TimingSource::ForcedAligned,
                provider_id: "fixture".into(),
                provider_version: "v1".into(),
            }],
            created_at_ms: 1,
            updated_at_ms: 1,
        }],
        active_word_timeline_id: Some(old_timeline_id.clone()),
        phone_timelines: Vec::new(),
        active_phone_timeline_id: None,
        rhythm_frames: Vec::new(),
        chunk_timelines: Vec::new(),
        active_chunk_timeline_id: None,
        artifacts: vec![LLTimelineArtifact {
            kind: "rhythm_word_acoustic_cues".into(),
            provider_id: Some("fixture".into()),
            provider_version: Some("v1".into()),
            payload: serde_json::json!({
                "timeline_id": old_timeline_id.as_str(),
                "cues": [
                    {
                        "sentence_id": old_sentence_id.as_str(),
                        "token_index": 0,
                        "energy_prominence": 0.5
                    }
                ]
            }),
        }],
    };

    remap_lltimeline_sentence_ids(&mut document, &new_track_id);

    let remapped_timeline_id = document.active_word_timeline_id.as_ref().unwrap().as_str();
    let remapped_sentence_id = document.segments[0].id.as_str();
    let payload = document.artifacts[0].payload.as_object().unwrap();
    assert_eq!(
        payload["timeline_id"].as_str().unwrap(),
        remapped_timeline_id
    );
    assert_eq!(
        payload["cues"][0]["sentence_id"].as_str().unwrap(),
        remapped_sentence_id
    );
    assert_ne!(remapped_timeline_id, old_timeline_id.as_str());
    assert_ne!(remapped_sentence_id, old_sentence_id.as_str());
}

#[test]
fn zero_length_word_timing_cache_is_not_usable() {
    let timing = WordTiming {
        sentence_id: SubtitleSentenceId::from_fingerprint("test", "sentence"),
        token_index: 0,
        text: "word".into(),
        start_ms: 100,
        end_ms: 100,
        confidence: None,
        timing_source: TimingSource::AsrReported,
        provider_id: "whisper.cpp".into(),
        provider_version: "dtw-v1".into(),
    };

    assert!(!word_timing_cache_is_usable(&[timing]));
}

#[test]
fn forced_alignment_overrides_coarse_asr_timing() {
    assert!(
        timing_priority(TimingSource::ForcedAligned) > timing_priority(TimingSource::AsrReported)
    );
}

#[test]
fn asr_track_source_uses_inferred_punctuation_config() {
    assert_eq!(
        chunk_partition_config_for_track_source("ASR-Whisper Large.srt").punctuation_reliability,
        speech_analysis::chunk_partition::PunctuationReliability::Inferred
    );
    assert_eq!(
        chunk_partition_config_for_track_source("official-subtitles.srt").punctuation_reliability,
        speech_analysis::chunk_partition::PunctuationReliability::Trusted
    );
}

// ── phrase_candidates ───────────────────────────────────────────────────

fn make_sentence(tokens: Vec<SubtitleToken>) -> SubtitleSentence {
    SubtitleSentence {
        id: SubtitleSentenceId::from_fingerprint("test", "sent1"),
        index: 0,
        start: TimeMs::new(0),
        end: TimeMs::new(5000),
        original_text: tokens
            .iter()
            .map(|t| t.text.as_str())
            .collect::<Vec<_>>()
            .join(" "),
        display_text: tokens
            .iter()
            .map(|t| t.text.as_str())
            .collect::<Vec<_>>()
            .join(" "),
        tokens,
    }
}

fn word_token(index: u32, text: &str) -> SubtitleToken {
    SubtitleToken {
        index,
        kind: SubtitleTokenKind::Word,
        text: text.into(),
        normalized: Some(text.to_ascii_lowercase()),
        start_char: 0,
        end_char: text.len() as u32,
    }
}

#[test]
fn phrase_candidates_finds_known_phrase() {
    let sentence = make_sentence(vec![
        word_token(0, "give"),
        word_token(1, "up"),
        word_token(2, "now"),
    ]);
    let candidates = phrase_candidates(&sentence);
    assert!(
        candidates.iter().any(|c| c.normalized_form == "give up"),
        "should find 'give up' phrase"
    );
    let give_up = candidates
        .iter()
        .find(|c| c.normalized_form == "give up")
        .unwrap();
    assert_eq!(give_up.token_start, 0);
    assert_eq!(give_up.token_end, 1);
    assert_eq!(give_up.canonical_form, "give up");
}

#[test]
fn phrase_candidates_finds_phrase_mid_sentence() {
    let sentence = make_sentence(vec![
        word_token(0, "we"),
        word_token(1, "need"),
        word_token(2, "to"),
        word_token(3, "figure"),
        word_token(4, "out"),
        word_token(5, "the"),
        word_token(6, "problem"),
    ]);
    let candidates = phrase_candidates(&sentence);
    assert!(candidates.iter().any(|c| c.normalized_form == "figure out"));
    let fo = candidates
        .iter()
        .find(|c| c.normalized_form == "figure out")
        .unwrap();
    assert_eq!(fo.token_start, 3);
    assert_eq!(fo.token_end, 4);
}

#[test]
fn phrase_candidates_empty_for_no_match() {
    let sentence = make_sentence(vec![word_token(0, "hello"), word_token(1, "world")]);
    let candidates = phrase_candidates(&sentence);
    assert!(
        !candidates.iter().any(|c| c.normalized_form == "give up"),
        "should not find phrases in unrelated text"
    );
}

#[test]
fn phrase_candidates_finds_multiple_phrases() {
    let sentence = make_sentence(vec![
        word_token(0, "make"),
        word_token(1, "sure"),
        word_token(2, "you"),
        word_token(3, "pick"),
        word_token(4, "up"),
    ]);
    let candidates = phrase_candidates(&sentence);
    assert!(candidates.iter().any(|c| c.normalized_form == "make sure"));
    assert!(candidates.iter().any(|c| c.normalized_form == "pick up"));
}

#[test]
fn phrase_candidates_respects_token_boundaries() {
    // "in front of" should match correctly
    let sentence = make_sentence(vec![
        word_token(0, "stand"),
        word_token(1, "in"),
        word_token(2, "front"),
        word_token(3, "of"),
        word_token(4, "the"),
        word_token(5, "door"),
    ]);
    let candidates = phrase_candidates(&sentence);
    let fo = candidates
        .iter()
        .find(|c| c.normalized_form == "in front of")
        .unwrap();
    assert_eq!(fo.token_start, 1);
    assert_eq!(fo.token_end, 3);
}

#[test]
fn phrase_candidates_skips_non_word_tokens() {
    let sentence = SubtitleSentence {
        id: SubtitleSentenceId::from_fingerprint("test", "sent"),
        index: 0,
        start: TimeMs::new(0),
        end: TimeMs::new(1000),
        original_text: "give up.".into(),
        display_text: "give up.".into(),
        tokens: vec![
            word_token(0, "give"),
            word_token(1, "up"),
            SubtitleToken {
                index: 2,
                kind: SubtitleTokenKind::Punctuation,
                text: ".".into(),
                normalized: None,
                start_char: 0,
                end_char: 1,
            },
        ],
    };
    let candidates = phrase_candidates(&sentence);
    assert!(candidates.iter().any(|c| c.normalized_form == "give up"));
}

#[test]
fn phrase_candidates_with_normalized_matching() {
    // "Used to" should match "used to" phrase even with capitalization
    let sentence = make_sentence(vec![
        word_token(0, "I"),
        word_token(1, "used"),
        word_token(2, "to"),
        word_token(3, "swim"),
    ]);
    let candidates = phrase_candidates(&sentence);
    assert!(candidates.iter().any(|c| c.normalized_form == "used to"));
}

// ── now_ms ──────────────────────────────────────────────────────────────

#[test]
fn now_ms_returns_plausible_timestamp() {
    let ts = now_ms();
    // After year 2020 in milliseconds
    assert!(ts > 1_577_836_800_000);
    // Should be increasing
    let ts2 = now_ms();
    assert!(ts2 >= ts);
}
