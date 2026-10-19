use domain::{
    ConnectedSpeechExplanation, ConnectedSpeechExplanationStatus, RhythmCompressionSpan,
    RhythmPhraseBoundary, RhythmSignalSource, RhythmStressAnchor, RhythmWeakGroup,
    SoundLearningPhone,
};

use super::helpers::clamp01;

pub(super) fn timing_source_label(
    uses_word_timeline: bool,
    uses_audio_timing: bool,
    uses_estimated_word_timing: bool,
) -> &'static str {
    if uses_word_timeline && uses_audio_timing && uses_estimated_word_timing {
        "word_timeline_mixed"
    } else if uses_word_timeline && uses_audio_timing {
        "word_timeline"
    } else if uses_word_timeline {
        "word_timeline_estimated"
    } else {
        "phone_timeline_transitional"
    }
}

pub(super) fn prominence_sources(
    uses_audio_timing: bool,
    uses_energy_cues: bool,
    uses_pitch_cues: bool,
) -> Vec<RhythmSignalSource> {
    let mut sources = vec![RhythmSignalSource::TextPrior];
    if uses_audio_timing {
        sources.push(RhythmSignalSource::Timing);
    }
    if uses_energy_cues {
        sources.push(RhythmSignalSource::Energy);
    }
    if uses_pitch_cues {
        sources.push(RhythmSignalSource::Pitch);
    }
    sources
}

pub(super) fn boundary_sources(boundaries: &[RhythmPhraseBoundary]) -> Vec<RhythmSignalSource> {
    let mut sources = Vec::new();
    for boundary in boundaries {
        for source in &boundary.signal_sources {
            if !sources.contains(source) {
                sources.push(*source);
            }
        }
    }
    sources
}

pub(super) fn connected_speech_quality_source(
    connected_speech: &[ConnectedSpeechExplanation],
) -> RhythmSignalSource {
    if connected_speech.iter().any(|value| {
        matches!(
            value.status,
            ConnectedSpeechExplanationStatus::SupportedByAudio
                | ConnectedSpeechExplanationStatus::DetectedInAudio
        )
    }) {
        RhythmSignalSource::PhoneSegmental
    } else {
        RhythmSignalSource::TextPrior
    }
}

pub(super) fn phone_evidence_coverage(learning_phones: &[SoundLearningPhone]) -> f32 {
    if learning_phones.is_empty() {
        return 0.0;
    }
    learning_phones
        .iter()
        .filter(|phone| phone.observed_phone_index.is_some())
        .count() as f32
        / learning_phones.len() as f32
}

pub(super) fn rhythm_confidence(
    phone_evidence_coverage: f32,
    anchors: &[RhythmStressAnchor],
    weak_groups: &[RhythmWeakGroup],
    compression_spans: &[RhythmCompressionSpan],
) -> f32 {
    let mut values = anchors
        .iter()
        .map(|value| value.confidence)
        .chain(weak_groups.iter().map(|value| value.confidence))
        .chain(compression_spans.iter().map(|value| value.confidence))
        .collect::<Vec<_>>();
    if values.is_empty() {
        return phone_evidence_coverage * 0.4;
    }
    values.push(phone_evidence_coverage);
    clamp01(values.iter().sum::<f32>() / values.len() as f32)
}
