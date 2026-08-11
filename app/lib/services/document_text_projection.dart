/// Core 3.2 temporary inline `document_text` projection (Phase 1 Slice 0).
///
/// Slice 1 establishes the canonical Document Rendition boundary in Core;
/// Slice 2 replaces this module with the App adapter for that boundary and
/// deletes the whole file. Until then, every piece of document-text business
/// logic in the App lives here — nothing outside this module and the Core 3.2
/// transport (`lib/services/api/materials.dart`) may spell the `document_text`
/// asset kind or decide how it matches submitted text.
///
/// The projection is deliberately thin: it constructs the create input and
/// finds the created asset whose text is byte-for-byte the submitted text.
/// It must not grow into a second document model.
library;

import '../models/learning_material.dart';

/// Builds the inline UTF-8 document-text asset input, untagged. Explicit
/// `retain: false` on the create keeps this a Temporary Material that cannot
/// enter the Personal Library.
DocumentTextMaterialAssetInput documentTextAssetInput(String text) =>
    DocumentTextMaterialAssetInput(text: text, language: null);

/// The created material's document asset whose text is byte-for-byte the
/// submitted text, or null when no document_text asset matches.
///
/// Core 3.2 may converge an equal-content create onto an already retained
/// material; its persisted revision then holds the same text, so an exact
/// match still exists. A response without an exact match must be refused by
/// the caller, never guessed.
DocumentTextMaterialAsset? matchingDocumentTextAsset(
  MaterialDetails details,
  String text,
) {
  final assets = details.currentRevision.assets
      .whereType<DocumentTextMaterialAsset>()
      .toList(growable: false);
  for (final asset in assets) {
    if (asset.text == text) return asset;
  }
  return null;
}
