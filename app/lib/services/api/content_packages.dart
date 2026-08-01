part of '../api_service.dart';

extension ContentPackagesApi on LocalApi {
  Future<ContentPackageImportReceipt> importContentPackage(
    String mediaId,
    String packagePath,
  ) async => parseContentPackageImportReceipt(
    (await _request(
          'POST',
          '/v1/media/${Uri.encodeComponent(mediaId)}/content-packages/import',
          {'package_path': packagePath},
        ))
        as Map<String, dynamic>,
  );
}

ContentPackageImportReceipt parseContentPackageImportReceipt(
  Map<String, dynamic> json,
) {
  final receipt = json['receipt'] as Map<String, dynamic>;
  final trackJson = json['track'];
  if (trackJson is! Map<String, dynamic>) {
    throw const FormatException('Content package receipt requires a track');
  }
  return ContentPackageImportReceipt(
    manifestSha256: receipt['manifest_sha256'] as String,
    track: SubtitleTrack.fromJson({
      ...trackJson,
      'sentences':
          trackJson['sentences'] ?? trackJson['cues'] ?? const <Object?>[],
    }),
    resources: (receipt['resources'] as List<dynamic>? ?? const [])
        .map(
          (value) => _parseContentPackageResourceDisposition(
            value as Map<String, dynamic>,
          ),
        )
        .toList(growable: false),
    warnings: (receipt['warnings'] as List<dynamic>? ?? const [])
        .cast<String>(),
  );
}

ContentPackageResourceDisposition _parseContentPackageResourceDisposition(
  Map<String, dynamic> json,
) => ContentPackageResourceDisposition(
  resourceId: json['resource_id'] as String,
  kind: json['kind'] as String,
  outcome: json['outcome'] as String,
  reason: json['reason'] as String?,
  reviewStatus: json['review_status'] as String?,
  provenance: json['provenance'] is Map<String, dynamic>
      ? _parseContentPackageResourceProvenance(
          json['provenance'] as Map<String, dynamic>,
        )
      : null,
  localIds: (json['local_ids'] as List<dynamic>? ?? const []).cast<String>(),
);

ContentPackageResourceProvenance _parseContentPackageResourceProvenance(
  Map<String, dynamic> json,
) => ContentPackageResourceProvenance(
  createdAtMs: json['created_at_ms'] as int,
  tool: _parseContentPackageIdentity(json['tool'])!,
  provider: _parseContentPackageIdentity(json['provider']),
  model: _parseContentPackageIdentity(json['model']),
  configSha256: json['config_sha256'] as String?,
);

ContentPackageProducerIdentity? _parseContentPackageIdentity(Object? value) =>
    value is Map<String, dynamic>
    ? ContentPackageProducerIdentity(
        id: value['id'] as String,
        version: value['version'] as String,
      )
    : null;
