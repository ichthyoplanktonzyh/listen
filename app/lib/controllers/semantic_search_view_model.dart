import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/repositories/semantic_search_repository.dart';
import '../models/named_failure.dart';
import '../models/semantic_embedding.dart';

enum SemanticSearchActivity { installing, indexing }

@immutable
class SemanticSearchState {
  SemanticSearchState({
    this.capability,
    List<SemanticSearchHitView> hits = const [],
    this.busy = true,
    this.activity,
    this.failure,
  }) : _hits = List.unmodifiable(hits);

  final SemanticEmbeddingCapabilityView? capability;
  final List<SemanticSearchHitView> _hits;
  List<SemanticSearchHitView> get hits => List.unmodifiable(_hits);
  final bool busy;
  final SemanticSearchActivity? activity;
  final NamedFailure? failure;
}

class SemanticSearchViewModel extends ChangeNotifier {
  SemanticSearchViewModel(this._repository);

  final SemanticSearchRepository _repository;
  SemanticSearchState _state = SemanticSearchState();
  int _generation = 0;
  bool _disposed = false;

  SemanticSearchState get state => _state;
  UnmodifiableListView<SemanticSearchHitView> get hits =>
      UnmodifiableListView(_state.hits);

  Future<void> loadCapability() => _capabilityAction(
    request: _repository.capability,
    failureKey: 'semanticSearchCapabilityUnavailable',
  );

  Future<void> install() => _capabilityAction(
    request: _repository.install,
    failureKey: 'semanticSearchInstallFailed',
    activity: SemanticSearchActivity.installing,
  );

  Future<void> rebuild() => _capabilityAction(
    request: _repository.rebuild,
    failureKey: 'semanticSearchRebuildFailed',
    activity: SemanticSearchActivity.indexing,
  );

  Future<void> disable() => _capabilityAction(
    request: _repository.disable,
    failureKey: 'semanticSearchToggleFailed',
    clearHits: true,
  );

  Future<void> enable() => _capabilityAction(
    request: _repository.enable,
    failureKey: 'semanticSearchToggleFailed',
  );

  Future<void> uninstall() => _capabilityAction(
    request: _repository.uninstall,
    failureKey: 'semanticSearchUninstallFailed',
    clearHits: true,
  );

  Future<void> search({required String query, required String language}) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;
    final generation = ++_generation;
    _publish(
      SemanticSearchState(
        capability: _state.capability,
        hits: _state.hits,
        failure: null,
      ),
    );
    try {
      final result = await _repository.search(
        query: normalizedQuery,
        language: language,
      );
      if (!_isCurrent(generation)) return;
      _publish(
        SemanticSearchState(
          capability: result.capability,
          hits: List.unmodifiable(result.hits),
          busy: false,
        ),
      );
    } catch (thrown) {
      _publishFailureIfCurrent(generation, 'semanticSearchQueryFailed', thrown);
    }
  }

  Future<void> _capabilityAction({
    required Future<SemanticEmbeddingCapabilityView> Function() request,
    required String failureKey,
    SemanticSearchActivity? activity,
    bool clearHits = false,
  }) async {
    final generation = ++_generation;
    _publish(
      SemanticSearchState(
        capability: _state.capability,
        hits: _state.hits,
        activity: activity,
      ),
    );
    try {
      final capability = await request();
      if (!_isCurrent(generation)) return;
      _publish(
        SemanticSearchState(
          capability: capability,
          hits: clearHits ? const [] : _state.hits,
          busy: false,
        ),
      );
    } catch (thrown) {
      _publishFailureIfCurrent(generation, failureKey, thrown);
    }
  }

  void _publishFailureIfCurrent(
    int generation,
    String messageKey,
    Object thrown,
  ) {
    if (!_isCurrent(generation)) return;
    _publish(
      SemanticSearchState(
        capability: _state.capability,
        hits: _state.hits,
        busy: false,
        failure: NamedFailure(
          messageKey,
          detail: thrown is SemanticSearchRepositoryFailure
              ? thrown.detail
              : null,
        ),
      ),
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _publish(SemanticSearchState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
