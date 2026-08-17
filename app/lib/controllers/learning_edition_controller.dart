import 'package:flutter/foundation.dart';

import '../data/repositories/capability_repository.dart';
import '../models/learning_edition.dart';

/// Loads and adopts immutable learning-package editions for one Material.
///
/// The controller deliberately exposes no resource mutation API. A resource
/// belongs to an immutable package release; the only learner choice is which
/// installed release the Material adopts.
class LearningEditionController extends ChangeNotifier {
  LearningEditionController({required this.repository, this.onAdopted});

  final CapabilityRepository repository;
  final Future<void> Function()? onAdopted;

  String? _materialId;
  List<LearningEdition> _editions = const [];
  bool _loading = false;
  bool _failed = false;
  String? _adoptingReleaseId;
  int _generation = 0;
  bool _disposed = false;

  String? get materialId => _materialId;
  List<LearningEdition> get editions => List.unmodifiable(_editions);
  bool get loading => _loading;
  bool get failed => _failed;
  String? get adoptingReleaseId => _adoptingReleaseId;

  LearningEdition? get adoptedEdition {
    for (final edition in _editions) {
      if (edition.adopted) return edition;
    }
    return null;
  }

  Future<void> load(String materialId) async {
    final generation = ++_generation;
    _materialId = materialId;
    _loading = true;
    _failed = false;
    _adoptingReleaseId = null;
    _editions = const [];
    _publish();
    await _readEditions(materialId, generation);
  }

  Future<void> refresh() async {
    final materialId = _materialId;
    if (materialId == null) return;
    final generation = ++_generation;
    _loading = true;
    _failed = false;
    _publish();
    await _readEditions(materialId, generation);
  }

  Future<void> adopt(LearningEdition edition) async {
    final materialId = _materialId;
    if (materialId == null || edition.adopted || _adoptingReleaseId != null) {
      return;
    }
    final generation = ++_generation;
    _adoptingReleaseId = edition.releaseId;
    _failed = false;
    _publish();
    try {
      await repository.adoptEdition(materialId, edition.releaseId);
      if (!_isCurrent(materialId, generation)) return;
      await onAdopted?.call();
      if (!_isCurrent(materialId, generation)) return;
      _editions = await repository.listEditions(materialId);
      if (!_isCurrent(materialId, generation)) return;
    } on Object {
      if (!_isCurrent(materialId, generation)) return;
      _failed = true;
    } finally {
      if (_isCurrent(materialId, generation)) {
        _adoptingReleaseId = null;
        _loading = false;
        _publish();
      }
    }
  }

  Future<void> _readEditions(String materialId, int generation) async {
    try {
      final editions = await repository.listEditions(materialId);
      if (!_isCurrent(materialId, generation)) return;
      _editions = editions;
    } on Object {
      if (!_isCurrent(materialId, generation)) return;
      _editions = const [];
      _failed = true;
    } finally {
      if (_isCurrent(materialId, generation)) {
        _loading = false;
        _publish();
      }
    }
  }

  bool _isCurrent(String materialId, int generation) =>
      !_disposed && _materialId == materialId && _generation == generation;

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
