import 'package:llplayer_next/services/content_generator_setup.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/content_package_journey_view_model.dart';
import 'package:llplayer_next/data/repositories/content_package_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/content_package.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/screens/content_package_journey_screen.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';

void main() {
  testWidgets(
    'receipt requires separate subtitle and word activation actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var subtitleSelections = 0;
      final activated = <String>[];
      final viewModel = ContentPackageJourneyViewModel(
        _WidgetRepository(),
        (_) async => subtitleSelections++,
        (id) async => activated.add(id),
        mediaId: 'media-1',
        mediaPath: '/tmp/media.wav',
        mediaTitle: 'Lesson',
        mediaKind: 'audio',
        durationMs: 2200,
      );
      addTearDown(viewModel.dispose);
      await viewModel.chooseAndImportPackage();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          home: ContentPackageJourneyScreen(viewModel: viewModel),
        ),
      );

      expect(find.text('Unsigned local'), findsOneWidget);
      expect(find.text('Publisher unknown'), findsOneWidget);
      expect(find.text('machine_checked · listen-gen/0.1.0'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('select-imported-subtitle')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-imported-subtitle')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('activate-word-timeline-word-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activate-word-timeline-word-1')));
      await tester.pump();

      expect(subtitleSelections, 1);
      expect(activated, ['word-1']);
      expect(find.text('Subtitle selected'), findsOneWidget);
      expect(find.text('Activated'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an active run can be cancelled before its first event', (
    tester,
  ) async {
    final run = _PendingRun();
    final viewModel = ContentPackageJourneyViewModel(
      _GeneratingRepository(run),
      (_) async {},
      (_) async {},
      mediaId: 'media-1',
      mediaPath: '/tmp/media.wav',
      mediaTitle: 'Lesson',
      mediaKind: 'audio',
      durationMs: 2200,
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: ContentPackageJourneyScreen(viewModel: viewModel),
      ),
    );

    await tester.tap(find.byKey(const Key('generate-content-package')));
    await tester.pump();

    expect(viewModel.state.phase, ContentPackageJourneyPhase.preparing);
    expect(find.byKey(const Key('cancel-content-package')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-content-package')));
    await tester.pumpAndSettle();

    expect(run.cancelled, isTrue);
    expect(viewModel.state.phase, ContentPackageJourneyPhase.cancelled);
  });
}

class _GeneratingRepository implements ContentPackageRepository {
  const _GeneratingRepository(this.run);

  final ListenGenProcessRun run;

  @override
  bool get coreAvailable => true;
  @override
  bool get generatorConfigured => true;
  @override
  ContentGeneratorState get generatorState => generatorConfigured
      ? ContentGeneratorState.ready
      : ContentGeneratorState.generatorMissing;
  @override
  ApiFailure failureDetail(Object error) => error is ListenGenProcessFailure
      ? ApiFailure(raw: '', code: error.code)
      : const ApiFailure(raw: '');
  @override
  Future<String?> pickPackage() async => null;
  @override
  Future<ContentPackageImportReceipt> importPackage({
    required String mediaId,
    required String packagePath,
  }) => throw UnimplementedError();
  @override
  Future<ListenGenProcessRun> startGeneration(
    ContentPackageGenerationRequest request,
  ) async => run;
}

class _PendingRun implements ListenGenProcessRun {
  final _events = StreamController<ListenGenMachineEvent>();
  final _package = Completer<String>();
  bool cancelled = false;

  @override
  Stream<ListenGenMachineEvent> get events => _events.stream;
  @override
  Future<String> get packagePath => _package.future;
  @override
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    _package.completeError(const ListenGenProcessFailure('cancelled'));
  }

  @override
  Future<void> cleanUp() => _events.close();
}

class _WidgetRepository implements ContentPackageRepository {
  @override
  bool get coreAvailable => true;
  @override
  bool get generatorConfigured => false;
  @override
  ContentGeneratorState get generatorState => generatorConfigured
      ? ContentGeneratorState.ready
      : ContentGeneratorState.generatorMissing;
  @override
  ApiFailure failureDetail(Object error) => const ApiFailure(raw: '');
  @override
  Future<String?> pickPackage() async => '/tmp/lesson.listenpkg';
  @override
  Future<ContentPackageImportReceipt> importPackage({
    required String mediaId,
    required String packagePath,
  }) async => ContentPackageImportReceipt(
    manifestSha256:
        'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    track: const SubtitleTrack(id: 'track-1', cues: []),
    resources: [
      ContentPackageResourceDisposition(
        resourceId: 'sha256:subtitle',
        kind: 'subtitle_text_track',
        outcome: 'consumed',
        localIds: const ['track-1'],
      ),
      ContentPackageResourceDisposition(
        resourceId: 'sha256:word',
        kind: 'word_timeline',
        outcome: 'consumed',
        localIds: const ['word-1'],
      ),
    ],
  );
  @override
  Future<ListenGenProcessRun> startGeneration(
    ContentPackageGenerationRequest request,
  ) => throw UnimplementedError();
}
