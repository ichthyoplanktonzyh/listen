import '../models/timeline.dart';

const manualReviewProviderId = 'user';
const manualReviewProviderVersion = 'llplayernext-manual-review-v1';
const manualReviewAlgorithmId = 'manual-review';
const manualReviewAlgorithmVersion = 'llplayernext-phase-2.3';

class ManualReviewDraft {
  ManualReviewDraft({
    required this.track,
    required this.sourceTimeline,
    required List<WordTiming> words,
    required Cue initialCue,
    Set<WordKey>? dirtyWords,
  }) : _words = List<WordTiming>.from(words),
       currentCue = initialCue,
       dirtyWords = dirtyWords ?? <WordKey>{};

  final SubtitleTrack track;
  final WordTimeline sourceTimeline;
  final Set<WordKey> dirtyWords;
  Cue currentCue;
  final List<WordTiming> _words;

  List<WordTiming> get words => List.unmodifiable(_words);

  List<WordTiming> get currentSentenceWords {
    final values = _words
        .where((word) => word.sentenceId == currentCue.id)
        .toList();
    values.sortByTokenIndex();
    return values;
  }

  bool get dirty => dirtyWords.isNotEmpty;

  void selectCue(Cue cue) {
    currentCue = cue;
  }

  void resetCurrentSentence() {
    for (var index = 0; index < _words.length; index += 1) {
      final source = sourceTimeline.words.where(
        (word) =>
            word.sentenceId == currentCue.id &&
            word.tokenIndex == _words[index].tokenIndex,
      );
      if (source.isNotEmpty) _words[index] = source.first;
    }
    dirtyWords.removeWhere((key) => key.sentenceId == currentCue.id);
  }

  void updateWordBoundary({
    required String sentenceId,
    required int tokenIndex,
    Duration? start,
    Duration? end,
  }) {
    final index = _words.indexWhere(
      (word) => word.sentenceId == sentenceId && word.tokenIndex == tokenIndex,
    );
    if (index < 0) return;
    final current = _words[index];
    _words[index] = current.copyWith(
      start: start,
      end: end,
      source: 'user_adjusted',
      provider: manualReviewProviderId,
      providerVersion: manualReviewProviderVersion,
    );
    dirtyWords.add(WordKey(sentenceId, tokenIndex));
  }

  void stepWordBoundary({
    required String sentenceId,
    required int tokenIndex,
    required bool adjustStart,
    required int deltaMs,
  }) {
    final word = _words.firstWhere(
      (value) =>
          value.sentenceId == sentenceId && value.tokenIndex == tokenIndex,
    );
    updateWordBoundary(
      sentenceId: sentenceId,
      tokenIndex: tokenIndex,
      start: adjustStart
          ? Duration(milliseconds: word.start.inMilliseconds + deltaMs)
          : null,
      end: adjustStart
          ? null
          : Duration(milliseconds: word.end.inMilliseconds + deltaMs),
    );
  }

  List<String> validateCurrentSentence() =>
      validateSentence(currentCue, currentSentenceWords);

  List<String> validateAll() {
    final errors = <String>[];
    if (_words.isEmpty) errors.add('WordTimeline must contain words.');
    for (final cue in track.cues) {
      final sentenceWords =
          _words.where((word) => word.sentenceId == cue.id).toList()
            ..sortByTokenIndex();
      if (sentenceWords.isEmpty) continue;
      errors.addAll(validateSentence(cue, sentenceWords));
    }
    return errors;
  }

  List<String> validateSentence(Cue cue, List<WordTiming> words) {
    final errors = <String>[];
    final wordTokens = cue.tokens
        .where((token) => token.kind == 'word')
        .map((token) => token.index)
        .toSet();
    final byStart = List<WordTiming>.from(words)
      ..sort((a, b) {
        final start = a.start.compareTo(b.start);
        if (start != 0) return start;
        return a.tokenIndex.compareTo(b.tokenIndex);
      });
    for (final word in words) {
      if (!wordTokens.contains(word.tokenIndex)) {
        errors.add('${wordLabel(word, cue)} does not match a word token.');
      }
      if (word.start.inMilliseconds < cue.start.inMilliseconds ||
          word.end.inMilliseconds > cue.end.inMilliseconds) {
        errors.add('${wordLabel(word, cue)} is outside sentence boundaries.');
      }
      if (word.end <= word.start) {
        errors.add('${wordLabel(word, cue)} must end after it starts.');
      }
    }
    for (var index = 1; index < byStart.length; index += 1) {
      if (byStart[index - 1].end > byStart[index].start) {
        errors.add(
          '${wordLabel(byStart[index - 1], cue)} overlaps '
          '${wordLabel(byStart[index], cue)}.',
        );
      }
    }
    return errors;
  }

  Map<String, dynamic> createPayload() {
    final editedSentenceIds = dirtyWords.map((key) => key.sentenceId).toSet();
    return {
      'parent_timeline_id': sourceTimeline.id,
      'created_by': 'user',
      'status': 'active',
      'algorithm_id': manualReviewAlgorithmId,
      'algorithm_version': manualReviewAlgorithmVersion,
      'metrics_json': {
        'lifecycle': {'human_reviewed': true},
        'review': {
          'parent_timeline_id': sourceTimeline.id,
          'edited_word_count': dirtyWords.length,
          'reviewed_sentence_ids': editedSentenceIds.toList()..sort(),
        },
      },
      'words': _words.map((word) => word.toJson()).toList(growable: false),
    };
  }
}

class WordKey {
  const WordKey(this.sentenceId, this.tokenIndex);

  final String sentenceId;
  final int tokenIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WordKey &&
          other.sentenceId == sentenceId &&
          other.tokenIndex == tokenIndex;

  @override
  int get hashCode => Object.hash(sentenceId, tokenIndex);
}

String wordLabel(WordTiming word, Cue cue) {
  if (word.text.isNotEmpty) return word.text;
  final token = cue.tokens.where((value) => value.index == word.tokenIndex);
  if (token.isNotEmpty) return token.first.text;
  return '#${word.tokenIndex}';
}

extension on List<WordTiming> {
  void sortByTokenIndex() =>
      sort((a, b) => a.tokenIndex.compareTo(b.tokenIndex));
}
