import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/coach_dashboard_repository.dart';
import '../models/api_failure.dart';
import '../models/coach_dashboard.dart';
import '../models/types.dart';
import '../state/store.dart';

class CoachEvidenceFeed {
  CoachEvidenceFeed({
    List<CoachEvidenceItem> items = const [],
    this.loading = false,
    this.exhausted = false,
    this.failure,
  }) : _items = List.unmodifiable(items);

  final List<CoachEvidenceItem> _items;
  List<CoachEvidenceItem> get items => List.unmodifiable(_items);
  final bool loading;
  final bool exhausted;
  final ApiFailure? failure;
}

class CoachDashboardState {
  CoachDashboardState({
    this.dashboard,
    this.loading = false,
    this.error,
    Map<String, CoachEvidenceFeed> evidence = const {},
    this.calibrationSamples,
    this.calibrationLoading = false,
    this.calibrationFailure,
    this.actionBusy = false,
    this.actionFailure,
  }) : _evidence = Map.unmodifiable(evidence);

  final CoachDashboard? dashboard;
  final bool loading;
  final ApiFailure? error;
  final Map<String, CoachEvidenceFeed> _evidence;
  Map<String, CoachEvidenceFeed> get evidence => Map.unmodifiable(_evidence);
  final List<ContentFitCalibrationSample>? calibrationSamples;
  final bool calibrationLoading;
  final ApiFailure? calibrationFailure;
  final bool actionBusy;
  final ApiFailure? actionFailure;
}

/// Loads Core's listening facts and exposes only explicit learner actions.
class CoachDashboardController extends ChangeNotifier {
  CoachDashboardController(this._repository)
    : _store = Store(CoachDashboardState()) {
    _store.addListener(notifyListeners);
  }

  final CoachDashboardRepository _repository;
  final Store<CoachDashboardState> _store;
  int _generation = 0;
  bool _disposed = false;
  int _days = 7;
  String _language = 'en';

  CoachDashboardState get state => _store.state;

  void _set(CoachDashboardState next) {
    if (_disposed) return;
    _store.replace(next);
  }

  Future<void> load({int days = 7, required String language}) async {
    _days = days.clamp(1, 365);
    _language = language;
    final generation = ++_generation;
    _set(
      CoachDashboardState(
        dashboard: state.dashboard,
        loading: true,
        evidence: state.evidence,
        calibrationSamples: state.calibrationSamples,
        calibrationLoading: state.calibrationLoading,
        calibrationFailure: state.calibrationFailure,
      ),
    );
    try {
      final dashboard = await _repository.loadDashboard(
        days: _days,
      );
      if (!_isCurrent(generation)) return;
      _set(
        CoachDashboardState(
          dashboard: dashboard,
          evidence: state.evidence,
          calibrationSamples: state.calibrationSamples,
          calibrationLoading: state.calibrationLoading,
          calibrationFailure: state.calibrationFailure,
        ),
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _set(
        CoachDashboardState(
          dashboard: state.dashboard,
          evidence: state.evidence,
          calibrationSamples: state.calibrationSamples,
          calibrationLoading: state.calibrationLoading,
          calibrationFailure: state.calibrationFailure,
          error: _repository.failureDetail(error),
        ),
      );
    }
  }

  Future<void> loadEvidencePage(String metric, {int pageSize = 5}) async {
    final previous = state.evidence[metric] ?? CoachEvidenceFeed();
    if (previous.loading || previous.exhausted) return;
    final evidence = Map<String, CoachEvidenceFeed>.of(state.evidence)
      ..[metric] = CoachEvidenceFeed(items: previous.items, loading: true);
    _set(
      CoachDashboardState(
        dashboard: state.dashboard,
        loading: state.loading,
        error: state.error,
        evidence: evidence,
        calibrationSamples: state.calibrationSamples,
        calibrationLoading: state.calibrationLoading,
        calibrationFailure: state.calibrationFailure,
      ),
    );
    try {
      final page = await _repository.loadEvidence(
        metric: metric,
        days: _days,
        limit: pageSize,
        offset: previous.items.length,
      );
      final next = Map<String, CoachEvidenceFeed>.of(state.evidence)
        ..[metric] = CoachEvidenceFeed(
          items: [...previous.items, ...page],
          exhausted: page.length < pageSize,
        );
      _set(
        CoachDashboardState(
          dashboard: state.dashboard,
          loading: state.loading,
          error: state.error,
          evidence: next,
          calibrationSamples: state.calibrationSamples,
          calibrationLoading: state.calibrationLoading,
          calibrationFailure: state.calibrationFailure,
        ),
      );
    } catch (error) {
      final next = Map<String, CoachEvidenceFeed>.of(state.evidence)
        ..[metric] = CoachEvidenceFeed(
          items: previous.items,
          failure: _repository.failureDetail(error),
        );
      _set(
        CoachDashboardState(
          dashboard: state.dashboard,
          loading: state.loading,
          error: state.error,
          evidence: next,
          calibrationSamples: state.calibrationSamples,
          calibrationLoading: state.calibrationLoading,
          calibrationFailure: state.calibrationFailure,
        ),
      );
    }
  }

  Future<void> loadCalibrationSamples() async {
    if (state.calibrationLoading) return;
    _set(
      CoachDashboardState(
        dashboard: state.dashboard,
        loading: state.loading,
        error: state.error,
        evidence: state.evidence,
        calibrationSamples: state.calibrationSamples,
        calibrationLoading: true,
      ),
    );
    try {
      final samples = await _repository.calibrationSamples(language: _language);
      if (_disposed) return;
      _set(
        CoachDashboardState(
          dashboard: state.dashboard,
          loading: state.loading,
          error: state.error,
          evidence: state.evidence,
          calibrationSamples: samples,
        ),
      );
    } catch (error) {
      if (_disposed) return;
      _set(
        CoachDashboardState(
          dashboard: state.dashboard,
          loading: state.loading,
          error: state.error,
          evidence: state.evidence,
          calibrationFailure: _repository.failureDetail(error),
        ),
      );
    }
  }

  Future<ApiFailure?> setMaterialIntent(String mediaId, String? intent) =>
      _runMaterialAction(() => _repository.setMaterialIntent(mediaId, intent));

  Future<ApiFailure?> graduateMaterial(String mediaId) =>
      _runMaterialAction(() => _repository.graduateMaterial(mediaId));

  Future<ApiFailure?> _runMaterialAction(
    Future<Object?> Function() action,
  ) async {
    if (state.actionBusy) return null;
    _set(
      CoachDashboardState(
        dashboard: state.dashboard,
        loading: state.loading,
        error: state.error,
        evidence: state.evidence,
        calibrationSamples: state.calibrationSamples,
        calibrationLoading: state.calibrationLoading,
        calibrationFailure: state.calibrationFailure,
        actionBusy: true,
      ),
    );
    try {
      await action();
      await load(days: _days, language: _language);
      return null;
    } catch (error) {
      final failure = _repository.failureDetail(error);
      _set(
        CoachDashboardState(
          dashboard: state.dashboard,
          loading: state.loading,
          error: state.error,
          evidence: state.evidence,
          calibrationSamples: state.calibrationSamples,
          calibrationLoading: state.calibrationLoading,
          calibrationFailure: state.calibrationFailure,
          actionFailure: failure,
        ),
      );
      return failure;
    } finally {
      if (!_disposed && state.actionBusy) {
        _set(
          CoachDashboardState(
            dashboard: state.dashboard,
            loading: state.loading,
            error: state.error,
            evidence: state.evidence,
            calibrationSamples: state.calibrationSamples,
            calibrationLoading: state.calibrationLoading,
            calibrationFailure: state.calibrationFailure,
            actionFailure: state.actionFailure,
          ),
        );
      }
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _store.dispose();
    super.dispose();
  }
}
