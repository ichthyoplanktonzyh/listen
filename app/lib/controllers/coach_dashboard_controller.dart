import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/repositories/coach_dashboard_repository.dart';
import '../models/coach_dashboard.dart';
import '../models/named_failure.dart';
import '../state/store.dart';

@immutable
class CoachEvidenceFeed {
  CoachEvidenceFeed({
    List<CoachEvidenceItem> items = const [],
    this.loading = false,
    this.failure,
    this.exhausted = false,
  }) : _items = List.unmodifiable(items);

  final List<CoachEvidenceItem> _items;
  List<CoachEvidenceItem> get items => List.unmodifiable(_items);
  final bool loading;
  final NamedFailure? failure;
  final bool exhausted;
}

@immutable
class CoachDashboardState {
  CoachDashboardState({
    this.dashboard,
    this.loading = false,
    this.error,
    Map<String, CoachEvidenceFeed> evidence = const {},
    this.materialFailure,
  }) : _evidence = Map.unmodifiable(evidence);

  final CoachDashboard? dashboard;
  final bool loading;
  final String? error;
  final Map<String, CoachEvidenceFeed> _evidence;
  Map<String, CoachEvidenceFeed> get evidence => Map.unmodifiable(_evidence);
  final NamedFailure? materialFailure;
}

class CoachDashboardController extends ChangeNotifier {
  CoachDashboardController(this._repository)
    : store = Store(CoachDashboardState()) {
    store.addListener(notifyListeners);
  }

  final CoachDashboardRepository _repository;
  final Store<CoachDashboardState> store;
  int _generation = 0;
  final _evidenceGenerations = <String, int>{};
  bool _disposed = false;
  int _days = 7;
  String _language = 'en';

  CoachDashboardState get state => store.state;
  UnmodifiableMapView<String, CoachEvidenceFeed> get evidence =>
      UnmodifiableMapView(state.evidence);

  Future<void> load({int days = 7, String language = 'en'}) async {
    _days = days;
    _language = language;
    final generation = ++_generation;
    final settledEvidence = _withoutEvidenceLoading();
    _replace(
      CoachDashboardState(
        dashboard: state.dashboard,
        loading: true,
        evidence: settledEvidence,
      ),
    );
    try {
      final dashboard = await _repository.loadDashboard(
        days: days,
        language: language,
      );
      if (!_isCurrent(generation)) return;
      _replace(
        CoachDashboardState(dashboard: dashboard, evidence: state.evidence),
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _replace(
        CoachDashboardState(
          error: 'coachDashboardLoadFailed',
          evidence: state.evidence,
        ),
      );
    }
  }

  Future<bool> graduateMaterial(String mediaId) =>
      _changeMaterial(request: () => _repository.graduateMaterial(mediaId));

  Future<bool> setMaterialIntent(String mediaId, String? intent) =>
      _changeMaterial(
        request: () => _repository.setMaterialIntent(mediaId, intent),
      );

  Future<bool> _changeMaterial({
    required Future<void> Function() request,
  }) async {
    final generation = ++_generation;
    final settledEvidence = _withoutEvidenceLoading();
    _replace(
      CoachDashboardState(
        dashboard: state.dashboard,
        loading: state.loading,
        evidence: settledEvidence,
      ),
    );
    try {
      await request();
      if (!_isCurrent(generation)) return false;
      await load(days: _days, language: _language);
      return !_disposed && state.error == null;
    } catch (thrown) {
      if (!_isCurrent(generation)) return false;
      _replace(
        CoachDashboardState(
          dashboard: state.dashboard,
          evidence: state.evidence,
          materialFailure: NamedFailure(
            'coachMaterialActionFailed',
            detail: thrown is CoachDashboardRepositoryFailure
                ? thrown.detail
                : null,
          ),
        ),
      );
      return false;
    }
  }

  Future<void> loadEvidencePage(String metricKey, {int pageSize = 5}) async {
    final current = state.evidence[metricKey] ?? CoachEvidenceFeed();
    if (current.loading || current.exhausted) return;
    final dashboardGeneration = _generation;
    final metricGeneration = (_evidenceGenerations[metricKey] ?? 0) + 1;
    _evidenceGenerations[metricKey] = metricGeneration;
    _setEvidence(
      metricKey,
      CoachEvidenceFeed(items: current.items, loading: true),
    );
    try {
      final page = await _repository.loadEvidence(
        metric: metricKey,
        days: _days,
        limit: pageSize,
        offset: current.items.length,
      );
      if (!_isEvidenceCurrent(
        metricKey,
        dashboardGeneration,
        metricGeneration,
      )) {
        return;
      }
      _setEvidence(
        metricKey,
        CoachEvidenceFeed(
          items: List.unmodifiable([...current.items, ...page]),
          exhausted: page.length < pageSize,
        ),
      );
    } catch (thrown) {
      if (!_isEvidenceCurrent(
        metricKey,
        dashboardGeneration,
        metricGeneration,
      )) {
        return;
      }
      _setEvidence(
        metricKey,
        CoachEvidenceFeed(
          items: current.items,
          failure: NamedFailure(
            'coachEvidenceFailed',
            detail: thrown is CoachDashboardRepositoryFailure
                ? thrown.detail
                : null,
          ),
        ),
      );
    }
  }

  void _setEvidence(String metricKey, CoachEvidenceFeed feed) {
    final evidence = Map<String, CoachEvidenceFeed>.unmodifiable({
      ...state.evidence,
      metricKey: feed,
    });
    _replace(
      CoachDashboardState(
        dashboard: state.dashboard,
        loading: state.loading,
        error: state.error,
        evidence: evidence,
        materialFailure: state.materialFailure,
      ),
    );
  }

  Map<String, CoachEvidenceFeed> _withoutEvidenceLoading() =>
      Map<String, CoachEvidenceFeed>.unmodifiable({
        for (final entry in state.evidence.entries)
          entry.key: entry.value.loading
              ? CoachEvidenceFeed(
                  items: entry.value.items,
                  failure: entry.value.failure,
                  exhausted: entry.value.exhausted,
                )
              : entry.value,
      });

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _isEvidenceCurrent(
    String metricKey,
    int dashboardGeneration,
    int metricGeneration,
  ) =>
      _isCurrent(dashboardGeneration) &&
      _evidenceGenerations[metricKey] == metricGeneration;

  void _replace(CoachDashboardState state) {
    if (_disposed) return;
    store.replace(state);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _evidenceGenerations.clear();
    store.removeListener(notifyListeners);
    store.dispose();
    super.dispose();
  }
}
