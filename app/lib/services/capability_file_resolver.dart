import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/learning_material.dart';
import 'capability_request_encoder.dart';

/// Resolves local AV files and verifies the exact bytes the Gen run consumes.
abstract interface class CapabilityFileResolver {
  /// Resolves the local file behind a media rendition, or null when the
  /// rendition's file is not known on this machine.
  Future<String?> mediaPath(MediaRendition rendition);

  /// Exact byte facts of a media rendition's local file.
  Future<MediaBlobFacts?> mediaBlobFacts(MediaRendition rendition);

  Future<void> dispose();
}

final class LocalCapabilityFileResolver implements CapabilityFileResolver {
  LocalCapabilityFileResolver({this._mediaFilePath});

  final Future<String?> Function(MediaRendition rendition)? _mediaFilePath;

  @override
  Future<String?> mediaPath(MediaRendition rendition) async =>
      await _mediaFilePath?.call(rendition);

  @override
  Future<MediaBlobFacts?> mediaBlobFacts(MediaRendition rendition) async {
    final path = await mediaPath(rendition);
    if (path == null) return null;
    try {
      final file = File(path);
      final size = await file.length();
      final digest = await sha256.bind(file.openRead()).first;
      return MediaBlobFacts(sha256Hex: digest.toString(), sizeBytes: size);
    } on Object {
      // The request carries no blob facts; Gen reports a typed input failure.
      return null;
    }
  }

  @override
  Future<void> dispose() async {}
}
