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
    expect(timing.text, 'world');
    expect(timing.confidence, 0.35);
    expect(timing.providerVersion, 'v1');
    expect(timing.tokenIndex, 2);
    expect(timing.toJson()['start_ms'], 100);
    expect(timing.toJson()['end_ms'], 300);
  });

  test('parses complete word timeline resources', () {
    final timeline = WordTimeline.fromJson(const {
      'id': 'timeline-1',
      'track_id': 'track-1',
      'media_id': 'media-1',
      'algorithm_id': 'mfa',
      'algorithm_version': '2.0',
      'config_hash': 'hash',
      'parent_timeline_id': null,
      'created_by': 'algorithm',
      'status': 'active',
      'metrics_json': {},
      'created_at_ms': 10,
      'updated_at_ms': 20,
      'words': [
        {
          'sentence_id': 'sentence-1',
          'token_index': 0,
          'text': 'Hello',
          'start_ms': 100,
          'end_ms': 250,
          'confidence': null,
          'timing_source': 'forced_aligned',
          'provider_id': 'mfa',
          'provider_version': '2.0',
        },
      ],
    });

    expect(timeline.id, 'timeline-1');
    expect(timeline.words.single.start, const Duration(milliseconds: 100));
    expect(timeline.words.single.providerVersion, '2.0');
  });

  test(
    'selects current detected phone with offset and excludes end boundary',
    () {
      const phones = [
        DetectedPhone(
          symbol: 'AH',
          displayIpa: 'ə',
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
          displayIpa: 'A',
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
          displayIpa: 'B',
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

  test('parses chunk partition and selects current chunk with offset', () {
    final partition = SentenceChunkPartition.fromJson(const {
      'sentence_id': 'sentence-1',
      'partitioner_id': 'test',
      'partitioner_version': 'v1',
      'timing_quality': 'estimated',
      'chunks': [
        {
          'index': 0,
          'token_start': 0,
          'token_end': 1,
          'text': 'hello world',
          'start_ms': 100,
          'end_ms': 500,
          'boundary_after': null,
        },
      ],
    });

    expect(partition.chunks.single.text, 'hello world');
    expect(
      currentChunkAtPosition(
        partition,
        const Duration(milliseconds: 350),
        offset: const Duration(milliseconds: 100),
      ),
      0,
    );
    expect(
      currentChunkAtPosition(
        partition,
        const Duration(milliseconds: 600),
        offset: const Duration(milliseconds: 100),
      ),
      isNull,
    );
  });

  test('parses chunk timeline resources into sentence partitions', () {
    final timeline = ChunkTimeline.fromJson(const {
      'id': 'chunk-timeline-1',
      'track_id': 'track-1',
      'media_id': 'media-1',
      'parent_word_timeline_id': 'word-timeline-1',
      'provider_id': 'acoustic-first-rule-partitioner',
      'provider_version': 'v4',
      'algorithm': 'acoustic_semantic_v1',
      'precision': 'precise',
      'created_by': 'algorithm',
      'status': 'active',
      'metrics_json': {},
      'chunks': [
        {
          'id': 'chunk-1',
          'sentence_id': 'sentence-1',
          'chunk_index': 0,
          'start_word_index': 0,
          'end_word_index': 1,
          'start_ms': 100,
          'end_ms': 500,
          'text': 'hello world',
          'boundary_sources': ['pause'],
          'confidence': 0.92,
          'warnings': [],
          'evidence_json': {},
        },
      ],
      'created_at_ms': 1,
      'updated_at_ms': 2,
    });

    final partitions = chunkPartitionsFromTimeline(timeline);
    expect(partitions['sentence-1']?.partitionerId, timeline.providerId);
    expect(partitions['sentence-1']?.timingQuality, 'precise');
    expect(partitions['sentence-1']?.chunks.single.tokenEnd, 1);
    expect(
      currentChunkAtPosition(
        partitions['sentence-1'],
        const Duration(milliseconds: 200),
      ),
      0,
    );
  });
}
