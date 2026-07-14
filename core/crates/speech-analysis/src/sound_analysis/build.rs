use domain::{
    ConnectedSpeechExplanation, DetectedPhone, PhoneAlignment, RhythmFrame, RhythmFrameQuality,
    RhythmSignalSource, SoundAnalysis, SoundLearningPhone, SoundProsodicPhrase, SoundSyllable,
    SubtitleSentence, WordTiming,
};

use crate::phonetic_alignment::CanonicalPhone;

use super::anchors::{build_information_anchors, detect_stress_anchors};
use super::boundaries::detect_phrase_boundaries;
use super::config::{RhythmWordAcousticCue, SoundAnalysisConfig};
use super::connected::{connected_speech_with_default, explain_connected_speech};
use super::grouping::{detect_compression_spans, detect_weak_groups};
use super::hotspots::build_listening_hotspots;
use super::nuclei::{mark_anchor_nuclei, select_nuclei};
use super::phones::{build_learning_phones, detect_prosodic_phrases, syllabify};
use super::quality::{
    boundary_sources, connected_speech_quality_source, phone_evidence_coverage, prominence_sources,
    rhythm_confidence, timing_source_label,
};
use super::references::{build_connected_speech_refs, rhythm_references};
use super::tokens::rhythm_tokens;

pub fn build_sound_analysis(
    canonical: &[CanonicalPhone],
    observed: &[DetectedPhone],
    alignments: &[PhoneAlignment],
    config: SoundAnalysisConfig<'_>,
) -> SoundAnalysis {
    let learning_phones = build_learning_phones(canonical, observed, alignments, config.phone_set);
    let connected_speech = connected_speech_with_default(
        config.sentence,
        explain_connected_speech(alignments, observed, &learning_phones),
    );
    let syllables = syllabify(&learning_phones);
    let prosodic_phrases = detect_prosodic_phrases(&syllables);
    let rhythm_frame = build_rhythm_frame(
        config.sentence,
        canonical,
        config.word_timings,
        config.word_acoustic_cues,
        &learning_phones,
        &syllables,
        &prosodic_phrases,
        &connected_speech,
    );
    SoundAnalysis {
        provider_id: config.provider_id.into(),
        provider_version: config.provider_version.into(),
        model_revision: config.model_revision,
        phone_set: config.phone_set.into(),
        generated_from: if canonical.is_empty() {
            "observed_phones".into()
        } else {
            "expected_phones_aligned_to_observed_timing".into()
        },
        learning_phones,
        connected_speech,
        syllables,
        prosodic_phrases,
        rhythm_frame: Some(rhythm_frame),
    }
}

pub fn build_rhythm_frame_from_word_timeline(
    sentence: &SubtitleSentence,
    canonical: &[CanonicalPhone],
    word_timings: &[WordTiming],
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
) -> RhythmFrame {
    let connected_speech = connected_speech_with_default(Some(sentence), Vec::new());
    build_rhythm_frame(
        Some(sentence),
        canonical,
        Some(word_timings),
        word_acoustic_cues,
        &[],
        &[],
        &[],
        &connected_speech,
    )
}

// All inputs are distinct synchronized analysis streams required to construct
// one frame; keeping them explicit prevents accidental default evidence.
#[allow(clippy::too_many_arguments)]
fn build_rhythm_frame(
    sentence: Option<&SubtitleSentence>,
    canonical: &[CanonicalPhone],
    word_timings: Option<&[WordTiming]>,
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
    learning_phones: &[SoundLearningPhone],
    syllables: &[SoundSyllable],
    prosodic_phrases: &[SoundProsodicPhrase],
    connected_speech: &[ConnectedSpeechExplanation],
) -> RhythmFrame {
    let tokens = rhythm_tokens(
        sentence,
        canonical,
        word_timings,
        word_acoustic_cues,
        learning_phones,
        syllables,
    );
    let uses_word_timeline = tokens.iter().any(|token| token.from_word_timeline);
    let uses_audio_timing = tokens.iter().any(|token| token.timing_audio_supported);
    let uses_estimated_word_timing = tokens
        .iter()
        .any(|token| token.from_word_timeline && !token.timing_audio_supported);
    let uses_energy_cues = tokens
        .iter()
        .any(|token| token.energy_prominence_score().is_some());
    let uses_pitch_prominence_cues = tokens
        .iter()
        .any(|token| token.pitch_prominence_score().is_some());
    let connected_speech_refs = build_connected_speech_refs(sentence, connected_speech);
    let connected_speech_source = connected_speech_quality_source(connected_speech);
    let stress_anchors = detect_stress_anchors(&tokens);
    let phrase_boundaries = detect_phrase_boundaries(&tokens, syllables, prosodic_phrases);
    let nuclei = select_nuclei(&tokens, &stress_anchors, &phrase_boundaries);
    let stress_anchors = mark_anchor_nuclei(stress_anchors, &nuclei);
    let information_anchors = build_information_anchors(
        &tokens,
        canonical,
        learning_phones,
        &stress_anchors,
        &nuclei,
    );
    let weak_groups = detect_weak_groups(&tokens, &stress_anchors, connected_speech);
    let compression_spans = detect_compression_spans(&tokens);
    let listening_hotspots = build_listening_hotspots(
        &weak_groups,
        &compression_spans,
        connected_speech,
        learning_phones,
        &tokens,
    );
    let phone_evidence_coverage = phone_evidence_coverage(learning_phones);
    let rhythm_confidence = rhythm_confidence(
        phone_evidence_coverage,
        &stress_anchors,
        &weak_groups,
        &compression_spans,
    );
    let boundary_sources = boundary_sources(&phrase_boundaries);
    let uses_pitch_cues =
        uses_pitch_prominence_cues || boundary_sources.contains(&RhythmSignalSource::Pitch);
    let uses_acoustic_cues = uses_energy_cues || uses_pitch_cues;

    RhythmFrame {
        generated_from: if uses_word_timeline && uses_audio_timing && uses_acoustic_cues {
            "wordtimeline_timing_acoustic_prominence_v1".into()
        } else if uses_word_timeline && uses_audio_timing {
            "wordtimeline_timing_prominence_v1".into()
        } else if uses_word_timeline && uses_acoustic_cues {
            "wordtimeline_estimated_acoustic_prominence_v1".into()
        } else if uses_word_timeline {
            "wordtimeline_estimated_prominence_v1".into()
        } else {
            "legacy_phone_timing_adapter_v1".into()
        },
        references: rhythm_references(
            uses_word_timeline,
            uses_audio_timing,
            uses_energy_cues,
            uses_pitch_cues,
        ),
        information_anchors,
        stress_anchors,
        nuclei,
        weak_groups,
        compression_spans,
        phrase_boundaries,
        connected_speech_refs,
        listening_hotspots,
        quality: RhythmFrameQuality {
            timing_source: timing_source_label(
                uses_word_timeline,
                uses_audio_timing,
                uses_estimated_word_timing,
            )
            .into(),
            prominence_sources: prominence_sources(
                uses_audio_timing,
                uses_energy_cues,
                uses_pitch_prominence_cues,
            ),
            boundary_sources,
            connected_speech_source,
            phone_evidence_coverage,
            rhythm_confidence,
        },
    }
}
