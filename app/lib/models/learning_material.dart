/// App domain models for the learning-material boundary (Core contract 4.0).
///
/// These are pure, immutable App models: they carry no transport or
/// wire-format coupling (no JSON decoding/encoding helpers) and never expose
/// a file location. JSON decode/encode lives exclusively in
/// `lib/services/api/materials.dart`, which owns the exact Core 4.0
/// `source_assets` / `document_renditions` / `media_renditions` union and
/// nullable membership semantics.
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

/// Composition shape of a material's current revision (Core 4.0 `shape`).
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

/// The concrete encoding kind of a [MediaRendition].
enum MediaRenditionKind { video, audio }

/// Playback-source state of a [MediaRendition], independent of Personal
/// Library membership.
enum MediaRenditionAvailability { available, missing, archived }

/// Whether a rendition records the learner-authorized original bytes
/// (Source) or a producer-derived realization (Derived).
enum RenditionOrigin { source, derived }

/// Where the exact source bytes live (Core 4.0 `SourceAssetBinding`).
enum SourceAssetBindingType { managed, referenced }

/// App-owned binding facts of a [SourceAsset]. Never a file location for the wire to dereference:
/// [reference] is an opaque app-owned key, resolved by the App's own mapping.
class SourceAssetBinding {
  const SourceAssetBinding({required this.type, this.reference});

  final SourceAssetBindingType type;

  /// Opaque app-owned reference for a `referenced` binding; null for a
  /// managed binding.
  final String? reference;
}

/// Runtime availability fact of a [SourceAsset]'s exact bytes.
enum SourceAssetAvailabilityState { available, unavailable }

/// Why a [SourceAsset] is unavailable; null while it is available.
enum SourceAssetUnavailableReason { fileMissing, integrityMismatch }

class SourceAssetAvailability {
  const SourceAssetAvailability({
    required this.state,
    this.reason,
  });

  final SourceAssetAvailabilityState state;
  final SourceAssetUnavailableReason? reason;

  bool get isAvailable =>
      state == SourceAssetAvailabilityState.available;
}

/// A learner-authorized source evidence fact (Core 4.0 `SourceAsset`): the
/// exact bytes of the original source, described without any file location.
class SourceAsset {
  const SourceAsset({
    required this.id,
    required this.mediaType,
    required this.byteLength,
    required this.sha256Digest,
    required this.binding,
    required this.availability,
    required this.createdAtMs,
  });

  final String id;
  final String mediaType;
  final int byteLength;

  /// Lowercase hex SHA-256 of the exact source bytes.
  final String sha256Digest;
  final SourceAssetBinding binding;
  final SourceAssetAvailability availability;
  final int createdAtMs;
}

/// A document rendition (Core 4.0 `DocumentRendition`): the readable
/// representation of one document of the material revision, with its exact
/// text bytes verified. Derived renditions record exact producer facts and
/// inputs, never exposed here.
class DocumentRendition {
  const DocumentRendition({
    required this.id,
    required this.origin,
    required this.mediaType,
    required this.language,
    required this.digest,
    required this.byteSize,
    required this.sourceAssetId,
  });

  final String id;
  final RenditionOrigin origin;
  final String mediaType;

  /// Normalized language tag; null means the text is untagged.
  final String? language;

  /// Lowercase hex SHA-256 of the exact rendition bytes. For a Source
  /// rendition those are the bound Source Asset's exact bytes.
  final String digest;
  final int byteSize;

  /// The bound Source Asset for a Source rendition; null for Derived.
  final String? sourceAssetId;
}

/// A media rendition (Core 4.0 `MediaRendition`): a source or derived
/// realization of the material's media, snapshotting the media source's
/// facts — never a file location.
class MediaRendition {
  const MediaRendition({
    required this.id,
    required this.origin,
    required this.kind,
    required this.mediaType,
    required this.fingerprint,
    required this.availability,
    required this.mediaId,
    required this.mediaSha256,
    required this.mediaByteSize,
  });

  final String id;
  final RenditionOrigin origin;
  final MediaRenditionKind kind;
  final String mediaType;
  final String fingerprint;
  final MediaRenditionAvailability availability;

  /// The bound media source for a Source rendition; null for Derived.
  final String? mediaId;

  /// Required for a Derived rendition.
  final String? mediaSha256;
  final int? mediaByteSize;
}

/// A stable semantic and timeline version of a [LearningMaterial] (DOMAIN.md).
class MaterialRevision {
  MaterialRevision({
    required this.id,
    required this.materialId,
    required this.title,
    required List<SourceAsset> sourceAssets,
    required List<DocumentRendition> documentRenditions,
    required List<MediaRendition> mediaRenditions,
    required this.createdAtMs,
  }) : _sourceAssets = List.unmodifiable(sourceAssets),
       _documentRenditions = List.unmodifiable(documentRenditions),
       _mediaRenditions = List.unmodifiable(mediaRenditions);

  final String id;
  final String materialId;
  final String title;

  final List<SourceAsset> _sourceAssets;
  final List<DocumentRendition> _documentRenditions;
  final List<MediaRendition> _mediaRenditions;

  /// Immutable: the lists are wrapped unmodifiable at construction.
  List<SourceAsset> get sourceAssets => _sourceAssets;
  List<DocumentRendition> get documentRenditions => _documentRenditions;
  List<MediaRendition> get mediaRenditions => _mediaRenditions;
  final int createdAtMs;
}

/// A learning material with its actual current revision and composition shape,
/// as served by every Core 4.0 material response.
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

/// Typed Source Asset input (Core 4.0 `SourceAssetInput`): the exact byte
/// facts of the original source, without any file location.
class SourceAssetInput {
  const SourceAssetInput({
    required this.mediaType,
    required this.byteLength,
    required this.sha256Digest,
    required this.binding,
  });

  final String mediaType;
  final int byteLength;
  final String sha256Digest;
  final SourceAssetBinding binding;
}

/// Typed Document Rendition input (Core 4.0 `DocumentRenditionInput`).
class DocumentRenditionInput {
  const DocumentRenditionInput({
    required this.mediaType,
    required this.digest,
    required this.byteSize,
    this.language,
    this.sourceAssetIndex,
  });

  final String mediaType;

  /// Lowercase hex SHA-256 of the exact rendition bytes. The App always binds
  /// Source rendition bytes to a Source Asset in the same request, so this is
  /// the Source Asset's own digest; Core verifies the exact match.
  final String digest;
  final int byteSize;

  /// Normalized language tag; null means the text is untagged.
  final String? language;

  /// Index of a Source Asset in the same request to bind as this Source
  /// rendition's exact bytes; null means no Source Asset binding.
  final int? sourceAssetIndex;
}

/// Typed Media Rendition input (Core 4.0 `MediaRenditionInput`).
class MediaRenditionInput {
  const MediaRenditionInput({required this.mediaId});

  /// Media source id of an already-registered media item.
  final String mediaId;
}

/// Typed create body for [createLearningMaterial]. [retain] is carried by the
/// operation's [MaterialRetainDirective] argument, not here, so omission stays
/// omission.
class CreateLearningMaterialInput {
  CreateLearningMaterialInput({
    required this.title,
    required List<SourceAssetInput> sourceAssets,
    required List<DocumentRenditionInput> documentRenditions,
    required List<MediaRenditionInput> mediaRenditions,
  }) : _sourceAssets = List.unmodifiable(sourceAssets),
       _documentRenditions = List.unmodifiable(documentRenditions),
       _mediaRenditions = List.unmodifiable(mediaRenditions);

  final String title;
  final List<SourceAssetInput> _sourceAssets;
  final List<DocumentRenditionInput> _documentRenditions;
  final List<MediaRenditionInput> _mediaRenditions;

  /// Immutable: the lists are wrapped unmodifiable at construction.
  List<SourceAssetInput> get sourceAssets => _sourceAssets;
  List<DocumentRenditionInput> get documentRenditions => _documentRenditions;
  List<MediaRenditionInput> get mediaRenditions => _mediaRenditions;
}

/// Typed append-revision body for [appendMaterialRevision], using the same
/// typed inputs as creation.
class AppendMaterialRevisionInput {
  AppendMaterialRevisionInput({
    required this.title,
    required List<SourceAssetInput> sourceAssets,
    required List<DocumentRenditionInput> documentRenditions,
    required List<MediaRenditionInput> mediaRenditions,
  }) : _sourceAssets = List.unmodifiable(sourceAssets),
       _documentRenditions = List.unmodifiable(documentRenditions),
       _mediaRenditions = List.unmodifiable(mediaRenditions);

  final String title;
  final List<SourceAssetInput> _sourceAssets;
  final List<DocumentRenditionInput> _documentRenditions;
  final List<MediaRenditionInput> _mediaRenditions;

  /// Immutable: the lists are wrapped unmodifiable at construction.
  List<SourceAssetInput> get sourceAssets => _sourceAssets;
  List<DocumentRenditionInput> get documentRenditions => _documentRenditions;
  List<MediaRenditionInput> get mediaRenditions => _mediaRenditions;
}

/// A material capability (Core 4.0 `MaterialCapabilityProjection.capability`).
enum MaterialCapability {
  read,
  listen,
  watch,
  synchronizedReadListen,
}

/// The five-state capability projection
/// (Core 4.0 `MaterialCapabilityProjection.status`). Attempts are the unit of
/// `generating` / `failed_attempt` evidence; a failed attempt never
/// invalidates an otherwise usable Material.
enum MaterialCapabilityStatus {
  available,
  derivable,
  generating,
  unavailable,
  failedAttempt,
}

/// Latest durable attempt of a capability (Core 4.0 `CapabilityAttempt`).
class CapabilityAttempt {
  const CapabilityAttempt({
    required this.attemptId,
    required this.status,
    required this.startedAtMs,
    required this.finishedAtMs,
    required this.failureReason,
    required this.producerToolId,
    required this.producerToolVersion,
  });

  final String attemptId;

  /// running / succeeded / failed.
  final String status;
  final int startedAtMs;
  final int? finishedAtMs;
  final String? failureReason;
  final String? producerToolId;
  final String? producerToolVersion;
}

/// One capability's projection (Core 4.0 `MaterialCapabilityProjection`).
class MaterialCapabilityProjection {
  const MaterialCapabilityProjection({
    required this.capability,
    required this.status,
    required this.latestAttempt,
  });

  final MaterialCapability capability;
  final MaterialCapabilityStatus status;
  final CapabilityAttempt? latestAttempt;
}
