import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/reading_controller.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/reading.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/widgets/panels/reading_view.dart';
import 'package:llplayer_next/widgets/panels/reading_word_inspector.dart';

Cue _cue(int index, String text, {required int startMs, required int endMs}) {
  final words = text
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final tokens = <SubtitleToken>[];
  for (final word in words) {
    if (tokens.isNotEmpty) {
      tokens.add(
        SubtitleToken(
          index: tokens.length,
          kind: 'whitespace',
          text: ' ',
          normalized: null,
        ),
      );
    }
    tokens.add(
      SubtitleToken(
        index: tokens.length,
        kind: 'word',
        text: word,
        normalized: word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), ''),
      ),
    );
  }
  return Cue(
    id: 'cue-$index',
    index: index,
    start: Duration(milliseconds: startMs),
    end: Duration(milliseconds: endMs),
    text: text,
    tokens: tokens,
  );
}

SubtitleTrack _track(List<Cue> cues, {String id = 'track-1'}) =>
    SubtitleTrack(id: id, cues: cues, mediaId: 'media-1');

void main() {
  group('ReadingController', () {
    test('open derives paragraphs and projects translations', () {
      final controller = ReadingController();
      controller.open(
        _track([
          _cue(0, 'First paragraph here.', startMs: 0, endMs: 2000),
          _cue(1, 'Second paragraph text.', startMs: 5000, endMs: 7000),
        ]),
        secondaryTrack: _track([
          _cue(10, '第一段翻译', startMs: 100, endMs: 1900),
          _cue(11, '第二段翻译', startMs: 5100, endMs: 6900),
        ], id: 'track-2'),
      );
      expect(controller.state.open, isTrue);
      expect(controller.state.paragraphs, hasLength(2));
      expect(controller.state.translationByAnchor['cue-0'], '第一段翻译');
      expect(controller.state.translationByAnchor['cue-1'], '第二段翻译');
    });

    test('resume anchor survives only when it still exists', () {
      final controller = ReadingController();
      final track = _track([
        _cue(0, 'One sentence.', startMs: 0, endMs: 1000),
        _cue(1, 'Two sentence.', startMs: 3000, endMs: 4000),
      ]);
      controller.open(track, resumeAnchorCueId: 'cue-1');
      expect(controller.state.anchorCueId, 'cue-1');
      expect(controller.state.anchorParagraphIndex, 1);
      controller.open(track, resumeAnchorCueId: 'cue-missing');
      expect(controller.state.anchorCueId, isNull);
    });

    test('markPosition and close', () {
      final controller = ReadingController();
      controller.open(
        _track([_cue(0, 'Hello there.', startMs: 0, endMs: 1000)]),
      );
      controller.markPosition('cue-0');
      expect(controller.state.anchorCueId, 'cue-0');
      controller.close();
      expect(controller.state.open, isFalse);
    });

    test('translation preference survives a channel round trip', () {
      final controller = ReadingController();
      final track = _track([_cue(0, 'Hello there.', startMs: 0, endMs: 1000)]);
      controller.open(track);
      controller.setTranslationVisible(true);
      controller.close();
      controller.open(track);
      expect(controller.state.translationVisible, isTrue);
    });
  });

  group('composeParagraphCue', () {
    test('re-indexes tokens and maps origins back to real cues', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, 'Hello brave', startMs: 0, endMs: 1000),
        _cue(1, 'new world.', startMs: 1000, endMs: 2000),
      ]);
      final composite = composeParagraphCue(paragraphs.single);
      expect(composite.cue.id, 'cue-0');
      final wordTokens = composite.cue.tokens
          .where((token) => token.kind == 'word')
          .toList();
      expect(wordTokens.map((token) => token.text), [
        'Hello',
        'brave',
        'new',
        'world.',
      ]);
      // Indexes are contiguous over the synthetic token list.
      for (var i = 0; i < composite.cue.tokens.length; i++) {
        expect(composite.cue.tokens[i].index, i);
      }
      final worldToken = wordTokens.last;
      final origin = composite.tokenOrigins[worldToken.index];
      expect(origin, isNotNull);
      expect(origin!.$1.id, 'cue-1');
      expect(origin.$2.text, 'world.');
    });
  });

  group('ReadingView', () {
    Widget host(
      ReadingController controller, {
      Future<void> Function(SubtitleToken, Cue)? onWord,
      Future<void> Function(ReadingSentence)? onPlaySentence,
      VoidCallback? onClose,
    }) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ReadingView(
          controller: controller,
          wordEntries: const {},
          capabilityProfiles: const {},
          showStyles: false,
          onWord: onWord ?? (_, _) async {},
          onPlaySentence: onPlaySentence ?? (_) async {},
          onPlayParagraph: (_) async {},
          onClose: onClose ?? () {},
        ),
      ),
    );

    testWidgets('renders paragraphs and separator markers', (tester) async {
      final controller = ReadingController();
      controller.open(
        _track([
          _cue(0, '(upbeat music)', startMs: 0, endMs: 1000),
          _cue(1, 'Welcome to the show.', startMs: 1000, endMs: 2000),
        ]),
      );
      await tester.pumpWidget(host(controller));
      expect(find.text('(upbeat music)'), findsOneWidget);
      expect(find.textContaining('Welcome'), findsWidgets);
    });

    testWidgets('word tap maps back to the original cue', (tester) async {
      final controller = ReadingController();
      controller.open(
        _track([
          _cue(0, 'Hello brave', startMs: 0, endMs: 1000),
          _cue(1, 'new world.', startMs: 1000, endMs: 2000),
        ]),
      );
      SubtitleToken? tappedToken;
      Cue? tappedCue;
      await tester.pumpWidget(
        host(
          controller,
          onWord: (token, cue) async {
            tappedToken = token;
            tappedCue = cue;
          },
        ),
      );
      await tester.tap(find.text('brave'));
      expect(tappedToken?.text, 'brave');
      expect(tappedCue?.id, 'cue-0');
      await tester.tap(find.text('world.'));
      expect(tappedToken?.text, 'world.');
      expect(tappedCue?.id, 'cue-1');
    });

    testWidgets(
      'tapping a paragraph anchors it and reveals the inline toolbar',
      (tester) async {
        final controller = ReadingController();
        controller.open(
          _track([
            _cue(0, 'First paragraph text.', startMs: 0, endMs: 1000),
            _cue(1, 'Second paragraph text.', startMs: 4000, endMs: 5000),
          ]),
        );
        ReadingSentence? played;
        await tester.pumpWidget(
          host(
            controller,
            onPlaySentence: (sentence) async {
              played = sentence;
            },
          ),
        );
        expect(find.text('Play paragraph'), findsNothing);
        // Tap paragraph whitespace (top-left corner), not a word's InkWell —
        // word taps intentionally win over paragraph selection.
        await tester.tapAt(
          tester.getTopLeft(
                find.byKey(const ValueKey('reading-paragraph-cue-1')),
              ) +
              const Offset(4, 4),
        );
        await tester.pump();
        expect(controller.state.anchorCueId, 'cue-1');
        expect(find.text('Play paragraph'), findsOneWidget);
        final sentenceAction = find.byKey(
          const ValueKey('reading-sentence-cue-1-0'),
        );
        expect(sentenceAction, findsOneWidget);
        await tester.tap(sentenceAction);
        expect(played?.cues.first.id, 'cue-1');
      },
    );

    testWidgets('translation toggle shows and hides translations', (
      tester,
    ) async {
      final controller = ReadingController();
      controller.open(
        _track([_cue(0, 'Hello world.', startMs: 0, endMs: 2000)]),
        secondaryTrack: _track([
          _cue(10, '你好世界', startMs: 100, endMs: 1900),
        ], id: 'track-2'),
      );
      await tester.pumpWidget(host(controller));
      expect(find.text('你好世界'), findsNothing);
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pump();
      expect(find.text('你好世界'), findsOneWidget);
    });

    testWidgets('vocabulary overview and channel lenses stay separated', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ReadingController();
      controller.open(
        _track([_cue(0, 'Hello world.', startMs: 0, endMs: 2000)]),
      );
      await tester.pumpWidget(host(controller));

      await tester.tap(
        find.byKey(const ValueKey('reading-vocabulary-overview')),
      );
      await tester.pump();
      expect(find.text('unique words'), findsOneWidget);
      expect(find.text('reading marks'), findsOneWidget);
      expect(find.text('listening estimates'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reading-lens-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading marks').last);
      await tester.pumpAndSettle();
      expect(find.text('Reading marks'), findsOneWidget);
      expect(find.text('Listening estimates'), findsNothing);
    });

    testWidgets('close button invokes onClose', (tester) async {
      final controller = ReadingController();
      controller.open(
        _track([_cue(0, 'Hello world.', startMs: 0, endMs: 1000)]),
      );
      var closed = false;
      await tester.pumpWidget(host(controller, onClose: () => closed = true));
      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    });
  });

  group('Reading word inspector', () {
    testWidgets('opens beside the reader and can be dismissed', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final learning = LearningController();
      learning.setSelectedToken(
        const SubtitleToken(
          index: 0,
          kind: 'word',
          text: 'schools',
          normalized: 'school',
        ),
      );
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReadingContextLayout(
              inspectorOpen: true,
              reader: const ColoredBox(
                key: ValueKey('reader-content'),
                color: Colors.white,
              ),
              inspector: ReadingWordInspector(
                learningController: learning,
                onClose: () => closed = true,
                onStatus: (_) {},
                onSave: (_, _) async {},
                onSource: (_) {},
                onHeard: () {},
                onNotHeard: () {},
                onCapabilityOverride: (_, _) async {},
                onReadingMark: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('reader-content')), findsOneWidget);
      expect(find.text('schools'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reading-word-inspector-rail')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('reading-word-inspector-close')),
      );
      expect(closed, isTrue);
    });
  });
}
