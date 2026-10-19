part of '../api_service.dart';

// Adopted composition (Core 4.0): the single Core-owned composition
// interface. The App never re-parses a `.listenpkg` to read adopted content;
// every selected resource payload and rendition blob is read back through
// Core, re-verified by it.

extension AdoptedCompositionApi on LocalApi {
  /// Resolves the current adopted composition of a Material: the selected
  /// resources and renditions with their exact digest/size facts and Source
  /// Asset / Media bindings. A Material with no adopted composition is a
  /// typed not-found.
  Future<AdoptedComposition> readAdoptedComposition(String materialId) async =>
      decodeAdoptedComposition(
        (await _request(
              'GET',
              '/v1/materials/${Uri.encodeComponent(materialId)}/composition',
            ))
            as Map<String, dynamic>,
      );

  /// The exact durable payload bytes of one selected resource, re-verified by
  /// Core. Resource payloads are JSON documents.
  Future<List<int>> readCompositionResourcePayload(
    String materialId,
    String resourceId,
  ) async => (await _requestBlob(
    'GET',
    '/v1/materials/${Uri.encodeComponent(materialId)}/composition/resources/'
        '${Uri.encodeComponent(resourceId)}/payload',
  ))!;

  /// The exact durable embedded bytes of one selected rendition, re-verified
  /// by Core. Document/Media rendition blobs are raw bytes.
  Future<List<int>> readCompositionRenditionBlob(
    String materialId,
    String renditionId,
  ) async => (await _requestBlob(
    'GET',
    '/v1/materials/${Uri.encodeComponent(materialId)}/composition/renditions/'
        '${Uri.encodeComponent(renditionId)}/blob',
  ))!;
}

AdoptedComposition decodeAdoptedComposition(Map<String, dynamic> json) =>
    AdoptedComposition(
      materialId: json['material_id'] as String,
      materialRevisionId: json['material_revision_id'] as String,
      releaseId: json['release_id'] as String,
      editionId: json['edition_id'] as String,
      title: json['title'] as String,
      targetLanguage: json['target_language'] as String,
      supportLanguages: (json['support_languages'] as List<dynamic>)
          .cast<String>(),
      adoptedAtMs: json['adopted_at_ms'] as int,
      resources: (json['resources'] as List<dynamic>)
          .map(
            (value) => decodeAdoptedCompositionResource(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
      renditions: (json['renditions'] as List<dynamic>)
          .map(
            (value) => decodeAdoptedCompositionRendition(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
    );

AdoptedCompositionResource decodeAdoptedCompositionResource(
  Map<String, dynamic> json,
) => AdoptedCompositionResource(
  resourceId: json['resource_id'] as String,
  kind: json['kind'] as String,
  schema: json['schema'] as String,
  role: json['role'] as String,
  required: json['required'] as bool,
  availability: json['availability'] as String,
  contentLanguage: json['content_language'] as String?,
  supportLanguages: (json['support_languages'] as List<dynamic>).cast<String>(),
  payloadDigest: json['payload_digest'] as String,
  payloadSizeBytes: json['payload_size_bytes'] as int,
  reviewStatus: json['review_status'] as String,
);

AdoptedCompositionRendition decodeAdoptedCompositionRendition(
  Map<String, dynamic> json,
) => AdoptedCompositionRendition(
  renditionId: json['rendition_id'] as String,
  kind: json['kind'] as String,
  origin: json['origin'] as String,
  mediaType: json['media_type'] as String,
  language: json['language'] as String?,
  digest: json['digest'] as String,
  byteSize: json['byte_size'] as int,
  blobAvailable: json['blob_available'] as bool,
  binding: switch (json['binding']) {
    null => null,
    final binding => decodeAdoptedCompositionBinding(
      Map<String, dynamic>.from(binding as Map),
    ),
  },
  producerToolId: json['producer_tool_id'] as String?,
);

AdoptedCompositionBinding decodeAdoptedCompositionBinding(
  Map<String, dynamic> json,
) => switch (json['type'] as String) {
  'managed_source_asset' => AdoptedCompositionManagedSourceBinding(
    sourceAssetId: json['source_asset_id'] as String,
  ),
  'referenced_source_asset' => AdoptedCompositionReferencedSourceBinding(
    sourceAssetId: json['source_asset_id'] as String,
    reference: json['reference'] as String,
    available: json['available'] as bool,
  ),
  'media' => AdoptedCompositionMediaBinding(
    mediaId: json['media_id'] as String,
  ),
  final other => throw FormatException(
    'unknown composition binding type: $other',
  ),
};
