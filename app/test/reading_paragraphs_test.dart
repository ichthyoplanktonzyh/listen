import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/reading.dart';
import 'package:llplayer_next/models/timeline.dart';

Cue _cue(
  int index,
  String text, {
  required int startMs,
  required int endMs,
  int? words,
}) {
  final wordCount =
      words ?? text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  return Cue(
    id: 'cue-$index',
    index: index,
    start: Duration(milliseconds: startMs),
    end: Duration(milliseconds: endMs),
    text: text,
    tokens: List.generate(
      wordCount,
      (i) =>
          SubtitleToken(index: i, kind: 'word', text: 'w$i', normalized: 'w$i'),
    ),
  );
}

void main() {
  group('sentence assembly', () {
    test('merges gapless cues until terminal punctuation', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, "I'm here with your news", startMs: 0, endMs: 1000),
        _cue(1, 'for June 9th.', startMs: 1000, endMs: 2000),
        _cue(2, 'On with the show.', startMs: 2000, endMs: 3000),
      ]);
      expect(paragraphs, hasLength(1));
      final sentences = paragraphs.single.sentences;
      expect(sentences, hasLength(2));
      expect(sentences.first.text, "I'm here with your news for June 9th.");
      expect(sentences.first.cues.map((c) => c.id), ['cue-0', 'cue-1']);
    });

    test('closing quote after terminal mark still ends the sentence', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, 'She said "stop."', startMs: 0, endMs: 1000),
        _cue(1, 'Then she left.', startMs: 1000, endMs: 2000),
      ]);
      expect(paragraphs.single.sentences, hasLength(2));
    });

    test('a large gap breaks a sentence without punctuation', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, 'never gonna give you up', startMs: 0, endMs: 1000),
        _cue(1, 'never gonna let you down', startMs: 4000, endMs: 5000),
      ]);
      final sentences = paragraphs
          .expand((paragraph) => paragraph.sentences)
          .toList();
      expect(sentences, hasLength(2));
    });

    test('♪-terminated lyric lines are sentences, not non-speech', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, "♪ We're no strangers to love ♪", startMs: 0, endMs: 1000),
        _cue(1, '♪ You know the rules ♪', startMs: 1200, endMs: 2200),
      ]);
      expect(paragraphs, hasLength(1));
      expect(paragraphs.single.nonSpeech, isFalse);
      expect(paragraphs.single.sentences, hasLength(2));
    });

    test('pure music markers stay non-speech separators', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, '[♪♪♪]', startMs: 0, endMs: 1000, words: 0),
        _cue(1, 'Welcome back.', startMs: 1000, endMs: 2000),
      ]);
      expect(paragraphs, hasLength(2));
      expect(paragraphs.first.nonSpeech, isTrue);
    });

    test('runaway cap forces a break in punctuation-less stretches', () {
      final cues = List.generate(
        30,
        (i) => _cue(i, 'la la la', startMs: i * 1000, endMs: (i + 1) * 1000),
      );
      final sentences = deriveReadingParagraphs(
        cues,
      ).expand((paragraph) => paragraph.sentences).toList();
      expect(sentences.length, greaterThan(1));
      for (final sentence in sentences) {
        expect(sentence.cues.length, lessThanOrEqualTo(12));
      }
    });
  });

  group('paragraph assembly', () {
    test('speaker turn dash starts a new sentence and paragraph', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, 'What do you think about the ban?', startMs: 0, endMs: 1000),
        _cue(1, "- It's honestly been great.", startMs: 1000, endMs: 2000),
        _cue(2, '- I miss my phone.', startMs: 2000, endMs: 3000),
      ]);
      expect(paragraphs, hasLength(3));
      expect(paragraphs[1].sentences.single.speakerTurn, isTrue);
    });

    test('soft cap closes a paragraph at the next sentence boundary', () {
      final cues = <Cue>[];
      for (var i = 0; i < 8; i++) {
        cues.add(
          _cue(
            i,
            'this sentence carries exactly ten words of content today ok.',
            startMs: i * 1000,
            endMs: (i + 1) * 1000,
            words: 10,
          ),
        );
      }
      final paragraphs = deriveReadingParagraphs(cues);
      expect(paragraphs.length, greaterThan(1));
      // 45-word target with 10-word sentences → paragraphs of 5 sentences.
      expect(paragraphs.first.sentences, hasLength(5));
    });

    test('gap before a sentence starts a new paragraph', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, 'First thought.', startMs: 0, endMs: 1000),
        _cue(1, 'Second thought.', startMs: 2500, endMs: 3500),
      ]);
      expect(paragraphs, hasLength(2));
    });

    test('non-speech markers become separator paragraphs', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, '(upbeat music)', startMs: 0, endMs: 1000),
        _cue(1, 'Welcome to the show.', startMs: 1000, endMs: 2000),
        _cue(2, '[applause]', startMs: 2000, endMs: 3000),
      ]);
      expect(paragraphs, hasLength(3));
      expect(paragraphs[0].nonSpeech, isTrue);
      expect(paragraphs[1].nonSpeech, isFalse);
      expect(paragraphs[2].nonSpeech, isTrue);
    });

    test('anchor cue id is the first cue of the paragraph', () {
      final paragraphs = deriveReadingParagraphs([
        _cue(0, 'Hello there.', startMs: 0, endMs: 1000),
        _cue(1, 'Another paragraph.', startMs: 3000, endMs: 4000),
      ]);
      expect(paragraphs[0].anchorCueId, 'cue-0');
      expect(paragraphs[1].anchorCueId, 'cue-1');
    });

    test('empty and single-cue inputs', () {
      expect(deriveReadingParagraphs(const []), isEmpty);
      final single = deriveReadingParagraphs([
        _cue(0, 'Just one line.', startMs: 0, endMs: 1000),
      ]);
      expect(single, hasLength(1));
      expect(single.single.wordCount, 3);
    });
  });
}
