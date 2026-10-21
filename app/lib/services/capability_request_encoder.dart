import '../models/learning_material.dart';

/// Encodes one `listen_gen.capability-request.v2` document.
abstract final class CapabilityRequestEncoder {
  static const schema = 'listen_gen.capability-request.v2';
  static const version = 2;

  static Map<String, dynamic> encode({
    required String materialId,
    required String materialRevisionId,
    required String materialTitle,
    required String editionId,
    required String editionTitle,
    required String targetLanguage,
    required List<String> supportLanguages,
    required String requestedCapability,
    required int createdAtMs,
    String? attemptId,
    List<DocumentRendition> documentRenditions = const [],
    String? Function(DocumentRendition rendition)? documentFilePath,
    List<MediaRendition> mediaRenditions = const [],
    String? Function(MediaRendition rendition)? mediaFilePath,
    Map<String, MediaBlobFacts>? mediaBlobFacts,
  }) {
    final availableEntries = <Map<String, dynamic>>[];
    for (final rendition in documentRenditions) {
      // Gen v2 uses SHA-256 references for rendition/source IDs, matching the
      // package protocol. Core's canonical IDs are lowercase hex strings.
      availableEntries.add({
        'kind': 'document',
        'rendition_id': _sha256Reference(rendition.id),
        'media_type': rendition.mediaType,
        'language': rendition.language,
        // Source Asset IDs are Core-owned identifiers and remain raw in the
        // request. Gen adds the `sha256:` package-reference prefix only at
        // the Content Package v3 boundary.
        'source_asset_id': rendition.sourceAssetId,
        'blob': {
          'digest': _sha256Reference(rendition.digest),
          'size_bytes': rendition.byteSize,
          'path': documentFilePath?.call(rendition),
        },
      });
    }
    for (final rendition in mediaRenditions) {
      final path = mediaFilePath?.call(rendition);
      final facts = mediaBlobFacts?[rendition.id];
      final digest = facts?.sha256Hex ?? rendition.mediaSha256;
      final sizeBytes = facts?.sizeBytes ?? rendition.mediaByteSize;
      availableEntries.add({
        'kind': 'media',
        'rendition_id': _sha256Reference(rendition.id),
        'media_kind': rendition.kind.name,
        'media_type': rendition.mediaType,
        'media_id': rendition.mediaId,
        'fingerprint': rendition.fingerprint,
        'blob': {
          'digest': digest == null ? null : _sha256Reference(digest),
          'size_bytes': sizeBytes,
          'path': path,
        },
      });
    }
    return {
      'schema': schema,
      'version': version,
      'created_at_ms': createdAtMs,
      'material': {
        'material_id': materialId,
        'material_revision_id': materialRevisionId,
        'title': materialTitle,
      },
      'edition': {
        'edition_id': editionId,
        'title': editionTitle,
        'target_language': targetLanguage,
        'support_languages': supportLanguages,
      },
      'requested_capability': requestedCapability,
      'available_renditions': availableEntries,
      'attempt_id': ?attemptId,
    };
  }

  /// A stable edition identity for one material: content generations name
  /// the same edition, so repeated equal generations converge.
  static String editionIdFor(String materialId) => 'edition:$materialId';

  /// Wraps a Core 4.0 lowercase hex identity in its `sha256:` reference form.
  static String _sha256Reference(String lowercaseHex) => 'sha256:$lowercaseHex';
}

/// Exact byte facts of one media rendition's local file, used when the Core
/// projection does not carry a digest. The App owns the file, so it can
/// produce the authoritative digest/size itself.
class MediaBlobFacts {
  const MediaBlobFacts({required this.sha256Hex, required this.sizeBytes});

  /// Lowercase hex SHA-256 of the exact file bytes.
  final String sha256Hex;
  final int sizeBytes;
}
