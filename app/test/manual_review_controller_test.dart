import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/manual_review_controller.dart';
import 'package:llplayer_next/controllers/manual_review_flow_controller.dart';
import 'package:llplayer_next/models/timeline.dart';

void main() {
  const cue = Cue(
    id: 'sentence-1',
    index: 0,
    start: Duration(milliseconds: 1000),
    end: Duration(milliseconds: 3000),
    text: 'Hello world',
    tokens: [
      SubtitleToken(index: 0, kind: 'word', text: 'Hello', normalized: 'hello'),
      SubtitleToken(index: 1, kind: 'word', text: 'world', normalized: 'world'),
    ],
  );
  const track = SubtitleTrack(id: 'track-1', mediaId: 'media-1', cues: [cue]);
  const sourceWords = [
    WordTiming(
      sentenceId: 'sentence-1',
      tokenIndex: 0,
      text: 'Hello',
      start: Duration(milliseconds: 1100),
      end: Duration(milliseconds: 1600),
      source: 'forced_aligned',
      provider: 'mfa',
      providerVersion: '2.0',
      confidence: 0.9,
    ),
    WordTiming(
      sentenceId: 'sentence-1',
      tokenIndex: 1,
      text: 'world',
      start: Duration(milliseconds: 1700),
      end: Duration(milliseconds: 2400),
      source: 'forced_aligned',
      provider: 'mfa',
      providerVersion: '2.0',
      confidence: 0.8,
    ),
  ];
  const sourceTimeline = WordTimeline(
    id: 'timeline-source',
    trackId: 'track-1',
    mediaId: 'media-1',
    algorithmId: 'mfa',
    algorithmVersion: '2.0',
    configHash: 'hash',
    createdBy: 'algorithm',
    status: 'active',
    metricsJson: TimelineMetrics.empty(),
    words: sourceWords,
    createdAt: Duration.zero,
    updatedAt: Duration.zero,
  );

  test('marks edited words and emits absolute millisecond payload', () {
    final draft = ManualReviewDraft(
      track: track,
      sourceTimeline: sourceTimeline,
      words: sourceTimeline.words,
      initialCue: cue,
    );

    draft.updateWordBoundary(
      sentenceId: 'sentence-1',
      tokenIndex: 0,
      start: const Duration(milliseconds: 1123),
    );

    expect(draft.dirtyWords, contains(const WordKey('sentence-1', 0)));
    expect(draft.validateAll(), isEmpty);
    final payload = draft.createPayload();
    final words = payload['words'] as List<dynamic>;
    final edited = words.first as Map<String, dynamic>;
    final inherited = words.last as Map<String, dynamic>;

    expect(payload['parent_timeline_id'], 'timeline-source');
    expect(payload['created_by'], 'user');
    expect(payload['status'], 'active');
    expect(edited['start_ms'], 1123);
    expect(edited['end_ms'], 1600);
    expect(edited['timing_source'], 'user_adjusted');
    expect(edited['provider_id'], 'user');
    expect(inherited['start_ms'], 1700);
    expect(inherited['provider_id'], 'mfa');
  });

  test('validates overlap and can reset current sentence', () {
    final draft = ManualReviewDraft(
      track: track,
      sourceTimeline: sourceTimeline,
      words: sourceTimeline.words,
      initialCue: cue,
    );

    draft.updateWordBoundary(
      sentenceId: 'sentence-1',
      tokenIndex: 1,
      start: const Duration(milliseconds: 1500),
    );

    expect(draft.validateCurrentSentence().join(' '), contains('overlaps'));
    draft.resetCurrentSentence();
    expect(draft.validateCurrentSentence(), isEmpty);
    expect(draft.dirty, false);
  });

  test(
    'editor intents publish immutable snapshots without mutating old state',
    () {
      final viewModel = ManualReviewEditorViewModel(
        ManualReviewDraft(
          track: track,
          sourceTimeline: sourceTimeline,
          words: sourceTimeline.words,
          initialCue: cue,
        ),
      );
      final before = viewModel.state;

      viewModel.updateWordBoundary(
        sentenceId: 'sentence-1',
        tokenIndex: 0,
        start: const Duration(milliseconds: 1123),
      );
      final after = viewModel.state;

      expect(before.dirty, isFalse);
      expect(before.currentSentenceWords.first.start.inMilliseconds, 1100);
      expect(after.dirtyWords, contains(const WordKey('sentence-1', 0)));
      expect(after.currentSentenceWords.first.start.inMilliseconds, 1123);
      expect(() => after.currentSentenceWords.clear(), throwsUnsupportedError);
      expect(() => after.dirtyWords.clear(), throwsUnsupportedError);
      expect(() => after.allErrors.clear(), throwsUnsupportedError);
      expect(() => after.cues.clear(), throwsUnsupportedError);
      expect(() => after.currentCue.tokens.clear(), throwsUnsupportedError);
    },
  );
}
