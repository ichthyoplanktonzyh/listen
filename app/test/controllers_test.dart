import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';

void main() {
  const cue = Cue(
    id: 'sentence-1',
    index: 0,
    start: Duration(milliseconds: 100),
    end: Duration(milliseconds: 500),
    text: 'Hello',
    tokens: [
      SubtitleToken(index: 0, kind: 'word', text: 'Hello', normalized: 'hello'),
    ],
  );
  const track = SubtitleTrack(id: 'track-1', cues: [cue]);

  test('player controller clears nullable media and loop state', () {
    final controller = PlayerController()
      ..setMedia(
        id: 'media-1',
        path: '/tmp/media.mp4',
        title: 'Media',
        fingerprint: 'fingerprint',
      )
      ..setSourceLoop(Duration.zero, const Duration(seconds: 1));

    controller.clearMedia();
    controller.setSourceLoop(null, null);

    expect(controller.mediaId, isNull);
    expect(controller.mediaPath, isNull);
    expect(controller.sourceLoopStart, isNull);
    expect(controller.sourceLoopEnd, isNull);
  });

  test('player controller exposes strongly typed track lists from startup', () {
    final controller = PlayerController();
    const track = PlayerTrack(index: 0, id: 'audio-0');

    expect(controller.audioTracks, isA<List<PlayerTrack>>());
    expect(controller.embeddedSubtitleTracks, isA<List<PlayerTrack>>());

    controller.setAudioTracks(const [track]);
    controller.setEmbeddedSubtitleTracks(const [track]);

    expect(controller.audioTracks, const [track]);
    expect(controller.embeddedSubtitleTracks, const [track]);
  });

  test('subtitle controller clears tracks and follows local word timings', () {
    final controller = SubtitleController()
      ..setPrimaryTrack(track)
      ..setCurrentPrimaryCue(cue)
      ..setSpeechEnhancements(
        pronunciationBySentence: const {},
        pronunciationProviders: const [
          {'id': 'cmudict', 'version': '1'},
        ],
        timingsBySentence: const {
          'sentence-1': [
            WordTiming(
              sentenceId: 'sentence-1',
              tokenIndex: 0,
              start: Duration(milliseconds: 100),
              end: Duration(milliseconds: 300),
              source: 'estimated',
              provider: 'deterministic',
            ),
          ],
        },
        phoneticAnalysisBySentence: const {
          'sentence-1': {
            'detected_phones': [
              {
                'symbol': 'HH',
                'phone_set': 'arpabet',
                'start_ms': 100,
                'end_ms': 200,
                'confidence': 0.5,
                'token_index': 0,
                'provider_id': 'test',
                'model_revision': 'v1',
              },
            ],
          },
        },
        chunkPartitionsBySentence: const {
          'sentence-1': SentenceChunkPartition(
            sentenceId: 'sentence-1',
            chunks: [
              DisplayChunk(
                index: 0,
                tokenStart: 0,
                tokenEnd: 0,
                text: 'Hello',
                start: Duration(milliseconds: 100),
                end: Duration(milliseconds: 300),
              ),
            ],
            partitionerId: 'test',
            partitionerVersion: 'v1',
            timingQuality: 'estimated',
          ),
        },
      );

    controller.updateCurrentWord(
      const Duration(milliseconds: 200),
      enabled: true,
    );
    expect(controller.currentWordToken, 0);
    expect(controller.currentChunkIndex, 0);
    controller.updateCurrentWord(
      const Duration(milliseconds: 300),
      enabled: true,
    );
    expect(controller.currentWordToken, isNull);
    expect(controller.currentChunkIndex, isNull);
    expect(controller.pronunciationProviders.single['id'], 'cmudict');
    controller.updateCurrentDetectedPhone(
      const Duration(milliseconds: 150),
      enabled: true,
    );
    expect(controller.currentDetectedPhone?.symbol, 'HH');

    controller.clearSpeechEnhancements();
    expect(controller.pronunciationProviders, isEmpty);
    expect(controller.currentDetectedPhone, isNull);
    expect(controller.chunkPartitionsBySentence, isEmpty);

    controller.setPrimaryTrack(null);
    controller.setCurrentPrimaryCue(null);
    expect(controller.primaryTrack, isNull);
    expect(controller.currentPrimaryCue, isNull);
  });

  test('subtitle controller stores resource capabilities separately', () {
    final controller = SubtitleController()
      ..setSubtitleResources(const [track])
      ..setSubtitleResourceCapabilities(const {
        'track-1': SubtitleResourceCapabilities(
          sentenceTiming: true,
          wordTiming: true,
          chunkTiming: false,
          phoneTiming: false,
          sentenceCount: 1,
          wordTimingCount: 1,
        ),
      });

    expect(controller.subtitleResources.single.id, 'track-1');
    expect(
      controller.subtitleResourceCapabilities['track-1']?.wordTiming,
      true,
    );
    expect(
      controller.subtitleResourceCapabilities['track-1']?.chunkTiming,
      false,
    );

    controller.setSubtitleResources(const []);
    expect(
      controller.subtitleResourceCapabilities['track-1']?.wordTiming,
      true,
    );
  });

  test('selecting a word opens the word learning side panel', () {
    final controller = LearningController()
      ..selectSidePanel(1)
      ..selectWord(const {
        'profile': {'lemma': 'hello'},
      });

    expect(controller.sidePanel, 2);
  });

  test(
    'subtitle controller keeps timeline resource data when marking error',
    () {
      const document = LLTimelineDocument(
        schema: 'llplayer.timeline.v1',
        metadata: LLTimelineMetadata(
          createdAt: Duration(milliseconds: 1),
          generatorId: 'fixture-generator',
          generatorVersion: 'v1',
          generatorMode: 'production_engine',
          mediaTitle: 'Fixture',
          mediaFingerprint: 'fingerprint',
          humanReviewed: false,
          extra: {'track_source': 'lltimeline-json-v1'},
        ),
        activeWordTimelineId: 'timeline-active',
        artifacts: [
          LLTimelineArtifact(kind: 'alignment_diagnostics', payload: {}),
        ],
      );
      const summaries = [
        WordTimelineSummary(
          id: 'timeline-active',
          trackId: 'track-1',
          mediaId: 'media-1',
          algorithmId: 'whisperx',
          algorithmVersion: '1.0',
          createdBy: 'algorithm',
          status: 'active',
          lifecycleStage: 'algorithm_candidate',
          wordCount: 12,
          providerIds: ['whisperx'],
          timingSources: ['forced_aligned'],
          canActivate: true,
          canArchive: true,
          canDelete: true,
        ),
      ];
      final controller = SubtitleController()
        ..setTimelineResource(summaries: summaries, document: document)
        ..setTimelineResourceError('Timeline resource refresh warning');

      expect(controller.llTimelineDocument, same(document));
      expect(controller.wordTimelineSummaries, same(summaries));
      expect(
        controller.timelineResourceError,
        'Timeline resource refresh warning',
      );
    },
  );

  test('learning controller clears pronunciation and diagnosis', () {
    final controller = LearningController()
      ..selectWord(const {'profile': {}})
      ..setSelectedPronunciation(const {'variants': []})
      ..setDiagnosis(const {'hints': []});

    controller.clearSelection();
    controller.setDiagnosis(null);

    expect(controller.selectedWordDetails, isNull);
    expect(controller.selectedPronunciation, isNull);
    expect(controller.diagnosis, isNull);
  });
}
