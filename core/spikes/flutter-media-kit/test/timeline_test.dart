import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_media_kit/timeline.dart';

void main() {
  const cues = [
    Cue('first', Duration(milliseconds: 500), Duration(seconds: 2)),
    Cue('overlap-a', Duration(seconds: 3), Duration(milliseconds: 4800)),
    Cue('overlap-b', Duration(seconds: 4), Duration(milliseconds: 5500)),
  ];

  test('returns no cue in a gap', () {
    expect(currentCueAt(cues, const Duration(milliseconds: 2500)), isNull);
  });

  test('includes exact cue boundaries', () {
    expect(currentCueAt(cues, const Duration(milliseconds: 500))?.id, 'first');
    expect(currentCueAt(cues, const Duration(seconds: 2))?.id, 'first');
  });

  test('selects latest-starting active cue during overlap', () {
    expect(currentCueAt(cues, const Duration(milliseconds: 4500))?.id, 'overlap-b');
  });
}
