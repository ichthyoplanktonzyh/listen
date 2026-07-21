import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
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

  test('playback notices are flagged so health surfaces can skip them', () {
    final player = PlayerController();
    addTearDown(player.dispose);

    player.setStatus('Playing sample.mp4', playback: true);
    expect(player.statusIsPlayback, isTrue);
    expect(player.statusIsError, isFalse);

    // A later plain status must clear the flag, otherwise the home core tile
    // would keep hiding real messages after playback started.
    player.setStatus('Subtitle exported');
    expect(player.statusIsPlayback, isFalse);

    player.setStatus('Playback failed', error: true);
    expect(player.statusIsPlayback, isFalse);
    expect(player.statusIsError, isTrue);
  });

  test('store-backed controllers notify aggregate listeners', () {
    final player = PlayerController();
    var playerNotifications = 0;
    player.addListener(() => playerNotifications++);
    player.setStatus('probe');
    expect(player.status, 'probe');
    expect(playerNotifications, 1);
    player.dispose();

    final subtitle = SubtitleController()..setPrimaryTrack(track);
    var subtitleNotifications = 0;
    subtitle.addListener(() => subtitleNotifications++);
    subtitle.updatePosition(const Duration(milliseconds: 250));
    expect(subtitle.currentPrimaryCue, cue);
    expect(subtitleNotifications, 1);
    subtitle.dispose();

    final learning = LearningController();
    var learningNotifications = 0;
    learning.addListener(() => learningNotifications++);
    learning.selectSidePanel(1);
    expect(learning.sidePanel, 1);
    expect(learningNotifications, 1);
    learning.dispose();
  });

  test('position ticks bypass the aggregate notifier entirely', () {
    final player = PlayerController();
    var aggregateNotifications = 0;
    var positionNotifications = 0;
    player.addListener(() => aggregateNotifications++);
    player.positionListenable.addListener(() => positionNotifications++);

    // Simulate the 100ms polling loop: aggregate listeners (the merged
    // Listenable driving the whole Scaffold) must stay silent.
    for (var ms = 100; ms <= 1000; ms += 100) {
      player.setPosition(Duration(milliseconds: ms));
    }

    expect(player.position, const Duration(milliseconds: 1000));
    expect(positionNotifications, 10);
    expect(aggregateNotifications, 0);

    // A repeated identical position is de-duplicated by the notifier.
    player.setPosition(const Duration(milliseconds: 1000));
    expect(positionNotifications, 10);
    player.dispose();
  });

  test('word/chunk highlight cursors bypass the aggregate notifier', () {
    final controller = SubtitleController()
      ..setPrimaryTrack(track)
      ..setCurrentPrimaryCue(cue)
      ..setSpeechEnhancements(
        pronunciationBySentence: const {},
        pronunciationProviders: const [],
        timingsBySentence: const {
          'sentence-1': [
            WordTiming(
              sentenceId: 'sentence-1',
              tokenIndex: 0,
              text: 'Hello',
              start: Duration(milliseconds: 100),
              end: Duration(milliseconds: 300),
              source: 'asr',
              provider: 'test',
            ),
          ],
        },
      );

    var aggregateNotifications = 0;
    var wordNotifications = 0;
    controller.addListener(() => aggregateNotifications++);
    controller.currentWordTokenListenable.addListener(
      () => wordNotifications++,
    );

    controller.updateCurrentWord(
      const Duration(milliseconds: 200),
      enabled: true,
    );

    expect(controller.currentWordToken, 0);
    expect(wordNotifications, 1);
    expect(
      aggregateNotifications,
      0,
      reason: 'speech-rate cursors must not rebuild the merged tree',
    );
    controller.dispose();
  });

  test('subtitle controller clears tracks and follows local word timings', () {
    final controller = SubtitleController()
      ..setPrimaryTrack(track)
      ..setCurrentPrimaryCue(cue)
      ..setSpeechEnhancements(
        pronunciationBySentence: const {},
        pronunciationProviders: const [
          PronunciationProvider(
            id: 'cmudict',
            displayName: 'CMUdict',
            version: '1',
          ),
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
          'sentence-1': PhoneticAnalysis(
            providerId: 'test',
            modelRevision: 'v1',
            phoneSet: 'arpabet',
            detectedPhones: [
              DetectedPhone(
                symbol: 'HH',
                displayIpa: 'HH',
                phoneSet: 'arpabet',
                start: Duration(milliseconds: 100),
                end: Duration(milliseconds: 200),
                confidence: 0.5,
                tokenIndex: 0,
                provider: 'test',
                modelRevision: 'v1',
              ),
            ],
          ),
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
    expect(controller.pronunciationProviders.single.id, 'cmudict');
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

  test(
    'subtitle controller keeps current word through short ASR display gaps',
    () {
      final controller = SubtitleController()
        ..setPrimaryTrack(track)
        ..setCurrentPrimaryCue(cue)
        ..setSpeechEnhancements(
          pronunciationBySentence: const {},
          pronunciationProviders: const [],
          timingsBySentence: const {
            'sentence-1': [
              WordTiming(
                sentenceId: 'sentence-1',
                tokenIndex: 0,
                start: Duration(milliseconds: 100),
                end: Duration(milliseconds: 300),
                source: 'asr_reported',
                provider: 'whisper.cpp',
              ),
              WordTiming(
                sentenceId: 'sentence-1',
                tokenIndex: 2,
                start: Duration(milliseconds: 450),
                end: Duration(milliseconds: 650),
                source: 'asr_reported',
                provider: 'whisper.cpp',
              ),
            ],
          },
        );

      controller.updateCurrentWord(
        const Duration(milliseconds: 350),
        enabled: true,
      );
      expect(controller.currentWordToken, 0);
      controller.updateCurrentWord(
        const Duration(milliseconds: 450),
        enabled: true,
      );
      expect(controller.currentWordToken, 2);

      controller.dispose();
    },
  );

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
      ..selectWord(_lexicalDetails);

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
        activePhoneTimelineId: null,
        activeChunkTimelineId: null,
        rhythmFrames: [],
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
        ..setTimelineResource(
          summaries: summaries,
          phoneSummaries: const [],
          chunkSummaries: const [],
          document: document,
        )
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
      ..selectWord(_lexicalDetails)
      ..setSelectedPronunciation(
        const WordPronunciation(
          tokenIndex: 0,
          text: 'Hello',
          normalized: 'hello',
        ),
      )
      ..setDiagnosis(const Diagnosis());

    controller.clearSelection();
    controller.setDiagnosis(null);

    expect(controller.selectedLexicalDetails, isNull);
    expect(controller.selectedPronunciation, isNull);
    expect(controller.diagnosis, isNull);
  });
}

const _lexicalDetails = LexicalEntryDetails(
  entry: LexicalEntry(
    id: 'lexical-1',
    normalizedForm: 'hello',
    displayForm: 'Hello',
    kind: 'word',
    language: 'en',
  ),
);
