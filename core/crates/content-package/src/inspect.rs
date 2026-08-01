use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fs;
use std::io::{Cursor, Read};
use std::path::{Component, Path};

use sha2::{Digest as _, Sha256};
use thiserror::Error;

use crate::model::{
    KnownResource, PACKAGE_SCHEMA_V1, PHONE_TIMELINE_SCHEMA_V1, PROSODY_ANALYSIS_SCHEMA_V1,
    PackageManifest, PhoneTimeline, ProsodyAnalysis, ResourceDependency, ResourceEnvelope,
    ResourceManifestEntry, ResourceSubject, SENSE_GROUP_ANALYSIS_SCHEMA_V1,
    SUBTITLE_TEXT_TRACK_SCHEMA_V1, SenseGroupAnalysis, SubtitleSentence, SubtitleTextTrack,
    TokenKind, TokenRef, WORD_ACOUSTICS_SCHEMA_V1, WORD_TIMELINE_SCHEMA_V1, WordAcoustics,
    WordTimeline,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InspectLimits {
    pub max_file_count: usize,
    pub max_file_bytes: u64,
    pub max_manifest_bytes: u64,
    pub max_total_bytes: u64,
}

impl Default for InspectLimits {
    fn default() -> Self {
        Self {
            max_file_count: 1_024,
            max_file_bytes: 32 * 1024 * 1024,
            max_manifest_bytes: 4 * 1024 * 1024,
            max_total_bytes: 256 * 1024 * 1024,
        }
    }
}

#[derive(Debug, Clone)]
pub struct PackageInspection {
    pub package: ValidatedPackage,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct ValidatedPackage {
    pub manifest: PackageManifest,
    pub manifest_sha256: String,
    pub resources: Vec<ResourceRecord>,
    pub opaque_resources: Vec<OpaqueResource>,
    pub total_bytes: u64,
}

#[derive(Debug, Clone)]
pub struct ResourceRecord {
    pub descriptor: ResourceManifestEntry,
    pub resource: KnownResource,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct OpaqueResource {
    pub descriptor: ResourceManifestEntry,
    pub subject: ResourceSubject,
    pub dependencies: Vec<ResourceDependency>,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Error)]
pub enum PackageError {
    #[error("could not access package: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid ZIP package: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("package limit exceeded: {0}")]
    Limit(&'static str),
    #[error("invalid package entry path: {0}")]
    UnsafePath(String),
    #[error("symbolic links are not allowed in packages: {0}")]
    Symlink(String),
    #[error("duplicate package entry: {0}")]
    DuplicatePath(String),
    #[error("manifest.json is missing")]
    MissingManifest,
    #[error("manifest is invalid JSON: {0}")]
    ManifestJson(serde_json::Error),
    #[error("resource {path} is invalid JSON: {source}")]
    ResourceJson {
        path: String,
        #[source]
        source: serde_json::Error,
    },
    #[error("invalid package at {path}: {message}")]
    Invalid { path: String, message: String },
}

pub fn inspect_path(path: impl AsRef<Path>) -> Result<PackageInspection, PackageError> {
    inspect_path_with_limits(path, InspectLimits::default())
}

pub fn inspect_path_with_limits(
    path: impl AsRef<Path>,
    limits: InspectLimits,
) -> Result<PackageInspection, PackageError> {
    let path = path.as_ref();
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() {
        return Err(PackageError::Symlink(path.display().to_string()));
    }
    let files = if metadata.is_dir() {
        read_directory(path, limits)?
    } else {
        read_zip(path, limits)?
    };
    inspect_files(files, limits)
}

fn read_directory(
    root: &Path,
    limits: InspectLimits,
) -> Result<BTreeMap<String, Vec<u8>>, PackageError> {
    let mut pending = vec![root.to_path_buf()];
    let mut files = BTreeMap::new();
    let mut total = 0_u64;
    while let Some(directory) = pending.pop() {
        for entry in fs::read_dir(&directory)? {
            let entry = entry?;
            let metadata = fs::symlink_metadata(entry.path())?;
            let relative = entry
                .path()
                .strip_prefix(root)
                .map_err(|_| invalid("package", "entry escaped package root"))?
                .to_path_buf();
            let name = safe_path_string(&relative)?;
            if metadata.file_type().is_symlink() {
                return Err(PackageError::Symlink(name));
            }
            if metadata.is_dir() {
                pending.push(entry.path());
                continue;
            }
            if !metadata.is_file() {
                return Err(invalid(&name, "entry is not a regular file"));
            }
            enforce_file_limits(&name, metadata.len(), &mut total, files.len(), limits)?;
            let bytes = fs::read(entry.path())?;
            if files.insert(name.clone(), bytes).is_some() {
                return Err(PackageError::DuplicatePath(name));
            }
        }
    }
    Ok(files)
}

fn read_zip(path: &Path, limits: InspectLimits) -> Result<BTreeMap<String, Vec<u8>>, PackageError> {
    if fs::metadata(path)?.len() > limits.max_total_bytes {
        return Err(PackageError::Limit("ZIP file size"));
    }
    let bytes = fs::read(path)?;
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes))?;
    if archive.len() > limits.max_file_count {
        return Err(PackageError::Limit("ZIP entry count"));
    }
    let mut files = BTreeMap::new();
    let mut total = 0_u64;
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index)?;
        let raw_name = entry.name().to_owned();
        let enclosed = entry
            .enclosed_name()
            .ok_or_else(|| PackageError::UnsafePath(raw_name.clone()))?;
        let name = safe_path_string(&enclosed)?;
        if entry.is_symlink() {
            return Err(PackageError::Symlink(name));
        }
        if entry.is_dir() {
            continue;
        }
        enforce_file_limits(&name, entry.size(), &mut total, files.len(), limits)?;
        let capacity =
            usize::try_from(entry.size()).map_err(|_| PackageError::Limit("file size"))?;
        let mut contents = Vec::with_capacity(capacity);
        entry
            .by_ref()
            .take(limits.max_file_bytes.saturating_add(1))
            .read_to_end(&mut contents)?;
        if contents.len() as u64 != entry.size() {
            return Err(invalid(
                &name,
                "ZIP entry size does not match decompressed bytes",
            ));
        }
        if files.insert(name.clone(), contents).is_some() {
            return Err(PackageError::DuplicatePath(name));
        }
    }
    Ok(files)
}

fn enforce_file_limits(
    name: &str,
    size: u64,
    total: &mut u64,
    current_count: usize,
    limits: InspectLimits,
) -> Result<(), PackageError> {
    if current_count >= limits.max_file_count {
        return Err(PackageError::Limit("file count"));
    }
    let maximum = if name == "manifest.json" {
        limits.max_manifest_bytes
    } else {
        limits.max_file_bytes
    };
    if size > maximum {
        return Err(PackageError::Limit("file size"));
    }
    *total = total
        .checked_add(size)
        .ok_or(PackageError::Limit("total decompressed size"))?;
    if *total > limits.max_total_bytes {
        return Err(PackageError::Limit("total decompressed size"));
    }
    Ok(())
}

fn safe_path_string(path: &Path) -> Result<String, PackageError> {
    if path.as_os_str().is_empty() || path.is_absolute() {
        return Err(PackageError::UnsafePath(path.display().to_string()));
    }
    let mut parts = Vec::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => {
                let part = part
                    .to_str()
                    .ok_or_else(|| PackageError::UnsafePath(path.display().to_string()))?;
                if part.contains('\\') || part.contains(':') || part.chars().any(char::is_control) {
                    return Err(PackageError::UnsafePath(path.display().to_string()));
                }
                parts.push(part);
            }
            _ => return Err(PackageError::UnsafePath(path.display().to_string())),
        }
    }
    Ok(parts.join("/"))
}

type ResourceProbe = ResourceEnvelope<serde_json::Value>;

fn inspect_files(
    mut files: BTreeMap<String, Vec<u8>>,
    _limits: InspectLimits,
) -> Result<PackageInspection, PackageError> {
    let manifest_bytes = files
        .remove("manifest.json")
        .ok_or(PackageError::MissingManifest)?;
    let manifest: PackageManifest =
        serde_json::from_slice(&manifest_bytes).map_err(PackageError::ManifestJson)?;
    if manifest.schema != PACKAGE_SCHEMA_V1 {
        return Err(invalid("manifest.json", "unsupported package schema"));
    }
    if manifest.resources.is_empty() {
        return Err(invalid("manifest.json", "package contains no resources"));
    }
    if !manifest.resources.iter().any(|entry| {
        entry.required
            && entry.kind == "subtitle_text_track"
            && entry.schema == SUBTITLE_TEXT_TRACK_SCHEMA_V1
    }) {
        return Err(invalid(
            "manifest.json",
            "package requires no supported subtitle text track",
        ));
    }
    validate_media_fingerprint(
        "manifest.json",
        &manifest.content_document.media_fingerprint,
    )?;
    if manifest.content_document.title.trim().is_empty()
        || manifest.content_document.duration_ms == 0
    {
        return Err(invalid(
            "manifest.json",
            "content document title and duration must be non-empty",
        ));
    }

    let mut resource_ids = HashSet::new();
    let mut manifest_paths = HashSet::new();
    let mut known = Vec::new();
    let mut opaque = Vec::new();
    let mut graph = HashMap::<String, Vec<String>>::new();
    let mut typed_edges = HashMap::<String, Vec<ResourceDependency>>::new();

    for descriptor in &manifest.resources {
        validate_resource_id(&descriptor.resource_id)
            .map_err(|message| invalid(&descriptor.path, message))?;
        let safe_path = safe_path_string(Path::new(&descriptor.path))?;
        if safe_path == "manifest.json" {
            return Err(invalid(
                &descriptor.path,
                "manifest cannot list itself as a resource",
            ));
        }
        if !resource_ids.insert(descriptor.resource_id.clone()) {
            return Err(invalid(&descriptor.path, "duplicate resource_id"));
        }
        if !manifest_paths.insert(safe_path.clone()) {
            return Err(invalid(&descriptor.path, "duplicate resource path"));
        }
        let bytes = files
            .remove(&safe_path)
            .ok_or_else(|| invalid(&safe_path, "listed resource is missing"))?;
        if bytes.len() as u64 != descriptor.size_bytes {
            return Err(invalid(
                &safe_path,
                "manifest size does not match resource bytes",
            ));
        }
        let actual_id = sha256_id(&bytes);
        if actual_id != descriptor.resource_id {
            return Err(invalid(
                &safe_path,
                "manifest SHA-256 does not match resource bytes",
            ));
        }
        let probe: ResourceProbe =
            serde_json::from_slice(&bytes).map_err(|source| PackageError::ResourceJson {
                path: safe_path.clone(),
                source,
            })?;
        if !probe.payload.is_object() {
            return Err(invalid(&safe_path, "resource payload must be an object"));
        }
        if probe.schema != descriptor.schema || probe.kind != descriptor.kind {
            return Err(invalid(
                &safe_path,
                "manifest schema/kind does not match resource",
            ));
        }
        validate_subject(&safe_path, &probe.subject)?;
        if probe.subject.media_fingerprint != manifest.content_document.media_fingerprint {
            return Err(invalid(
                &safe_path,
                "resource media subject differs from manifest",
            ));
        }
        graph.insert(
            descriptor.resource_id.clone(),
            probe
                .dependencies
                .iter()
                .map(|dependency| dependency.resource_id.clone())
                .collect(),
        );
        typed_edges.insert(descriptor.resource_id.clone(), probe.dependencies.clone());

        match parse_known_resource(descriptor, &bytes, &safe_path)? {
            Some(resource) => known.push(ResourceRecord {
                descriptor: descriptor.clone(),
                resource,
                bytes,
            }),
            None if descriptor.required => {
                return Err(invalid(
                    &safe_path,
                    "required resource kind/schema is unsupported",
                ));
            }
            None => opaque.push(OpaqueResource {
                descriptor: descriptor.clone(),
                subject: probe.subject,
                dependencies: probe.dependencies,
                bytes,
            }),
        }
    }

    if let Some(path) = files.keys().next() {
        return Err(invalid(path, "file is not declared by the manifest"));
    }
    validate_dependency_graph(&graph)?;
    let manifest_kinds = manifest
        .resources
        .iter()
        .map(|entry| (entry.resource_id.as_str(), entry.kind.as_str()))
        .collect::<HashMap<_, _>>();
    for (source, dependencies) in typed_edges {
        for dependency in dependencies {
            if manifest_kinds
                .get(dependency.resource_id.as_str())
                .is_some_and(|kind| **kind != dependency.kind)
            {
                return Err(invalid(
                    source,
                    "dependency kind differs from the referenced manifest entry",
                ));
            }
        }
    }

    let all_resources = known
        .iter()
        .map(|record| (record.descriptor.resource_id.clone(), &record.resource))
        .collect::<HashMap<_, _>>();
    for record in &known {
        validate_known_resource(
            &record.descriptor.resource_id,
            &record.resource,
            &all_resources,
            manifest.content_document.duration_ms,
        )?;
    }

    let total_bytes = manifest_bytes.len() as u64
        + known
            .iter()
            .map(|value| value.bytes.len() as u64)
            .sum::<u64>()
        + opaque
            .iter()
            .map(|value| value.bytes.len() as u64)
            .sum::<u64>();
    Ok(PackageInspection {
        package: ValidatedPackage {
            manifest,
            manifest_sha256: sha256_id(&manifest_bytes),
            resources: known,
            opaque_resources: opaque,
            total_bytes,
        },
        warnings: Vec::new(),
    })
}

fn parse_known_resource(
    descriptor: &ResourceManifestEntry,
    bytes: &[u8],
    path: &str,
) -> Result<Option<KnownResource>, PackageError> {
    macro_rules! parse {
        ($variant:ident, $payload:ty) => {{
            let value =
                serde_json::from_slice::<ResourceEnvelope<$payload>>(bytes).map_err(|source| {
                    PackageError::ResourceJson {
                        path: path.to_owned(),
                        source,
                    }
                })?;
            Some(KnownResource::$variant(value))
        }};
    }
    let value = match (descriptor.kind.as_str(), descriptor.schema.as_str()) {
        ("subtitle_text_track", SUBTITLE_TEXT_TRACK_SCHEMA_V1) => {
            parse!(SubtitleTextTrack, SubtitleTextTrack)
        }
        ("word_timeline", WORD_TIMELINE_SCHEMA_V1) => parse!(WordTimeline, WordTimeline),
        ("phone_timeline", PHONE_TIMELINE_SCHEMA_V1) => parse!(PhoneTimeline, PhoneTimeline),
        ("sense_group_analysis", SENSE_GROUP_ANALYSIS_SCHEMA_V1) => {
            parse!(SenseGroupAnalysis, SenseGroupAnalysis)
        }
        ("word_acoustics", WORD_ACOUSTICS_SCHEMA_V1) => {
            parse!(WordAcoustics, WordAcoustics)
        }
        ("prosody_analysis", PROSODY_ANALYSIS_SCHEMA_V1) => {
            parse!(ProsodyAnalysis, ProsodyAnalysis)
        }
        _ => None,
    };
    if let Some(resource) = &value
        && (resource.kind() != descriptor.kind || resource.schema() != descriptor.schema)
    {
        return Err(invalid(path, "typed resource schema/kind mismatch"));
    }
    Ok(value)
}

pub(crate) fn validate_dependency_graph(
    graph: &HashMap<String, Vec<String>>,
) -> Result<(), PackageError> {
    for (resource_id, dependencies) in graph {
        let mut unique = HashSet::new();
        for dependency in dependencies {
            validate_resource_id(dependency).map_err(|message| invalid(resource_id, message))?;
            if !unique.insert(dependency) {
                return Err(invalid(resource_id, "resource dependency is duplicated"));
            }
            if !graph.contains_key(dependency) {
                return Err(invalid(
                    resource_id,
                    "resource dependency is not in the package",
                ));
            }
        }
    }
    fn visit<'a>(
        id: &'a str,
        graph: &'a HashMap<String, Vec<String>>,
        visiting: &mut HashSet<&'a str>,
        visited: &mut HashSet<&'a str>,
    ) -> bool {
        if visited.contains(id) {
            return false;
        }
        if !visiting.insert(id) {
            return true;
        }
        if graph[id]
            .iter()
            .any(|next| visit(next, graph, visiting, visited))
        {
            return true;
        }
        visiting.remove(id);
        visited.insert(id);
        false
    }
    let mut visiting = HashSet::new();
    let mut visited = HashSet::new();
    for id in graph.keys() {
        if visit(id, graph, &mut visiting, &mut visited) {
            return Err(invalid(id, "resource dependency graph contains a cycle"));
        }
    }
    Ok(())
}

fn validate_known_resource(
    id: &str,
    resource: &KnownResource,
    resources: &HashMap<String, &KnownResource>,
    media_duration_ms: u64,
) -> Result<(), PackageError> {
    validate_confidence(id, resource.quality().confidence, "quality confidence")?;
    let provenance = resource.provenance();
    if provenance.tool.id.trim().is_empty()
        || provenance.tool.version.trim().is_empty()
        || provenance
            .provider
            .as_ref()
            .is_some_and(|value| value.id.trim().is_empty() || value.version.trim().is_empty())
        || provenance
            .model
            .as_ref()
            .is_some_and(|value| value.id.trim().is_empty() || value.version.trim().is_empty())
    {
        return Err(invalid(
            id,
            "provenance producer identities must not be empty",
        ));
    }
    if let Some(digest) = &provenance.config_sha256 {
        validate_resource_id(digest).map_err(|message| invalid(id, message))?;
    }
    if resource
        .quality()
        .warnings
        .iter()
        .any(|warning| warning.trim().is_empty())
    {
        return Err(invalid(id, "quality warnings must not be empty"));
    }
    for dependency in resource.dependencies() {
        if dependency.resource_id == id {
            return Err(invalid(id, "resource cannot depend on itself"));
        }
    }
    validate_dependency_shape(id, resource)?;
    match resource {
        KnownResource::SubtitleTextTrack(value) => {
            validate_subtitle(id, &value.payload, media_duration_ms)
        }
        KnownResource::WordTimeline(value) => {
            require_direct_anchor_kind(id, resource, resources, "subtitle_text_track")?;
            let transcript = anchored_transcript(id, resource, resources)?;
            if value.payload.words.is_empty() {
                return Err(invalid(id, "word timeline must not be empty"));
            }
            let mut previous_reference = None;
            let mut previous_time = None;
            let mut word_refs = HashSet::new();
            for timing in &value.payload.words {
                validate_time(id, timing.start_ms, timing.end_ms)?;
                validate_within_media(id, timing.end_ms, media_duration_ms)?;
                validate_confidence(id, timing.confidence, "word timing confidence")?;
                let sentence = sentence(id, transcript, &timing.sentence_id)?;
                validate_word_token(id, sentence, timing.token_index)?;
                if timing.start_ms < sentence.start_ms || timing.end_ms > sentence.end_ms {
                    return Err(invalid(id, "word timing is outside its subtitle sentence"));
                }
                let reference_order = (sentence.index, timing.token_index);
                let time_order = (timing.start_ms, timing.end_ms);
                if previous_reference.is_some_and(|previous| previous >= reference_order)
                    || previous_time.is_some_and(|previous| previous > time_order)
                    || !word_refs.insert((timing.sentence_id.as_str(), timing.token_index))
                {
                    return Err(invalid(
                        id,
                        "word timings are not monotonic in presentation order",
                    ));
                }
                previous_reference = Some(reference_order);
                previous_time = Some(time_order);
            }
            Ok(())
        }
        KnownResource::PhoneTimeline(value) => {
            require_direct_anchor_kind(id, resource, resources, "word_timeline")?;
            let transcript = anchored_transcript(id, resource, resources)?;
            let word_timeline = direct_word_timeline(id, resource, resources)?;
            if value.payload.phone_set.trim().is_empty() {
                return Err(invalid(id, "phone_set must not be empty"));
            }
            if value.payload.phones.is_empty() {
                return Err(invalid(id, "phone timeline must not be empty"));
            }
            let mut previous_time = None;
            for phone in &value.payload.phones {
                validate_time(id, phone.start_ms, phone.end_ms)?;
                validate_within_media(id, phone.end_ms, media_duration_ms)?;
                validate_confidence(id, phone.confidence, "phone confidence")?;
                if phone.symbol.trim().is_empty() {
                    return Err(invalid(id, "phone symbol must not be empty"));
                }
                if phone
                    .display_ipa
                    .as_deref()
                    .is_some_and(|value| value.trim().is_empty())
                {
                    return Err(invalid(id, "display_ipa must not be empty"));
                }
                let time_order = (phone.start_ms, phone.end_ms);
                if previous_time.is_some_and(|previous| previous > time_order) {
                    return Err(invalid(id, "phone timings are not monotonic"));
                }
                previous_time = Some(time_order);
                if let Some(word_ref) = &phone.word_ref {
                    let sentence = sentence(id, transcript, &word_ref.sentence_id)?;
                    validate_word_token(id, sentence, word_ref.token_index)?;
                    validate_timeline_word_ref(id, word_timeline, word_ref)?;
                    if phone.start_ms < sentence.start_ms || phone.end_ms > sentence.end_ms {
                        return Err(invalid(id, "phone timing is outside its subtitle sentence"));
                    }
                }
            }
            Ok(())
        }
        KnownResource::SenseGroupAnalysis(value) => {
            require_direct_anchor_kind(id, resource, resources, "subtitle_text_track")?;
            let transcript = anchored_transcript(id, resource, resources)?;
            if value.payload.groups.is_empty() {
                return Err(invalid(id, "sense group analysis must not be empty"));
            }
            let mut indexes_by_sentence = HashMap::<&str, u32>::new();
            let mut end_by_sentence = HashMap::<&str, u32>::new();
            for group in &value.payload.groups {
                validate_confidence(id, Some(group.confidence), "sense group confidence")?;
                validate_token_span(
                    id,
                    transcript,
                    &group.sentence_id,
                    group.start_token_index,
                    group.end_token_index_exclusive,
                )?;
                if let Some(head) = group.head_token_index
                    && (head < group.start_token_index || head >= group.end_token_index_exclusive)
                {
                    return Err(invalid(id, "sense group head is outside its token span"));
                }
                let expected = indexes_by_sentence.entry(&group.sentence_id).or_default();
                if group.group_index != *expected
                    || end_by_sentence
                        .get(group.sentence_id.as_str())
                        .is_some_and(|end| group.start_token_index < *end)
                    || group.sources.is_empty()
                {
                    return Err(invalid(
                        id,
                        "sense groups are not a valid ordered partition",
                    ));
                }
                *expected += 1;
                end_by_sentence.insert(&group.sentence_id, group.end_token_index_exclusive);
            }
            Ok(())
        }
        KnownResource::WordAcoustics(value) => {
            require_direct_anchor_kind(id, resource, resources, "word_timeline")?;
            let transcript = anchored_transcript(id, resource, resources)?;
            let word_timeline = direct_word_timeline(id, resource, resources)?;
            if value.payload.sample_rate_hz == 0 {
                return Err(invalid(id, "sample_rate_hz must be positive"));
            }
            if value.payload.measurements.is_empty() {
                return Err(invalid(id, "word acoustics must not be empty"));
            }
            for measurement in &value.payload.measurements {
                validate_word_anchor(id, transcript, &measurement.word_ref)?;
                validate_timeline_word_ref(id, word_timeline, &measurement.word_ref)?;
                if measurement.duration.duration_ms == 0 {
                    return Err(invalid(id, "acoustic duration must be positive"));
                }
                validate_confidence(id, measurement.energy.prominence, "energy prominence")?;
                validate_confidence(id, measurement.pitch.prominence, "pitch prominence")?;
                validate_confidence(id, measurement.pitch.reset_after, "pitch reset")?;
                validate_confidence(id, measurement.voiced_frame_ratio, "voiced frame ratio")?;
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
                        return Err(invalid(id, format!("{label} must be finite")));
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
                        return Err(invalid(id, format!("{label} must be positive")));
                    }
                }
                if measurement
                    .pitch
                    .range_semitones
                    .is_some_and(|number| number < 0.0)
                {
                    return Err(invalid(id, "range_semitones must be non-negative"));
                }
            }
            Ok(())
        }
        KnownResource::ProsodyAnalysis(value) => {
            require_direct_anchor_kind(id, resource, resources, "word_timeline")?;
            require_direct_anchor_kind(id, resource, resources, "word_acoustics")?;
            let transcript = anchored_transcript(id, resource, resources)?;
            let word_timeline = direct_word_timeline(id, resource, resources)?;
            for anchor in &value.payload.anchors {
                validate_confidence(id, Some(anchor.confidence), "prosody confidence")?;
                validate_confidence(id, Some(anchor.realized_prominence), "realized prominence")?;
                validate_word_anchor(id, transcript, &anchor.word_ref)?;
                validate_timeline_word_ref(id, word_timeline, &anchor.word_ref)?;
                if anchor.evidence.is_empty() {
                    return Err(invalid(id, "prosody evidence must not be empty"));
                }
                let unique = anchor.evidence.iter().collect::<HashSet<_>>();
                if unique.len() != anchor.evidence.len() {
                    return Err(invalid(id, "prosody evidence must be unique"));
                }
            }
            Ok(())
        }
    }
}

fn validate_dependency_shape(id: &str, resource: &KnownResource) -> Result<(), PackageError> {
    let expected: &[(&str, usize, usize)] = match resource {
        KnownResource::SubtitleTextTrack(_) => &[],
        KnownResource::WordTimeline(_) => &[("subtitle_text_track", 1, 1)],
        KnownResource::PhoneTimeline(_) => &[("word_timeline", 1, 1)],
        KnownResource::SenseGroupAnalysis(_) => &[("subtitle_text_track", 1, 1)],
        KnownResource::WordAcoustics(_) => &[("word_timeline", 1, 1)],
        KnownResource::ProsodyAnalysis(_) => &[
            ("word_timeline", 1, 1),
            ("word_acoustics", 1, 1),
            ("sense_group_analysis", 0, 1),
        ],
    };
    if expected.is_empty() {
        if resource.dependencies().is_empty() {
            return Ok(());
        }
        return Err(invalid(id, "subtitle text track cannot have dependencies"));
    }
    if resource
        .dependencies()
        .iter()
        .any(|dependency| !expected.iter().any(|(kind, _, _)| *kind == dependency.kind))
    {
        return Err(invalid(id, "resource has an unsupported dependency kind"));
    }
    for (kind, minimum, maximum) in expected {
        let count = resource
            .dependencies()
            .iter()
            .filter(|dependency| dependency.kind == *kind)
            .count();
        if count < *minimum || count > *maximum {
            return Err(invalid(
                id,
                format!("resource dependency count for {kind} is invalid"),
            ));
        }
    }
    Ok(())
}

fn validate_subtitle(
    id: &str,
    track: &SubtitleTextTrack,
    media_duration_ms: u64,
) -> Result<(), PackageError> {
    if track.language.trim().is_empty() {
        return Err(invalid(id, "subtitle language must not be empty"));
    }
    let mut segment_ids = HashSet::new();
    let mut indexes = BTreeSet::new();
    if track.sentences.is_empty() {
        return Err(invalid(id, "subtitle must contain at least one sentence"));
    }
    for (expected_index, sentence) in track.sentences.iter().enumerate() {
        validate_time(id, sentence.start_ms, sentence.end_ms)?;
        validate_within_media(id, sentence.end_ms, media_duration_ms)?;
        if sentence.id.trim().is_empty() || !segment_ids.insert(&sentence.id) {
            return Err(invalid(id, "segment ids must be non-empty and unique"));
        }
        if !indexes.insert(sentence.index) || sentence.index as usize != expected_index {
            return Err(invalid(id, "segment indexes must be unique"));
        }
        let mut token_indexes = HashSet::new();
        let character_count = sentence.original_text.chars().count();
        let mut previous_char_end = 0_u32;
        for (expected_token_index, token) in sentence.tokens.iter().enumerate() {
            if token.text.is_empty()
                || token.start_char >= token.end_char
                || token.end_char as usize > character_count
            {
                return Err(invalid(
                    id,
                    "token text and half-open character range are invalid",
                ));
            }
            if !token_indexes.insert(token.index)
                || token.index as usize != expected_token_index
                || token.start_char != previous_char_end
            {
                return Err(invalid(id, "token indexes must be unique within a segment"));
            }
            let actual = sentence
                .original_text
                .chars()
                .skip(token.start_char as usize)
                .take((token.end_char - token.start_char) as usize)
                .collect::<String>();
            if actual != token.text {
                return Err(invalid(id, "token text differs from its character span"));
            }
            previous_char_end = token.end_char;
        }
        if !sentence.tokens.is_empty() && previous_char_end as usize != character_count {
            return Err(invalid(
                id,
                "subtitle tokens do not cover the original text",
            ));
        }
    }
    Ok(())
}

fn require_direct_anchor_kind(
    id: &str,
    resource: &KnownResource,
    resources: &HashMap<String, &KnownResource>,
    expected: &str,
) -> Result<(), PackageError> {
    let matches = resource
        .dependencies()
        .iter()
        .filter(|dependency| dependency.kind == expected)
        .filter_map(|dependency| resources.get(&dependency.resource_id))
        .filter(|dependency| dependency.kind() == expected)
        .count();
    if matches == 1 {
        Ok(())
    } else {
        Err(invalid(
            id,
            format!(
                "resource must have exactly one direct anchor of kind {}",
                expected
            ),
        ))
    }
}

fn anchored_transcript<'a>(
    id: &str,
    resource: &KnownResource,
    resources: &'a HashMap<String, &KnownResource>,
) -> Result<&'a SubtitleTextTrack, PackageError> {
    let mut found = Vec::new();
    let mut pending = resource
        .dependencies()
        .iter()
        .map(|dependency| dependency.resource_id.as_str())
        .collect::<Vec<_>>();
    let mut seen = HashSet::new();
    while let Some(next) = pending.pop() {
        if !seen.insert(next) {
            continue;
        }
        let Some(dependency) = resources.get(next) else {
            // Opaque dependencies are graph-valid but cannot establish typed anchors.
            continue;
        };
        match dependency {
            KnownResource::SubtitleTextTrack(value) => found.push(&value.payload),
            other => pending.extend(
                other
                    .dependencies()
                    .iter()
                    .map(|dependency| dependency.resource_id.as_str()),
            ),
        }
    }
    found.dedup_by(|left, right| std::ptr::eq(*left, *right));
    if found.len() != 1 {
        return Err(invalid(
            id,
            "resource must resolve exactly one subtitle anchor",
        ));
    }
    Ok(found[0])
}

fn direct_word_timeline<'a>(
    id: &str,
    resource: &KnownResource,
    resources: &'a HashMap<String, &KnownResource>,
) -> Result<&'a WordTimeline, PackageError> {
    let dependency = resource
        .dependencies()
        .iter()
        .find(|dependency| dependency.kind == "word_timeline")
        .ok_or_else(|| invalid(id, "resource has no word timeline dependency"))?;
    match resources.get(&dependency.resource_id) {
        Some(KnownResource::WordTimeline(value)) => Ok(&value.payload),
        _ => Err(invalid(id, "word timeline dependency is not supported")),
    }
}

fn validate_timeline_word_ref(
    id: &str,
    timeline: &WordTimeline,
    word_ref: &TokenRef,
) -> Result<(), PackageError> {
    if timeline.words.iter().any(|word| {
        word.sentence_id == word_ref.sentence_id && word.token_index == word_ref.token_index
    }) {
        Ok(())
    } else {
        Err(invalid(
            id,
            "word reference is absent from the depended-on word timeline",
        ))
    }
}

fn validate_token_span(
    id: &str,
    transcript: &SubtitleTextTrack,
    segment_id: &str,
    start: u32,
    end_exclusive: u32,
) -> Result<(), PackageError> {
    if start >= end_exclusive {
        return Err(invalid(id, "token span must be non-empty and half-open"));
    }
    let sentence = sentence(id, transcript, segment_id)?;
    validate_token(id, sentence, start)?;
    if end_exclusive as usize > sentence.tokens.len() {
        return Err(invalid(id, "token span exceeds its subtitle sentence"));
    }
    Ok(())
}

fn validate_word_anchor(
    id: &str,
    transcript: &SubtitleTextTrack,
    word_ref: &TokenRef,
) -> Result<(), PackageError> {
    let sentence = sentence(id, transcript, &word_ref.sentence_id)?;
    validate_word_token(id, sentence, word_ref.token_index)
}

fn sentence<'a>(
    id: &str,
    transcript: &'a SubtitleTextTrack,
    sentence_id: &str,
) -> Result<&'a SubtitleSentence, PackageError> {
    transcript
        .sentences
        .iter()
        .find(|sentence| sentence.id == sentence_id)
        .ok_or_else(|| invalid(id, "resource references an unknown subtitle sentence"))
}

fn validate_token(
    id: &str,
    sentence: &SubtitleSentence,
    token_index: u32,
) -> Result<(), PackageError> {
    if sentence
        .tokens
        .iter()
        .any(|token| token.index == token_index)
    {
        Ok(())
    } else {
        Err(invalid(id, "resource references an unknown subtitle token"))
    }
}

fn validate_word_token(
    id: &str,
    sentence: &SubtitleSentence,
    token_index: u32,
) -> Result<(), PackageError> {
    let token = sentence
        .tokens
        .iter()
        .find(|token| token.index == token_index)
        .ok_or_else(|| invalid(id, "resource references an unknown subtitle token"))?;
    if token.kind != TokenKind::Word {
        return Err(invalid(id, "word reference does not identify a word token"));
    }
    Ok(())
}

fn validate_time(id: &str, start_ms: u64, end_ms: u64) -> Result<(), PackageError> {
    if start_ms >= end_ms {
        Err(invalid(id, "time range must be non-empty and half-open"))
    } else {
        Ok(())
    }
}

fn validate_within_media(
    id: &str,
    end_ms: u64,
    media_duration_ms: u64,
) -> Result<(), PackageError> {
    if end_ms > media_duration_ms {
        Err(invalid(id, "time range exceeds media duration"))
    } else {
        Ok(())
    }
}

fn validate_confidence(id: &str, value: Option<f64>, label: &str) -> Result<(), PackageError> {
    if value.is_some_and(|number| !number.is_finite() || !(0.0..=1.0).contains(&number)) {
        Err(invalid(id, format!("{label} must be within 0..=1")))
    } else {
        Ok(())
    }
}

fn validate_subject(path: &str, subject: &ResourceSubject) -> Result<(), PackageError> {
    validate_media_fingerprint(path, &subject.media_fingerprint)
}

fn validate_media_fingerprint(path: &str, value: &str) -> Result<(), PackageError> {
    validate_resource_id(value).map_err(|message| invalid(path, message))
}

fn validate_resource_id(value: &str) -> Result<(), &'static str> {
    let Some(hex_value) = value.strip_prefix("sha256:") else {
        return Err("resource_id must start with sha256:");
    };
    if hex_value.len() != 64
        || !hex_value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err("resource_id must contain a SHA-256 hex digest");
    }
    Ok(())
}

fn sha256_id(bytes: &[u8]) -> String {
    format!("sha256:{}", hex::encode(Sha256::digest(bytes)))
}

fn invalid(path: impl Into<String>, message: impl Into<String>) -> PackageError {
    PackageError::Invalid {
        path: path.into(),
        message: message.into(),
    }
}
