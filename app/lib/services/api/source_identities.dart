part of '../api_service.dart';

// Source Identity (Core 4.0): mapping a discovered item's source-scoped
// canonical key to the exact Material Revision it resolved to, and resolving
// it back. The canonical key is the only match identity; everything else in
// the mapping is typed evidence carried along, never substituted for the key.

extension SourceIdentityApi on LocalApi {
  /// Records (or updates) the mapping of a discovered item's canonical key
  /// (source identity + item identity) to an exact Material Revision.
  ///
  /// Used after intake converges on a Material, so a later refresh of the
  /// same feed item resolves the same Material instead of creating a second
  /// one.
  Future<SourceIdentityMapping> registerSourceIdentityMapping({
    required String sourceId,
    required String itemId,
    required List<SourceItemEvidence> evidence,
    required String materialId,
    required String materialRevisionId,
  }) async {
    final body = <String, dynamic>{
      'source_id': sourceId,
      'item_id': itemId,
      'evidence': {
        'feed_item_id': _evidenceOf(SourceItemEvidenceKind.feedItemId, evidence),
        'entry_url':
            ?_evidenceOf(SourceItemEvidenceKind.entryUrl, evidence),
        'enclosure_urls': [
          ?_evidenceOf(SourceItemEvidenceKind.enclosureUrl, evidence),
        ],
        'file_sha256':
            ?_evidenceOf(SourceItemEvidenceKind.byteFingerprint, evidence),
        'title': ?_evidenceOf(SourceItemEvidenceKind.title, evidence),
      },
      'material_id': materialId,
      'material_revision_id': materialRevisionId,
      'mapped_at_ms': DateTime.now().millisecondsSinceEpoch,
    };
    return _decodeSourceIdentityMapping(
      (await _request('POST', '/v1/source-identities/mappings', body))
          as Map<String, dynamic>,
    );
  }

  /// Resolves a discovered item's canonical key to its recorded mapping, or
  /// null when none is recorded.
  Future<SourceIdentityMapping?> resolveSourceIdentity({
    required String sourceId,
    required String itemId,
  }) async {
    final dynamic response;
    try {
      response = await _request(
        'GET',
        '/v1/source-identities/resolve?source_id='
        '${Uri.encodeQueryComponent(sourceId)}'
        '&item_id=${Uri.encodeQueryComponent(itemId)}',
      );
    } on HttpException catch (error) {
      // An unrecorded key is a typed not-found, not a transport failure: the
      // body carries `{"code":"not_found",…}`. Anything else is a real error
      // and must surface as one.
      try {
        final body = jsonDecode(error.message);
        if (body is Map<String, dynamic> && body['code'] == 'not_found') {
          return null;
        }
      } on FormatException {
        // Not a JSON error body; fall through and rethrow.
      }
      rethrow;
    }
    if (response is Map<String, dynamic>) {
      return _decodeSourceIdentityMapping(response);
    }
    return null;
  }

  static String? _evidenceOf(
    SourceItemEvidenceKind kind,
    List<SourceItemEvidence> evidence,
  ) {
    for (final field in evidence) {
      if (field.kind == kind && field.value.isNotEmpty) return field.value;
    }
    return null;
  }
}

/// Wire decode of a Source Identity mapping.
///
/// A missing or non-string key is not a mapping this app can act on; the
/// resolve path turns that into "no mapping" rather than a guess, and the
/// register path throws because a register response echoes the mapping it
/// stored.
SourceIdentityMapping? _decodeSourceIdentityMappingOrNull(
  Map<String, dynamic> json,
) {
  final sourceId = json['source_id'];
  final itemId = json['item_id'];
  final materialId = json['material_id'];
  final materialRevisionId = json['material_revision_id'];
  if (sourceId is! String ||
      itemId is! String ||
      materialId is! String ||
      materialRevisionId is! String) {
    return null;
  }
  return SourceIdentityMapping(
    sourceId: sourceId,
    itemId: itemId,
    evidence: _decodeEvidence(json['evidence']),
    materialId: materialId,
    materialRevisionId: materialRevisionId,
    mappedAtMs: json['mapped_at_ms'] is int ? json['mapped_at_ms'] as int : 0,
  );
}

SourceIdentityMapping _decodeSourceIdentityMapping(Map<String, dynamic> json) {
  final mapping = _decodeSourceIdentityMappingOrNull(json);
  if (mapping == null) {
    throw const FormatException('response is not a source identity mapping');
  }
  return mapping;
}

List<SourceItemEvidence> _decodeEvidence(Object? raw) {
  if (raw is! Map<dynamic, dynamic>) return const [];
  final evidence = <SourceItemEvidence>[];
  void add(SourceItemEvidenceKind kind, Object? value) {
    if (value is String && value.isNotEmpty) {
      evidence.add(SourceItemEvidence(kind, value));
    }
  }

  add(SourceItemEvidenceKind.feedItemId, raw['feed_item_id']);
  add(SourceItemEvidenceKind.entryUrl, raw['entry_url']);
  if (raw['enclosure_urls'] is List<dynamic>) {
    for (final url in raw['enclosure_urls'] as List<dynamic>) {
      add(SourceItemEvidenceKind.enclosureUrl, url);
    }
  }
  add(SourceItemEvidenceKind.byteFingerprint, raw['file_sha256']);
  add(SourceItemEvidenceKind.title, raw['title']);
  return List.unmodifiable(evidence);
}
