import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/writing_channel_coordinator.dart';
import 'package:llplayer_next/controllers/writing_task_controller.dart';
import 'package:llplayer_next/models/semantic_task.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/services/api_service.dart';

Cue _cue(int index, String text, {required int startMs, required int endMs}) =>
    Cue(
      id: 'cue-$index',
      index: index,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
      text: text,
      tokens: [
        for (final (position, word) in text.split(' ').indexed)
          SubtitleToken(
            index: position,
            kind: 'word',
            text: word,
            normalized: word.toLowerCase().replaceAll(RegExp('[^a-z]'), ''),
          ),
      ],
    );

SubtitleTrack _track() => SubtitleTrack(
  id: 'track-1',
  mediaId: 'media-1',
  language: 'en',
  cues: [
    _cue(0, 'First paragraph here.', startMs: 0, endMs: 2000),
    _cue(1, 'Still the first paragraph.', startMs: 2200, endMs: 4000),
    _cue(2, 'Second paragraph text.', startMs: 30000, endMs: 32000),
  ],
);

const _template = [
  RubricPointView(
    pointId: 'main-idea',
    importance: 'required',
    statement: 'main idea',
  ),
];

class _Harness {
  _Harness() {
    subtitle.setPrimaryTrack(_track());
    coordinator.bind(
      getApi: () => api,
      isMounted: () => true,
      openSlicePlayback: (occurrence) async {
        slicePlaybacks.add(occurrence);
      },
      closeOtherChannels: () async {
        otherChannelsClosed++;
      },
    );
  }

  final requests = <String>[];
  final slicePlaybacks = <Map<String, dynamic>>[];
  int otherChannelsClosed = 0;

  late final api = LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'tok',
    transport: (method, path, body) async {
      requests.add('$method $path');
      // Synthesis is unavailable in tests; the readback path must report it
      // rather than throw.
      if (path.startsWith('/v1/speech-synthesis')) {
        return (statusCode: 503, body: '');
      }
      return (statusCode: 404, body: '{"code":"not_found"}');
    },
  );

  final subtitle = SubtitleController();
  final player = PlayerController();
  final settings = SettingsController();
  final slicePlayer = SlicePlayerController();
  final auxiliaryAudio = AuxiliaryAudioController();
  final task = WritingTaskController();

  late final coordinator = WritingChannelCoordinator(
    adapter: DesktopPlayerAdapter(),
    recordingAdapter: DesktopPlayerAdapter(),
    player: player,
    subtitle: subtitle,
    settings: settings,
    slicePlayer: slicePlayer,
    auxiliaryAudio: auxiliaryAudio,
    task: task,
  );

  Future<void> open(String kind) => coordinator.openTask(
    kind,
    promptSnapshot: 'prompt',
    fixedRubricPoints: _template,
  );

  /// The task load is fired-and-forgotten by design; let it settle so the
  /// fake transport never lands on a disposed controller.
  Future<void> dispose() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    coordinator.dispose();
    subtitle.dispose();
    player.dispose();
    settings.dispose();
    slicePlayer.dispose();
    auxiliaryAudio.dispose();
    task.dispose();
  }
}

void main() {
  test('opening anchors on the paragraph under the playhead', () async {
    final harness = _Harness();
    harness.subtitle.setCurrentPrimaryCue(
      harness.subtitle.primaryTrack!.cues[2],
    );
    await harness.open(WritingTaskController.opinionKind);
    final source = harness.coordinator.studioSource;
    expect(source, isNotNull);
    expect(source!.anchorCueId, 'cue-2');
    expect(source.sourceLanguage, 'en');
    expect(harness.coordinator.kind, WritingTaskController.opinionKind);
    // The writing channel never tears down its neighbours itself.
    expect(harness.otherChannelsClosed, 1);
    await harness.dispose();
  });

  test('opening without a primary track is a no-op', () async {
    final harness = _Harness();
    harness.subtitle.setPrimaryTrack(null);
    await harness.open(WritingTaskController.summaryKind);
    expect(harness.coordinator.isOpen, isFalse);
    expect(harness.otherChannelsClosed, 0);
    await harness.dispose();
  });

  test('switching kinds resets the replay count', () async {
    final harness = _Harness();
    await harness.open(WritingTaskController.summaryKind);
    harness.coordinator.playSource();
    harness.coordinator.playSource();
    expect(harness.coordinator.playCount, 2);
    expect(harness.slicePlaybacks, hasLength(2));
    expect(
      harness.slicePlaybacks.first['sentence_id'],
      harness.coordinator.studioSource!.anchorCueId,
    );
    await harness.open(WritingTaskController.dictoglossKind);
    expect(harness.coordinator.kind, WritingTaskController.dictoglossKind);
    expect(harness.coordinator.playCount, 0);
    await harness.dispose();
  });

  test('close clears the studio source', () async {
    final harness = _Harness();
    await harness.open(WritingTaskController.summaryKind);
    expect(harness.coordinator.isOpen, isTrue);
    await harness.coordinator.close();
    expect(harness.coordinator.isOpen, isFalse);
    expect(harness.coordinator.studioSource, isNull);
    await harness.dispose();
  });

  test('readback reports whether synthesis was available', () async {
    final unavailable = _Harness();
    await unavailable.open(WritingTaskController.summaryKind);
    expect(await unavailable.coordinator.speakText('my summary'), isFalse);
    // Blank text never reaches the backend and is not reported as a failure.
    unavailable.requests.clear();
    expect(await unavailable.coordinator.speakText('   '), isTrue);
    expect(unavailable.requests, isEmpty);
    await unavailable.dispose();
  });
}
