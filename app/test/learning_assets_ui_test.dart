import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/learning_assets_ui.dart';
import 'package:llplayer_next/models/runtime_resources.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/subtitle/token_line.dart';

Widget localized(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

// A line where the semantic (sense-group) and prosodic (chunk) boundaries
// deliberately diverge, so compare mode has something to mark. Chunk edge sits
// at token 4; sense-group edges sit at tokens 2, 4 and 6 — so 2 and 6 diverge
// while 4 coincides.
const _groupingCue = Cue(
  id: 'sentence-1',
  index: 0,
  start: Duration.zero,
  end: Duration(seconds: 3),
  text: 'I think it is great',
  tokens: [
    SubtitleToken(index: 0, kind: 'word', text: 'I', normalized: 'i'),
    SubtitleToken(index: 1, kind: 'whitespace', text: ' ', normalized: null),
    SubtitleToken(index: 2, kind: 'word', text: 'think', normalized: 'think'),
    SubtitleToken(index: 3, kind: 'whitespace', text: ' ', normalized: null),
    SubtitleToken(index: 4, kind: 'word', text: 'it', normalized: 'it'),
    SubtitleToken(index: 5, kind: 'whitespace', text: ' ', normalized: null),
    SubtitleToken(index: 6, kind: 'word', text: 'is', normalized: 'is'),
    SubtitleToken(index: 7, kind: 'whitespace', text: ' ', normalized: null),
    SubtitleToken(index: 8, kind: 'word', text: 'great', normalized: 'great'),
  ],
);

const _groupingPartition = SentenceChunkPartition(
  sentenceId: 'sentence-1',
  chunks: [
    DisplayChunk(
      index: 0,
      tokenStart: 0,
      tokenEnd: 3,
      text: 'I think',
      start: Duration.zero,
      end: Duration(seconds: 1),
    ),
    DisplayChunk(
      index: 1,
      tokenStart: 4,
      tokenEnd: 8,
      text: 'it is great',
      start: Duration(seconds: 1),
      end: Duration(seconds: 3),
    ),
  ],
  partitionerId: 'test',
  partitionerVersion: 'v1',
  timingQuality: 'estimated',
);

const _groupingSenseGroups = [
  SenseGroup(
    id: 'sg-0',
    sentenceId: 'sentence-1',
    groupIndex: 0,
    startTokenIndex: 0,
    endTokenIndex: 1,
    text: 'I',
    confidence: 0.5,
    sources: [],
  ),
  SenseGroup(
    id: 'sg-1',
    sentenceId: 'sentence-1',
    groupIndex: 1,
    startTokenIndex: 2,
    endTokenIndex: 3,
    text: 'think',
    confidence: 0.5,
    sources: [],
  ),
  SenseGroup(
    id: 'sg-2',
    sentenceId: 'sentence-1',
    groupIndex: 2,
    startTokenIndex: 4,
    endTokenIndex: 5,
    text: 'it',
    confidence: 0.5,
    sources: [],
  ),
  SenseGroup(
    id: 'sg-3',
    sentenceId: 'sentence-1',
    groupIndex: 3,
    startTokenIndex: 6,
    endTokenIndex: 8,
    text: 'is great',
    confidence: 0.5,
    sources: [],
  ),
];

const _groupingWordTimings = [
  WordTiming(
    sentenceId: 'sentence-1',
    tokenIndex: 0,
    start: Duration.zero,
    end: Duration(milliseconds: 350),
    source: 'test',
    provider: 'test',
  ),
  WordTiming(
    sentenceId: 'sentence-1',
    tokenIndex: 2,
    start: Duration(milliseconds: 400),
    end: Duration(milliseconds: 900),
    source: 'test',
    provider: 'test',
  ),
  WordTiming(
    sentenceId: 'sentence-1',
    tokenIndex: 4,
    start: Duration(milliseconds: 1000),
    end: Duration(milliseconds: 1350),
    source: 'test',
    provider: 'test',
  ),
  WordTiming(
    sentenceId: 'sentence-1',
    tokenIndex: 6,
    start: Duration(milliseconds: 1400),
    end: Duration(milliseconds: 1700),
    source: 'test',
    provider: 'test',
  ),
  WordTiming(
    sentenceId: 'sentence-1',
    tokenIndex: 8,
    start: Duration(milliseconds: 1800),
    end: Duration(milliseconds: 2300),
    source: 'test',
    provider: 'test',
  ),
];

void main() {
  test('OpenSubtitles media hash follows the 64-bit file algorithm', () async {
    final directory = await Directory.systemTemp.createTemp(
      'llplayer-learning-assets-hash-',
    );
    final file = File('${directory.path}/media.bin');
    await file.writeAsBytes(List<int>.filled(131072, 0));
    expect(await computeOpenSubtitlesMovieHash(file.path), '0000000000020000');
    await directory.delete(recursive: true);
  });

  testWidgets('learning asset tile shows phrase status and durable sources', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      localized(
        LearningAssetTile(
          details: const LexicalEntryDetails(
            entry: LexicalEntry(
              id: 'lexical-1',
              normalizedForm: 'piece of cake',
              displayForm: 'piece of cake',
              kind: 'phrase',
              status: 'known_not_recognized',
              language: 'en',
            ),
            occurrences: [
              LexicalOccurrence(
                mediaTitleSnapshot: 'Clip',
                mediaFingerprintSnapshot: 'sha256:clip',
                sentenceTextSnapshot: 'That was a piece of cake.',
                startMsSnapshot: 0,
                endMsSnapshot: 1000,
                encounterCount: 1,
              ),
            ],
          ),
          onTap: () => selected = true,
        ),
      ),
    );
    expect(find.text('piece of cake'), findsOneWidget);
    expect(find.text('Phrase · Known, not recognized'), findsOneWidget);
    expect(find.text('1 Sources'), findsOneWidget);
    await tester.tap(find.text('piece of cake'));
    expect(selected, isTrue);
  });

  testWidgets('learning resource tile exposes provenance and install action', (
    tester,
  ) async {
    var toggled = false;
    await tester.pumpWidget(
      localized(
        LearningResourceTile(
          value: const LearningResourceDescriptor(
            id: 'ecdict',
            displayName: 'ECDICT',
            version: 'bc015ed2',
            license: 'MIT',
            checksumSha256: 'abc123',
            sizeBytes: 1024,
            state: 'available',
            installedBytes: 0,
          ),
          busy: false,
          onToggle: () => toggled = true,
        ),
      ),
    );
    expect(find.text('ECDICT'), findsOneWidget);
    expect(find.textContaining('MIT · available'), findsOneWidget);
    expect(find.textContaining('abc123'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.download));
    expect(toggled, isTrue);
  });

  testWidgets(
    'subtitle phrase underline prefers longest candidate and selects phrase',
    (tester) async {
      PhraseCandidate? selectedPhrase;
      var selectedWords = 0;
      const cue = Cue(
        id: 'sentence-1',
        index: 0,
        start: Duration.zero,
        end: Duration(seconds: 2),
        text: 'I look forward to it.',
        tokens: [
          SubtitleToken(index: 0, kind: 'word', text: 'I', normalized: 'i'),
          SubtitleToken(
            index: 1,
            kind: 'whitespace',
            text: ' ',
            normalized: null,
          ),
          SubtitleToken(
            index: 2,
            kind: 'word',
            text: 'look',
            normalized: 'look',
          ),
          SubtitleToken(
            index: 3,
            kind: 'whitespace',
            text: ' ',
            normalized: null,
          ),
          SubtitleToken(
            index: 4,
            kind: 'word',
            text: 'forward',
            normalized: 'forward',
          ),
          SubtitleToken(
            index: 5,
            kind: 'whitespace',
            text: ' ',
            normalized: null,
          ),
          SubtitleToken(index: 6, kind: 'word', text: 'to', normalized: 'to'),
          SubtitleToken(
            index: 7,
            kind: 'whitespace',
            text: ' ',
            normalized: null,
          ),
          SubtitleToken(index: 8, kind: 'word', text: 'it', normalized: 'it'),
          SubtitleToken(
            index: 9,
            kind: 'punctuation',
            text: '.',
            normalized: null,
          ),
        ],
      );
      await tester.pumpWidget(
        localized(
          TokenLine(
            cue: cue,
            profiles: const {},
            showStyles: true,
            phraseCandidates: const [
              PhraseCandidate(
                canonicalForm: 'look forward to',
                displayForm: 'look forward to',
                tokenStart: 2,
                tokenEnd: 6,
              ),
              PhraseCandidate(
                canonicalForm: 'forward to',
                displayForm: 'forward to',
                tokenStart: 4,
                tokenEnd: 6,
              ),
            ],
            onWord: (_, _) async => selectedWords += 1,
            onPhrase: (candidate, _) async => selectedPhrase = candidate,
          ),
        ),
      );
      expect(find.byType(PhraseUnderlineSpan), findsOneWidget);
      final underline = tester.getRect(find.byType(PhraseUnderlineSpan));
      await tester.tapAt(Offset(underline.center.dx, underline.bottom - 2));
      expect(selectedPhrase?.canonicalForm, 'look forward to');
      expect(selectedWords, 0);
    },
  );

  testWidgets('subtitle renders static product chunks as separate capsules', (
    tester,
  ) async {
    const cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration.zero,
      end: Duration(seconds: 2),
      text: 'I think so',
      tokens: [
        SubtitleToken(index: 0, kind: 'word', text: 'I', normalized: 'i'),
        SubtitleToken(
          index: 1,
          kind: 'whitespace',
          text: ' ',
          normalized: null,
        ),
        SubtitleToken(
          index: 2,
          kind: 'word',
          text: 'think',
          normalized: 'think',
        ),
        SubtitleToken(
          index: 3,
          kind: 'whitespace',
          text: ' ',
          normalized: null,
        ),
        SubtitleToken(index: 4, kind: 'word', text: 'so', normalized: 'so'),
      ],
    );
    await tester.pumpWidget(
      localized(
        TokenLine(
          cue: cue,
          profiles: const {},
          showStyles: true,
          groupingMode: 'prosodic',
          chunkPartition: const SentenceChunkPartition(
            sentenceId: 'sentence-1',
            chunks: [
              DisplayChunk(
                index: 0,
                tokenStart: 0,
                tokenEnd: 2,
                text: 'I think',
                start: Duration.zero,
                end: Duration(seconds: 1),
              ),
              DisplayChunk(
                index: 1,
                tokenStart: 4,
                tokenEnd: 4,
                text: 'so',
                start: Duration(seconds: 1),
                end: Duration(seconds: 2),
              ),
            ],
            partitionerId: 'test',
            partitionerVersion: 'v1',
            timingQuality: 'estimated',
          ),
          onWord: (_, _) async {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chunk-container-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('chunk-container-1')), findsOneWidget);
    expect(find.text('so'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('chunk-scale-0')))
          .scale,
      1,
    );
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('chunk-scale-1')))
          .scale,
      1,
    );
  });

  testWidgets('chunk bounce is optional and independent from word style', (
    tester,
  ) async {
    const cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration.zero,
      end: Duration(seconds: 2),
      text: 'I think',
      tokens: [
        SubtitleToken(index: 0, kind: 'word', text: 'I', normalized: 'i'),
        SubtitleToken(
          index: 1,
          kind: 'whitespace',
          text: ' ',
          normalized: null,
        ),
        SubtitleToken(
          index: 2,
          kind: 'word',
          text: 'think',
          normalized: 'think',
        ),
      ],
    );
    await tester.pumpWidget(
      localized(
        TokenLine(
          cue: cue,
          profiles: const {},
          showStyles: true,
          groupingMode: 'prosodic',
          chunkPartition: const SentenceChunkPartition(
            sentenceId: 'sentence-1',
            chunks: [
              DisplayChunk(
                index: 0,
                tokenStart: 0,
                tokenEnd: 2,
                text: 'I think',
                start: Duration.zero,
                end: Duration(seconds: 2),
              ),
            ],
            partitionerId: 'test',
            partitionerVersion: 'v1',
            timingQuality: 'estimated',
          ),
          currentChunkIndex: 0,
          chunkHighlightStyle: 'bounce',
          currentWordStyle: 'glow',
          onWord: (_, _) async {},
        ),
      ),
    );

    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('chunk-scale-0')))
          .scale,
      1.045,
    );
  });

  testWidgets('prosodic grouping renders chunk capsules only', (tester) async {
    await tester.pumpWidget(
      localized(
        TokenLine(
          cue: _groupingCue,
          profiles: const {},
          showStyles: true,
          groupingMode: 'prosodic',
          chunkPartition: _groupingPartition,
          senseGroups: _groupingSenseGroups,
          onWord: (_, _) async {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chunk-container-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('chunk-container-1')), findsOneWidget);
    // No semantic capsules and no compare overlay in a single prosodic layer.
    expect(find.byKey(const ValueKey('sense-provisional-0')), findsNothing);
    expect(find.byKey(const ValueKey('divergence-marker-2')), findsNothing);
  });

  testWidgets('semantic grouping renders solid capsules', (tester) async {
    await tester.pumpWidget(
      localized(
        TokenLine(
          cue: _groupingCue,
          profiles: const {},
          showStyles: true,
          groupingMode: 'semantic',
          chunkPartition: _groupingPartition,
          senseGroups: _groupingSenseGroups,
          onWord: (_, _) async {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('sense-container-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('sense-provisional-0')), findsNothing);
    final container = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('sense-container-0')),
    );
    expect((container.decoration! as BoxDecoration).border, isNotNull);
    // Semantic mode does not draw the prosodic chunks or divergence markers.
    expect(find.byKey(const ValueKey('chunk-container-0')), findsNothing);
    expect(find.byKey(const ValueKey('divergence-marker-2')), findsNothing);
  });

  testWidgets('semantic grouping follows the projected playback range', (
    tester,
  ) async {
    Widget line(Duration position) => localized(
      TokenLine(
        cue: _groupingCue,
        profiles: const {},
        showStyles: true,
        groupingMode: 'semantic',
        senseGroups: _groupingSenseGroups,
        wordTimings: _groupingWordTimings,
        mediaPosition: position,
        chunkHighlightStyle: 'bounce',
        onWord: (_, _) async {},
      ),
    );

    await tester.pumpWidget(line(const Duration(milliseconds: 500)));
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('sense-scale-1')))
          .scale,
      1.045,
    );
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('sense-scale-3')))
          .scale,
      1,
    );

    await tester.pumpWidget(line(const Duration(milliseconds: 1900)));
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('sense-scale-1')))
          .scale,
      1,
    );
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('sense-scale-3')))
          .scale,
      1.045,
    );
  });

  testWidgets('semantic capsule click seeks through the chunk callback', (
    tester,
  ) async {
    DisplayChunk? selected;
    await tester.pumpWidget(
      localized(
        TokenLine(
          cue: _groupingCue,
          profiles: const {},
          showStyles: true,
          groupingMode: 'semantic',
          senseGroups: _groupingSenseGroups,
          wordTimings: _groupingWordTimings,
          onWord: (_, _) async {},
          onChunk: (chunk) async => selected = chunk,
        ),
      ),
    );

    final rect = tester.getRect(
      find.byKey(const ValueKey('sense-container-1')),
    );
    await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
    expect(selected?.start, const Duration(milliseconds: 400));
    expect(selected?.end, const Duration(milliseconds: 900));
  });

  testWidgets('semantic group without a projection is not interactive', (
    tester,
  ) async {
    var seekCount = 0;
    await tester.pumpWidget(
      localized(
        TokenLine(
          cue: _groupingCue,
          profiles: const {},
          showStyles: true,
          groupingMode: 'semantic',
          senseGroups: _groupingSenseGroups,
          wordTimings: _groupingWordTimings.sublist(1),
          mediaPosition: const Duration(milliseconds: 100),
          onWord: (_, _) async {},
          onChunk: (_) async => seekCount += 1,
        ),
      ),
    );

    final firstCapsule = find.byKey(const ValueKey('sense-container-0'));
    final detector = tester.widget<GestureDetector>(
      find.ancestor(of: firstCapsule, matching: find.byType(GestureDetector)),
    );
    expect(detector.onTap, isNull);
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const ValueKey('sense-scale-0')))
          .scale,
      1,
    );
    final rect = tester.getRect(firstCapsule);
    await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
    expect(seekCount, 0);

    final secondRect = tester.getRect(
      find.byKey(const ValueKey('sense-container-1')),
    );
    await tester.tapAt(Offset(secondRect.center.dx, secondRect.top + 1));
    expect(seekCount, 1);
  });

  testWidgets('compare grouping overlays divergence markers where layers '
      'disagree', (tester) async {
    await tester.pumpWidget(
      localized(
        TokenLine(
          cue: _groupingCue,
          profiles: const {},
          showStyles: true,
          groupingMode: 'compare',
          chunkPartition: _groupingPartition,
          senseGroups: _groupingSenseGroups,
          onWord: (_, _) async {},
        ),
      ),
    );

    // Prosodic capsules form the acoustic base.
    expect(find.byKey(const ValueKey('chunk-container-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('chunk-container-1')), findsOneWidget);
    // Markers only where a sense-group edge does not coincide with a chunk edge.
    expect(find.byKey(const ValueKey('divergence-marker-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('divergence-marker-6')), findsOneWidget);
    // The sense edge at token 4 matches the chunk edge, so it is not marked.
    expect(find.byKey(const ValueKey('divergence-marker-4')), findsNothing);
  });

  testWidgets('off grouping renders a flat line with no grouping affordances', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(
        TokenLine(
          cue: _groupingCue,
          profiles: const {},
          showStyles: true,
          chunkPartition: _groupingPartition,
          senseGroups: _groupingSenseGroups,
          onWord: (_, _) async {},
        ),
      ),
    );

    expect(find.text('think'), findsOneWidget);
    expect(find.byKey(const ValueKey('chunk-container-0')), findsNothing);
    expect(find.byKey(const ValueKey('sense-container-0')), findsNothing);
    expect(find.byKey(const ValueKey('divergence-marker-2')), findsNothing);
  });
}
