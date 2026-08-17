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
      projectCompositionTimedTranscript(
        null,
        trackId: 'composition:missing',
      ),
      isNull,
    );
  });
}
