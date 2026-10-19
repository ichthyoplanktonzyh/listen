import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/utils/media_title.dart';

void main() {
  group('displayMediaTitle', () {
    test('strips extension, provider id and trailing date together', () {
      expect(
        displayMediaTitle(
          'How a cell phone ban has transformed this Brooklyn middle '
          'school｜June 9, 2026 [9FFSOYLiFxc].mp4',
        ),
        'How a cell phone ban has transformed this Brooklyn middle school',
      );
    });

    test('accepts a full path and reads only the file name', () {
      expect(
        displayMediaTitle('/Users/me/Movies/Morning news [abcdefghijk].mp4'),
        'Morning news',
      );
    });

    test('leaves a name with neither id nor date alone', () {
      expect(displayMediaTitle('Morning news.mp4'), 'Morning news');
    });

    test('keeps a name that has nothing to strip at all', () {
      expect(displayMediaTitle('Morning news'), 'Morning news');
    });

    test('strips a chain of short extensions', () {
      expect(displayMediaTitle('lecture.en.vtt'), 'lecture');
      expect(displayMediaTitle('talk.zh-Hans.srt'), 'talk.zh-Hans');
    });

    test('keeps a long dotted segment, which is not a container extension', () {
      // Conservative on purpose: past five characters a dotted segment is far
      // more likely to be part of the name than a file type.
      expect(displayMediaTitle('lecture.generated.srt'), 'lecture.generated');
    });

    test('keeps a dotted word that is not an extension', () {
      expect(displayMediaTitle('Physics Ep. 12.mp4'), 'Physics Ep. 12');
    });

    test('strips a full-width separated CJK date', () {
      expect(displayMediaTitle('中文听力训练｜2026年6月9日 [9FFSOYLiFxc].mkv'), '中文听力训练');
    });

    test('strips written and numeric date tails without a separator', () {
      expect(
        displayMediaTitle('Weekly digest 2026-06-09.mp4'),
        'Weekly digest',
      );
      expect(
        displayMediaTitle('Weekly digest 9 June 2026.mp4'),
        'Weekly digest',
      );
      expect(
        displayMediaTitle('Weekly digest June 9th, 2026.mp4'),
        'Weekly digest',
      );
    });

    test('keeps a year that is part of the title', () {
      expect(
        displayMediaTitle('What changed in 2026.mp4'),
        'What changed in 2026',
      );
    });

    test('keeps an authored bracket that is not a provider id', () {
      expect(displayMediaTitle('Interview [Part 2].mp4'), 'Interview [Part 2]');
      expect(displayMediaTitle('Interview [HD].mp4'), 'Interview [HD]');
    });

    test('falls back to the raw name when cleaning would empty it', () {
      expect(displayMediaTitle('[9FFSOYLiFxc].mp4'), '[9FFSOYLiFxc].mp4');
    });

    test('keeps a name that is itself a date', () {
      // Nothing precedes it, so the date is the title rather than a suffix.
      expect(displayMediaTitle('2026-06-09.mp4'), '2026-06-09');
    });

    test('collapses the whitespace an id leaves behind', () {
      expect(
        displayMediaTitle('Morning news [9FFSOYLiFxc] extra.mp4'),
        'Morning news extra',
      );
    });

    test('handles an empty or separator-only name honestly', () {
      expect(displayMediaTitle(''), '');
      expect(displayMediaTitle('   '), '');
      expect(displayMediaTitle('|'), '|');
    });
  });
}
