import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/timeline_phone_projection.dart';

Map<String, dynamic> _phone(
  String symbol,
  int startMs, {
  Object? tokenIndex = 0,
}) => {
  'symbol': symbol,
  'display_ipa': symbol,
  'phone_set': 'ipa',
  'start_ms': startMs,
  'end_ms': startMs + 50,
  'confidence': 0.5,
  'token_index': tokenIndex,
  'provider_id': 'wav2vec2-ctc-phoneme',
  'model_revision': 'rev',
};

Map<String, dynamic> _timeline({
  required String sentenceId,
  required String status,
  required List<Map<String, dynamic>> phones,
}) => {
  'id': 'timeline-$sentenceId-$status',
  'track_id': 'track-1',
  'media_id': 'media-1',
  'sentence_id': sentenceId,
  'provider_id': 'wav2vec2-ctc-phoneme',
  'provider_version': '1',
  'phone_set': 'ipa',
  'precision': 'frame',
  'created_by': 'package',
  'status': status,
  'metrics_json': const <String, dynamic>{},
  'phones': phones,
  'created_at_ms': 1,
  'updated_at_ms': 2,
};

void main() {
  // Core's package import contract lands every package resource as a
  // candidate, so an adopted package's track has no active phone timeline at
  // all. Reading only the active one reported "no phone evidence" over a
  // fully generated package, which hid C entirely.
  test('prefers an active timeline but accepts candidates', () {
    final phones = phonesBySentenceFromTimelineJson({
      'phone_timelines': [
        _timeline(
          sentenceId: 'sentence-1',
          status: 'candidate',
          phones: [
            // Out of order, to pin the time sort.
            _phone('b', 200),
            _phone('a', 100),
            // No token index: cannot be tied to a word, so it is dropped.
            _phone('x', 150, tokenIndex: null),
          ],
        ),
        _timeline(
          sentenceId: 'sentence-1',
          status: 'archived',
          phones: [_phone('z', 0)],
        ),
        _timeline(
          sentenceId: 'sentence-2',
          status: 'candidate',
          phones: [_phone('c', 0)],
        ),
        _timeline(
          sentenceId: 'sentence-2',
          status: 'active',
          phones: [_phone('d', 0)],
        ),
      ],
    });

    expect(phones['sentence-1']!.map((p) => p.symbol), ['a', 'b']);
    expect(phones['sentence-2']!.map((p) => p.symbol), ['d']);
    expect(phones['missing'], isNull);
  });

  // Core's export omits keys on some phone timeline shapes — a committed
  // contract fixture carries entries with no `track_id`. Parsing the family
  // through the typed model threw on those and took the whole document down,
  // rhythm frames included. Each malformed item may cost only itself.
  test('a malformed timeline or phone drops that item alone', () {
    final phones = phonesBySentenceFromTimelineJson({
      'phone_timelines': [
        // No track_id, which the typed model requires.
        {
          'id': 'partial',
          'sentence_id': 'sentence-1',
          'status': 'candidate',
          'phones': [_phone('a', 0)],
        },
        _timeline(
          sentenceId: 'sentence-2',
          status: 'candidate',
          phones: [
            {'symbol': 'broken'},
            _phone('b', 0),
          ],
        ),
        'not a map',
      ],
    });

    expect(phones['sentence-1']!.map((p) => p.symbol), ['a']);
    expect(phones['sentence-2']!.map((p) => p.symbol), ['b']);
  });

  test('an export with no phone family projects nothing', () {
    expect(phonesBySentenceFromTimelineJson(const {}), isEmpty);
    expect(
      phonesBySentenceFromTimelineJson(const {'phone_timelines': null}),
      isEmpty,
    );
  });
}
