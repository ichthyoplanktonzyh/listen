import 'dart:io';

import 'package:file_selector/file_selector.dart';

typedef ReadOccurrenceMedia =
    Future<Map<String, dynamic>> Function(String mediaId);
typedef FingerprintOccurrenceMedia = Future<String> Function(String path);
typedef RegisterOccurrenceMedia = Future<void> Function(String path);
typedef PickOccurrenceMedia =
    Future<XFile?> Function(List<XTypeGroup> acceptedTypeGroups);
typedef OccurrenceFileExists = Future<bool> Function(String path);

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

/// Resolves a lexical occurrence's media snapshot to a playable local path.
///
/// It is intentionally UI-framework-light except for [XTypeGroup], so both
/// the existing source-loop action and the independent slice player follow
/// exactly the same linked-media, file-picker, fingerprint, and registration
/// path.
class OccurrenceMediaResolver {
  OccurrenceMediaResolver({
    required this.readMedia,
    required this.fingerprintFile,
    required this.registerMedia,
    required this.pickFile,
    OccurrenceFileExists? fileExists,
  }) : fileExists = fileExists ?? _fileExists;

  final ReadOccurrenceMedia readMedia;
  final FingerprintOccurrenceMedia fingerprintFile;
  final RegisterOccurrenceMedia registerMedia;
  final PickOccurrenceMedia pickFile;
  final OccurrenceFileExists fileExists;

  static Future<bool> _fileExists(String path) => File(path).exists();

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
        await fileExists(currentMediaPath)) {
      return ResolvedOccurrenceMedia(
        path: currentMediaPath,
        usesCurrentMedia: true,
      );
    }

    final linkedMediaId = occurrence['media_id'] as String?;
    if (linkedMediaId != null) {
      try {
        final linkedMedia = await readMedia(linkedMediaId);
        final linkedPath = linkedMedia['path'];
        if (linkedPath is String && await fileExists(linkedPath)) {
          return ResolvedOccurrenceMedia(
            path: linkedPath,
            usesCurrentMedia: false,
          );
        }
      } catch (_) {
        // A stale link is recoverable: continue to explicit file location.
      }
    }

    final group = filterMediaExtensions
        ? const XTypeGroup(
            label: 'source media',
            extensions: [
              'mp4',
              'mkv',
              'mov',
              'webm',
              'm4a',
              'mp3',
              'wav',
              'flac',
            ],
          )
        : const XTypeGroup(label: 'source media');
    final file = await pickFile([group]);
    if (file == null) {
      return const UnresolvedOccurrenceMedia(
        OccurrenceMediaResolutionFailure.cancelled,
      );
    }
    if (await fingerprintFile(file.path) != expectedFingerprint) {
      return const UnresolvedOccurrenceMedia(
        OccurrenceMediaResolutionFailure.fingerprintMismatch,
      );
    }
    try {
      await registerMedia(file.path);
    } catch (error) {
      return UnresolvedOccurrenceMedia(
        OccurrenceMediaResolutionFailure.registrationFailed,
        error: error,
      );
    }
    return ResolvedOccurrenceMedia(path: file.path, usesCurrentMedia: false);
  }
}
