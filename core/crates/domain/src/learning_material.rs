//! Durable learner-facing material: Source Assets and typed Document/Media
//! Renditions bundled into revisions of a learning material.
//!
//! This module owns the identity and invariant rules for learning material and
//! deliberately contains no file path, repository, or HTTP concepts. Media
//! renditions snapshot their source kind, fingerprint, and availability only;
//! resolving a rendition to a concrete playable source is a later adapter
//! concern.

use serde::{Deserialize, Serialize};

use crate::{
    DomainError, LearningMaterialId, MaterialRevisionId, MediaId, Rendition, RenditionOrigin,
    SourceAsset, length_prefixed,
};

/// The overall composition shape of a learning material revision.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MaterialShape {
    Text,
    Audio,
    Video,
    Mixed,
}

/// Derives the composition shape from revision renditions: document-only is
/// `Text`; exactly audio renditions is `Audio`; exactly video renditions is
/// `Video`; any combination is `Mixed`. Source Assets alone carry no shape.
pub fn material_shape(revision: &MaterialRevision) -> MaterialShape {
    let mut has_document = false;
    let mut has_audio = false;
    let mut has_video = false;
    for rendition in &revision.renditions {
        match rendition {
            Rendition::Document(_) => has_document = true,
            Rendition::Media(media) => match media.kind {
                crate::MediaKind::Audio => has_audio = true,
                crate::MediaKind::Video => has_video = true,
            },
        }
    }
    match (has_document, has_audio, has_video) {
        (true, false, false) => MaterialShape::Text,
        (false, true, false) => MaterialShape::Audio,
        (false, false, true) => MaterialShape::Video,
        _ => MaterialShape::Mixed,
    }
}

/// One immutable snapshot of a learning material's content.
///
/// Revision identity is content-idempotent: derived from the material id,
/// exact title, and the canonicalized Source Asset and Rendition facts, with
/// no timestamp, so retries at different times converge on the same revision.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MaterialRevision {
    pub id: MaterialRevisionId,
    pub material_id: LearningMaterialId,
    pub title: String,
    pub source_assets: Vec<SourceAsset>,
    pub renditions: Vec<Rendition>,
    pub created_at_ms: u64,
}

impl MaterialRevision {
    /// Rejects a blank title, an empty component set, and duplicate component
    /// ids. Components are canonicalized (sorted by id) so equal content in a
    /// different input order produces the same revision id.
    pub fn new(
        material_id: LearningMaterialId,
        title: impl Into<String>,
        source_assets: Vec<SourceAsset>,
        mut renditions: Vec<Rendition>,
        created_at_ms: u64,
    ) -> Result<Self, DomainError> {
        let title = title.into();
        if title.trim().is_empty() {
            return Err(DomainError::EmptyValue("MaterialRevision.title"));
        }
        if source_assets.is_empty() && renditions.is_empty() {
            return Err(DomainError::EmptyValue("MaterialRevision.components"));
        }
        let mut all_ids: Vec<String> = source_assets
            .iter()
            .map(|asset| asset.id.as_str().to_owned())
            .collect();
        canonicalize_source_assets(&mut all_ids)?;
        sort_renditions(&mut renditions);
        for rendition in &renditions {
            all_ids.push(rendition.id().as_str().to_owned());
        }
        all_ids.sort();
        for pair in all_ids.windows(2) {
            if pair[0] == pair[1] {
                return Err(DomainError::DuplicateAssetId);
            }
        }
        let identity =
            revision_identity_fingerprint(&material_id, &title, &source_assets, &renditions);
        let id = MaterialRevisionId::from_fingerprint("material-revision", &identity);
        Ok(Self {
            id,
            material_id,
            title,
            source_assets,
            renditions,
            created_at_ms,
        })
    }

    /// Composition shape derived from the revision renditions.
    pub fn shape(&self) -> crate::MaterialShape {
        crate::material_shape(self)
    }
}

fn canonicalize_source_assets(ids: &mut [String]) -> Result<(), DomainError> {
    ids.sort();
    for pair in ids.windows(2) {
        if pair[0] == pair[1] {
            return Err(DomainError::DuplicateAssetId);
        }
    }
    Ok(())
}

fn sort_renditions(renditions: &mut [Rendition]) {
    renditions.sort_by(|a, b| a.id().as_str().cmp(b.id().as_str()));
}

/// A durable learner-facing material that advances through revisions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LearningMaterial {
    pub id: LearningMaterialId,
    pub current_revision_id: MaterialRevisionId,
    /// Evidence of explicit retention (e.g. personal library membership).
    /// Null means the material is temporary.
    pub retained_at_ms: Option<u64>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

impl LearningMaterial {
    /// Creates the initial material from its first revision.
    ///
    /// The material identity is deterministic: media-backed materials derive
    /// it from the bound media id so later adapters can converge on existing
    /// media, while other materials derive it from the canonical component
    /// facts (equal content converges). A revision whose `material_id`
    /// diverges from the deterministic identity is rejected. Because this
    /// represents initial creation, the revision must carry the material's own
    /// creation timestamp; `updated_at_ms` must not precede `created_at_ms`;
    /// and retention, when present, must neither precede creation nor
    /// postdate the latest update.
    pub fn new(
        revision: &MaterialRevision,
        retained_at_ms: Option<u64>,
        created_at_ms: u64,
        updated_at_ms: u64,
    ) -> Result<Self, DomainError> {
        if created_at_ms > updated_at_ms {
            return Err(DomainError::InvalidTimestamp(
                "updated_at_ms precedes created_at_ms",
            ));
        }
        if retained_at_ms.is_some_and(|retained| retained < created_at_ms) {
            return Err(DomainError::InvalidTimestamp(
                "retained_at_ms precedes created_at_ms",
            ));
        }
        // Initial creation must carry the revision's own creation timestamp.
        if revision.created_at_ms != created_at_ms {
            return Err(DomainError::InvalidTimestamp(
                "revision.created_at_ms must equal material created_at_ms",
            ));
        }
        // Retention evidence cannot postdate the latest update.
        if retained_at_ms.is_some_and(|retained| retained > updated_at_ms) {
            return Err(DomainError::InvalidTimestamp(
                "retained_at_ms must not be later than updated_at_ms",
            ));
        }
        let id = initial_material_id(&revision.source_assets, &revision.renditions)?;
        if revision.material_id != id {
            return Err(DomainError::MaterialIdentityMismatch);
        }
        Ok(Self {
            id,
            current_revision_id: revision.id.clone(),
            retained_at_ms,
            created_at_ms,
            updated_at_ms,
        })
    }
}

/// Deterministic initial identity for a learning material, derived from its
/// initial components.
///
/// - Empty component set: rejected.
/// - Exactly one Source media rendition: keyed from that media id so adapters
///   can converge on existing media.
/// - Multiple different Source media renditions: ambiguous, rejected.
/// - Otherwise: content-backed, from the canonical component fingerprints
///   (equal content converges).
pub fn initial_material_id(
    source_assets: &[SourceAsset],
    renditions: &[Rendition],
) -> Result<LearningMaterialId, DomainError> {
    if source_assets.is_empty() && renditions.is_empty() {
        return Err(DomainError::EmptyValue("LearningMaterial.components"));
    }
    let media_ids: Vec<&MediaId> = renditions
        .iter()
        .filter_map(|rendition| match rendition {
            Rendition::Media(media)
                if media.origin == RenditionOrigin::Source && media.media_id.is_some() =>
            {
                media.media_id.as_ref()
            }
            _ => None,
        })
        .collect();
    match media_ids.len() {
        0 => {
            let mut keys: Vec<String> = Vec::new();
            for asset in source_assets {
                keys.push(format!(
                    "asset:{}",
                    length_prefixed(&[asset.sha256_digest.as_str()])
                ));
            }
            for rendition in renditions {
                keys.push(format!(
                    "{}:{}",
                    match rendition {
                        Rendition::Document(_) => "document",
                        Rendition::Media(_) => "media",
                    },
                    length_prefixed(&[rendition.id().as_str()])
                ));
            }
            keys.sort();
            let keys: Vec<&str> = keys.iter().map(String::as_str).collect();
            Ok(LearningMaterialId::from_fingerprint(
                "learning-material",
                &length_prefixed(&keys),
            ))
        }
        1 => Ok(LearningMaterialId::from_fingerprint(
            "learning-material",
            &format!("media:{}", media_ids[0].as_str()),
        )),
        _ => Err(DomainError::AmbiguousInitialMediaIdentity),
    }
}

fn revision_identity_fingerprint(
    material_id: &LearningMaterialId,
    title: &str,
    source_assets: &[SourceAsset],
    renditions: &[Rendition],
) -> String {
    let mut asset_keys: Vec<String> = source_assets
        .iter()
        .map(|asset| format!("asset:{}", asset.id.as_str()))
        .collect();
    asset_keys.sort();
    let mut rendition_keys: Vec<String> = renditions
        .iter()
        .map(|rendition| rendition.id().as_str().to_owned())
        .collect();
    rendition_keys.sort();
    let encoded_assets =
        length_prefixed(&asset_keys.iter().map(String::as_str).collect::<Vec<&str>>());
    let encoded_renditions = length_prefixed(
        &rendition_keys
            .iter()
            .map(String::as_str)
            .collect::<Vec<&str>>(),
    );
    length_prefixed(&[
        material_id.as_str(),
        title,
        encoded_assets.as_str(),
        encoded_renditions.as_str(),
    ])
}

#[cfg(test)]
mod tests {
    use sha2::{Digest as _, Sha256};

    use super::*;
    use crate::{
        DocumentRendition, LanguageCode, MaterialShape, MediaAvailability, MediaKind,
        MediaRendition,
    };

    fn language(code: &str) -> LanguageCode {
        LanguageCode::parse(code).expect("valid language code")
    }

    fn text_rendition(text: &str, language: Option<LanguageCode>) -> Rendition {
        Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                language,
                text.to_string(),
                None,
                None,
                None,
            )
            .expect("valid text rendition"),
        )
    }

    fn media_rendition(kind: MediaKind, media_id: &str, fingerprint: &str) -> Rendition {
        Rendition::Media(
            MediaRendition::new(
                RenditionOrigin::Source,
                kind,
                "audio/mpeg",
                fingerprint.to_string(),
                MediaAvailability::Available,
                Some(MediaId::parse(media_id).expect("valid media id")),
                None,
                None,
                None,
                None,
            )
            .expect("valid media rendition"),
        )
    }

    fn revision(
        material_id: LearningMaterialId,
        title: &str,
        renditions: Vec<Rendition>,
        created_at_ms: u64,
    ) -> MaterialRevision {
        MaterialRevision::new(material_id, title, Vec::new(), renditions, created_at_ms)
            .expect("valid revision")
    }

    #[test]
    fn document_rendition_preserves_exact_text_bytes() {
        let Rendition::Document(rendition) =
            text_rendition("  Hello, world!  \n", Some(language("en")))
        else {
            panic!("expected document rendition");
        };
        assert_eq!(rendition.text, "  Hello, world!  \n");
        assert_eq!(
            rendition.language.as_ref().map(LanguageCode::as_str),
            Some("en")
        );
        assert_eq!(
            rendition.text_sha256,
            hex::encode(Sha256::digest(b"  Hello, world!  \n"))
        );
        // byte_size counts bytes, not characters.
        let text = "héllo";
        let Rendition::Document(unicode) = text_rendition(text, None) else {
            panic!("expected document rendition");
        };
        assert_eq!(unicode.text_byte_size, text.len() as u64);
        assert_eq!(unicode.text_byte_size, 6);
    }

    #[test]
    fn revision_identity_is_order_independent() {
        let material_id = LearningMaterialId::parse("material-a").unwrap();
        let r1 = text_rendition("first", None);
        let m1 = media_rendition(MediaKind::Audio, "media-1", "fp-1");
        let m2 = media_rendition(MediaKind::Video, "media-2", "fp-2");
        let forward = revision(
            material_id.clone(),
            "Title",
            vec![r1.clone(), m1.clone(), m2.clone()],
            1,
        );
        let reversed = revision(material_id, "Title", vec![m2, r1, m1], 1);
        assert_eq!(forward.id, reversed.id);
        assert_eq!(forward.renditions, reversed.renditions);
    }

    #[test]
    fn revision_identity_is_content_idempotent_across_retries() {
        let material_id = LearningMaterialId::parse("material-retry").unwrap();
        let first = revision(
            material_id.clone(),
            "Same title",
            vec![text_rendition("same content", None)],
            1,
        );
        let retry = revision(
            material_id,
            "Same title",
            vec![text_rendition("same content", None)],
            999,
        );
        assert_eq!(
            first.id, retry.id,
            "retries at different times converge on the same revision id"
        );
    }

    #[test]
    fn duplicate_component_ids_are_rejected() {
        let duplicate = text_rendition("duplicate", None);
        let result = MaterialRevision::new(
            LearningMaterialId::parse("material").unwrap(),
            "Title",
            Vec::new(),
            vec![duplicate.clone(), duplicate],
            1,
        );
        assert_eq!(result, Err(DomainError::DuplicateAssetId));
    }

    #[test]
    fn blank_title_and_empty_components_are_rejected() {
        let material_id = LearningMaterialId::parse("material").unwrap();
        assert_eq!(
            MaterialRevision::new(
                material_id.clone(),
                "   ",
                Vec::new(),
                vec![text_rendition("x", None)],
                1,
            ),
            Err(DomainError::EmptyValue("MaterialRevision.title"))
        );
        assert_eq!(
            MaterialRevision::new(material_id, "Title", Vec::new(), Vec::new(), 1),
            Err(DomainError::EmptyValue("MaterialRevision.components"))
        );
    }

    #[test]
    fn shapes_derive_from_revision_renditions() {
        let material_id = LearningMaterialId::parse("material").unwrap();
        let shape = |renditions: Vec<Rendition>| {
            revision(material_id.clone(), "Title", renditions, 1).shape()
        };
        assert_eq!(
            shape(vec![text_rendition("text", None)]),
            MaterialShape::Text
        );
        assert_eq!(
            shape(vec![media_rendition(MediaKind::Audio, "m-a", "fp")]),
            MaterialShape::Audio
        );
        assert_eq!(
            shape(vec![media_rendition(MediaKind::Video, "m-v", "fp")]),
            MaterialShape::Video
        );
        assert_eq!(
            shape(vec![
                text_rendition("text", None),
                media_rendition(MediaKind::Audio, "m-a", "fp")
            ]),
            MaterialShape::Mixed
        );
        assert_eq!(
            shape(vec![
                media_rendition(MediaKind::Audio, "m-a", "fp"),
                media_rendition(MediaKind::Video, "m-v", "fp")
            ]),
            MaterialShape::Mixed
        );
    }

    #[test]
    fn media_backed_material_identity_converges_on_media_id() {
        let media = media_rendition(MediaKind::Audio, "media-known", "fp-1");
        let rev_a = revision(
            initial_material_id(&[], std::slice::from_ref(&media)).unwrap(),
            "A",
            vec![media],
            1,
        );
        let media_b = media_rendition(MediaKind::Video, "media-known", "fp-2");
        let rev_b = revision(
            initial_material_id(&[], std::slice::from_ref(&media_b)).unwrap(),
            "B",
            vec![media_b],
            2,
        );
        assert_eq!(
            initial_material_id(&rev_a.source_assets, &rev_a.renditions).unwrap(),
            initial_material_id(&rev_b.source_assets, &rev_b.renditions).unwrap()
        );
        assert_eq!(
            initial_material_id(&rev_a.source_assets, &rev_a.renditions)
                .unwrap()
                .as_str(),
            LearningMaterialId::from_fingerprint("learning-material", "media:media-known").as_str()
        );
    }

    #[test]
    fn multiple_different_source_media_renditions_are_ambiguous() {
        let renditions = vec![
            media_rendition(MediaKind::Audio, "media-1", "fp-1"),
            media_rendition(MediaKind::Video, "media-2", "fp-2"),
        ];
        assert_eq!(
            initial_material_id(&[], &renditions),
            Err(DomainError::AmbiguousInitialMediaIdentity)
        );
    }

    #[test]
    fn initial_material_id_rejects_empty_components() {
        assert_eq!(
            initial_material_id(&[], &[]),
            Err(DomainError::EmptyValue("LearningMaterial.components"))
        );
    }

    #[test]
    fn text_backed_material_identity_converges_on_equal_content() {
        let rev = revision(
            initial_material_id(&[], &[text_rendition("equal text", Some(language("en")))])
                .unwrap(),
            "Title",
            vec![text_rendition("equal text", Some(language("en")))],
            1,
        );
        let material = LearningMaterial::new(&rev, None, 1, 1).expect("valid material");
        assert_eq!(material.id, rev.material_id);
        assert_eq!(
            material.id,
            initial_material_id(&[], &rev.renditions).unwrap()
        );

        let retry = revision(
            material.id.clone(),
            "Title",
            vec![text_rendition("equal text", Some(language("en")))],
            999,
        );
        assert_eq!(retry.id, rev.id);
        let material_retry = LearningMaterial::new(&retry, None, 999, 999).expect("valid material");
        assert_eq!(material.id, material_retry.id);
    }

    #[test]
    fn material_constructor_validates_identity_and_timestamps() {
        let rev = revision(
            initial_material_id(&[], &[text_rendition("content", None)]).unwrap(),
            "Title",
            vec![text_rendition("content", None)],
            1,
        );

        let mut diverged = rev.clone();
        diverged.material_id = LearningMaterialId::parse("other").unwrap();
        assert_eq!(
            LearningMaterial::new(&diverged, None, 1, 1),
            Err(DomainError::MaterialIdentityMismatch)
        );

        assert_eq!(
            LearningMaterial::new(&rev, None, 10, 5),
            Err(DomainError::InvalidTimestamp(
                "updated_at_ms precedes created_at_ms"
            ))
        );
        assert_eq!(
            LearningMaterial::new(&rev, Some(0), 10, 10),
            Err(DomainError::InvalidTimestamp(
                "retained_at_ms precedes created_at_ms"
            ))
        );
        assert_eq!(
            LearningMaterial::new(&rev, None, 2, 2),
            Err(DomainError::InvalidTimestamp(
                "revision.created_at_ms must equal material created_at_ms"
            ))
        );
        assert_eq!(
            LearningMaterial::new(&rev, Some(2), 1, 1),
            Err(DomainError::InvalidTimestamp(
                "retained_at_ms must not be later than updated_at_ms"
            ))
        );

        let material = LearningMaterial::new(&rev, Some(1), 1, 1).expect("valid material");
        assert_eq!(material.id, rev.material_id);
        assert_eq!(material.current_revision_id, rev.id);
        assert_eq!(material.retained_at_ms, Some(1));
    }
}
