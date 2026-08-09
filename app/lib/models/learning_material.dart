/// App domain models for the learning-material boundary (Core contract 3.2).
///
/// These are pure, immutable App models: they carry no transport or
/// wire-format coupling (no JSON decoding/encoding helpers) and never expose
/// a file location. JSON decode/encode lives exclusively in
/// `lib/services/api/materials.dart`, which owns the exact Core 3.2
/// `asset_type` union and nullable membership semantics.
library;

/// How a caller stated `retain` on [createLearningMaterial].
///
/// Omission (the default) leaves the key absent on the wire; an explicit
/// directive carries a nullable bool that is always included — `null`, `false`
/// and `true` each keep their exact wire state and are never coerced into
/// another. Core treats omitted/null as the Personal Library default; explicit
/// `false` creates Temporary Material.
sealed class MaterialRetainDirective {
  const MaterialRetainDirective();
}

/// The caller did not state a value: the `retain` key stays absent on the
/// wire.
final class MaterialRetainOmitted extends MaterialRetainDirective {
  const MaterialRetainOmitted();
}

/// An explicitly stated value. [value] is included on the wire exactly as
/// given — `null`, `false` and `true` are all transmitted, never coerced.
final class MaterialRetainExplicit extends MaterialRetainDirective {
  const MaterialRetainExplicit(this.value);

  final bool? value;
}

/// A Learning Material as available inside Listen (DOMAIN.md). It is valid
/// without generated enrichment.
class LearningMaterial {
  const LearningMaterial({
    required this.id,
    required this.currentRevisionId,
    required this.retainedAtMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String id;

  /// Stable id of the current [MaterialRevision].
  final String currentRevisionId;

  /// Evidence of explicit Personal Library membership. Null means Temporary
  /// Material: readable by id and resolvable from its media, but absent from
  /// the material library until explicitly retained.
  final int? retainedAtMs;

  final int createdAtMs;
  final int updatedAtMs;

  /// Whether this material is currently in the Personal Library.
  bool get isRetained => retainedAtMs != null;
}

/// Composition shape of a material's current revision (Core 3.2 `shape`).
enum MaterialShape {
  /// Text-only composition.
  text,

  /// Exactly audio renditions.
  audio,

  /// Exactly video renditions.
  video,

  /// Any mixed combination.
  mixed,
}

/// The concrete encoding kind of a [MediaRenditionMaterialAsset].
enum MediaRenditionKind { video, audio }

/// Playback-source state of a [MediaRenditionMaterialAsset], independent of
/// Personal Library membership.
enum MediaRenditionAvailability { available, missing, archived }

/// A typed asset inside a [MaterialRevision]. Sealed so every asset kind is
/// explicit; the wire union is the flat `asset_type` discriminator decoded in
/// `lib/services/api/materials.dart`.
sealed class MaterialAsset {
  const MaterialAsset({required this.id});

  final String id;
}

/// A document-text asset: inline text plus an optional normalized language
/// tag. Null [language] means the text is untagged.
final class DocumentTextMaterialAsset extends MaterialAsset {
  const DocumentTextMaterialAsset({
    required super.id,
    required this.text,
    required this.sha256Digest,
    required this.byteSize,
    required this.language,
  });

  final String text;

  /// Lowercase hex SHA-256 of the exact stored UTF-8 bytes.
  final String sha256Digest;
  final int byteSize;
  final String? language;
}

/// A media asset referencing an already-registered media source by id. It
/// snapshots the source kind, fingerprint, and availability only — never a
/// file location.
final class MediaRenditionMaterialAsset extends MaterialAsset {
  const MediaRenditionMaterialAsset({
    required super.id,
    required this.mediaId,
    required this.mediaKind,
    required this.fingerprint,
    required this.availability,
  });

  final String mediaId;
  final MediaRenditionKind mediaKind;
  final String fingerprint;
  final MediaRenditionAvailability availability;
}

/// A stable semantic and timeline version of a [LearningMaterial] (DOMAIN.md).
class MaterialRevision {
  MaterialRevision({
    required this.id,
    required this.materialId,
    required this.title,
    required List<MaterialAsset> assets,
    required this.createdAtMs,
  }) : _assets = List.unmodifiable(assets);

  final String id;
  final String materialId;
  final String title;
  final List<MaterialAsset> _assets;

  /// Immutable: the list is wrapped unmodifiable at construction.
  List<MaterialAsset> get assets => _assets;
  final int createdAtMs;
}

/// A learning material with its actual current revision and composition shape,
/// as served by every Core 3.2 material response.
class MaterialDetails {
  const MaterialDetails({
    required this.material,
    required this.currentRevision,
    required this.shape,
  });

  final LearningMaterial material;
  final MaterialRevision currentRevision;
  final MaterialShape shape;

  bool get isRetained => material.isRetained;
}

/// Typed asset input for creating or extending a learning material (Core 3.2
/// `MaterialAssetInput`). Inputs carry only what is needed to build the asset:
/// `document_text` text/language or `media_rendition` media id.
sealed class MaterialAssetInput {
  const MaterialAssetInput();
}

final class DocumentTextMaterialAssetInput extends MaterialAssetInput {
  const DocumentTextMaterialAssetInput({required this.text, this.language});

  final String text;

  /// Normalized language tag; null means the text is untagged.
  final String? language;
}

final class MediaRenditionMaterialAssetInput extends MaterialAssetInput {
  const MediaRenditionMaterialAssetInput({required this.mediaId});

  /// Media source id of an already-registered media item.
  final String mediaId;
}

/// Typed create body for [createLearningMaterial]. [retain] is carried by the
/// operation's [MaterialRetainDirective] argument, not here, so omission stays
/// omission.
class CreateLearningMaterialInput {
  CreateLearningMaterialInput({
    required this.title,
    required List<MaterialAssetInput> assets,
  }) : _assets = List.unmodifiable(assets);

  final String title;
  final List<MaterialAssetInput> _assets;

  /// Immutable: the list is wrapped unmodifiable at construction.
  List<MaterialAssetInput> get assets => _assets;
}

/// Typed append-revision body for [appendMaterialRevision], using the same
/// asset inputs as creation.
class AppendMaterialRevisionInput {
  AppendMaterialRevisionInput({
    required this.title,
    required List<MaterialAssetInput> assets,
  }) : _assets = List.unmodifiable(assets);

  final String title;
  final List<MaterialAssetInput> _assets;

  /// Immutable: the list is wrapped unmodifiable at construction.
  List<MaterialAssetInput> get assets => _assets;
}
