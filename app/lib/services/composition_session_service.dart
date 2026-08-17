import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../data/repositories/capability_repository.dart';
import '../data/repositories/resource_repository.dart';
import '../models/adopted_composition.dart';
import '../models/composition.dart';
import '../models/timeline.dart';
import 'composition_core_projection.dart';
import 'composition_resolution.dart';
import 'composition_resource_projection.dart';

/// Resolves what the adopted-composition surface needs to render: the adopted
/// composition (through Core's single composition interface) and its learner
/// content — the structured reading, the alignment, and the derived audio.
///
/// The App never re-parses a `.listenpkg` to read adopted content; every
/// payload and blob comes back through Core, re-verified by it. Package
/// identity, manifest, and provider raw output stay out of this surface.
class CompositionSessionService {
  CompositionSessionService({
    required this.repository,
    required this.resources,
  });

  final CapabilityRepository repository;
  final ResourceRepository resources;

  /// The resolved learner content of the currently adopted composition, or
  /// null when nothing is adopted (a typed not-found) or when the required
  /// content cannot be resolved honestly.
  Future<ResolvedComposition?> resolveComposition(String materialId) async {
    final AdoptedComposition adopted;
    try {
      adopted = await repository.readAdoptedComposition(materialId);
    } on Object catch (error) {
      // No adopted composition is a normal state, not a failure of the
      // material; everything else propagates to the caller's failure surface.
      final failure = repository.failureDetail(error);
      if (failure.code == 'not_found') return null;
      rethrow;
    }

    final structuredReading = adopted.resourceOfKind('structured_reading');
    if (structuredReading == null) return null;
    List<int>? alignmentPayload;
    final alignment = adopted.resourceOfKind('anchor_time_alignment');
    if (alignment != null) {
      alignmentPayload = await repository.readCompositionResourcePayload(
        materialId,
        alignment.resourceId,
      );
    }
    final structuredReadingPayload = await repository
        .readCompositionResourcePayload(
          materialId,
          structuredReading.resourceId,
        );

    // The derived audio rendition's embedded blob is downloaded so the player
    // can play the produced speech; its bytes stay re-verified by Core.
    final media = adopted.derivedMediaRendition;
    String? derivedMediaPath;
    if (media != null) {
      final blob = await repository.readCompositionRenditionBlob(
        materialId,
        media.renditionId,
      );
      derivedMediaPath = _writeMediaBlob(media, blob);
    }

    final projected = await _readWorkbenchResources(materialId, adopted);

    return resolveCompositionContent(
      composition: adopted,
      structuredReadingPayload: structuredReadingPayload,
      alignmentPayload: alignmentPayload,
      derivedMediaPath: derivedMediaPath,
      transcript: projected.transcript,
      enhancements: projected.enhancements,
    );
  }

  /// Reads the composition's workbench resources from Core, never from the
  /// package payload.
  ///
  /// The adopted `subtitle_text_track` is a real subtitle track under the
  /// composition's source media; its sentence ids are global
  /// `SubtitleSentenceId`s. Its five analysis resource families are read back
  /// through the track's LLTimeline export, already re-keyed by Core. The
  /// tokenless `timed_text_track` has no Core landing and remains the honest
  /// display-only fallback.
  ///
  /// Every one of these is optional by contract, so this never fails the
  /// composition: a resource that is absent, unreadable, or unresolvable
  /// simply contributes nothing.
  Future<
    ({CompositionResourceProjection enhancements, SubtitleTrack? transcript})
  >
  _readWorkbenchResources(String materialId, AdoptedComposition adopted) async {
    try {
      final sourceMediaId = adopted.sourceMediaId;
      if (sourceMediaId != null) {
        final tracks = await resources.mediaSubtitles(sourceMediaId);
        final track = _packageSubtitleTrack(tracks);
        if (track != null) {
          final document = await resources.exportTimelineJson(track.id);
          return (
            enhancements: projectCompositionResourcesFromCore(
              track: track,
              documentJson: document.json,
            ),
            transcript: track,
          );
        }
      }
      final timedTrackPayload = await _payloadOfKind(
        materialId,
        adopted,
        'timed_text_track',
      );
      return (
        enhancements: const CompositionResourceProjection(),
        transcript: projectCompositionTimedTranscript(
          timedTrackPayload,
          trackId: 'composition:${adopted.editionId}',
        ),
      );
    } on Object {
      return (
        enhancements: const CompositionResourceProjection(),
        transcript: null,
      );
    }
  }

  /// The package subtitle track Core landed for this composition, when it is
  /// still available and still carries sentences.
  SubtitleTrack? _packageSubtitleTrack(List<SubtitleTrack> tracks) {
    for (final track in tracks) {
      if (track.source == 'package:subtitle_text_track' &&
          track.usableForLearning) {
        return track;
      }
    }
    return null;
  }

  /// The exact payload of one resource kind, or null when the composition
  /// does not carry it or the read fails.
  Future<List<int>?> _payloadOfKind(
    String materialId,
    AdoptedComposition adopted,
    String kind,
  ) async {
    final resource = adopted.resourceOfKind(kind);
    if (resource == null) return null;
    try {
      return await repository.readCompositionResourcePayload(
        materialId,
        resource.resourceId,
      );
    } on Object {
      return null;
    }
  }

  /// Writes the exact derived audio bytes to a temporary file for the player.
  static String _writeMediaBlob(
    AdoptedCompositionRendition media,
    List<int> bytes,
  ) {
    final extension = switch (media.mediaType) {
      'audio/mp4' => 'm4a',
      'audio/mpeg' => 'mp3',
      'audio/wav' => 'wav',
      final other when other.startsWith('audio/') => other.substring(
        'audio/'.length,
      ),
      _ => 'bin',
    };
    final directory = Directory(
      '${Directory.systemTemp.path}/listen-composition-media/'
      '${_safeName(media.renditionId)}',
    );
    directory.createSync(recursive: true);
    final path = '${directory.path}/${_safeName(media.renditionId)}.$extension';
    File(path).writeAsBytesSync(bytes, flush: true);
    return path;
  }

  static String _safeName(String value) {
    final digest = sha256Hex(value);
    return '${value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}-$digest';
  }

  static String sha256Hex(String value) {
    // SHA-256 over the UTF-8 bytes of the rendition id: a deterministic,
    // collision-safe temporary name. The id is already a Core digest, but a
    // plain substring would leak unrelated id bytes into the file name.
    return sha256.convert(utf8.encode(value)).toString();
  }
}
