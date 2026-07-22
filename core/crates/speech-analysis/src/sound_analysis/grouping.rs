use domain::{
    ConnectedSpeechExplanation, RhythmCompressionSpan, RhythmEvidenceClass, RhythmSignalSource,
    RhythmStressAnchor, RhythmWeakGroup,
};

use super::anchors::claim_status;
use super::constants::{COMPRESSION_UNIT_MS, COMPRESSION_WORD_MS, PAUSE_BOUNDARY_MS};
use super::helpers::{clamp01, overlaps_token_range, score_flag};
use super::tokens::RhythmToken;

pub(super) fn detect_weak_groups(
    tokens: &[RhythmToken],
    anchors: &[RhythmStressAnchor],
    connected_speech: &[ConnectedSpeechExplanation],
) -> Vec<RhythmWeakGroup> {
    let mut values = Vec::new();
    let mut cursor = 0usize;
    while cursor < tokens.len() {
        if !tokens[cursor].is_function_word() {
            cursor += 1;
            continue;
        }
        let start = cursor;
        while cursor + 1 < tokens.len()
            && tokens[cursor + 1].is_function_word()
            && tokens[cursor + 1]
                .start_ms
                .saturating_sub(tokens[cursor].end_ms)
                < PAUSE_BOUNDARY_MS
        {
            cursor += 1;
        }
        let end = cursor;
        let group = &tokens[start..=end];
        let duration = group
            .last()
            .map(|token| token.end_ms)
            .unwrap_or(0)
            .saturating_sub(group.first().map(|token| token.start_ms).unwrap_or(0))
            .max(1);
        let short_duration = duration as f32 / group.len() as f32 <= COMPRESSION_WORD_MS;
        let has_connected_speech = connected_speech.iter().any(|value| {
            overlaps_token_range(
                value.token_start,
                value.token_end.or(value.token_start),
                Some(group.first().unwrap().index),
                Some(group.last().unwrap().index),
            )
        });
        let confidence = clamp01(
            0.52 + score_flag(short_duration) * 0.14 + score_flag(has_connected_speech) * 0.12,
        );
        let anchor_token_index = nearest_anchor_token(
            group.first().unwrap().index,
            group.last().unwrap().index,
            anchors,
        );
        let mut signal_sources = vec![RhythmSignalSource::TextPrior];
        if short_duration && group.iter().all(|token| token.timing_audio_supported) {
            signal_sources.push(RhythmSignalSource::Timing);
        }
        let reduction_refs = connected_speech
            .iter()
            .enumerate()
            .filter(|&(_index, value)| {
                overlaps_token_range(
                    value.token_start,
                    value.token_end.or(value.token_start),
                    Some(group.first().unwrap().index),
                    Some(group.last().unwrap().index),
                )
            })
            .map(|(index, _value)| format!("cs{}", index + 1))
            .collect::<Vec<_>>();
        let claim_status = claim_status(&signal_sources);
        values.push(RhythmWeakGroup {
            token_start: Some(group.first().unwrap().index),
            token_end: Some(group.last().unwrap().index),
            phone_start: group.first().unwrap().phone_start,
            phone_end: group.last().unwrap().phone_end,
            anchor_token_index,
            start_ms: group.first().unwrap().start_ms,
            end_ms: group.last().unwrap().end_ms,
            label: group
                .iter()
                .map(|token| token.text.as_str())
                .collect::<Vec<_>>()
                .join(" "),
            reason: "These function words are likely backgrounded around the nearest anchor."
                .into(),
            reduction_refs,
            signal_sources,
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status,
            confidence,
        });
        cursor += 1;
    }
    values
}

pub(super) fn detect_compression_spans(tokens: &[RhythmToken]) -> Vec<RhythmCompressionSpan> {
    let mut values = Vec::new();
    let mut cursor = 0usize;
    while cursor < tokens.len() {
        let mut best_end = None;
        for end in cursor + 1..tokens.len().min(cursor + 5) {
            if tokens[end].start_ms.saturating_sub(tokens[end - 1].end_ms) >= PAUSE_BOUNDARY_MS {
                break;
            }
            let group = &tokens[cursor..=end];
            let expected_units = group.iter().map(RhythmToken::expected_units).sum::<u32>();
            let duration = group
                .last()
                .unwrap()
                .end_ms
                .saturating_sub(group.first().unwrap().start_ms)
                .max(1);
            let unit_ms = duration as f32 / expected_units.max(1) as f32;
            let word_ms = duration as f32 / group.len() as f32;
            if expected_units >= 4
                && (unit_ms <= COMPRESSION_UNIT_MS || word_ms <= COMPRESSION_WORD_MS)
            {
                best_end = Some(end);
            }
        }
        let Some(end) = best_end else {
            cursor += 1;
            continue;
        };
        let group = &tokens[cursor..=end];
        let expected_units = group.iter().map(RhythmToken::expected_units).sum::<u32>();
        let duration = group
            .last()
            .unwrap()
            .end_ms
            .saturating_sub(group.first().unwrap().start_ms)
            .max(1);
        let unit_rate_per_second = expected_units as f32 * 1000.0 / duration as f32;
        let unit_ms = duration as f32 / expected_units.max(1) as f32;
        let confidence = clamp01(0.5 + ((COMPRESSION_UNIT_MS - unit_ms).max(0.0) / 100.0));
        let signal_sources = if group.iter().all(|token| token.timing_audio_supported) {
            vec![RhythmSignalSource::Timing]
        } else {
            vec![RhythmSignalSource::TextPrior]
        };
        let claim_status = claim_status(&signal_sources);
        values.push(RhythmCompressionSpan {
            token_start: Some(group.first().unwrap().index),
            token_end: Some(group.last().unwrap().index),
            phone_start: group.first().unwrap().phone_start,
            phone_end: group.last().unwrap().phone_end,
            start_ms: group.first().unwrap().start_ms,
            end_ms: group.last().unwrap().end_ms,
            expected_units,
            duration_ms: duration,
            unit_rate_per_second,
            label: group
                .iter()
                .map(|token| token.text.as_str())
                .collect::<Vec<_>>()
                .join(" "),
            reason: "Several expected sounds are packed into a short time window.".into(),
            signal_sources,
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status,
            confidence,
        });
        cursor = end + 1;
    }
    values
}

fn nearest_anchor_token(
    group_start: u32,
    group_end: u32,
    anchors: &[RhythmStressAnchor],
) -> Option<u32> {
    anchors
        .iter()
        .filter_map(|anchor| anchor.token_index)
        .min_by_key(|index| {
            if *index < group_start {
                group_start - *index
            } else {
                index.saturating_sub(group_end)
            }
        })
}
