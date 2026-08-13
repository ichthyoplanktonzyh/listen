//! Structural payload validation for Content Package v3.
//!
//! The shared v2 payload families reuse the v2 validators verbatim; the v3
//! structured reading and anchor-to-time alignment payloads own their rules
//! here, mirroring the domain invariants: stable unique anchors, known
//! block/span references, acyclic block hierarchies, exact in-release
//! rendition locators, and unique monotonic alignments.

use std::collections::{HashMap, HashSet};

use crate::v2::validate::{
    validate_half_open, validate_language_tag, validate_phone_timeline, validate_prosody_analysis,
    validate_sense_group_analysis, validate_subtitle_text_track, validate_timed_text_track,
    validate_word_acoustics, validate_word_timeline,
};

use crate::v2::ResourceRole;

use super::model::PackageReleaseV3;
use super::payload::{
    AnchorTimeAlignment, KnownPayloadV3, ReadingBlock, ReadingBlockKind, StructuredReading,
};

/// Validates one known payload of `resource` against locally checkable
/// in-release references.
pub(crate) fn validate_payload(
    release: &PackageReleaseV3,
    resource_id: &str,
    kind: &str,
    payload: &KnownPayloadV3,
    decoded: &HashMap<String, KnownPayloadV3>,
    warnings: &mut Vec<String>,
) -> Result<(), String> {
    let subtitle = anchored_payload(release, resource_id, decoded, |payload| match payload {
        KnownPayloadV3::SubtitleTextTrack(track) => Some(track),
        _ => None,
    });
    let timeline = anchored_payload(release, resource_id, decoded, |payload| match payload {
        KnownPayloadV3::WordTimeline(track) => Some(track),
        _ => None,
    });
    match payload {
        KnownPayloadV3::TimedTextTrack(value) => validate_timed_text_track(value),
        KnownPayloadV3::Translation(value) => {
            validate_translation(release, resource_id, kind, decoded, value, warnings)
        }
        KnownPayloadV3::SubtitleTextTrack(value) => validate_subtitle_text_track(value),
        KnownPayloadV3::WordTimeline(value) => validate_word_timeline(value, subtitle),
        KnownPayloadV3::PhoneTimeline(value) => validate_phone_timeline(value, subtitle, timeline),
        KnownPayloadV3::SenseGroupAnalysis(value) => validate_sense_group_analysis(value, subtitle),
        KnownPayloadV3::WordAcoustics(value) => validate_word_acoustics(value, subtitle, timeline),
        KnownPayloadV3::ProsodyAnalysis(value) => {
            validate_prosody_analysis(value, subtitle, timeline)
        }
        KnownPayloadV3::StructuredReading(value) => validate_structured_reading(release, value),
        KnownPayloadV3::AnchorTimeAlignment(value) => {
            validate_anchor_time_alignment(release, value, decoded, warnings)
        }
    }
}

/// A `translation` v1 assistance payload: anchored to an exact Structured
/// Reading Base Resource with an explicit support language. Phase 1 semantic
/// production consumes Structured Reading; a translation never re-parses raw
/// document bytes.
fn validate_translation(
    release: &PackageReleaseV3,
    resource_id: &str,
    kind: &str,
    decoded: &HashMap<String, KnownPayloadV3>,
    payload: &crate::v2::Translation,
    warnings: &mut Vec<String>,
) -> Result<(), String> {
    if kind != "translation" {
        return Err("translation resource kind must be translation".to_owned());
    }
    validate_language_tag(&payload.support_language)?;
    let descriptor = release
        .resources
        .iter()
        .find(|resource| resource.resource_id == resource_id)
        .ok_or_else(|| "translation resource is not declared".to_owned())?;
    if descriptor.descriptor.role != ResourceRole::Assistance {
        return Err("translation resource must have assistance role".to_owned());
    }
    if !descriptor
        .descriptor
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
    if base.descriptor.role != ResourceRole::Base {
        return Err("translation base_resource_id must reference a Base Resource".to_owned());
    }
    if base.descriptor.kind != "structured_reading" {
        return Err(
            "translation base_resource_id must reference a structured_reading resource".to_owned(),
        );
    }
    if !descriptor
        .descriptor
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
    // Validate source segment references against the base Structured Reading
    // payload when it is embedded and known; otherwise warn instead of
    // assuming. A source segment must reference a sentence anchor.
    match decoded.get(&payload.base_resource_id) {
        Some(KnownPayloadV3::StructuredReading(base_payload)) => {
            let sentence_anchors: Vec<&str> = base_payload
                .anchors
                .iter()
                .filter(|anchor| anchor.kind == super::payload::AnchorKind::Sentence)
                .map(|anchor| anchor.anchor_id.as_str())
                .collect();
            validate_translation_segment_refs(payload, &sentence_anchors)
        }
        Some(_) => Err("translation base resource payload kind is unsupported".to_owned()),
        None => {
            warnings.push(format!(
                "{resource_id}: translation base payload is absent; source segments not verified"
            ));
            Ok(())
        }
    }
}

fn validate_translation_segment_refs(
    payload: &crate::v2::Translation,
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

/// A `structured_reading` v1 Base Resource: self-contained exact UTF-8
/// logical text, ordered hierarchy, blocks/spans, language metadata, stable
/// anchors, and optional mappings into exact Document Rendition Locators.
/// Every anchor range is a half-open byte window into the exact `text` bytes:
/// it must stay in bounds, land on character boundaries, and appear in
/// monotonic order.
fn validate_structured_reading(
    release: &PackageReleaseV3,
    payload: &StructuredReading,
) -> Result<(), String> {
    validate_language_tag(&payload.language)?;
    if payload.text.is_empty() {
        return Err("structured_reading text must not be empty".to_owned());
    }
    if payload.anchors.is_empty() {
        return Err("structured_reading must declare at least one anchor".to_owned());
    }
    let text_len = payload.text.len() as u64;
    let in_bounds =
        |offset: u64| offset <= text_len && payload.text.is_char_boundary(offset as usize);
    let mut anchor_ids = HashSet::new();
    let mut previous_start: Option<u64> = None;
    let mut previous_end: Option<u64> = None;
    for anchor in &payload.anchors {
        if anchor.anchor_id.trim().is_empty() {
            return Err("anchor ids must not be empty".to_owned());
        }
        if !anchor_ids.insert(anchor.anchor_id.as_str()) {
            return Err(format!("duplicate anchor id {}", anchor.anchor_id));
        }
        validate_half_open(anchor.start_offset, anchor.end_offset, "anchor range")?;
        if !in_bounds(anchor.start_offset) || !in_bounds(anchor.end_offset) {
            return Err(format!(
                "anchor {} range exceeds the text bytes or splits a character",
                anchor.anchor_id
            ));
        }
        // Monotonic order: anchors are declared in non-decreasing
        // (start, end) byte order; backwards anchors are invalid.
        if previous_start.is_some_and(|start| anchor.start_offset < start)
            || (previous_start == Some(anchor.start_offset)
                && previous_end.is_some_and(|end| anchor.end_offset < end))
        {
            return Err("anchor ranges must be in monotonic byte order".to_owned());
        }
        previous_start = Some(anchor.start_offset);
        previous_end = Some(anchor.end_offset);
    }
    let anchor_known = |anchor_id: &str| anchor_ids.contains(anchor_id);
    for span in &payload.spans {
        if span.span_id.trim().is_empty() {
            return Err("span ids must not be empty".to_owned());
        }
        if !anchor_known(&span.anchor_id) {
            return Err(format!("span references unknown anchor {}", span.anchor_id));
        }
        if span
            .parent_anchor_id
            .as_deref()
            .is_some_and(|parent| !anchor_known(parent))
        {
            return Err(format!(
                "span references unknown parent anchor {}",
                span.parent_anchor_id.as_deref().expect("checked above")
            ));
        }
    }
    validate_block_hierarchy(payload)?;
    for mapping in &payload.document_mappings {
        if !anchor_known(&mapping.anchor_id) {
            return Err(format!(
                "document mapping references unknown anchor {}",
                mapping.anchor_id
            ));
        }
        if mapping.locator.value.trim().is_empty() {
            return Err("document mapping locator value must not be empty".to_owned());
        }
        if !release
            .document_renditions
            .iter()
            .any(|rendition| rendition.rendition_id == mapping.rendition_id)
        {
            return Err(format!(
                "document mapping references undeclared rendition {}",
                mapping.rendition_id
            ));
        }
    }
    Ok(())
}

/// Block hierarchy rules: one `root` block with no parent; every other block
/// has a valid parent; `order` is 0-based and contiguous within each parent;
/// references are acyclic. Block kinds are constrained by the payload enum.
fn validate_block_hierarchy(payload: &StructuredReading) -> Result<(), String> {
    let block_known = |block_id: &str| {
        payload
            .blocks
            .iter()
            .any(|block| block.block_id == block_id)
    };
    let mut roots = 0_usize;
    let mut seen_ids = HashSet::new();
    for block in &payload.blocks {
        if block.block_id.trim().is_empty() {
            return Err("block ids must not be empty".to_owned());
        }
        if !seen_ids.insert(&block.block_id) {
            return Err(format!("duplicate block id {}", block.block_id));
        }
        if block.kind == ReadingBlockKind::Root {
            roots += 1;
            if block.parent_block_id.is_some() {
                return Err("root block must not declare a parent block".to_owned());
            }
        }
        if block.span_anchor_ids.is_empty() {
            return Err(format!(
                "block {} must reference at least one anchor",
                block.block_id
            ));
        }
        let mut seen_anchors = HashSet::new();
        for span_anchor in &block.span_anchor_ids {
            if !payload
                .anchors
                .iter()
                .any(|anchor| anchor.anchor_id == *span_anchor)
            {
                return Err(format!(
                    "block {} references unknown anchor {span_anchor}",
                    block.block_id
                ));
            }
            if !seen_anchors.insert(span_anchor) {
                return Err(format!(
                    "block {} references anchor {span_anchor} more than once",
                    block.block_id
                ));
            }
        }
    }
    if roots != 1 {
        return Err(format!(
            "block hierarchy must declare exactly one root block (found {roots})"
        ));
    }
    for block in &payload.blocks {
        if block.kind == ReadingBlockKind::Root {
            continue;
        }
        let parent = block
            .parent_block_id
            .as_deref()
            .ok_or_else(|| format!("block {} must declare a parent block", block.block_id))?;
        if !block_known(parent) {
            return Err(format!(
                "block {} references unknown parent block {}",
                block.block_id, parent
            ));
        }
        if parent == block.block_id {
            return Err(format!("block {} cannot be its own parent", block.block_id));
        }
    }
    if block_hierarchy_has_cycle(&payload.blocks) {
        return Err("block hierarchy contains a cycle".to_owned());
    }
    // Contiguous 0-based order within every parent group.
    for block in &payload.blocks {
        let key = block
            .parent_block_id
            .clone()
            .unwrap_or_else(|| block.block_id.clone());
        let mut orders: Vec<u32> = payload
            .blocks
            .iter()
            .filter(|candidate| {
                candidate.parent_block_id.as_deref() == block.parent_block_id.as_deref()
                    && candidate.block_id != block.block_id
            })
            .map(|candidate| candidate.order)
            .collect();
        orders.push(block.order);
        let mut expected: Vec<u32> = (0..orders.len() as u32).collect();
        orders.sort_unstable();
        expected.sort_unstable();
        if orders != expected {
            return Err(format!(
                "block {} sibling orders are not contiguous 0-based values",
                key
            ));
        }
    }
    Ok(())
}

/// Whether the block parent links form a cycle. Bounded: blocks were limited
/// by the enforced inventory budget and each node is visited once.
fn block_hierarchy_has_cycle(blocks: &[ReadingBlock]) -> bool {
    fn reachable(from: &str, blocks: &[ReadingBlock], visited: &mut Vec<String>) -> bool {
        for block in blocks {
            if block.block_id != from {
                continue;
            }
            let Some(parent) = &block.parent_block_id else {
                continue;
            };
            if visited.contains(parent) {
                return true;
            }
            visited.push(parent.clone());
            if reachable(parent, blocks, visited) {
                return true;
            }
            visited.pop();
        }
        false
    }
    blocks
        .iter()
        .any(|block| reachable(&block.block_id, blocks, &mut vec![block.block_id.clone()]))
}

/// An `anchor_time_alignment` v1 Base Resource: exact Reading Anchors mapped
/// to exact media-time Rendition Locators. The alignment is meaningful only
/// against the exact Structured Reading Resource and the exact Media
/// Rendition it names.
fn validate_anchor_time_alignment(
    release: &PackageReleaseV3,
    payload: &AnchorTimeAlignment,
    decoded: &HashMap<String, KnownPayloadV3>,
    warnings: &mut Vec<String>,
) -> Result<(), String> {
    let anchor_resource = release
        .resources
        .iter()
        .find(|resource| resource.resource_id == payload.anchor_resource_id)
        .ok_or_else(|| "anchor_time_alignment anchor_resource_id is not declared".to_owned())?;
    if anchor_resource.descriptor.kind != "structured_reading" {
        return Err(
            "anchor_time_alignment anchor_resource_id must reference a structured_reading resource"
                .to_owned(),
        );
    }
    if !release
        .media_renditions
        .iter()
        .any(|rendition| rendition.rendition_id == payload.rendition_id)
    {
        return Err(format!(
            "anchor_time_alignment references undeclared media rendition {}",
            payload.rendition_id
        ));
    }
    if payload.alignments.is_empty() {
        return Err("anchor_time_alignment must declare at least one entry".to_owned());
    }
    let mut seen = HashSet::new();
    let mut previous_time: Option<u64> = None;
    for entry in &payload.alignments {
        if entry.anchor_id.trim().is_empty() || !seen.insert(entry.anchor_id.as_str()) {
            return Err("alignment anchor ids must be non-empty and unique".to_owned());
        }
        if previous_time.is_some_and(|previous| entry.media_time_ms < previous) {
            return Err("alignment media times must be non-decreasing".to_owned());
        }
        previous_time = Some(entry.media_time_ms);
    }
    // When the anchor resource payload is embedded and known, every aligned
    // anchor must exist inside it; a missing base payload only warns.
    match decoded.get(&payload.anchor_resource_id) {
        Some(KnownPayloadV3::StructuredReading(base)) => {
            for entry in &payload.alignments {
                if !base
                    .anchors
                    .iter()
                    .any(|anchor| anchor.anchor_id == entry.anchor_id)
                {
                    return Err(format!(
                        "alignment references unknown anchor {}",
                        entry.anchor_id
                    ));
                }
            }
            Ok(())
        }
        Some(_) => {
            Err("anchor_time_alignment anchor resource payload kind is unsupported".to_owned())
        }
        None => {
            warnings.push(format!(
                "{}: anchor resource payload is absent; anchors not verified",
                payload.anchor_resource_id
            ));
            Ok(())
        }
    }
}

/// The first anchored payload of the expected kind reachable through the
/// descriptor dependency closure. Each resource id is visited once, so the
/// traversal is bounded by the enforced graph inventory.
fn anchored_payload<'a, T>(
    release: &PackageReleaseV3,
    resource_id: &str,
    decoded: &'a HashMap<String, KnownPayloadV3>,
    select: impl Fn(&'a KnownPayloadV3) -> Option<&'a T>,
) -> Option<&'a T> {
    let mut pending: Vec<&str> = release
        .resources
        .iter()
        .find(|resource| resource.resource_id == resource_id)?
        .descriptor
        .dependencies
        .iter()
        .map(|dependency| dependency.resource_id.as_str())
        .collect();
    let mut seen = HashSet::new();
    while let Some(next) = pending.pop() {
        if !seen.insert(next) {
            continue;
        }
        if let Some(payload) = decoded.get(next)
            && let Some(found) = select(payload)
        {
            return Some(found);
        }
        if let Some(dependency) = release
            .resources
            .iter()
            .find(|candidate| candidate.resource_id == next)
        {
            pending.extend(
                dependency
                    .descriptor
                    .dependencies
                    .iter()
                    .map(|item| item.resource_id.as_str()),
            );
        }
    }
    None
}
