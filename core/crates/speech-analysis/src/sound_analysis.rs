use domain::{
    ConnectedSpeechExplanation, ConnectedSpeechExplanationStatus, ConnectedSpeechFamily,
    DetectedPhone, ListeningHotspot, ListeningHotspotKind, PhoneAlignment, PhoneAlignmentKind,
    ProsodicBoundaryEvidence, RhythmAnchorImportance, RhythmClaimStatus, RhythmCompressionSpan,
    RhythmConnectedSpeechRef, RhythmDivergenceKind, RhythmEvidenceClass, RhythmFrame,
    RhythmFrameQuality, RhythmFrameReferences, RhythmNucleus, RhythmPhraseBoundary,
    RhythmReference, RhythmSignalSource, RhythmStressAnchor, RhythmWeakGroup, SoundAnalysis,
    SoundLearningPhone, SoundPhoneEvidence, SoundProsodicPhrase, SoundSyllable, SubtitleSentence,
    SubtitleTokenKind, SyllableStress, TimingSource, WordTiming,
};

use crate::phonetic_alignment::CanonicalPhone;

const PAUSE_BOUNDARY_MS: u64 = 100;
const COMPRESSION_UNIT_MS: f32 = 75.0;
const COMPRESSION_WORD_MS: f32 = 170.0;
const LENGTHENING_BOUNDARY_MIN_WORD_MS: u64 = 220;
const LENGTHENING_BOUNDARY_MIN_REFERENCES: usize = 3;
const LENGTHENING_BOUNDARY_REFERENCE_BEFORE: usize = 3;
const LENGTHENING_BOUNDARY_REFERENCE_AFTER: usize = 2;
const LENGTHENING_BOUNDARY_RATIO: f32 = 1.75;
const LENGTHENING_BOUNDARY_RATIO_MAX: f32 = 2.75;
const PITCH_RESET_BOUNDARY_MIN: f32 = 0.5;

pub struct SoundAnalysisConfig<'a> {
    pub provider_id: &'a str,
    pub provider_version: &'a str,
    pub model_revision: Option<String>,
    pub phone_set: &'a str,
    pub sentence: Option<&'a SubtitleSentence>,
    pub word_timings: Option<&'a [WordTiming]>,
    pub word_acoustic_cues: Option<&'a [RhythmWordAcousticCue]>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RhythmWordAcousticCue {
    pub token_index: u32,
    pub energy_prominence: Option<f32>,
    pub pitch_prominence: Option<f32>,
    pub pitch_reset_after: Option<f32>,
}

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

pub fn build_learning_phones(
    canonical: &[CanonicalPhone],
    observed: &[DetectedPhone],
    alignments: &[PhoneAlignment],
    phone_set: &str,
) -> Vec<SoundLearningPhone> {
    if canonical.is_empty() {
        return observed
            .iter()
            .enumerate()
            .map(|(index, phone)| SoundLearningPhone {
                symbol: phone.symbol.clone(),
                display_ipa: phone.display_ipa.clone(),
                phone_set: phone.phone_set.clone(),
                start_ms: phone.start_ms,
                end_ms: phone.end_ms,
                confidence: phone.confidence,
                token_index: phone.token_index,
                stress: None,
                observed_phone_index: Some(index as u32),
                observed_symbol: Some(phone.symbol.clone()),
                evidence: SoundPhoneEvidence::ObservedOnly,
            })
            .collect();
    }

    let mut values = Vec::new();
    for alignment in alignments {
        match alignment.kind {
            PhoneAlignmentKind::Insertion => {}
            PhoneAlignmentKind::Deletion => {
                for symbol in &alignment.canonical_phones {
                    let index = values.len();
                    let (start_ms, end_ms) = estimated_slot(canonical.len(), observed, index);
                    values.push(SoundLearningPhone {
                        symbol: symbol.clone(),
                        display_ipa: arpabet_display(symbol),
                        phone_set: phone_set.into(),
                        start_ms,
                        end_ms,
                        confidence: None,
                        token_index: alignment.token_start,
                        stress: canonical
                            .iter()
                            .find(|phone| phone.symbol == *symbol)
                            .and_then(|phone| phone.stress),
                        observed_phone_index: None,
                        observed_symbol: None,
                        evidence: SoundPhoneEvidence::Deletion,
                    });
                }
            }
            PhoneAlignmentKind::Match
            | PhoneAlignmentKind::Substitution
            | PhoneAlignmentKind::Merge => {
                let observed_slice = observed_slice(observed, alignment);
                let evidence = match alignment.kind {
                    PhoneAlignmentKind::Match => SoundPhoneEvidence::Match,
                    PhoneAlignmentKind::Substitution => SoundPhoneEvidence::Substitution,
                    PhoneAlignmentKind::Merge => SoundPhoneEvidence::Merge,
                    _ => SoundPhoneEvidence::ExpectedOnly,
                };
                for (offset, symbol) in alignment.canonical_phones.iter().enumerate() {
                    let (start_ms, end_ms, confidence, observed_index, observed_symbol) =
                        aligned_timing(&observed_slice, offset, alignment.canonical_phones.len());
                    values.push(SoundLearningPhone {
                        symbol: symbol.clone(),
                        display_ipa: arpabet_display(symbol),
                        phone_set: phone_set.into(),
                        start_ms,
                        end_ms,
                        confidence,
                        token_index: alignment.token_start,
                        stress: canonical
                            .iter()
                            .find(|phone| {
                                phone.symbol == *symbol
                                    && Some(phone.token_index) == alignment.token_start
                            })
                            .and_then(|phone| phone.stress),
                        observed_phone_index: observed_index,
                        observed_symbol,
                        evidence,
                    });
                }
            }
        }
    }

    if values.is_empty() {
        canonical
            .iter()
            .enumerate()
            .map(|(index, phone)| {
                let (start_ms, end_ms) = estimated_slot(canonical.len(), observed, index);
                SoundLearningPhone {
                    symbol: phone.symbol.clone(),
                    display_ipa: arpabet_display(&phone.symbol),
                    phone_set: phone_set.into(),
                    start_ms,
                    end_ms,
                    confidence: None,
                    token_index: Some(phone.token_index),
                    stress: phone.stress,
                    observed_phone_index: None,
                    observed_symbol: None,
                    evidence: SoundPhoneEvidence::ExpectedOnly,
                }
            })
            .collect()
    } else {
        values
    }
}

pub fn syllabify(phones: &[SoundLearningPhone]) -> Vec<SoundSyllable> {
    if phones.is_empty() {
        return Vec::new();
    }
    let nuclei = phones
        .iter()
        .enumerate()
        .filter_map(|(index, phone)| is_vowel(&phone.symbol).then_some(index))
        .collect::<Vec<_>>();
    if nuclei.is_empty() {
        return vec![syllable(
            0,
            phones.len() - 1,
            Vec::new(),
            Vec::new(),
            (0..phones.len()).map(|value| value as u32).collect(),
            phones,
        )];
    }

    let mut starts = Vec::with_capacity(nuclei.len());
    let mut ends = Vec::with_capacity(nuclei.len());
    starts.push(0);
    for pair in nuclei.windows(2) {
        let prev_nucleus = pair[0];
        let next_nucleus = pair[1];
        let consonants = next_nucleus.saturating_sub(prev_nucleus + 1);
        let has_pause_before_next_nucleus = next_nucleus > 0
            && phones[next_nucleus]
                .start_ms
                .saturating_sub(phones[next_nucleus - 1].end_ms)
                >= PAUSE_BOUNDARY_MS;
        let next_start = if consonants == 0 || has_pause_before_next_nucleus {
            next_nucleus
        } else {
            next_nucleus - 1
        };
        ends.push(next_start.saturating_sub(1));
        starts.push(next_start);
    }
    ends.push(phones.len() - 1);

    nuclei
        .iter()
        .enumerate()
        .map(|(syllable_index, nucleus)| {
            let start = starts[syllable_index];
            let end = ends[syllable_index];
            let onset = (start..*nucleus).map(|value| value as u32).collect();
            let coda = ((*nucleus + 1)..=end).map(|value| value as u32).collect();
            syllable(start, end, onset, vec![*nucleus as u32], coda, phones)
        })
        .collect()
}

pub fn detect_prosodic_phrases(syllables: &[SoundSyllable]) -> Vec<SoundProsodicPhrase> {
    if syllables.is_empty() {
        return Vec::new();
    }
    let mut phrases = Vec::new();
    let mut start = 0usize;
    let mut evidence = ProsodicBoundaryEvidence::SentenceStart;
    for index in 1..syllables.len() {
        let gap = syllables[index]
            .start_ms
            .saturating_sub(syllables[index - 1].end_ms);
        if gap >= PAUSE_BOUNDARY_MS {
            phrases.push(phrase(start, index - 1, evidence, 0.95, syllables));
            start = index;
            evidence = ProsodicBoundaryEvidence::Pause;
        }
    }
    phrases.push(phrase(
        start,
        syllables.len() - 1,
        if start == 0 {
            ProsodicBoundaryEvidence::SentenceEnd
        } else {
            evidence
        },
        0.9,
        syllables,
    ));
    phrases
}

pub fn explain_connected_speech(
    alignments: &[PhoneAlignment],
    observed: &[DetectedPhone],
    learning_phones: &[SoundLearningPhone],
) -> Vec<ConnectedSpeechExplanation> {
    let mut values = Vec::new();
    let mut learning_cursor = 0usize;

    for alignment in alignments {
        let canonical_len = alignment.canonical_phones.len();
        let phone_range = if canonical_len == 0 {
            if learning_cursor < learning_phones.len() {
                Some((learning_cursor as u32, learning_cursor as u32))
            } else {
                nearest_learning_phone_range(alignment, learning_phones)
            }
        } else {
            let start = learning_cursor;
            let end = learning_cursor + canonical_len - 1;
            learning_cursor += canonical_len;
            (end < learning_phones.len()).then_some((start as u32, end as u32))
        };

        let detected = observed_slice(observed, alignment);
        let Some(family) = connected_speech_family(alignment, &detected) else {
            continue;
        };
        let confidence = explanation_confidence(alignment, family);
        let (label, hint) = learner_copy(family);
        let status = explanation_status(alignment, family, confidence);
        let learning_symbols = phone_range
            .map(|(start, end)| {
                (start..=end)
                    .filter_map(|index| learning_phones.get(index as usize))
                    .map(|phone| phone.symbol.clone())
                    .collect()
            })
            .unwrap_or_default();

        values.push(ConnectedSpeechExplanation {
            family,
            label: label.into(),
            hint: hint.into(),
            phone_start: phone_range.map(|(start, _)| start),
            phone_end: phone_range.map(|(_, end)| end),
            token_start: alignment.token_start,
            token_end: alignment.token_end.or(alignment.token_start),
            confidence,
            status,
            expected_symbols: alignment.canonical_phones.clone(),
            learning_symbols,
            observed_symbols: detected
                .iter()
                .map(|(_, phone)| phone.symbol.clone())
                .collect(),
            evidence: evidence_copy(family, alignment.kind),
        });
    }

    values
}

fn connected_speech_with_default(
    sentence: Option<&SubtitleSentence>,
    audio_connected_speech: Vec<ConnectedSpeechExplanation>,
) -> Vec<ConnectedSpeechExplanation> {
    let mut default_connected = sentence
        .map(crate::connected_speech_rules::predict_default_connected)
        .unwrap_or_default();
    if default_connected.is_empty() {
        return audio_connected_speech;
    }

    let mut values = Vec::new();
    for audio in audio_connected_speech {
        if let Some(default_index) = default_connected
            .iter()
            .position(|candidate| connected_speech_rule_matches(candidate, &audio))
        {
            let mut merged = default_connected.remove(default_index);
            merged.status = audio.status;
            merged.phone_start = audio.phone_start;
            merged.phone_end = audio.phone_end;
            if !audio.expected_symbols.is_empty() {
                merged.expected_symbols = audio.expected_symbols;
            }
            if !audio.learning_symbols.is_empty() {
                merged.learning_symbols = audio.learning_symbols;
            }
            merged.observed_symbols = audio.observed_symbols;
            merged.confidence = merged.confidence.max(audio.confidence);
            merged.evidence = format!("{}; {}", merged.evidence, audio.evidence);
            values.push(merged);
        } else {
            values.push(audio);
        }
    }
    values.extend(default_connected);
    values.sort_by_key(|value| {
        (
            value.token_start.unwrap_or(u32::MAX),
            value.token_end.unwrap_or(u32::MAX),
            value.label.clone(),
        )
    });
    values
}

fn connected_speech_rule_matches(
    default_rule: &ConnectedSpeechExplanation,
    audio: &ConnectedSpeechExplanation,
) -> bool {
    default_rule.family == audio.family
        && overlaps_token_range(
            default_rule.token_start,
            default_rule.token_end.or(default_rule.token_start),
            audio.token_start,
            audio.token_end.or(audio.token_start),
        )
}

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

fn rhythm_references(
    uses_word_timeline: bool,
    uses_audio_timing: bool,
    uses_energy_cues: bool,
    uses_pitch_cues: bool,
) -> RhythmFrameReferences {
    RhythmFrameReferences {
        citation: RhythmReference {
            label: "citation_form".into(),
            source: "dictionary_lexical_stress".into(),
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
        },
        default_connected: Some(RhythmReference {
            label: "default_connected_variants".into(),
            source: crate::connected_speech_rules::rule_source().into(),
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
        }),
        actual: RhythmReference {
            label: "actual_delivery".into(),
            source: if uses_word_timeline
                && uses_audio_timing
                && uses_energy_cues
                && uses_pitch_cues
            {
                "word_timeline_duration_energy_pitch".into()
            } else if uses_word_timeline && uses_audio_timing && uses_energy_cues {
                "word_timeline_duration_energy".into()
            } else if uses_word_timeline && uses_audio_timing && uses_pitch_cues {
                "word_timeline_duration_pitch".into()
            } else if uses_word_timeline && uses_audio_timing {
                "word_timeline_duration".into()
            } else if uses_word_timeline && uses_energy_cues && uses_pitch_cues {
                "word_timeline_estimated_timing_energy_pitch".into()
            } else if uses_word_timeline && uses_energy_cues {
                "word_timeline_estimated_timing_energy".into()
            } else if uses_word_timeline && uses_pitch_cues {
                "word_timeline_estimated_timing_pitch".into()
            } else if uses_word_timeline {
                "word_timeline_estimated_timing".into()
            } else {
                "phone_timeline_transitional".into()
            },
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
        },
    }
}

fn timing_source_label(
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

fn prominence_sources(
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

fn boundary_sources(boundaries: &[RhythmPhraseBoundary]) -> Vec<RhythmSignalSource> {
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

fn build_connected_speech_refs(
    sentence: Option<&SubtitleSentence>,
    connected_speech: &[ConnectedSpeechExplanation],
) -> Vec<RhythmConnectedSpeechRef> {
    connected_speech
        .iter()
        .enumerate()
        .map(|(index, value)| {
            let predicted_by_rule =
                crate::connected_speech_rules::is_default_rule_explanation(value);
            let signal_sources = match value.status {
                ConnectedSpeechExplanationStatus::PossibleByRule => {
                    vec![RhythmSignalSource::TextPrior]
                }
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
            RhythmConnectedSpeechRef {
                id: format!("cs{}", index + 1),
                connected_speech_index: Some(index as u32),
                token_start: value.token_start,
                token_end: value.token_end.or(value.token_start),
                phone_start: value.phone_start,
                phone_end: value.phone_end,
                family: Some(value.family),
                surface_text: connected_surface_text(
                    sentence,
                    value.token_start,
                    value.token_end.or(value.token_start),
                ),
                label: value.label.clone(),
                hint: value.hint.clone(),
                expected_symbols: value.expected_symbols.clone(),
                default_symbols: value.learning_symbols.clone(),
                expected_display_ipa: display_ipa_for_symbols(&value.expected_symbols, false),
                default_display_ipa: display_ipa_for_symbols(&value.learning_symbols, true),
                divergence: match value.status {
                    ConnectedSpeechExplanationStatus::PossibleByRule => {
                        RhythmDivergenceKind::TeachableRule
                    }
                    ConnectedSpeechExplanationStatus::SupportedByAudio
                    | ConnectedSpeechExplanationStatus::DetectedInAudio
                        if predicted_by_rule =>
                    {
                        RhythmDivergenceKind::TeachableRule
                    }
                    ConnectedSpeechExplanationStatus::SupportedByAudio
                    | ConnectedSpeechExplanationStatus::DetectedInAudio => {
                        RhythmDivergenceKind::ClipSpecific
                    }
                },
                signal_sources,
                evidence_class: RhythmEvidenceClass::HeuristicProxy,
                confidence: value.confidence,
            }
        })
        .collect()
}

fn display_ipa_for_symbols(symbols: &[String], connected: bool) -> String {
    symbols
        .iter()
        .map(|symbol| {
            let display: String = if connected && strip_stress(symbol) == "AH" {
                "ə".into()
            } else {
                arpabet_display(symbol)
            };
            display.to_ascii_lowercase()
        })
        .collect::<Vec<_>>()
        .join("")
}

fn connected_surface_text(
    sentence: Option<&SubtitleSentence>,
    token_start: Option<u32>,
    token_end: Option<u32>,
) -> String {
    let (Some(sentence), Some(start), Some(end)) = (sentence, token_start, token_end) else {
        return String::new();
    };
    sentence
        .tokens
        .iter()
        .filter(|token| {
            token.kind == SubtitleTokenKind::Word && token.index >= start && token.index <= end
        })
        .map(|token| token.text.as_str())
        .collect::<Vec<_>>()
        .join(" ")
}

fn connected_speech_quality_source(
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

fn select_nuclei(
    tokens: &[RhythmToken],
    anchors: &[RhythmStressAnchor],
    phrase_boundaries: &[RhythmPhraseBoundary],
) -> Vec<RhythmNucleus> {
    let Some(first_token) = tokens.first() else {
        return Vec::new();
    };
    let last_token_index = tokens
        .last()
        .map(|token| token.index)
        .unwrap_or(first_token.index);
    let mut phrase_start = first_token.index;
    let mut nuclei = Vec::new();
    let mut boundaries = phrase_boundaries
        .iter()
        .filter_map(|boundary| boundary.after_token_index)
        .collect::<Vec<_>>();
    boundaries.sort_unstable();
    boundaries.dedup();
    boundaries.push(last_token_index);

    for phrase_end in boundaries {
        if phrase_end < phrase_start {
            continue;
        }
        if let Some(anchor) = anchors
            .iter()
            .filter(|anchor| anchor.claim_status == RhythmClaimStatus::AudioSupported)
            .filter(|anchor| {
                anchor
                    .token_index
                    .is_some_and(|index| index >= phrase_start && index <= phrase_end)
            })
            .max_by(|left, right| left.prominence.total_cmp(&right.prominence))
        {
            nuclei.push(RhythmNucleus {
                phrase_index: nuclei.len() as u32,
                token_index: anchor.token_index,
                syllable_index: anchor.syllable_index,
                start_ms: anchor.start_ms,
                end_ms: anchor.end_ms,
                label: anchor.label.clone(),
                reason: "Most prominent audio-supported anchor in this phrase.".into(),
                cues: anchor.prominence_cues.clone(),
                evidence_class: anchor.evidence_class,
                claim_status: anchor.claim_status,
                confidence: anchor.confidence,
            });
        }
        phrase_start = phrase_end.saturating_add(1);
    }
    nuclei
}

fn mark_anchor_nuclei(
    mut anchors: Vec<RhythmStressAnchor>,
    nuclei: &[RhythmNucleus],
) -> Vec<RhythmStressAnchor> {
    for anchor in &mut anchors {
        anchor.is_nucleus = nuclei.iter().any(|nucleus| {
            nucleus.token_index == anchor.token_index
                && nucleus.syllable_index == anchor.syllable_index
        });
    }
    anchors
}

fn claim_status(signal_sources: &[RhythmSignalSource]) -> RhythmClaimStatus {
    if signal_sources.iter().any(|source| is_audio_source(*source)) {
        RhythmClaimStatus::AudioSupported
    } else {
        RhythmClaimStatus::Predicted
    }
}

fn is_audio_source(source: RhythmSignalSource) -> bool {
    matches!(
        source,
        RhythmSignalSource::Timing
            | RhythmSignalSource::Energy
            | RhythmSignalSource::Pitch
            | RhythmSignalSource::PhoneSegmental
    )
}

#[derive(Debug, Clone)]
struct RhythmToken {
    index: u32,
    text: String,
    normalized: String,
    start_ms: u64,
    end_ms: u64,
    phone_start: Option<u32>,
    phone_end: Option<u32>,
    phone_count: u32,
    syllable_index: Option<u32>,
    syllable_count: u32,
    has_primary_stress: bool,
    has_secondary_stress: bool,
    average_confidence: Option<f32>,
    energy_prominence: Option<f32>,
    pitch_prominence: Option<f32>,
    pitch_reset_after: Option<f32>,
    timing_audio_supported: bool,
    from_word_timeline: bool,
}

impl RhythmToken {
    fn duration_ms(&self) -> u64 {
        self.end_ms.saturating_sub(self.start_ms).max(1)
    }

    fn expected_units(&self) -> u32 {
        self.phone_count.max(self.syllable_count).max(1)
    }

    fn is_function_word(&self) -> bool {
        is_function_word(&self.normalized)
    }

    fn energy_prominence_score(&self) -> Option<f32> {
        self.energy_prominence
            .filter(|value| value.is_finite() && *value > 0.0)
            .map(clamp01)
    }

    fn pitch_prominence_score(&self) -> Option<f32> {
        self.pitch_prominence
            .filter(|value| value.is_finite() && *value > 0.0)
            .map(clamp01)
    }

    fn pitch_reset_after_score(&self) -> Option<f32> {
        self.pitch_reset_after
            .filter(|value| value.is_finite() && *value > 0.0)
            .map(clamp01)
    }
}

fn rhythm_tokens(
    sentence: Option<&SubtitleSentence>,
    canonical: &[CanonicalPhone],
    word_timings: Option<&[WordTiming]>,
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
    learning_phones: &[SoundLearningPhone],
    syllables: &[SoundSyllable],
) -> Vec<RhythmToken> {
    let word_timeline_tokens =
        rhythm_tokens_from_word_timings(sentence, canonical, word_timings, word_acoustic_cues);
    if !word_timeline_tokens.is_empty() {
        return word_timeline_tokens;
    }

    if let Some(sentence) = sentence {
        let mut values = Vec::new();
        for token in sentence
            .tokens
            .iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word)
        {
            if let Some(value) = rhythm_token(
                token.index,
                &token.text,
                token.normalized.as_deref().unwrap_or(&token.text),
                learning_phones,
                syllables,
                word_acoustic_cues,
            ) {
                values.push(value);
            }
        }
        if !values.is_empty() {
            return values;
        }
    }

    let mut token_indexes = learning_phones
        .iter()
        .filter_map(|phone| phone.token_index)
        .collect::<Vec<_>>();
    token_indexes.sort_unstable();
    token_indexes.dedup();
    token_indexes
        .into_iter()
        .filter_map(|index| {
            rhythm_token(
                index,
                &format!("token-{index}"),
                &format!("token-{index}"),
                learning_phones,
                syllables,
                word_acoustic_cues,
            )
        })
        .collect()
}

fn rhythm_token(
    token_index: u32,
    text: &str,
    normalized: &str,
    learning_phones: &[SoundLearningPhone],
    syllables: &[SoundSyllable],
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
) -> Option<RhythmToken> {
    let phone_indexes = learning_phones
        .iter()
        .enumerate()
        .filter_map(|(index, phone)| (phone.token_index == Some(token_index)).then_some(index))
        .collect::<Vec<_>>();
    let first_phone = *phone_indexes.first()?;
    let last_phone = *phone_indexes.last()?;
    let start_ms = phone_indexes
        .iter()
        .filter_map(|index| learning_phones.get(*index))
        .map(|phone| phone.start_ms)
        .min()
        .unwrap_or(0);
    let end_ms = phone_indexes
        .iter()
        .filter_map(|index| learning_phones.get(*index))
        .map(|phone| phone.end_ms)
        .max()
        .unwrap_or(start_ms + 1);
    let confidences = phone_indexes
        .iter()
        .filter_map(|index| {
            learning_phones
                .get(*index)
                .and_then(|phone| phone.confidence)
        })
        .collect::<Vec<_>>();
    let average_confidence = (!confidences.is_empty())
        .then(|| confidences.iter().sum::<f32>() / confidences.len() as f32);
    let syllable_indexes = syllables
        .iter()
        .enumerate()
        .filter_map(|(index, syllable)| {
            syllable
                .phones
                .iter()
                .any(|phone| (*phone as usize) >= first_phone && (*phone as usize) <= last_phone)
                .then_some(index as u32)
        })
        .collect::<Vec<_>>();
    let has_primary_stress = syllable_indexes.iter().any(|index| {
        syllables
            .get(*index as usize)
            .is_some_and(|syllable| syllable.stress == SyllableStress::Primary)
    });
    let has_secondary_stress = syllable_indexes.iter().any(|index| {
        syllables
            .get(*index as usize)
            .is_some_and(|syllable| syllable.stress == SyllableStress::Secondary)
    });

    Some(RhythmToken {
        index: token_index,
        text: text.into(),
        normalized: normalize_rhythm_word(normalized),
        start_ms,
        end_ms: end_ms.max(start_ms + 1),
        phone_start: Some(first_phone as u32),
        phone_end: Some(last_phone as u32),
        phone_count: phone_indexes.len() as u32,
        syllable_index: syllable_indexes.first().copied(),
        syllable_count: syllable_indexes.len().max(1) as u32,
        has_primary_stress,
        has_secondary_stress,
        average_confidence,
        energy_prominence: acoustic_energy_prominence(word_acoustic_cues, token_index),
        pitch_prominence: acoustic_pitch_prominence(word_acoustic_cues, token_index),
        pitch_reset_after: acoustic_pitch_reset_after(word_acoustic_cues, token_index),
        timing_audio_supported: true,
        from_word_timeline: false,
    })
}

fn rhythm_tokens_from_word_timings(
    sentence: Option<&SubtitleSentence>,
    canonical: &[CanonicalPhone],
    word_timings: Option<&[WordTiming]>,
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
) -> Vec<RhythmToken> {
    let (Some(sentence), Some(word_timings)) = (sentence, word_timings) else {
        return Vec::new();
    };
    let mut timings = word_timings
        .iter()
        .filter(|timing| timing.sentence_id == sentence.id)
        .filter(|timing| timing.end_ms > timing.start_ms)
        .collect::<Vec<_>>();
    if timings.is_empty() {
        timings = word_timings
            .iter()
            .filter(|timing| timing.end_ms > timing.start_ms)
            .collect::<Vec<_>>();
    }
    if timings.is_empty() {
        return Vec::new();
    }
    timings.sort_by_key(|timing| (timing.start_ms, timing.end_ms, timing.token_index));
    let mut values = Vec::new();
    for timing in timings {
        let token = sentence.tokens.iter().find(|token| {
            token.index == timing.token_index && token.kind == SubtitleTokenKind::Word
        });
        let text = token
            .map(|token| token.text.as_str())
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(timing.text.as_str());
        let normalized = token
            .and_then(|token| token.normalized.as_deref())
            .unwrap_or(text);
        let token_phones = canonical
            .iter()
            .filter(|phone| phone.token_index == timing.token_index)
            .collect::<Vec<_>>();
        let syllable_count = token_phones
            .iter()
            .filter(|phone| phone.stress.is_some())
            .count()
            .max(1) as u32;
        let has_primary_stress = token_phones
            .iter()
            .any(|phone| phone.stress == Some(1) || phone.stress == Some(2));
        let has_secondary_stress = token_phones.iter().any(|phone| phone.stress == Some(2));
        values.push(RhythmToken {
            index: timing.token_index,
            text: text.into(),
            normalized: normalize_rhythm_word(normalized),
            start_ms: timing.start_ms,
            end_ms: timing.end_ms.max(timing.start_ms + 1),
            phone_start: None,
            phone_end: None,
            phone_count: token_phones.len() as u32,
            syllable_index: None,
            syllable_count,
            has_primary_stress,
            has_secondary_stress,
            average_confidence: timing.confidence,
            energy_prominence: acoustic_energy_prominence(word_acoustic_cues, timing.token_index),
            pitch_prominence: acoustic_pitch_prominence(word_acoustic_cues, timing.token_index),
            pitch_reset_after: acoustic_pitch_reset_after(word_acoustic_cues, timing.token_index),
            timing_audio_supported: is_audio_backed_word_timing(timing.timing_source),
            from_word_timeline: true,
        });
    }
    values
}

fn is_audio_backed_word_timing(source: TimingSource) -> bool {
    matches!(
        source,
        TimingSource::AsrReported
            | TimingSource::AsrAligned
            | TimingSource::ForcedAligned
            | TimingSource::UserAdjusted
    )
}

fn acoustic_energy_prominence(
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
    token_index: u32,
) -> Option<f32> {
    word_acoustic_cues?
        .iter()
        .find(|cue| cue.token_index == token_index)
        .and_then(|cue| cue.energy_prominence)
        .filter(|value| value.is_finite() && *value > 0.0)
        .map(clamp01)
}

fn acoustic_pitch_prominence(
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
    token_index: u32,
) -> Option<f32> {
    word_acoustic_cues?
        .iter()
        .find(|cue| cue.token_index == token_index)
        .and_then(|cue| cue.pitch_prominence)
        .filter(|value| value.is_finite() && *value > 0.0)
        .map(clamp01)
}

fn acoustic_pitch_reset_after(
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
    token_index: u32,
) -> Option<f32> {
    word_acoustic_cues?
        .iter()
        .find(|cue| cue.token_index == token_index)
        .and_then(|cue| cue.pitch_reset_after)
        .filter(|value| value.is_finite() && *value > 0.0)
        .map(clamp01)
}

fn detect_stress_anchors(tokens: &[RhythmToken]) -> Vec<RhythmStressAnchor> {
    let mut anchors = Vec::new();
    let final_content_token_index = tokens
        .iter()
        .rev()
        .find(|token| !token.is_function_word())
        .map(|token| token.index);
    let mut seen_content_words = Vec::new();
    for token in tokens {
        let content_word = !token.is_function_word();
        let stressed = token.has_primary_stress || token.has_secondary_stress;
        let long_enough = token.duration_ms() >= 180;
        let energy_prominence = token.energy_prominence_score();
        let pitch_prominence = token.pitch_prominence_score();
        if !content_word {
            continue;
        }
        if !stressed && !long_enough && token.text.len() <= 2 {
            continue;
        }
        let repeated_content = seen_content_words.contains(&token.normalized);
        let final_focus = final_content_token_index == Some(token.index);
        seen_content_words.push(token.normalized.clone());
        let confidence = clamp01(
            0.6 + score_flag(content_word) * 0.08
                + score_flag(token.has_primary_stress) * 0.14
                + score_flag(token.has_secondary_stress) * 0.08
                + token.average_confidence.unwrap_or(0.4) * 0.08
                + energy_prominence.unwrap_or(0.0) * 0.14
                + pitch_prominence.unwrap_or(0.0) * 0.14
                + score_flag(final_focus) * 0.08
                - score_flag(repeated_content) * 0.1,
        );
        let mut signal_sources = vec![RhythmSignalSource::TextPrior];
        let mut prominence_cues = vec![RhythmSignalSource::TextPrior];
        if long_enough && token.timing_audio_supported {
            signal_sources.push(RhythmSignalSource::Timing);
            prominence_cues.push(RhythmSignalSource::Timing);
        }
        if energy_prominence.is_some() {
            signal_sources.push(RhythmSignalSource::Energy);
            prominence_cues.push(RhythmSignalSource::Energy);
        }
        if pitch_prominence.is_some() {
            signal_sources.push(RhythmSignalSource::Pitch);
            prominence_cues.push(RhythmSignalSource::Pitch);
        }
        let claim_status = claim_status(&signal_sources);
        let prominence = confidence
            .max(energy_prominence.unwrap_or(0.0))
            .max(pitch_prominence.unwrap_or(0.0));
        anchors.push(RhythmStressAnchor {
            token_index: Some(token.index),
            syllable_index: token.syllable_index,
            phone_start: token.phone_start,
            phone_end: token.phone_end,
            start_ms: token.start_ms,
            end_ms: token.end_ms,
            label: token.text.clone(),
            reason: if repeated_content {
                "Repeated content is slightly backgrounded by the information-structure prior."
                    .into()
            } else if final_focus {
                "Phrase-final content is a likely focus candidate.".into()
            } else if stressed {
                "Catch this stressed content word as a listening anchor.".into()
            } else {
                "Catch this content word as a meaning anchor.".into()
            },
            importance: if token.has_primary_stress || content_word {
                RhythmAnchorImportance::Primary
            } else {
                RhythmAnchorImportance::Secondary
            },
            is_nucleus: false,
            prominence,
            prominence_cues,
            signal_sources,
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status,
            confidence,
        });
    }
    anchors
}

fn detect_weak_groups(
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
            .filter_map(|(index, value)| {
                overlaps_token_range(
                    value.token_start,
                    value.token_end.or(value.token_start),
                    Some(group.first().unwrap().index),
                    Some(group.last().unwrap().index),
                )
                .then(|| format!("cs{}", index + 1))
            })
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

fn detect_compression_spans(tokens: &[RhythmToken]) -> Vec<RhythmCompressionSpan> {
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

fn detect_phrase_boundaries(
    tokens: &[RhythmToken],
    syllables: &[SoundSyllable],
    prosodic_phrases: &[SoundProsodicPhrase],
) -> Vec<RhythmPhraseBoundary> {
    let mut values = Vec::new();
    for pair in tokens.windows(2) {
        if !pair.iter().all(|token| token.timing_audio_supported) {
            continue;
        }
        let gap = pair[1].start_ms.saturating_sub(pair[0].end_ms);
        if gap >= PAUSE_BOUNDARY_MS {
            values.push(RhythmPhraseBoundary {
                after_token_index: Some(pair[0].index),
                before_token_index: Some(pair[1].index),
                at_ms: pair[1].start_ms,
                reason: "Pause between aligned words suggests an intonation phrase boundary."
                    .into(),
                cues: vec!["pause".into()],
                signal_sources: vec![RhythmSignalSource::Timing],
                evidence_class: RhythmEvidenceClass::HeuristicProxy,
                claim_status: RhythmClaimStatus::AudioSupported,
                is_final: false,
                confidence: 0.9,
            });
        }
    }
    for boundary_position in 0..tokens.len().saturating_sub(1) {
        let left = &tokens[boundary_position];
        let right = &tokens[boundary_position + 1];
        let gap = right.start_ms.saturating_sub(left.end_ms);
        if gap >= PAUSE_BOUNDARY_MS {
            continue;
        }
        let lengthening_ratio = pre_boundary_lengthening_ratio(tokens, boundary_position);
        let pitch_reset = left
            .pitch_reset_after_score()
            .filter(|score| *score >= PITCH_RESET_BOUNDARY_MIN);
        if lengthening_ratio.is_none() && pitch_reset.is_none() {
            continue;
        }
        let range = (LENGTHENING_BOUNDARY_RATIO_MAX - LENGTHENING_BOUNDARY_RATIO).max(f32::EPSILON);
        let mut cues = Vec::new();
        let mut signal_sources = Vec::new();
        let mut confidence: f32 = 0.0;
        if let Some(ratio) = lengthening_ratio {
            cues.push("final_lengthening".into());
            signal_sources.push(RhythmSignalSource::Timing);
            confidence = confidence.max(clamp01(
                0.7 + 0.18 * ((ratio - LENGTHENING_BOUNDARY_RATIO) / range),
            ));
        }
        if let Some(score) = pitch_reset {
            cues.push("pitch_reset".into());
            signal_sources.push(RhythmSignalSource::Pitch);
            confidence = confidence.max(clamp01(0.62 + score * 0.28));
        }
        values.push(RhythmPhraseBoundary {
            after_token_index: Some(left.index),
            before_token_index: Some(right.index),
            at_ms: left.end_ms,
            reason: match (lengthening_ratio.is_some(), pitch_reset.is_some()) {
                (true, true) => {
                    "Final lengthening and a pitch reset support this phrase boundary.".into()
                }
                (true, false) => {
                    "The pre-boundary word is lengthened relative to nearby words.".into()
                }
                (false, true) => {
                    "A pitch reset between words supports this phrase boundary.".into()
                }
                (false, false) => unreachable!(),
            },
            cues,
            signal_sources,
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status: RhythmClaimStatus::AudioSupported,
            is_final: false,
            confidence,
        });
    }
    for phrase in prosodic_phrases {
        if phrase.boundary_evidence != ProsodicBoundaryEvidence::Pause {
            continue;
        }
        let Some(first_syllable) = phrase.syllables.first() else {
            continue;
        };
        let Some(syllable) = syllables.get(*first_syllable as usize) else {
            continue;
        };
        if values
            .iter()
            .any(|value| value.at_ms.abs_diff(syllable.start_ms) < 20)
        {
            continue;
        }
        let before = tokens
            .iter()
            .rev()
            .find(|token| token.end_ms <= syllable.start_ms)
            .map(|token| token.index);
        let after = tokens
            .iter()
            .find(|token| token.start_ms >= syllable.start_ms)
            .map(|token| token.index);
        values.push(RhythmPhraseBoundary {
            after_token_index: before,
            before_token_index: after,
            at_ms: syllable.start_ms,
            reason: "Prosodic phrase detector found a pause boundary.".into(),
            cues: vec!["pause".into()],
            signal_sources: vec![RhythmSignalSource::Timing],
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status: RhythmClaimStatus::AudioSupported,
            is_final: false,
            confidence: phrase.confidence,
        });
    }
    values.sort_by_key(|value| value.at_ms);
    values
}

fn pre_boundary_lengthening_ratio(tokens: &[RhythmToken], boundary_position: usize) -> Option<f32> {
    let left = tokens.get(boundary_position)?;
    if !left.timing_audio_supported {
        return None;
    }
    if left.duration_ms() < LENGTHENING_BOUNDARY_MIN_WORD_MS {
        return None;
    }
    let unit_ms = normalized_unit_ms(left);
    let before_start = boundary_position.saturating_sub(LENGTHENING_BOUNDARY_REFERENCE_BEFORE);
    let after_end =
        (boundary_position + 1 + LENGTHENING_BOUNDARY_REFERENCE_AFTER).min(tokens.len());
    let mut references = tokens[before_start..boundary_position]
        .iter()
        .chain(tokens[boundary_position + 1..after_end].iter())
        .filter(|token| token.timing_audio_supported && token.duration_ms() > 0)
        .map(normalized_unit_ms)
        .filter(|value| *value > 0.0)
        .collect::<Vec<_>>();
    if references.len() < LENGTHENING_BOUNDARY_MIN_REFERENCES {
        return None;
    }
    references.sort_by(|left, right| left.total_cmp(right));
    let baseline = median_f32(&references);
    if baseline <= f32::EPSILON {
        return None;
    }
    let ratio = unit_ms / baseline;
    (ratio >= LENGTHENING_BOUNDARY_RATIO).then_some(ratio)
}

fn normalized_unit_ms(token: &RhythmToken) -> f32 {
    token.duration_ms() as f32 / token.expected_units().max(1) as f32
}

fn median_f32(sorted: &[f32]) -> f32 {
    let middle = sorted.len() / 2;
    if sorted.len().is_multiple_of(2) {
        (sorted[middle - 1] + sorted[middle]) / 2.0
    } else {
        sorted[middle]
    }
}

fn build_listening_hotspots(
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

fn overlaps_token_range(
    left_start: Option<u32>,
    left_end: Option<u32>,
    right_start: Option<u32>,
    right_end: Option<u32>,
) -> bool {
    let (Some(left_start), Some(left_end), Some(right_start), Some(right_end)) =
        (left_start, left_end, right_start, right_end)
    else {
        return false;
    };
    left_start <= right_end && right_start <= left_end
}

fn phone_evidence_coverage(learning_phones: &[SoundLearningPhone]) -> f32 {
    if learning_phones.is_empty() {
        return 0.0;
    }
    learning_phones
        .iter()
        .filter(|phone| phone.observed_phone_index.is_some())
        .count() as f32
        / learning_phones.len() as f32
}

fn rhythm_confidence(
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

fn normalize_rhythm_word(value: &str) -> String {
    value
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '\'')
        .collect::<String>()
        .to_ascii_lowercase()
}

fn is_function_word(value: &str) -> bool {
    matches!(
        value,
        "a" | "an"
            | "the"
            | "and"
            | "or"
            | "but"
            | "to"
            | "of"
            | "in"
            | "on"
            | "at"
            | "about"
            | "for"
            | "from"
            | "with"
            | "as"
            | "by"
            | "is"
            | "am"
            | "are"
            | "was"
            | "were"
            | "be"
            | "been"
            | "being"
            | "do"
            | "does"
            | "did"
            | "have"
            | "has"
            | "had"
            | "can"
            | "could"
            | "will"
            | "would"
            | "should"
            | "may"
            | "might"
            | "must"
            | "not"
            | "i"
            | "you"
            | "he"
            | "she"
            | "it"
            | "we"
            | "they"
            | "that"
            | "this"
            | "these"
            | "those"
            | "who"
            | "whom"
            | "whose"
            | "which"
            | "when"
            | "where"
            | "why"
            | "how"
            | "me"
            | "him"
            | "her"
            | "us"
            | "them"
            | "my"
            | "your"
            | "his"
            | "our"
            | "their"
            | "there"
    )
}

fn clamp01(value: f32) -> f32 {
    value.clamp(0.0, 1.0)
}

fn score_flag(value: bool) -> f32 {
    if value { 1.0 } else { 0.0 }
}

fn connected_speech_family(
    alignment: &PhoneAlignment,
    detected: &[(usize, &DetectedPhone)],
) -> Option<ConnectedSpeechFamily> {
    let canonical = alignment
        .canonical_phones
        .iter()
        .map(|phone| strip_stress(phone))
        .collect::<Vec<_>>();
    let observed = detected
        .iter()
        .map(|(_, phone)| normalize_phone_symbol(&phone.symbol))
        .collect::<Vec<_>>();
    match alignment.kind {
        PhoneAlignmentKind::Substitution
            if canonical
                .iter()
                .any(|phone| matches!(phone.as_str(), "T" | "D"))
                && observed
                    .iter()
                    .any(|phone| matches!(phone.as_str(), "DX" | "ɾ")) =>
        {
            Some(ConnectedSpeechFamily::Flapping)
        }
        PhoneAlignmentKind::Substitution
            if canonical.iter().any(|phone| is_vowel(phone))
                && observed
                    .iter()
                    .any(|phone| matches!(phone.as_str(), "AX" | "AH" | "ə")) =>
        {
            Some(ConnectedSpeechFamily::WeakForm)
        }
        PhoneAlignmentKind::Merge => Some(ConnectedSpeechFamily::Assimilation),
        PhoneAlignmentKind::Deletion if alignment.token_start != alignment.token_end => {
            Some(ConnectedSpeechFamily::Contraction)
        }
        PhoneAlignmentKind::Deletion => Some(ConnectedSpeechFamily::Deletion),
        // A raw CTC insertion is not enough evidence for learner-facing linking.
        // Real linking needs cross-token boundary context; otherwise every extra
        // observed phone becomes a noisy "possible linking" marker.
        PhoneAlignmentKind::Insertion => None,
        PhoneAlignmentKind::Match | PhoneAlignmentKind::Substitution => None,
    }
}

fn explanation_confidence(alignment: &PhoneAlignment, family: ConnectedSpeechFamily) -> f32 {
    let base = alignment.confidence.clamp(0.0, 1.0);
    if base > 0.0 {
        return base;
    }
    match family {
        ConnectedSpeechFamily::Deletion | ConnectedSpeechFamily::Contraction => 0.62,
        ConnectedSpeechFamily::Linking => 0.58,
        _ => 0.5,
    }
}

fn explanation_status(
    alignment: &PhoneAlignment,
    family: ConnectedSpeechFamily,
    confidence: f32,
) -> ConnectedSpeechExplanationStatus {
    match family {
        ConnectedSpeechFamily::Deletion
        | ConnectedSpeechFamily::Contraction
        | ConnectedSpeechFamily::Linking
            if confidence < 0.75 =>
        {
            ConnectedSpeechExplanationStatus::PossibleByRule
        }
        _ if confidence >= 0.75 && alignment.kind != PhoneAlignmentKind::Insertion => {
            ConnectedSpeechExplanationStatus::DetectedInAudio
        }
        _ => ConnectedSpeechExplanationStatus::SupportedByAudio,
    }
}

fn learner_copy(family: ConnectedSpeechFamily) -> (&'static str, &'static str) {
    match family {
        ConnectedSpeechFamily::WeakForm => (
            "possible reduction",
            "A small function-word or vowel sound may be reduced in fast speech.",
        ),
        ConnectedSpeechFamily::Deletion => (
            "possible deletion",
            "A /t/ or /d/ sound may be weakened or not fully released here.",
        ),
        ConnectedSpeechFamily::Linking => (
            "possible linking",
            "The speaker may connect the end of one word into the next word.",
        ),
        ConnectedSpeechFamily::Assimilation => (
            "possible assimilation",
            "Neighboring sounds may blend so the boundary is easier to say.",
        ),
        ConnectedSpeechFamily::Contraction => (
            "possible contraction",
            "This phrase may be spoken as a shorter connected form.",
        ),
        ConnectedSpeechFamily::Flapping => (
            "possible flap",
            "In American English, /t/ or /d/ can sound like a quick tap between vowels.",
        ),
    }
}

fn evidence_copy(family: ConnectedSpeechFamily, kind: PhoneAlignmentKind) -> String {
    let source = match kind {
        PhoneAlignmentKind::Insertion => "extra observed sound near the word boundary",
        PhoneAlignmentKind::Deletion => "expected sound has little direct audio support",
        PhoneAlignmentKind::Merge => "neighboring expected sounds share one observed region",
        PhoneAlignmentKind::Substitution => {
            "observed sound matches a common connected-speech pattern"
        }
        PhoneAlignmentKind::Match => "matched sound",
    };
    let family = match family {
        ConnectedSpeechFamily::WeakForm => "reduction",
        ConnectedSpeechFamily::Deletion => "deletion",
        ConnectedSpeechFamily::Linking => "linking",
        ConnectedSpeechFamily::Assimilation => "assimilation",
        ConnectedSpeechFamily::Contraction => "contraction",
        ConnectedSpeechFamily::Flapping => "flapping",
    };
    format!("{family} evidence: {source}")
}

fn nearest_learning_phone_range(
    alignment: &PhoneAlignment,
    learning_phones: &[SoundLearningPhone],
) -> Option<(u32, u32)> {
    let target = alignment.detected_phone_start?;
    learning_phones
        .iter()
        .enumerate()
        .filter_map(|(index, phone)| {
            let observed = phone.observed_phone_index?;
            let distance = observed.abs_diff(target);
            Some((distance, index as u32))
        })
        .min_by_key(|(distance, _)| *distance)
        .map(|(_, index)| (index, index))
}

fn observed_slice<'a>(
    observed: &'a [DetectedPhone],
    alignment: &PhoneAlignment,
) -> Vec<(usize, &'a DetectedPhone)> {
    let Some(start) = alignment.detected_phone_start else {
        return Vec::new();
    };
    let Some(end) = alignment.detected_phone_end else {
        return Vec::new();
    };
    (start as usize..=end as usize)
        .filter_map(|index| observed.get(index).map(|phone| (index, phone)))
        .collect()
}

fn normalize_phone_symbol(symbol: &str) -> String {
    strip_stress(symbol).to_ascii_uppercase()
}

fn aligned_timing(
    observed_slice: &[(usize, &DetectedPhone)],
    offset: usize,
    canonical_len: usize,
) -> (u64, u64, Option<f32>, Option<u32>, Option<String>) {
    if observed_slice.is_empty() {
        return (0, 1, None, None, None);
    }
    if observed_slice.len() == canonical_len {
        let (index, phone) = observed_slice[offset];
        return (
            phone.start_ms,
            phone.end_ms,
            phone.confidence,
            Some(index as u32),
            Some(phone.symbol.clone()),
        );
    }
    let (index, phone) = observed_slice[offset.min(observed_slice.len() - 1)];
    let duration = phone.end_ms.saturating_sub(phone.start_ms).max(1);
    let width = (duration / canonical_len.max(1) as u64).max(1);
    let start_ms = phone.start_ms + width * offset as u64;
    let end_ms = if offset + 1 == canonical_len {
        phone.end_ms
    } else {
        start_ms + width
    };
    (
        start_ms,
        end_ms.max(start_ms + 1),
        phone.confidence,
        Some(index as u32),
        Some(phone.symbol.clone()),
    )
}

fn estimated_slot(total: usize, observed: &[DetectedPhone], index: usize) -> (u64, u64) {
    let start = observed.first().map(|phone| phone.start_ms).unwrap_or(0);
    let end = observed.last().map(|phone| phone.end_ms).unwrap_or(1);
    let duration = end.saturating_sub(start).max(total.max(1) as u64);
    let width = (duration / total.max(1) as u64).max(1);
    let phone_start = start + width * index as u64;
    (
        phone_start,
        (phone_start + width).min(end).max(phone_start + 1),
    )
}

fn syllable(
    start: usize,
    end: usize,
    onset: Vec<u32>,
    nucleus: Vec<u32>,
    coda: Vec<u32>,
    phones: &[SoundLearningPhone],
) -> SoundSyllable {
    let stress = nucleus
        .iter()
        .filter_map(|index| phones.get(*index as usize).and_then(|phone| phone.stress))
        .map(stress_level)
        .next()
        .unwrap_or(SyllableStress::Unknown);
    SoundSyllable {
        phones: (start..=end).map(|value| value as u32).collect(),
        onset,
        nucleus,
        coda,
        start_ms: phones[start].start_ms,
        end_ms: phones[end].end_ms,
        stress,
    }
}

fn stress_level(value: u8) -> SyllableStress {
    match value {
        1 => SyllableStress::Primary,
        2 => SyllableStress::Secondary,
        0 => SyllableStress::Unstressed,
        _ => SyllableStress::Unknown,
    }
}

fn phrase(
    start: usize,
    end: usize,
    boundary_evidence: ProsodicBoundaryEvidence,
    confidence: f32,
    syllables: &[SoundSyllable],
) -> SoundProsodicPhrase {
    SoundProsodicPhrase {
        syllables: (start..=end).map(|value| value as u32).collect(),
        start_ms: syllables[start].start_ms,
        end_ms: syllables[end].end_ms,
        boundary_evidence,
        confidence,
    }
}

fn is_vowel(symbol: &str) -> bool {
    matches!(
        strip_stress(symbol).as_str(),
        "AA" | "AE"
            | "AH"
            | "AO"
            | "AW"
            | "AX"
            | "AY"
            | "EH"
            | "ER"
            | "EY"
            | "IH"
            | "IY"
            | "OW"
            | "OY"
            | "UH"
            | "UW"
    )
}

fn strip_stress(symbol: &str) -> String {
    symbol
        .chars()
        .filter(|value| !value.is_ascii_digit())
        .collect::<String>()
        .to_ascii_uppercase()
}

fn arpabet_display(symbol: &str) -> String {
    match strip_stress(symbol).as_str() {
        "AA" => "ɑ",
        "AE" => "æ",
        "AH" => "ʌ",
        "AO" => "ɔ",
        "AW" => "aʊ",
        "AX" => "ə",
        "AY" => "aɪ",
        "EH" => "ɛ",
        "ER" => "ɝ",
        "EY" => "eɪ",
        "IH" => "ɪ",
        "IY" => "i",
        "OW" => "oʊ",
        "OY" => "ɔɪ",
        "UH" => "ʊ",
        "UW" => "u",
        "SH" => "ʃ",
        "ZH" => "ʒ",
        "TH" => "θ",
        "DH" => "ð",
        "CH" => "tʃ",
        "JH" => "dʒ",
        "NG" => "ŋ",
        "Y" => "j",
        "HH" => "h",
        "DX" => "ɾ",
        other => other,
    }
    .into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::phonetic_alignment::align_phones;

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

    fn word_timings(
        sentence: &SubtitleSentence,
        values: &[(u32, &str, u64, u64)],
    ) -> Vec<WordTiming> {
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
}
