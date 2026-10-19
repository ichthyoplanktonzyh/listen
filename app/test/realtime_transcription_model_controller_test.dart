import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_transcription_model_controller.dart';
import 'package:llplayer_next/data/repositories/transcription_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/runtime_resources.dart';

void main() {
  test(
    'preserves a compatible installed model for normalized English tags',
    () async {
      final repository = _Repository([
        model('english', englishOnly: true),
        model('multilingual'),
      ]);
      final controller = RealtimeTranscriptionModelController(repository);
      addTearDown(controller.dispose);

      final outcome = await controller.selectForLanguage('en-US');

      expect(outcome, isA<RealtimeTranscriptionModelSelected>());
      expect(
        (outcome as RealtimeTranscriptionModelSelected).modelId,
        'english',
      );
      expect(repository.installCalls, 0);
    },
  );

  test(
    'offers multilingual base for language tags without an installed match',
    () async {
      final repository = _Repository([
        model(
          'whisper.cpp:base.en@main',
          englishOnly: true,
          state: 'downloadable',
        ),
        model(
          'whisper.cpp:small@main',
          state: 'downloadable',
          sizeBytes: 487601967,
        ),
        model(
          RealtimeTranscriptionModelController.preferredMultilingualModelId,
          displayName: 'base',
          state: 'downloadable',
        ),
      ]);
      final controller = RealtimeTranscriptionModelController(repository);
      addTearDown(controller.dispose);

      final outcome = await controller.selectForLanguage('zh-CN');

      expect(outcome, isA<RealtimeTranscriptionModelNeedsDownload>());
      expect(
        (outcome as RealtimeTranscriptionModelNeedsDownload).model.id,
        RealtimeTranscriptionModelController.preferredMultilingualModelId,
      );
      expect(repository.installCalls, 0);
    },
  );

  test('installing catalog entry still waits for explicit consent', () async {
    late _Repository repository;
    repository = _Repository(
      [
        model(
          RealtimeTranscriptionModelController.preferredMultilingualModelId,
          displayName: 'base',
          state: 'installing',
        ),
      ],
      onInstall: (_) async {
        repository.catalog = [
          model(
            RealtimeTranscriptionModelController.preferredMultilingualModelId,
            displayName: 'base',
          ),
        ];
      },
    );
    final controller = RealtimeTranscriptionModelController(
      repository,
      pollInterval: Duration.zero,
      maxPollAttempts: 2,
    );
    addTearDown(controller.dispose);

    final outcome = await controller.selectForLanguage('zh');
    expect(outcome, isA<RealtimeTranscriptionModelNeedsDownload>());
    expect(
      controller.installState.status,
      RealtimeTranscriptionModelInstallStatus.awaitingConsent,
    );
    expect(repository.installCalls, 0);

    repository.catalog = [
      model(
        RealtimeTranscriptionModelController.preferredMultilingualModelId,
        displayName: 'base',
        state: 'downloadable',
      ),
    ];
    expect(repository.installCalls, 0);
    expect(
      await controller.installOfferedModel(),
      isA<RealtimeTranscriptionModelSelected>(),
    );
    expect(repository.installCalls, 1);
  });

  test(
    'automatic and non-English tags never select English-only models',
    () async {
      for (final language in ['auto', 'zh', 'ja-JP']) {
        final controller = RealtimeTranscriptionModelController(
          _Repository([model('english', englishOnly: true)]),
        );
        addTearDown(controller.dispose);

        expect(
          await controller.selectForLanguage(language),
          isA<RealtimeTranscriptionModelUnavailable>(),
        );
      }
    },
  );

  test('reports unavailable catalogs and typed repository failures', () async {
    final unavailable = RealtimeTranscriptionModelController(
      _Repository([model('other', state: 'unavailable')]),
    );
    final failed = RealtimeTranscriptionModelController(
      _Repository(const [], modelsError: StateError('offline')),
    );
    addTearDown(unavailable.dispose);
    addTearDown(failed.dispose);

    expect(
      await unavailable.selectForLanguage('en'),
      isA<RealtimeTranscriptionModelUnavailable>(),
    );
    final outcome = await failed.selectForLanguage('en');
    expect(outcome, isA<RealtimeTranscriptionModelFailure>());
    expect(
      (outcome as RealtimeTranscriptionModelFailure).failure,
      isA<ApiFailure>(),
    );
    expect(outcome.failure.raw, contains('offline'));
  });

  test(
    'does not request install when a compatible model is already installed',
    () async {
      final repository = _Repository([model('installed')]);
      final controller = RealtimeTranscriptionModelController(repository);

      expect(
        await controller.selectForLanguage('zh-Hant'),
        isA<RealtimeTranscriptionModelSelected>(),
      );
      controller.dispose();

      expect(repository.installCalls, 0);
      expect(repository.cancelCalls, 0);
    },
  );

  test(
    'returns selection only after Core reports the model installed',
    () async {
      final installed = Completer<List<TranscriptionModelView>>();
      final waitingForFinalPoll = Completer<void>();
      late _Repository repository;
      repository = _Repository(
        [
          model(
            RealtimeTranscriptionModelController.preferredMultilingualModelId,
            displayName: 'base',
            state: 'downloadable',
          ),
        ],
        onModels: (call) {
          if (call <= 2) return repository.catalog;
          if (call == 3) {
            return [
              model(
                RealtimeTranscriptionModelController
                    .preferredMultilingualModelId,
                displayName: 'base',
                state: 'installing',
                installedBytes: 48 * 1000 * 1000,
              ),
            ];
          }
          waitingForFinalPoll.complete();
          return installed.future;
        },
        onInstall: (_) async {
          repository.catalog = [
            model(
              RealtimeTranscriptionModelController.preferredMultilingualModelId,
              displayName: 'base',
              state: 'installing',
            ),
          ];
        },
      );
      final controller = RealtimeTranscriptionModelController(
        repository,
        pollInterval: Duration.zero,
        maxPollAttempts: 4,
      );

      expect(
        await controller.selectForLanguage('zh-CN'),
        isA<RealtimeTranscriptionModelNeedsDownload>(),
      );
      var completed = false;
      final installing = controller.installOfferedModel()
        ..then((_) => completed = true);
      await waitingForFinalPoll.future;
      expect(completed, isFalse);
      expect(controller.installState.progress, closeTo(48 / 147.951465, 0.001));

      installed.complete([
        model(
          RealtimeTranscriptionModelController.preferredMultilingualModelId,
          displayName: 'base',
        ),
      ]);
      final outcome = await installing;

      expect(outcome, isA<RealtimeTranscriptionModelSelected>());
      expect(repository.installCalls, 1);
      controller.dispose();
      expect(repository.cancelCalls, 0);
    },
  );

  test('failed install can be retried and then selected', () async {
    late _Repository repository;
    repository = _Repository(
      [
        model(
          RealtimeTranscriptionModelController.preferredMultilingualModelId,
          displayName: 'base',
          state: 'downloadable',
        ),
      ],
      onInstall: (_) async {
        repository.catalog = [
          model(
            RealtimeTranscriptionModelController.preferredMultilingualModelId,
            displayName: 'base',
            state: repository.installCalls == 1 ? 'failed' : 'installed',
            error: repository.installCalls == 1 ? 'network' : null,
          ),
        ];
      },
    );
    final controller = RealtimeTranscriptionModelController(
      repository,
      pollInterval: Duration.zero,
      maxPollAttempts: 3,
    );
    addTearDown(controller.dispose);

    await controller.selectForLanguage('zh');
    final failed = await controller.installOfferedModel();
    expect(failed, isA<RealtimeTranscriptionModelFailure>());
    expect(
      controller.installState.status,
      RealtimeTranscriptionModelInstallStatus.failed,
    );

    final retried = await controller.installOfferedModel();
    expect(retried, isA<RealtimeTranscriptionModelSelected>());
    expect(repository.installCalls, 2);
  });

  test(
    'cancel waits for the install request then cancels without selecting',
    () async {
      final installStarted = Completer<void>();
      final releaseInstallRequest = Completer<void>();
      late _Repository repository;
      repository = _Repository(
        [
          model(
            RealtimeTranscriptionModelController.preferredMultilingualModelId,
            displayName: 'base',
            state: 'downloadable',
          ),
        ],
        onInstall: (_) async {
          repository.catalog = [
            model(
              RealtimeTranscriptionModelController.preferredMultilingualModelId,
              displayName: 'base',
              state: 'installing',
            ),
          ];
          installStarted.complete();
          await releaseInstallRequest.future;
        },
        onCancel: (_) async {
          repository.catalog = [
            model(
              RealtimeTranscriptionModelController.preferredMultilingualModelId,
              displayName: 'base',
              state: 'downloadable',
            ),
          ];
        },
      );
      final controller = RealtimeTranscriptionModelController(
        repository,
        pollInterval: Duration.zero,
        maxPollAttempts: 3,
      );
      addTearDown(controller.dispose);

      await controller.selectForLanguage('zh');
      final installing = controller.installOfferedModel();
      await installStarted.future;
      final cancelling = controller.cancelInstall();
      expect(repository.cancelCalls, 0);
      releaseInstallRequest.complete();

      await cancelling;
      expect(await installing, isA<RealtimeTranscriptionModelUnavailable>());
      expect(repository.cancelCalls, 1);
      expect(repository.installCalls, 1);
    },
  );

  test(
    'Core cancellation failure does not escape or select the model',
    () async {
      final installStarted = Completer<void>();
      final releaseInstallRequest = Completer<void>();
      final repository = _Repository(
        [
          model(
            RealtimeTranscriptionModelController.preferredMultilingualModelId,
            displayName: 'base',
            state: 'downloadable',
          ),
        ],
        onInstall: (_) async {
          installStarted.complete();
          await releaseInstallRequest.future;
        },
        onCancel: (_) async => throw StateError('core disconnected'),
      );
      final controller = RealtimeTranscriptionModelController(
        repository,
        pollInterval: Duration.zero,
        maxPollAttempts: 3,
      );
      addTearDown(controller.dispose);

      await controller.selectForLanguage('zh');
      final installing = controller.installOfferedModel();
      await installStarted.future;
      final cancelling = controller.cancelInstall();
      releaseInstallRequest.complete();

      await expectLater(cancelling, completes);
      expect(await installing, isA<RealtimeTranscriptionModelUnavailable>());
      expect(
        controller.installState.status,
        RealtimeTranscriptionModelInstallStatus.failed,
      );
      expect(repository.cancelCalls, 1);
    },
  );

  test('cancel before consent never calls install or cancel', () async {
    final repository = _Repository([
      model(
        RealtimeTranscriptionModelController.preferredMultilingualModelId,
        displayName: 'base',
        state: 'downloadable',
      ),
    ]);
    final controller = RealtimeTranscriptionModelController(repository);
    addTearDown(controller.dispose);

    await controller.selectForLanguage('zh');
    await controller.cancelInstall();

    expect(repository.installCalls, 0);
    expect(repository.cancelCalls, 0);
    expect(
      controller.installState.status,
      RealtimeTranscriptionModelInstallStatus.cancelled,
    );
  });

  test('disposing during an active install requests cancellation', () async {
    final installStarted = Completer<void>();
    final releaseInstallRequest = Completer<void>();
    final cancellationCompleted = Completer<void>();
    late _Repository repository;
    repository = _Repository(
      [
        model(
          RealtimeTranscriptionModelController.preferredMultilingualModelId,
          displayName: 'base',
          state: 'downloadable',
        ),
      ],
      onInstall: (_) async {
        installStarted.complete();
        await releaseInstallRequest.future;
      },
      onCancel: (_) async {
        repository.catalog = [
          model(
            RealtimeTranscriptionModelController.preferredMultilingualModelId,
            displayName: 'base',
            state: 'downloadable',
          ),
        ];
        cancellationCompleted.complete();
      },
    );
    final controller = RealtimeTranscriptionModelController(
      repository,
      pollInterval: Duration.zero,
      maxPollAttempts: 3,
    );

    await controller.selectForLanguage('zh');
    final installing = controller.installOfferedModel();
    await installStarted.future;
    controller.dispose();
    releaseInstallRequest.complete();

    expect(await installing, isA<RealtimeTranscriptionModelUnavailable>());
    await cancellationCompleted.future;
    expect(repository.cancelCalls, 1);
  });

  test(
    'disposing during consent recheck cannot start a delayed install',
    () async {
      final preflight = Completer<List<TranscriptionModelView>>();
      final preflightEntered = Completer<void>();
      late _Repository repository;
      repository = _Repository(
        [
          model(
            RealtimeTranscriptionModelController.preferredMultilingualModelId,
            displayName: 'base',
            state: 'downloadable',
          ),
        ],
        onModels: (call) {
          if (call == 1) return repository.catalog;
          preflightEntered.complete();
          return preflight.future;
        },
      );
      final controller = RealtimeTranscriptionModelController(repository);

      await controller.selectForLanguage('zh');
      final installing = controller.installOfferedModel();
      await preflightEntered.future;
      controller.dispose();
      preflight.complete(repository.catalog);

      expect(await installing, isA<RealtimeTranscriptionModelUnavailable>());
      expect(repository.installCalls, 0);
      expect(repository.cancelCalls, 0);
    },
  );
}

TranscriptionModelView model(
  String id, {
  String? displayName,
  bool englishOnly = false,
  String state = 'installed',
  int sizeBytes = 147951465,
  int? installedBytes,
  String? error,
}) => TranscriptionModelView(
  id: id,
  displayName: displayName ?? id,
  revision: 'main',
  sizeBytes: sizeBytes,
  quality: 'balanced',
  englishOnly: englishOnly,
  state: state,
  installedBytes: installedBytes ?? (state == 'installed' ? sizeBytes : 0),
  error: error,
  license: 'MIT',
);

final class _Repository implements TranscriptionRepository {
  _Repository(
    this.catalog, {
    this.modelsError,
    this.onModels,
    this.onInstall,
    this.onCancel,
  });

  List<TranscriptionModelView> catalog;
  final Object? modelsError;
  final FutureOr<List<TranscriptionModelView>> Function(int call)? onModels;
  final Future<void> Function(String id)? onInstall;
  final Future<void> Function(String id)? onCancel;
  int modelsCalls = 0;
  int installCalls = 0;
  int cancelCalls = 0;

  @override
  Future<List<TranscriptionModelView>> models() async {
    modelsCalls++;
    if (modelsError case final error?) throw error;
    return await onModels?.call(modelsCalls) ?? catalog;
  }

  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '$error');
  @override
  Future<List<TranscriptionProviderView>> providers() async => const [];
  @override
  Future<void> registerCustomModel(String path) async {}
  @override
  Future<void> installModel(String id) async {
    installCalls++;
    await onInstall?.call(id);
  }

  @override
  Future<void> cancelModelInstall(String id) async {
    cancelCalls++;
    await onCancel?.call(id);
  }

  @override
  Future<void> deleteModel(String id) async {}
}
