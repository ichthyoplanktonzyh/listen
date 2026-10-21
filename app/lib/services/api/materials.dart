part of '../api_service.dart';

// Learning-material lifecycle (Core 5.0). All JSON decode/encode for the
// material models lives here — the models themselves stay pure.

extension LearningMaterialApi on LocalApi {
  /// Lists Personal Library materials only: every retained learning material
  /// with its actual current revision and composition shape.
  Future<List<MaterialDetails>> listLearningMaterials() async =>
      ((await _request('GET', '/v1/materials')) as List<dynamic>)
          .map(
            (value) =>
                decodeMaterialDetails(Map<String, dynamic>.from(value as Map)),
          )
          .toList(growable: false);

  /// Creates (or converges on) a media learning material from registered
  /// Media Renditions.
  ///
  /// [retain] is a typed [MaterialRetainDirective] and is transmitted honestly:
  /// [MaterialRetainOmitted] (the default) leaves the key absent and an
  /// explicit [MaterialRetainExplicit] sends its nullable value as
  /// `"retain": …`. Both omission and an explicit `null` use Core's retained
  /// default; only an explicit `false` creates Temporary Material — readable
  /// by id and resolvable from media, but absent from the material library
  /// until explicitly retained. None of the states is ever coerced into
  /// another.
  Future<MaterialDetails> createLearningMaterial(
    CreateLearningMaterialInput input, {
    MaterialRetainDirective retain = const MaterialRetainOmitted(),
  }) async {
    final body = <String, dynamic>{
      'title': input.title,
      'media_renditions': [
        for (final rendition in input.mediaRenditions)
          encodeMediaRenditionInput(rendition),
      ],
    };
    switch (retain) {
      case MaterialRetainOmitted():
        break;
      case MaterialRetainExplicit(:final value):
        body['retain'] = value;
    }
    return decodeMaterialDetails(
      (await _request('POST', '/v1/materials', body)) as Map<String, dynamic>,
    );
  }

  /// Reads a learning material with its actual current revision and shape.
  /// Temporary Material is readable here.
  Future<MaterialDetails> readLearningMaterial(String materialId) async =>
      decodeMaterialDetails(
        (await _request(
              'GET',
              '/v1/materials/${Uri.encodeComponent(materialId)}',
            ))
            as Map<String, dynamic>,
      );

  /// Appends a new immutable revision to an existing material using the same
  /// typed inputs as creation.
  Future<MaterialDetails> appendMaterialRevision(
    String materialId,
    AppendMaterialRevisionInput input,
  ) async {
    return decodeMaterialDetails(
      (await _request(
            'POST',
            '/v1/materials/${Uri.encodeComponent(materialId)}/revisions',
            {
              'title': input.title,
              'media_renditions': [
                for (final rendition in input.mediaRenditions)
                  encodeMediaRenditionInput(rendition),
              ],
            },
          ))
          as Map<String, dynamic>,
    );
  }

  /// Reads one historical or current revision, only when it belongs to the
  /// requested material.
  Future<MaterialRevision> readMaterialRevision(
    String materialId,
    String revisionId,
  ) async => decodeMaterialRevision(
    (await _request(
          'GET',
          '/v1/materials/${Uri.encodeComponent(materialId)}/revisions/'
              '${Uri.encodeComponent(revisionId)}',
        ))
        as Map<String, dynamic>,
  );

  /// Adds an existing learning material to the Personal Library. Idempotent:
  /// retaining an already-retained material preserves the original membership
  /// timestamp and changes nothing else.
  Future<MaterialDetails> retainLearningMaterial(String materialId) async =>
      decodeMaterialDetails(
        (await _request(
              'PUT',
              '/v1/materials/${Uri.encodeComponent(materialId)}'
                  '/library-membership',
            ))
            as Map<String, dynamic>,
      );

  /// Removes an existing learning material from the Personal Library.
  /// Membership only: the material stays readable, and its revisions, media
  /// bindings, resources, and learner state are untouched.
  Future<MaterialDetails> unretainLearningMaterial(String materialId) async =>
      decodeMaterialDetails(
        (await _request(
              'DELETE',
              '/v1/materials/${Uri.encodeComponent(materialId)}'
                  '/library-membership',
            ))
            as Map<String, dynamic>,
      );

  /// Projects the Material's capability state for every capability:
  /// `available`, `derivable`, `generating`, `unavailable`, or
  /// `failed_attempt`, each with the latest durable attempt (when any).
  Future<List<MaterialCapabilityProjection>> listMaterialCapabilities(
    String materialId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/materials/${Uri.encodeComponent(materialId)}/capabilities',
              ))
              as List<dynamic>)
          .map(
            (value) => decodeMaterialCapabilityProjection(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false);

  /// Resolves the learning material bound to a media source, with the
  /// material's actual current revision and shape. Registered media resolve
  /// immediately; a media source with no bound material is a typed not-found.
  Future<MaterialDetails> resolveMaterialForMedia(String mediaId) async =>
      decodeMaterialDetails(
        (await _request(
              'GET',
              '/v1/media/${Uri.encodeComponent(mediaId)}/material',
            ))
            as Map<String, dynamic>,
      );
}

/// Decodes a Core 5.0 [MaterialDetails] response. Transport knowledge stays in
/// the service layer; [MaterialDetails] itself is a pure model.
MaterialDetails decodeMaterialDetails(Map<String, dynamic> json) =>
    MaterialDetails(
      material: decodeLearningMaterial(
        Map<String, dynamic>.from(json['material'] as Map),
      ),
      currentRevision: decodeMaterialRevision(
        Map<String, dynamic>.from(json['current_revision'] as Map),
      ),
      shape: decodeMaterialShape(json['shape'] as String),
    );

LearningMaterial decodeLearningMaterial(Map<String, dynamic> json) =>
    LearningMaterial(
      id: json['id'] as String,
      currentRevisionId: json['current_revision_id'] as String,
      // Required-but-nullable: every response states known membership, and
      // null means Temporary Material. Never coerced to a boolean.
      retainedAtMs: json['retained_at_ms'] as int?,
      createdAtMs: json['created_at_ms'] as int,
      updatedAtMs: json['updated_at_ms'] as int,
    );

MaterialRevision decodeMaterialRevision(Map<String, dynamic> json) =>
    MaterialRevision(
      id: json['id'] as String,
      materialId: json['material_id'] as String,
      title: json['title'] as String,
      mediaRenditions: (json['media_renditions'] as List<dynamic>)
          .map(
            (value) =>
                decodeMediaRendition(Map<String, dynamic>.from(value as Map)),
          )
          .toList(growable: false),
      createdAtMs: json['created_at_ms'] as int,
    );

MediaRendition decodeMediaRendition(Map<String, dynamic> json) =>
    MediaRendition(
      id: json['id'] as String,
      origin: decodeRenditionOrigin(json['origin'] as String),
      kind: decodeMediaRenditionKind(json['kind'] as String),
      mediaType: json['media_type'] as String,
      fingerprint: json['fingerprint'] as String,
      availability: decodeMediaRenditionAvailability(
        json['availability'] as String,
      ),
      mediaId: json['media_id'] as String?,
      mediaSha256: json['media_sha256'] as String?,
      mediaByteSize: json['media_byte_size'] as int?,
    );

RenditionOrigin decodeRenditionOrigin(String value) => switch (value) {
  'source' => RenditionOrigin.source,
  'derived' => RenditionOrigin.derived,
  final other => throw FormatException('unknown rendition origin: $other'),
};

MaterialShape decodeMaterialShape(String value) => switch (value) {
  'audio' => MaterialShape.audio,
  'video' => MaterialShape.video,
  'mixed' => MaterialShape.mixed,
  final other => throw FormatException('unknown material shape: $other'),
};

MediaRenditionKind decodeMediaRenditionKind(String value) => switch (value) {
  'video' => MediaRenditionKind.video,
  'audio' => MediaRenditionKind.audio,
  final other => throw FormatException('unknown media rendition kind: $other'),
};

MediaRenditionAvailability decodeMediaRenditionAvailability(String value) =>
    switch (value) {
      'available' => MediaRenditionAvailability.available,
      'missing' => MediaRenditionAvailability.missing,
      'archived' => MediaRenditionAvailability.archived,
      final other => throw FormatException(
        'unknown media rendition availability: $other',
      ),
    };

Map<String, dynamic> encodeMediaRenditionInput(MediaRenditionInput input) => {
  'media_id': input.mediaId,
};

MaterialCapabilityProjection decodeMaterialCapabilityProjection(
  Map<String, dynamic> json,
) => MaterialCapabilityProjection(
  capability: decodeMaterialCapability(json['capability'] as String),
  status: decodeMaterialCapabilityStatus(json['status'] as String),
  latestAttempt: switch (json['latest_attempt']) {
    null => null,
    final attempt => decodeCapabilityAttempt(
      Map<String, dynamic>.from(attempt as Map),
    ),
  },
);

MaterialCapability decodeMaterialCapability(String value) => switch (value) {
  'read' => MaterialCapability.read,
  'listen' => MaterialCapability.listen,
  'watch' => MaterialCapability.watch,
  'synchronized_read_listen' => MaterialCapability.synchronizedReadListen,
  final other => throw FormatException('unknown material capability: $other'),
};

MaterialCapabilityStatus decodeMaterialCapabilityStatus(String value) =>
    switch (value) {
      'available' => MaterialCapabilityStatus.available,
      'derivable' => MaterialCapabilityStatus.derivable,
      'generating' => MaterialCapabilityStatus.generating,
      'unavailable' => MaterialCapabilityStatus.unavailable,
      'failed_attempt' => MaterialCapabilityStatus.failedAttempt,
      final other => throw FormatException(
        'unknown material capability status: $other',
      ),
    };

CapabilityAttempt decodeCapabilityAttempt(Map<String, dynamic> json) =>
    CapabilityAttempt(
      attemptId: json['attempt_id'] as String,
      status: json['status'] as String,
      startedAtMs: json['started_at_ms'] as int,
      finishedAtMs: json['finished_at_ms'] as int?,
      failureReason: json['failure_reason'] as String?,
      producerToolId: json['producer_tool_id'] as String?,
      producerToolVersion: json['producer_tool_version'] as String?,
    );
