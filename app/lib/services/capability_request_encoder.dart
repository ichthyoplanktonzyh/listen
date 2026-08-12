import '../models/learning_material.dart';

/// Encodes one `listen_gen.capability-request.v2` document. Pure: transport
/// and process knowledge stay in services. Ids follow Core 4.0 domain
/// identity rules; the request wraps them in their `sha256:` reference form.
abstract final class CapabilityRequestEncoder {
  static const schema = 'listen_gen.capability-request.v2';
  static const version = 2;

  /// [documentTextSha256] is the Core 4.0 lowercase hex digest; the request
  /// declares the `sha256:` reference form. [documentTextPath] must be an
  /// absolute readable path carrying exactly those bytes (or null when the
  /// document rendition has no local text).
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
    List<MediaRendition> mediaRenditions = const [],
    String? Function(DocumentRendition rendition)? documentTextPath,
    String? Function(MediaRendition rendition)? mediaFilePath,
    Map<String, MediaBlobFacts>? mediaBlobFacts,
  }) {
    final documentEntries = <Map<String, dynamic>>[];
    for (final rendition in documentRenditions) {
      final path = documentTextPath?.call(rendition);
      // Core 4.0 document renditions without a source asset bind carry no
      // source_asset_id; the rendition's own stable sha256 id anchors the
      // source identity for the package qualification.
      final sourceAssetId = rendition.sourceAssetId ?? rendition.id;
      documentEntries.add({
        'kind': 'document',
        'rendition_id': _sha256Reference(rendition.id),
        'media_type': rendition.mediaType,
        'language': rendition.language,
        'source_asset_id': _sha256Reference(sourceAssetId),
        'blob': {
          'digest': _sha256Reference(rendition.textSha256),
          'size_bytes': rendition.textByteSize,
          'path': path,
        },
      });
    }
    final mediaEntries = <Map<String, dynamic>>[];
    for (final rendition in mediaRenditions) {
      final path = mediaFilePath?.call(rendition);
      final facts = mediaBlobFacts?[rendition.id];
      final digest = facts?.sha256Hex ?? rendition.mediaSha256;
      final sizeBytes = facts?.sizeBytes ?? rendition.mediaByteSize;
      mediaEntries.add({
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
      'available_renditions': [...documentEntries, ...mediaEntries],
      'available_resources': <Object>[],
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

