import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/transcription_repository.dart';
import '../models/named_failure.dart';
import '../models/runtime_resources.dart';
import '../models/timeline.dart';
import '../services/transcription_file_service.dart';

typedef GeneratedTrackLoader =
    Future<void> Function(SubtitleTrack track, bool secondary);
typedef RegenerateTranscriptionJob =
    Future<void> Function(TranscriptionJobView job);

@immutable
class GenerateSubtitlesState {
  GenerateSubtitlesState({
    List<TranscriptionModelView> installedModels = const [],
    this.modelId,
    this.language = 'auto',
    this.translate = false,
    this.loading = true,
    this.created = false,
  }) : installedModels = List.unmodifiable(installedModels);

  final List<TranscriptionModelView> installedModels;
  final String? modelId;
  final String language;
  final bool translate;
  final bool loading;
  final bool created;
}

class GenerateSubtitlesViewModel extends ChangeNotifier {
  GenerateSubtitlesViewModel(
    this._repository, {
    required this.mediaId,
    required this.secondary,
    this.preferredQuality = 'balanced',
    this.preferredLanguage = 'auto',
    this.force = false,
  });

  final TranscriptionRepository _repository;
  final String mediaId;
  final bool secondary;
  final String preferredQuality;
  final String preferredLanguage;
  final bool force;
  GenerateSubtitlesState _state = GenerateSubtitlesState();
  int _generation = 0;
  bool _disposed = false;

  GenerateSubtitlesState get state => _state;

  Future<void> load() async {
    final generation = ++_generation;
    final values = (await _repository.models())
        .where((model) => model.state == 'installed' || model.state == 'custom')
        .toList(growable: false);
    if (!_isCurrent(generation)) return;
    final preferred = values.where(
      (model) => model.quality == preferredQuality,
    );
    _publish(
      GenerateSubtitlesState(
        installedModels: values,
        modelId: values.isEmpty
            ? null
            : (preferred.isEmpty ? values.first : preferred.first).id,
        language: preferredLanguage,
        loading: false,
      ),
    );
  }

  void setModel(String value) {
    if (_disposed) return;
    _generation++;
    _publish(
      GenerateSubtitlesState(
        installedModels: _state.installedModels,
        modelId: value,
        language: _state.language,
        translate: _state.translate,
        loading: _state.loading,
      ),
    );
  }

  void setLanguage(String value) {
    if (_disposed) return;
    _generation++;
    _publish(
      GenerateSubtitlesState(
        installedModels: _state.installedModels,
        modelId: _state.modelId,
        language: value,
        translate: _state.translate,
        loading: _state.loading,
      ),
    );
  }

  void setTranslate(bool value) {
    if (_disposed) return;
    _generation++;
    _publish(
      GenerateSubtitlesState(
        installedModels: _state.installedModels,
        modelId: _state.modelId,
        language: _state.language,
        translate: value,
        loading: _state.loading,
      ),
    );
  }

  Future<bool> create() async {
    if (_disposed) return false;
    final modelId = _state.modelId;
    if (modelId == null) return false;
    final generation = ++_generation;
    await _repository.createJob(
      mediaId: mediaId,
      modelId: modelId,
      secondary: secondary,
      translate: _state.translate,
      language: _state.language == 'auto' ? null : _state.language,
      force: force,
    );
    if (!_isCurrent(generation)) return false;
    _publish(
      GenerateSubtitlesState(
        installedModels: _state.installedModels,
        modelId: modelId,
        language: _state.language,
        translate: _state.translate,
        loading: false,
        created: true,
      ),
    );
    return true;
  }

  void _publish(GenerateSubtitlesState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

@immutable
class TranscriptionCenterState {
  TranscriptionCenterState({
    List<TranscriptionProviderView> providers = const [],
    List<TranscriptionModelView> models = const [],
    List<TranscriptionJobView> jobs = const [],
    this.failure,
  }) : providers = List.unmodifiable(providers),
       models = List.unmodifiable(models),
       jobs = List.unmodifiable(jobs);

  final List<TranscriptionProviderView> providers;
  final List<TranscriptionModelView> models;
  final List<TranscriptionJobView> jobs;
  final NamedFailure? failure;
}

class TranscriptionCenterViewModel extends ChangeNotifier {
  TranscriptionCenterViewModel(
    this._repository, {
    required this.loadTrack,
    this.fileService = const LocalTranscriptionFileService(),
  });

  final TranscriptionRepository _repository;
  final GeneratedTrackLoader loadTrack;
  final TranscriptionFileService fileService;
  TranscriptionCenterState _state = TranscriptionCenterState();
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  TranscriptionCenterState get state => _state;

  Future<void> start() async {
    await refresh();
    if (_disposed) return;
    _timer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(refresh()),
    );
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
      _publish(
        TranscriptionCenterState(
          providers: values[0] as List<TranscriptionProviderView>,
          models: values[1] as List<TranscriptionModelView>,
          jobs: values[2] as List<TranscriptionJobView>,
        ),
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _publish(
        TranscriptionCenterState(
          providers: _state.providers,
          models: _state.models,
          jobs: _state.jobs,
          failure: NamedFailure(
            'transcriptionLoadFailed',
            detail: _repository.failureDetail(error),
          ),
        ),
      );
    }
  }

  Future<void> registerCustomModel() async {
    final path = await fileService.pickCustomModel();
    if (path == null) return;
    await _run(() => _repository.registerCustomModel(path));
  }

  Future<void> installModel(String id) =>
      _run(() => _repository.installModel(id));
  Future<void> cancelModelInstall(String id) =>
      _run(() => _repository.cancelModelInstall(id));
  Future<void> deleteModel(String id) =>
      _run(() => _repository.deleteModel(id));
  Future<void> cancelJob(String id) => _run(() => _repository.cancelJob(id));
  Future<void> retryJob(String id) => _run(() => _repository.retryJob(id));
  Future<void> archiveJob(String id) => _run(() => _repository.archiveJob(id));

  Future<void> loadGenerated(TranscriptionJobView job) async {
    final track = await _repository.readSubtitle(job.generatedTrackId!);
    await loadTrack(track, job.destination == 'secondary');
  }

  Future<void> exportSrt(TranscriptionJobView job) async {
    final content = await _repository.exportSubtitleSrt(job.generatedTrackId!);
    await fileService.saveSrt(
      suggestedName: '${job.mediaTitle}.generated.srt',
      content: content,
    );
  }

  Future<void> _run(Future<void> Function() command) async {
    await command();
    await refresh();
  }

  void _publish(TranscriptionCenterState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
