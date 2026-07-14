// Reading-view read model: derives paragraph structure from a subtitle
// track's production sentences (cues). Derived projection only — paragraph
// grouping is never persisted as authority; cue identity stays the anchor
// for playback mapping and reading positions (Phase 3.13 PLAN v2 decision 2).

import 'timeline.dart';

/// Tunable inputs for paragraph derivation. Defaults were calibrated on two
/// real content classes (Slice 0 spike): whisper-generated news transcripts
/// are ~99% gapless so punctuation and size carry the structure, while
/// human-authored subtitles have small gaps everywhere and sparse
/// punctuation, so gap breaks and the runaway cap carry it.
class ReadingDerivationConfig {
  const ReadingDerivationConfig({
    this.sentenceGapBreakMs = 2000,
    this.paragraphGapBreakMs = 1200,
    this.targetParagraphWords = 45,
    this.maxSentenceCues = 12,
  });

  /// A silence this long ends the current sentence even without punctuation.
  final int sentenceGapBreakMs;

  /// A silence this long before a sentence starts a new paragraph.
  final int paragraphGapBreakMs;

  /// Soft cap: once a paragraph has at least this many words it closes at
  /// the next sentence boundary.
  final int targetParagraphWords;

  /// Runaway guard for punctuation-less stretches (songs, raw ASR).
  final int maxSentenceCues;
}

/// One displayed sentence: consecutive cues merged up to a terminal
/// punctuation, speaker turn, large gap, or the runaway cap.
class ReadingSentence {
  const ReadingSentence({
    required this.cues,
    required this.nonSpeech,
    required this.speakerTurn,
  });

  final List<Cue> cues;

  /// True when this is a bracketed stage direction / music marker, kept as a
  /// separator rather than reading content.
  final bool nonSpeech;

  /// True when the sentence opens with a speaker-turn dash (`- `).
  final bool speakerTurn;

  Duration get start => cues.first.start;
  Duration get end => cues.last.end;
  String get text =>
      cues.map((cue) => cue.text.trim()).join(' ').trim();
  int get wordCount => cues.fold(
    0,
    (sum, cue) =>
        sum + cue.tokens.where((token) => token.kind == 'word').length,
  );
}

/// One reading paragraph. Identity is the first cue id (`anchorCueId`):
/// stable across re-derivation and directly mappable back to playback.
class ReadingParagraph {
  const ReadingParagraph({required this.sentences, required this.nonSpeech});

  final List<ReadingSentence> sentences;
  final bool nonSpeech;

  String get anchorCueId => sentences.first.cues.first.id;
  Duration get start => sentences.first.start;
  Duration get end => sentences.last.end;
  int get wordCount =>
      sentences.fold(0, (sum, sentence) => sum + sentence.wordCount);
}

// ♪ closes a lyric line: human-authored song subtitles end each line with it
// and rarely carry sentence punctuation.
const _terminalPunctuation = {'.', '!', '?', '…', '。', '！', '？', '♪'};
// Trailing characters that may close a sentence after its terminal mark.
const _closingTrailers = {'"', '”', '’', "'", ')', ']', '）', '】', '」', '』'};

bool _endsSentence(String text) {
  final trimmed = text.trimRight();
  if (trimmed.isEmpty) return false;
  var index = trimmed.length - 1;
  while (index >= 0 && _closingTrailers.contains(trimmed[index])) {
    index--;
  }
  return index >= 0 && _terminalPunctuation.contains(trimmed[index]);
}

bool _startsSpeakerTurn(String text) {
  final trimmed = text.trimLeft();
  return trimmed.startsWith('- ') ||
      trimmed.startsWith('– ') ||
      trimmed.startsWith('— ');
}

/// A cue whose entire text is bracketed is a stage direction or sound
/// marker, not reading content. ♪-wrapped cues are lyrics — real reading
/// content — unless they carry no words at all (pure music markers).
bool isNonSpeechCue(Cue cue) {
  final trimmed = cue.text.trim();
  if (trimmed.isEmpty) return true;
  const pairs = {'(': ')', '[': ']', '（': '）', '【': '】'};
  final close = pairs[trimmed[0]];
  if (close != null && trimmed.endsWith(close)) return true;
  return !cue.tokens.any((token) => token.kind == 'word');
}

List<ReadingSentence> _deriveSentences(
  List<Cue> cues,
  ReadingDerivationConfig config,
) {
  final sentences = <ReadingSentence>[];
  var current = <Cue>[];

  void flush() {
    if (current.isEmpty) return;
    sentences.add(
      ReadingSentence(
        cues: List.unmodifiable(current),
        nonSpeech: false,
        speakerTurn: _startsSpeakerTurn(current.first.text),
      ),
    );
    current = <Cue>[];
  }

  for (final cue in cues) {
    if (isNonSpeechCue(cue)) {
      flush();
      sentences.add(
        ReadingSentence(
          cues: List.unmodifiable([cue]),
          nonSpeech: true,
          speakerTurn: false,
        ),
      );
      continue;
    }
    if (current.isNotEmpty) {
      final gapMs =
          cue.start.inMilliseconds - current.last.end.inMilliseconds;
      if (gapMs >= config.sentenceGapBreakMs || _startsSpeakerTurn(cue.text)) {
        flush();
      }
    }
    current.add(cue);
    if (_endsSentence(cue.text) || current.length >= config.maxSentenceCues) {
      flush();
    }
  }
  flush();
  return sentences;
}

/// A paragraph flattened into one synthetic cue so the existing token-span
/// renderer can lay it out as flowing text. Word taps map back to the real
/// cue via [tokenOrigins] — the synthetic cue never leaks into learning
/// writes.
class ParagraphComposite {
  const ParagraphComposite({required this.cue, required this.tokenOrigins});

  /// Synthetic cue: id is the paragraph anchor cue id, tokens re-indexed
  /// across all member cues.
  final Cue cue;

  /// Synthetic token index → (original cue, original token).
  final Map<int, (Cue, SubtitleToken)> tokenOrigins;
}

/// Flattens a paragraph's cues into a single synthetic cue for flowing-text
/// rendering. A single space token is inserted between cues so words from
/// adjacent cues never fuse.
ParagraphComposite composeParagraphCue(ReadingParagraph paragraph) {
  final tokens = <SubtitleToken>[];
  final origins = <int, (Cue, SubtitleToken)>{};
  final text = StringBuffer();
  for (final sentence in paragraph.sentences) {
    for (final cue in sentence.cues) {
      if (tokens.isNotEmpty) {
        tokens.add(
          SubtitleToken(
            index: tokens.length,
            kind: 'whitespace',
            text: ' ',
            normalized: null,
          ),
        );
        text.write(' ');
      }
      for (final token in cue.tokens) {
        final synthetic = SubtitleToken(
          index: tokens.length,
          kind: token.kind,
          text: token.text,
          normalized: token.normalized,
        );
        origins[synthetic.index] = (cue, token);
        tokens.add(synthetic);
      }
      text.write(cue.text.trim());
    }
  }
  final first = paragraph.sentences.first.cues.first;
  return ParagraphComposite(
    cue: Cue(
      id: first.id,
      index: first.index,
      start: paragraph.start,
      end: paragraph.end,
      text: text.toString(),
      tokens: List.unmodifiable(tokens),
    ),
    tokenOrigins: origins,
  );
}

/// Pure derivation from production cues to reading paragraphs. Non-speech
/// markers become their own single-sentence paragraphs so the reading view
/// can render them as separators (or skip them) without losing timeline
/// coverage.
List<ReadingParagraph> deriveReadingParagraphs(
  List<Cue> cues, [
  ReadingDerivationConfig config = const ReadingDerivationConfig(),
]) {
  final paragraphs = <ReadingParagraph>[];
  var current = <ReadingSentence>[];
  var currentWords = 0;

  void flush() {
    if (current.isEmpty) return;
    paragraphs.add(
      ReadingParagraph(sentences: List.unmodifiable(current), nonSpeech: false),
    );
    current = <ReadingSentence>[];
    currentWords = 0;
  }

  for (final sentence in _deriveSentences(cues, config)) {
    if (sentence.nonSpeech) {
      flush();
      paragraphs.add(
        ReadingParagraph(
          sentences: List.unmodifiable([sentence]),
          nonSpeech: true,
        ),
      );
      continue;
    }
    if (current.isNotEmpty) {
      final gapMs = sentence.start.inMilliseconds -
          current.last.end.inMilliseconds;
      if (sentence.speakerTurn ||
          gapMs >= config.paragraphGapBreakMs ||
          currentWords >= config.targetParagraphWords) {
        flush();
      }
    }
    current.add(sentence);
    currentWords += sentence.wordCount;
  }
  flush();
  return paragraphs;
}
