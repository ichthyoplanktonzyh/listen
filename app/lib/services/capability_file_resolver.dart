import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/learning_material.dart';
import 'capability_request_encoder.dart';
import 'document_reference_store.dart';

/// The file-system boundary behind capability production. The coordinator
/// resolves rendition content through this seam: it never owns transport,
/// file, or picker implementations itself.
///
/// Document renditions resolve to their exact Source Asset bytes — never to a
/// fabricated "extracted text" file. The App owns the bytes, so the resolver
/// produces the path the Gen run must read; the digest facts travel in the
/// request and are verified by Core.
abstract interface class CapabilityFileResolver {
  /// Resolves the local file carrying the exact Source Asset bytes of a
  /// document rendition, or null when the rendition has no resolvable source
  /// on this machine. Managed bindings read the verified content-addressed
  /// store copy; referenced bindings read the learner-chosen original
  /// location, re-verified at use.
  Future<String?> documentSourcePath(
    DocumentRendition rendition,
    SourceAsset? sourceAsset,
  );

  /// Exact byte facts of a media rendition's local file, or null when the
  /// rendition's file is not available on this machine.
  Future<MediaBlobFacts?> mediaBlobFacts(MediaRendition rendition);

  /// Removes any temporary file this resolver wrote.
  Future<void> dispose();
}

/// The local-file resolver: document source bytes resolve through the managed
/// asset store and the reference map; media blob facts are computed from the
/// rendition's local file.
final class LocalCapabilityFileResolver implements CapabilityFileResolver {
  LocalCapabilityFileResolver({
    required this._managedStorePath,
    required this._referenceStore,
    this._mediaFilePath,
  });

  /// Resolves the managed-store path of a Source Asset's exact bytes, or null
  /// when the store is unavailable.
  final String? Function(SourceAsset asset)? _managedStorePath;

  /// The app-owned reference map for `referenced` bindings.
  final DocumentReferenceStore _referenceStore;

  final String? Function(MediaRendition rendition)? _mediaFilePath;

  @override
  Future<String?> documentSourcePath(
    DocumentRendition rendition,
    SourceAsset? sourceAsset,
  ) async {
    final asset = sourceAsset;
    if (asset == null) return null;
    // The rendition's digest is the Source Asset's exact-byte digest: only a
    // file whose bytes verify is a valid Gen input. Managed copies were
    // verified when copied; referenced locations are re-verified at use.
    if (asset.binding.type == SourceAssetBindingType.managed) {
      return _managedStorePath?.call(asset);
    }
    final reference = asset.binding.reference;
    if (reference == null || reference.isEmpty) return null;
    final location = await _referenceStore.resolve(reference);
    if (location == null || !await _verifies(location, asset)) return null;
    return location;
  }

  /// Re-verifies a referenced location at use: the exact bytes must match the
  /// Source Asset's digest and size before a Gen run reads them.
  Future<bool> _verifies(String path, SourceAsset asset) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      if (await file.length() != asset.byteLength) return false;
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == asset.sha256Digest;
    } on Object {
      return false;
    }
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
    // The resolver writes no temporary files: document sources are the
    // learner's own bytes, never a projection.
  }
}
