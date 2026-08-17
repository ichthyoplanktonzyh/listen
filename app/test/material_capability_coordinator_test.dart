import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/material_capability_coordinator.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/models/adopted_composition.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/gen_machine_event.dart';
import 'package:llplayer_next/models/learning_edition.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/capability_generation_request.dart';
import 'package:llplayer_next/services/content_generator_setup.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';

import 'support/learning_material_fixtures.dart';

/// The coordinator is the deep completion flow: resolution order (adopted →
/// candidate adopt → local import → production), durable attempts, cancellation
/// with latest-request-wins, and honest state transitions. This harness drives
/// every branch with scriptable repository and generator fakes.

void main() {
  late _Harness harness;

  setUp(() {
    harness = _Harness();
  });

  test(
    'an already adopted satisfying composition resolves immediately',
    () async {
      harness.repo.editions = [_editionCopy(adopted: true)];
      harness.repo.capabilities = const [];

      final outcome = await harness.request(MaterialCapability.read);

      expect(outcome, isA<CapabilityAvailable>());
      expect(
        harness.gen.startCount,
        0,
        reason: 'no production run should start',
      );
      expect(harness.repo.adoptedReleases, isEmpty);
    },
  );

  test(
    'forceProduce forces a fresh gen run even when an adopted edition exists',
    () async {
      harness.repo.editions = [_editionCopy(adopted: true)];
      harness.repo.capabilities = const [];

      final requestFuture = harness.request(
        MaterialCapability.read,
        forceProduce: true,
      );
      await _settle();

      expect(harness.gen.startCount, 1);
      harness.gen.lastRun!
        ..emitProtocol()
        ..emitAccepted(attemptId: 'attempt-1');
      await _settle();
      harness.gen.lastRun!.emitCompleted();
      await _settle();
      await _settle();

      final outcome = await requestFuture;
      expect(outcome, isA<CapabilityAvailable>());
      expect(harness.runView!.phase, CapabilityRunPhase.completed);
    },
  );

  test('an installed candidate is adopted explicitly', () async {
    harness.repo.editions = [_editionCopy(adopted: false)];

    final outcome = await harness.request(MaterialCapability.read);

    expect(outcome, isA<CapabilityAvailable>());
    expect(harness.repo.adoptedReleases, [_satisfyingEdition.releaseId]);
    expect(harness.gen.startCount, 0);
  });

  test('a candidate whose adoption fails degrades into production', () async {
    harness.repo.editions = [_editionCopy(adopted: false)];
    harness.repo.adoptFailuresRemaining = 1;

    final requestFuture = harness.request(MaterialCapability.read);
    await _settle();

    // The failed adoption is a warning, not a verdict: production proceeds.
    expect(harness.gen.startCount, 1);
    harness.gen.lastRun!
      ..emitProtocol()
      ..emitAccepted(attemptId: 'attempt-1');
    await _settle();
    harness.gen.lastRun!.emitCompleted();
    await _settle();
    await _settle();

    final outcome = await requestFuture;
    expect(outcome, isA<CapabilityAvailable>());
    expect(harness.runView!.phase, CapabilityRunPhase.completed);
  });

  test('an explicit local package import installs and adopts', () async {
    final outcome = await harness.request(
      MaterialCapability.read,
      localPackagePath: '/tmp/local.package.zip',
    );

    expect(outcome, isA<CapabilityAvailable>());
    expect(harness.repo.installedPackagePaths, ['/tmp/local.package.zip']);
    expect(harness.repo.adoptedReleases, [_satisfyingEdition.releaseId]);
    expect(harness.gen.startCount, 0);
  });

  test('a local import failure fails the run', () async {
    harness.repo.failInstall = true;

    final outcome = await harness.request(
      MaterialCapability.read,
      localPackagePath: '/tmp/local.package.zip',
    );

    expect(outcome, isA<CapabilityFailed>());
    expect(harness.runView!.phase, CapabilityRunPhase.failed);
  });

  test('an unavailable capability resolves as unavailable', () async {
    harness.repo.capabilities = const [
      MaterialCapabilityProjection(
        capability: MaterialCapability.read,
        status: MaterialCapabilityStatus.unavailable,
        latestAttempt: null,
      ),
    ];

    final outcome = await harness.request(MaterialCapability.read);

    expect(outcome, isA<CapabilityUnavailable>());
    expect(harness.gen.startCount, 0);
  });

  test(
    'production runs resolve → attempt → generate → install → adopt → finalize',
    () async {
      final requestFuture = harness.request(MaterialCapability.read);
      await _settle();

      expect(harness.repo.attemptCount, 1);
      expect(harness.gen.startCount, 1);
      expect(harness.runView!.phase, CapabilityRunPhase.generating);

      final run = harness.gen.lastRun!;
      expect(run.request.requestJson['attempt_id'], 'attempt-1');
      expect(run.request.requestJson['requested_capability'], 'read');
      expect(
        run.request.requestJson['material']['material_id'],
        _mediaOnlyMaterial.material.id,
      );

      run.emitProtocol();
      await _settle();
      run.emitAccepted(attemptId: 'attempt-1');
      await _settle();
      run.emitRunning('transcribing');
      await _settle();
      expect(harness.runView!.stage, 'transcribing');

      run.emitCompleted();
      await _settle();
      await _settle();

      final outcome = await requestFuture;
      expect(outcome, isA<CapabilityAvailable>());
      expect(harness.runView!.phase, CapabilityRunPhase.completed);
      expect(harness.runView!.producedPackageSha256, isNotNull);
      expect(harness.repo.finalizedSucceeded, 1);
      expect(harness.repo.adoptedReleases, [_satisfyingEdition.releaseId]);
      expect(harness.repo.installedPackagePaths, ['/tmp/generated.zip']);
    },
  );

  test(
    'the selected media subtitle becomes Gen forced-alignment input',
    () async {
      harness.selectedSubtitle = const SubtitleTrack(
        id: 'track-1',
        mediaId: 'media-1',
        language: 'en',
        cues: [
          Cue(
            id: 'cue-1',
            index: 0,
            start: Duration(milliseconds: 120),
            end: Duration(milliseconds: 1450),
            text: 'Use the selected subtitle.',
            tokens: [],
          ),
        ],
      );

      final baseRevision = _mediaOnlyMaterial.currentRevision;
      final material = MaterialDetails(
        material: _mediaOnlyMaterial.material,
        currentRevision: MaterialRevision(
          id: baseRevision.id,
          materialId: baseRevision.materialId,
          title: baseRevision.title,
          sourceAssets: baseRevision.sourceAssets,
          documentRenditions: baseRevision.documentRenditions,
          mediaRenditions: [
            const MediaRendition(
              id: 'media-rendition-2',
              origin: RenditionOrigin.source,
              kind: MediaRenditionKind.audio,
              mediaType: 'audio/wav',
              fingerprint: 'other-fingerprint',
              availability: MediaRenditionAvailability.available,
              mediaId: 'media-2',
              mediaSha256: null,
              mediaByteSize: null,
            ),
            ...baseRevision.mediaRenditions,
          ],
          createdAtMs: baseRevision.createdAtMs,
        ),
        shape: MaterialShape.audio,
      );

      final requestFuture = harness.request(
        MaterialCapability.read,
        material: material,
      );
      await _settle();

      expect(
        harness.gen.lastRun!.request.subtitleSrt,
        '1\n00:00:00,120 --> 00:00:01,450\n'
        'Use the selected subtitle.\n\n',
      );

      harness.gen.lastRun!
        ..emitProtocol()
        ..emitAccepted(attemptId: 'attempt-1')
        ..emitCompleted();
      await _settle();
      await _settle();
      await requestFuture;
    },
  );

  test(
    'a generator failure finalizes the attempt and reports the code',
    () async {
      final requestFuture = harness.request(MaterialCapability.read);
      await _settle();
      final run = harness.gen.lastRun!;

      run.emitProtocol();
      await _settle();
      run.emitFailed(code: 'provider_timeout');
      await _settle();
      await _settle();

      final outcome = await requestFuture;
      expect(outcome, isA<CapabilityFailed>());
      expect((outcome as CapabilityFailed).retryable, isTrue);
      expect(harness.repo.finalizedFailures, ['provider_timeout']);
      expect(harness.runView!.phase, CapabilityRunPhase.failed);
      expect(harness.runView!.failureCode, 'provider_timeout');
    },
  );

  test(
    'a process failure before machine events keeps its stable code',
    () async {
      final requestFuture = harness.request(MaterialCapability.read);
      await _settle();

      harness.gen.lastRun!.failProcess('generator_python_unavailable');
      await _settle();
      await _settle();

      final outcome = await requestFuture;
      expect(outcome, isA<CapabilityFailed>());
      expect(harness.repo.finalizedFailures, ['generator_python_unavailable']);
      expect(harness.runView!.failureCode, 'generator_python_unavailable');
    },
  );

  test('a failed attempt is still retryable through a fresh attempt', () async {
    harness.repo.failNextStart = true;
    final first = await harness.request(MaterialCapability.read);
    expect(first, isA<CapabilityFailed>());
    expect(harness.repo.attemptCount, 1);

    final secondFuture = harness.request(MaterialCapability.read);
    await _settle();
    expect(harness.repo.attemptCount, 2, reason: 'retry opens a new attempt');
    final run = harness.gen.lastRun!;
    run.emitProtocol();
    await _settle();
    run.emitAccepted(attemptId: 'attempt-1');
    await _settle();
    run.emitCompleted();
    await _settle();
    await _settle();

    expect(await secondFuture, isA<CapabilityAvailable>());
    expect(harness.repo.finalizedSucceeded, 1);
  });

  test('cancellation finalizes as cancelled and drops the process', () async {
    final requestFuture = harness.request(MaterialCapability.read);
    await _settle();
    final run = harness.gen.lastRun!;

    await harness.coordinator.cancel('material-1', MaterialCapability.read);
    await _settle();

    expect(run.cancelled, isTrue);
    expect(harness.repo.finalizedFailures, ['cancelled']);

    final outcome = await requestFuture;
    expect(outcome, isA<CapabilityCancelled>());
    expect(harness.runView!.phase, CapabilityRunPhase.cancelled);
  });

  test(
    'a newer request replaces the stale run and drops its results',
    () async {
      final first = harness.request(MaterialCapability.read);
      await _settle();
      final staleRun = harness.gen.lastRun!;
      expect(staleRun.cancelled, isFalse);

      final second = harness.request(MaterialCapability.read);
      await _settle();

      // The stale run is terminated by the replacement.
      expect(staleRun.cancelled, isTrue);
      expect(harness.gen.startCount, 2);
      expect(await first, isA<CapabilityReplaced>());
      // Only the newer run's results are installed and adopted.
      expect(harness.repo.finalizedSucceeded, 0);

      harness.gen.lastRun!
        ..emitProtocol()
        ..emitAccepted(attemptId: 'attempt-1');
      await _settle();
      harness.gen.lastRun!.emitCompleted();
      await _settle();
      await _settle();

      expect(await second, isA<CapabilityAvailable>());
      expect(harness.repo.finalizedSucceeded, 1);
      expect(harness.runView!.phase, CapabilityRunPhase.completed);
    },
  );

  test('an install failure finalizes the attempt and fails the run', () async {
    harness.repo.failInstall = true;
    final requestFuture = harness.request(MaterialCapability.read);
    await _settle();
    final run = harness.gen.lastRun!;
    run
      ..emitProtocol()
      ..emitAccepted(attemptId: 'attempt-1');
    await _settle();
    run.emitCompleted();
    await _settle();
    await _settle();

    final outcome = await requestFuture;
    expect(outcome, isA<CapabilityFailed>());
    expect(harness.repo.finalizedFailures, isNotEmpty);
    expect(harness.runView!.phase, CapabilityRunPhase.failed);
  });

  test('an adoption failure finalizes the attempt and fails the run', () async {
    harness.repo.adoptFailuresRemaining = 1;
    final requestFuture = harness.request(MaterialCapability.read);
    await _settle();
    harness.gen.lastRun!
      ..emitProtocol()
      ..emitAccepted(attemptId: 'attempt-1');
    await _settle();
    harness.gen.lastRun!.emitCompleted();
    await _settle();
    await _settle();

    final outcome = await requestFuture;
    expect(outcome, isA<CapabilityFailed>());
    expect(harness.runView!.phase, CapabilityRunPhase.failed);
  });

  test('a listing failure is a failed attempt, not a verdict', () async {
    harness.repo.failListCapabilities = true;

    final outcome = await harness.request(MaterialCapability.read);

    expect(outcome, isA<CapabilityFailed>());
    expect(harness.runView!.phase, CapabilityRunPhase.failed);
    expect(harness.gen.startCount, 0);
  });

  test(
    'a media edition does not satisfy watch without a video material',
    () async {
      // The edition carries a media rendition, but the material is audio-only:
      // watch stays unsatisfied and production is attempted (and fails here on
      // the generator level is not reached — the projection gates it).
      harness.repo.editions = [_mediaEdition];

      final outcome = await harness.request(MaterialCapability.watch);

      // No satisfying adopted edition and no derivable watch projection.
      expect(outcome, isA<CapabilityUnavailable>());
      expect(harness.gen.startCount, 0);
    },
  );

  test(
    'derived document audio satisfies listen without source audio',
    () async {
      harness.repo.editions = [_mediaEdition];
      harness.repo.capabilities = const [];

      final outcome = await harness.request(
        MaterialCapability.listen,
        material: _documentMaterial(language: 'en'),
      );

      expect(outcome, isA<CapabilityAvailable>());
      expect(harness.gen.startCount, 0);
      expect(harness.repo.attemptCount, 0);
    },
  );

  test(
    'an empty-plan completion is a satisfied outcome, not a failure',
    () async {
      final requestFuture = harness.request(MaterialCapability.read);
      await _settle();
      harness.gen.lastRun!
        ..emitProtocol()
        ..emitAccepted(attemptId: 'attempt-1');
      await _settle();
      harness.gen.lastRun!.emitCompletedWithoutSha();
      await _settle();
      await _settle();

      final outcome = await requestFuture;
      expect(outcome, isA<CapabilityAvailable>());
      expect(harness.repo.finalizedFailures, isEmpty);
      expect(
        harness.repo.finalizedSucceeded,
        1,
        reason: 'an empty plan is a successful attempt',
      );
      expect(harness.runView!.phase, CapabilityRunPhase.completed);
    },
  );

  test('warnings surface on the run view', () async {
    final requestFuture = harness.request(MaterialCapability.read);
    await _settle();
    harness.gen.lastRun!
      ..emitProtocol()
      ..emitAccepted(attemptId: 'attempt-1');
    await _settle();
    harness.gen.lastRun!.emitWarning('slow: slow lane');
    await _settle();
    expect(harness.runView!.warnings, contains('slow: slow lane'));
    harness.gen.lastRun!.emitCompleted();
    await _settle();
    await _settle();
    await requestFuture;
    expect(harness.runView!.phase, CapabilityRunPhase.completed);
  });

  test('an accepted attempt mismatch is a protocol violation', () async {
    final requestFuture = harness.request(MaterialCapability.read);
    await _settle();
    final run = harness.gen.lastRun!;
    run.emitProtocol();
    await _settle();
    run.emitAccepted(attemptId: 'attempt-other');
    await _settle();

    // The mismatch terminates the run; the session records the warning.
    expect(run.cancelled, isTrue);
    expect(
      harness.runView!.warnings.any((w) => w.contains('attempt_id_mismatch')),
      isTrue,
    );
    await _settle();
    await _settle();
    expect(await requestFuture, isA<CapabilityFailed>());
  });

  test(
    'an already-satisfied projection resolves as available without a run',
    () async {
      // The material has no document rendition, but the projection already
      // reports read available (an adopted composition the learner has): the
      // capability is present, never reported as broken.
      harness.repo.capabilities = const [
        MaterialCapabilityProjection(
          capability: MaterialCapability.read,
          status: MaterialCapabilityStatus.available,
          latestAttempt: null,
        ),
      ];

      final outcome = await harness.request(MaterialCapability.read);

      expect(outcome, isA<CapabilityAvailable>());
      expect(harness.gen.startCount, 0);
      expect(harness.repo.attemptCount, 0);
      expect(harness.runView!.phase, CapabilityRunPhase.completed);
    },
  );

  test(
    'a leftover generating projection is superseded by a fresh attempt',
    () async {
      // A projection still marked generating is a running attempt nobody owns
      // (for example after an App restart); the new request supersedes it via
      // Core's atomic start and produces afresh.
      harness.repo.capabilities = const [
        MaterialCapabilityProjection(
          capability: MaterialCapability.read,
          status: MaterialCapabilityStatus.generating,
          latestAttempt: null,
        ),
      ];

      final requestFuture = harness.request(MaterialCapability.read);
      await _settle();

      expect(harness.repo.attemptCount, 1);
      expect(harness.gen.startCount, 1);

      harness.gen.lastRun!
        ..emitProtocol()
        ..emitAccepted(attemptId: 'attempt-1');
      await _settle();
      harness.gen.lastRun!.emitCompleted();
      await _settle();
      await _settle();

      expect(await requestFuture, isA<CapabilityAvailable>());
    },
  );

  test('the request declares reusable adopted resources with exact payload '
      'facts', () async {
    harness.repo.composition = _adoptedComposition;
    harness.repo.resourcePayloads[_adoptedResourceId] = utf8.encode(
      '{"text":"Hello","anchors":[]}',
    );

    final requestFuture = harness.request(MaterialCapability.read);
    await _settleUntil(() => harness.gen.hasRun);

    final resources =
        harness.gen.lastRun!.request.requestJson['available_resources']
            as List<dynamic>;
    expect(resources, hasLength(1));
    final entry = resources.single as Map<String, dynamic>;
    expect(entry['resource_id'], 'sha256:$_adoptedResourceId');
    expect(entry['kind'], 'structured_reading');
    expect(entry['schema'], 'listen.structured_reading.v1');
    expect(entry['role'], 'base');
    expect(entry['content_language'], 'en');
    expect(entry['material_revision_id'], 'revision-1');
    final blob = entry['blob'] as Map<String, dynamic>;
    expect(blob['digest'], 'sha256:$_adoptedPayloadDigest');
    expect(blob['size_bytes'], 28);
    final path = blob['path'] as String;
    expect(path, isNotEmpty);
    expect(await File(path).readAsString(), '{"text":"Hello","anchors":[]}');

    harness.gen.lastRun!
      ..emitProtocol()
      ..emitAccepted(attemptId: 'attempt-1');
    await _settle();
    harness.gen.lastRun!.emitCompleted();
    await _settle();
    await _settle();
    await requestFuture;
  });

  test('an unreadable resource payload is not declared for reuse', () async {
    // The adopted composition declares the structured reading, but its
    // payload cannot be read from Core: the request must not claim a reuse
    // it cannot back, and generation proceeds without it.
    harness.repo.composition = _adoptedComposition;

    final requestFuture = harness.request(MaterialCapability.read);
    await _settleUntil(() => harness.gen.hasRun);

    final resources =
        harness.gen.lastRun!.request.requestJson['available_resources']
            as List<dynamic>;
    expect(resources, isEmpty);

    harness.gen.lastRun!
      ..emitProtocol()
      ..emitAccepted(attemptId: 'attempt-1');
    await _settle();
    harness.gen.lastRun!.emitCompleted();
    await _settle();
    await _settle();
    await requestFuture;
  });

  test(
    'the request target language is the document rendition language',
    () async {
      final documentMaterial = _documentMaterial(language: 'zh');

      final requestFuture = harness.request(
        MaterialCapability.read,
        material: documentMaterial,
      );
      await _settle();

      expect(
        harness.gen.lastRun!.request.requestJson['edition']['target_language'],
        'zh',
      );

      harness.gen.lastRun!
        ..emitProtocol()
        ..emitAccepted(attemptId: 'attempt-1');
      await _settle();
      harness.gen.lastRun!.emitCompleted();
      await _settle();
      await _settle();
      await requestFuture;
    },
  );

  test('a material with no language fact declares und, never a guessed '
      'surface language', () async {
    final requestFuture = harness.request(MaterialCapability.read);
    await _settle();

    expect(
      harness.gen.lastRun!.request.requestJson['edition']['target_language'],
      'und',
    );

    harness.gen.lastRun!
      ..emitProtocol()
      ..emitAccepted(attemptId: 'attempt-1');
    await _settle();
    harness.gen.lastRun!.emitCompleted();
    await _settle();
    await _settle();
    await requestFuture;
  });
}

final class _Harness {
  final repo = _FakeCapabilityRepository();
  final gen = _FakeGenService();
  SubtitleTrack? selectedSubtitle;
  late final MaterialCapabilityCoordinator coordinator =
      MaterialCapabilityCoordinator(
        repository: repo,
        generator: gen,
        subtitleTrackForMedia: (rendition) =>
            selectedSubtitle?.mediaId == rendition.mediaId
            ? selectedSubtitle
            : null,
        providerArguments: () => const ['--tts-provider', 'say'],
      );

  Future<CapabilityOutcome> request(
    MaterialCapability capability, {
    MaterialDetails? material,
    String? localPackagePath,
    bool forceProduce = false,
  }) => coordinator.requestCapability(
    material ?? _mediaOnlyMaterial,
    capability,
    localPackagePath: localPackagePath,
    forceProduce: forceProduce,
  );

  CapabilityRunView? get runView =>
      coordinator.runViewFor('material-1', MaterialCapability.read);
}

final class _FakeGenService implements ListenGenProcessService {
  _FakeGenService();

  _FakeGenRun? lastRun;
  int startCount = 0;

  bool get hasRun => lastRun != null;

  @override
  bool get isConfigured => true;

  @override
  ContentGeneratorState get state => ContentGeneratorState.ready;

  @override
  Future<ListenGenProcessRun> start(CapabilityGenerationRequest request) async {
    startCount++;
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
  int _sequence = 0;

  @override
  Stream<GenMachineEvent> get events => _events.stream;

  @override
  Future<String> get packagePath => _packagePath.future;

  @override
  void cancel() {
    cancelled = true;
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

  void emitWarning(String text) => _events.add(
    GenMachineEvent(
      sequence: _sequence++,
      kind: GenEventKind.warning,
      warningCode: text.split(': ').first,
      warningMessage: text.split(': ').last,
    ),
  );

  void emitCompleted() {
    _events.add(
      GenMachineEvent(
        sequence: _sequence++,
        kind: GenEventKind.completed,
        packageSha256: 'sha256:${'b' * 64}',
      ),
    );
    _packagePath.complete('/tmp/generated.zip');
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

  void failProcess(String code) {
    _packagePath.completeError(ListenGenProcessFailure(code, retryable: false));
  }
}

final class _FakeGenFailure implements Exception {
  const _FakeGenFailure(this.code);
  final String code;
}

final class _FakeCapabilityRepository implements CapabilityRepository {
  _FakeCapabilityRepository();

  final _FakeGenService genService = _FakeGenService();
  List<MaterialCapabilityProjection> capabilities = [
    const MaterialCapabilityProjection(
      capability: MaterialCapability.read,
      status: MaterialCapabilityStatus.derivable,
      latestAttempt: null,
    ),
    const MaterialCapabilityProjection(
      capability: MaterialCapability.watch,
      status: MaterialCapabilityStatus.unavailable,
      latestAttempt: null,
    ),
  ];
  List<LearningEdition> editions = [];
  int attemptCount = 0;
  int finalizedSucceeded = 0;
  final List<String> finalizedFailures = [];
  final List<String> adoptedReleases = [];
  final List<String> installedPackagePaths = [];
  int adoptFailuresRemaining = 0;
  bool failInstall = false;
  bool failNextStart = false;
  bool failListCapabilities = false;

  /// The adopted composition a production run may reuse resources from; null
  /// reads as Core's typed not-found (no adopted composition).
  AdoptedComposition? composition;

  /// Keyed by resource id: the exact payload bytes behind each declared
  /// resource. Missing payloads read as unreadable and are not reused.
  final Map<String, List<int>> resourcePayloads = {};
  bool failReadComposition = false;

  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '', code: '$error');

  @override
  Future<MaterialDetails> readMaterial(String materialId) async =>
      _mediaOnlyMaterial;

  @override
  Future<List<MaterialCapabilityProjection>> listCapabilities(
    String materialId,
  ) async {
    if (failListCapabilities) throw const ApiFailure(raw: 'listing failed');
    return capabilities;
  }

  @override
  Future<CapabilityAttempt> startAttempt(
    String materialId,
    String capability,
  ) async {
    attemptCount++;
    if (failNextStart) {
      failNextStart = false;
      throw const ApiFailure(raw: 'start failed');
    }
    return const CapabilityAttempt(
      attemptId: 'attempt-1',
      status: 'running',
      startedAtMs: 1,
      finishedAtMs: null,
      failureReason: null,
      producerToolId: null,
      producerToolVersion: null,
    );
  }

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
  Future<LearningEdition> installPackage(
    String materialId,
    String packagePath,
  ) async {
    if (failInstall) throw const ApiFailure(raw: 'install failed');
    installedPackagePaths.add(packagePath);
    return _satisfyingEdition;
  }

  @override
  Future<List<LearningEdition>> listEditions(String materialId) async =>
      editions;

  @override
  Future<LearningEdition> adoptEdition(
    String materialId,
    String releaseId,
  ) async {
    if (adoptFailuresRemaining > 0) {
      adoptFailuresRemaining--;
      throw const ApiFailure(raw: 'adopt failed');
    }
    adoptedReleases.add(releaseId);
    return _satisfyingEdition;
  }

  @override
  Future<void> deleteEdition(String materialId, String releaseId) async {
    editions.removeWhere((edition) => edition.releaseId == releaseId);
  }

  @override
  Future<AdoptedComposition> readAdoptedComposition(String materialId) async {
    if (failReadComposition) throw const ApiFailure(raw: 'composition failed');
    final value = composition;
    if (value == null) {
      throw const ApiFailure(raw: 'not found', code: 'not_found');
    }
    return value;
  }

  @override
  Future<List<int>> readCompositionResourcePayload(
    String materialId,
    String resourceId,
  ) async {
    final payload = resourcePayloads[resourceId];
    if (payload == null) {
      throw const ApiFailure(raw: 'payload not found');
    }
    return payload;
  }

  @override
  Future<List<int>> readCompositionRenditionBlob(
    String materialId,
    String renditionId,
  ) async => throw StateError('unexpected readCompositionRenditionBlob');
}

LearningEdition _editionCopy({required bool adopted}) => LearningEdition(
  materialId: 'material-1',
  materialRevisionId: 'revision-1',
  editionId: 'edition:material-1',
  releaseId:
      'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  title: 'Lesson',
  targetLanguage: 'en',
  supportLanguages: [],
  installedAtMs: 1,
  adoptedAtMs: adopted ? 2 : null,
  adopted: adopted,
  resources: const [
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
  renditions: const [],
);

final _satisfyingEdition = LearningEdition(
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

final _mediaEdition = LearningEdition(
  materialId: 'material-1',
  materialRevisionId: 'revision-1',
  editionId: 'edition:material-1',
  releaseId:
      'sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
  title: 'Lesson',
  targetLanguage: 'en',
  supportLanguages: [],
  installedAtMs: 1,
  adoptedAtMs: 2,
  adopted: true,
  resources: [],
  renditions: [
    LearningEditionRendition(
      renditionId:
          'sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      kind: 'media',
      available: true,
    ),
  ],
);

final _mediaOnlyMaterial = MaterialDetails(
  material: LearningMaterial(
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
    sourceAssets: [],
    documentRenditions: [],
    mediaRenditions: [
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

/// A text document material whose Source Document Rendition declares a
/// concrete language: the request's target language must come from here,
/// never from a hardcoded learner surface language.
MaterialDetails _documentMaterial({String language = 'zh'}) => materialDetails(
  title: 'Lesson',
  sourceAssets: [sourceAsset(id: 'source-1')],
  documentRenditions: [
    documentRenditionForText(
      '你好世界',
      id: 'document-rendition-1',
      language: language,
      sourceAssetId: 'source-1',
    ),
  ],
);

const _adoptedResourceId =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _adoptedPayloadDigest =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

/// The adopted composition a production run can reuse resources from.
AdoptedComposition get _adoptedComposition => AdoptedComposition(
  materialId: 'material-1',
  materialRevisionId: 'revision-1',
  releaseId:
      'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  editionId: 'edition:material-1',
  title: 'Lesson',
  targetLanguage: 'en',
  supportLanguages: const [],
  adoptedAtMs: 2,
  resources: const [
    AdoptedCompositionResource(
      resourceId: _adoptedResourceId,
      kind: 'structured_reading',
      schema: 'listen.structured_reading.v1',
      role: 'base',
      required: true,
      availability: 'available',
      contentLanguage: 'en',
      supportLanguages: [],
      payloadDigest: _adoptedPayloadDigest,
      payloadSizeBytes: 28,
      reviewStatus: 'machine_checked',
    ),
  ],
  renditions: const [],
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Settles until [condition] holds or a generous number of rounds passed.
/// Production now reads and materializes adopted resources before starting
/// the generator, so a single settle round is no longer enough.
Future<void> _settleUntil(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await _settle();
  }
}
