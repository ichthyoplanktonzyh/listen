use std::collections::HashMap;
use std::sync::Arc;

use domain::*;
use serde::Serialize;

mod chunks;
mod diagnosis;
mod dictionary;
mod dto;
mod error;
mod learning;
mod lexical;
mod media;
mod phonetic_fixture;
mod pronunciation;
mod providers;
mod repositories;
mod subtitles;
mod transcription_pipeline;
mod util;
mod vocabulary;
mod word_timelines;

pub use dto::*;
pub use error::ApplicationError;
pub use providers::*;
pub use repositories::*;
pub use util::now_ms;
pub(crate) use util::{
    clean_optional, clean_required, lexical_from_word, lexical_source_from_word,
    normalize_american_english, normalize_phrase, phrase_candidates, require_text,
};

const DICTIONARY_CACHE_TTL_MS: u64 = 30 * 24 * 60 * 60 * 1000;

#[derive(Debug, Serialize)]
pub(crate) struct ForcedAlignRequest {
    pub(crate) audio_path: String,
    pub(crate) segments: Vec<ForcedAlignSegment>,
}

#[derive(Debug, Serialize)]
pub(crate) struct ForcedAlignSegment {
    pub(crate) index: u32,
    pub(crate) text: String,
    pub(crate) words: Vec<String>,
    pub(crate) start_ms: u64,
    pub(crate) end_ms: u64,
}

#[derive(Clone)]
pub struct AppServices {
    pub(crate) media: Arc<dyn MediaRepository>,
    pub(crate) progress: Arc<dyn PlaybackProgressRepository>,
    pub(crate) words: Arc<dyn WordProfileRepository>,
    pub(crate) observations: Arc<dyn WordObservationRepository>,
    pub(crate) subtitles: Arc<dyn SubtitleRepository>,
    pub(crate) dictionary: Arc<dyn DictionaryCacheRepository>,
    pub(crate) vocabulary: Arc<dyn VocabularyAssetRepository>,
    pub(crate) lexical: Arc<dyn LexicalEntryRepository>,
    pub(crate) lexical_normalizers: Arc<Vec<Arc<dyn LexicalNormalizationProvider>>>,
}

impl AppServices {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        media: Arc<dyn MediaRepository>,
        progress: Arc<dyn PlaybackProgressRepository>,
        words: Arc<dyn WordProfileRepository>,
        observations: Arc<dyn WordObservationRepository>,
        subtitles: Arc<dyn SubtitleRepository>,
        dictionary: Arc<dyn DictionaryCacheRepository>,
        vocabulary: Arc<dyn VocabularyAssetRepository>,
        lexical: Arc<dyn LexicalEntryRepository>,
    ) -> Self {
        Self {
            media,
            progress,
            words,
            observations,
            subtitles,
            dictionary,
            vocabulary,
            lexical,
            lexical_normalizers: Arc::new(Vec::new()),
        }
    }

    pub fn with_lexical_normalizers(
        mut self,
        providers: Vec<Arc<dyn LexicalNormalizationProvider>>,
    ) -> Self {
        self.lexical_normalizers = Arc::new(providers);
        self
    }
}

pub(crate) fn timing_priority(source: TimingSource) -> u8 {
    match source {
        TimingSource::Estimated => 1,
        TimingSource::AsrReported => 2,
        TimingSource::ForcedAligned => 3,
        TimingSource::UserAdjusted => 4,
    }
}

pub(crate) fn validate_word_timeline_words(
    track: &SubtitleTrack,
    timings: &[WordTiming],
) -> Result<Vec<WordTiming>, ApplicationError> {
    if timings.is_empty() {
        return Err(ApplicationError::Validation("word timeline timings"));
    }
    let sentences = track
        .sentences
        .iter()
        .map(|sentence| (sentence.id.clone(), sentence))
        .collect::<std::collections::HashMap<_, _>>();
    let sentence_order = track
        .sentences
        .iter()
        .enumerate()
        .map(|(index, sentence)| (sentence.id.clone(), index))
        .collect::<std::collections::HashMap<_, _>>();
    let mut grouped = std::collections::HashMap::<SubtitleSentenceId, Vec<WordTiming>>::new();
    for timing in timings {
        let sentence = sentences
            .get(&timing.sentence_id)
            .ok_or(ApplicationError::Validation("word timing sentence"))?;
        if timing.end_ms <= timing.start_ms
            || timing.start_ms < sentence.start.get()
            || timing.end_ms > sentence.end.get()
            || !sentence.tokens.iter().any(|token| {
                token.index == timing.token_index && token.kind == SubtitleTokenKind::Word
            })
        {
            return Err(ApplicationError::Validation("word timing boundary"));
        }
        grouped
            .entry(timing.sentence_id.clone())
            .or_default()
            .push(timing.clone());
    }

    let mut values = Vec::with_capacity(timings.len());
    for (sentence_id, mut sentence_timings) in grouped {
        sentence_timings.sort_by_key(|value| (value.start_ms, value.end_ms, value.token_index));
        if sentence_timings
            .windows(2)
            .any(|pair| pair[0].end_ms > pair[1].start_ms)
        {
            return Err(ApplicationError::Validation("word timing monotonicity"));
        }
        let order = *sentence_order
            .get(&sentence_id)
            .ok_or(ApplicationError::Validation("word timing sentence"))?;
        values.extend(sentence_timings.into_iter().map(|timing| (order, timing)));
    }
    values.sort_by_key(|(sentence_order, timing)| {
        (
            *sentence_order,
            timing.start_ms,
            timing.end_ms,
            timing.token_index,
        )
    });
    Ok(values.into_iter().map(|(_, timing)| timing).collect())
}

pub(crate) fn build_word_timeline(
    track: &SubtitleTrack,
    words: Vec<WordTiming>,
    algorithm_id: Option<String>,
    algorithm_version: Option<String>,
    config_hash: Option<String>,
    parent_timeline_id: Option<WordTimelineId>,
    created_by: Option<TimelineCreator>,
    status: TimelineStatus,
    metrics_json: Option<serde_json::Value>,
) -> Result<WordTimeline, ApplicationError> {
    let words = validate_word_timeline_words(track, &words)?;
    let first = words
        .first()
        .ok_or(ApplicationError::Validation("word timeline timings"))?;
    let default_algorithm_id = match first.timing_source {
        TimingSource::UserAdjusted => "user-adjusted".to_owned(),
        _ => first.provider_id.clone(),
    };
    let algorithm_id = clean_required(
        algorithm_id.unwrap_or(default_algorithm_id),
        "word timeline algorithm",
    )?;
    let algorithm_version = clean_required(
        algorithm_version.unwrap_or_else(|| first.provider_version.clone()),
        "word timeline algorithm version",
    )?;
    let created_by = created_by.unwrap_or_else(|| {
        if first.timing_source == TimingSource::UserAdjusted {
            TimelineCreator::User
        } else {
            TimelineCreator::Algorithm
        }
    });
    let generated_config_hash = WordTimelineId::from_fingerprint(
        "word-timeline-config",
        &format!(
            "{}:{}:{}:{}:{}",
            track.id.as_str(),
            algorithm_id,
            algorithm_version,
            first.provider_id,
            first.provider_version
        ),
    )
    .as_str()
    .to_owned();
    let config_hash = clean_required(
        config_hash.unwrap_or(generated_config_hash),
        "word timeline config hash",
    )?;
    let now = now_ms();
    let id = WordTimelineId::from_fingerprint(
        "word-timeline",
        &format!(
            "{}:{}:{}:{}:{now}",
            track.id.as_str(),
            algorithm_id,
            algorithm_version,
            config_hash
        ),
    );
    Ok(WordTimeline {
        id,
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        algorithm_id,
        algorithm_version,
        config_hash,
        parent_timeline_id,
        created_by,
        status,
        metrics_json: metrics_json.unwrap_or_else(|| serde_json::json!({})),
        words,
        created_at_ms: now,
        updated_at_ms: now,
    })
}

pub(crate) fn save_word_timeline_snapshot(
    services: &AppServices,
    track_id: &SubtitleTrackId,
    timings: &[WordTiming],
    algorithm_id: &str,
    algorithm_version: &str,
    config_hash: &str,
    status: TimelineStatus,
    parent_timeline_id: Option<&WordTimelineId>,
) -> Option<WordTimelineId> {
    services
        .create_word_timeline(
            track_id,
            CreateWordTimeline {
                algorithm_id: Some(algorithm_id.into()),
                algorithm_version: Some(algorithm_version.into()),
                config_hash: Some(config_hash.into()),
                parent_timeline_id: parent_timeline_id.cloned(),
                created_by: Some(TimelineCreator::Algorithm),
                status: Some(status),
                metrics_json: None,
                words: timings.to_vec(),
            },
        )
        .ok()
        .map(|timeline| timeline.id)
}

pub(crate) fn forced_align_segments(sentences: &[SubtitleSentence]) -> Vec<ForcedAlignSegment> {
    sentences
        .iter()
        .filter_map(|sentence| {
            let words = sentence
                .tokens
                .iter()
                .filter(|token| token.kind == SubtitleTokenKind::Word)
                .map(|token| token.text.clone())
                .collect::<Vec<_>>();
            if words.is_empty() {
                return None;
            }
            Some(ForcedAlignSegment {
                index: sentence.index,
                text: sentence.display_text.clone(),
                words,
                start_ms: sentence.start.get(),
                end_ms: sentence.end.get(),
            })
        })
        .collect()
}

pub(crate) fn word_timeline_summary(timeline: &WordTimeline) -> WordTimelineSummary {
    let mut provider_ids = timeline
        .words
        .iter()
        .map(|word| word.provider_id.clone())
        .collect::<Vec<_>>();
    provider_ids.sort();
    provider_ids.dedup();
    let mut timing_sources = timeline
        .words
        .iter()
        .map(|word| word.timing_source)
        .collect::<Vec<_>>();
    timing_sources.sort();
    timing_sources.dedup();
    let confidence_values = timeline
        .words
        .iter()
        .filter_map(|word| word.confidence)
        .collect::<Vec<_>>();
    let average_confidence = if confidence_values.is_empty() {
        None
    } else {
        Some(confidence_values.iter().sum::<f32>() / confidence_values.len() as f32)
    };
    WordTimelineSummary {
        id: timeline.id.clone(),
        track_id: timeline.track_id.clone(),
        media_id: timeline.media_id.clone(),
        algorithm_id: timeline.algorithm_id.clone(),
        algorithm_version: timeline.algorithm_version.clone(),
        parent_timeline_id: timeline.parent_timeline_id.clone(),
        created_by: timeline.created_by,
        status: timeline.status,
        lifecycle_stage: word_timeline_lifecycle_stage(timeline),
        word_count: timeline.words.len() as u32,
        start_ms: timeline.words.iter().map(|word| word.start_ms).min(),
        end_ms: timeline.words.iter().map(|word| word.end_ms).max(),
        provider_ids,
        timing_sources,
        average_confidence,
        created_at_ms: timeline.created_at_ms,
        updated_at_ms: timeline.updated_at_ms,
        can_activate: timeline.status != TimelineStatus::Archived,
        can_archive: timeline.status != TimelineStatus::Archived,
        can_delete: true,
    }
}

pub(crate) fn word_timeline_lifecycle_stage(timeline: &WordTimeline) -> WordTimelineLifecycleStage {
    if timeline
        .metrics_json
        .pointer("/lifecycle/published")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false)
    {
        WordTimelineLifecycleStage::Published
    } else if timeline.created_by == TimelineCreator::User
        || timeline
            .words
            .iter()
            .any(|word| word.timing_source == TimingSource::UserAdjusted)
    {
        WordTimelineLifecycleStage::UserAdjusted
    } else {
        WordTimelineLifecycleStage::AlgorithmCandidate
    }
}

pub(crate) fn mark_word_timeline_published(timeline: &mut WordTimeline) {
    let now = now_ms();
    if !timeline.metrics_json.is_object() {
        timeline.metrics_json = serde_json::json!({});
    }
    let root = timeline
        .metrics_json
        .as_object_mut()
        .expect("metrics_json was normalized to object");
    let lifecycle = root
        .entry("lifecycle")
        .or_insert_with(|| serde_json::json!({}));
    if !lifecycle.is_object() {
        *lifecycle = serde_json::json!({});
    }
    let lifecycle = lifecycle
        .as_object_mut()
        .expect("lifecycle was normalized to object");
    lifecycle.insert("published".into(), serde_json::json!(true));
    lifecycle.insert("published_at_ms".into(), serde_json::json!(now));
}

pub(crate) fn lltimeline_segments_from_track(track: &SubtitleTrack) -> Vec<LLTimelineSegment> {
    track
        .sentences
        .iter()
        .map(|sentence| LLTimelineSegment {
            id: sentence.id.clone(),
            index: sentence.index,
            start_ms: sentence.start.get(),
            end_ms: sentence.end.get(),
            text: sentence.original_text.clone(),
            display_text: sentence.display_text.clone(),
            tokens: sentence
                .tokens
                .iter()
                .map(|token| LLTimelineToken {
                    index: token.index,
                    kind: token.kind,
                    text: token.text.clone(),
                    normalized: token.normalized.clone(),
                    start_char: token.start_char,
                    end_char: token.end_char,
                })
                .collect(),
        })
        .collect()
}

pub(crate) fn lltimeline_track_extra(
    track_id: &SubtitleTrackId,
    track_fingerprint: &str,
    track_source: &str,
) -> serde_json::Value {
    serde_json::json!({
        "track_id": track_id.as_str(),
        "track_fingerprint": track_fingerprint,
        "track_source": track_source,
    })
}

pub(crate) fn merge_lltimeline_track_extra(
    extra: serde_json::Value,
    track_id: &SubtitleTrackId,
    track_fingerprint: &str,
    track_source: &str,
) -> serde_json::Value {
    let mut merged = extra.as_object().cloned().unwrap_or_default();
    merged.insert("track_id".into(), serde_json::json!(track_id.as_str()));
    merged.insert(
        "track_fingerprint".into(),
        serde_json::json!(track_fingerprint),
    );
    merged.insert("track_source".into(), serde_json::json!(track_source));
    serde_json::Value::Object(merged)
}

pub(crate) fn lltimeline_track_id(
    document: &LLTimelineDocument,
) -> Result<SubtitleTrackId, ApplicationError> {
    if let Some(track_id) = document
        .metadata
        .extra
        .get("track_id")
        .and_then(serde_json::Value::as_str)
    {
        return SubtitleTrackId::parse(track_id.to_owned()).map_err(ApplicationError::from);
    }
    Ok(SubtitleTrackId::from_fingerprint(
        "subtitle-track",
        &format!(
            "{}:{}",
            document.metadata.media.id.as_str(),
            lltimeline_track_fingerprint(document)
        ),
    ))
}

pub(crate) fn lltimeline_track_fingerprint(document: &LLTimelineDocument) -> String {
    document
        .metadata
        .extra
        .get("track_fingerprint")
        .and_then(serde_json::Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_owned)
        .unwrap_or_else(|| {
            LLTimelineId::from_fingerprint(
                "lltimeline-track-fingerprint",
                &serde_json::to_string(&document.segments).unwrap_or_default(),
            )
            .as_str()
            .to_owned()
        })
}

pub(crate) fn remap_lltimeline_sentence_ids(
    document: &mut LLTimelineDocument,
    track_id: &SubtitleTrackId,
) {
    let mut sentence_ids = HashMap::new();
    for segment in &mut document.segments {
        let original = segment.id.clone();
        let remapped = SubtitleSentenceId::from_fingerprint(
            "subtitle-sentence",
            &format!("{}:{}", track_id.as_str(), original.as_str()),
        );
        segment.id = remapped.clone();
        sentence_ids.insert(original, remapped);
    }
    for timeline in &mut document.word_timelines {
        for word in &mut timeline.words {
            if let Some(sentence_id) = sentence_ids.get(&word.sentence_id) {
                word.sentence_id = sentence_id.clone();
            }
        }
    }
    for chunk_timeline in &mut document.chunk_timelines {
        for chunk in &mut chunk_timeline.chunks {
            if let Some(sentence_id) = sentence_ids.get(&chunk.sentence_id) {
                chunk.sentence_id = sentence_id.clone();
            }
        }
    }
    let mut word_timeline_ids = HashMap::new();
    for timeline in &mut document.word_timelines {
        let original = timeline.id.clone();
        let remapped = WordTimelineId::from_fingerprint(
            "word-timeline",
            &format!("{}:{}", track_id.as_str(), original.as_str()),
        );
        timeline.id = remapped.clone();
        word_timeline_ids.insert(original, remapped);
    }
    if let Some(active_id) = document.active_word_timeline_id.as_mut()
        && let Some(remapped) = word_timeline_ids.get(active_id)
    {
        *active_id = remapped.clone();
    }
    for timeline in &mut document.word_timelines {
        if let Some(parent_id) = timeline.parent_timeline_id.as_mut()
            && let Some(remapped) = word_timeline_ids.get(parent_id)
        {
            *parent_id = remapped.clone();
        }
    }
    for chunk_timeline in &mut document.chunk_timelines {
        if let Some(word_timeline_id) = chunk_timeline.parent_word_timeline_id.as_mut()
            && let Some(remapped) = word_timeline_ids.get(word_timeline_id)
        {
            *word_timeline_id = remapped.clone();
        }
    }
    let mut chunk_timeline_ids = HashMap::new();
    for timeline in &mut document.chunk_timelines {
        let original = timeline.id.clone();
        let remapped = ChunkTimelineId::from_fingerprint(
            "chunk-timeline",
            &format!("{}:{}", track_id.as_str(), original.as_str()),
        );
        timeline.id = remapped.clone();
        chunk_timeline_ids.insert(original, remapped.clone());
        for chunk in &mut timeline.chunks {
            chunk.id = ChunkId::from_fingerprint(
                "chunk",
                &format!(
                    "{}:{}:{}",
                    remapped.as_str(),
                    chunk.sentence_id.as_str(),
                    chunk.chunk_index
                ),
            );
        }
    }
    if let Some(active_id) = document.active_chunk_timeline_id.as_mut()
        && let Some(remapped) = chunk_timeline_ids.get(active_id)
    {
        *active_id = remapped.clone();
    }
}

pub(crate) fn lltimeline_segments_to_sentences(
    segments: &[LLTimelineSegment],
) -> Result<Vec<SubtitleSentence>, ApplicationError> {
    if segments.is_empty() {
        return Err(ApplicationError::Validation("lltimeline segments"));
    }
    let mut sentences = Vec::with_capacity(segments.len());
    for segment in segments {
        if segment.end_ms <= segment.start_ms {
            return Err(ApplicationError::Validation("lltimeline segment boundary"));
        }
        sentences.push(SubtitleSentence {
            id: segment.id.clone(),
            index: segment.index,
            start: TimeMs::new(segment.start_ms),
            end: TimeMs::new(segment.end_ms),
            original_text: segment.text.clone(),
            display_text: segment.display_text.clone(),
            tokens: segment
                .tokens
                .iter()
                .map(|token| SubtitleToken {
                    index: token.index,
                    kind: token.kind,
                    text: token.text.clone(),
                    normalized: token.normalized.clone(),
                    start_char: token.start_char,
                    end_char: token.end_char,
                })
                .collect(),
        });
    }
    sentences.sort_by_key(|sentence| (sentence.start, sentence.end, sentence.index));
    Ok(sentences)
}

pub(crate) fn word_timing_cache_is_usable(values: &[WordTiming]) -> bool {
    values.first().is_some_and(|first| {
        (first.timing_source != TimingSource::Estimated
            || (first.provider_id == "subtitle-weighted-estimator"
                && first.provider_version == "v1"))
            && values.iter().all(|value| value.start_ms < value.end_ms)
    })
}

pub(crate) fn chunk_partition_config_for_track_source(
    source: &str,
) -> speech_analysis::chunk_partition::ChunkPartitionConfig {
    if source.starts_with("ASR-") {
        speech_analysis::chunk_partition::ChunkPartitionConfig::for_asr_generated_subtitle()
    } else {
        speech_analysis::chunk_partition::ChunkPartitionConfig::default()
    }
}

#[cfg(test)]
mod tests;
