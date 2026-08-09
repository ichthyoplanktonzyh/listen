//! Durable learner-facing material: typed text documents and media renditions
//! bundled into revisions of a learning material.
//!
//! This module owns the identity and invariant rules for learning material and
//! deliberately contains no file path, repository, or HTTP concepts. Media
//! renditions snapshot their source kind, fingerprint, and availability only;
//! resolving a rendition to a concrete playable source is a later adapter
//! concern.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{
    DomainError, LanguageCode, LearningMaterialId, MaterialAssetId, MaterialRevisionId,
    MediaAvailability, MediaId, MediaKind,
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

/// A learner-facing text document asset.
///
/// Identity is deterministic: derived from the exact UTF-8 bytes plus the
/// normalized language. The stored text is never trimmed or mutated; the
/// digest and byte size are always computed from the exact stored bytes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DocumentTextAsset {
    pub id: MaterialAssetId,
    pub text: String,
    /// Lowercase hex SHA-256 of the exact stored bytes.
    pub sha256_digest: String,
    /// Size of the exact stored bytes.
    pub byte_size: u64,
    pub language: Option<LanguageCode>,
}

impl DocumentTextAsset {
    /// Derives the deterministic asset identity from the exact bytes plus the
    /// optional normalized language. Whitespace-only text is rejected.
    pub fn new(
        text: impl Into<String>,
        language: Option<LanguageCode>,
    ) -> Result<Self, DomainError> {
        let text = text.into();
        if text.trim().is_empty() {
            return Err(DomainError::WhitespaceOnlyText);
        }
        let digest = hex::encode(Sha256::digest(text.as_bytes()));
        // `String::len` is the exact UTF-8 byte length.
        let byte_size = text.len() as u64;
        let language_key = language.as_ref().map(LanguageCode::as_str).unwrap_or("");
        let id = MaterialAssetId::from_fingerprint(
            "material-document-text",
            &length_prefixed(&[digest.as_str(), language_key]),
        );
        Ok(Self {
            id,
            text,
            sha256_digest: digest,
            byte_size,
            language,
        })
    }
}

/// A snapshot of a media source used inside a learning material.
///
/// Kind, fingerprint, and availability are snapshotted so the material stays
/// readable even if the underlying media source moves or is re-registered.
/// The asset never contains a path.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaRenditionAsset {
    pub id: MaterialAssetId,
    pub media_id: MediaId,
    pub kind: MediaKind,
    pub fingerprint: String,
    pub availability: MediaAvailability,
}

impl MediaRenditionAsset {
    /// Derives the deterministic asset identity from the media id, kind, and
    /// fingerprint. A blank fingerprint is rejected. Availability is a stored
    /// snapshot fact and does not participate in identity.
    pub fn new(
        media_id: MediaId,
        kind: MediaKind,
        fingerprint: impl Into<String>,
        availability: MediaAvailability,
    ) -> Result<Self, DomainError> {
        let fingerprint = fingerprint.into();
        if fingerprint.trim().is_empty() {
            return Err(DomainError::EmptyValue("MediaRenditionAsset.fingerprint"));
        }
        let id = MaterialAssetId::from_fingerprint(
            "material-media-rendition",
            &length_prefixed(&[
                media_id.as_str(),
                media_kind_key(kind),
                fingerprint.as_str(),
            ]),
        );
        Ok(Self {
            id,
            media_id,
            kind,
            fingerprint,
            availability,
        })
    }
}

fn media_kind_key(kind: MediaKind) -> &'static str {
    match kind {
        MediaKind::Video => "video",
        MediaKind::Audio => "audio",
    }
}

/// Encodes fields with explicit byte-length prefixes so the concatenation is
/// unambiguously decodable even when a field contains separator characters
/// such as ":" or "|". The encoding is injective: distinct field tuples always
/// produce distinct strings. Format per field: `<byte_len>:<bytes>`.
fn length_prefixed(fields: &[&str]) -> String {
    let mut encoded = String::new();
    for field in fields {
        encoded.push_str(&field.len().to_string());
        encoded.push(':');
        encoded.push_str(field);
    }
    encoded
}

/// A typed asset inside a learning material: either a text document or a
/// media rendition.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MaterialAsset {
    DocumentText(DocumentTextAsset),
    MediaRendition(MediaRenditionAsset),
}

impl MaterialAsset {
    pub fn id(&self) -> &MaterialAssetId {
        match self {
            MaterialAsset::DocumentText(asset) => &asset.id,
            MaterialAsset::MediaRendition(asset) => &asset.id,
        }
    }

    /// Deterministic canonical content fingerprint. Equal content always
    /// yields the same fingerprint, regardless of input ordering. Fields are
    /// byte-length prefixed so the fingerprint is unambiguous even when
    /// inputs contain separator characters.
    pub fn canonical_fingerprint(&self) -> String {
        match self {
            MaterialAsset::DocumentText(asset) => {
                let language = asset
                    .language
                    .as_ref()
                    .map(LanguageCode::as_str)
                    .unwrap_or("");
                format!(
                    "text:{}",
                    length_prefixed(&[asset.sha256_digest.as_str(), language])
                )
            }
            MaterialAsset::MediaRendition(asset) => format!(
                "media:{}",
                length_prefixed(&[
                    asset.media_id.as_str(),
                    media_kind_key(asset.kind),
                    asset.fingerprint.as_str(),
                ])
            ),
        }
    }
}

/// One immutable snapshot of a learning material's content.
///
/// Revision identity is content-idempotent: derived from the material id,
/// exact title, and the canonicalized asset fingerprints, with no timestamp,
/// so retries at different times converge on the same revision.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MaterialRevision {
    pub id: MaterialRevisionId,
    pub material_id: LearningMaterialId,
    pub title: String,
    pub assets: Vec<MaterialAsset>,
    pub created_at_ms: u64,
}

impl MaterialRevision {
    /// Rejects a blank title, an empty asset list, and duplicate
    /// `MaterialAssetId`s. Assets are canonicalized (sorted by id) so equal
    /// content in a different input order produces the same revision id.
    pub fn new(
        material_id: LearningMaterialId,
        title: impl Into<String>,
        mut assets: Vec<MaterialAsset>,
        created_at_ms: u64,
    ) -> Result<Self, DomainError> {
        let title = title.into();
        if title.trim().is_empty() {
            return Err(DomainError::EmptyValue("MaterialRevision.title"));
        }
        if assets.is_empty() {
            return Err(DomainError::EmptyValue("MaterialRevision.assets"));
        }
        canonicalize_assets(&mut assets)?;
        let identity = revision_identity_fingerprint(&material_id, &title, &assets);
        let id = MaterialRevisionId::from_fingerprint("material-revision", &identity);
        Ok(Self {
            id,
            material_id,
            title,
            assets,
            created_at_ms,
        })
    }

    /// Composition shape derived from the current revision assets.
    pub fn shape(&self) -> MaterialShape {
        material_shape(&self.assets)
    }
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
    /// The material identity is deterministic: text-backed materials derive it
    /// from the canonical initial assets (equal text input converges), while
    /// materials that include media derive it from the media id so later
    /// adapters can converge on existing media. A revision whose `material_id`
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
        let id = initial_material_id(&revision.assets)?;
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
/// initial assets.
///
/// - Empty asset list: rejected.
/// - No media renditions: content-backed, from the canonical asset
///   fingerprints (equal text input converges).
/// - Exactly one media rendition (with or without accompanying text):
///   keyed from that media id so adapters can converge on existing media.
/// - Multiple different media renditions: ambiguous, rejected.
pub fn initial_material_id(assets: &[MaterialAsset]) -> Result<LearningMaterialId, DomainError> {
    if assets.is_empty() {
        return Err(DomainError::EmptyValue("LearningMaterial.assets"));
    }
    let media_assets: Vec<&MediaRenditionAsset> = assets
        .iter()
        .filter_map(|asset| match asset {
            MaterialAsset::MediaRendition(rendition) => Some(rendition),
            MaterialAsset::DocumentText(_) => None,
        })
        .collect();
    match media_assets.len() {
        0 => {
            let mut sorted = assets.to_vec();
            sorted.sort_by(|a, b| a.id().as_str().cmp(b.id().as_str()));
            let keys: Vec<String> = sorted
                .iter()
                .map(MaterialAsset::canonical_fingerprint)
                .collect();
            let keys: Vec<&str> = keys.iter().map(String::as_str).collect();
            Ok(LearningMaterialId::from_fingerprint(
                "learning-material",
                &length_prefixed(&keys),
            ))
        }
        1 => Ok(LearningMaterialId::from_fingerprint(
            "learning-material",
            &format!("media:{}", media_assets[0].media_id.as_str()),
        )),
        _ => Err(DomainError::AmbiguousInitialMediaIdentity),
    }
}

/// Derives the composition shape from revision assets: text-only => `Text`;
/// exactly audio renditions => `Audio`; exactly video renditions => `Video`;
/// any combination of text plus media, or audio plus video => `Mixed`.
pub fn material_shape(assets: &[MaterialAsset]) -> MaterialShape {
    let mut has_text = false;
    let mut has_audio = false;
    let mut has_video = false;
    for asset in assets {
        match asset {
            MaterialAsset::DocumentText(_) => has_text = true,
            MaterialAsset::MediaRendition(rendition) => match rendition.kind {
                MediaKind::Audio => has_audio = true,
                MediaKind::Video => has_video = true,
            },
        }
    }
    match (has_text, has_audio, has_video) {
        (true, false, false) => MaterialShape::Text,
        (false, true, false) => MaterialShape::Audio,
        (false, false, true) => MaterialShape::Video,
        _ => MaterialShape::Mixed,
    }
}

fn canonicalize_assets(assets: &mut [MaterialAsset]) -> Result<(), DomainError> {
    assets.sort_by(|a, b| a.id().as_str().cmp(b.id().as_str()));
    for pair in assets.windows(2) {
        if pair[0].id() == pair[1].id() {
            return Err(DomainError::DuplicateAssetId);
        }
    }
    Ok(())
}

fn revision_identity_fingerprint(
    material_id: &LearningMaterialId,
    title: &str,
    assets: &[MaterialAsset],
) -> String {
    let asset_keys: Vec<String> = assets
        .iter()
        .map(MaterialAsset::canonical_fingerprint)
        .collect();
    let asset_keys: Vec<&str> = asset_keys.iter().map(String::as_str).collect();
    let encoded_assets = length_prefixed(&asset_keys);
    length_prefixed(&[material_id.as_str(), title, encoded_assets.as_str()])
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn text_asset(text: &str, language: Option<&str>) -> MaterialAsset {
        let language = language.map(|code| LanguageCode::parse(code).expect("valid language code"));
        MaterialAsset::DocumentText(
            DocumentTextAsset::new(text.to_string(), language).expect("valid text asset"),
        )
    }

    fn media_asset(kind: MediaKind, media_id: &str, fingerprint: &str) -> MaterialAsset {
        MaterialAsset::MediaRendition(
            MediaRenditionAsset::new(
                MediaId::parse(media_id).expect("valid media id"),
                kind,
                fingerprint.to_string(),
                MediaAvailability::Available,
            )
            .expect("valid media rendition"),
        )
    }

    fn revision(
        material_id: LearningMaterialId,
        title: &str,
        assets: Vec<MaterialAsset>,
        created_at_ms: u64,
    ) -> MaterialRevision {
        MaterialRevision::new(material_id, title, assets, created_at_ms).expect("valid revision")
    }

    #[test]
    fn document_text_preserves_exact_bytes() {
        let asset = text_asset("  Hello, world!  \n", Some("en"));
        let MaterialAsset::DocumentText(asset) = asset else {
            panic!("expected document text asset");
        };
        assert_eq!(asset.text, "  Hello, world!  \n");
        assert_eq!(
            asset.language.as_ref().map(LanguageCode::as_str),
            Some("en")
        );
    }

    #[test]
    fn whitespace_only_text_is_rejected() {
        for whitespace in ["", "   ", "\t\n ", "\u{2003}"] {
            let result = DocumentTextAsset::new(whitespace.to_string(), None);
            assert_eq!(
                result,
                Err(DomainError::WhitespaceOnlyText),
                "input: {whitespace:?}"
            );
        }
    }

    #[test]
    fn document_text_digest_and_byte_size_are_computed_from_exact_bytes() {
        let text = "héllo";
        let asset = text_asset(text, None);
        let MaterialAsset::DocumentText(asset) = asset else {
            panic!("expected document text asset");
        };
        let expected_digest = hex::encode(Sha256::digest(text.as_bytes()));
        assert_eq!(asset.sha256_digest, expected_digest);
        assert_eq!(asset.sha256_digest, asset.sha256_digest.to_lowercase());
        // byte_size counts bytes, not characters.
        assert_eq!(asset.byte_size, text.len() as u64);
        assert_eq!(asset.byte_size, 6);
    }

    #[test]
    fn asset_ids_are_deterministic() {
        let a = text_asset("same text", Some("en"));
        let b = text_asset("same text", Some("en"));
        assert_eq!(a.id(), b.id());
        let without_language = text_asset("same text", None);
        assert_ne!(
            a.id(),
            without_language.id(),
            "language participates in text asset identity"
        );
        let different = text_asset("different text", Some("en"));
        assert_ne!(a.id(), different.id());

        let media_a = media_asset(MediaKind::Audio, "media-1", "fp-1");
        let media_b = media_asset(MediaKind::Audio, "media-1", "fp-1");
        assert_eq!(media_a.id(), media_b.id());
        let media_other = media_asset(MediaKind::Video, "media-1", "fp-1");
        assert_ne!(
            media_a.id(),
            media_other.id(),
            "kind participates in identity"
        );
        let media_other_fp = media_asset(MediaKind::Audio, "media-1", "fp-2");
        assert_ne!(media_a.id(), media_other_fp.id());
        let media_other_id = media_asset(MediaKind::Audio, "media-2", "fp-1");
        assert_ne!(media_a.id(), media_other_id.id());
    }

    #[test]
    fn media_asset_identity_is_unambiguous_despite_separator_like_input() {
        // Under the previous colon-joined encoding, both of these distinct
        // media tuples encoded to the same field string ("m:audio:audio:fp"),
        // so their asset ids and canonical fingerprints collided. The
        // byte-length-prefixed encoding must keep them distinct.
        let tuple_a = media_asset(MediaKind::Audio, "m:audio", "fp");
        let tuple_b = media_asset(MediaKind::Audio, "m", "audio:fp");
        assert_ne!(tuple_a.id(), tuple_b.id());
        assert_ne!(
            tuple_a.canonical_fingerprint(),
            tuple_b.canonical_fingerprint()
        );

        // The same collision shape across the kind-key boundary.
        let tuple_c = media_asset(MediaKind::Video, "m:video", "fp");
        let tuple_d = media_asset(MediaKind::Video, "m", "video:fp");
        assert_ne!(tuple_c.id(), tuple_d.id());
        assert_ne!(
            tuple_c.canonical_fingerprint(),
            tuple_d.canonical_fingerprint()
        );

        // Text and media canonical fingerprints stay distinct.
        let text = text_asset("c", None);
        assert_ne!(
            text.canonical_fingerprint(),
            tuple_a.canonical_fingerprint()
        );
    }

    #[test]
    fn revision_identity_is_order_independent() {
        let material_id = LearningMaterialId::parse("material-a").unwrap();
        let a1 = text_asset("first", None);
        let m1 = media_asset(MediaKind::Audio, "media-1", "fp-1");
        let m2 = media_asset(MediaKind::Video, "media-2", "fp-2");
        let forward = revision(
            material_id.clone(),
            "Title",
            vec![a1.clone(), m1.clone(), m2.clone()],
            1,
        );
        let reversed = revision(material_id, "Title", vec![m2, a1, m1], 1);
        assert_eq!(forward.id, reversed.id);
        // Stored asset order is canonicalized by id.
        assert_eq!(forward.assets, reversed.assets);
    }

    #[test]
    fn revision_identity_is_content_idempotent_across_retries() {
        let material_id = LearningMaterialId::parse("material-retry").unwrap();
        let first = revision(
            material_id.clone(),
            "Same title",
            vec![text_asset("same content", None)],
            1,
        );
        let retry = revision(
            material_id,
            "Same title",
            vec![text_asset("same content", None)],
            999,
        );
        assert_eq!(
            first.id, retry.id,
            "retries at different times converge on the same revision id"
        );
    }

    #[test]
    fn revision_identity_is_unambiguous_despite_separator_like_title_and_assets() {
        // Under the previous colon/pipe-joined encoding, each pair of these
        // distinct revisions produced the same identity string: the first pair
        // both encoded to "mat:a:b:media:m:audio:fp" and the second pair both
        // encoded to "mat:Title:media:m:audio:fp|media:o:audio:x".
        let title_boundary = [
            revision(
                LearningMaterialId::parse("mat").unwrap(),
                "a:b",
                vec![media_asset(MediaKind::Audio, "m", "fp")],
                1,
            ),
            revision(
                LearningMaterialId::parse("mat:a").unwrap(),
                "b",
                vec![media_asset(MediaKind::Audio, "m", "fp")],
                1,
            ),
        ];
        assert_ne!(
            title_boundary[0].id, title_boundary[1].id,
            "material id/title boundary must not be ambiguous"
        );

        let material_id = LearningMaterialId::parse("mat").unwrap();
        let asset_list_boundary = [
            revision(
                material_id.clone(),
                "Title",
                vec![media_asset(MediaKind::Audio, "m", "fp|media:o:audio:x")],
                1,
            ),
            revision(
                material_id,
                "Title",
                vec![
                    media_asset(MediaKind::Audio, "m", "fp"),
                    media_asset(MediaKind::Audio, "o", "x"),
                ],
                1,
            ),
        ];
        assert_ne!(
            asset_list_boundary[0].id, asset_list_boundary[1].id,
            "asset list boundary must not be ambiguous"
        );
    }

    #[test]
    fn duplicate_asset_ids_are_rejected() {
        let duplicate = text_asset("duplicate", None);
        let result = MaterialRevision::new(
            LearningMaterialId::parse("material").unwrap(),
            "Title",
            vec![duplicate.clone(), duplicate],
            1,
        );
        assert_eq!(result, Err(DomainError::DuplicateAssetId));
    }

    #[test]
    fn blank_title_and_empty_assets_are_rejected() {
        let material_id = LearningMaterialId::parse("material").unwrap();
        assert_eq!(
            MaterialRevision::new(material_id.clone(), "   ", vec![text_asset("x", None)], 1),
            Err(DomainError::EmptyValue("MaterialRevision.title"))
        );
        assert_eq!(
            MaterialRevision::new(material_id, "Title", vec![], 1),
            Err(DomainError::EmptyValue("MaterialRevision.assets"))
        );
    }

    #[test]
    fn shapes_derive_from_revision_assets() {
        let material_id = LearningMaterialId::parse("material").unwrap();
        let shape =
            |assets: Vec<MaterialAsset>| revision(material_id.clone(), "Title", assets, 1).shape();
        assert_eq!(shape(vec![text_asset("text", None)]), MaterialShape::Text);
        assert_eq!(
            shape(vec![media_asset(MediaKind::Audio, "m-a", "fp")]),
            MaterialShape::Audio
        );
        assert_eq!(
            shape(vec![media_asset(MediaKind::Video, "m-v", "fp")]),
            MaterialShape::Video
        );
        assert_eq!(
            shape(vec![
                text_asset("text", None),
                media_asset(MediaKind::Audio, "m-a", "fp")
            ]),
            MaterialShape::Mixed
        );
        assert_eq!(
            shape(vec![
                text_asset("text", None),
                media_asset(MediaKind::Video, "m-v", "fp")
            ]),
            MaterialShape::Mixed
        );
        assert_eq!(
            shape(vec![
                media_asset(MediaKind::Audio, "m-a", "fp"),
                media_asset(MediaKind::Video, "m-v", "fp")
            ]),
            MaterialShape::Mixed
        );
    }

    #[test]
    fn media_rendition_assets_contain_no_path_by_construction() {
        let rendition = media_asset(MediaKind::Video, "media-no-path", "fp-xyz");
        let MaterialAsset::MediaRendition(rendition) = rendition else {
            panic!("expected media rendition asset");
        };
        assert_eq!(rendition.media_id.as_str(), "media-no-path");
        assert_eq!(rendition.kind, MediaKind::Video);
        assert_eq!(rendition.fingerprint, "fp-xyz");
        assert_eq!(rendition.availability, MediaAvailability::Available);

        let json = serde_json::to_value(&rendition).expect("serializes");
        let object = json.as_object().expect("object");
        assert!(!object.contains_key("path"));
        for key in ["id", "media_id", "kind", "fingerprint", "availability"] {
            assert!(object.contains_key(key), "missing key: {key}");
        }

        assert_eq!(
            MediaRenditionAsset::new(
                MediaId::parse("m").unwrap(),
                MediaKind::Audio,
                "   ",
                MediaAvailability::Available,
            ),
            Err(DomainError::EmptyValue("MediaRenditionAsset.fingerprint"))
        );
    }

    #[test]
    fn media_backed_material_identity_converges_on_media_id() {
        // Same media with different surrounding text still converges.
        let rev_a = revision(
            initial_material_id(&[media_asset(MediaKind::Audio, "media-known", "fp-1")]).unwrap(),
            "A",
            vec![
                text_asset("notes about the media", None),
                media_asset(MediaKind::Audio, "media-known", "fp-1"),
            ],
            1,
        );
        let rev_b = revision(
            initial_material_id(&[media_asset(MediaKind::Video, "media-known", "fp-2")]).unwrap(),
            "B",
            vec![
                media_asset(MediaKind::Video, "media-known", "fp-2"),
                text_asset("different notes", None),
            ],
            2,
        );
        assert_eq!(
            initial_material_id(&rev_a.assets).unwrap(),
            initial_material_id(&rev_b.assets).unwrap()
        );
        // Mixed (media + text) is media-backed: keyed from the media id.
        assert_eq!(
            initial_material_id(&rev_a.assets).unwrap().as_str(),
            LearningMaterialId::from_fingerprint("learning-material", "media:media-known").as_str()
        );
    }

    #[test]
    fn multiple_different_media_renditions_are_ambiguous_for_initial_identity() {
        let assets = vec![
            media_asset(MediaKind::Audio, "media-1", "fp-1"),
            media_asset(MediaKind::Video, "media-2", "fp-2"),
        ];
        assert_eq!(
            initial_material_id(&assets),
            Err(DomainError::AmbiguousInitialMediaIdentity)
        );
    }

    #[test]
    fn initial_material_id_rejects_empty_assets() {
        assert_eq!(
            initial_material_id(&[]),
            Err(DomainError::EmptyValue("LearningMaterial.assets"))
        );
    }

    #[test]
    fn text_backed_material_identity_converges_on_equal_content() {
        let rev = revision(
            initial_material_id(&[text_asset("equal text", Some("en"))]).unwrap(),
            "Title",
            vec![text_asset("equal text", Some("en"))],
            1,
        );
        let material = LearningMaterial::new(&rev, None, 1, 1).expect("valid material");
        assert_eq!(material.id, initial_material_id(&rev.assets).unwrap());

        // A retry at a different time with equal content converges on both the
        // same revision id and the same material id.
        let retry = revision(
            material.id.clone(),
            "Title",
            vec![text_asset("equal text", Some("en"))],
            999,
        );
        assert_eq!(retry.id, rev.id);
        let material_retry = LearningMaterial::new(&retry, None, 999, 999).expect("valid material");
        assert_eq!(material.id, material_retry.id);
    }

    #[test]
    fn material_constructor_validates_identity_and_timestamps() {
        let rev = revision(
            initial_material_id(&[text_asset("content", None)]).unwrap(),
            "Title",
            vec![text_asset("content", None)],
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

        // Initial creation must carry the revision's own creation timestamp.
        assert_eq!(
            LearningMaterial::new(&rev, None, 2, 2),
            Err(DomainError::InvalidTimestamp(
                "revision.created_at_ms must equal material created_at_ms"
            ))
        );
        // Retention evidence cannot postdate the latest update.
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

    #[test]
    fn material_shape_serializes_snake_case() {
        assert_eq!(
            serde_json::to_value(MaterialShape::Text).unwrap(),
            json!("text")
        );
        assert_eq!(
            serde_json::to_value(MaterialShape::Audio).unwrap(),
            json!("audio")
        );
        assert_eq!(
            serde_json::to_value(MaterialShape::Video).unwrap(),
            json!("video")
        );
        assert_eq!(
            serde_json::to_value(MaterialShape::Mixed).unwrap(),
            json!("mixed")
        );
    }

    #[test]
    fn asset_enum_serializes_with_snake_case_variant_names() {
        let asset = text_asset("hello", None);
        let json = serde_json::to_value(&asset).unwrap();
        assert!(json.get("document_text").is_some());
        let back: MaterialAsset = serde_json::from_value(json).expect("round trips");
        assert_eq!(back, asset);

        let media = media_asset(MediaKind::Audio, "m", "fp");
        let json = serde_json::to_value(&media).unwrap();
        assert!(json.get("media_rendition").is_some());
        let back: MaterialAsset = serde_json::from_value(json).expect("round trips");
        assert_eq!(back, media);
    }
}
