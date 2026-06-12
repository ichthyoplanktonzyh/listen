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
      );

    controller.updateCurrentWord(
      const Duration(milliseconds: 200),
      enabled: true,
    );
    expect(controller.currentWordToken, 0);
    controller.updateCurrentWord(
      const Duration(milliseconds: 300),
      enabled: true,
    );
    expect(controller.currentWordToken, isNull);
    expect(controller.pronunciationProviders.single['id'], 'cmudict');

    controller.clearSpeechEnhancements();
    expect(controller.pronunciationProviders, isEmpty);

    controller.setPrimaryTrack(null);
    controller.setCurrentPrimaryCue(null);
    expect(controller.primaryTrack, isNull);
    expect(controller.currentPrimaryCue, isNull);
  });

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
