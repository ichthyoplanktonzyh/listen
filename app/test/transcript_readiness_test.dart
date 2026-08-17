import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/material_capability_coordinator.dart';
import 'package:llplayer_next/controllers/media_session_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/resource_actions_coordinator.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/transcript_readiness_view_model.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/data/repositories/learning_material_repository.dart';
import 'package:llplayer_next/data/repositories/media_session_repository.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/services/core_timeline_export.dart';
import 'package:llplayer_next/data/repositories/subtitle_analysis_repository.dart';
import 'package:llplayer_next/models/adopted_composition.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/composition.dart';
import 'package:llplayer_next/models/gen_machine_event.dart';
import 'package:llplayer_next/services/capability_generation_request.dart';
import 'package:llplayer_next/models/learning_edition.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/composition_transcript_bridge.dart';
import 'package:llplayer_next/services/content_generator_setup.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/managed_asset_store.dart';
import 'package:llplayer_next/player_adapter.dart';

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
      );
      addTearDown(subject.vm.dispose);

      expect(subject.vm.state.phase, TranscriptReadinessPhase.missing);
    });

    test('no transcript and no generator shows unavailable', () {
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: false,
      );
      addTearDown(subject.vm.dispose);

      expect(subject.vm.state.phase, TranscriptReadinessPhase.unavailable);
      expect(
        subject.vm.state.unavailableReason,
        TranscriptPreparationAvailability.generatorUnavailable,
      );
    });

    test(
      'unavailable state still forwards an explicit generation intent',
      () async {
        final subject = _readinessViewModel(
          tracks: const [],
          canAutoPrepare: false,
        );
        addTearDown(subject.vm.dispose);

        final request = subject.vm.prepareLearningTranscript();
        await _waitForRun(subject.coordinator, subject.repository.genService);
        final run = subject.repository.genService.lastRun;
        expect(run, isNotNull);
        run!
          ..emitProtocol()
          ..emitAccepted(attemptId: run.attemptId)
          ..emitFailed(code: 'generator_not_configured');
        await request;

        expect(subject.vm.state.phase, TranscriptReadinessPhase.failed);
      },
    );

    test('several usable tracks show the chooser and select on tap', () async {
      final subject = _readinessViewModel(
        tracks: const [_usableTrackA, _usableTrackB],
        canAutoPrepare: true,
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
    });

    test(
      'prepare runs resolve → generate → install → adopt to ready',
      () async {
        final subject = _readinessViewModel(
          tracks: const [],
          canAutoPrepare: true,
        );
        addTearDown(subject.vm.dispose);

        final request = subject.vm.prepareLearningTranscript();
        await _settle();

        expect(subject.vm.state.phase, TranscriptReadinessPhase.preparing);

        final generator = subject.repository.genService;
        final run = generator.lastRun!;
        expect(run.cancelled, isFalse);
        expect(subject.vm.state.canCancel, isTrue);

        // The run's protocol asks for a staged transcript.
        expect(run.eventsClosed, isFalse, reason: 'stream must be open');
        run.emitProtocol();
        await Future<void>.delayed(Duration.zero);
        run.emitAccepted(attemptId: run.attemptId);
        await Future<void>.delayed(Duration.zero);
        run.emitRunning('transcribing media');
        await Future<void>.delayed(Duration.zero);
        run.emitCompleted();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          subject.repository.genService.lastRun!.packagePathCompleted,
          isTrue,
          reason: 'packagePath must be completed by emitCompleted',
        );

        await request;

        final view = subject.coordinator.runViewFor(
          'material-1',
          MaterialCapability.read,
        );
        expect(
          view?.phase,
          CapabilityRunPhase.completed,
          reason: 'failure=${view?.failureCode}',
        );
        expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
        expect(subject.repository.finalizedSucceeded, 1);
        expect(subject.repository.adoptedReleases, [_edition.releaseId]);
        expect(subject.vm.state.failure, isNull);
      },
    );

    test(
      'completed Gen projects tokenized composition into the workbench',
      () async {
        final composition = ResolvedComposition(
          releaseId: 'release-1',
          editionId: 'edition-1',
          logicalText: 'Hello',
          sentences: const [
            CompositionSentence(
              id: 'cue-a',
              index: 0,
              text: 'Hello',
              startByte: 0,
              endByte: 5,
            ),
          ],
          anchors: const [],
          alignments: const {'cue-a': 0},
          transcript: _usableTrackA,
        );
        final subject = _readinessViewModel(
          tracks: const [],
          canAutoPrepare: true,
          resolveComposition: (_) async => composition,
        );
        addTearDown(subject.vm.dispose);

        final request = subject.vm.prepareLearningTranscript();
        await _waitForRun(subject.coordinator, subject.repository.genService);
        final run = subject.repository.genService.lastRun!;
        run
          ..emitProtocol()
          ..emitAccepted(attemptId: run.attemptId)
          ..emitCompleted();
        await request;
        await _settle();

        expect(subject.subtitle.primaryTrack?.id, _usableTrackA.id);
        expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
      },
    );

    test(
      'adopting another package re-projects it without switching media',
      () async {
        var composition = ResolvedComposition(
          releaseId: 'release-1',
          editionId: 'edition-1',
          logicalText: 'Hello',
          sentences: const [
            CompositionSentence(
              id: 'cue-a',
              index: 0,
              text: 'Hello',
              startByte: 0,
              endByte: 5,
            ),
          ],
          anchors: const [],
          alignments: const {'cue-a': 0},
          transcript: _usableTrackA,
        );
        final subject = _readinessViewModel(
          tracks: const [_usableTrackA],
          canAutoPrepare: true,
          resolveComposition: (_) async => composition,
        );
        addTearDown(subject.vm.dispose);
        subject.subtitle.setPrimaryTrack(_usableTrackA);

        composition = ResolvedComposition(
          releaseId: 'release-2',
          editionId: 'edition-1',
          logicalText: 'World',
          sentences: const [
            CompositionSentence(
              id: 'cue-b',
              index: 0,
              text: 'World',
              startByte: 0,
              endByte: 5,
            ),
          ],
          anchors: const [],
          alignments: const {'cue-b': 0},
          transcript: _usableTrackB,
        );

        await subject.vm.refreshAdoptedComposition();

        expect(subject.subtitle.primaryTrack?.id, _usableTrackB.id);
        expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
      },
    );

    test('a failed run shows failed and retry recovers', () async {
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: true,
      );
      addTearDown(subject.vm.dispose);

      var request = subject.vm.prepareLearningTranscript();
      await _waitForRun(subject.coordinator, subject.repository.genService);
      final run = subject.repository.genService.lastRun!;
      run.emitProtocol();
      run.emitAccepted(attemptId: run.attemptId);
      run.emitFailed(code: 'generation_failed');
      await request;

      expect(subject.vm.state.phase, TranscriptReadinessPhase.failed);
      expect(subject.vm.state.canRetry, isTrue);
      expect(subject.repository.finalizedFailures, ['generation_failed']);

      request = subject.vm.retry();
      await _settle();
      final retryRun = subject.repository.genService.lastRun!;
      retryRun.emitProtocol();
      retryRun.emitAccepted(attemptId: retryRun.attemptId);
      retryRun.emitRunning('transcribing media');
      retryRun.emitCompleted();
      await request;

      expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
      expect(subject.repository.finalizedSucceeded, 1);
    });

    test('cancel stops the run and returns to the missing surface', () async {
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: true,
      );
      addTearDown(subject.vm.dispose);

      final request = subject.vm.prepareLearningTranscript();
      await _waitForRun(subject.coordinator, subject.repository.genService);
      final run = subject.repository.genService.lastRun!;

      subject.vm.cancel();
      await _settle();
      await request;

      expect(run.cancelled, isTrue);
      expect(subject.repository.finalizedFailures, contains('cancelled'));
      expect(subject.vm.state.phase, TranscriptReadinessPhase.missing);
    });

    test('an already-completed capability run reads as ready', () async {
      final subject = _readinessViewModel(
        tracks: const [],
        canAutoPrepare: true,
      );
      addTearDown(subject.vm.dispose);
      subject.repository.capabilities = [_projectionDerivableRead];

      // Complete the read capability directly through the coordinator.
      final request = subject.coordinator.requestCapability(
        _mediaOnlyMaterial,
        MaterialCapability.read,
      );
      await _waitForRun(subject.coordinator, subject.repository.genService);
      final run = subject.repository.genService.lastRun!;
      run.emitProtocol();
      run.emitAccepted(attemptId: run.attemptId);
      run.emitRunning('transcribing media');
      run.emitCompleted();
      await request;
      await _settle();

      expect(subject.vm.state.phase, TranscriptReadinessPhase.ready);
    });
    group('composition to srt bridge', () {
      test('builds srt from reading text and anchor times', () {
        final srt = CompositionTranscriptBridge.compositionToSrt(
          {
            'text': 'Hello world. This is a test.',
            'anchors': [
              {
                'anchor_id': 'sentence-0',
                'kind': 'sentence',
                'start_offset': 0,
                'end_offset': 12,
              },
              {
                'anchor_id': 'sentence-1',
                'kind': 'sentence',
                'start_offset': 13,
                'end_offset': 28,
              },
            ],
          },
          {
            'alignments': [
              {'anchor_id': 'sentence-0', 'media_time_ms': 0},
              {'anchor_id': 'sentence-1', 'media_time_ms': 4000},
            ],
          },
        );

        expect(srt, isNotNull);
        expect(srt, contains('00:00:00,000 --> 00:00:04,000'));
        expect(srt, contains('Hello world.'));
        expect(srt, contains('This is a test.'));
      });

      test('drops sentences without times and empty text', () {
        final srt = CompositionTranscriptBridge.compositionToSrt(
          {
            'text': 'A. B.',
            'anchors': [
              {
                'anchor_id': 'sentence-0',
                'kind': 'sentence',
                'start_offset': 0,
                'end_offset': 2,
              },
              {
                'anchor_id': 'sentence-1',
                'kind': 'sentence',
                'start_offset': 3,
                'end_offset': 5,
              },
            ],
          },
          {
            'alignments': [
              {'anchor_id': 'sentence-0', 'media_time_ms': 1000},
            ],
          },
        );

        expect(srt, isNotNull);
        expect(srt, contains('A.'));
        expect(srt, isNot(contains('B.')));
      });
    });
  });
}

({
  TranscriptReadinessViewModel vm,
  SubtitleController subtitle,
  MaterialCapabilityCoordinator coordinator,
  _FakeCapabilityRepository repository,
})
_readinessViewModel({
  required List<SubtitleTrack> tracks,
  required bool canAutoPrepare,
  Future<ResolvedComposition?> Function(String materialId)? resolveComposition,
}) {
  final harness = _coordinatorHarness(tracks);
  if (resolveComposition != null) {
    harness.mediaSession.player.setMedia(
      id: 'media-1',
      path: '/tmp/media.wav',
      title: 'Lesson',
      fingerprint: 'fingerprint',
      kind: 'audio',
    );
  }
  harness.subtitle.setSubtitleResources(tracks);
  final repository = _FakeCapabilityRepository();
  final generator = repository.genService;
  final coordinator = MaterialCapabilityCoordinator(
    repository: repository,
    generator: generator,
  );
  final vm = TranscriptReadinessViewModel(
    subtitle: harness.subtitle,
    mediaSession: harness.mediaSession,
    preparationAvailability: () => canAutoPrepare
        ? TranscriptPreparationAvailability.ready
        : TranscriptPreparationAvailability.generatorUnavailable,
    coordinator: coordinator,
    currentMaterial: () => _mediaOnlyMaterial,
    resolveComposition: resolveComposition,
  )..bind(text: (key) => key);
  return (
    vm: vm,
    subtitle: harness.subtitle,
    coordinator: coordinator,
    repository: repository,
  );
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// Waits until the production run is generating (the coordinator has
/// resolved editions and capabilities, started the run, and attached the
/// event listener — so emitted events cannot be lost).
Future<void> _waitForRun(
  MaterialCapabilityCoordinator coordinator,
  _FakeGenService service,
) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final view = coordinator.runViewFor('material-1', MaterialCapability.read);
    if (view?.phase == CapabilityRunPhase.generating) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
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
        managedStore: _UnavailableManagedStore(),
        materialRepository: _NoopLearningMaterialRepository(),
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

/// A fake generator service with a scriptable run.
final class _FakeGenService implements ListenGenProcessService {
  _FakeGenService();

  _FakeGenRun? lastRun;

  @override
  bool get isConfigured => true;

  @override
  ContentGeneratorState get state => ContentGeneratorState.ready;

  @override
  Future<ListenGenProcessRun> start(CapabilityGenerationRequest request) async {
    final run = _FakeGenRun(request);
    lastRun = run;
    return run;
  }
}

final class _FakeGenRun implements ListenGenProcessRun {
  _FakeGenRun(this.request);

  final CapabilityGenerationRequest request;
  final StreamController<GenMachineEvent> _events =
      StreamController<GenMachineEvent>();
  final Completer<String> _packagePath = Completer<String>();
  bool cancelled = false;
  bool packagePathCompleted = false;
  int _sequence = 0;
  final String attemptId = 'attempt-1';

  @override
  Stream<GenMachineEvent> get events => _events.stream;

  @override
  Future<String> get packagePath => _packagePath.future;

  bool get eventsClosed => _events.isClosed;

  @override
  void cancel() {
    cancelled = true;
    // Mirrors the real process service: cancellation terminates the run and
    // its artifact handoff fails with the `cancelled` code.
    if (!_packagePath.isCompleted) {
      _packagePath.completeError(_FakeGenFailure('cancelled'));
    }
  }

  @override
  Future<void> cleanUp() async {
    if (!_events.isClosed) await _events.close();
  }

  void emitProtocol() => _events.add(
    GenMachineEvent(sequence: _sequence++, kind: GenEventKind.protocol),
  );

  void emitAccepted({required String attemptId}) => _events.add(
    GenMachineEvent(
      sequence: _sequence++,
      kind: GenEventKind.accepted,
      attemptId: attemptId,
    ),
  );

  void emitRunning(String stage) => _events.add(
    GenMachineEvent(
      sequence: _sequence++,
      kind: GenEventKind.running,
      stage: stage,
    ),
  );

  void emitCompleted() {
    _events.add(
      GenMachineEvent(
        sequence: _sequence++,
        kind: GenEventKind.completed,
        packageSha256: _packageSha,
      ),
    );
    _packagePath.complete('/tmp/generated.content-package.zip');
    packagePathCompleted = true;
  }

  void emitCompletedWithoutSha() {
    _events.add(
      GenMachineEvent(sequence: _sequence++, kind: GenEventKind.completed),
    );
  }

  void emitFailed({required String code}) {
    _events.add(
      GenMachineEvent(
        sequence: _sequence++,
        kind: GenEventKind.failed,
        code: code,
        message: code,
      ),
    );
    _packagePath.completeError(_FakeGenFailure(code));
  }

  String get _packageSha =>
      'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
}

final class _FakeGenFailure implements Exception {
  const _FakeGenFailure(this.code);
  final String code;
}

/// The scriptable capability + package-lifecycle repository the coordinator
/// drives.
final class _FakeCapabilityRepository implements CapabilityRepository {
  _FakeCapabilityRepository();

  final _FakeGenService genService = _FakeGenService();
  List<MaterialCapabilityProjection> capabilities = [_projectionDerivableRead];
  List<LearningEdition> editions = [];
  int finalizedSucceeded = 0;
  final List<String> finalizedFailures = [];
  final List<String> adoptedReleases = [];

  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '', code: '$error');

  @override
  Future<MaterialDetails> readMaterial(String materialId) async =>
      _mediaOnlyMaterial;

  @override
  Future<List<MaterialCapabilityProjection>> listCapabilities(
    String materialId,
  ) async => capabilities;

  @override
  Future<CapabilityAttempt> startAttempt(
    String materialId,
    String capability,
  ) async => CapabilityAttempt(
    attemptId: 'attempt-1',
    status: 'running',
    startedAtMs: 1,
    finishedAtMs: null,
    failureReason: null,
    producerToolId: null,
    producerToolVersion: null,
  );

  @override
  Future<CapabilityAttempt> finalizeAttempt({
    required String materialId,
    required String attemptId,
    required bool succeeded,
    String? failureReason,
    String? toolId,
    String? toolVersion,
  }) async {
    if (succeeded) {
      finalizedSucceeded++;
    } else {
      finalizedFailures.add(failureReason ?? 'unknown');
    }
    return CapabilityAttempt(
      attemptId: attemptId,
      status: succeeded ? 'succeeded' : 'failed',
      startedAtMs: 1,
      finishedAtMs: 2,
      failureReason: failureReason,
      producerToolId: toolId,
      producerToolVersion: toolVersion,
    );
  }

  @override
  Future<AdoptedComposition> readAdoptedComposition(String materialId) async =>
      throw const ApiFailure(raw: 'not found', code: 'not_found');

  @override
  Future<List<int>> readCompositionResourcePayload(
    String materialId,
    String resourceId,
  ) async => throw const ApiFailure(raw: 'payload not found');

  @override
  Future<List<int>> readCompositionRenditionBlob(
    String materialId,
    String renditionId,
  ) async => throw StateError('unexpected readCompositionRenditionBlob');

  @override
  Future<LearningEdition> installPackage(
    String materialId,
    String packagePath,
  ) async => _edition;

  @override
  Future<List<LearningEdition>> listEditions(String materialId) async =>
      editions;

  @override
  Future<LearningEdition> adoptEdition(
    String materialId,
    String releaseId,
  ) async {
    adoptedReleases.add(releaseId);
    return _edition;
  }

  @override
  Future<void> deleteEdition(
    String materialId,
    String releaseId,
  ) async {
    editions.removeWhere((e) => e.releaseId == releaseId);
  }
}

const _projectionDerivableRead = MaterialCapabilityProjection(
  capability: MaterialCapability.read,
  status: MaterialCapabilityStatus.derivable,
  latestAttempt: null,
);

final _edition = LearningEdition(
  materialId: 'material-1',
  materialRevisionId: 'revision-1',
  editionId: 'edition:material-1',
  releaseId:
      'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  title: 'Lesson',
  targetLanguage: 'en',
  supportLanguages: [],
  installedAtMs: 1,
  adoptedAtMs: 2,
  adopted: true,
  resources: [
    LearningEditionResource(
      resourceId:
          'sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      kind: 'structured_reading',
      role: 'base',
      required: true,
      availability: 'available',
      reviewStatus: 'machine_checked',
      contentLanguage: 'en',
      supportLanguages: [],
    ),
  ],
  renditions: [],
);

final _mediaOnlyMaterial = MaterialDetails(
  material: const LearningMaterial(
    id: 'material-1',
    currentRevisionId: 'revision-1',
    retainedAtMs: 1,
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
  currentRevision: MaterialRevision(
    id: 'revision-1',
    materialId: 'material-1',
    title: 'Lesson',
    sourceAssets: const [],
    documentRenditions: const [],
    mediaRenditions: const [
      MediaRendition(
        id: 'media-rendition-1',
        origin: RenditionOrigin.source,
        kind: MediaRenditionKind.audio,
        mediaType: 'audio/wav',
        fingerprint: 'fingerprint',
        availability: MediaRenditionAvailability.available,
        mediaId: 'media-1',
        mediaSha256: null,
        mediaByteSize: null,
      ),
    ],
    createdAtMs: 0,
  ),
  shape: MaterialShape.audio,
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
  Future<CoreTimelineExport> exportTimelineJson(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<void> updateTrackLanguage(String trackId, String language) async =>
      throw UnimplementedError();
  @override
  Future<void> activateWordTimeline(String timelineId) async =>
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
  Future<MediaItem> registerMedia(
    String path, {
    required bool retain,
    String? title,
    String? kind,
  }) async => MediaItem(
    id: 'media-1',
    path: path,
    fingerprint: 'fingerprint',
    title: title ?? 'Title',
    kind: 'audio',
    durationMs: 2200,
    availability: 'available',
    createdAtMs: 0,
    updatedAtMs: 0,
    retainedAtMs: retain ? 1 : null,
  );
  @override
  Future<MediaItem> retainMedia(String mediaId) async =>
      throw UnimplementedError();
  @override
  Future<MediaItem> unretainMedia(String mediaId) async =>
      throw UnimplementedError();
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

/// A store that can never be reached — used by harnesses whose scenario does
/// not touch retention, so the store is a wall rather than a promise.
final class _UnavailableManagedStore implements ManagedAssetStoreService {
  @override
  Future<ManagedAssetCopy> copyIntoStore({
    required String sourcePath,
    String? mediaKind,
  }) => throw const ManagedStoreUnavailable();
  @override
  Future<ManagedAssetCopy> copyBytesIntoStore({
    required List<int> bytes,
    required String mediaKind,
  }) => throw const ManagedStoreUnavailable();
  @override
  Future<List<int>?> readBytes(String path) async => null;
  @override
  Future<void> deleteStoreCopy(String path) async {}
}

/// Transcript readiness never touches the learning-material boundary; this
/// wall keeps the coordinator constructible and provably inert.
final class _NoopLearningMaterialRepository
    implements LearningMaterialRepository {
  @override
  bool get isAvailable => false;

  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '', code: '$error');

  @override
  Future<List<MaterialDetails>> listLearningMaterials() async => const [];

  @override
  Future<MaterialDetails> createLearningMaterial(
    CreateLearningMaterialInput input, {
    MaterialRetainDirective retain = const MaterialRetainOmitted(),
  }) => throw UnimplementedError();

  @override
  Future<MaterialDetails> readLearningMaterial(String materialId) =>
      throw UnimplementedError();

  @override
  Future<MaterialDetails> appendMaterialRevision(
    String materialId,
    AppendMaterialRevisionInput input,
  ) => throw UnimplementedError();

  @override
  Future<MaterialRevision> readMaterialRevision(
    String materialId,
    String revisionId,
  ) => throw UnimplementedError();

  @override
  Future<MaterialDetails> retainLearningMaterial(String materialId) =>
      throw UnimplementedError();

  @override
  Future<MaterialDetails> unretainLearningMaterial(String materialId) =>
      throw UnimplementedError();

  @override
  Future<MaterialDetails> resolveMaterialForMedia(String mediaId) =>
      throw UnimplementedError();

  @override
  Future<MaterialRevision> updateSourceAssetAvailability(
    String materialId,
    String sourceAssetId,
    SourceAssetAvailability availability,
  ) => throw UnimplementedError();

  @override
  Future<List<MaterialCapabilityProjection>> listMaterialCapabilities(
    String materialId,
  ) => throw UnimplementedError();
}
