import '../data/repositories/occurrence_media_repository.dart';
import '../services/occurrence_media_file_service.dart';

sealed class OccurrenceMediaResolution {
  const OccurrenceMediaResolution();
}

/// The local file that can satisfy a lexical occurrence's durable source
/// snapshot. [usesCurrentMedia] lets legacy callers retain their current
/// player without reopening it.
class ResolvedOccurrenceMedia extends OccurrenceMediaResolution {
  const ResolvedOccurrenceMedia({
    required this.path,
    required this.usesCurrentMedia,
  });

  final String path;
  final bool usesCurrentMedia;
}

enum OccurrenceMediaResolutionFailure {
  coreUnavailable,
  invalidSnapshot,
  cancelled,
  fingerprintMismatch,
  registrationFailed,
}

/// An explicit failure returned to UI callers rather than a silently aborted
/// source-play action.
class UnresolvedOccurrenceMedia extends OccurrenceMediaResolution {
  const UnresolvedOccurrenceMedia(this.failure, {this.error});

  final OccurrenceMediaResolutionFailure failure;
  final Object? error;

  String get message => switch (failure) {
    OccurrenceMediaResolutionFailure.coreUnavailable =>
      'Connect the local core before playing a source clip',
    OccurrenceMediaResolutionFailure.invalidSnapshot =>
      'This source clip has no usable media fingerprint',
    OccurrenceMediaResolutionFailure.cancelled =>
      'Source media was not selected',
    OccurrenceMediaResolutionFailure.fingerprintMismatch =>
      'Selected file does not match the source fingerprint',
    OccurrenceMediaResolutionFailure.registrationFailed =>
      'Could not register the selected source media',
  };
}

/// Builds the occurrence snapshot for a time range of the currently loaded
/// media (reading replay, listening check). The fingerprint is what lets
/// [OccurrenceMediaResolver] short-circuit to the current player path; without
/// it every resolution is rejected as an invalid snapshot before the
/// linked-media route is even tried.
Map<String, dynamic> currentMediaSliceOccurrence({
  required String? mediaId,
  required String? trackId,
  required String sentenceId,
  required String textSnapshot,
  required int startMs,
  required int endMs,
  required String? mediaFingerprint,
}) => {
  'media_id': mediaId,
  'track_id': trackId,
  'sentence_id': sentenceId,
  'sentence_text_snapshot': textSnapshot,
  'start_ms_snapshot': startMs,
  'end_ms_snapshot': endMs,
  if (mediaFingerprint != null && mediaFingerprint.isNotEmpty)
    'media_fingerprint_snapshot': mediaFingerprint,
};

/// Resolves a lexical occurrence's media snapshot to a playable local path.
///
/// Platform file operations and data access are injected boundaries, so both
/// the existing source-loop action and the independent slice player follow
/// exactly the same recovery path without this controller knowing plugins or
/// transport APIs.
class OccurrenceMediaResolver {
  OccurrenceMediaResolver({
    required this.repository,
    this.fileService = const LocalOccurrenceMediaFileService(),
  });

  final OccurrenceMediaRepository repository;
  final OccurrenceMediaFileService fileService;

  /// Reads only the durable identifier needed to construct a clip snapshot.
  /// A stale media link is recoverable later through [resolve], so it is null
  /// rather than an exception at this boundary.
  Future<String?> mediaFingerprint(String mediaId) async {
    try {
      return (await repository.readMedia(mediaId)).fingerprint;
    } catch (_) {
      return null;
    }
  }

  Future<OccurrenceMediaResolution> resolve(
    Map<String, dynamic> occurrence, {
    required String? currentMediaFingerprint,
    required String? currentMediaPath,
    bool filterMediaExtensions = false,
  }) async {
    final expectedFingerprint = occurrence['media_fingerprint_snapshot'];
    if (expectedFingerprint is! String || expectedFingerprint.isEmpty) {
      return const UnresolvedOccurrenceMedia(
        OccurrenceMediaResolutionFailure.invalidSnapshot,
      );
    }

    if (expectedFingerprint == currentMediaFingerprint &&
        currentMediaPath != null &&
        await fileService.exists(currentMediaPath)) {
      return ResolvedOccurrenceMedia(
        path: currentMediaPath,
        usesCurrentMedia: true,
      );
    }

    final linkedMediaId = occurrence['media_id'] as String?;
    if (linkedMediaId != null) {
      try {
        final linkedMedia = await repository.readMedia(linkedMediaId);
        final linkedPath = linkedMedia.path;
        if (await fileService.exists(linkedPath)) {
          return ResolvedOccurrenceMedia(
            path: linkedPath,
            usesCurrentMedia: false,
          );
        }
      } catch (_) {
        // A stale link is recoverable: continue to explicit file location.
      }
    }

    final path = await fileService.pickSourceMedia(
      filterMediaExtensions: filterMediaExtensions,
    );
    if (path == null) {
      return const UnresolvedOccurrenceMedia(
        OccurrenceMediaResolutionFailure.cancelled,
      );
    }
    if (await repository.fingerprintFile(path) != expectedFingerprint) {
      return const UnresolvedOccurrenceMedia(
        OccurrenceMediaResolutionFailure.fingerprintMismatch,
      );
    }
    try {
      await repository.registerMedia(path);
    } catch (error) {
      return UnresolvedOccurrenceMedia(
        OccurrenceMediaResolutionFailure.registrationFailed,
        error: error,
      );
    }
    return ResolvedOccurrenceMedia(path: path, usesCurrentMedia: false);
  }
}
