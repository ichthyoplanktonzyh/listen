/// App domain models for retained and temporary audio/video learning material.
///
/// The transport adapter owns Core wire decoding. These immutable models carry
/// no file paths or transport details.
library;

/// How a caller stated `retain` on [createLearningMaterial].
sealed class MaterialRetainDirective {
  const MaterialRetainDirective();
}

/// The caller did not state a value: the `retain` key stays absent on the wire.
final class MaterialRetainOmitted extends MaterialRetainDirective {
  const MaterialRetainOmitted();
}

/// An explicitly stated value. `null`, `false` and `true` remain distinct.
final class MaterialRetainExplicit extends MaterialRetainDirective {
  const MaterialRetainExplicit(this.value);
  final bool? value;
}

/// A learning material with no generated-enrichment requirement.
class LearningMaterial {
  const LearningMaterial({
    required this.id,
    required this.currentRevisionId,
    required this.retainedAtMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String id;
  final String currentRevisionId;
  final int? retainedAtMs;
  final int createdAtMs;
  final int updatedAtMs;
  bool get isRetained => retainedAtMs != null;
}

/// Composition shape of a media material's current revision.
enum MaterialShape { audio, video, mixed }

/// Concrete encoding kind of a [MediaRendition].
enum MediaRenditionKind { video, audio }

/// Playback-source state of a [MediaRendition].
enum MediaRenditionAvailability { available, missing, archived }

/// Whether a rendition is learner-authorized original media or a Gen-derived
/// realization.
enum RenditionOrigin { source, derived }

/// A media rendition, snapshotting the media source's identity facts without
/// exposing a file location.
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
  final String? mediaId;
  final String? mediaSha256;
  final int? mediaByteSize;
}

/// A stable semantic and timeline version of a [LearningMaterial].
class MaterialRevision {
  MaterialRevision({
    required this.id,
    required this.materialId,
    required this.title,
    required List<MediaRendition> mediaRenditions,
    required this.createdAtMs,
  }) : _mediaRenditions = List.unmodifiable(mediaRenditions);

  final String id;
  final String materialId;
  final String title;
  final List<MediaRendition> _mediaRenditions;
  List<MediaRendition> get mediaRenditions => _mediaRenditions;
  final int createdAtMs;
}

/// A learning material with its actual current media revision and shape.
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

/// Typed input for an already registered media source.
class MediaRenditionInput {
  const MediaRenditionInput({required this.mediaId});
  final String mediaId;
}

/// Typed create body for [createLearningMaterial]. Retention stays on the
/// operation directive so omission remains explicit.
class CreateLearningMaterialInput {
  CreateLearningMaterialInput({
    required this.title,
    required List<MediaRenditionInput> mediaRenditions,
  }) : _mediaRenditions = List.unmodifiable(mediaRenditions);

  final String title;
  final List<MediaRenditionInput> _mediaRenditions;
  List<MediaRenditionInput> get mediaRenditions => _mediaRenditions;
}

/// Typed append-revision body for [appendMaterialRevision].
class AppendMaterialRevisionInput {
  AppendMaterialRevisionInput({
    required this.title,
    required List<MediaRenditionInput> mediaRenditions,
  }) : _mediaRenditions = List.unmodifiable(mediaRenditions);

  final String title;
  final List<MediaRenditionInput> _mediaRenditions;
  List<MediaRenditionInput> get mediaRenditions => _mediaRenditions;
}

/// A material capability. `read` means ASR/structured-reading production from
/// audio/video media; it is not an independent document-reading route.
enum MaterialCapability { read, listen, watch, synchronizedReadListen }

enum MaterialCapabilityStatus {
  available,
  derivable,
  generating,
  unavailable,
  failedAttempt,
}

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
  final String status;
  final int startedAtMs;
  final int? finishedAtMs;
  final String? failureReason;
  final String? producerToolId;
  final String? producerToolVersion;
}

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
