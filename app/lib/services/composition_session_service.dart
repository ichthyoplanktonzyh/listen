import '../data/repositories/capability_repository.dart';
import '../models/learning_edition.dart';
import 'composition_store.dart';

/// Resolves what the adopted-composition surface needs to render: the adopted
/// edition and its retained composition content. Keeps the presentation layer
/// free of repository and file-system ownership.
class CompositionSessionService {
  CompositionSessionService({
    required this._repository,
    CompositionStore? store,
  }) : _store = store ?? CompositionStore();

  final CapabilityRepository _repository;
  final CompositionStore _store;

  /// The currently adopted edition of one material, or null when nothing is
  /// adopted.
  Future<LearningEdition?> adoptedEdition(String materialId) async {
    final editions = await _repository.listEditions(materialId);
    for (final edition in editions) {
      if (edition.adopted) return edition;
    }
    return null;
  }

  /// The resolved composition content of an edition, or null when the
  /// retained carrier is absent (content resolution degrades honestly).
  Future<ResolvedComposition?> resolveComposition(
    String materialId,
    String releaseId,
  ) => _store.resolve(materialId: materialId, releaseId: releaseId);
}
