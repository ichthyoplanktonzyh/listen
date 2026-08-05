import 'package:llplayer_next/services/content_generator_setup.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/content_package_journey_view_model.dart';
import 'package:llplayer_next/data/repositories/content_package_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/content_package.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';

void main() {
  test(
    'import produces candidates without selecting or activating them',
    () async {
      final repository = _FakePackageRepository(receipt: _receipt());
      var selected = 0;
      var activated = 0;
      final viewModel = _viewModel(
        repository,
        select: (_) async => selected++,
        activate: (_) async => activated++,
      );
      addTearDown(viewModel.dispose);

      await viewModel.chooseAndImportPackage();

      expect(viewModel.state.phase, ContentPackageJourneyPhase.candidateReady);
      expect(selected, 0);
      expect(activated, 0);
      await viewModel.selectImportedSubtitle();
      await viewModel.activateImportedWordTimeline('word-1');
      expect(selected, 1);
      expect(activated, 1);
      expect(viewModel.state.selectedTrackId, 'track-1');
      expect(viewModel.state.activatedWordTimelineIds, {'word-1'});
    },
  );

  test('maps the frozen Core mismatch code to its own phase', () async {
    final repository = _FakePackageRepository(
      importFailure: const ApiFailure(
        raw: '',
        code: 'content_package_media_mismatch',
      ),
    );
    final viewModel = _viewModel(repository);
    addTearDown(viewModel.dispose);

    await viewModel.chooseAndImportPackage();

    expect(
      viewModel.state.phase,
      ContentPackageJourneyPhase.fingerprintMismatch,
    );
  });

  test('retry repeats the original package path and can recover', () async {
    final repository = _FakePackageRepository(
      receipt: _receipt(),
      failuresRemaining: 1,
    );
    final viewModel = _viewModel(repository);
    addTearDown(viewModel.dispose);

    await viewModel.chooseAndImportPackage();
    expect(viewModel.state.phase, ContentPackageJourneyPhase.failed);
    await viewModel.retry();

    expect(viewModel.state.phase, ContentPackageJourneyPhase.candidateReady);
    expect(repository.importedPaths, [
      '/tmp/lesson.listenpkg',
      '/tmp/lesson.listenpkg',
    ]);
    expect(viewModel.canRetry, isFalse);
  });

  test('picker cancellation has no retryable intent', () async {
    final repository = _FakePackageRepository(pickedPath: null);
    final viewModel = _viewModel(repository);
    addTearDown(viewModel.dispose);

    await viewModel.chooseAndImportPackage();

    expect(viewModel.state.phase, ContentPackageJourneyPhase.cancelled);
    expect(viewModel.canRetry, isFalse);
  });

  test('disconnected Core prevents generator startup', () async {
    final repository = _FakePackageRepository(coreIsAvailable: false);
    final viewModel = _viewModel(repository);
    addTearDown(viewModel.dispose);

    expect(viewModel.generatorConfigured, isFalse);
    await viewModel.generateAndImport();

    expect(repository.generationStarts, 0);
    expect(viewModel.state.phase, ContentPackageJourneyPhase.idle);
  });

  test(
    'cancel forwards to the active generator and publishes cancelled',
    () async {
      final run = _FakeRun();
      final repository = _FakePackageRepository(run: run);
      final viewModel = _viewModel(repository);
      addTearDown(viewModel.dispose);

      final future = viewModel.generateAndImport();
      await Future<void>.delayed(Duration.zero);
      run.eventsController.add(
        ListenGenMachineEvent(sequence: 0, kind: ListenGenEventKind.protocol),
      );
      run.eventsController.add(
        ListenGenMachineEvent(sequence: 1, kind: ListenGenEventKind.started),
      );
      await Future<void>.delayed(Duration.zero);
      viewModel.cancel();
      run.packageCompleter.completeError(
        const ListenGenProcessFailure('cancelled'),
      );
      await future;

      expect(run.cancelled, isTrue);
      expect(viewModel.state.phase, ContentPackageJourneyPhase.cancelled);
    },
  );

  test('successful generation preserves the verified archive digest', () async {
    final run = _FakeRun();
    final repository = _FakePackageRepository(run: run, receipt: _receipt());
    final viewModel = _viewModel(repository);
    addTearDown(viewModel.dispose);

    final future = viewModel.generateAndImport();
    await Future<void>.delayed(Duration.zero);
    run.eventsController.add(
      ListenGenMachineEvent(sequence: 0, kind: ListenGenEventKind.protocol),
    );
    run.eventsController.add(
      ListenGenMachineEvent(sequence: 1, kind: ListenGenEventKind.started),
    );
    run.eventsController.add(
      ListenGenMachineEvent(
        sequence: 2,
        kind: ListenGenEventKind.completed,
        packageSha256:
            'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    run.packageCompleter.complete('/tmp/generated.listenpkg');
    await future;

    expect(viewModel.state.phase, ContentPackageJourneyPhase.candidateReady);
    expect(
      viewModel.state.archiveSha256,
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  });
}

ContentPackageJourneyViewModel _viewModel(
  ContentPackageRepository repository, {
  Future<void> Function(SubtitleTrack)? select,
  Future<void> Function(String)? activate,
}) => ContentPackageJourneyViewModel(
  repository,
  select ?? (_) async {},
  activate ?? (_) async {},
  mediaId: 'media-1',
  mediaPath: '/tmp/media.wav',
  mediaTitle: 'Lesson',
  mediaKind: 'audio',
  durationMs: 2200,
);

ContentPackageImportReceipt _receipt() => ContentPackageImportReceipt(
  manifestSha256:
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  track: const SubtitleTrack(id: 'track-1', cues: []),
  resources: [
    ContentPackageResourceDisposition(
      resourceId:
          'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      kind: 'subtitle_text_track',
      outcome: 'consumed',
      localIds: const ['track-1'],
    ),
    ContentPackageResourceDisposition(
      resourceId:
          'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      kind: 'word_timeline',
      outcome: 'consumed',
      localIds: const ['word-1'],
    ),
  ],
);

class _FakePackageRepository implements ContentPackageRepository {
  _FakePackageRepository({
    this.receipt,
    this.importFailure,
    this.failuresRemaining = 0,
    this.run,
    this.pickedPath = '/tmp/lesson.listenpkg',
    this.coreIsAvailable = true,
  });

  final ContentPackageImportReceipt? receipt;
  final ApiFailure? importFailure;
  int failuresRemaining;
  final ListenGenProcessRun? run;
  final String? pickedPath;
  final bool coreIsAvailable;
  int generationStarts = 0;
  final List<String> importedPaths = [];

  @override
  bool get coreAvailable => coreIsAvailable;
  @override
  bool get generatorConfigured => true;
  @override
  ContentGeneratorState get generatorState => generatorConfigured
      ? ContentGeneratorState.ready
      : ContentGeneratorState.generatorMissing;
  @override
  ApiFailure failureDetail(Object error) =>
      error is ApiFailure ? error : ApiFailure(raw: '', code: '$error');
  @override
  Future<String?> pickPackage() async => pickedPath;
  @override
  Future<ContentPackageImportReceipt> importPackage({
    required String mediaId,
    required String packagePath,
  }) async {
    importedPaths.add(packagePath);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const ApiFailure(raw: '', code: 'temporary', retryable: true);
    }
    if (importFailure != null) throw importFailure!;
    return receipt!;
  }

  @override
  Future<ListenGenProcessRun> startGeneration(
    ContentPackageGenerationRequest request,
  ) async {
    generationStarts++;
    return run!;
  }
}

class _FakeRun implements ListenGenProcessRun {
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
