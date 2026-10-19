import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/phonetic_analysis_repository.dart';
import '../models/named_failure.dart';
import '../models/runtime_resources.dart';

@immutable
class PhoneticAnalysisState {
  PhoneticAnalysisState({
    List<PhoneticProviderView> providers = const [],
    List<PhoneticModelView> models = const [],
    List<PhoneticJobView> jobs = const [],
    this.failure,
  }) : providers = List.unmodifiable(providers),
       models = List.unmodifiable(models),
       jobs = List.unmodifiable(jobs);

  final List<PhoneticProviderView> providers;
  final List<PhoneticModelView> models;
  final List<PhoneticJobView> jobs;
  final NamedFailure? failure;
}

class PhoneticAnalysisViewModel extends ChangeNotifier {
  PhoneticAnalysisViewModel(this._repository);

  final PhoneticAnalysisRepository _repository;
  PhoneticAnalysisState _state = PhoneticAnalysisState();
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  PhoneticAnalysisState get state => _state;
  bool get hasActiveJobs => _state.jobs.any((job) => isActive(job.status));
  bool get hasTerminalJobs => _state.jobs.any((job) => isTerminal(job.status));

  Future<void> start() async {
    await refresh();
    _scheduleTimer();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    try {
      final values = await Future.wait([
        _repository.providers(),
        _repository.models(),
        _repository.jobs(),
      ]);
      if (_disposed || generation != _generation) return;
      final hadActive = hasActiveJobs;
      _publish(
        PhoneticAnalysisState(
          providers: values[0] as List<PhoneticProviderView>,
          models: values[1] as List<PhoneticModelView>,
          jobs: values[2] as List<PhoneticJobView>,
        ),
      );
      if (hadActive != hasActiveJobs) _scheduleTimer();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _publish(
        PhoneticAnalysisState(
          providers: _state.providers,
          models: _state.models,
          jobs: _state.jobs,
          failure: NamedFailure(
            'phoneticAnalysisLoadFailed',
            detail: _repository.failureDetail(error),
          ),
        ),
      );
    }
  }

  Future<void> installModel(String id) => _run(
    () => _repository.installModel(id),
    failureKey: 'phoneticModelInstallFailed',
  );
  Future<void> cancelJob(String id) => _run(() => _repository.cancelJob(id));
  Future<void> retryJob(String id) => _run(() => _repository.retryJob(id));
  Future<void> deleteJob(String id) => _run(() => _repository.deleteJob(id));
  Future<void> clearTerminalJobs() => _run(_repository.clearTerminalJobs);

  Future<void> _run(
    Future<void> Function() command, {
    String failureKey = 'phoneticAnalysisLoadFailed',
  }) async {
    try {
      await command();
      await refresh();
    } catch (error) {
      _publish(
        PhoneticAnalysisState(
          providers: _state.providers,
          models: _state.models,
          jobs: _state.jobs,
          failure: NamedFailure(
            failureKey,
            detail: _repository.failureDetail(error),
          ),
        ),
      );
    }
  }

  void _scheduleTimer() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer.periodic(
      hasActiveJobs ? const Duration(seconds: 1) : const Duration(seconds: 5),
      (_) => unawaited(refresh()),
    );
  }

  void _publish(PhoneticAnalysisState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  static bool isActive(String status) => const {
    'queued',
    'extracting',
    'recognizing_phones',
    'aligning',
    'analyzing',
  }.contains(status);

  static bool isTerminal(String status) => const {
    'completed',
    'cancelled',
    'failed',
    'interrupted',
  }.contains(status);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
