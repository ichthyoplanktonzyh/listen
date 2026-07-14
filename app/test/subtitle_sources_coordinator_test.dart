import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/controllers/subtitle_sources_coordinator.dart';
import 'package:llplayer_next/models/task_status.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/api_service.dart';

const _cue = Cue(
  id: 'sentence-1',
  index: 0,
  start: Duration(milliseconds: 100),
  end: Duration(milliseconds: 500),
  text: 'Hello',
  tokens: [
    SubtitleToken(index: 0, kind: 'word', text: 'Hello', normalized: 'hello'),
  ],
);

const _track = SubtitleTrack(id: 'track-1', cues: [_cue]);

LocalApi _fakeApi(
  ({int statusCode, String body}) Function(String, String, String?) handler,
) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async => handler(method, path, body),
);

({
  SubtitleSourcesCoordinator coordinator,
  PlayerController player,
  SubtitleController subtitle,
  List<String> snackBars,
  List<UserTaskStatus> taskStatuses,
  List<String> openedMedia,
  List<String> openedSubtitles,
})
_wire(LocalApi? Function() getApi) {
  final player = PlayerController();
  final subtitle = SubtitleController();
  final settings = SettingsController();
  final snackBars = <String>[];
  final taskStatuses = <UserTaskStatus>[];
  final openedMedia = <String>[];
  final openedSubtitles = <String>[];
  final coordinator = SubtitleSourcesCoordinator(
    player: player,
    subtitle: subtitle,
    settings: settings,
  )..bind(
    getApi: getApi,
    isMounted: () => true,
    showSnackBar: snackBars.add,
    setTaskStatus: taskStatuses.add,
    openMediaPath: (path) async => openedMedia.add(path),
    openSubtitlePath: (path, {required secondary}) async =>
        openedSubtitles.add('$path secondary=$secondary'),
  );
  return (
    coordinator: coordinator,
    player: player,
    subtitle: subtitle,
    snackBars: snackBars,
    taskStatuses: taskStatuses,
    openedMedia: openedMedia,
    openedSubtitles: openedSubtitles,
  );
}

void main() {
  test('isMediaPath and isSubtitlePath classify by extension', () {
    final w = _wire(() => null);

    expect(w.coordinator.isMediaPath('/a/movie.MKV'), isTrue);
    expect(w.coordinator.isMediaPath('/a/audio.flac'), isTrue);
    expect(w.coordinator.isMediaPath('/a/subs.srt'), isFalse);
    expect(w.coordinator.isSubtitlePath('/a/subs.srt'), isTrue);
    expect(w.coordinator.isSubtitlePath('/a/subs.VTT'), isTrue);
    expect(w.coordinator.isSubtitlePath('/a/movie.mp4'), isFalse);
  });

  test('handleDrop opens the first media and reports unsupported', () async {
    final w = _wire(() => null);

    await w.coordinator.handleDrop(['/a/movie.mp4', '/b/other.mkv']);
    expect(w.openedMedia, ['/a/movie.mp4']);

    await w.coordinator.handleDrop(['/a/readme.pdf']);
    expect(w.player.status, 'Unsupported dropped file type');
  });

  test('handleDrop guards subtitles dropped before media', () async {
    final w = _wire(() => null);

    await w.coordinator.handleDrop(['/a/subs.srt']);

    expect(w.player.status, 'Drop or open media before subtitles');
    expect(w.openedSubtitles, isEmpty);
  });

  test('handleDrop routes a subtitle once media is loaded', () async {
    final api = _fakeApi((method, path, body) => (statusCode: 200, body: '{}'));
    final w = _wire(() => api);
    w.player.setMedia(
      id: 'media-1',
      path: '/a/movie.mp4',
      title: 'Movie',
      fingerprint: 'fp',
    );

    await w.coordinator.handleDrop(['/a/subs.srt']);

    expect(w.openedSubtitles, ['/a/subs.srt secondary=false']);
  });

  test('ensureCurrentPronunciation caches the current sentence', () async {
    final api = _fakeApi((method, path, body) {
      if (method == 'POST' && path == '/v1/pronunciation/analyze-sentence') {
        return (
          statusCode: 200,
          body: jsonEncode({
            'sentence_id': 'sentence-1',
            'display_ipa': 'həˈloʊ',
          }),
        );
      }
      throw StateError('unexpected $method $path');
    });
    final w = _wire(() => api);
    w.subtitle.setPrimaryTrack(_track);
    w.subtitle.updatePosition(const Duration(milliseconds: 250));

    await w.coordinator.ensureCurrentPronunciation(_cue);

    expect(
      w.subtitle.pronunciationBySentence['sentence-1']?.displayIpa,
      'həˈloʊ',
    );
  });

  test('ensureCurrentPronunciation skips an already cached cue', () async {
    var calls = 0;
    final api = _fakeApi((method, path, body) {
      calls++;
      return (
        statusCode: 200,
        body: jsonEncode({'sentence_id': 'sentence-1', 'display_ipa': 'x'}),
      );
    });
    final w = _wire(() => api);
    w.subtitle.setPrimaryTrack(_track);
    w.subtitle.updatePosition(const Duration(milliseconds: 250));

    await w.coordinator.ensureCurrentPronunciation(_cue);
    await w.coordinator.ensureCurrentPronunciation(_cue);

    expect(calls, 1);
  });

  test('analyzePhonetics guards a missing track with a snack bar', () async {
    final w = _wire(() => null);

    await w.coordinator.analyzePhonetics(wholeTrack: true);

    expect(w.snackBars, ['No media or subtitle loaded']);
    expect(w.taskStatuses, isEmpty);
  });

  test('analyzePhonetics dispatches a job for an installed model', () async {
    final w = _wire(
      () => _fakeApi((method, path, body) {
        if (method == 'GET' && path == '/v1/phonetic-analysis/models') {
          return (
            statusCode: 200,
            body: jsonEncode([
              {'id': 'model-1', 'state': 'installed'},
            ]),
          );
        }
        if (method == 'POST' && path == '/v1/phonetic-analysis/jobs') {
          return (statusCode: 200, body: jsonEncode({'status': 'queued'}));
        }
        throw StateError('unexpected $method $path');
      }),
    );
    w.subtitle.setPrimaryTrack(_track);

    await w.coordinator.analyzePhonetics(wholeTrack: true);

    expect(w.taskStatuses, hasLength(1));
    expect(w.taskStatuses.single.state, UserTaskState.working);
    expect(w.snackBars, ['Audio analysis queued']);
  });

  test('analyzePhonetics reports a failure task status', () async {
    final w = _wire(
      () => _fakeApi((method, path, body) {
        if (method == 'GET' && path == '/v1/phonetic-analysis/models') {
          return (statusCode: 200, body: jsonEncode([]));
        }
        throw StateError('unexpected $method $path');
      }),
    );
    w.subtitle.setPrimaryTrack(_track);

    await w.coordinator.analyzePhonetics(wholeTrack: true);

    expect(w.taskStatuses, hasLength(1));
    expect(w.taskStatuses.single.state, UserTaskState.error);
    expect(w.snackBars.single, startsWith('Audio analysis failed:'));
  });
}
