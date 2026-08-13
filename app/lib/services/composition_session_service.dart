import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../data/repositories/capability_repository.dart';
import '../models/adopted_composition.dart';
import 'composition_resolution.dart';

/// Resolves what the adopted-composition surface needs to render: the adopted
/// composition (through Core's single composition interface) and its learner
/// content — the structured reading, the alignment, and the derived audio.
///
/// The App never re-parses a `.listenpkg` to read adopted content; every
/// payload and blob comes back through Core, re-verified by it. Package
/// identity, manifest, and provider raw output stay out of this surface.
class CompositionSessionService {
  CompositionSessionService({required this.repository});

  final CapabilityRepository repository;

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
    final structuredReadingPayload =
        await repository.readCompositionResourcePayload(
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

    return resolveCompositionContent(
      composition: adopted,
      structuredReadingPayload: structuredReadingPayload,
      alignmentPayload: alignmentPayload,
      derivedMediaPath: derivedMediaPath,
    );
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
      final other when other.startsWith('audio/') =>
        other.substring('audio/'.length),
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
