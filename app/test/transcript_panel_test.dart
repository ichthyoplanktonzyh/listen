import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/models/workbench_study_mode.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/panels/transcript_panel.dart';

void main() {
  _analysisGroup();
  _studyModeGroup();

  testWidgets('transcript keeps the current cue visible with variable rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final cues = List.generate(72, _cue);
    final track = SubtitleTrack(id: 'track-1', cues: cues, source: 'fixture');

    await tester.pumpWidget(
      _Harness(controller: controller, track: track, currentCue: cues[56]),
    );
    await tester.pumpAndSettle();

    _expectCueVisible(tester, 'cue-56');

    await tester.pumpWidget(
      _Harness(controller: controller, track: track, currentCue: cues[9]),
    );
    await tester.pumpAndSettle();

    _expectCueVisible(tester, 'cue-9');
  });

  testWidgets('manual scroll pauses following and back button resumes it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final cues = List.generate(72, _cue);
    final track = SubtitleTrack(id: 'track-1', cues: cues, source: 'fixture');

    await tester.pumpWidget(
      _Harness(controller: controller, track: track, currentCue: cues[4]),
    );
    await tester.pumpAndSettle();

    // No manual interaction yet: the back-to-current affordance stays hidden.
    expect(find.byKey(const Key('transcript-back-to-current')), findsNothing);

    // Drag the transcript away from the current cue.
    await tester.drag(
      find.byKey(const ValueKey('transcript-cue-cue-4')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    // Following is paused, so a new current cue must not scroll the list, and
    // the resume affordance appears.
    expect(find.byKey(const Key('transcript-back-to-current')), findsOneWidget);

    await tester.tap(find.byKey(const Key('transcript-back-to-current')));
    await tester.pumpAndSettle();

    // Resuming following scrolls the current cue back into view and hides the
    // affordance again.
    expect(find.byKey(const Key('transcript-back-to-current')), findsNothing);
    _expectCueVisible(tester, 'cue-4');
  });

  testWidgets('back-to-current floats over the list without shrinking it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final cues = List.generate(72, _cue);
    final track = SubtitleTrack(id: 'track-1', cues: cues, source: 'fixture');

    await tester.pumpWidget(
      _Harness(controller: controller, track: track, currentCue: cues[4]),
    );
    await tester.pumpAndSettle();

    final listBefore = tester.getRect(find.byType(ListView));

    await tester.drag(
      find.byKey(const ValueKey('transcript-cue-cue-4')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    final fab = tester.getRect(
      find.byKey(const Key('transcript-back-to-current')),
    );
    final listAfter = tester.getRect(find.byType(ListView));

    // The FAB is stacked over the list, not laid out beneath it: the list keeps
    // its full height instead of giving up a row's worth to the affordance.
    expect(listAfter.height, closeTo(listBefore.height, 0.5));

    // It floats inside the list's bounds, tucked into the bottom-right corner —
    // where it can only ever overlap a sentence the reader has scrolled past.
    expect(fab.bottom, lessThanOrEqualTo(listAfter.bottom + 0.5));
    expect(fab.right, lessThanOrEqualTo(listAfter.right + 0.5));
    expect(fab.top, greaterThan(listAfter.center.dy));
    expect(fab.left, greaterThan(listAfter.center.dx));
  });
}

/// The analysis used to be one of five side-panel tabs, so reaching it meant
/// the transcript — including the sentence being analysed — left the screen.
/// These pin the replacement: it is an expansion of one sentence, offered on
/// that sentence only, and it never displaces the text.
void _analysisGroup() {
  testWidgets('analysis is offered on the current sentence only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final cues = List.generate(8, _cue);
    final track = SubtitleTrack(id: 'track-1', cues: cues, source: 'fixture');

    await tester.pumpWidget(
      _Harness(
        controller: controller,
        track: track,
        currentCue: cues[2],
        onToggleAnalysis: () {},
      ),
    );
    await tester.pumpAndSettle();

    // Eight sentences are on screen; exactly one carries the control.
    expect(
      find.byKey(const Key('transcript-analyse-sentence')),
      findsOneWidget,
    );
    final control = tester.getRect(
      find.byKey(const Key('transcript-analyse-sentence')),
    );
    final currentCue = tester.getRect(
      find.byKey(const ValueKey('transcript-cue-cue-2')),
    );
    expect(control.top, greaterThanOrEqualTo(currentCue.bottom - 0.5));
  });

  testWidgets('expanding the analysis keeps every sentence on screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final cues = List.generate(8, _cue);
    final track = SubtitleTrack(id: 'track-1', cues: cues, source: 'fixture');

    var toggles = 0;
    await tester.pumpWidget(
      _Harness(
        controller: controller,
        track: track,
        currentCue: cues[2],
        onToggleAnalysis: () => toggles += 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transcript-analyse-sentence')));
    expect(toggles, 1);

    await tester.pumpWidget(
      _Harness(
        controller: controller,
        track: track,
        currentCue: cues[2],
        onToggleAnalysis: () {},
        analysisExpanded: true,
        analysis: const Text('analysis body', key: Key('analysis-body')),
      ),
    );
    await tester.pumpAndSettle();

    // The analysis renders inside the sentence it describes, and the transcript
    // is still a transcript — the list did not get replaced by it.
    expect(find.byKey(const Key('analysis-body')), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    final body = tester.getRect(find.byKey(const Key('analysis-body')));
    final currentCue = tester.getRect(
      find.byKey(const ValueKey('transcript-cue-cue-2')),
    );
    expect(body.top, greaterThanOrEqualTo(currentCue.bottom - 0.5));
  });

  testWidgets('a word tap reports where it landed, for the bubble anchor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final cues = List.generate(4, _cue);
    final track = SubtitleTrack(id: 'track-1', cues: cues, source: 'fixture');

    Offset? anchor;
    await tester.pumpWidget(
      _Harness(
        controller: controller,
        track: track,
        currentCue: cues[0],
        onWord: (_, _, position) async => anchor = position,
      ),
    );
    await tester.pumpAndSettle();

    // Tap a word in the first sentence. The panel records the press itself,
    // because `TokenLine` hands word taps over without a position. The
    // transcript is left-aligned, so aim just inside the row's leading edge —
    // where the opening word sits — rather than the row's geometric centre,
    // which now lands in the ragged-right whitespace past the text.
    final row = tester.getRect(
      find.byKey(const ValueKey('transcript-cue-cue-0')),
    );
    final target = Offset(row.left + 40, row.top + 22);
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(anchor, isNotNull);
    expect(anchor, target);
  });
}

/// The reading states are displays of this same pane, not separate windows.
/// Blind and word-select both replace the scrolling transcript with the current
/// sentence in focus — blanked — matching 每日英语听力's 盲听 / 选词.
void _studyModeGroup() {
  String plainOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).textSpan!.toPlainText();

  testWidgets(
    'blind mode focuses the current sentence, blanked, with a count',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(620, 420));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = ScrollController();
      addTearDown(controller.dispose);
      final cues = List.generate(8, _cue);
      final track = SubtitleTrack(id: 'track-1', cues: cues, source: 'fixture');

      await tester.pumpWidget(
        _Harness(
          controller: controller,
          track: track,
          currentCue: cues[2],
          studyMode: WorkbenchStudyMode.blindListening,
        ),
      );
      await tester.pumpAndSettle();

      // Only the current sentence is on screen — the list is gone — and it is
      // blanked (underscore runs) with some scaffolding words kept.
      expect(find.byType(ListView), findsNothing);
      expect(
        find.byKey(const Key('transcript-blind-sentence')),
        findsOneWidget,
      );
      final plain = plainOf(tester, const Key('transcript-blind-sentence'));
      expect(plain, contains('_'));
      expect(plain.replaceAll('_', '').trim(), isNotEmpty);
      // The count stands where in the piece the ear is: sentence 3 of 8.
      expect(find.text('3 / 8'), findsOneWidget);
      // Blind shows no candidate words — that is word-select's job.
      expect(find.byType(OutlinedButton), findsNothing);
    },
  );

  testWidgets('word select offers the removed words as chips and fills a blank', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final cues = List.generate(6, _cue);
    final track = SubtitleTrack(id: 'track-1', cues: cues, source: 'fixture');

    await tester.pumpWidget(
      _Harness(
        controller: controller,
        track: track,
        currentCue: cues[1],
        studyMode: WorkbenchStudyMode.wordSelection,
      ),
    );
    await tester.pumpAndSettle();

    // The current sentence, blanked, plus the prompt and a chip per blank.
    expect(find.byType(ListView), findsNothing);
    expect(find.text('请选择下列单词进行填空'), findsOneWidget);
    final before = plainOf(
      tester,
      const Key('transcript-word-select-sentence'),
    );
    final blanks = RegExp(r'_+').allMatches(before).length;
    final chips = find.byType(OutlinedButton);
    expect(tester.widgetList(chips), hasLength(blanks));
    expect(blanks, greaterThan(0));

    // Tapping a chip drops its word into the first empty blank and consumes it.
    final label =
        ((tester.widget<OutlinedButton>(chips.first)).child! as Text).data!;
    await tester.ensureVisible(chips.first);
    await tester.tap(chips.first);
    await tester.pumpAndSettle();

    final after = plainOf(tester, const Key('transcript-word-select-sentence'));
    expect(after, contains(label));
    expect(RegExp(r'_+').allMatches(after).length, blanks - 1);
    // The used chip stays visible but disabled, so the pool keeps its shape.
    expect(tester.widget<OutlinedButton>(chips.first).onPressed, isNull);
  });

  testWidgets('focus modes ask for a sentence when none is playing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final cues = List.generate(4, _cue);
    final track = SubtitleTrack(id: 'track-1', cues: cues, source: 'fixture');

    await tester.pumpWidget(
      _Harness(
        controller: controller,
        track: track,
        currentCue: null,
        studyMode: WorkbenchStudyMode.wordSelection,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transcript-focus-awaiting')), findsOneWidget);
  });
}

Cue _cue(int index) {
  final text = index.isEven
      ? 'Target sentence $index with a compact listening line.'
      : 'Target sentence $index with a much longer listening line that wraps '
            'across multiple visual rows so fixed item extent scrolling drifts.';
  return Cue(
    id: 'cue-$index',
    index: index,
    start: Duration(seconds: index * 2),
    end: Duration(seconds: index * 2 + 1),
    text: text,
    tokens: _tokens(text),
  );
}

List<SubtitleToken> _tokens(String text) {
  final parts = text.split(' ');
  final tokens = <SubtitleToken>[];
  for (var index = 0; index < parts.length; index += 1) {
    tokens.add(
      SubtitleToken(
        index: tokens.length,
        kind: 'word',
        text: parts[index],
        normalized: parts[index].toLowerCase().replaceAll('.', ''),
      ),
    );
    if (index != parts.length - 1) {
      tokens.add(
        SubtitleToken(
          index: tokens.length,
          kind: 'whitespace',
          text: ' ',
          normalized: null,
        ),
      );
    }
  }
  return tokens;
}

void _expectCueVisible(WidgetTester tester, String cueId) {
  final host = tester.getRect(find.byKey(const Key('transcript-host')));
  final cue = tester.getRect(find.byKey(ValueKey('transcript-cue-$cueId')));
  expect(cue.center.dy, inInclusiveRange(host.top, host.bottom));
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.controller,
    required this.track,
    required this.currentCue,
    this.onToggleAnalysis,
    this.analysisExpanded = false,
    this.analysis,
    this.onWord,
    this.studyMode = WorkbenchStudyMode.normal,
  });

  final ScrollController controller;
  final SubtitleTrack track;
  final Cue? currentCue;
  final VoidCallback? onToggleAnalysis;
  final bool analysisExpanded;
  final Widget? analysis;
  final Future<void> Function(SubtitleToken, Cue, Offset)? onWord;
  final WorkbenchStudyMode studyMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
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
      body: Center(
        child: SizedBox(
          key: const Key('transcript-host'),
          width: 520,
          height: 300,
          child: TranscriptPanel(
            track: track,
            scrollController: controller,
            currentCue: currentCue,
            wordEntries: const <String, LexicalEntry>{},
            showStyles: true,
            baseColor: Colors.black,
            onWord: onWord ?? (_, _, _) async {},
            onSeekCue: (_) async {},
            onToggleAnalysis: onToggleAnalysis,
            analysisExpanded: analysisExpanded,
            analysis: analysis,
            studyMode: studyMode,
          ),
        ),
      ),
    ),
  );
}
