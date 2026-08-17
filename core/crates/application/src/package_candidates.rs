//! Projects adopted package analysis resources into Core-owned candidate
//! records with the same global sentence identity space as the package's
//! landed `subtitle_text_track`.
//!
//! Package analysis payloads address sentences by the package-local sentence
//! id (`subtitle_text_track.sentences[].id`). Those ids never resolve against
//! Core sentence-scoped endpoints. This module is the single authority that
//! re-keys every package analysis sentence reference to the deterministic
//! global [`SubtitleSentenceId`] of the adopted package subtitle track before
//! the candidate records are persisted.
//!
//! Projection policy mirrors the App's old package projection: a resource is
//! optional, and an item whose reference does not resolve to a landed
//! sentence/token drops that item alone. It never invents text, spans, or
//! timings, and it never fails an already committed adoption.

use std::collections::HashMap;

use content_package::{
    EnergyBaseline, PhoneTimeline as PackagePhoneTimeline, PitchBaseline,
    ProsodyAnalysis as PackageProsodyAnalysis, SenseGroupAnalysis as PackageSenseGroupAnalysis,
    SubtitleTextTrack as PackageSubtitleTextTrack, WordAcoustics as PackageWordAcoustics,
    WordTimeline as PackageWordTimeline,
};
use domain::{
    DetectedPhone, LLTimelineArtifact, LLTimelineGenerator, LLTimelineMedia, LLTimelineMetadata,
    LexicalStress, MediaItem, PackageResourceFact, PhoneTimeline, PhoneTimelineId,
    PhoneTimelinePrecision, ProsodicChunk, ProsodyAnalysis, ProsodyAnalysisId, ProsodyAnchor,
    ProsodyEvidence, ProsodyWordRef, SenseGroup, SenseGroupAnalysis, SenseGroupAnalysisId,
    SenseGroupId, SenseGroupSource, SubtitleSentenceId, SubtitleTokenKind, SubtitleTrack, TimeMs,
    TimelineCreator, TimelineMetrics, TimelineStatus, TimingSource, UtteranceRole, WordTimeline,
    WordTimelineId, WordTiming,
};
use serde::de::DeserializeOwned;

use crate::{ApplicationError, ContentPackageCandidateImport};

const ACOUSTIC_ARTIFACT_KIND: &str = "rhythm_word_acoustic_cues";
const PACKAGE_GENERATOR_ID: &str = "listen-resource-package";
const PACKAGE_GENERATOR_VERSION: &str = "v3";
const PACKAGE_SOURCE: &str = "package:subtitle_text_track";

/// One package fact plus its exact decoded payload, addressed by resource id.
pub(crate) struct PackageResourcePayloads {
    facts: HashMap<String, PackageResourceFact>,
    payloads: HashMap<String, Vec<u8>>,
}

impl PackageResourcePayloads {
    pub(crate) fn new(facts: Vec<PackageResourceFact>, payloads: HashMap<String, Vec<u8>>) -> Self {
        Self {
            facts: facts
                .into_iter()
                .map(|fact| (fact.resource_id.clone(), fact))
                .collect(),
            payloads,
        }
    }

    fn fact(&self, kind: &str) -> Option<&PackageResourceFact> {
        self.facts.values().find(|fact| fact.kind == kind)
    }

    fn decode<T: DeserializeOwned>(&self, fact: &PackageResourceFact) -> Option<T> {
        let bytes = self.payloads.get(&fact.resource_id)?;
        serde_json::from_slice(bytes).ok()
    }
}

/// Projects every selected package analysis resource that can be re-keyed
/// into global sentence ids. Resources that are absent, malformed, or whose
/// references do not resolve contribute nothing; the subtitle track and the
/// adoption are never affected.
pub(crate) fn project_package_candidates(
    track: &SubtitleTrack,
    media: &MediaItem,
    release_created_at_ms: u64,
    subtitle_payload: &PackageSubtitleTextTrack,
    resources: PackageResourcePayloads,
) -> Result<ContentPackageCandidateImport, ApplicationError> {
    let sentence_ids = sentence_identity_map(track, subtitle_payload)?;
    let sentences_by_id = track
        .sentences
        .iter()
        .map(|sentence| (sentence.id.clone(), sentence))
        .collect::<HashMap<_, _>>();

    let word_timeline = resources
        .fact("word_timeline")
        .and_then(|fact| {
            resources
                .decode::<PackageWordTimeline>(fact)
                .map(|payload| (fact, payload))
        })
        .and_then(|(fact, payload)| {
            project_word_timeline(
                track,
                media,
                fact,
                &payload,
                &sentence_ids,
                &sentences_by_id,
            )
        });

    let word_timing_lookup = resources
        .fact("word_timeline")
        .and_then(|fact| resources.decode::<PackageWordTimeline>(fact))
        .map(|payload| package_word_timing_lookup(&payload))
        .unwrap_or_default();
    let word_timeline_id = word_timeline.as_ref().map(|timeline| timeline.id.clone());

    let phone_timelines = resources
        .fact("phone_timeline")
        .and_then(|fact| {
            resources
                .decode::<PackagePhoneTimeline>(fact)
                .map(|payload| (fact, payload))
        })
        .map(|(fact, payload)| {
            project_phone_timelines(
                track,
                media,
                fact,
                &payload,
                &sentence_ids,
                &sentences_by_id,
                word_timeline_id.as_ref(),
            )
        })
        .unwrap_or_default();

    let sense_group_analyses = resources
        .fact("sense_group_analysis")
        .and_then(|fact| {
            resources
                .decode::<PackageSenseGroupAnalysis>(fact)
                .map(|payload| (fact, payload))
        })
        .and_then(|(fact, payload)| {
            project_sense_group_analysis(
                track,
                media,
                fact,
                &payload,
                &sentence_ids,
                &sentences_by_id,
                word_timeline_id.as_ref(),
            )
        });

    let prosody_analyses = resources
        .fact("prosody_analysis")
        .and_then(|fact| {
            resources
                .decode::<PackageProsodyAnalysis>(fact)
                .map(|payload| (fact, payload))
        })
        .and_then(|(fact, payload)| {
            project_prosody_analysis(
                track,
                media,
                fact,
                &payload,
                &sentence_ids,
                &sentences_by_id,
                word_timeline_id.as_ref(),
                &word_timing_lookup,
            )
        });

    let artifacts = resources
        .fact("word_acoustics")
        .and_then(|fact| {
            resources
                .decode::<PackageWordAcoustics>(fact)
                .map(|payload| (fact, payload))
        })
        .and_then(|(fact, payload)| {
            project_word_acoustics(
                fact,
                &payload,
                &sentence_ids,
                &sentences_by_id,
                word_timeline_id.as_ref(),
                &word_timing_lookup,
            )
        })
        .into_iter()
        .collect::<Vec<_>>();

    let metadata = LLTimelineMetadata {
        created_at_ms: release_created_at_ms,
        generator: LLTimelineGenerator {
            id: PACKAGE_GENERATOR_ID.into(),
            version: PACKAGE_GENERATOR_VERSION.into(),
            mode: "adopted_package".into(),
        },
        media: LLTimelineMedia {
            id: media.id.clone(),
            fingerprint: media.fingerprint.clone(),
            path: None,
            title: media.title.clone(),
            duration_ms: media.duration.map(TimeMs::get),
        },
        language: track.language.clone(),
        human_reviewed: resources
            .fact("subtitle_text_track")
            .is_some_and(|fact| fact.review_status == domain::PackageReviewStatus::HumanReviewed),
        extra: serde_json::json!({
            "track_id": track.id.as_str(),
            "track_fingerprint": track.fingerprint,
            "track_source": PACKAGE_SOURCE,
            "package_release_created_at_ms": release_created_at_ms,
        }),
    };

    Ok(ContentPackageCandidateImport {
        track: track.clone(),
        metadata,
        artifacts,
        word_timelines: word_timeline.into_iter().collect(),
        phone_timelines,
        sense_group_analyses: sense_group_analyses.into_iter().collect(),
        prosody_analyses: prosody_analyses.into_iter().collect(),
        corpus_occurrences: Vec::new(),
    })
}

/// `package sentence id → global sentence id`, derived from the same
/// deterministic projection that landed the track. The subtitle payload
/// sentence order and the track sentence order are both the payload's
/// declaration order.
fn sentence_identity_map(
    track: &SubtitleTrack,
    subtitle_payload: &PackageSubtitleTextTrack,
) -> Result<HashMap<String, SubtitleSentenceId>, ApplicationError> {
    if subtitle_payload.sentences.len() != track.sentences.len() {
        return Err(ApplicationError::Invalid(
            "package subtitle sentence count changed during landing".into(),
        ));
    }
    Ok(subtitle_payload
        .sentences
        .iter()
        .zip(&track.sentences)
        .map(|(package, landed)| (package.id.clone(), landed.id.clone()))
        .collect())
}

fn project_word_timeline(
    track: &SubtitleTrack,
    media: &MediaItem,
    fact: &PackageResourceFact,
    payload: &PackageWordTimeline,
    sentence_ids: &HashMap<String, SubtitleSentenceId>,
    sentences_by_id: &HashMap<SubtitleSentenceId, &domain::SubtitleSentence>,
) -> Option<WordTimeline> {
    let (provider_id, provider_version) = producer(fact);
    let words = payload
        .words
        .iter()
        .filter_map(|word| {
            let sentence_id = sentence_ids.get(&word.sentence_id)?;
            let sentence = sentences_by_id.get(sentence_id)?;
            let token = sentence
                .tokens
                .iter()
                .find(|token| token.index == word.token_index)?;
            (word.end_ms >= word.start_ms).then_some(WordTiming {
                sentence_id: sentence_id.clone(),
                token_index: word.token_index,
                text: token.text.clone(),
                start_ms: word.start_ms,
                end_ms: word.end_ms,
                confidence: word.confidence.map(|value| value as f32),
                timing_source: map_timing_source(word.timing_source),
                provider_id: provider_id.clone(),
                provider_version: provider_version.clone(),
            })
        })
        .collect::<Vec<_>>();
    if words.is_empty() {
        return None;
    }
    Some(WordTimeline {
        id: WordTimelineId::from_fingerprint(
            "package-word-timeline",
            &format!("{}:{}", track.id.as_str(), fact.resource_id),
        ),
        track_id: track.id.clone(),
        media_id: media.id.clone(),
        algorithm_id: provider_id,
        algorithm_version: provider_version,
        config_hash: fact
            .provenance
            .config_sha256
            .clone()
            .unwrap_or_else(|| fact.resource_id.clone()),
        parent_timeline_id: None,
        created_by: TimelineCreator::Algorithm,
        status: TimelineStatus::Candidate,
        metrics_json: resource_metrics(fact),
        words,
        created_at_ms: fact.provenance.created_at_ms,
        updated_at_ms: fact.provenance.created_at_ms,
    })
}

fn project_phone_timelines(
    track: &SubtitleTrack,
    media: &MediaItem,
    fact: &PackageResourceFact,
    payload: &PackagePhoneTimeline,
    sentence_ids: &HashMap<String, SubtitleSentenceId>,
    sentences_by_id: &HashMap<SubtitleSentenceId, &domain::SubtitleSentence>,
    parent_word_timeline_id: Option<&WordTimelineId>,
) -> Vec<PhoneTimeline> {
    let (provider_id, provider_version) = producer(fact);
    let model_revision = fact
        .provenance
        .model_version
        .clone()
        .unwrap_or_else(|| provider_version.clone());
    let mut by_sentence = HashMap::<SubtitleSentenceId, Vec<DetectedPhone>>::new();
    for phone in &payload.phones {
        let Some(word_ref) = phone.word_ref.as_ref() else {
            continue;
        };
        let Some(sentence_id) = sentence_ids.get(&word_ref.sentence_id) else {
            continue;
        };
        let Some(sentence) = sentences_by_id.get(sentence_id) else {
            continue;
        };
        if !sentence
            .tokens
            .iter()
            .any(|token| token.index == word_ref.token_index)
        {
            continue;
        }
        by_sentence
            .entry(sentence_id.clone())
            .or_default()
            .push(DetectedPhone {
                symbol: phone.symbol.clone(),
                display_ipa: phone
                    .display_ipa
                    .clone()
                    .unwrap_or_else(|| phone.symbol.clone()),
                phone_set: payload.phone_set.clone(),
                start_ms: phone.start_ms,
                end_ms: phone.end_ms,
                confidence: phone.confidence.map(|value| value as f32),
                token_index: Some(word_ref.token_index),
                provider_id: provider_id.clone(),
                provider_version: provider_version.clone(),
                model_revision: model_revision.clone(),
            });
    }
    by_sentence
        .into_iter()
        .map(|(sentence_id, phones)| PhoneTimeline {
            id: PhoneTimelineId::from_fingerprint(
                "package-phone-timeline",
                &format!("{}:{}:{sentence_id}", track.id.as_str(), fact.resource_id),
            ),
            track_id: track.id.clone(),
            media_id: media.id.clone(),
            sentence_id: Some(sentence_id),
            parent_word_timeline_id: parent_word_timeline_id.cloned(),
            parent_phonetic_analysis_id: None,
            provider_id: provider_id.clone(),
            provider_version: provider_version.clone(),
            model_id: None,
            model_revision: Some(model_revision.clone()),
            phone_set: payload.phone_set.clone(),
            precision: map_phone_precision(payload.precision),
            created_by: TimelineCreator::Algorithm,
            status: TimelineStatus::Candidate,
            metrics_json: resource_metrics(fact),
            phones,
            alignments: Vec::new(),
            findings: Vec::new(),
            sound_analysis: None,
            created_at_ms: fact.provenance.created_at_ms,
            updated_at_ms: fact.provenance.created_at_ms,
        })
        .collect()
}

fn project_sense_group_analysis(
    track: &SubtitleTrack,
    media: &MediaItem,
    fact: &PackageResourceFact,
    payload: &PackageSenseGroupAnalysis,
    sentence_ids: &HashMap<String, SubtitleSentenceId>,
    sentences_by_id: &HashMap<SubtitleSentenceId, &domain::SubtitleSentence>,
    parent_word_timeline_id: Option<&WordTimelineId>,
) -> Option<SenseGroupAnalysis> {
    let (provider_id, provider_version) = producer(fact);
    let groups = payload
        .groups
        .iter()
        .filter_map(|group| {
            let sentence_id = sentence_ids.get(&group.sentence_id)?;
            let sentence = sentences_by_id.get(sentence_id)?;
            let end_exclusive = group.end_token_index_exclusive;
            if end_exclusive <= group.start_token_index
                || end_exclusive as usize > sentence.tokens.len()
            {
                return None;
            }
            let text = sentence
                .tokens
                .iter()
                .filter(|token| {
                    token.index >= group.start_token_index && token.index < end_exclusive
                })
                .map(|token| token.text.as_str())
                .collect::<String>();
            if text.is_empty() {
                return None;
            }
            Some(SenseGroup {
                id: SenseGroupId::from_fingerprint(
                    "package-sense-group",
                    &format!(
                        "{}:{}:{}",
                        track.id.as_str(),
                        fact.resource_id,
                        group.group_index
                    ),
                ),
                sentence_id: sentence_id.clone(),
                group_index: group.group_index,
                start_token_index: group.start_token_index,
                end_token_index: end_exclusive - 1,
                text,
                label: group.label.clone(),
                head_token_index: group.head_token_index,
                confidence: group.confidence as f32,
                sources: group
                    .sources
                    .iter()
                    .copied()
                    .map(map_sense_source)
                    .collect(),
            })
        })
        .collect::<Vec<_>>();
    if groups.is_empty() {
        return None;
    }
    Some(SenseGroupAnalysis {
        id: SenseGroupAnalysisId::from_fingerprint(
            "package-sense-group-analysis",
            &format!("{}:{}", track.id.as_str(), fact.resource_id),
        ),
        track_id: track.id.clone(),
        media_id: media.id.clone(),
        parent_word_timeline_id: parent_word_timeline_id.cloned(),
        provider_id,
        provider_version,
        algorithm: PACKAGE_GENERATOR_ID.into(),
        status: TimelineStatus::Candidate,
        created_by: TimelineCreator::Algorithm,
        metrics_json: resource_metrics(fact),
        groups,
        created_at_ms: fact.provenance.created_at_ms,
        updated_at_ms: fact.provenance.created_at_ms,
    })
}

#[allow(clippy::too_many_arguments)]
fn project_prosody_analysis(
    track: &SubtitleTrack,
    media: &MediaItem,
    fact: &PackageResourceFact,
    payload: &PackageProsodyAnalysis,
    sentence_ids: &HashMap<String, SubtitleSentenceId>,
    sentences_by_id: &HashMap<SubtitleSentenceId, &domain::SubtitleSentence>,
    parent_word_timeline_id: Option<&WordTimelineId>,
    word_timing_lookup: &HashMap<(String, u32), (u64, u64)>,
) -> Option<ProsodyAnalysis> {
    let (provider_id, provider_version) = producer(fact);
    let chunks = payload
        .chunks
        .iter()
        .filter_map(|chunk| {
            let sentence_id = sentence_ids.get(&chunk.sentence_id)?;
            let sentence = sentences_by_id.get(sentence_id)?;
            let end_exclusive = chunk.end_token_index_exclusive;
            if end_exclusive <= chunk.start_token_index
                || end_exclusive as usize > sentence.tokens.len()
                || !sentence
                    .tokens
                    .iter()
                    .any(|token| token.index == chunk.start_token_index)
                || !sentence
                    .tokens
                    .iter()
                    .any(|token| token.index == end_exclusive - 1)
                || chunk
                    .nucleus_token_index
                    .is_some_and(|index| index < chunk.start_token_index || index >= end_exclusive)
            {
                return None;
            }
            Some(ProsodicChunk {
                sentence_id: sentence_id.clone(),
                chunk_index: chunk.chunk_index,
                start_token_index: chunk.start_token_index,
                end_token_index: end_exclusive - 1,
                nucleus_token_index: chunk.nucleus_token_index,
                confidence: chunk.confidence,
            })
        })
        .collect::<Vec<_>>();
    let anchors = payload
        .anchors
        .iter()
        .filter_map(|anchor| {
            let sentence_id = sentence_ids.get(&anchor.word_ref.sentence_id)?;
            let sentence = sentences_by_id.get(sentence_id)?;
            let token = sentence
                .tokens
                .iter()
                .find(|token| token.index == anchor.word_ref.token_index)?;
            if token.kind != SubtitleTokenKind::Word {
                return None;
            }
            word_timing_lookup.get(&(
                anchor.word_ref.sentence_id.clone(),
                anchor.word_ref.token_index,
            ))?;
            Some(ProsodyAnchor {
                word_ref: ProsodyWordRef {
                    sentence_id: sentence_id.clone(),
                    token_index: anchor.word_ref.token_index,
                },
                syllable_index: anchor.syllable_index,
                lexical_stress: map_lexical_stress(anchor.lexical_stress),
                realized_prominence: anchor.realized_prominence,
                utterance_role: map_utterance_role(anchor.utterance_role),
                evidence: anchor
                    .evidence
                    .iter()
                    .copied()
                    .map(map_prosody_evidence)
                    .collect(),
                confidence: anchor.confidence,
            })
        })
        .collect::<Vec<_>>();
    if chunks.is_empty() && anchors.is_empty() {
        return None;
    }
    Some(ProsodyAnalysis {
        id: ProsodyAnalysisId::from_fingerprint(
            "package-prosody-analysis",
            &format!("{}:{}", track.id.as_str(), fact.resource_id),
        ),
        track_id: track.id.clone(),
        media_id: media.id.clone(),
        parent_word_timeline_id: parent_word_timeline_id.cloned(),
        provider_id,
        provider_version,
        algorithm: PACKAGE_GENERATOR_ID.into(),
        status: TimelineStatus::Candidate,
        created_by: TimelineCreator::Algorithm,
        metrics_json: resource_metrics(fact),
        chunks,
        anchors,
        created_at_ms: fact.provenance.created_at_ms,
        updated_at_ms: fact.provenance.created_at_ms,
    })
}

fn project_word_acoustics(
    fact: &PackageResourceFact,
    payload: &PackageWordAcoustics,
    sentence_ids: &HashMap<String, SubtitleSentenceId>,
    sentences_by_id: &HashMap<SubtitleSentenceId, &domain::SubtitleSentence>,
    parent_word_timeline_id: Option<&WordTimelineId>,
    word_timing_lookup: &HashMap<(String, u32), (u64, u64)>,
) -> Option<LLTimelineArtifact> {
    let parent_word_timeline_id = parent_word_timeline_id?;
    let (provider_id, provider_version) = producer(fact);
    let cues = payload
        .measurements
        .iter()
        .filter_map(|measurement| {
            let sentence_id = sentence_ids.get(&measurement.word_ref.sentence_id)?;
            let sentence = sentences_by_id.get(sentence_id)?;
            let token = sentence
                .tokens
                .iter()
                .find(|token| token.index == measurement.word_ref.token_index)?;
            if token.kind != SubtitleTokenKind::Word {
                return None;
            }
            let timing = word_timing_lookup.get(&(
                measurement.word_ref.sentence_id.clone(),
                measurement.word_ref.token_index,
            ))?;
            let energy = serde_json::to_value(&measurement.energy).ok()?;
            let pitch = serde_json::to_value(&measurement.pitch).ok()?;
            let duration = serde_json::to_value(&measurement.duration).ok()?;
            Some(serde_json::json!({
                "sentence_id": sentence_id.as_str(),
                "token_index": measurement.word_ref.token_index,
                "text": token.text,
                "start_ms": timing.0,
                "end_ms": timing.1,
                "energy_prominence": measurement.energy.prominence,
                "pitch_prominence": measurement.pitch.prominence,
                "pitch_reset_after": measurement.pitch.reset_after,
                "voiced_frame_ratio": measurement.voiced_frame_ratio,
                // Exact package measurement facts, preserved key-for-key for
                // the App's composition acoustic projection.
                "energy": energy,
                "pitch": pitch,
                "duration": duration,
            }))
        })
        .collect::<Vec<_>>();
    if cues.is_empty() {
        return None;
    }
    Some(LLTimelineArtifact {
        kind: ACOUSTIC_ARTIFACT_KIND.into(),
        provider_id: Some(provider_id),
        provider_version: Some(provider_version),
        payload: serde_json::json!({
            "status": "scored",
            "line": "sound",
            "resource_id": fact.resource_id,
            "exchange_source": PACKAGE_SOURCE,
            "timeline_id": parent_word_timeline_id.as_str(),
            "sample_rate_hz": payload.sample_rate_hz,
            "calibration": {
                "energy": match payload.energy_baseline {
                    EnergyBaseline::SentenceMedianDbfs => "sentence_median_dbfs",
                },
                "pitch": match payload.pitch_baseline {
                    PitchBaseline::SentenceMedianF0Hz => "sentence_median_f0_hz",
                }
            },
            "cues": cues
        }),
    })
}

fn package_word_timing_lookup(payload: &PackageWordTimeline) -> HashMap<(String, u32), (u64, u64)> {
    payload
        .words
        .iter()
        .map(|word| {
            (
                (word.sentence_id.clone(), word.token_index),
                (word.start_ms, word.end_ms),
            )
        })
        .collect()
}

fn resource_metrics(fact: &PackageResourceFact) -> TimelineMetrics {
    TimelineMetrics::from_value(serde_json::json!({
        "exchange_resource_id": fact.resource_id,
        "exchange_schema": fact.schema,
        "exchange_source": PACKAGE_SOURCE,
        "line": "sound"
    }))
}

fn producer(fact: &PackageResourceFact) -> (String, String) {
    if let (Some(provider_id), Some(provider_version)) = (
        fact.provenance.provider_id.as_deref(),
        fact.provenance.provider_version.as_deref(),
    ) {
        return (provider_id.to_owned(), provider_version.to_owned());
    }
    (
        fact.provenance.tool_id.clone(),
        fact.provenance.tool_version.clone(),
    )
}

fn map_timing_source(value: content_package::TimingSource) -> TimingSource {
    match value {
        content_package::TimingSource::AsrReported => TimingSource::AsrReported,
        content_package::TimingSource::AsrAligned => TimingSource::AsrAligned,
        content_package::TimingSource::ForcedAligned => TimingSource::ForcedAligned,
        content_package::TimingSource::Estimated => TimingSource::Estimated,
        content_package::TimingSource::UserAdjusted => TimingSource::UserAdjusted,
    }
}

fn map_phone_precision(value: content_package::PhoneTimelinePrecision) -> PhoneTimelinePrecision {
    match value {
        content_package::PhoneTimelinePrecision::Detected => PhoneTimelinePrecision::Detected,
        content_package::PhoneTimelinePrecision::Aligned => PhoneTimelinePrecision::Aligned,
        content_package::PhoneTimelinePrecision::Approximate => PhoneTimelinePrecision::Approximate,
    }
}

fn map_sense_source(value: content_package::SenseGroupSource) -> SenseGroupSource {
    match value {
        content_package::SenseGroupSource::DependencyParse => SenseGroupSource::DependencyParse,
        content_package::SenseGroupSource::PhraseStructure => SenseGroupSource::PhraseStructure,
        content_package::SenseGroupSource::LanguageModel => SenseGroupSource::LanguageModel,
        content_package::SenseGroupSource::Punctuation => SenseGroupSource::Punctuation,
        content_package::SenseGroupSource::LengthLimit => SenseGroupSource::LengthLimit,
        content_package::SenseGroupSource::Rule => SenseGroupSource::Rule,
        content_package::SenseGroupSource::User => SenseGroupSource::User,
    }
}

fn map_lexical_stress(value: content_package::LexicalStress) -> LexicalStress {
    match value {
        content_package::LexicalStress::Primary => LexicalStress::Primary,
        content_package::LexicalStress::Secondary => LexicalStress::Secondary,
        content_package::LexicalStress::Unstressed => LexicalStress::Unstressed,
        content_package::LexicalStress::Unknown => LexicalStress::Unknown,
    }
}

fn map_utterance_role(value: content_package::UtteranceRole) -> UtteranceRole {
    match value {
        content_package::UtteranceRole::Nucleus => UtteranceRole::Nucleus,
        content_package::UtteranceRole::Prenuclear => UtteranceRole::Prenuclear,
        content_package::UtteranceRole::Postnuclear => UtteranceRole::Postnuclear,
        content_package::UtteranceRole::Unmarked => UtteranceRole::Unmarked,
        content_package::UtteranceRole::Unknown => UtteranceRole::Unknown,
    }
}

fn map_prosody_evidence(value: content_package::ProsodyEvidence) -> ProsodyEvidence {
    match value {
        content_package::ProsodyEvidence::Energy => ProsodyEvidence::Energy,
        content_package::ProsodyEvidence::Pitch => ProsodyEvidence::Pitch,
        content_package::ProsodyEvidence::Duration => ProsodyEvidence::Duration,
        content_package::ProsodyEvidence::LexicalStress => ProsodyEvidence::LexicalStress,
        content_package::ProsodyEvidence::Context => ProsodyEvidence::Context,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use content_package::{
        EnergyBaseline, EnergyMeasurement, PitchBaseline, PitchMeasurement,
        ProsodyEvidence as PackageProsodyEvidence, SubtitleSentence as PackageSubtitleSentence,
        SubtitleSourceKind, SubtitleToken as PackageSubtitleToken, TokenKind as PackageTokenKind,
        TokenRef, WordTiming as PackageWordTiming,
    };
    use domain::{
        LanguageCode, PackageResourceAvailability, PackageResourceProvenance, PackageResourceRole,
        PackageReviewStatus, SubtitleSentence, SubtitleSentenceId, SubtitleToken,
        SubtitleTokenKind, SubtitleTrackStatus, TimeMs,
    };

    fn fact(kind: &str, resource_id: &str) -> PackageResourceFact {
        PackageResourceFact {
            resource_id: resource_id.to_owned(),
            kind: kind.to_owned(),
            schema: format!("listen.resource.{kind}.v1"),
            role: PackageResourceRole::Base,
            required: false,
            availability: PackageResourceAvailability::Available,
            content_language: None,
            support_languages: Vec::new(),
            dependencies: Vec::new(),
            anchor_resource_ids: Vec::new(),
            payload_digest: format!("digest-{resource_id}"),
            payload_size_bytes: 0,
            provenance: PackageResourceProvenance {
                created_at_ms: 10,
                tool_id: "listen-gen".into(),
                tool_version: "0.1.0".into(),
                provider_id: Some("example-asr".into()),
                provider_version: Some("v1".into()),
                model_id: None,
                model_version: Some("model-v1".into()),
                config_sha256: None,
            },
            review_status: PackageReviewStatus::MachineChecked,
            quality_warnings: Vec::new(),
        }
    }

    fn media() -> MediaItem {
        MediaItem {
            id: domain::MediaId::from_fingerprint("media", "audio-a"),
            path: "/tmp/audio-a.mp4".into(),
            fingerprint: "audio-fingerprint".into(),
            title: "Audio A".into(),
            kind: domain::MediaKind::Video,
            duration: Some(TimeMs::new(2_000)),
            availability: domain::MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        }
    }

    fn subtitle_payload() -> PackageSubtitleTextTrack {
        content_package::SubtitleTextTrack {
            language: "en".into(),
            source_kind: SubtitleSourceKind::Asr,
            sentences: vec![PackageSubtitleSentence {
                id: "local-0".into(),
                index: 0,
                start_ms: 0,
                end_ms: 900,
                original_text: "Pandas eat bamboo.".into(),
                display_text: "Pandas eat bamboo.".into(),
                tokens: vec![
                    PackageSubtitleToken {
                        index: 0,
                        kind: PackageTokenKind::Word,
                        text: "Pandas".into(),
                        normalized: Some("panda".into()),
                        start_char: 0,
                        end_char: 6,
                    },
                    PackageSubtitleToken {
                        index: 1,
                        kind: PackageTokenKind::Whitespace,
                        text: " ".into(),
                        normalized: None,
                        start_char: 6,
                        end_char: 7,
                    },
                ],
            }],
        }
    }

    fn track() -> SubtitleTrack {
        SubtitleTrack {
            id: domain::SubtitleTrackId::from_fingerprint("package-subtitle-track", "media"),
            media_id: media().id,
            fingerprint: "material:rev:resource".into(),
            language: Some(LanguageCode::parse("en").unwrap()),
            source: "package:subtitle_text_track".into(),
            status: SubtitleTrackStatus::Available,
            sentences: vec![SubtitleSentence {
                id: SubtitleSentenceId::from_fingerprint(
                    "package-subtitle-sentence",
                    "global-sentence",
                ),
                index: 0,
                start: TimeMs::new(0),
                end: TimeMs::new(900),
                original_text: "Pandas eat bamboo.".into(),
                display_text: "Pandas eat bamboo.".into(),
                tokens: vec![
                    SubtitleToken {
                        index: 0,
                        kind: SubtitleTokenKind::Word,
                        text: "Pandas".into(),
                        normalized: Some("panda".into()),
                        start_char: 0,
                        end_char: 6,
                    },
                    SubtitleToken {
                        index: 1,
                        kind: SubtitleTokenKind::Whitespace,
                        text: " ".into(),
                        normalized: None,
                        start_char: 6,
                        end_char: 7,
                    },
                ],
            }],
        }
    }

    fn resources(payloads: Vec<(&str, Vec<u8>)>) -> PackageResourcePayloads {
        PackageResourcePayloads::new(
            payloads
                .iter()
                .map(|(kind, _)| fact(kind, &format!("{kind}-1")))
                .collect(),
            payloads
                .into_iter()
                .map(|(kind, bytes)| (format!("{kind}-1"), bytes))
                .collect(),
        )
    }

    fn full_resources() -> PackageResourcePayloads {
        resources(vec![
            (
                "word_timeline",
                serde_json::to_vec(&content_package::WordTimeline {
                    words: vec![PackageWordTiming {
                        sentence_id: "local-0".into(),
                        token_index: 0,
                        start_ms: 0,
                        end_ms: 400,
                        confidence: Some(0.9),
                        timing_source: content_package::TimingSource::ForcedAligned,
                    }],
                })
                .unwrap(),
            ),
            (
                "phone_timeline",
                serde_json::to_vec(&content_package::PhoneTimeline {
                    phone_set: "ipa".into(),
                    precision: content_package::PhoneTimelinePrecision::Detected,
                    phones: vec![content_package::Phone {
                        symbol: "p".into(),
                        display_ipa: Some("p".into()),
                        start_ms: 0,
                        end_ms: 100,
                        confidence: Some(0.8),
                        word_ref: Some(TokenRef {
                            sentence_id: "local-0".into(),
                            token_index: 0,
                        }),
                    }],
                })
                .unwrap(),
            ),
            (
                "sense_group_analysis",
                serde_json::to_vec(&content_package::SenseGroupAnalysis {
                    groups: vec![content_package::SenseGroup {
                        sentence_id: "local-0".into(),
                        group_index: 0,
                        start_token_index: 0,
                        end_token_index_exclusive: 1,
                        label: Some("NP".into()),
                        head_token_index: Some(0),
                        confidence: 0.9,
                        sources: vec![content_package::SenseGroupSource::DependencyParse],
                    }],
                })
                .unwrap(),
            ),
            (
                "prosody_analysis",
                serde_json::to_vec(&content_package::ProsodyAnalysis {
                    chunks: vec![content_package::ProsodicChunk {
                        sentence_id: "local-0".into(),
                        chunk_index: 0,
                        start_token_index: 0,
                        end_token_index_exclusive: 1,
                        nucleus_token_index: Some(0),
                        confidence: 0.9,
                    }],
                    anchors: vec![content_package::ProsodyAnchor {
                        word_ref: TokenRef {
                            sentence_id: "local-0".into(),
                            token_index: 0,
                        },
                        syllable_index: Some(0),
                        lexical_stress: content_package::LexicalStress::Primary,
                        realized_prominence: 0.8,
                        utterance_role: content_package::UtteranceRole::Nucleus,
                        evidence: vec![PackageProsodyEvidence::Pitch],
                        confidence: 0.9,
                    }],
                })
                .unwrap(),
            ),
            (
                "word_acoustics",
                serde_json::to_vec(&content_package::WordAcoustics {
                    sample_rate_hz: 16_000,
                    energy_baseline: EnergyBaseline::SentenceMedianDbfs,
                    pitch_baseline: PitchBaseline::SentenceMedianF0Hz,
                    measurements: vec![content_package::WordAcousticMeasurement {
                        word_ref: TokenRef {
                            sentence_id: "local-0".into(),
                            token_index: 0,
                        },
                        energy: EnergyMeasurement {
                            rms_dbfs: Some(-20.0),
                            local_baseline_dbfs: Some(-22.0),
                            delta_db: Some(2.0),
                            prominence: Some(0.4),
                        },
                        pitch: PitchMeasurement {
                            median_f0_hz: Some(120.0),
                            local_baseline_f0_hz: Some(115.0),
                            delta_semitones: Some(0.5),
                            range_semitones: Some(2.0),
                            prominence: Some(0.3),
                            reset_after: Some(0.1),
                        },
                        duration: content_package::DurationMeasurement {
                            duration_ms: 400,
                            local_ratio: Some(1.0),
                        },
                        voiced_frame_ratio: Some(0.9),
                    }],
                })
                .unwrap(),
            ),
        ])
    }

    #[test]
    fn rekeys_every_analysis_family_to_global_sentence_ids() {
        let projected = project_package_candidates(
            &track(),
            &media(),
            10,
            &subtitle_payload(),
            full_resources(),
        )
        .unwrap();

        let global = &track().sentences[0].id;
        assert_eq!(projected.word_timelines.len(), 1);
        assert_eq!(projected.word_timelines[0].words[0].sentence_id, *global);
        assert_eq!(projected.phone_timelines.len(), 1);
        assert_eq!(
            projected.phone_timelines[0].sentence_id.as_ref(),
            Some(global)
        );
        assert_eq!(projected.phone_timelines[0].phones[0].token_index, Some(0));
        assert_eq!(projected.sense_group_analyses.len(), 1);
        assert_eq!(
            projected.sense_group_analyses[0].groups[0].sentence_id,
            *global
        );
        assert_eq!(projected.prosody_analyses.len(), 1);
        assert_eq!(projected.prosody_analyses[0].chunks[0].sentence_id, *global);
        assert_eq!(
            projected.prosody_analyses[0].anchors[0]
                .word_ref
                .sentence_id,
            *global
        );
        assert_eq!(projected.artifacts.len(), 1);
        assert_eq!(
            projected.artifacts[0].payload["cues"][0]["sentence_id"],
            global.as_str()
        );
        assert_eq!(
            projected.artifacts[0].payload["cues"][0]["energy"]["prominence"],
            0.4
        );
        assert!(projected.word_timelines.iter().all(|timeline| {
            timeline.status == TimelineStatus::Candidate
                && timeline.metrics_json.as_object()["exchange_source"] == PACKAGE_SOURCE
        }));
        assert!(projected.corpus_occurrences.is_empty());
    }

    #[test]
    fn package_local_ids_never_survive_projection() {
        let projected = project_package_candidates(
            &track(),
            &media(),
            10,
            &subtitle_payload(),
            full_resources(),
        )
        .unwrap();
        let serialized = serde_json::to_string(&projected.word_timelines).unwrap();
        assert!(!serialized.contains("local-0"));
    }

    #[test]
    fn malformed_items_drop_alone_without_failing_landing() {
        let word_payload = content_package::WordTimeline {
            words: vec![
                PackageWordTiming {
                    sentence_id: "local-0".into(),
                    token_index: 0,
                    start_ms: 400,
                    end_ms: 300,
                    confidence: None,
                    timing_source: content_package::TimingSource::Estimated,
                },
                PackageWordTiming {
                    sentence_id: "missing-sentence".into(),
                    token_index: 0,
                    start_ms: 0,
                    end_ms: 100,
                    confidence: None,
                    timing_source: content_package::TimingSource::Estimated,
                },
            ],
        };
        let projected = project_package_candidates(
            &track(),
            &media(),
            10,
            &subtitle_payload(),
            resources(vec![(
                "word_timeline",
                serde_json::to_vec(&word_payload).unwrap(),
            )]),
        )
        .unwrap();
        assert!(projected.word_timelines.is_empty());
        assert!(projected.phone_timelines.is_empty());
        assert!(projected.sense_group_analyses.is_empty());
    }
}
