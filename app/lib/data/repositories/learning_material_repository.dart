import '../../models/api_failure.dart';
import '../../models/learning_material.dart';
import '../../services/api_service.dart';

Future<T> _request<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(describeApiFailure(error), stackTrace);
  }
}

/// The learning-material boundary used by the media session and future
/// material surfaces.
///
/// This interface mirrors the Core 3.2 learning-material surface exactly and
/// keeps its callers independent of transport details: every failed operation
/// throws a typed [ApiFailure], never a transport error.
abstract interface class LearningMaterialRepository {
  bool get isAvailable;

  /// Typed view of a failed operation for surfaces that catch it themselves.
  ApiFailure failureDetail(Object error);

  /// Lists Personal Library materials only (retained materials with their
  /// current revisions). Temporary Material is absent here.
  Future<List<MaterialDetails>> listLearningMaterials();

  /// Creates (or converges on) a learning material. [retain] is a typed
  /// directive: omission/null are the retained Core default, explicit `false`
  /// creates Temporary Material — transmitted honestly, never coerced.
  Future<MaterialDetails> createLearningMaterial(
    CreateLearningMaterialInput input, {
    MaterialRetainDirective retain = const MaterialRetainOmitted(),
  });

  /// Reads a learning material with its actual current revision and shape.
  /// Temporary Material is readable here.
  Future<MaterialDetails> readLearningMaterial(String materialId);

  /// Appends a new immutable revision to an existing material.
  Future<MaterialDetails> appendMaterialRevision(
    String materialId,
    AppendMaterialRevisionInput input,
  );

  /// Reads one historical or current revision owned by the material.
  Future<MaterialRevision> readMaterialRevision(
    String materialId,
    String revisionId,
  );

  /// Adds an existing material to the Personal Library (idempotent).
  Future<MaterialDetails> retainLearningMaterial(String materialId);

  /// Removes an existing material from the Personal Library. Membership only:
  /// revisions, media bindings, resources, and learner state are untouched.
  Future<MaterialDetails> unretainLearningMaterial(String materialId);

  /// Resolves the learning material bound to a media source.
  Future<MaterialDetails> resolveMaterialForMedia(String mediaId);
}

/// Production implementation backed by the typed local API client.
final class LocalLearningMaterialRepository
    implements LearningMaterialRepository {
  LocalLearningMaterialRepository(this._getApi);

  final LocalApi? Function() _getApi;
  LocalApi get _api =>
      _getApi() ?? (throw StateError('Learning material API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);

  @override
  Future<List<MaterialDetails>> listLearningMaterials() =>
      _request(() => _api.listLearningMaterials());

  @override
  Future<MaterialDetails> createLearningMaterial(
    CreateLearningMaterialInput input, {
    MaterialRetainDirective retain = const MaterialRetainOmitted(),
  }) => _request(() => _api.createLearningMaterial(input, retain: retain));

  @override
  Future<MaterialDetails> readLearningMaterial(String materialId) =>
      _request(() => _api.readLearningMaterial(materialId));

  @override
  Future<MaterialDetails> appendMaterialRevision(
    String materialId,
    AppendMaterialRevisionInput input,
  ) => _request(() => _api.appendMaterialRevision(materialId, input));

  @override
  Future<MaterialRevision> readMaterialRevision(
    String materialId,
    String revisionId,
  ) => _request(() => _api.readMaterialRevision(materialId, revisionId));

  @override
  Future<MaterialDetails> retainLearningMaterial(String materialId) =>
      _request(() => _api.retainLearningMaterial(materialId));

  @override
  Future<MaterialDetails> unretainLearningMaterial(String materialId) =>
      _request(() => _api.unretainLearningMaterial(materialId));

  @override
  Future<MaterialDetails> resolveMaterialForMedia(String mediaId) =>
      _request(() => _api.resolveMaterialForMedia(mediaId));
}
