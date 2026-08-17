import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/transcript_readiness_view_model.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/panels/transcript_panel.dart';

void main() {
  group('missing transcript surface', () {
    testWidgets('zh copy offers prepare and manual import', (tester) async {
      var prepared = 0;
      var imported = 0;
      await tester.pumpWidget(
        _harness(
          locale: 'zh',
          view: _view(
            phase: TranscriptReadinessPhase.missing,
            onPrepare: () async => prepared++,
            onImportSubtitle: () async => imported++,
          ),
        ),
      );

      expect(find.text('学习材料尚未准备'), findsOneWidget);
      expect(find.text('生成学习材料'), findsOneWidget);
      expect(find.text('导入字幕文件'), findsOneWidget);

      await tester.tap(find.byKey(const Key('prepare-learning-transcript')));
      await tester.tap(find.byKey(const Key('import-subtitle-file')));
      await tester.pump();
      expect(prepared, 1);
      expect(imported, 1);
    });

    testWidgets('en copy matches the zh surface', (tester) async {
      await tester.pumpWidget(
        _harness(
          locale: 'en',
          view: _view(phase: TranscriptReadinessPhase.missing),
        ),
      );

      expect(find.text('Learning materials are not ready'), findsOneWidget);
      expect(find.text('Generate learning materials'), findsOneWidget);
      expect(find.text('Import subtitle file'), findsOneWidget);
    });
  });

  group('chooser surface', () {
    testWidgets('lists usable tracks and selects the tapped one only', (
      tester,
    ) async {
      final selected = <String>[];
      var prepared = 0;
      await tester.pumpWidget(
        _harness(
          locale: 'zh',
          view: _view(
            phase: TranscriptReadinessPhase.choosing,
            usableTracks: const [_trackA, _trackB],
            onPrepare: () async => prepared++,
            onSelectTrack: (track) async => selected.add(track.id),
          ),
        ),
      );

      expect(find.text('选择学习文稿'), findsOneWidget);
      // Language names come from localization; raw ids never render.
      expect(find.text('English'), findsOneWidget);
      expect(find.text('简体中文'), findsOneWidget);
      expect(find.text('track-a'), findsNothing);
      expect(find.text('track-b'), findsNothing);

      await tester.tap(find.byKey(const Key('transcript-choice-track-b')));
      await tester.pump();

      expect(selected, ['track-b']);
      expect(prepared, 0);
    });

    testWidgets('en copy matches the chooser surface', (tester) async {
      await tester.pumpWidget(
        _harness(
          locale: 'en',
          view: _view(
            phase: TranscriptReadinessPhase.choosing,
            usableTracks: const [_trackA],
          ),
        ),
      );

      expect(find.text('Choose a learning transcript'), findsOneWidget);
      expect(find.text('Generated'), findsOneWidget);
    });
  });

  group('preparing surface', () {
    testWidgets('shows the user-facing stage and cancel', (tester) async {
      var cancelled = 0;
      await tester.pumpWidget(
        _harness(
          locale: 'zh',
          view: _view(
            phase: TranscriptReadinessPhase.preparing,
            preparationStage: TranscriptPreparationStage.transcribing,
            canCancel: true,
            onCancel: () => cancelled++,
          ),
        ),
      );

      expect(find.text('正在生成学习文稿…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel-transcript-preparation')));
      expect(cancelled, 1);
    });

    testWidgets('maps every preparation stage to localized copy', (
      tester,
    ) async {
      final stageLabels = {
        TranscriptPreparationStage.starting: 'Preparing learning transcript…',
        TranscriptPreparationStage.checkingMedia: 'Checking media…',
        TranscriptPreparationStage.readingMedia: 'Reading media info…',
        TranscriptPreparationStage.preparingAudio: 'Preparing audio…',
        TranscriptPreparationStage.transcribing:
            'Generating learning transcript…',
        TranscriptPreparationStage.organizing: 'Organizing learning resources…',
        TranscriptPreparationStage.importing: 'Importing learning transcript…',
      };
      for (final entry in stageLabels.entries) {
        await tester.pumpWidget(
          _harness(
            locale: 'en',
            view: _view(
              phase: TranscriptReadinessPhase.preparing,
              preparationStage: entry.key,
            ),
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
      }
    });
  });

  group('failed surface', () {
    testWidgets('retryable failure offers retry and manual import', (
      tester,
    ) async {
      var retried = 0;
      await tester.pumpWidget(
        _harness(
          locale: 'zh',
          view: _view(
            phase: TranscriptReadinessPhase.failed,
            canRetry: true,
            onRetry: () async => retried++,
          ),
        ),
      );

      expect(find.text('学习文稿准备失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('导入字幕文件'), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry-transcript-preparation')));
      expect(retried, 1);
    });

    testWidgets('fingerprint mismatch stays explicit without retry', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          locale: 'zh',
          view: _view(
            phase: TranscriptReadinessPhase.failed,
            fingerprintMismatch: true,
            canRetry: true,
          ),
        ),
      );

      expect(find.text('这份文稿对应的是不同的媒体文件'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(find.text('导入字幕文件'), findsOneWidget);
    });

    testWidgets('en copy matches the failed surface', (tester) async {
      await tester.pumpWidget(
        _harness(
          locale: 'en',
          view: _view(phase: TranscriptReadinessPhase.failed, canRetry: true),
        ),
      );

      expect(
        find.text('Could not prepare the learning transcript'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('unavailable surface', () {
    testWidgets('names an incompatible local Python runtime', (tester) async {
      await tester.pumpWidget(
        _harness(
          locale: 'zh',
          view: _view(
            phase: TranscriptReadinessPhase.unavailable,
            unavailableReason:
                TranscriptPreparationAvailability.pythonUnavailable,
          ),
        ),
      );

      expect(find.textContaining('Python 3.11'), findsOneWidget);
    });

    testWidgets('keeps generation primary and manual import secondary', (
      tester,
    ) async {
      var prepared = 0;
      await tester.pumpWidget(
        _harness(
          locale: 'zh',
          view: _view(
            phase: TranscriptReadinessPhase.unavailable,
            unavailableReason:
                TranscriptPreparationAvailability.generatorUnavailable,
            onPrepare: () async => prepared++,
          ),
        ),
      );

      expect(find.text('学习材料尚未准备'), findsOneWidget);
      expect(find.textContaining('锁定的本地 Gen 发布包尚未安装'), findsOneWidget);
      expect(find.textContaining('本地 Core 与 Gen'), findsNothing);
      expect(find.text('生成学习材料'), findsOneWidget);
      expect(find.text('导入字幕文件'), findsOneWidget);
      await tester.tap(find.byKey(const Key('prepare-learning-transcript')));
      await tester.pump();
      expect(prepared, 1);
    });

    testWidgets('en copy matches the unavailable surface', (tester) async {
      await tester.pumpWidget(
        _harness(
          locale: 'en',
          view: _view(
            phase: TranscriptReadinessPhase.unavailable,
            unavailableReason:
                TranscriptPreparationAvailability.coreUnavailable,
          ),
        ),
      );

      expect(find.text('Learning materials are not ready'), findsOneWidget);
      expect(
        find.textContaining('Local Core is not connected'),
        findsOneWidget,
      );
      expect(find.text('Generate learning materials'), findsOneWidget);
    });

    testWidgets(
      'opened media with failed Core registration is not called missing',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            locale: 'zh',
            view: _view(
              phase: TranscriptReadinessPhase.unavailable,
              unavailableReason: TranscriptPreparationAvailability
                  .mediaRegistrationUnavailable,
            ),
          ),
        );

        expect(find.textContaining('媒体文件已经在本机打开'), findsOneWidget);
        expect(find.textContaining('当前媒体文件在本机不可用'), findsNothing);
      },
    );
  });
}

TranscriptReadinessView _view({
  required TranscriptReadinessPhase phase,
  List<SubtitleTrack> usableTracks = const [],
  TranscriptPreparationStage? preparationStage,
  bool canCancel = false,
  bool canRetry = false,
  bool fingerprintMismatch = false,
  TranscriptPreparationAvailability? unavailableReason,
  Future<void> Function()? onPrepare,
  Future<void> Function(SubtitleTrack)? onSelectTrack,
  Future<void> Function()? onImportSubtitle,
  void Function()? onCancel,
  Future<void> Function()? onRetry,
}) => TranscriptReadinessView(
  phase: phase,
  usableTracks: usableTracks,
  preparationStage: preparationStage,
  canCancel: canCancel,
  canRetry: canRetry,
  fingerprintMismatch: fingerprintMismatch,
  unavailableReason: unavailableReason,
  onPrepare: onPrepare ?? () async {},
  onSelectTrack: onSelectTrack ?? (_) async {},
  onImportSubtitle: onImportSubtitle ?? () async {},
  onCancel: onCancel ?? () {},
  onRetry: onRetry ?? () async {},
);

Widget _harness({
  required String locale,
  required TranscriptReadinessView view,
}) => MaterialApp(
  theme: ListenTheme.light(),
  locale: Locale(locale),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: SizedBox(
      width: 520,
      height: 420,
      child: TranscriptPanel(
        track: null,
        scrollController: ScrollController(),
        currentCue: null,
        wordEntries: const <String, LexicalEntry>{},
        showStyles: true,
        baseColor: Colors.black,
        onWord: (_, _, _) async {},
        onSeekCue: (_) async {},
        readiness: view,
      ),
    ),
  ),
);

const _cue = Cue(
  id: 'cue-1',
  index: 0,
  start: Duration.zero,
  end: Duration(seconds: 1),
  text: 'Hello',
  tokens: [
    SubtitleToken(index: 0, kind: 'word', text: 'Hello', normalized: 'hello'),
  ],
);

const _trackA = SubtitleTrack(
  id: 'track-a',
  language: 'en',
  source: 'generated',
  cues: [_cue],
);

const _trackB = SubtitleTrack(
  id: 'track-b',
  language: 'zh',
  source: 'subtitle',
  cues: [_cue],
);
