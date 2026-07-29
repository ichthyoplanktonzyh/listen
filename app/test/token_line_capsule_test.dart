import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/subtitle/token_line.dart';

/// §3.7 item 4: the chunk capsules drawn over the video are ink, not a light
/// block. A pale grey fill on top of the picture is the shell glowing over
/// content (charter P2) — and it also pre-highlights every word inside it,
/// leaving the current word nothing left to say.
void main() {
  const cue = Cue(
    id: 'sentence-1',
    index: 0,
    start: Duration.zero,
    end: Duration(seconds: 4),
    text: 'we have been meaning to ask',
    tokens: [
      SubtitleToken(index: 0, kind: 'word', text: 'we', normalized: 'we'),
      SubtitleToken(index: 1, kind: 'space', text: ' ', normalized: null),
      SubtitleToken(index: 2, kind: 'word', text: 'have', normalized: 'have'),
      SubtitleToken(index: 3, kind: 'space', text: ' ', normalized: null),
      SubtitleToken(index: 4, kind: 'word', text: 'been', normalized: 'been'),
      SubtitleToken(index: 5, kind: 'space', text: ' ', normalized: null),
      SubtitleToken(index: 6, kind: 'word', text: 'to', normalized: 'to'),
      SubtitleToken(index: 7, kind: 'space', text: ' ', normalized: null),
      SubtitleToken(index: 8, kind: 'word', text: 'ask', normalized: 'ask'),
    ],
  );

  const partition = SentenceChunkPartition(
    sentenceId: 'sentence-1',
    partitionerId: 'fixture',
    partitionerVersion: '1',
    timingQuality: 'word_timings',
    chunks: [
      DisplayChunk(
        index: 0,
        tokenStart: 0,
        tokenEnd: 3,
        text: 'we have',
        start: Duration.zero,
        end: Duration(seconds: 2),
      ),
      DisplayChunk(
        index: 1,
        tokenStart: 4,
        tokenEnd: 8,
        text: 'been to ask',
        start: Duration(seconds: 2),
        end: Duration(seconds: 4),
      ),
    ],
  );

  Widget app({int? currentChunkIndex}) => MaterialApp(
    theme: ListenTheme.dark(),
    home: Scaffold(
      body: TokenLine(
        cue: cue,
        profiles: const {},
        showStyles: false,
        onWord: (_, _) async {},
        groupingMode: 'prosodic',
        chunkPartition: partition,
        currentChunkIndex: currentChunkIndex,
      ),
    ),
  );

  List<Color?> capsuleColors(WidgetTester tester) => tester
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .map((container) => (container.decoration as BoxDecoration?)?.color)
      .toList();

  testWidgets('a resting capsule uses the overlay surface token', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final colors = capsuleColors(tester);
    expect(colors, isNotEmpty);
    for (final color in colors) {
      expect(color, ListenColors.overlaySurfaceSoft);
    }
  });

  testWidgets('the spoken capsule tints the ink instead of replacing it', (
    tester,
  ) async {
    await tester.pumpWidget(app(currentChunkIndex: 1));
    await tester.pumpAndSettle();

    final colors = capsuleColors(tester).whereType<Color>().toList();
    expect(colors.length, 2);

    final resting = colors.firstWhere(
      (color) => color == ListenColors.overlaySurfaceSoft,
    );
    final spoken = colors.firstWhere(
      (color) => color != ListenColors.overlaySurfaceSoft,
    );

    // The wash is laid over the ink rather than replacing it: it reads a
    // little warmer than the resting capsule, but it is still a dark surface —
    // never the pale block the capsule used to be.
    expect(spoken.a, greaterThanOrEqualTo(resting.a));
    expect(spoken.computeLuminance(), lessThan(0.2));
    expect(spoken.computeLuminance(), greaterThan(resting.computeLuminance()));
  });
}
