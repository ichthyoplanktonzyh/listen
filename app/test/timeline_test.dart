import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/timeline.dart';

Cue cue(String id, int start, int end) => Cue(
  id: id,
  index: int.parse(id),
  start: Duration(milliseconds: start),
  end: Duration(milliseconds: end),
  text: id,
  tokens: const [],
);

void main() {
  final cues = [
    cue('0', 500, 2000),
    cue('1', 1500, 2500),
    cue('2', 3000, 4000),
  ];

  test('returns no cue in a gap and excludes the end boundary', () {
    final timeline = TimelineCursor(cues);
    expect(timeline.current(const Duration(milliseconds: 499)), isNull);
    expect(timeline.current(const Duration(milliseconds: 2500)), isNull);
  });

  test('selects latest-starting active cue during overlap', () {
    final timeline = TimelineCursor(cues);
    expect(timeline.current(const Duration(milliseconds: 1700))?.id, '1');
  });

  test('applies offset to lookup seek and loop boundaries', () {
    final timeline = TimelineCursor(
      cues,
      offset: const Duration(milliseconds: 100),
    );
    expect(timeline.current(const Duration(milliseconds: 550)), isNull);
    expect(timeline.current(const Duration(milliseconds: 600))?.id, '0');
    expect(timeline.mediaStart(cues.first), const Duration(milliseconds: 600));
    expect(timeline.mediaEnd(cues.first), const Duration(milliseconds: 2100));
  });

  test('navigates adjacent cues with clear boundaries', () {
    final timeline = TimelineCursor(cues);
    expect(timeline.previous(cues.first), isNull);
    expect(timeline.next(cues.first)?.id, '1');
    expect(timeline.next(cues.last), isNull);
  });

  test('finds the final cue in a 2100 cue timeline', () {
    final large = List.generate(
      2100,
      (index) => cue('$index', index * 1000, index * 1000 + 800),
    );
    expect(
      TimelineCursor(large).current(const Duration(milliseconds: 2099500))?.id,
      '2099',
    );
  });

  test('selects current word with offset and excludes end boundary', () {
    const timings = [
      WordTiming(
        sentenceId: 'sentence-1',
        tokenIndex: 2,
        start: Duration(milliseconds: 100),
        end: Duration(milliseconds: 300),
        source: 'estimated',
        provider: 'deterministic',
      ),
    ];
    expect(
      currentWordTokenIndex(
        timings,
        const Duration(milliseconds: 250),
        offset: const Duration(milliseconds: 100),
      ),
      2,
    );
    expect(
      currentWordTokenIndex(
        timings,
        const Duration(milliseconds: 400),
        offset: const Duration(milliseconds: 100),
      ),
      isNull,
    );
  });

  test(
    'selects both words when repeated ASR points are split into intervals',
    () {
      const timings = [
        WordTiming(
          sentenceId: 'sentence-1',
          tokenIndex: 5,
          start: Duration(milliseconds: 4200),
          end: Duration(milliseconds: 4201),
          source: 'asr_reported',
          provider: 'whisper.cpp',
        ),
        WordTiming(
          sentenceId: 'sentence-1',
          tokenIndex: 6,
          start: Duration(milliseconds: 4201),
          end: Duration(milliseconds: 5560),
          source: 'asr_reported',
          provider: 'whisper.cpp',
        ),
      ];

      expect(
        currentWordTokenIndex(timings, const Duration(milliseconds: 4200)),
        5,
      );
      expect(
        currentWordTokenIndex(timings, const Duration(milliseconds: 4201)),
        6,
      );
      expect(
        currentWordTokenIndex(timings, const Duration(milliseconds: 5559)),
        6,
      );
    },
  );

  test('parses word timing fields from the API contract', () {
    final timing = WordTiming.fromJson(const {
      'sentence_id': 'sentence-1',
      'token_index': 2,
      'text': 'world',
      'start_ms': 100,
      'end_ms': 300,
      'confidence': 0.35,
      'timing_source': 'estimated',
      'provider_id': 'subtitle-weighted-estimator',
      'provider_version': 'v1',
    });

    expect(timing.source, 'estimated');
    expect(timing.provider, 'subtitle-weighted-estimator');
    expect(timing.tokenIndex, 2);
  });

  test(
    'selects current detected phone with offset and excludes end boundary',
    () {
      const phones = [
        DetectedPhone(
          symbol: 'AH',
          phoneSet: 'arpabet',
          start: Duration(milliseconds: 100),
          end: Duration(milliseconds: 200),
          confidence: 0.8,
          tokenIndex: 0,
          provider: 'test',
          modelRevision: 'v1',
        ),
      ];
      expect(
        currentDetectedPhoneAt(
          phones,
          const Duration(milliseconds: 250),
          offset: const Duration(milliseconds: 100),
        )?.symbol,
        'AH',
      );
      expect(
        currentDetectedPhoneAt(
          phones,
          const Duration(milliseconds: 300),
          offset: const Duration(milliseconds: 100),
        ),
        isNull,
      );
    },
  );

  test(
    'detected phone selection follows seek loop and drag position changes',
    () {
      const phones = [
        DetectedPhone(
          symbol: 'A',
          phoneSet: 'test',
          start: Duration(milliseconds: 100),
          end: Duration(milliseconds: 200),
          confidence: 0.8,
          tokenIndex: 0,
          provider: 'test',
          modelRevision: 'v1',
        ),
        DetectedPhone(
          symbol: 'B',
          phoneSet: 'test',
          start: Duration(milliseconds: 200),
          end: Duration(milliseconds: 300),
          confidence: 0.8,
          tokenIndex: 0,
          provider: 'test',
          modelRevision: 'v1',
        ),
      ];

      final positions = [150, 250, 125, 350, 225, 50];
      final selected = positions
          .map(
            (value) => currentDetectedPhoneAt(
              phones,
              Duration(milliseconds: value),
            )?.symbol,
          )
          .toList();

      expect(selected, ['A', 'B', 'A', null, 'B', null]);
    },
  );

  test(
    'keeps newest phonetic analysis when sentence has multiple versions',
    () {
      final values = latestPhoneticAnalysesBySentence([
        {'id': 'new', 'sentence_id': 'sentence-1'},
        {'id': 'old', 'sentence_id': 'sentence-1'},
        {'id': 'other', 'sentence_id': 'sentence-2'},
      ]);

      expect(values['sentence-1']?['id'], 'new');
      expect(values['sentence-2']?['id'], 'other');
    },
  );
}
