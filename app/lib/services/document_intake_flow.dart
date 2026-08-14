import '../data/repositories/learning_material_repository.dart';
import '../models/learning_material.dart';
import 'document_decoding/document_format.dart';
import 'document_intake_service.dart';
import 'document_reference_store.dart';
import 'managed_asset_store.dart';

/// The outcome of taking a document in: the created (or converged-on)
/// material together with the exact byte digest the intake submitted, so the
/// caller can verify the response carries a rendition of exactly those bytes.
final class DocumentIntakeOutcome {
  const DocumentIntakeOutcome({
    required this.details,
    required this.sha256Digest,
  });

  final MaterialDetails details;

  /// SHA-256 of the exact submitted bytes, in lowercase 64-hex.
  final String sha256Digest;
}

/// The shared document intake: decode, bind, create, and exact-match the
/// source Document Rendition.
///
/// One intake for every door a document can enter by — a picked file, pasted
/// text, and a discovered article — so an article travels the same decode,
/// the same binding decision, and the same Core create as a local file. The
/// caller owns presentation (sessions, progress, failures); this service owns
/// the four facts that must never drift apart:
///
/// 1. the bytes are validated and their exact facts (digest, size, media
///    type) established;
/// 2. the bytes are bound — copied into the managed store, or referenced in
///    place under the app-owned reference key;
/// 3. Core creates (or converges on) the Material with one Source Asset and
///    one Source Document Rendition of exactly those bytes, never retained;
/// 4. a create failure rolls back only what this intake created, and a
///    response without an exact byte match is refused.
///
/// On failure the original error is rethrown (a [DocumentIntakeFailure] for
/// decode, anything the repository threw otherwise), so callers map it to
/// their own failure surface.
final class DocumentIntakeFlow {
  DocumentIntakeFlow({
    required this.materialRepository,
    required this.codec,
    required this.store,
    required this.referenceStore,
  });

  final LearningMaterialRepository materialRepository;
  final DocumentIntakeCodec codec;
  final ManagedAssetStoreService store;
  final DocumentReferenceStore referenceStore;

  /// Takes a document in and returns the material holding exactly those
  /// bytes as a Source Document Rendition.
  ///
  /// [title] is the material's title as the caller knows it (a file name, a
  /// feed's item title). [format] must match the bytes (e.g. html for a
  /// fetched article page). [referenceInPlace] records the original location
  /// under the app-owned reference key when [sourcePath] exists; otherwise —
  /// and always for bytes without a location — the exact bytes are copied
  /// into the managed store.
  Future<DocumentIntakeOutcome> takeInDocument({
    required String title,
    required List<int> bytes,
    required DocumentFormat format,
    String? sourcePath,
    bool referenceInPlace = false,
  }) async {
    final input = await codec.decodeDocument(
      bytes: bytes,
      title: title,
      format: format,
    );

    var binding = const SourceAssetBinding(
      type: SourceAssetBindingType.managed,
    );
    String? createdStoreCopy;
    try {
      if (referenceInPlace && sourcePath != null) {
        await referenceStore.save(input.sha256Digest, sourcePath);
        binding = SourceAssetBinding(
          type: SourceAssetBindingType.referenced,
          reference: input.sha256Digest,
        );
      } else {
        final copy = await store.copyBytesIntoStore(
          bytes: bytes,
          mediaKind: 'document',
        );
        createdStoreCopy = copy.createdNew ? copy.path : null;
      }
    } catch (_) {
      if (binding.type == SourceAssetBindingType.referenced) {
        try {
          await referenceStore.remove(input.sha256Digest);
        } catch (_) {
          // Best effort.
        }
      }
      rethrow;
    }

    final MaterialDetails details;
    try {
      details = await materialRepository.createLearningMaterial(
        CreateLearningMaterialInput(
          title: input.title,
          sourceAssets: [
            SourceAssetInput(
              mediaType: input.mediaType,
              byteLength: input.byteLength,
              sha256Digest: input.sha256Digest,
              // The binding is an app-owned fact, never a file location the
              // wire may dereference.
              binding: binding,
            ),
          ],
          documentRenditions: [
            // The Source Document Rendition is the exact Source Asset bytes:
            // same digest, same size, bound to the Source Asset. The material
            // never carries a fabricated extracted-text body.
            DocumentRenditionInput(
              mediaType: input.mediaType,
              digest: input.sha256Digest,
              byteSize: input.byteLength,
              sourceAssetIndex: 0,
            ),
          ],
          mediaRenditions: const [],
        ),
        retain: const MaterialRetainExplicit(false),
      );
    } catch (error) {
      // The create failed: roll back the store copy only when this call
      // created it (a deduplicated pre-existing target is shared and stays),
      // and drop the reference mapping for a failed referenced create.
      final copy = createdStoreCopy;
      if (copy != null) {
        try {
          await store.deleteStoreCopy(copy);
        } catch (_) {
          // Rollback is best effort; the failure surface stays typed.
        }
      }
      if (binding.type == SourceAssetBindingType.referenced) {
        try {
          await referenceStore.remove(input.sha256Digest);
        } catch (_) {
          // Best effort.
        }
      }
      rethrow;
    }

    final rendition = matchingDocumentRendition(details, input.sha256Digest);
    if (rendition == null) {
      // The response holds no source document rendition bound to the exact
      // submitted bytes. Refuse to guess: showing another rendition's body as
      // the taken-in document breaks direct-view integrity.
      throw StateError(
        'create response has no document rendition matching the submitted '
        'bytes',
      );
    }
    return DocumentIntakeOutcome(details: details, sha256Digest: input.sha256Digest);
  }

  /// The created material's source document rendition whose exact bytes are
  /// the submitted Source Asset's, or null when no rendition matches.
  ///
  /// Core 4.0 may converge an equal-content create onto an already retained
  /// material; its persisted revision then holds the same bytes, so an exact
  /// digest match still exists. A response without an exact match must be
  /// refused by the caller, never guessed.
  static DocumentRendition? matchingDocumentRendition(
    MaterialDetails details,
    String sourceSha256,
  ) {
    for (final rendition in details.currentRevision.documentRenditions) {
      if (rendition.origin != RenditionOrigin.source) continue;
      if (rendition.digest == sourceSha256) return rendition;
    }
    return null;
  }
}
