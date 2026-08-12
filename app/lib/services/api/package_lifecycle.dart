part of '../api_service.dart';

// Material package lifecycle (Core 4.0): candidate-only installation,
// installed-edition listing, and explicit Learning Edition adoption. The
// learner intents stay distinct: installation never adopts, adoption is an
// explicit idempotent commit.

extension PackageLifecycleApi on LocalApi {
  /// Installs one local Content Package v3 carrier for the material's current
  /// revision. Candidate only: the release is validated, prepared, and
  /// durably persisted as candidate Learning Resources; nothing is adopted.
  Future<LearningEdition> installMaterialPackage(
    String materialId,
    String packagePath,
  ) async => decodeLearningEdition(
    (await _request(
          'POST',
          '/v1/materials/${Uri.encodeComponent(materialId)}/package-installations',
          {'package_path': packagePath},
        ))
        as Map<String, dynamic>,
  );

  /// Every installed Learning Edition of the material's actual current
  /// revision, ordered by release id with current-adoption evidence.
  Future<List<LearningEdition>> listLearningEditions(
    String materialId,
  ) async => ((await _request(
            'GET',
            '/v1/materials/${Uri.encodeComponent(materialId)}/editions',
          )) as List<dynamic>)
      .map(
        (value) => decodeLearningEdition(
          Map<String, dynamic>.from(value as Map),
        ),
      )
      .toList(growable: false);

  /// Explicitly adopts one installed Package Release for the material's
  /// current revision. Idempotent: re-adopting the current release preserves
  /// the original adoption time.
  Future<LearningEdition> adoptLearningEdition(
    String materialId,
    String releaseId,
  ) async => decodeLearningEdition(
    (await _request(
          'PUT',
          '/v1/materials/${Uri.encodeComponent(materialId)}/edition-adoption',
          {'release_id': releaseId},
        ))
        as Map<String, dynamic>,
  );
}

LearningEdition decodeLearningEdition(Map<String, dynamic> json) =>
    LearningEdition(
      materialId: json['material_id'] as String,
      materialRevisionId: json['material_revision_id'] as String,
      editionId: json['edition_id'] as String,
      releaseId: json['release_id'] as String,
      title: json['title'] as String,
      targetLanguage: json['target_language'] as String,
      supportLanguages: (json['support_languages'] as List<dynamic>)
          .cast<String>(),
      installedAtMs: json['installed_at_ms'] as int,
      adoptedAtMs: json['adopted_at_ms'] as int?,
      adopted: json['adopted'] as bool,
      resources: (json['resources'] as List<dynamic>)
          .map(
            (value) => LearningEditionResource(
              resourceId: (value as Map<String, dynamic>)['resource_id']
                  as String,
              kind: value['kind'] as String,
              role: value['role'] as String,
              required: value['required'] as bool,
              availability: value['availability'] as String,
              reviewStatus: value['review_status'] as String,
              contentLanguage: value['content_language'] as String?,
              supportLanguages:
                  (value['support_languages'] as List<dynamic>).cast<String>(),
            ),
          )
          .toList(growable: false),
      renditions: (json['renditions'] as List<dynamic>)
          .map(
            (value) => LearningEditionRendition(
              renditionId: (value as Map<String, dynamic>)['rendition_id']
                  as String,
              kind: value['kind'] as String,
              available: value['available'] as bool,
            ),
          )
          .toList(growable: false),
    );
