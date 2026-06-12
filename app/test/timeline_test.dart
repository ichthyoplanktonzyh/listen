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
}
