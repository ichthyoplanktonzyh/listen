import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/learning_material.dart';
import 'document_reference_store.dart';
import 'managed_asset_store.dart';

/// The outcome of resolving a Source Asset's exact bytes for direct rendering.
sealed class DocumentSourceBytes {
  const DocumentSourceBytes();
}

final class DocumentSourceAvailable extends DocumentSourceBytes {
  const DocumentSourceAvailable(this.bytes);

  final List<int> bytes;
}

/// The bytes are not resolvable right now: a referenced file disappeared, the
/// managed store is unavailable, or the binding is unknown. This is an
/// honest availability fact — never a reason to delete the Material.
final class DocumentSourceUnavailable extends DocumentSourceBytes {
  const DocumentSourceUnavailable();
}

/// Resolves [SourceAsset] bytes for direct rendering.
///
/// Managed bindings read the verified content-addressed store copy; referenced
/// bindings read the learner-chosen original location through the App-owned
/// reference map. The resolver never dereferences anything Core returned as a
/// path — Core returns no paths.
abstract interface class DocumentSourceResolver {
  Future<DocumentSourceBytes> bytesFor(SourceAsset asset);
}

/// Local resolver wired at the composition root.
class LocalDocumentSourceResolver implements DocumentSourceResolver {
  LocalDocumentSourceResolver({
    required this.store,
    required this.referenceStore,
    required this.resolveStoreRoot,
  });

  final ManagedAssetStoreService store;
  final DocumentReferenceStore referenceStore;

  /// The current managed-store root, or null when unavailable.
  final String? Function() resolveStoreRoot;

  @override
  Future<DocumentSourceBytes> bytesFor(SourceAsset asset) async {
    switch (asset.binding.type) {
      case SourceAssetBindingType.managed:
        final root = resolveStoreRoot();
        if (root == null || root.isEmpty) {
          return const DocumentSourceUnavailable();
        }
        final path =
            '$root${Platform.pathSeparator}${asset.sha256Digest}';
        final bytes = await store.readBytes(path);
        return bytes == null
            ? const DocumentSourceUnavailable()
            : DocumentSourceAvailable(bytes);
      case SourceAssetBindingType.referenced:
        final key = asset.binding.reference;
        if (key == null || key.isEmpty) {
          return const DocumentSourceUnavailable();
        }
        final location = await referenceStore.resolve(key);
        if (location == null) return const DocumentSourceUnavailable();
        try {
          final file = File(location);
          if (!await file.exists()) return const DocumentSourceUnavailable();
          final bytes = await file.readAsBytes();
          // Reference in Place is re-verified at every use: the exact bytes
          // must match the Source Asset's digest and size. A changed or
          // replaced file is an honest unavailable fact — never a wrong
          // document.
          if (bytes.length != asset.byteLength) {
            return const DocumentSourceUnavailable();
          }
          if (sha256.convert(bytes).toString() != asset.sha256Digest) {
            return const DocumentSourceUnavailable();
          }
          return DocumentSourceAvailable(bytes);
        } on FileSystemException {
          return const DocumentSourceUnavailable();
        }
    }
  }
}
