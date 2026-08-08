import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/content_package_journey_view_model.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/media_session_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/resource_actions_coordinator.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/transcript_readiness_view_model.dart';
import 'package:llplayer_next/data/repositories/content_package_repository.dart';
import 'package:llplayer_next/data/repositories/media_session_repository.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/data/repositories/subtitle_analysis_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/content_package.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/services/content_generator_setup.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';

void main() {
  group('MediaSessionCoordinator transcript reconciliation', () {
    test('a single usable track is selected automatically', () async {
      final harness = _coordinatorHarness(const [
        _archivedTrack,
        _usableTrackA,
      ]);
      harness.subtitle.setSubtitleResources(const [
        _archivedTrack,
        _usableTrackA,
      ]);

      await harness.mediaSession.reconcileLearningTranscript();

      expect(harness.subtitle.primaryTrack?.id, _usableTrackA.id);
    });

    test('an already-selected primary track is never replaced', () async {
      final harness = _coordinatorHarness(const [_usableTrackA, _usableTrackB]);
      harness.subtitle.setSubtitleResources(const [
        _usableTrackA,
        _usableTrackB,
      ]);
      harness.subtitle.setPrimaryTrack(_usableTrackA);

      await harness.mediaSession.reconcileLearningTranscript();

      expect(harness.subtitle.primaryTrack?.id, _usableTrackA.id);
    });

    test('several usable tracks are left for the chooser', () async {
      final harness = _coordinatorHarness(const [_usableTrackA, _usableTrackB]);
      harness.subtitle.setSubtitleResources(const [
        _usableTrackA,
        _usableTrackB,
      ]);

      await harness.mediaSession.reconcileLearningTranscript();

      expect(harness.subtitle.primaryTrack, isNull);
    });

    test('no usable tracks leaves the prepare surface in charge', () async {
      final harness = _coordinatorHarness(const [_archivedTrack]);
      harness.subtitle.setSubtitleResources(const [_archivedTrack]);

      await harness.mediaSession.reconcileLearningTranscript();

      expect(harness.subtitle.primaryTrack, isNull);
    });

    test('archived tracks never count as candidates', () async {
      // One archived track with sentences and one available track: only the
      // available one may be auto-selected.
      final harness = _coordinatorHarness(const [
        _archivedTrack,
        _usableTrackA,
      ]);
      harness.subtitle.setSubtitleResources(const [
        _archivedTrack,
        _usableTrackA,
      ]);

      await harness.mediaSession.reconcileLearningTranscript();

      expect(harness.subtitle.primaryTrack?.id, _usableTrackA.id);
    });
  });

  group('TranscriptReadinessViewModel', () {
    test('no transcript and a configured generator shows missing', () {
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: true,
        repository: _FakePackageRepository(),
      );
      addTearDown(subject.vm.dispose);

      expect(subject.vm.state.phase, TranscriptReadinessPhase.missing);
    });

    test('no transcript and no generator shows unavailable', () {
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: false,
        repository: _FakePackageRepository(),
      );
      addTearDown(subject.vm.dispose);

      expect(subject.vm.state.phase, TranscriptReadinessPhase.unavailable);
    });

    test('several usable tracks show the chooser and select on tap', () async {
      var generationStarts = 0;
      final subject = _readinessViewModel(
        tracks: const [_usableTrackA, _usableTrackB],
        canAutoPrepare: true,
        repository: _FakePackageRepository(onStart: () => generationStarts++),
      );
      addTearDown(subject.vm.dispose);

      expect(subject.vm.state.phase, TranscriptReadinessPhase.choosing);
      expect(subject.vm.state.usableTracks.map((track) => track.id), [
        _usableTrackA.id,
        _usableTrackB.id,
      ]);
      // No arbitrary first item is selected on its own.
      expect(subject.subtitle.primaryTrack, isNull);

      await subject.vm.selectTrack(_usableTrackB);

      expect(subject.subtitle.primaryTrack?.id, _usableTrackB.id);
      expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
      expect(generationStarts, 0);
    });

    test(
      'prepare runs generate → import → auto-select without a second tap',
      () async {
        final receipt = _receipt(
          track: _usableTrackA,
          includeWordTimeline: false,
        );
        final repository = _FakePackageRepository(
          receipt: receipt,
          runForAttempt: (attempt) => _FakeRun(attempt: attempt),
        );
        final subject = _readinessViewModel(
          tracks: const [],
          canAutoPrepare: true,
          repository: repository,
        );
        addTearDown(subject.vm.dispose);

        await _runGeneration(subject.vm, repository);

        expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
        expect(subject.subtitle.primaryTrack?.id, _usableTrackA.id);
        expect(subject.vm.state.failure, isNull);
        expect(repository.activatedTimelines, isEmpty);
      },
    );

    test(
      'preparation stages map machine phases to user-facing labels',
      () async {
        final importGate = Completer<ContentPackageImportReceipt>();
        final repository = _FakePackageRepository(
          receipt: _receipt(track: _usableTrackA),
          runForAttempt: (attempt) => _FakeRun(attempt: attempt),
          importGate: importGate,
        );
        final subject = _readinessViewModel(
          tracks: const [],
          canAutoPrepare: true,
          repository: repository,
        );
        addTearDown(subject.vm.dispose);

        final future = subject.vm.prepareLearningTranscript();
        await _settle();
        expect(subject.vm.state.phase, TranscriptReadinessPhase.preparing);
        final run = repository.runs.single;
        run.eventsController.add(
          ListenGenMachineEvent(sequence: 0, kind: ListenGenEventKind.protocol),
        );
        run.eventsController.add(
          ListenGenMachineEvent(sequence: 1, kind: ListenGenEventKind.started),
        );
        await _settle();
        run.eventsController.add(
          ListenGenMachineEvent(
            sequence: 2,
            kind: ListenGenEventKind.phase,
            phase: 'validating',
          ),
        );
        await _settle();
        expect(
          subject.vm.state.preparationStage,
          TranscriptPreparationStage.checkingMedia,
        );
        run.eventsController.add(
          ListenGenMachineEvent(
            sequence: 3,
            kind: ListenGenEventKind.phase,
            phase: 'transcribing',
          ),
        );
        await _settle();
        expect(
          subject.vm.state.preparationStage,
          TranscriptPreparationStage.transcribing,
        );
        run.eventsController.add(
          ListenGenMachineEvent(
            sequence: 4,
            kind: ListenGenEventKind.completed,
          ),
        );
        await _settle();
        run.packageCompleter.complete('/tmp/generated.listenpkg');
        await _settle();
        // The import is gated, so the surface sits on its importing stage
        // until the core finishes with the package.
        expect(subject.vm.state.phase, TranscriptReadinessPhase.preparing);
        expect(
          subject.vm.state.preparationStage,
          TranscriptPreparationStage.importing,
        );
        importGate.complete(_receipt(track: _usableTrackA));
        await future;
        await _settle();
        expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
      },
    );

    test(
      'a transcript-only package is still ready (no WordTimeline)',
      () async {
        final receipt = _receipt(
          track: _usableTrackA,
          includeWordTimeline: false,
        );
        final repository = _FakePackageRepository(
          receipt: receipt,
          runForAttempt: (attempt) => _FakeRun(attempt: attempt),
        );
        final subject = _readinessViewModel(
          tracks: const [],
          canAutoPrepare: true,
          repository: repository,
        );
        addTearDown(subject.vm.dispose);

        await _runGeneration(subject.vm, repository);

        expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
        expect(subject.subtitle.primaryTrack?.id, _usableTrackA.id);
        expect(receipt.resources.map((resource) => resource.kind), [
          'subtitle_text_track',
        ]);
      },
    );

    test('cancel stops the run and returns to the missing surface', () async {
      final repository = _FakePackageRepository(
        runForAttempt: (attempt) => _FakeRun(attempt: attempt),
      );
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: true,
        repository: repository,
      );
      addTearDown(subject.vm.dispose);

      final future = subject.vm.prepareLearningTranscript();
      await _settle();
      final run = repository.runs.single;
      run.eventsController.add(
        ListenGenMachineEvent(sequence: 0, kind: ListenGenEventKind.protocol),
      );
      run.eventsController.add(
        ListenGenMachineEvent(sequence: 1, kind: ListenGenEventKind.started),
      );
      await _settle();
      expect(subject.vm.state.canCancel, isTrue);

      subject.vm.cancel();
      run.packageCompleter.completeError(
        const ListenGenProcessFailure('cancelled'),
      );
      await future;
      await _settle();

      expect(run.cancelled, isTrue);
      expect(subject.vm.state.phase, TranscriptReadinessPhase.missing);
      expect(subject.subtitle.primaryTrack, isNull);
    });

    test('a retryable generation failure offers retry and recovers', () async {
      final repository = _FakePackageRepository(
        receipt: _receipt(track: _usableTrackA),
        runForAttempt: (attempt) => _FakeRun(attempt: attempt),
      );
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: true,
        repository: repository,
      );
      addTearDown(subject.vm.dispose);

      await _runGeneration(subject.vm, repository, fail: true);

      expect(subject.vm.state.phase, TranscriptReadinessPhase.failed);
      expect(subject.vm.state.fingerprintMismatch, isFalse);
      expect(subject.vm.state.canRetry, isTrue);
      expect(subject.subtitle.primaryTrack, isNull);

      final retryFuture = subject.vm.retry();
      await _settle();
      await _runGeneration(subject.vm, repository, pending: retryFuture);

      expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
      expect(subject.subtitle.primaryTrack?.id, _usableTrackA.id);
    });

    test('fingerprint mismatch stays an explicit failure', () async {
      final repository = _FakePackageRepository(
        importFailure: const ApiFailure(
          raw: '',
          code: 'content_package_media_mismatch',
        ),
        runForAttempt: (attempt) => _FakeRun(attempt: attempt),
      );
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: true,
        repository: repository,
      );
      addTearDown(subject.vm.dispose);

      await _runGeneration(subject.vm, repository);

      expect(subject.vm.state.phase, TranscriptReadinessPhase.failed);
      expect(subject.vm.state.fingerprintMismatch, isTrue);
      expect(subject.subtitle.primaryTrack, isNull);
    });

    test(
      'a failed preparation never changes the selected transcript',
      () async {
        final repository = _FakePackageRepository(
          importFailure: const ApiFailure(raw: '', code: 'temporary'),
          runForAttempt: (attempt) => _FakeRun(attempt: attempt),
        );
        final subject = _readinessViewModel(
          tracks: const [_usableTrackA],
          canAutoPrepare: true,
          repository: repository,
        );
        addTearDown(subject.vm.dispose);

        await subject.vm.selectTrack(_usableTrackA);
        expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);

        await _runGeneration(subject.vm, repository);

        expect(subject.subtitle.primaryTrack?.id, _usableTrackA.id);
        // The existing selection keeps the ready surface even when a later
        // preparation attempt fails.
        expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
      },
    );

    test('generator unavailable does not start a run', () async {
      var starts = 0;
      final repository = _FakePackageRepository(
        runForAttempt: (attempt) => _FakeRun(attempt: attempt),
        onStart: () => starts++,
      );
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: false,
        repository: repository,
      );
      addTearDown(subject.vm.dispose);

      await subject.vm.prepareLearningTranscript();

      expect(subject.vm.state.phase, TranscriptReadinessPhase.unavailable);
      expect(starts, 0);
      expect(subject.subtitle.primaryTrack, isNull);
    });

    test(
      'readiness flips unavailable → missing when the readiness input arrives',
      () {
        var autoPrepare = false;
        final trigger = ValueNotifier<int>(0);
        final subject = _readinessViewModel(
          tracks: const [],
          canAutoPrepare: autoPrepare,
          canAutoPrepareOverride: () => autoPrepare,
          refreshTrigger: trigger,
          repository: _FakePackageRepository(),
        );
        addTearDown(subject.vm.dispose);

        expect(subject.vm.state.phase, TranscriptReadinessPhase.unavailable);

        // The predicate changed, but the projection must not recompute until
        // the invalidation seam actually fires — no polling of the predicate.
        autoPrepare = true;
        expect(subject.vm.state.phase, TranscriptReadinessPhase.unavailable);

        trigger.value++;
        expect(subject.vm.state.phase, TranscriptReadinessPhase.missing);
      },
    );

    test(
      'readiness flips missing → unavailable when the readiness input leaves',
      () {
        var autoPrepare = true;
        final trigger = ValueNotifier<int>(0);
        final subject = _readinessViewModel(
          tracks: const [],
          canAutoPrepare: autoPrepare,
          canAutoPrepareOverride: () => autoPrepare,
          refreshTrigger: trigger,
          repository: _FakePackageRepository(),
        );
        addTearDown(subject.vm.dispose);

        expect(subject.vm.state.phase, TranscriptReadinessPhase.missing);

        autoPrepare = false;
        expect(subject.vm.state.phase, TranscriptReadinessPhase.missing);

        trigger.value++;
        expect(subject.vm.state.phase, TranscriptReadinessPhase.unavailable);
      },
    );
  });
}

/// Drives one generation attempt to its terminal state through the real
/// journey orchestration. [fail] completes the run with a failed machine
/// event; otherwise it completes normally and imports. [pending] carries an
/// already-started run's future (e.g. a retry) instead of starting a new one.
Future<void> _runGeneration(
  TranscriptReadinessViewModel vm,
  _FakePackageRepository repository, {
  bool fail = false,
  Future<void>? pending,
}) async {
  final future = pending ?? vm.prepareLearningTranscript();
  await _settle();
  final run = repository.runs.last;
  run.eventsController.add(
    ListenGenMachineEvent(sequence: 0, kind: ListenGenEventKind.protocol),
  );
  run.eventsController.add(
    ListenGenMachineEvent(sequence: 1, kind: ListenGenEventKind.started),
  );
  run.eventsController.add(
    fail
        ? ListenGenMachineEvent(
            sequence: 2,
            kind: ListenGenEventKind.failed,
            code: 'generator_failed',
            message: 'temporary problem',
          )
        : ListenGenMachineEvent(
            sequence: 2,
            kind: ListenGenEventKind.completed,
          ),
  );
  await _settle();
  run.packageCompleter.complete('/tmp/generated.listenpkg');
  await future;
  await _settle();
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

({TranscriptReadinessViewModel vm, SubtitleController subtitle})
_readinessViewModel({
  required List<SubtitleTrack> tracks,
  required bool canAutoPrepare,
  required _FakePackageRepository repository,
  bool Function()? canAutoPrepareOverride,
  Listenable? refreshTrigger,
}) {
  final harness = _coordinatorHarness(tracks);
  harness.subtitle.setSubtitleResources(tracks);
  final vm = TranscriptReadinessViewModel(
    subtitle: harness.subtitle,
    mediaSession: harness.mediaSession,
    canAutoPrepare: canAutoPrepareOverride ?? () => canAutoPrepare,
    createJourney: () => ContentPackageJourneyViewModel(
      repository,
      (track) async {
        await harness.mediaSession.usePrimarySubtitleTrack(
          track,
          nextStatus: 'selected',
        );
        await harness.mediaSession.resourceActions.loadSubtitleResources(
          updateStatus: false,
        );
      },
      (timelineId) async {
        repository.activatedTimelines.add(timelineId);
      },
      mediaId: 'media-1',
      mediaPath: '/tmp/media.wav',
      mediaTitle: 'Lesson',
      mediaKind: 'audio',
      durationMs: 2200,
    ),
    refreshTrigger: refreshTrigger,
  )..bind(text: (key) => key);
  return (vm: vm, subtitle: harness.subtitle);
}

({SubtitleController subtitle, MediaSessionCoordinator mediaSession})
_coordinatorHarness(List<SubtitleTrack> tracks) {
  final player = PlayerController();
  final subtitle = SubtitleController();
  final speech = SpeechEnhancementWorkflowController();
  final resourceActions =
      ResourceActionsCoordinator(
        player: player,
        subtitle: subtitle,
        speechEnhancement: speech,
        repository: _FakeResourceRepository(tracks),
      )..bind(
        isMounted: () => true,
        reloadSpeechEnhancements: (_) async {},
        activatePrimaryTrack: (_, {required nextStatus}) async {},
        reloadLearningEntries: () async {},
      );
  final mediaSession =
      MediaSessionCoordinator(
        adapter: DesktopPlayerAdapter(),
        player: player,
        subtitle: subtitle,
        learning: LearningController(),
        settings: SettingsController(),
        speechEnhancement: speech,
        resourceActions: resourceActions,
        repository: _FakeMediaSessionRepository(),
        subtitleAnalysis: _FakeSubtitleAnalysisRepository(),
      )..bind(
        isMounted: () => true,
        text: (key) => key,
        confirmLLTimelineMismatch:
            ({
              required String resourceFingerprint,
              required String currentFingerprint,
            }) async => false,
        onMediaSwitched: () {},
        reloadLearningEntries: () async {},
        loadPhraseCandidates: (_) async {},
      );
  return (subtitle: subtitle, mediaSession: mediaSession);
}

ContentPackageImportReceipt _receipt({
  required SubtitleTrack track,
  bool includeWordTimeline = true,
}) => ContentPackageImportReceipt(
  manifestSha256:
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  track: track,
  resources: [
    ContentPackageResourceDisposition(
      resourceId:
          'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      kind: 'subtitle_text_track',
      outcome: 'consumed',
      localIds: const ['track-a'],
    ),
    if (includeWordTimeline)
      ContentPackageResourceDisposition(
        resourceId:
            'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        kind: 'word_timeline',
        outcome: 'consumed',
        localIds: const ['word-1'],
      ),
  ],
);

const _usableTrackA = SubtitleTrack(
  id: 'track-a',
  language: 'en',
  source: 'generated',
  cues: [
    Cue(
      id: 'cue-1',
      index: 0,
      start: Duration.zero,
      end: Duration(seconds: 1),
      text: 'Hello',
      tokens: [
        SubtitleToken(
          index: 0,
          kind: 'word',
          text: 'Hello',
          normalized: 'hello',
        ),
      ],
    ),
  ],
);

const _usableTrackB = SubtitleTrack(
  id: 'track-b',
  language: 'zh',
  source: 'subtitle',
  cues: [
    Cue(
      id: 'cue-2',
      index: 0,
      start: Duration.zero,
      end: Duration(seconds: 1),
      text: '你好',
      tokens: [
        SubtitleToken(index: 0, kind: 'word', text: '你好', normalized: '你好'),
      ],
    ),
  ],
);

const _archivedTrack = SubtitleTrack(
  id: 'track-archived',
  language: 'en',
  status: 'archived',
  cues: [
    Cue(
      id: 'cue-3',
      index: 0,
      start: Duration.zero,
      end: Duration(seconds: 1),
      text: 'Archived',
      tokens: [
        SubtitleToken(
          index: 0,
          kind: 'word',
          text: 'Archived',
          normalized: 'archived',
        ),
      ],
    ),
  ],
);

final class _FakePackageRepository implements ContentPackageRepository {
  _FakePackageRepository({
    this.receipt,
    this.importFailure,
    this.runForAttempt,
    this.onStart,
    this.importGate,
  });

  final ContentPackageImportReceipt? receipt;
  final ApiFailure? importFailure;
  final _FakeRun Function(int attempt)? runForAttempt;
  final void Function()? onStart;
  final Completer<ContentPackageImportReceipt>? importGate;
  final List<_FakeRun> runs = [];
  final List<String> activatedTimelines = [];
  int _attempt = 0;

  @override
  bool get coreAvailable => true;
  @override
  bool get generatorConfigured => true;
  @override
  ContentGeneratorState get generatorState => ContentGeneratorState.ready;
  @override
  ApiFailure failureDetail(Object error) =>
      error is ApiFailure ? error : ApiFailure(raw: '', code: '$error');
  @override
  Future<String?> pickPackage() async => null;
  @override
  Future<ContentPackageImportReceipt> importPackage({
    required String mediaId,
    required String packagePath,
  }) async {
    if (importFailure != null) throw importFailure!;
    if (importGate != null) return importGate!.future;
    return receipt!;
  }

  @override
  Future<ListenGenProcessRun> startGeneration(
    ContentPackageGenerationRequest request,
  ) async {
    onStart?.call();
    final attempt = ++_attempt;
    final run = runForAttempt?.call(attempt) ?? _FakeRun(attempt: attempt);
    runs.add(run);
    return run;
  }
}

final class _FakeRun implements ListenGenProcessRun {
  _FakeRun({required int attempt}) : packageSha = 'run-$attempt';

  final String packageSha;
  final eventsController = StreamController<ListenGenMachineEvent>();
  final packageCompleter = Completer<String>();
  bool cancelled = false;

  @override
  Stream<ListenGenMachineEvent> get events => eventsController.stream;
  @override
  Future<String> get packagePath => packageCompleter.future;
  @override
  void cancel() => cancelled = true;
  @override
  Future<void> cleanUp() async {
    await eventsController.close();
  }
}

final class _FakeResourceRepository implements ResourceRepository {
  _FakeResourceRepository(this.tracks);

  final List<SubtitleTrack> tracks;

  @override
  bool get isAvailable => true;
  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '', code: '$error');
  @override
  Future<ContentDifficultyProfile> contentFit(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<List<SubtitleTrack>> mediaSubtitles(String mediaId) async => tracks;
  @override
  Future<List<WordTiming>> wordTimings(String trackId) async => const [];
  @override
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(
    String trackId,
  ) async => const [];
  @override
  Future<List<ChunkTimelineSummary>> chunkTimelineSummaries(
    String trackId,
  ) async => const [];
  @override
  Future<void> archiveSubtitle(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<void> restoreSubtitle(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteSubtitle(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<String> exportSubtitleSrt(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<LLTimelineDocument> exportTimeline(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<void> updateTrackLanguage(String trackId, String language) async =>
      throw UnimplementedError();
  @override
  Future<void> activateWordTimeline(String timelineId) async =>
      throw UnimplementedError();
  @override
  Future<void> generateChunkTimeline(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<void> activateChunkTimeline(String timelineId) async =>
      throw UnimplementedError();
  @override
  Future<void> archiveChunkTimeline(String timelineId) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteChunkTimeline(String timelineId) async =>
      throw UnimplementedError();
  @override
  Future<void> activatePhoneTimeline(String timelineId) async =>
      throw UnimplementedError();
  @override
  Future<void> archivePhoneTimeline(String timelineId) async =>
      throw UnimplementedError();
  @override
  Future<void> deletePhoneTimeline(String timelineId) async =>
      throw UnimplementedError();
}

final class _FakeMediaSessionRepository implements MediaSessionRepository {
  @override
  bool get isAvailable => true;
  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '', code: '$error');
  @override
  Future<void> saveProgress(String mediaId, Duration position) async {}
  @override
  Future<MediaItem> registerMedia(String path) async => MediaItem(
    id: 'media-1',
    path: path,
    fingerprint: 'fingerprint',
    title: 'Title',
    kind: 'audio',
    durationMs: 2200,
    availability: 'available',
    createdAtMs: 0,
    updatedAtMs: 0,
  );
  @override
  Future<Duration?> readProgress(String mediaId) async => null;
  @override
  Future<SubtitleTrack> importSubtitle(String mediaId, String path) async =>
      throw UnimplementedError();
  @override
  Future<SubtitleTrack> importTimeline({
    required String mediaId,
    required Map<String, dynamic> document,
    required bool allowMismatch,
  }) async => throw UnimplementedError();
}

final class _FakeSubtitleAnalysisRepository
    implements SubtitleAnalysisRepository {
  @override
  bool get isAvailable => false;
  @override
  Future<bool> syntaxReady() async => false;
  @override
  Future<void> analyzeTrackSyntax(String trackId) async {}
  @override
  Future<PronunciationAnalysis> analyzePronunciation(String sentenceId) async =>
      throw UnimplementedError();
  @override
  Future<String> startPhoneticAnalysis({
    required String trackId,
    required String? sentenceId,
    required String preferredModelId,
  }) async => throw UnimplementedError();
}
