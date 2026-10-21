import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/learning_material.dart';
import 'capability_request_encoder.dart';
import 'document_reference_store.dart';

/// Resolves local AV files and verifies the exact bytes the Gen run consumes.
abstract interface class CapabilityFileResolver {
  /// Resolves the exact source file backing a document rendition. The path is
  /// an App-local fact and is only placed in the run-owned Gen request.
  Future<String?> documentSourcePath(
    DocumentRendition rendition,
    SourceAsset? sourceAsset,
  );

  /// Resolves the local file behind a media rendition, or null when the
  /// rendition's file is not known on this machine.
  Future<String?> mediaPath(MediaRendition rendition);

  /// Exact byte facts of a media rendition's local file.
  Future<MediaBlobFacts?> mediaBlobFacts(MediaRendition rendition);

  Future<void> dispose();
}

final class LocalCapabilityFileResolver implements CapabilityFileResolver {
  LocalCapabilityFileResolver({
    this.mediaFilePath,
    this.managedStoreRoot,
    this.referenceStore,
  });

  final Future<String?> Function(MediaRendition rendition)? mediaFilePath;
  final String? Function()? managedStoreRoot;
  final DocumentReferenceStore? referenceStore;

  @override
  Future<String?> documentSourcePath(
    DocumentRendition rendition,
    SourceAsset? sourceAsset,
  ) async {
    final asset = sourceAsset;
    if (rendition.origin != RenditionOrigin.source ||
        asset == null ||
        !asset.availability.isAvailable ||
        asset.sha256Digest != rendition.digest ||
        asset.byteLength != rendition.byteSize) {
      return null;
    }
    switch (asset.binding.type) {
      case SourceAssetBindingType.managed:
        final root = managedStoreRoot?.call();
        if (root == null || root.isEmpty) return null;
        final path = p.join(root, asset.sha256Digest);
        return await _verifies(path, asset) ? path : null;
      case SourceAssetBindingType.referenced:
        final reference = asset.binding.reference;
        final store = referenceStore;
        if (reference == null || reference.isEmpty || store == null) {
          return null;
        }
        final path = await store.resolve(reference);
        return path != null && await _verifies(path, asset) ? path : null;
    }
  }

  Future<bool> _verifies(String path, SourceAsset asset) async {
    try {
      final file = File(path);
      if (!await file.exists() || await file.length() != asset.byteLength) {
        return false;
      }
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == asset.sha256Digest;
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> mediaPath(MediaRendition rendition) async =>
      await mediaFilePath?.call(rendition);

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
