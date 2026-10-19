//! Structural and cross-reference validation for known v2 payloads.
//!
//! These validators mirror the v1 invariants (half-open positive ranges,
//! contiguous indexes, explicit languages, locally checkable references) but
//! deliberately drop the v1 media-duration bound: v2 has no package-wide
//! media, duration, or fingerprint requirement, and no English-only default.

use std::collections::{HashMap, HashSet};

use crate::model::{
    AcousticTrack, PhoneTimeline, ProsodyAnalysis, SenseGroupAnalysis, SpeechActivity,
    SubtitleTextTrack, SubtitleToken, TokenRef, WordAcoustics, WordTimeline,
};

use super::payload::{DocumentText, KnownPayload, TimedTextTrack, Translation};

pub(crate) fn validate_document_text(payload: &DocumentText) -> Result<(), String> {
    validate_language_tag(&payload.language)?;
    if payload.text.is_empty() {
        return Err("document_text.text must not be empty".to_owned());
    }
    if payload.segments.is_empty() {
        return Err("document_text must declare at least one segment".to_owned());
    }
    let character_count = payload.text.chars().count() as u32;
    let mut segment_ids = HashSet::new();
    let mut previous_end = 0_u32;
    for (expected_index, segment) in payload.segments.iter().enumerate() {
        if segment.id.trim().is_empty() || !segment_ids.insert(&segment.id) {
            return Err("segment ids must be non-empty and unique".to_owned());
        }
        if segment.index as usize != expected_index {
            return Err("segment indexes must be contiguous".to_owned());
        }
        validate_language_tag(&segment.language)?;
        if segment.start_char != previous_end || segment.start_char >= segment.end_char {
            return Err("segment text anchors must be contiguous and half-open".to_owned());
        }
        if segment.end_char > character_count {
            return Err("segment text anchor exceeds the document text".to_owned());
        }
        previous_end = segment.end_char;
    }
    if previous_end != character_count {
        return Err("segments must cover the whole document text".to_owned());
    }
    Ok(())
}

pub(crate) fn validate_timed_text_track(payload: &TimedTextTrack) -> Result<(), String> {
    validate_language_tag(&payload.language)?;
    if payload.segments.is_empty() {
        return Err("timed_text_track must declare at least one segment".to_owned());
    }
    let mut segment_ids = HashSet::new();
    for (expected_index, segment) in payload.segments.iter().enumerate() {
        if segment.id.trim().is_empty() || !segment_ids.insert(&segment.id) {
            return Err("segment ids must be non-empty and unique".to_owned());
        }
        if segment.index as usize != expected_index {
            return Err("segment indexes must be contiguous".to_owned());
        }
        validate_language_tag(&segment.language)?;
        validate_half_open(segment.start_ms, segment.end_ms, "segment time span")?;
        if segment.text.trim().is_empty() {
            return Err("segment text must not be empty".to_owned());
        }
    }
    Ok(())
}

pub(crate) fn validate_translation(
    resource: &super::model::ReleaseResource,
    release: &super::model::PackageRelease,
    decoded: &HashMap<String, KnownPayload>,
    payload: &Translation,
    warnings: &mut Vec<String>,
) -> Result<(), String> {
    validate_language_tag(&payload.support_language)?;
    let descriptor = &resource.descriptor;
    if descriptor.role != super::model::ResourceRole::Assistance {
        return Err("translation resource must have assistance role".to_owned());
    }
    if !descriptor
        .support_languages
        .contains(&payload.support_language)
    {
        return Err("translation support_language must be declared by the resource".to_owned());
    }
    let base = release
        .resources
        .iter()
        .find(|candidate| candidate.resource_id == payload.base_resource_id)
        .ok_or_else(|| "translation base_resource_id is not declared".to_owned())?;
    if base.descriptor.role != super::model::ResourceRole::Base {
        return Err("translation base_resource_id must reference a Base Resource".to_owned());
    }
    if !descriptor
        .dependencies
        .iter()
        .any(|dependency| dependency.resource_id == payload.base_resource_id)
    {
        return Err("translation base_resource_id must be a dependency of the resource".to_owned());
    }
    if payload.segments.is_empty() {
        return Err("translation must declare at least one segment".to_owned());
    }
    let mut segment_ids = HashSet::new();
    for (expected_index, segment) in payload.segments.iter().enumerate() {
        if segment.id.trim().is_empty() || !segment_ids.insert(&segment.id) {
            return Err("translation segment ids must be non-empty and unique".to_owned());
        }
        if segment.index as usize != expected_index {
            return Err("translation segment indexes must be contiguous".to_owned());
        }
        if segment.text.trim().is_empty() {
            return Err("translation segment text must not be empty".to_owned());
        }
    }
    // Validate source segment references against the base payload when the
    // base payload is embedded and known; otherwise warn instead of assuming.
    match decoded.get(&payload.base_resource_id) {
        Some(KnownPayload::DocumentText(base_payload)) => {
            let base_ids: Vec<&str> = base_payload
                .segments
                .iter()
                .map(|s| s.id.as_str())
                .collect();
            validate_translation_segment_refs(payload, &base_ids)
        }
        Some(KnownPayload::TimedTextTrack(base_payload)) => {
            let base_ids: Vec<&str> = base_payload
                .segments
                .iter()
                .map(|s| s.id.as_str())
                .collect();
            validate_translation_segment_refs(payload, &base_ids)
        }
        Some(_) => Err("translation base resource payload kind is unsupported".to_owned()),
        None => {
            warnings.push(format!(
                "{}: translation base payload is absent; source segments not verified",
                resource.resource_id
            ));
            Ok(())
        }
    }
}

fn validate_translation_segment_refs(
    payload: &Translation,
    base_segment_ids: &[&str],
) -> Result<(), String> {
    for segment in &payload.segments {
        if !base_segment_ids.contains(&segment.source_segment_id.as_str()) {
            return Err(format!(
                "translation references unknown base segment {}",
                segment.source_segment_id
            ));
        }
    }
    Ok(())
}

pub(crate) fn validate_subtitle_text_track(payload: &SubtitleTextTrack) -> Result<(), String> {
    validate_language_tag(&payload.language)?;
    if payload.sentences.is_empty() {
        return Err("subtitle_text_track must declare at least one sentence".to_owned());
    }
    let mut sentence_ids = HashSet::new();
    for (expected_index, sentence) in payload.sentences.iter().enumerate() {
        if sentence.id.trim().is_empty() || !sentence_ids.insert(&sentence.id) {
            return Err("sentence ids must be non-empty and unique".to_owned());
        }
        if sentence.index as usize != expected_index {
            return Err("sentence indexes must be contiguous".to_owned());
        }
        validate_half_open(sentence.start_ms, sentence.end_ms, "sentence time span")?;
        validate_tokens(&sentence.original_text, &sentence.tokens)?;
    }
    Ok(())
}

fn validate_tokens(text: &str, tokens: &[SubtitleToken]) -> Result<(), String> {
    let character_count = text.chars().count();
    let mut token_indexes = HashSet::new();
    let mut previous_char_end = 0_u32;
    for (expected_index, token) in tokens.iter().enumerate() {
        if token.text.is_empty()
            || token.start_char >= token.end_char
            || token.end_char as usize > character_count
        {
            return Err("token text and half-open character range are invalid".to_owned());
        }
        if !token_indexes.insert(token.index)
            || token.index as usize != expected_index
            || token.start_char != previous_char_end
        {
            return Err("token indexes must be unique and contiguous".to_owned());
        }
        let actual = text
            .chars()
            .skip(token.start_char as usize)
            .take((token.end_char - token.start_char) as usize)
            .collect::<String>();
        if actual != token.text {
            return Err("token text differs from its character span".to_owned());
        }
        previous_char_end = token.end_char;
    }
    if !tokens.is_empty() && previous_char_end as usize != character_count {
        return Err("tokens must cover the original text".to_owned());
    }
    Ok(())
}

pub(crate) fn validate_word_timeline(
    payload: &WordTimeline,
    subtitle: Option<&SubtitleTextTrack>,
) -> Result<(), String> {
    if payload.words.is_empty() {
        return Err("word_timeline must not be empty".to_owned());
    }
    let Some(subtitle) = subtitle else {
        return Err("word_timeline requires an embedded subtitle_text_track anchor".to_owned());
    };
    let mut previous_reference = None;
    let mut previous_time = None;
    let mut word_refs = HashSet::new();
    for word in &payload.words {
        validate_half_open(word.start_ms, word.end_ms, "word timing span")?;
        validate_confidence(word.confidence, "word timing confidence")?;
        let sentence = sentence(subtitle, &word.sentence_id)?;
        validate_word_token(sentence, word.token_index)?;
        if word.start_ms < sentence.start_ms || word.end_ms > sentence.end_ms {
            return Err("word timing is outside its subtitle sentence".to_owned());
        }
        let reference_order = (sentence.index, word.token_index);
        let time_order = (word.start_ms, word.end_ms);
        if previous_reference.is_some_and(|previous| previous >= reference_order)
            || previous_time.is_some_and(|previous| previous > time_order)
            || !word_refs.insert((word.sentence_id.as_str(), word.token_index))
        {
            return Err("word timings are not monotonic in presentation order".to_owned());
        }
        previous_reference = Some(reference_order);
        previous_time = Some(time_order);
    }
    Ok(())
}

pub(crate) fn validate_phone_timeline(
    payload: &PhoneTimeline,
    subtitle: Option<&SubtitleTextTrack>,
    word_timeline: Option<&WordTimeline>,
) -> Result<(), String> {
    if payload.phone_set.trim().is_empty() {
        return Err("phone_set must not be empty".to_owned());
    }
    if payload.phones.is_empty() {
        return Err("phone_timeline must not be empty".to_owned());
    }
    let mut previous_time = None;
    for phone in &payload.phones {
        validate_half_open(phone.start_ms, phone.end_ms, "phone time span")?;
        validate_confidence(phone.confidence, "phone confidence")?;
        if phone.symbol.trim().is_empty() {
            return Err("phone symbol must not be empty".to_owned());
        }
        let time_order = (phone.start_ms, phone.end_ms);
        if previous_time.is_some_and(|previous| previous > time_order) {
            return Err("phone timings are not monotonic".to_owned());
        }
        previous_time = Some(time_order);
        if let Some(word_ref) = &phone.word_ref {
            if let Some(word_timeline) = word_timeline {
                validate_timeline_word_ref(word_timeline, word_ref)?;
            }
            if let Some(subtitle) = subtitle {
                let sentence = sentence(subtitle, &word_ref.sentence_id)?;
                validate_word_token(sentence, word_ref.token_index)?;
                if phone.start_ms < sentence.start_ms || phone.end_ms > sentence.end_ms {
                    return Err("phone timing is outside its subtitle sentence".to_owned());
                }
            }
        }
    }
    Ok(())
}

pub(crate) fn validate_sense_group_analysis(
    payload: &SenseGroupAnalysis,
    subtitle: Option<&SubtitleTextTrack>,
) -> Result<(), String> {
    if payload.groups.is_empty() {
        return Err("sense_group_analysis must not be empty".to_owned());
    }
    let Some(subtitle) = subtitle else {
        return Err(
            "sense_group_analysis requires an embedded subtitle_text_track anchor".to_owned(),
        );
    };
    let mut indexes_by_sentence = HashMap::<&str, u32>::new();
    let mut end_by_sentence = HashMap::<&str, u32>::new();
    for group in &payload.groups {
        validate_confidence(Some(group.confidence), "sense group confidence")?;
        validate_token_span(
            subtitle,
            &group.sentence_id,
            group.start_token_index,
            group.end_token_index_exclusive,
        )?;
        if let Some(head) = group.head_token_index
            && (head < group.start_token_index || head >= group.end_token_index_exclusive)
        {
            return Err("sense group head is outside its token span".to_owned());
        }
        let expected = indexes_by_sentence.entry(&group.sentence_id).or_default();
        if group.group_index != *expected
            || end_by_sentence
                .get(group.sentence_id.as_str())
                .is_some_and(|end| group.start_token_index < *end)
            || group.sources.is_empty()
        {
            return Err("sense groups are not a valid ordered partition".to_owned());
        }
        *expected += 1;
        end_by_sentence.insert(&group.sentence_id, group.end_token_index_exclusive);
    }
    Ok(())
}

pub(crate) fn validate_word_acoustics(
    payload: &WordAcoustics,
    subtitle: Option<&SubtitleTextTrack>,
    word_timeline: Option<&WordTimeline>,
) -> Result<(), String> {
    if payload.sample_rate_hz == 0 {
        return Err("sample_rate_hz must be positive".to_owned());
    }
    if payload.measurements.is_empty() {
        return Err("word_acoustics must not be empty".to_owned());
    }
    for measurement in &payload.measurements {
        if measurement.duration.duration_ms == 0 {
            return Err("acoustic duration must be positive".to_owned());
        }
        validate_confidence(measurement.voiced_frame_ratio, "voiced frame ratio")?;
        validate_confidence(measurement.energy.prominence, "energy prominence")?;
        validate_confidence(measurement.pitch.prominence, "pitch prominence")?;
        validate_confidence(measurement.pitch.reset_after, "pitch reset")?;
        for (label, value) in [
            ("rms_dbfs", measurement.energy.rms_dbfs),
            (
                "local_baseline_dbfs",
                measurement.energy.local_baseline_dbfs,
            ),
            ("delta_db", measurement.energy.delta_db),
            ("median_f0_hz", measurement.pitch.median_f0_hz),
            (
                "local_baseline_f0_hz",
                measurement.pitch.local_baseline_f0_hz,
            ),
            ("delta_semitones", measurement.pitch.delta_semitones),
            ("range_semitones", measurement.pitch.range_semitones),
            ("local_ratio", measurement.duration.local_ratio),
        ] {
            if value.is_some_and(|number| !number.is_finite()) {
                return Err(format!("{label} must be finite"));
            }
        }
        for (label, value) in [
            ("median_f0_hz", measurement.pitch.median_f0_hz),
            (
                "local_baseline_f0_hz",
                measurement.pitch.local_baseline_f0_hz,
            ),
            ("local_ratio", measurement.duration.local_ratio),
        ] {
            if value.is_some_and(|number| number <= 0.0) {
                return Err(format!("{label} must be positive"));
            }
        }
        if measurement
            .pitch
            .range_semitones
            .is_some_and(|number| number < 0.0)
        {
            return Err("range_semitones must be non-negative".to_owned());
        }
        if let Some(word_timeline) = word_timeline {
            validate_timeline_word_ref(word_timeline, &measurement.word_ref)?;
        }
        if let Some(subtitle) = subtitle {
            let sentence = sentence(subtitle, &measurement.word_ref.sentence_id)?;
            validate_word_token(sentence, measurement.word_ref.token_index)?;
        }
    }
    Ok(())
}

/// Structural validation for `acoustic_track` v1, mirroring the invariants Gen
/// already guarantees at qualification: at least one frame; strictly increasing
/// frame `time_ms` that lands on the fixed `frame_step_ms`; finite energy; and
/// `f0_rel_st` present only when `f0_hz` is present. Audio-only evidence, so
/// there is no subtitle or timeline reference to cross-check.
pub(crate) fn validate_acoustic_track(payload: &AcousticTrack) -> Result<(), String> {
    if payload.sample_rate_hz == 0 {
        return Err("acoustic_track sample_rate_hz must be positive".to_owned());
    }
    if payload.frame_step_ms == 0 {
        return Err("acoustic_track frame_step_ms must be positive".to_owned());
    }
    if payload.frames.is_empty() {
        return Err("acoustic_track must declare at least one frame".to_owned());
    }
    let step = u64::from(payload.frame_step_ms);
    let mut previous_time: Option<u64> = None;
    for frame in &payload.frames {
        if !frame.energy_dbfs.is_finite() || !frame.energy_rel_db.is_finite() {
            return Err("acoustic_track energy must be finite".to_owned());
        }
        if let Some(previous) = previous_time {
            if frame.time_ms <= previous {
                return Err("acoustic_track frame times must strictly increase".to_owned());
            }
            if frame.time_ms - previous != step {
                return Err("acoustic_track frame times must land on frame_step_ms".to_owned());
            }
        }
        previous_time = Some(frame.time_ms);
        match (frame.f0_hz, frame.f0_rel_st) {
            (None, Some(_)) => {
                return Err("acoustic_track f0_rel_st must be null when f0_hz is null".to_owned());
            }
            (Some(hz), _) if !hz.is_finite() || hz <= 0.0 => {
                return Err("acoustic_track f0_hz must be a positive finite value".to_owned());
            }
            _ => {}
        }
        if frame.f0_rel_st.is_some_and(|value| !value.is_finite()) {
            return Err("acoustic_track f0_rel_st must be finite".to_owned());
        }
    }
    Ok(())
}

/// Structural validation for `speech_activity` v1, mirroring Gen: at least one
/// span; every span half-open and positive; spans ordered and non-overlapping.
/// The `activity` label is constrained to speech/silence by the payload enum.
pub(crate) fn validate_speech_activity(payload: &SpeechActivity) -> Result<(), String> {
    if payload.spans.is_empty() {
        return Err("speech_activity must declare at least one span".to_owned());
    }
    let mut previous_end: Option<u64> = None;
    for span in &payload.spans {
        validate_half_open(span.start_ms, span.end_ms, "speech activity span")?;
        if previous_end.is_some_and(|previous| span.start_ms < previous) {
            return Err("speech_activity spans must be ordered and non-overlapping".to_owned());
        }
        previous_end = Some(span.end_ms);
    }
    Ok(())
}

pub(crate) fn validate_prosody_analysis(
    payload: &ProsodyAnalysis,
    subtitle: Option<&SubtitleTextTrack>,
    word_timeline: Option<&WordTimeline>,
) -> Result<(), String> {
    let mut indexes_by_sentence = HashMap::<&str, u32>::new();
    let mut end_by_sentence = HashMap::<&str, u32>::new();
    for chunk in &payload.chunks {
        validate_confidence(Some(chunk.confidence), "prosodic chunk confidence")?;
        if let Some(subtitle) = subtitle {
            validate_token_span(
                subtitle,
                &chunk.sentence_id,
                chunk.start_token_index,
                chunk.end_token_index_exclusive,
            )?;
            if chunk.nucleus_token_index.is_some_and(|index| {
                index < chunk.start_token_index || index >= chunk.end_token_index_exclusive
            }) {
                return Err("prosodic chunk nucleus is outside its token span".to_owned());
            }
            let expected = indexes_by_sentence.entry(&chunk.sentence_id).or_default();
            if chunk.chunk_index != *expected
                || end_by_sentence
                    .get(chunk.sentence_id.as_str())
                    .is_some_and(|end| chunk.start_token_index < *end)
            {
                return Err("prosodic chunks are not ordered non-overlapping spans".to_owned());
            }
            *expected += 1;
            end_by_sentence.insert(&chunk.sentence_id, chunk.end_token_index_exclusive);
        }
    }
    for anchor in &payload.anchors {
        validate_confidence(Some(anchor.confidence), "prosody confidence")?;
        validate_confidence(Some(anchor.realized_prominence), "realized prominence")?;
        if anchor.evidence.is_empty() {
            return Err("prosody evidence must not be empty".to_owned());
        }
        let unique = anchor.evidence.iter().collect::<HashSet<_>>();
        if unique.len() != anchor.evidence.len() {
            return Err("prosody evidence must be unique".to_owned());
        }
        if let Some(word_timeline) = word_timeline {
            validate_timeline_word_ref(word_timeline, &anchor.word_ref)?;
        }
        if let Some(subtitle) = subtitle {
            let sentence = sentence(subtitle, &anchor.word_ref.sentence_id)?;
            validate_word_token(sentence, anchor.word_ref.token_index)?;
        }
    }
    Ok(())
}

fn sentence<'a>(
    subtitle: &'a SubtitleTextTrack,
    sentence_id: &str,
) -> Result<&'a crate::model::SubtitleSentence, String> {
    subtitle
        .sentences
        .iter()
        .find(|sentence| sentence.id == sentence_id)
        .ok_or_else(|| format!("unknown subtitle sentence {sentence_id}"))
}

fn validate_word_token(
    sentence: &crate::model::SubtitleSentence,
    token_index: u32,
) -> Result<(), String> {
    let token = sentence
        .tokens
        .iter()
        .find(|token| token.index == token_index)
        .ok_or_else(|| format!("unknown subtitle token {token_index}"))?;
    if token.kind != crate::model::TokenKind::Word {
        return Err("word reference does not identify a word token".to_owned());
    }
    Ok(())
}

fn validate_timeline_word_ref(timeline: &WordTimeline, word_ref: &TokenRef) -> Result<(), String> {
    if timeline.words.iter().any(|word| {
        word.sentence_id == word_ref.sentence_id && word.token_index == word_ref.token_index
    }) {
        Ok(())
    } else {
        Err("word reference is absent from the depended-on word timeline".to_owned())
    }
}

fn validate_token_span(
    subtitle: &SubtitleTextTrack,
    segment_id: &str,
    start: u32,
    end_exclusive: u32,
) -> Result<(), String> {
    if start >= end_exclusive {
        return Err("token span must be non-empty and half-open".to_owned());
    }
    let sentence = sentence(subtitle, segment_id)?;
    if end_exclusive as usize > sentence.tokens.len() {
        return Err("token span exceeds its subtitle sentence".to_owned());
    }
    Ok(())
}

pub(crate) fn validate_half_open(start: u64, end: u64, label: &str) -> Result<(), String> {
    if start >= end {
        Err(format!("{label} must be half-open and positive"))
    } else {
        Ok(())
    }
}

pub(crate) fn validate_confidence(value: Option<f64>, label: &str) -> Result<(), String> {
    if value.is_some_and(|number| !number.is_finite() || !(0.0..=1.0).contains(&number)) {
        Err(format!("{label} must be within 0..=1"))
    } else {
        Ok(())
    }
}

/// Validates a BCP47-style language tag: non-empty hyphen-separated subtags
/// of ASCII letters and digits. Underscores are rejected and there is no
/// default language: an explicit tag is required.
pub(crate) fn validate_language_tag(tag: &str) -> Result<(), String> {
    if tag.is_empty() {
        return Err("language tag must not be empty".to_owned());
    }
    if tag.contains('_') {
        return Err(format!("language tag must use hyphens only: {tag}"));
    }
    let valid = tag.split('-').all(|subtag| {
        !subtag.is_empty()
            && subtag
                .chars()
                .all(|character| character.is_ascii_alphanumeric())
    });
    if !valid {
        return Err(format!("invalid language tag: {tag}"));
    }
    Ok(())
}

/// Rejects local paths, file URLs, credentials, fragments, and non-HTTPS
/// acquisition hints. The hint is never fetched during inspection.
pub(crate) fn validate_https_hint(url: &str) -> Result<(), String> {
    let parsed = url::Url::parse(url).map_err(|_| "acquisition hint is not a valid URL")?;
    if parsed.scheme() != "https" {
        return Err("acquisition hint must use https".to_owned());
    }
    if !parsed.username().is_empty() || parsed.password().is_some() {
        return Err("acquisition hint must not contain credentials".to_owned());
    }
    if parsed.fragment().is_some() {
        return Err("acquisition hint must not contain a fragment".to_owned());
    }
    if parsed.host_str().is_none() || parsed.host_str() == Some("") {
        return Err("acquisition hint must name a host".to_owned());
    }
    Ok(())
}

#[cfg(test)]
mod acoustic_evidence_tests {
    use super::{validate_acoustic_track, validate_speech_activity};
    use crate::model::{AcousticTrack, SpeechActivity};

    // Mirrors the exact `listen.payload.acoustic-track.v1` payload Gen writes
    // (see listen-gen rich.py `_acoustic_track_resource`): four 10 ms frames,
    // unvoiced frames carry null pitch, voiced frames carry both f0 fields.
    fn valid_track() -> AcousticTrack {
        serde_json::from_value(serde_json::json!({
            "sample_rate_hz": 16000,
            "frame_step_ms": 10,
            "energy_baseline": "recording_median_dbfs",
            "pitch_baseline": "recording_median_f0_hz",
            "frames": [
                {"time_ms": 0, "energy_dbfs": -55.0, "energy_rel_db": -8.0, "f0_hz": null, "f0_rel_st": null, "voiced": false},
                {"time_ms": 10, "energy_dbfs": -22.0, "energy_rel_db": 6.0, "f0_hz": 182.0, "f0_rel_st": 1.2, "voiced": true},
                {"time_ms": 20, "energy_dbfs": -24.0, "energy_rel_db": 4.0, "f0_hz": 176.0, "f0_rel_st": 0.7, "voiced": true},
                {"time_ms": 30, "energy_dbfs": -47.0, "energy_rel_db": -3.0, "f0_hz": null, "f0_rel_st": null, "voiced": false}
            ]
        }))
        .expect("valid acoustic track payload decodes")
    }

    fn valid_activity() -> SpeechActivity {
        serde_json::from_value(serde_json::json!({
            "spans": [
                {"start_ms": 0, "end_ms": 100, "activity": "silence"},
                {"start_ms": 100, "end_ms": 1900, "activity": "speech"},
                {"start_ms": 1900, "end_ms": 2200, "activity": "silence"}
            ]
        }))
        .expect("valid speech activity payload decodes")
    }

    #[test]
    fn accepts_gen_shaped_payloads() {
        assert!(validate_acoustic_track(&valid_track()).is_ok());
        assert!(validate_speech_activity(&valid_activity()).is_ok());
    }

    #[test]
    fn rejects_empty_frames_and_spans() {
        let mut track = valid_track();
        track.frames.clear();
        assert!(validate_acoustic_track(&track).is_err());
        let mut activity = valid_activity();
        activity.spans.clear();
        assert!(validate_speech_activity(&activity).is_err());
    }

    #[test]
    fn rejects_frame_time_off_the_fixed_hop() {
        let mut track = valid_track();
        track.frames[2].time_ms = 25; // 15 ms gap, not the declared 10 ms hop
        assert!(validate_acoustic_track(&track).is_err());
    }

    #[test]
    fn rejects_non_increasing_frame_time() {
        let mut track = valid_track();
        track.frames[2].time_ms = 10; // equal to the previous frame
        assert!(validate_acoustic_track(&track).is_err());
    }

    #[test]
    fn rejects_pitch_rel_without_pitch_hz() {
        let mut track = valid_track();
        track.frames[0].f0_rel_st = Some(0.5); // f0_hz is null → relative pitch is impossible
        assert!(validate_acoustic_track(&track).is_err());
    }

    #[test]
    fn rejects_overlapping_or_backwards_spans() {
        let mut activity = valid_activity();
        activity.spans[1].start_ms = 50; // overlaps the previous span [0,100)
        assert!(validate_speech_activity(&activity).is_err());
        let mut activity = valid_activity();
        activity.spans[1].end_ms = activity.spans[1].start_ms; // empty span
        assert!(validate_speech_activity(&activity).is_err());
    }
}
