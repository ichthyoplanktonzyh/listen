import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/learning_material.dart';
import 'capability_request_encoder.dart';

/// The file-system boundary behind capability production. The coordinator
/// resolves rendition content through this seam: it never owns transport,
/// file, or picker implementations itself.
abstract interface class CapabilityFileResolver {
  /// Resolves (or writes) the local text file behind a document rendition.
  /// Null when the rendition has no locally readable text.
  String? documentTextPath(DocumentRendition rendition);

  /// Exact byte facts of a media rendition's local file, or null when the
  /// rendition's file is not available on this machine.
  Future<MediaBlobFacts?> mediaBlobFacts(MediaRendition rendition);

  /// Removes any temporary file this resolver wrote.
  Future<void> dispose();
}

/// The local-file resolver: document text is written to a deterministic
/// per-digest temporary file owned by this resolver and removed on dispose;
/// media blob facts are computed from the rendition's local file.
final class LocalCapabilityFileResolver implements CapabilityFileResolver {
  LocalCapabilityFileResolver({
    required this._mediaFilePath,
  });

  final String? Function(MediaRendition rendition)? _mediaFilePath;

  final Map<String, String> _documentTextFiles = {};
  final Set<String> _ownedDocumentTextFiles = {};

  @override
  String? documentTextPath(DocumentRendition rendition) {
    final existing = _documentTextFiles[rendition.textSha256];
    if (existing != null && File(existing).existsSync()) return existing;
    final directory = Directory.systemTemp.createTempSync(
      'listen-capability-document-',
    );
    final path = '${directory.path}/document.txt';
    File(path).writeAsStringSync(rendition.text, flush: true);
    _documentTextFiles[rendition.textSha256] = path;
    _ownedDocumentTextFiles.add(path);
    return path;
  }

  @override
  Future<MediaBlobFacts?> mediaBlobFacts(MediaRendition rendition) async {
    final path = _mediaFilePath?.call(rendition);
    if (path == null) return null;
    try {
      final file = File(path);
      final size = await file.length();
      final digest = await sha256.bind(file.openRead()).first;
      return MediaBlobFacts(sha256Hex: digest.toString(), sizeBytes: size);
    } on Object {
      // The rendition stays without blob facts; a run that needs them fails
      // honestly on the request itself.
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    for (final path in _ownedDocumentTextFiles) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Best-effort cleanup of resolver-owned temp files.
      }
    }
    _documentTextFiles.clear();
    _ownedDocumentTextFiles.clear();
  }
}
