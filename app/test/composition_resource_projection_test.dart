import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/composition_resource_projection.dart';

List<int> _payload(Map<String, dynamic> json) => utf8.encode(jsonEncode(json));

void main() {
  test('v2 timed text keeps exact segments without inventing tokens', () {
    final track = projectCompositionTimedTranscript(
      _payload({
        'language': 'en',
        'segments': [
          {
            'id': 'segment-0',
            'index': 0,
            'language': 'en',
            'start_ms': 400,
            'end_ms': 1200,
            'text': 'Exact segment text.',
          },
        ],
      }),
      trackId: 'composition:edition-v2',
    );

    expect(track, isNotNull);
    expect(track!.id, 'composition:edition-v2');
    expect(track.language, 'en');
    expect(track.source, 'composition');
    expect(track.cues.single.text, 'Exact segment text.');
    expect(track.cues.single.start, const Duration(milliseconds: 400));
    expect(track.cues.single.end, const Duration(milliseconds: 1200));
    expect(track.cues.single.tokens, isEmpty);
  });

  test('a malformed or missing timed track projects to nothing', () {
    expect(
      projectCompositionTimedTranscript(
        utf8.encode('not json'),
        trackId: 'composition:broken',
      ),
      isNull,
    );
    expect(
      projectCompositionTimedTranscript(null, trackId: 'composition:missing'),
      isNull,
    );
  });

  test(
    'detached subtitle payload preserves sentence order, tokens and times',
    () {
      final track = projectCompositionDetachedSubtitleTranscript(
        _payload({
          'language': 'en',
          'sentences': [
            {
              'id': 'sentence-1',
              'index': 1,
              'display_text': 'Words matter.',
              'start_ms': 1300,
              'end_ms': 2100,
              'tokens': [
                {
                  'index': 0,
                  'kind': 'word',
                  'text': 'Words',
                  'normalized': 'words',
                  'start_char': 0,
                  'end_char': 5,
                },
                {
                  'index': 1,
                  'kind': 'whitespace',
                  'text': ' ',
                  'normalized': null,
                  'start_char': 5,
                  'end_char': 6,
                },
                {
                  'index': 2,
                  'kind': 'word',
                  'text': 'matter',
                  'normalized': 'matter',
                  'start_char': 6,
                  'end_char': 12,
                },
                {
                  'index': 3,
                  'kind': 'punctuation',
                  'text': '.',
                  'normalized': null,
                  'start_char': 12,
                  'end_char': 13,
                },
              ],
            },
            {
              'id': 'sentence-0',
              'index': 0,
              'display_text': 'Listen, carefully!',
              'start_ms': 100,
              'end_ms': 1200,
              'tokens': [
                {
                  'index': 0,
                  'kind': 'word',
                  'text': 'Listen',
                  'normalized': 'listen',
                  'start_char': 0,
                  'end_char': 6,
                },
                {
                  'index': 1,
                  'kind': 'punctuation',
                  'text': ',',
                  'normalized': null,
                  'start_char': 6,
                  'end_char': 7,
                },
                {
                  'index': 2,
                  'kind': 'whitespace',
                  'text': ' ',
                  'normalized': null,
                  'start_char': 7,
                  'end_char': 8,
                },
                {
                  'index': 3,
                  'kind': 'word',
                  'text': 'carefully',
                  'normalized': 'carefully',
                  'start_char': 8,
                  'end_char': 17,
                },
                {
                  'index': 4,
                  'kind': 'punctuation',
                  'text': '!',
                  'normalized': null,
                  'start_char': 17,
                  'end_char': 18,
                },
              ],
            },
          ],
        }),
        trackId: 'composition:detached:edition-1:subtitle_text_track',
      );

      expect(track, isNotNull);
      expect(track!.source, 'composition:detached:subtitle_text_track');
      expect(track.cues.map((cue) => cue.id), ['sentence-0', 'sentence-1']);
      expect(track.cues.first.start, const Duration(milliseconds: 100));
      expect(track.cues.last.end, const Duration(milliseconds: 2100));
      expect(track.cues.first.tokens[3].text, 'carefully');
      expect(track.cues.last.tokens[2].normalized, 'matter');
    },
  );

  test('detached subtitle rejects malformed coordinates and token order', () {
    final malformed = {
      'language': 'en',
      'sentences': [
        {
          'id': 'sentence-0',
          'index': 0,
          'display_text': 'Hello.',
          'start_ms': 500,
          'end_ms': 900,
          'tokens': [
            {
              'index': 1,
              'kind': 'word',
              'text': 'Hello',
              'normalized': 'hello',
              'start_char': 0,
              'end_char': 5,
            },
          ],
        },
      ],
    };
    expect(
      projectCompositionDetachedSubtitleTranscript(
        _payload(malformed),
        trackId: 'composition:detached:broken',
      ),
      isNull,
    );
  });

  test('detached subtitle rejects a non-positive sentence window', () {
    final malformed = {
      'language': 'en',
      'sentences': [
        {
          'id': 'sentence-0',
          'index': 0,
          'display_text': 'Hello.',
          'start_ms': 500,
          'end_ms': 500,
          'tokens': [
            {
              'index': 0,
              'kind': 'word',
              'text': 'Hello',
              'normalized': 'hello',
              'start_char': 0,
              'end_char': 5,
            },
            {
              'index': 1,
              'kind': 'punctuation',
              'text': '.',
              'normalized': null,
              'start_char': 5,
              'end_char': 6,
            },
          ],
        },
      ],
    };
    expect(
      projectCompositionDetachedSubtitleTranscript(
        _payload(malformed),
        trackId: 'composition:detached:broken',
      ),
      isNull,
    );
  });

  test('detached subtitle rejects a token text/span mismatch', () {
    final malformed = {
      'language': 'en',
      'sentences': [
        {
          'id': 'sentence-0',
          'index': 0,
          'display_text': 'Hello.',
          'start_ms': 500,
          'end_ms': 900,
          'tokens': [
            {
              'index': 0,
              'kind': 'word',
              'text': 'World',
              'normalized': 'world',
              'start_char': 0,
              'end_char': 5,
            },
            {
              'index': 1,
              'kind': 'punctuation',
              'text': '.',
              'normalized': null,
              'start_char': 5,
              'end_char': 6,
            },
          ],
        },
      ],
    };
    expect(
      projectCompositionDetachedSubtitleTranscript(
        _payload(malformed),
        trackId: 'composition:detached:broken',
      ),
      isNull,
    );
  });

  test('detached subtitle uses Unicode code-point offsets', () {
    final track = projectCompositionDetachedSubtitleTranscript(
      _payload({
        'language': 'en',
        'sentences': [
          {
            'id': 'sentence-emoji',
            'index': 0,
            'display_text': 'Hi 😀.',
            'start_ms': 100,
            'end_ms': 900,
            'tokens': [
              {
                'index': 0,
                'kind': 'word',
                'text': 'Hi',
                'normalized': 'hi',
                'start_char': 0,
                'end_char': 2,
              },
              {
                'index': 1,
                'kind': 'whitespace',
                'text': ' ',
                'normalized': null,
                'start_char': 2,
                'end_char': 3,
              },
              {
                'index': 2,
                'kind': 'other',
                'text': '😀',
                'normalized': null,
                'start_char': 3,
                'end_char': 4,
              },
              {
                'index': 3,
                'kind': 'punctuation',
                'text': '.',
                'normalized': null,
                'start_char': 4,
                'end_char': 5,
              },
            ],
          },
        ],
      }),
      trackId: 'composition:detached:emoji',
    );

    expect(track, isNotNull);
    expect(track!.cues.single.text, 'Hi 😀.');
    expect(track.cues.single.tokens[2].text, '😀');
  });

  test('detached subtitle rejects invalid UTF-8 without replacement', () {
    final invalid = <int>[
      ...utf8.encode('{"language":"en","sentences":['),
      0xC3,
      0x28,
      ...utf8.encode(']}'),
    ];
    expect(
      projectCompositionDetachedSubtitleTranscript(
        invalid,
        trackId: 'composition:detached:invalid-utf8',
      ),
      isNull,
    );
  });

  test('detached rich resources close over the local transcript', () {
    final subtitle = _payload({
      'language': 'en',
      'sentences': [
        {
          'id': 'sentence-0',
          'index': 0,
          'display_text': 'Listen, carefully!',
          'start_ms': 100,
          'end_ms': 1200,
          'tokens': [
            {
              'index': 0,
              'kind': 'word',
              'text': 'Listen',
              'normalized': 'listen',
              'start_char': 0,
              'end_char': 6,
            },
            {
              'index': 1,
              'kind': 'punctuation',
              'text': ',',
              'normalized': null,
              'start_char': 6,
              'end_char': 7,
            },
            {
              'index': 2,
              'kind': 'whitespace',
              'text': ' ',
              'normalized': null,
              'start_char': 7,
              'end_char': 8,
            },
            {
              'index': 3,
              'kind': 'word',
              'text': 'carefully',
              'normalized': 'carefully',
              'start_char': 8,
              'end_char': 17,
            },
            {
              'index': 4,
              'kind': 'punctuation',
              'text': '!',
              'normalized': null,
              'start_char': 17,
              'end_char': 18,
            },
          ],
        },
      ],
    });
    final track = projectCompositionDetachedSubtitleTranscript(
      subtitle,
      trackId: 'composition:detached:rich',
    );
    expect(track, isNotNull);

    final projection = projectCompositionDetachedResources(
      track: track!,
      payloads: {
        'word_timeline': _payload({
          'words': [
            {
              'sentence_id': 'sentence-0',
              'token_index': 0,
              'start_ms': 120,
              'end_ms': 350,
              'timing_source': 'forced_aligned',
              'confidence': 0.9,
            },
            {
              'sentence_id': 'sentence-0',
              'token_index': 3,
              'start_ms': 500,
              'end_ms': 900,
              'timing_source': 'forced_aligned',
              'confidence': 0.9,
            },
          ],
        }),
        'sense_group_analysis': _payload({
          'groups': [
            {
              'sentence_id': 'sentence-0',
              'group_index': 0,
              'start_token_index': 0,
              'end_token_index_exclusive': 4,
              'confidence': 0.8,
              'sources': ['rule'],
            },
          ],
        }),
        'word_acoustics': _payload({
          'sample_rate_hz': 16000,
          'energy_baseline': 'sentence_median_dbfs',
          'pitch_baseline': 'sentence_median_f0_hz',
          'measurements': [
            {
              'word_ref': {'sentence_id': 'sentence-0', 'token_index': 0},
              'energy': {'rms_dbfs': -20.0},
              'pitch': {'median_f0_hz': 180.0},
              'duration': {'duration_ms': 230},
              'voiced_frame_ratio': 0.9,
            },
          ],
        }),
        'prosody_analysis': _payload({
          'chunks': [
            {
              'sentence_id': 'sentence-0',
              'chunk_index': 0,
              'start_token_index': 0,
              'end_token_index_exclusive': 4,
              'nucleus_token_index': 0,
              'confidence': 0.8,
            },
          ],
          'anchors': [
            {
              'word_ref': {'sentence_id': 'sentence-0', 'token_index': 0},
              'lexical_stress': 'primary',
              'realized_prominence': 0.8,
              'utterance_role': 'nucleus',
              'evidence': ['energy'],
              'confidence': 0.8,
            },
          ],
        }),
        'phone_timeline': _payload({
          'phone_set': 'ipa',
          'precision': 'aligned',
          'phones': [
            {
              'symbol': 'l',
              'display_ipa': 'l',
              'start_ms': 120,
              'end_ms': 180,
              'word_ref': {'sentence_id': 'sentence-0', 'token_index': 0},
            },
          ],
        }),
      },
    );

    expect(projection.timingsBySentence['sentence-0'], isNotEmpty);
    expect(projection.senseGroupsBySentence['sentence-0'], isNotEmpty);
    expect(
      projection.chunkPartitionsBySentence['sentence-0']!.chunks,
      isNotEmpty,
    );
    expect(projection.acousticsBySentence['sentence-0'], isNotEmpty);
    expect(projection.prosodyAnchorsBySentence['sentence-0'], isNotEmpty);
    expect(projection.phonesBySentence['sentence-0'], isNotEmpty);
  });
}
