use domain::{
    ConnectedSpeechExplanation, ConnectedSpeechExplanationStatus, ListeningHotspot,
    ListeningHotspotKind, RhythmCompressionSpan, RhythmEvidenceClass, RhythmSignalSource,
    RhythmWeakGroup, SoundLearningPhone,
};

use super::anchors::claim_status;
use super::tokens::RhythmToken;

pub(super) fn build_listening_hotspots(
    weak_groups: &[RhythmWeakGroup],
    compression_spans: &[RhythmCompressionSpan],
    connected_speech: &[ConnectedSpeechExplanation],
    learning_phones: &[SoundLearningPhone],
    tokens: &[RhythmToken],
) -> Vec<ListeningHotspot> {
    let mut values = Vec::new();
    for group in weak_groups {
        values.push(ListeningHotspot {
            id: format!("hs{}", values.len() + 1),
            kind: ListeningHotspotKind::WeakGroup,
            token_start: group.token_start,
            token_end: group.token_end,
            phone_start: group.phone_start,
            phone_end: group.phone_end,
            start_ms: group.start_ms,
            end_ms: group.end_ms,
            label: "weak group".into(),
            hint: format!(
                "{} is likely backgrounded; listen through it toward the next anchor.",
                group.label
            ),
            signal_sources: group.signal_sources.clone(),
            evidence_class: group.evidence_class,
            claim_status: group.claim_status,
            confidence: group.confidence,
        });
    }
    for span in compression_spans {
        values.push(ListeningHotspot {
            id: format!("hs{}", values.len() + 1),
            kind: ListeningHotspotKind::CompressedSpan,
            token_start: span.token_start,
            token_end: span.token_end,
            phone_start: span.phone_start,
            phone_end: span.phone_end,
            start_ms: span.start_ms,
            end_ms: span.end_ms,
            label: "compressed span".into(),
            hint: format!(
                "{} is packed into a short span; catch the surrounding anchors first.",
                span.label
            ),
            signal_sources: span.signal_sources.clone(),
            evidence_class: span.evidence_class,
            claim_status: span.claim_status,
            confidence: span.confidence,
        });
    }
    for explanation in connected_speech {
        let confidence = match explanation.status {
            ConnectedSpeechExplanationStatus::PossibleByRule => explanation.confidence.min(0.69),
            _ => explanation.confidence,
        };
        let predicted_by_rule =
            crate::connected_speech_rules::is_default_rule_explanation(explanation);
        let signal_sources = match explanation.status {
            ConnectedSpeechExplanationStatus::PossibleByRule => vec![RhythmSignalSource::TextPrior],
            ConnectedSpeechExplanationStatus::SupportedByAudio
            | ConnectedSpeechExplanationStatus::DetectedInAudio
                if predicted_by_rule =>
            {
                vec![
                    RhythmSignalSource::TextPrior,
                    RhythmSignalSource::PhoneSegmental,
                ]
            }
            ConnectedSpeechExplanationStatus::SupportedByAudio
            | ConnectedSpeechExplanationStatus::DetectedInAudio => {
                vec![RhythmSignalSource::PhoneSegmental]
            }
        };
        let claim_status = claim_status(&signal_sources);
        let (start_ms, end_ms) = phone_range_timing(
            learning_phones,
            explanation.phone_start,
            explanation.phone_end,
        )
        .or_else(|| token_range_timing(tokens, explanation.token_start, explanation.token_end))
        .unwrap_or((0, 1));
        values.push(ListeningHotspot {
            id: format!("hs{}", values.len() + 1),
            kind: ListeningHotspotKind::ConnectedSpeech,
            token_start: explanation.token_start,
            token_end: explanation.token_end.or(explanation.token_start),
            phone_start: explanation.phone_start,
            phone_end: explanation.phone_end,
            start_ms,
            end_ms,
            label: explanation.label.clone(),
            hint: explanation.hint.clone(),
            signal_sources,
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status,
            confidence,
        });
    }
    values
}

fn phone_range_timing(
    learning_phones: &[SoundLearningPhone],
    phone_start: Option<u32>,
    phone_end: Option<u32>,
) -> Option<(u64, u64)> {
    let start = phone_start? as usize;
    let end = phone_end? as usize;
    if start > end || end >= learning_phones.len() {
        return None;
    }
    let values = &learning_phones[start..=end];
    let start_ms = values.iter().map(|phone| phone.start_ms).min()?;
    let end_ms = values.iter().map(|phone| phone.end_ms).max()?;
    Some((start_ms, end_ms.max(start_ms + 1)))
}

fn token_range_timing(
    tokens: &[RhythmToken],
    token_start: Option<u32>,
    token_end: Option<u32>,
) -> Option<(u64, u64)> {
    let start = token_start?;
    let end = token_end.or(token_start)?;
    let values = tokens
        .iter()
        .filter(|token| token.index >= start && token.index <= end)
        .collect::<Vec<_>>();
    if values.is_empty() {
        return None;
    }
    let start_ms = values.iter().map(|token| token.start_ms).min()?;
    let end_ms = values.iter().map(|token| token.end_ms).max()?;
    Some((start_ms, end_ms.max(start_ms + 1)))
}
