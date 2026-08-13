import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/material_capability_coordinator.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/models/adopted_composition.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/gen_machine_event.dart';
import 'package:llplayer_next/models/learning_edition.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/services/capability_generation_request.dart';
import 'package:llplayer_next/services/content_generator_setup.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';

/// The coordinator is the deep completion flow: resolution order (adopted →
/// candidate adopt → local import → production), durable attempts, cancellation
/// with latest-request-wins, and honest state transitions. This harness drives
/// every branch with scriptable repository and generator fakes.

void main() {
  late _Harness harness;

  setUp(() {
    harness = _Harness();
  });

  test('an already adopted satisfying composition resolves immediately', () async {
    harness.repo.editions = [_editionCopy(adopted: true)];
    harness.repo.capabilities = const [];

    final outcome = await harness.request(MaterialCapability.read);

    expect(outcome, isA<CapabilityAvailable>());
    expect(harness.gen.startCount, 0, reason: 'no production run should start');
    expect(harness.repo.adoptedReleases, isEmpty);
  });

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

  test('a generator failure finalizes the attempt and reports the code', () async {
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
  });

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

  test('a media edition does not satisfy watch without a video material', () async {
    // The edition carries a media rendition, but the material is audio-only:
    // watch stays unsatisfied and production is attempted (and fails here on
    // the generator level is not reached — the projection gates it).
    harness.repo.editions = [_mediaEdition];

    final outcome = await harness.request(MaterialCapability.watch);

    // No satisfying adopted edition and no derivable watch projection.
    expect(outcome, isA<CapabilityUnavailable>());
    expect(harness.gen.startCount, 0);
  });

  test('an empty-plan completion fails the run', () async {
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
    expect(outcome, isA<CapabilityFailed>());
    expect(harness.repo.finalizedFailures, ['generator_plan_was_empty']);
  });

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
}

final class _Harness {
  final repo = _FakeCapabilityRepository();
  final gen = _FakeGenService();
  late final MaterialCapabilityCoordinator coordinator =
      MaterialCapabilityCoordinator(
        repository: repo,
        generator: gen,
        targetLanguage: () => 'en',
      );

  Future<CapabilityOutcome> request(
    MaterialCapability capability, {
    String? localPackagePath,
  }) => coordinator.requestCapability(
    _mediaOnlyMaterial,
    capability,
    localPackagePath: localPackagePath,
  );

  CapabilityRunView? get runView =>
      coordinator.runViewFor('material-1', MaterialCapability.read);
}

final class _FakeGenService implements ListenGenProcessService {
  _FakeGenService();

  _FakeGenRun? lastRun;
  int startCount = 0;

  @override
  bool get isConfigured => true;

  @override
  ContentGeneratorState get state => ContentGeneratorState.ready;

  @override
  Future<ListenGenProcessRun> start(
    CapabilityGenerationRequest request,
  ) async {
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
    GenMachineEvent(sequence: _sequence++, kind: GenEventKind.running, stage: stage),
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

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '', code: '$error');

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
  Future<AdoptedComposition> readAdoptedComposition(
    String materialId,
  ) async => throw StateError('unexpected readAdoptedComposition');

  @override
  Future<List<int>> readCompositionResourcePayload(
    String materialId,
    String resourceId,
  ) async => throw StateError('unexpected readCompositionResourcePayload');

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
  releaseId: 'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  title: 'Lesson',
  targetLanguage: 'en',
  supportLanguages: [],
  installedAtMs: 1,
  adoptedAtMs: adopted ? 2 : null,
  adopted: adopted,
  resources: const [
    LearningEditionResource(
      resourceId: 'sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
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
  releaseId: 'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  title: 'Lesson',
  targetLanguage: 'en',
  supportLanguages: [],
  installedAtMs: 1,
  adoptedAtMs: 2,
  adopted: true,
  resources: [
    LearningEditionResource(
      resourceId: 'sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
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
  releaseId: 'sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
  title: 'Lesson',
  targetLanguage: 'en',
  supportLanguages: [],
  installedAtMs: 1,
  adoptedAtMs: 2,
  adopted: true,
  resources: [],
  renditions: [
    LearningEditionRendition(
      renditionId: 'sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
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

Future<void> _settle() => Future<void>.delayed(Duration.zero);
