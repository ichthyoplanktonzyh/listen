import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/content_package_repository.dart';
import '../models/api_failure.dart';
import '../models/content_package.dart';
import '../models/timeline.dart';
import '../services/listen_gen_process_service.dart';
import '../state/store.dart';

enum ContentPackageJourneyPhase {
  idle,
  preparing,
  generating,
  importing,
  candidateReady,
  fingerprintMismatch,
  failed,
  cancelled,
  retrying,
}

@immutable
class ContentPackageJourneyState {
  ContentPackageJourneyState({
    this.phase = ContentPackageJourneyPhase.idle,
    this.generatorPhase,
    this.receipt,
    this.failure,
    List<ListenGenResourceView> generatedResources = const [],
    List<String> generatorWarnings = const [],
    Set<String> activatedWordTimelineIds = const {},
    this.selectedTrackId,
  }) : _generatedResources = List.unmodifiable(generatedResources),
       _generatorWarnings = List.unmodifiable(generatorWarnings),
       _activatedWordTimelineIds = Set.unmodifiable(activatedWordTimelineIds);

  final ContentPackageJourneyPhase phase;
  final String? generatorPhase;
  final ContentPackageImportReceipt? receipt;
  final ApiFailure? failure;
  final List<ListenGenResourceView> _generatedResources;
  List<ListenGenResourceView> get generatedResources =>
      List.unmodifiable(_generatedResources);
  final List<String> _generatorWarnings;
  List<String> get generatorWarnings => List.unmodifiable(_generatorWarnings);
  final Set<String> _activatedWordTimelineIds;
  Set<String> get activatedWordTimelineIds =>
      Set.unmodifiable(_activatedWordTimelineIds);
  final String? selectedTrackId;

  bool get busy =>
      phase == ContentPackageJourneyPhase.preparing ||
      phase == ContentPackageJourneyPhase.generating ||
      phase == ContentPackageJourneyPhase.importing ||
      phase == ContentPackageJourneyPhase.retrying;

  ContentPackageJourneyState copyWith({
    ContentPackageJourneyPhase? phase,
    String? generatorPhase,
    bool clearGeneratorPhase = false,
    ContentPackageImportReceipt? receipt,
    bool clearReceipt = false,
    ApiFailure? failure,
    bool clearFailure = false,
    List<ListenGenResourceView>? generatedResources,
    List<String>? generatorWarnings,
    Set<String>? activatedWordTimelineIds,
    String? selectedTrackId,
    bool clearSelectedTrackId = false,
  }) => ContentPackageJourneyState(
    phase: phase ?? this.phase,
    generatorPhase: clearGeneratorPhase
        ? null
        : generatorPhase ?? this.generatorPhase,
    receipt: clearReceipt ? null : receipt ?? this.receipt,
    failure: clearFailure ? null : failure ?? this.failure,
    generatedResources: generatedResources ?? this.generatedResources,
    generatorWarnings: generatorWarnings ?? this.generatorWarnings,
    activatedWordTimelineIds:
        activatedWordTimelineIds ?? this.activatedWordTimelineIds,
    selectedTrackId: clearSelectedTrackId
        ? null
        : selectedTrackId ?? this.selectedTrackId,
  );
}

sealed class _LastPackageIntent {
  const _LastPackageIntent();
}

final class _ImportPackageIntent extends _LastPackageIntent {
  const _ImportPackageIntent(this.path);
  final String path;
}

final class _GeneratePackageIntent extends _LastPackageIntent {
  const _GeneratePackageIntent(this.request);
  final ContentPackageGenerationRequest request;
}

class ContentPackageJourneyViewModel extends ChangeNotifier {
  ContentPackageJourneyViewModel(
    this._repository,
    this._selectSubtitleTrack,
    this._activateWordTimeline, {
    required this.mediaId,
    required this.mediaPath,
    required this.mediaTitle,
    required this.mediaKind,
    required this.durationMs,
  }) : _store = Store(ContentPackageJourneyState()) {
    _store.addListener(notifyListeners);
  }

  final ContentPackageRepository _repository;
  final Store<ContentPackageJourneyState> _store;
  final Future<void> Function(SubtitleTrack track) _selectSubtitleTrack;
  final Future<void> Function(String timelineId) _activateWordTimeline;
  final String mediaId;
  final String mediaPath;
  final String mediaTitle;
  final String mediaKind;
  final int durationMs;
  ListenGenProcessRun? _run;
  StreamSubscription<ListenGenMachineEvent>? _events;
  _LastPackageIntent? _lastIntent;
  int _generation = 0;
  bool _disposed = false;

  ContentPackageJourneyState get state => _store.state;
  bool get generatorConfigured =>
      _repository.generatorConfigured && mediaPath.isNotEmpty && durationMs > 0;

  Future<void> chooseAndImportPackage() async {
    final generation = ++_generation;
    _publish(
      ContentPackageJourneyState(phase: ContentPackageJourneyPhase.preparing),
    );
    try {
      final path = await _repository.pickPackage();
      if (_stale(generation)) return;
      if (path == null) {
        _publish(
          ContentPackageJourneyState(
            phase: ContentPackageJourneyPhase.cancelled,
          ),
        );
        return;
      }
      _lastIntent = _ImportPackageIntent(path);
      await _import(path, generation);
    } catch (error) {
      if (!_stale(generation)) _fail(error);
    }
  }

  Future<void> generateAndImport() async {
    final request = ContentPackageGenerationRequest(
      mediaPath: mediaPath,
      title: mediaTitle,
      mediaKind: mediaKind,
      durationMs: durationMs,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _lastIntent = _GeneratePackageIntent(request);
    await _generate(request, ++_generation);
  }

  Future<void> retry() async {
    final intent = _lastIntent;
    if (intent == null || state.busy) return;
    final generation = ++_generation;
    _publish(
      state.copyWith(
        phase: ContentPackageJourneyPhase.retrying,
        clearFailure: true,
        clearReceipt: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    if (_stale(generation)) return;
    switch (intent) {
      case _ImportPackageIntent(:final path):
        await _import(path, generation);
      case _GeneratePackageIntent(:final request):
        await _generate(request, generation);
    }
  }

  Future<void> _generate(
    ContentPackageGenerationRequest request,
    int generation,
  ) async {
    _publish(
      ContentPackageJourneyState(phase: ContentPackageJourneyPhase.preparing),
    );
    ApiFailure? eventFailure;
    ListenGenProcessRun? ownedRun;
    StreamSubscription<ListenGenMachineEvent>? ownedEvents;
    try {
      final run = await _repository.startGeneration(request);
      if (_stale(generation)) {
        run.cancel();
        await run.cleanUp();
        return;
      }
      ownedRun = run;
      _run = run;
      ownedEvents = run.events.listen(
        (event) {
          if (_stale(generation)) return;
          switch (event.kind) {
            case ListenGenEventKind.protocol:
            case ListenGenEventKind.started:
              _publish(
                state.copyWith(
                  phase: ContentPackageJourneyPhase.generating,
                  clearFailure: true,
                ),
              );
            case ListenGenEventKind.phase:
              _publish(
                state.copyWith(
                  phase: ContentPackageJourneyPhase.generating,
                  generatorPhase: event.phase,
                ),
              );
            case ListenGenEventKind.completed:
              _publish(
                state.copyWith(
                  generatedResources: event.resources,
                  generatorWarnings: event.warnings,
                ),
              );
            case ListenGenEventKind.failed:
              eventFailure = ApiFailure(
                raw: '',
                code: event.code ?? 'generator_failed',
                message: event.message,
                retryable: true,
              );
            case ListenGenEventKind.cancelled:
              _publish(
                state.copyWith(phase: ContentPackageJourneyPhase.cancelled),
              );
          }
        },
        onError: (Object error) {
          eventFailure = _repository.failureDetail(error);
        },
      );
      _events = ownedEvents;
      final path = await run.packagePath;
      if (_stale(generation)) return;
      if (eventFailure != null) {
        _publish(
          state.copyWith(
            phase: ContentPackageJourneyPhase.failed,
            failure: eventFailure,
          ),
        );
        return;
      }
      await _import(path, generation);
    } catch (error) {
      if (_stale(generation)) return;
      if (state.phase == ContentPackageJourneyPhase.cancelled ||
          error is ListenGenProcessFailure && error.code == 'cancelled') {
        _publish(state.copyWith(phase: ContentPackageJourneyPhase.cancelled));
      } else {
        _fail(eventFailure ?? error);
      }
    } finally {
      await ownedEvents?.cancel();
      if (identical(_events, ownedEvents)) _events = null;
      if (identical(_run, ownedRun)) _run = null;
      await ownedRun?.cleanUp();
    }
  }

  Future<void> _import(String path, int generation) async {
    _publish(
      state.copyWith(
        phase: ContentPackageJourneyPhase.importing,
        clearFailure: true,
      ),
    );
    try {
      final receipt = await _repository.importPackage(
        mediaId: mediaId,
        packagePath: path,
      );
      if (_stale(generation)) return;
      _publish(
        state.copyWith(
          phase: ContentPackageJourneyPhase.candidateReady,
          receipt: receipt,
          clearFailure: true,
        ),
      );
    } catch (error) {
      if (_stale(generation)) return;
      _fail(error);
    }
  }

  Future<void> selectImportedSubtitle() async {
    final track = state.receipt?.track;
    if (track == null || state.busy) return;
    try {
      await _selectSubtitleTrack(track);
      _publish(state.copyWith(selectedTrackId: track.id));
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> activateImportedWordTimeline(String timelineId) async {
    if (state.busy || state.activatedWordTimelineIds.contains(timelineId)) {
      return;
    }
    try {
      await _activateWordTimeline(timelineId);
      _publish(
        state.copyWith(
          activatedWordTimelineIds: {
            ...state.activatedWordTimelineIds,
            timelineId,
          },
        ),
      );
    } catch (error) {
      _fail(error);
    }
  }

  void cancel() {
    if (_run == null) return;
    ++_generation;
    _run?.cancel();
    _publish(state.copyWith(phase: ContentPackageJourneyPhase.cancelled));
  }

  void _fail(Object error) {
    final failure = error is ApiFailure
        ? error
        : _repository.failureDetail(error);
    final mismatchCodes = {
      'fingerprint_mismatch',
      'media_fingerprint_mismatch',
      'content_package_fingerprint_mismatch',
      'content_package_media_mismatch',
    };
    _publish(
      state.copyWith(
        phase: mismatchCodes.contains(failure.code)
            ? ContentPackageJourneyPhase.fingerprintMismatch
            : ContentPackageJourneyPhase.failed,
        failure: failure,
      ),
    );
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  void _publish(ContentPackageJourneyState value) {
    if (!_disposed) _store.replace(value);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _run?.cancel();
    unawaited(_events?.cancel());
    _store.removeListener(notifyListeners);
    _store.dispose();
    super.dispose();
  }
}
