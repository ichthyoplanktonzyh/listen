import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_transcription_model_controller.dart';
import 'package:llplayer_next/data/repositories/transcription_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/runtime_resources.dart';
import 'package:llplayer_next/widgets/flows/realtime_transcription_model_dialog.dart';

void main() {
  testWidgets('does not install until Download and Cancel dismisses prompt', (
    tester,
  ) async {
    final repository = _Repository();
    final controller = RealtimeTranscriptionModelController(repository);
    addTearDown(controller.dispose);
    final offered = await controller.selectForLanguage('zh-CN');
    final model = (offered as RealtimeTranscriptionModelNeedsDownload).model;
    RealtimeTranscriptionModelSelected? selected;

    await tester.pumpWidget(
      _App(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showRealtimeTranscriptionModelDialog(
                  context: context,
                  controller: controller,
                  model: model,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Whisper base · 148 MB'), findsOneWidget);
    expect(repository.installCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.installCalls, 0);
    expect(repository.cancelCalls, 0);
    expect(selected, isNull);
  });

  testWidgets('dialog resumes with selected model only after installed state', (
    tester,
  ) async {
    final finalPoll = Completer<List<TranscriptionModelView>>();
    final waitingForFinalPoll = Completer<void>();
    final repository = _Repository(
      onModels: (call, current) {
        if (call <= 2) return current;
        if (call == 3) {
          return [model(state: 'installing', installedBytes: 32 * 1000 * 1000)];
        }
        waitingForFinalPoll.complete();
        return finalPoll.future;
      },
      onInstall: (_) async => [model(state: 'installing')],
    );
    final controller = RealtimeTranscriptionModelController(
      repository,
      pollInterval: Duration.zero,
      maxPollAttempts: 5,
    );
    addTearDown(controller.dispose);
    final offered = await controller.selectForLanguage('zh-CN');
    final candidate =
        (offered as RealtimeTranscriptionModelNeedsDownload).model;
    RealtimeTranscriptionModelSelected? selected;

    await tester.pumpWidget(
      _App(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showRealtimeTranscriptionModelDialog(
                  context: context,
                  controller: controller,
                  model: candidate,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 5 && !waitingForFinalPoll.isCompleted;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await waitingForFinalPoll.future;

    expect(find.textContaining('Downloading Whisper base'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(selected, isNull);
    expect(repository.installCalls, 1);

    finalPoll.complete([model(state: 'installed')]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(selected?.modelId, _baseId);
    expect(repository.cancelCalls, 0);
  });

  testWidgets(
    'catalog Installing to Downloadable transition still requires consent',
    (tester) async {
      final repository = _Repository();
      repository.current = [model(state: 'installing')];
      final controller = RealtimeTranscriptionModelController(repository);
      addTearDown(controller.dispose);
      final offered = await controller.selectForLanguage('zh-CN');
      final candidate =
          (offered as RealtimeTranscriptionModelNeedsDownload).model;
      repository.current = [model(state: 'downloadable')];

      await tester.pumpWidget(
        _App(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showRealtimeTranscriptionModelDialog(
                  context: context,
                  controller: controller,
                  model: candidate,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Download'), findsOneWidget);
      expect(repository.installCalls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.installCalls, 0);
      expect(repository.cancelCalls, 0);
    },
  );

  testWidgets('cancelling an active download waits for Core cancellation', (
    tester,
  ) async {
    final installStarted = Completer<void>();
    final installPost = Completer<void>();
    final repository = _Repository(
      onInstall: (current) async {
        installStarted.complete();
        await installPost.future;
        return [model(state: 'installing')];
      },
      onCancel: (_) async => [model(state: 'downloadable')],
    );
    final controller = RealtimeTranscriptionModelController(
      repository,
      pollInterval: Duration.zero,
      maxPollAttempts: 5,
    );
    addTearDown(controller.dispose);
    final offered = await controller.selectForLanguage('zh-CN');
    final candidate =
        (offered as RealtimeTranscriptionModelNeedsDownload).model;
    RealtimeTranscriptionModelSelected? selected;

    await tester.pumpWidget(
      _App(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showRealtimeTranscriptionModelDialog(
                  context: context,
                  controller: controller,
                  model: candidate,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pump();
    await installStarted.future;
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(repository.cancelCalls, 0);
    expect(selected, isNull);
    expect(find.byType(RealtimeTranscriptionModelDialog), findsOneWidget);
    installPost.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(repository.cancelCalls, 1);
    expect(selected, isNull);
  });

  testWidgets('download prompt copy is localized in Chinese', (tester) async {
    final repository = _Repository();
    final controller = RealtimeTranscriptionModelController(repository);
    addTearDown(controller.dispose);
    final offered = await controller.selectForLanguage('zh-CN');
    final candidate =
        (offered as RealtimeTranscriptionModelNeedsDownload).model;

    await tester.pumpWidget(
      _App(
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showRealtimeTranscriptionModelDialog(
                context: context,
                controller: controller,
                model: candidate,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('下载 Whisper 语音转文字模型？'), findsOneWidget);
    expect(find.text('Whisper base · 148 MB'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
  });
}

const _baseId = 'whisper.cpp:base@main';

TranscriptionModelView model({
  String state = 'downloadable',
  int installedBytes = 0,
}) => TranscriptionModelView(
  id: _baseId,
  displayName: 'base',
  revision: 'main-80da2d8',
  sizeBytes: 147951465,
  quality: 'fast',
  englishOnly: false,
  state: state,
  installedBytes: installedBytes,
  error: null,
  license: 'MIT',
);

final class _Repository implements TranscriptionRepository {
  _Repository({this.onModels, this.onInstall, this.onCancel});

  FutureOr<List<TranscriptionModelView>> Function(
    int call,
    List<TranscriptionModelView> current,
  )?
  onModels;
  FutureOr<List<TranscriptionModelView>> Function(
    List<TranscriptionModelView> current,
  )?
  onInstall;
  FutureOr<List<TranscriptionModelView>> Function(
    List<TranscriptionModelView> current,
  )?
  onCancel;
  List<TranscriptionModelView> current = [model()];
  int modelsCalls = 0;
  int installCalls = 0;
  int cancelCalls = 0;

  @override
  Future<List<TranscriptionModelView>> models() async {
    modelsCalls++;
    return await onModels?.call(modelsCalls, current) ?? current;
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
    final next = await onInstall?.call(current);
    if (next != null) current = next;
  }

  @override
  Future<void> cancelModelInstall(String id) async {
    cancelCalls++;
    final next = await onCancel?.call(current);
    if (next != null) current = next;
  }

  @override
  Future<void> deleteModel(String id) async {}
}

class _App extends StatelessWidget {
  const _App({required this.home, this.locale = const Locale('en')});

  final Widget home;
  final Locale locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
