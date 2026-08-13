import '../../models/adopted_composition.dart';
import '../../models/api_failure.dart';
import '../../models/learning_edition.dart';
import '../../models/learning_material.dart';
import '../../services/api_service.dart';

/// The Core 4.0 capability + package-lifecycle + adopted-composition surface
/// the coordinator depends on. One seam for the deep completion flow, so
/// tests can drive every state without a live sidecar.
abstract interface class CapabilityRepository {
  ApiFailure failureDetail(Object error);

  Future<MaterialDetails> readMaterial(String materialId);

  Future<List<MaterialCapabilityProjection>> listCapabilities(
    String materialId,
  );

  Future<CapabilityAttempt> startAttempt(
    String materialId,
    String capability,
  );

  Future<CapabilityAttempt> finalizeAttempt({
    required String materialId,
    required String attemptId,
    required bool succeeded,
    String? failureReason,
    String? toolId,
    String? toolVersion,
  });

  Future<LearningEdition> installPackage(
    String materialId,
    String packagePath,
  );

  Future<List<LearningEdition>> listEditions(String materialId);

  Future<LearningEdition> adoptEdition(String materialId, String releaseId);

  /// The resolved current adopted composition of a Material, re-read through
  /// Core. A Material with no adopted composition is a typed not-found.
  Future<AdoptedComposition> readAdoptedComposition(String materialId);

  /// The exact durable payload bytes of one selected resource of the adopted
  /// composition, re-verified by Core.
  Future<List<int>> readCompositionResourcePayload(
    String materialId,
    String resourceId,
  );

  /// The exact durable embedded bytes of one selected rendition of the
  /// adopted composition, re-verified by Core.
  Future<List<int>> readCompositionRenditionBlob(
    String materialId,
    String renditionId,
  );
}

final class LocalCapabilityRepository implements CapabilityRepository {
  LocalCapabilityRepository(this._getApi);

  final LocalApi? Function() _getApi;

  LocalApi? get _api => _getApi();

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);

  @override
  Future<MaterialDetails> readMaterial(String materialId) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.readLearningMaterial(materialId);
  }

  @override
  Future<List<MaterialCapabilityProjection>> listCapabilities(
    String materialId,
  ) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.listMaterialCapabilities(materialId);
  }

  @override
  Future<CapabilityAttempt> startAttempt(
    String materialId,
    String capability,
  ) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.startCapabilityAttempt(materialId, capability);
  }

  @override
  Future<CapabilityAttempt> finalizeAttempt({
    required String materialId,
    required String attemptId,
    required bool succeeded,
    String? failureReason,
    String? toolId,
    String? toolVersion,
  }) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.finalizeCapabilityAttempt(
      materialId: materialId,
      attemptId: attemptId,
      succeeded: succeeded,
      failureReason: failureReason,
      toolId: toolId,
      toolVersion: toolVersion,
    );
  }

  @override
  Future<LearningEdition> installPackage(
    String materialId,
    String packagePath,
  ) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.installMaterialPackage(materialId, packagePath);
  }

  @override
  Future<List<LearningEdition>> listEditions(String materialId) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.listLearningEditions(materialId);
  }

  @override
  Future<LearningEdition> adoptEdition(
    String materialId,
    String releaseId,
  ) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.adoptLearningEdition(materialId, releaseId);
  }

  @override
  Future<AdoptedComposition> readAdoptedComposition(
    String materialId,
  ) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.readAdoptedComposition(materialId);
  }

  @override
  Future<List<int>> readCompositionResourcePayload(
    String materialId,
    String resourceId,
  ) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.readCompositionResourcePayload(materialId, resourceId);
  }

  @override
  Future<List<int>> readCompositionRenditionBlob(
    String materialId,
    String renditionId,
  ) async {
    final api = _api;
    if (api == null) throw const ApiFailure(raw: 'core unavailable');
    return api.readCompositionRenditionBlob(materialId, renditionId);
  }
}
