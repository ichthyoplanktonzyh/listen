import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/widgets/subtitle/token_line.dart';

/// #31: the caption line marks connected speech with a painted ‿ tie between
/// linked words — replacing the space inside the link — and leaves unrelated
/// junctions alone. Display-only: the widget must not reinterpret the refs.
void main() {
  const cue = Cue(
    id: 'sentence-1',
    index: 0,
    start: Duration.zero,
    end: Duration(seconds: 2),
    text: 'been meaning to ask',
    tokens: [
      SubtitleToken(index: 0, kind: 'word', text: 'been', normalized: 'been'),
      SubtitleToken(index: 1, kind: 'space', text: ' ', normalized: null),
      SubtitleToken(
        index: 2,
        kind: 'word',
        text: 'meaning',
        normalized: 'meaning',
      ),
      SubtitleToken(index: 3, kind: 'space', text: ' ', normalized: null),
      SubtitleToken(index: 4, kind: 'word', text: 'to', normalized: 'to'),
      SubtitleToken(index: 5, kind: 'space', text: ' ', normalized: null),
      SubtitleToken(index: 6, kind: 'word', text: 'ask', normalized: 'ask'),
    ],
  );

  const linkingRef = RhythmConnectedSpeechRef(
    id: 'cs1',
    tokenStart: 0,
    tokenEnd: 2,
    label: 'linking',
    hint: 'been meaning links',
    divergence: 'clip_specific',
    signalSources: ['phone_segmental'],
    evidenceClass: 'heuristic_proxy',
    confidence: 0.8,
  );

  Widget app({List<RhythmConnectedSpeechRef> refs = const []}) => MaterialApp(
    home: Scaffold(
      body: TokenLine(
        cue: cue,
        profiles: const {},
        showStyles: false,
        onWord: (_, _) async {},
        connectedSpeechRefs: refs,
      ),
    ),
  );

  testWidgets('a linked junction replaces its space with a tooltip tie', (
    tester,
  ) async {
    await tester.pumpWidget(app(refs: const [linkingRef]));

    // The tie carries the reference's hint as its tooltip.
    expect(find.byTooltip('been meaning links'), findsOneWidget);
    // Both linked words still render; unrelated words are untouched.
    for (final word in const ['been', 'meaning', 'to', 'ask']) {
      expect(find.textContaining(word), findsWidgets);
    }
  });

  testWidgets('no refs means no ties', (tester) async {
    await tester.pumpWidget(app());

    expect(find.byTooltip('been meaning links'), findsNothing);
  });

  testWidgets('a ref without token indices is ignored', (tester) async {
    const timedOnlyRef = RhythmConnectedSpeechRef(
      id: 'cs2',
      label: 'weak form',
      hint: 'no token range',
      divergence: 'clip_specific',
      signalSources: ['phone_segmental'],
      evidenceClass: 'heuristic_proxy',
      confidence: 0.8,
    );
    await tester.pumpWidget(app(refs: const [timedOnlyRef]));

    expect(find.byTooltip('no token range'), findsNothing);
  });
}
