use std::collections::{BTreeMap, HashMap};
use std::path::Path;

use content_package::{KnownResource, ValidatedPackage};
use domain::{
    DetectedPhone, LLTIMELINE_SCHEMA_V1, LLTimelineArtifact, LLTimelineDocument,
    LLTimelineGenerator, LLTimelineMedia, LLTimelineMetadata, LLTimelineSegment, LLTimelineToken,
    LanguageCode, LexicalStress, MediaId, MediaItem, PhoneTimeline, PhoneTimelineId,
    PhoneTimelinePrecision, ProsodicChunk, ProsodyAnalysis, ProsodyAnalysisId, ProsodyAnchor,
    ProsodyEvidence, ProsodyWordRef, SenseGroup, SenseGroupAnalysis, SenseGroupAnalysisId,
    SenseGroupId, SenseGroupSource, SubtitleSentenceId, SubtitleTokenKind, SubtitleTrackId,
    TimelineCreator, TimelineMetrics, TimelineStatus, TimingSource, UtteranceRole, WordTimeline,
    WordTimelineId, WordTiming,
};

use crate::{ApplicationError, MediaAnalysisUseCases, SubtitleTrack};

const PACKAGE_GENERATOR_ID: &str = "listen-resource-package";
const PACKAGE_GENERATOR_VERSION: &str = "v1";
const ACOUSTIC_ARTIFACT_KIND: &str = "rhythm_word_acoustic_cues";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceImportDisposition {
    pub resource_id: String,
    pub kind: String,
    pub local_ids: Vec<String>,
    pub outcome: ResourceImportOutcome,
    pub reason: Option<String>,
    pub review_status: Option<ResourceImportReviewStatus>,
    pub provenance: Option<ResourceImportProvenance>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResourceImportOutcome {
    Consumed,
    PreservedNotConsumed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResourceImportReviewStatus {
    Unreviewed,
    MachineChecked,
    HumanReviewed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceImportProducer {
    pub id: String,
    pub version: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceImportProvenance {
    pub created_at_ms: u64,
    pub tool: ResourceImportProducer,
    pub provider: Option<ResourceImportProducer>,
    pub model: Option<ResourceImportProducer>,
    pub config_sha256: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentPackageImportReceipt {
    pub manifest_sha256: String,
    pub resources: Vec<ResourceImportDisposition>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct PreparedContentPackageImport {
    pub document: LLTimelineDocument,
    pub receipt: ContentPackageImportReceipt,
}

#[derive(Debug, Clone)]
pub struct ImportedContentPackage {
    pub track: SubtitleTrack,
    pub receipt: ContentPackageImportReceipt,
}

impl MediaAnalysisUseCases {
    /// Projects a validated exchange package for the dedicated candidate-only
    /// package import seam. This method is intentionally read-only.
    pub fn prepare_content_package_import(
        &self,
        media_id: &MediaId,
        package: &ValidatedPackage,
    ) -> Result<PreparedContentPackageImport, ApplicationError> {
        let media = self
            .media
            .get(media_id)?
            .ok_or(ApplicationError::NotFound("media item"))?;
        prepare_content_package_document(&media, package)
    }

    /// Projects and atomically attaches resources from a previously verified
    /// package as candidates. A Resource Package never selects or replaces an
    /// active analysis; that remains an explicit Core lifecycle decision.
    pub fn import_content_package(
        &self,
        media_id: &MediaId,
        package: &ValidatedPackage,
    ) -> Result<ImportedContentPackage, ApplicationError> {
        let media = self
            .media
            .get(media_id)?
            .ok_or(ApplicationError::NotFound("media item"))?;
        let prepared = prepare_content_package_document(&media, package)?;
        let projected_track =
            self.import_content_package_document_with_media(prepared.document, media)?;
        let track = self
            .subtitle_tracks
            .get_track(&projected_track.id)?
            .ok_or_else(|| {
                ApplicationError::Invalid(
                    "content package import committed without a durable track".into(),
                )
            })?;
        Ok(ImportedContentPackage {
            track,
            receipt: prepared.receipt,
        })
    }

    /// Inspects a directory or `.listenpkg` and imports its verified package.
    pub fn import_content_package_path(
        &self,
        media_id: &MediaId,
        path: &Path,
    ) -> Result<ImportedContentPackage, ApplicationError> {
        let inspected = content_package::inspect_path(path).map_err(|error| {
            ApplicationError::Invalid(format!("content package inspection failed: {error}"))
        })?;
        let mut imported = self.import_content_package(media_id, &inspected.package)?;
        imported.receipt.warnings.splice(0..0, inspected.warnings);
        Ok(imported)
    }
}

pub fn prepare_content_package_document(
    media: &MediaItem,
    package: &ValidatedPackage,
) -> Result<PreparedContentPackageImport, ApplicationError> {
    if !media_fingerprint_matches(
        &media.fingerprint,
        &package.manifest.content_document.media_fingerprint,
    ) {
        return Err(ApplicationError::Validation(
            "content package media fingerprint",
        ));
    }
    let subtitle_records = package
        .resources
        .iter()
        .filter(|record| matches!(record.resource, KnownResource::SubtitleTextTrack(_)))
        .collect::<Vec<_>>();
    if subtitle_records.len() != 1 {
        return Err(ApplicationError::Invalid(
            "content package must resolve exactly one subtitle text track".into(),
        ));
    }
    let subtitle_record = subtitle_records[0];
    let KnownResource::SubtitleTextTrack(subtitle) = &subtitle_record.resource else {
        unreachable!();
    };
    let language = LanguageCode::parse(&subtitle.payload.language)?;
    let origin_track_id = SubtitleTrackId::from_fingerprint(
        "content-package-track",
        &subtitle_record.descriptor.resource_id,
    );
    let segments = subtitle
        .payload
        .sentences
        .iter()
        .map(|sentence| {
            Ok(LLTimelineSegment {
                id: SubtitleSentenceId::parse(&sentence.id)?,
                index: sentence.index,
                start_ms: sentence.start_ms,
                end_ms: sentence.end_ms,
                text: sentence.original_text.clone(),
                display_text: sentence.display_text.clone(),
                tokens: sentence
                    .tokens
                    .iter()
                    .map(|token| LLTimelineToken {
                        index: token.index,
                        kind: match token.kind {
                            content_package::TokenKind::Word => SubtitleTokenKind::Word,
                            content_package::TokenKind::Whitespace => SubtitleTokenKind::Whitespace,
                            content_package::TokenKind::Punctuation => {
                                SubtitleTokenKind::Punctuation
                            }
                            content_package::TokenKind::Other => SubtitleTokenKind::Other,
                        },
                        text: token.text.clone(),
                        normalized: token.normalized.clone(),
                        start_char: token.start_char,
                        end_char: token.end_char,
                    })
                    .collect(),
            })
        })
        .collect::<Result<Vec<_>, ApplicationError>>()?;
    let sentence_lookup = segments
        .iter()
        .map(|sentence| (sentence.id.as_str().to_owned(), sentence))
        .collect::<HashMap<_, _>>();

    let mut receipt = ContentPackageImportReceipt {
        manifest_sha256: package.manifest_sha256.clone(),
        resources: vec![consumed(
            subtitle_record,
            vec![origin_track_id.as_str().to_owned()],
        )],
        warnings: Vec::new(),
    };
    let mut word_timelines = Vec::new();
    let mut word_ids = HashMap::<String, WordTimelineId>::new();
    let mut word_timing_lookup =
        HashMap::<(String, String, u32), &content_package::WordTiming>::new();

    for record in &package.resources {
        let KnownResource::WordTimeline(resource) = &record.resource else {
            continue;
        };
        let id = WordTimelineId::from_fingerprint(
            "content-package-word-timeline",
            &record.descriptor.resource_id,
        );
        let (provider_id, provider_version) = producer(resource);
        let words = resource
            .payload
            .words
            .iter()
            .map(|word| {
                let sentence = sentence_lookup.get(&word.sentence_id).ok_or_else(|| {
                    ApplicationError::Invalid("word timeline sentence was not converted".into())
                })?;
                let token = sentence
                    .tokens
                    .iter()
                    .find(|token| token.index == word.token_index)
                    .ok_or_else(|| {
                        ApplicationError::Invalid("word timeline token was not converted".into())
                    })?;
                word_timing_lookup.insert(
                    (
                        record.descriptor.resource_id.clone(),
                        word.sentence_id.clone(),
                        word.token_index,
                    ),
                    word,
                );
                Ok(WordTiming {
                    sentence_id: sentence.id.clone(),
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
            .collect::<Result<Vec<_>, ApplicationError>>()?;
        word_ids.insert(record.descriptor.resource_id.clone(), id.clone());
        word_timelines.push(WordTimeline {
            id: id.clone(),
            track_id: origin_track_id.clone(),
            media_id: media.id.clone(),
            algorithm_id: provider_id,
            algorithm_version: provider_version,
            config_hash: resource
                .provenance
                .config_sha256
                .clone()
                .unwrap_or_else(|| record.descriptor.resource_id.clone()),
            parent_timeline_id: None,
            created_by: TimelineCreator::Algorithm,
            status: TimelineStatus::Candidate,
            metrics_json: resource_metrics(record),
            words,
            created_at_ms: resource.provenance.created_at_ms,
            updated_at_ms: resource.provenance.created_at_ms,
        });
        receipt
            .resources
            .push(consumed(record, vec![id.as_str().to_owned()]));
    }

    let mut phone_timelines = Vec::new();
    for record in &package.resources {
        let KnownResource::PhoneTimeline(resource) = &record.resource else {
            continue;
        };
        if resource
            .payload
            .phones
            .iter()
            .any(|phone| phone.word_ref.is_none())
        {
            receipt.resources.push(not_consumed(
                record,
                "current PhoneTimeline cannot losslessly anchor a phone with null word_ref",
            ));
            continue;
        }
        let parent_resource_id = dependency_id(&resource.dependencies, "word_timeline")?;
        let parent_word_id = word_ids.get(parent_resource_id).cloned().ok_or_else(|| {
            ApplicationError::Invalid("phone timeline word dependency was not converted".into())
        })?;
        let (provider_id, provider_version) = producer(resource);
        let model_revision = resource
            .provenance
            .model
            .as_ref()
            .map(|model| model.version.clone())
            .unwrap_or_else(|| provider_version.clone());
        let mut by_sentence = BTreeMap::<String, Vec<DetectedPhone>>::new();
        for phone in &resource.payload.phones {
            let word_ref = phone.word_ref.as_ref().expect("checked above");
            by_sentence
                .entry(word_ref.sentence_id.clone())
                .or_default()
                .push(DetectedPhone {
                    symbol: phone.symbol.clone(),
                    display_ipa: phone
                        .display_ipa
                        .clone()
                        .unwrap_or_else(|| phone.symbol.clone()),
                    phone_set: resource.payload.phone_set.clone(),
                    start_ms: phone.start_ms,
                    end_ms: phone.end_ms,
                    confidence: phone.confidence.map(|value| value as f32),
                    token_index: Some(word_ref.token_index),
                    provider_id: provider_id.clone(),
                    provider_version: provider_version.clone(),
                    model_revision: model_revision.clone(),
                });
        }
        let mut local_ids = Vec::new();
        for (sentence, phones) in by_sentence {
            let sentence_id = SubtitleSentenceId::parse(&sentence)?;
            let id = PhoneTimelineId::from_fingerprint(
                "content-package-phone-timeline",
                &format!("{}:{sentence}", record.descriptor.resource_id),
            );
            local_ids.push(id.as_str().to_owned());
            phone_timelines.push(PhoneTimeline {
                id,
                track_id: origin_track_id.clone(),
                media_id: media.id.clone(),
                sentence_id: Some(sentence_id),
                parent_word_timeline_id: Some(parent_word_id.clone()),
                parent_phonetic_analysis_id: None,
                provider_id: provider_id.clone(),
                provider_version: provider_version.clone(),
                model_id: None,
                model_revision: Some(model_revision.clone()),
                phone_set: resource.payload.phone_set.clone(),
                precision: map_phone_precision(resource.payload.precision),
                created_by: TimelineCreator::Algorithm,
                status: TimelineStatus::Candidate,
                metrics_json: resource_metrics(record),
                phones,
                alignments: Vec::new(),
                findings: Vec::new(),
                sound_analysis: None,
                created_at_ms: resource.provenance.created_at_ms,
                updated_at_ms: resource.provenance.created_at_ms,
            });
        }
        receipt.resources.push(consumed(record, local_ids));
    }

    let mut sense_group_analyses = Vec::new();
    for record in &package.resources {
        let KnownResource::SenseGroupAnalysis(resource) = &record.resource else {
            continue;
        };
        let id = SenseGroupAnalysisId::from_fingerprint(
            "content-package-sense-group",
            &record.descriptor.resource_id,
        );
        let (provider_id, provider_version) = producer(resource);
        let groups = resource
            .payload
            .groups
            .iter()
            .map(|group| {
                let sentence = sentence_lookup.get(&group.sentence_id).ok_or_else(|| {
                    ApplicationError::Invalid("sense group sentence was not converted".into())
                })?;
                let text = sentence
                    .tokens
                    .iter()
                    .filter(|token| {
                        token.index >= group.start_token_index
                            && token.index < group.end_token_index_exclusive
                    })
                    .map(|token| token.text.as_str())
                    .collect::<String>();
                Ok(SenseGroup {
                    id: SenseGroupId::from_fingerprint(
                        "content-package-sense-group-item",
                        &format!(
                            "{}:{}:{}",
                            record.descriptor.resource_id, group.sentence_id, group.group_index
                        ),
                    ),
                    sentence_id: sentence.id.clone(),
                    group_index: group.group_index,
                    start_token_index: group.start_token_index,
                    end_token_index: group.end_token_index_exclusive - 1,
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
            .collect::<Result<Vec<_>, ApplicationError>>()?;
        sense_group_analyses.push(SenseGroupAnalysis {
            id: id.clone(),
            track_id: origin_track_id.clone(),
            media_id: media.id.clone(),
            parent_word_timeline_id: None,
            provider_id,
            provider_version,
            algorithm: PACKAGE_GENERATOR_ID.into(),
            status: TimelineStatus::Candidate,
            created_by: TimelineCreator::Algorithm,
            metrics_json: resource_metrics(record),
            groups,
            created_at_ms: resource.provenance.created_at_ms,
            updated_at_ms: resource.provenance.created_at_ms,
        });
        receipt
            .resources
            .push(consumed(record, vec![id.as_str().to_owned()]));
    }

    let mut prosody_analyses = Vec::new();
    for record in &package.resources {
        let KnownResource::ProsodyAnalysis(resource) = &record.resource else {
            continue;
        };
        let parent_resource_id = dependency_id(&resource.dependencies, "word_timeline")?;
        let Some(parent_word_id) = word_ids.get(parent_resource_id) else {
            return Err(ApplicationError::Invalid(
                "prosody analysis word dependency was not converted".into(),
            ));
        };
        let (provider_id, provider_version) = producer(resource);
        let chunks = resource
            .payload
            .chunks
            .iter()
            .map(|chunk| {
                let sentence = sentence_lookup.get(&chunk.sentence_id).ok_or_else(|| {
                    ApplicationError::Invalid("prosodic chunk sentence was not converted".into())
                })?;
                if chunk.end_token_index_exclusive <= chunk.start_token_index
                    || !sentence
                        .tokens
                        .iter()
                        .any(|token| token.index == chunk.start_token_index)
                    || !sentence
                        .tokens
                        .iter()
                        .any(|token| token.index == chunk.end_token_index_exclusive - 1)
                    || chunk.nucleus_token_index.is_some_and(|index| {
                        index < chunk.start_token_index || index >= chunk.end_token_index_exclusive
                    })
                {
                    return Err(ApplicationError::Invalid(
                        "prosodic chunk token span was not converted".into(),
                    ));
                }
                Ok(ProsodicChunk {
                    sentence_id: sentence.id.clone(),
                    chunk_index: chunk.chunk_index,
                    start_token_index: chunk.start_token_index,
                    end_token_index: chunk.end_token_index_exclusive - 1,
                    nucleus_token_index: chunk.nucleus_token_index,
                    confidence: chunk.confidence,
                })
            })
            .collect::<Result<Vec<_>, ApplicationError>>()?;
        let anchors = resource
            .payload
            .anchors
            .iter()
            .map(|anchor| {
                let key = (
                    parent_resource_id.to_owned(),
                    anchor.word_ref.sentence_id.clone(),
                    anchor.word_ref.token_index,
                );
                // The prosody resource's word_timeline dependency is exact: an
                // anchor must reference a token the parent timeline actually
                // timed, so the read-time playback projection always resolves.
                word_timing_lookup.get(&key).ok_or_else(|| {
                    ApplicationError::Invalid(
                        "prosody anchor reference has no converted timing".into(),
                    )
                })?;
                let sentence = sentence_lookup
                    .get(&anchor.word_ref.sentence_id)
                    .ok_or_else(|| {
                        ApplicationError::Invalid(
                            "prosody anchor sentence was not converted".into(),
                        )
                    })?;
                let token = sentence
                    .tokens
                    .iter()
                    .find(|token| token.index == anchor.word_ref.token_index)
                    .ok_or_else(|| {
                        ApplicationError::Invalid("prosody anchor token was not converted".into())
                    })?;
                if token.kind != SubtitleTokenKind::Word {
                    return Err(ApplicationError::Invalid(
                        "prosody anchor must reference a word token".into(),
                    ));
                }
                Ok(ProsodyAnchor {
                    word_ref: ProsodyWordRef {
                        sentence_id: sentence.id.clone(),
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
            .collect::<Result<Vec<_>, ApplicationError>>()?;
        let id = ProsodyAnalysisId::from_fingerprint(
            "content-package-prosody",
            &record.descriptor.resource_id,
        );
        prosody_analyses.push(ProsodyAnalysis {
            id: id.clone(),
            track_id: origin_track_id.clone(),
            media_id: media.id.clone(),
            parent_word_timeline_id: Some(parent_word_id.clone()),
            provider_id,
            provider_version,
            algorithm: PACKAGE_GENERATOR_ID.into(),
            status: TimelineStatus::Candidate,
            created_by: TimelineCreator::Algorithm,
            metrics_json: resource_metrics(record),
            chunks,
            anchors,
            created_at_ms: resource.provenance.created_at_ms,
            updated_at_ms: resource.provenance.created_at_ms,
        });
        receipt
            .resources
            .push(consumed(record, vec![id.as_str().to_owned()]));
    }

    let mut artifacts = Vec::new();
    for record in &package.resources {
        match &record.resource {
            KnownResource::WordAcoustics(resource) => {
                let parent_resource_id = dependency_id(&resource.dependencies, "word_timeline")?;
                let Some(parent_word_id) = word_ids.get(parent_resource_id) else {
                    return Err(ApplicationError::Invalid(
                        "word acoustics dependency was not converted".into(),
                    ));
                };
                let cues = resource
                    .payload
                    .measurements
                    .iter()
                    .map(|measurement| {
                        let key = (
                            parent_resource_id.to_owned(),
                            measurement.word_ref.sentence_id.clone(),
                            measurement.word_ref.token_index,
                        );
                        let timing = word_timing_lookup.get(&key).ok_or_else(|| {
                            ApplicationError::Invalid(
                                "word acoustics reference has no converted timing".into(),
                            )
                        })?;
                        let sentence = sentence_lookup
                            .get(&measurement.word_ref.sentence_id)
                            .ok_or_else(|| {
                                ApplicationError::Invalid(
                                    "word acoustics sentence was not converted".into(),
                                )
                            })?;
                        let token = sentence
                            .tokens
                            .iter()
                            .find(|token| token.index == measurement.word_ref.token_index)
                            .ok_or_else(|| {
                                ApplicationError::Invalid(
                                    "word acoustics token was not converted".into(),
                                )
                            })?;
                        Ok(serde_json::json!({
                            "sentence_id": measurement.word_ref.sentence_id,
                            "token_index": measurement.word_ref.token_index,
                            "text": token.text,
                            "start_ms": timing.start_ms,
                            "end_ms": timing.end_ms,
                            "energy_prominence": measurement.energy.prominence,
                            "dbfs": measurement.energy.rms_dbfs,
                            "sentence_median_dbfs": measurement.energy.local_baseline_dbfs,
                            "db_delta_from_sentence_median": measurement.energy.delta_db,
                            "pitch_prominence": measurement.pitch.prominence,
                            "f0_median_hz": measurement.pitch.median_f0_hz,
                            "f0_range_semitones": measurement.pitch.range_semitones,
                            "voiced_frame_ratio": measurement.voiced_frame_ratio,
                            "pitch_reset_after": measurement.pitch.reset_after
                        }))
                    })
                    .collect::<Result<Vec<_>, ApplicationError>>()?;
                let (provider_id, provider_version) = producer(resource);
                artifacts.push(LLTimelineArtifact {
                    kind: ACOUSTIC_ARTIFACT_KIND.into(),
                    provider_id: Some(provider_id),
                    provider_version: Some(provider_version),
                    payload: serde_json::json!({
                        "status": "scored",
                        "line": "sound",
                        "resource_id": record.descriptor.resource_id,
                        "timeline_id": parent_word_id.as_str(),
                        "sample_rate_hz": resource.payload.sample_rate_hz,
                        "calibration": {
                            "energy": "sentence_median_dbfs",
                            "pitch": "sentence_median_f0_hz"
                        },
                        "cues": cues
                    }),
                });
                receipt.resources.push(consumed(record, Vec::new()));
            }
            KnownResource::ProsodyAnalysis(_) => {}
            _ => {}
        }
    }
    for opaque in &package.opaque_resources {
        receipt.resources.push(ResourceImportDisposition {
            resource_id: opaque.descriptor.resource_id.clone(),
            kind: opaque.descriptor.kind.clone(),
            local_ids: Vec::new(),
            outcome: ResourceImportOutcome::PreservedNotConsumed,
            reason: Some("optional unknown resource remains preserved in the package".into()),
            review_status: None,
            provenance: None,
        });
    }

    let document = LLTimelineDocument {
        schema: LLTIMELINE_SCHEMA_V1.into(),
        metadata: LLTimelineMetadata {
            created_at_ms: package.manifest.created_at_ms,
            generator: LLTimelineGenerator {
                id: PACKAGE_GENERATOR_ID.into(),
                version: PACKAGE_GENERATOR_VERSION.into(),
                mode: "exchange_adapter".into(),
            },
            media: LLTimelineMedia {
                id: media.id.clone(),
                fingerprint: media.fingerprint.clone(),
                path: None,
                title: package.manifest.content_document.title.clone(),
                duration_ms: Some(package.manifest.content_document.duration_ms),
            },
            language: Some(language),
            human_reviewed: matches!(
                subtitle.quality.review_status,
                content_package::ReviewStatus::HumanReviewed
            ),
            extra: serde_json::json!({
                "track_id": origin_track_id.as_str(),
                "track_fingerprint": subtitle_record.descriptor.resource_id,
                "track_source": "listen-resource-package-v1",
                "package_manifest_sha256": package.manifest_sha256
            }),
        },
        segments,
        word_timelines,
        active_word_timeline_id: None,
        phone_timelines,
        active_phone_timeline_id: None,
        rhythm_frames: Vec::new(),
        chunk_timelines: Vec::new(),
        active_chunk_timeline_id: None,
        sense_group_analyses,
        active_sense_group_analysis_id: None,
        prosody_analyses,
        active_prosody_analysis_id: None,
        artifacts,
    };
    Ok(PreparedContentPackageImport { document, receipt })
}

fn media_fingerprint_matches(stored: &str, packaged: &str) -> bool {
    if stored == packaged {
        return true;
    }

    let Some(packaged_digest) = packaged.strip_prefix("sha256:") else {
        return false;
    };
    stored.len() == 64
        && stored
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
        && stored == packaged_digest
}

fn producer<P>(resource: &content_package::ResourceEnvelope<P>) -> (String, String) {
    resource
        .provenance
        .provider
        .as_ref()
        .unwrap_or(&resource.provenance.tool)
        .to_owned()
        .into_parts()
}

trait ProducerParts {
    fn into_parts(self) -> (String, String);
}

impl ProducerParts for content_package::VersionedProducer {
    fn into_parts(self) -> (String, String) {
        (self.id, self.version)
    }
}

fn dependency_id<'a>(
    dependencies: &'a [content_package::ResourceDependency],
    kind: &str,
) -> Result<&'a str, ApplicationError> {
    dependencies
        .iter()
        .find(|dependency| dependency.kind == kind)
        .map(|dependency| dependency.resource_id.as_str())
        .ok_or_else(|| ApplicationError::Invalid(format!("missing {kind} dependency")))
}

fn resource_metrics(record: &content_package::ResourceRecord) -> TimelineMetrics {
    TimelineMetrics::from_value(serde_json::json!({
        "exchange_resource_id": record.descriptor.resource_id,
        "exchange_schema": record.descriptor.schema,
        "line": "sound"
    }))
}

fn consumed(
    record: &content_package::ResourceRecord,
    local_ids: Vec<String>,
) -> ResourceImportDisposition {
    ResourceImportDisposition {
        resource_id: record.descriptor.resource_id.clone(),
        kind: record.descriptor.kind.clone(),
        local_ids,
        outcome: ResourceImportOutcome::Consumed,
        reason: None,
        review_status: Some(review_status(record)),
        provenance: Some(provenance(record)),
    }
}

fn not_consumed(
    record: &content_package::ResourceRecord,
    reason: &str,
) -> ResourceImportDisposition {
    ResourceImportDisposition {
        resource_id: record.descriptor.resource_id.clone(),
        kind: record.descriptor.kind.clone(),
        local_ids: Vec::new(),
        outcome: ResourceImportOutcome::PreservedNotConsumed,
        reason: Some(reason.into()),
        review_status: Some(review_status(record)),
        provenance: Some(provenance(record)),
    }
}

fn review_status(record: &content_package::ResourceRecord) -> ResourceImportReviewStatus {
    match record.resource.quality().review_status {
        content_package::ReviewStatus::Unreviewed => ResourceImportReviewStatus::Unreviewed,
        content_package::ReviewStatus::MachineChecked => ResourceImportReviewStatus::MachineChecked,
        content_package::ReviewStatus::HumanReviewed => ResourceImportReviewStatus::HumanReviewed,
    }
}

fn provenance(record: &content_package::ResourceRecord) -> ResourceImportProvenance {
    let value = record.resource.provenance();
    ResourceImportProvenance {
        created_at_ms: value.created_at_ms,
        tool: producer_descriptor(&value.tool),
        provider: value.provider.as_ref().map(producer_descriptor),
        model: value.model.as_ref().map(producer_descriptor),
        config_sha256: value.config_sha256.clone(),
    }
}

fn producer_descriptor(value: &content_package::VersionedProducer) -> ResourceImportProducer {
    ResourceImportProducer {
        id: value.id.clone(),
        version: value.version.clone(),
    }
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
    use std::path::Path;

    use content_package::inspect_path;
    use domain::{MediaAvailability, MediaKind, TimeMs};

    use super::*;

    fn canonical_package() -> ValidatedPackage {
        inspect_path(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../contracts/content-package/v1/examples/minimal"),
        )
        .unwrap()
        .package
    }

    fn matching_media() -> MediaItem {
        MediaItem {
            id: MediaId::parse("content-package-media").unwrap(),
            path: "/tmp/content-package-media.mp4".into(),
            fingerprint: format!("sha256:{}", "a".repeat(64)),
            title: "Local media".into(),
            kind: MediaKind::Video,
            duration: Some(TimeMs::new(2_500)),
            availability: MediaAvailability::Available,
            created_at_ms: 1,
            updated_at_ms: 1,
        }
    }

    #[test]
    fn converts_canonical_full_package_to_candidate_document() {
        let prepared =
            prepare_content_package_document(&matching_media(), &canonical_package()).unwrap();
        assert_eq!(prepared.document.segments.len(), 1);
        assert_eq!(prepared.document.word_timelines.len(), 1);
        assert_eq!(prepared.document.phone_timelines.len(), 1);
        assert_eq!(prepared.document.sense_group_analyses.len(), 1);
        assert_eq!(prepared.document.prosody_analyses.len(), 1);
        assert_eq!(prepared.document.artifacts.len(), 1);
        assert!(
            prepared
                .document
                .word_timelines
                .iter()
                .all(|timeline| timeline.status == TimelineStatus::Candidate)
        );
        assert!(
            prepared
                .document
                .phone_timelines
                .iter()
                .all(|timeline| timeline.status == TimelineStatus::Candidate)
        );
        assert!(
            prepared
                .document
                .prosody_analyses
                .iter()
                .all(|analysis| analysis.status == TimelineStatus::Candidate)
        );
        assert!(prepared.document.active_word_timeline_id.is_none());
        assert!(prepared.document.active_phone_timeline_id.is_none());
        assert!(prepared.document.active_sense_group_analysis_id.is_none());
        assert!(prepared.document.active_prosody_analysis_id.is_none());
        let prosody = prepared
            .document
            .prosody_analyses
            .iter()
            .find(|analysis| analysis.parent_word_timeline_id.is_some())
            .unwrap();
        assert!(!prosody.anchors.is_empty());
        assert!(prosody.anchors.iter().all(|anchor| {
            anchor.lexical_stress != domain::LexicalStress::Unknown
                && anchor.realized_prominence >= 0.0
        }));
        let prosody_disposition = prepared
            .receipt
            .resources
            .iter()
            .find(|resource| resource.kind == "prosody_analysis")
            .unwrap();
        assert_eq!(prosody_disposition.outcome, ResourceImportOutcome::Consumed);
        assert_eq!(prosody_disposition.local_ids.len(), 1);
        assert!(prepared.receipt.resources.iter().all(|resource| {
            resource.review_status.is_some()
                && resource.provenance.as_ref().is_some_and(|provenance| {
                    provenance.tool.id == "listen-gen" && provenance.tool.version == "0.1.0"
                })
        }));
        let subtitle = prepared
            .receipt
            .resources
            .iter()
            .find(|resource| resource.kind == "subtitle_text_track")
            .unwrap();
        assert_eq!(
            subtitle.review_status,
            Some(ResourceImportReviewStatus::MachineChecked)
        );
        assert_eq!(
            subtitle
                .provenance
                .as_ref()
                .and_then(|provenance| provenance.provider.as_ref())
                .map(|provider| provider.id.as_str()),
            Some("example-asr")
        );
        assert!(prepared.receipt.warnings.is_empty());
        assert_eq!(
            prepared.document.artifacts[0].payload["cues"][0]["voiced_frame_ratio"],
            serde_json::Value::Null
        );
    }

    #[test]
    fn converts_subtitle_only_package_without_inventing_analyses() {
        let mut package = canonical_package();
        package
            .resources
            .retain(|record| record.descriptor.kind == "subtitle_text_track");
        package
            .manifest
            .resources
            .retain(|record| record.kind == "subtitle_text_track");
        let prepared = prepare_content_package_document(&matching_media(), &package).unwrap();
        assert_eq!(prepared.document.segments.len(), 1);
        assert!(prepared.document.word_timelines.is_empty());
        assert!(prepared.document.phone_timelines.is_empty());
        assert!(prepared.document.sense_group_analyses.is_empty());
        assert!(prepared.document.prosody_analyses.is_empty());
        assert!(prepared.document.artifacts.is_empty());
        assert_eq!(prepared.receipt.resources.len(), 1);
    }

    #[test]
    fn media_mismatch_is_rejected_before_conversion() {
        let mut media = matching_media();
        media.fingerprint = format!("sha256:{}", "b".repeat(64));
        let error = prepare_content_package_document(&media, &canonical_package()).unwrap_err();
        assert!(matches!(
            error,
            ApplicationError::Validation("content package media fingerprint")
        ));
    }

    #[test]
    fn legacy_bare_sha256_media_fingerprint_matches_v1_package() {
        let mut media = matching_media();
        let media_id = media.id.clone();
        media.fingerprint = "a".repeat(64);

        let prepared = prepare_content_package_document(&media, &canonical_package()).unwrap();

        assert_eq!(prepared.document.metadata.media.id, media_id);
        assert_eq!(prepared.document.metadata.media.fingerprint, "a".repeat(64));
    }

    #[test]
    fn malformed_bare_media_fingerprint_is_not_treated_as_sha256() {
        for fingerprint in ["a".repeat(63), "A".repeat(64), "g".repeat(64)] {
            let mut media = matching_media();
            media.fingerprint = fingerprint;
            let error = prepare_content_package_document(&media, &canonical_package()).unwrap_err();
            assert!(matches!(
                error,
                ApplicationError::Validation("content package media fingerprint")
            ));
        }
    }

    #[test]
    fn conversion_is_deterministic_and_has_no_partial_result_on_failure() {
        let package = canonical_package();
        let first = prepare_content_package_document(&matching_media(), &package).unwrap();
        let second = prepare_content_package_document(&matching_media(), &package).unwrap();
        assert_eq!(
            serde_json::to_value(&first.document).unwrap(),
            serde_json::to_value(&second.document).unwrap()
        );

        let mut ambiguous = package;
        let duplicate = ambiguous
            .resources
            .iter()
            .find(|record| record.descriptor.kind == "subtitle_text_track")
            .unwrap()
            .clone();
        ambiguous.resources.push(duplicate);
        assert!(prepare_content_package_document(&matching_media(), &ambiguous).is_err());
    }

    #[test]
    fn phone_with_null_word_reference_is_preserved_not_fabricated() {
        let mut package = canonical_package();
        let phone = package
            .resources
            .iter_mut()
            .find_map(|record| match &mut record.resource {
                KnownResource::PhoneTimeline(resource) => Some(resource),
                _ => None,
            })
            .unwrap();
        phone.payload.phones[0].word_ref = None;
        let prepared = prepare_content_package_document(&matching_media(), &package).unwrap();
        assert!(prepared.document.phone_timelines.is_empty());
        assert!(prepared.receipt.resources.iter().any(|resource| {
            resource.kind == "phone_timeline"
                && resource.outcome == ResourceImportOutcome::PreservedNotConsumed
                && resource.review_status == Some(ResourceImportReviewStatus::Unreviewed)
                && resource.provenance.is_some()
        }));
    }

    #[test]
    fn opaque_optional_resource_reports_unknown_review_and_provenance() {
        let mut package = canonical_package();
        let index = package
            .resources
            .iter()
            .position(|record| record.descriptor.kind == "prosody_analysis")
            .unwrap();
        let record = package.resources.remove(index);
        package
            .opaque_resources
            .push(content_package::OpaqueResource {
                descriptor: record.descriptor,
                subject: record.resource.subject().clone(),
                dependencies: record.resource.dependencies().to_vec(),
                bytes: record.bytes,
            });

        let prepared = prepare_content_package_document(&matching_media(), &package).unwrap();
        let opaque = prepared
            .receipt
            .resources
            .iter()
            .find(|resource| resource.kind == "prosody_analysis")
            .unwrap();
        assert_eq!(opaque.outcome, ResourceImportOutcome::PreservedNotConsumed);
        assert_eq!(opaque.review_status, None);
        assert_eq!(opaque.provenance, None);
    }
}
