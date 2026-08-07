import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/transcript_readiness_view_model.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/utils/transcript_translation.dart';
import 'package:llplayer_next/widgets/panels/transcript_panel.dart';
import 'package:llplayer_next/widgets/subtitle/token_line.dart';

/// The second subtitle track used to exist only as a video overlay, so the
/// transcript — where the reading happens — had no translation at all. These
/// pin how the two tracks are matched, and what the transcript says when the
/// match comes up empty.
void main() {
  group('translationForCue', () {
    test('matches on overlap in media time, not on index', () {
      // A translation track routinely merges two originals into one line, so
      // the two tracks do not line up index for index.
      final secondary = [_cue('s0', 0, 4, '前两句合成的一行'), _cue('s1', 4, 8, '第三句')];

      expect(
        translationForCue(
          cue: _cue('p0', 0, 2, 'One.'),
          secondaryCues: secondary,
        ),
        '前两句合成的一行',
      );
      expect(
        translationForCue(
          cue: _cue('p1', 2, 4, 'Two.'),
          secondaryCues: secondary,
        ),
        '前两句合成的一行',
      );
      expect(
        translationForCue(
          cue: _cue('p2', 4, 6, 'Three.'),
          secondaryCues: secondary,
        ),
        '第三句',
      );
    });

    test('a split translation contributes every overlapping line', () {
      final secondary = [_cue('s0', 0, 2, '前半'), _cue('s1', 2, 4, '后半')];

      expect(
        translationForCue(
          cue: _cue('p0', 0, 4, 'One long.'),
          secondaryCues: secondary,
        ),
        '前半 后半',
      );
    });

    test('touching at a boundary is not overlapping', () {
      final secondary = [_cue('s0', 0, 2, '上一句')];

      expect(
        translationForCue(
          cue: _cue('p1', 2, 4, 'Next.'),
          secondaryCues: secondary,
        ),
        isNull,
      );
    });

    test('offsets on either track are applied before matching', () {
      final secondary = [_cue('s0', 0, 2, '译文')];

      // The secondary track runs two seconds early; without its offset the
      // sentence at 2–4s would find nothing.
      expect(
        translationForCue(
          cue: _cue('p0', 2, 4, 'Text.'),
          secondaryCues: secondary,
          secondaryOffset: const Duration(seconds: 2),
        ),
        '译文',
      );
    });

    test('no overlap returns null rather than an empty string', () {
      expect(
        translationForCue(
          cue: _cue('p0', 0, 2, 'Text.'),
          secondaryCues: [_cue('s0', 20, 22, '别处')],
        ),
        isNull,
      );
    });
  });

  group('TranscriptTranslation', () {
    test('an unknown persisted value degrades to bilingual', () {
      expect(
        TranscriptTranslation.fromStorage('something-new'),
        TranscriptTranslation.bilingual,
      );
      expect(
        TranscriptTranslation.fromStorage(null),
        TranscriptTranslation.bilingual,
      );
      expect(
        TranscriptTranslation.fromStorage('source'),
        TranscriptTranslation.source,
      );
    });
  });

  group('transcript translation rows', () {
    testWidgets('bilingual shows the original with its translation under it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          mode: TranscriptTranslation.bilingual,
          hasTranslationTrack: true,
          translationFor: (cue) => cue.id == 'p0' ? '第一句的译文' : null,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TokenLine), findsWidgets);
      expect(find.text('第一句的译文'), findsOneWidget);
    });

    testWidgets('a sentence with no translation says so, rather than blank', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          mode: TranscriptTranslation.bilingual,
          hasTranslationTrack: true,
          translationFor: (_) => null,
        ),
      );
      await tester.pumpAndSettle();

      // A blank row under the original would read as a translation that exists
      // and is empty — a different, false claim.
      expect(find.text('这句没有对应的译文'), findsWidgets);
    });

    testWidgets('a missing track is said once, not under every sentence', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          mode: TranscriptTranslation.bilingual,
          translationFor: (_) => null,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('transcript-no-translation-track')),
        findsOneWidget,
      );
      // The per-sentence line belongs to sentences a loaded track failed to
      // cover; with no track at all it would be the same fact repeated.
      expect(find.text('这句没有对应的译文'), findsNothing);
    });

    testWidgets('source-only shows neither the rows nor the notice', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          mode: TranscriptTranslation.source,
          hasTranslationTrack: true,
          translationFor: (_) => '译文',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TokenLine), findsWidgets);
      expect(find.text('译文'), findsNothing);
      expect(
        find.byKey(const Key('transcript-no-translation-track')),
        findsNothing,
      );
    });

    testWidgets('translation-only drops the original', (tester) async {
      await tester.pumpWidget(
        _harness(
          mode: TranscriptTranslation.translation,
          hasTranslationTrack: true,
          translationFor: (_) => '译文',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('译文'), findsWidgets);
      // Translation-only means the original is gone, not merely dimmed.
      expect(find.byType(TokenLine), findsNothing);
    });
  });
}

Cue _cue(String id, int startSeconds, int endSeconds, String text) => Cue(
  id: id,
  index: 0,
  start: Duration(seconds: startSeconds),
  end: Duration(seconds: endSeconds),
  text: text,
  tokens: const [],
);

Widget _harness({
  required TranscriptTranslation mode,
  required String? Function(Cue) translationFor,
  bool hasTranslationTrack = false,
}) {
  final track = SubtitleTrack(
    id: 'track-1',
    source: 'fixture',
    cues: [
      _cue('p0', 0, 2, 'First sentence.'),
      _cue('p1', 2, 4, 'Second one.'),
    ],
  );
  return MaterialApp(
    theme: ListenTheme.light(),
    locale: const Locale('zh'),
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
        height: 400,
        child: TranscriptPanel(
          track: track,
          scrollController: ScrollController(),
          currentCue: track.cues.first,
          wordEntries: const <String, LexicalEntry>{},
          showStyles: false,
          baseColor: Colors.black,
          onWord: (_, _, _) async {},
          onSeekCue: (_) async {},
          translationMode: mode,
          translationFor: translationFor,
          hasTranslationTrack: hasTranslationTrack,
          readiness: TranscriptReadinessView(
            phase: TranscriptReadinessPhase.ready,
            onPrepare: () async {},
            onSelectTrack: (_) async {},
            onImportSubtitle: () async {},
            onCancel: () {},
            onRetry: () async {},
          ),
        ),
      ),
    ),
  );
}
