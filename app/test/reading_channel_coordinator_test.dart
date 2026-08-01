import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/reading_channel_coordinator.dart';
import 'package:llplayer_next/controllers/reading_controller.dart';
import 'package:llplayer_next/controllers/reading_diff_controller.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/data/repositories/reading_task_repository.dart';
import 'package:llplayer_next/data/repositories/reading_session_repository.dart';
import 'package:llplayer_next/models/reading.dart';
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
        SubtitleToken(
          index: 0,
          kind: 'word',
          text: text.split(' ').first,
          normalized: text.split(' ').first.toLowerCase(),
        ),
      ],
    );

SubtitleTrack _track() => SubtitleTrack(
  id: 'track-1',
  mediaId: 'media-1',
  language: 'en',
  cues: [
    _cue(0, 'First paragraph here.', startMs: 0, endMs: 2000),
    _cue(1, 'Second paragraph text.', startMs: 30000, endMs: 32000),
  ],
);

const _template = [
  RubricPointView(
    pointId: 'main-idea',
    importance: 'required',
    statement: 'main idea',
  ),
];

/// Records every request and answers from a prefix table, mirroring the
/// transport fake used by the reading-task controller tests.
class _FakeBackend {
  final requests = <(String, String, Map<String, dynamic>?)>[];
  final responses = <(String, String, Object?)>[];

  void on(String method, String pathPrefix, Object? response) {
    responses.add((method, pathPrefix, response));
  }

  LocalApi get api => LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'tok',
    transport: (method, path, body) async {
      requests.add((
        method,
        path,
        body == null ? null : jsonDecode(body) as Map<String, dynamic>,
      ));
      for (final (m, prefix, response) in responses) {
        if (m == method && path.startsWith(prefix)) {
          if (response is int) return (statusCode: response, body: '');
          return (statusCode: 200, body: jsonEncode(response));
        }
      }
      return (statusCode: 404, body: '{"code":"not_found"}');
    },
  );
}

class _Harness {
  _Harness({LocalApi? api}) {
    final taskRepository = LocalReadingTaskRepository(() => api);
    readingTask = ReadingTaskController(repository: taskRepository);
    readingDiff = ReadingDiffController(repository: taskRepository);
    readingSession = LocalReadingSessionRepository(() => api);
    subtitle.setPrimaryTrack(_track());
    coordinator.bind(
      isMounted: () => true,
      openSlicePlayback: (occurrence) async {
        slicePlaybacks.add(occurrence);
      },
      openWord: (token, cue) async {
        openedWords.add(token.text);
      },
    );
  }

  final subtitle = SubtitleController();
  final player = PlayerController();
  final reading = ReadingController();
  late final ReadingTaskController readingTask;
  late final ReadingDiffController readingDiff;
  late final ReadingSessionRepository readingSession;
  final settings = SettingsController();
  final slicePlaybacks = <Map<String, dynamic>>[];
  final openedWords = <String>[];

  late final coordinator = ReadingChannelCoordinator(
    adapter: DesktopPlayerAdapter(),
    player: player,
    subtitle: subtitle,
    settings: settings,
    reading: reading,
    readingTask: readingTask,
    readingDiff: readingDiff,
    repository: readingSession,
  );

  ReadingParagraph get firstParagraph => reading.state.paragraphs.first;

  /// Task/diff loads are fired-and-forgotten by design; let them settle so
  /// the fake transport never lands on a disposed controller.
  Future<void> dispose() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    coordinator.dispose();
    subtitle.dispose();
    player.dispose();
    reading.dispose();
    readingTask.dispose();
    readingDiff.dispose();
    settings.dispose();
  }
}

void main() {
  test('open restores the saved reading cursor', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/reading/positions/', {
        'track_id': 'track-1',
        'anchor_cue_id': 'cue-1',
        'paragraph_index': 1,
        'updated_at_ms': 0,
      });
    final harness = _Harness(api: backend.api);
    await harness.coordinator.open();
    expect(harness.coordinator.isOpen, isTrue);
    expect(harness.reading.state.anchorCueId, 'cue-1');
    await harness.dispose();
  });

  test('open without a primary track is a no-op', () async {
    final harness = _Harness();
    harness.subtitle.setPrimaryTrack(null);
    await harness.coordinator.open();
    expect(harness.coordinator.isOpen, isFalse);
    await harness.dispose();
  });

  test(
    'task studio opens on a paragraph and closes back to the reader',
    () async {
      final backend = _FakeBackend()
        ..on('GET', '/v1/reading/positions/', null)
        ..on('GET', '/v1/learner/profile', {'l1_language': 'zh'})
        ..on('GET', '/v1/semantic/rubrics/lookup', null);
      final harness = _Harness(api: backend.api);
      await harness.coordinator.open();
      await harness.coordinator.openTask(
        harness.firstParagraph,
        templatePoints: _template,
      );
      final source = harness.coordinator.taskStudioSource;
      expect(source, isNotNull);
      // L1 from the learner profile wins over the track language.
      expect(source!.responseLanguage, 'zh');
      expect(source.sourceLanguage, 'en');
      harness.coordinator.closeTaskStudio();
      expect(harness.coordinator.taskStudioSource, isNull);
      await harness.dispose();
    },
  );

  test('diff card keeps its paragraph and clears on close', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/reading/positions/', null)
      ..on('GET', '/v1/learner/profile', {'l1_language': 'zh'})
      ..on('GET', '/v1/semantic/rubrics/lookup', null);
    final harness = _Harness(api: backend.api);
    await harness.coordinator.open();
    await harness.coordinator.openDiff(harness.firstParagraph);
    expect(harness.coordinator.diffSource, isNotNull);
    expect(
      harness.coordinator.diffParagraph?.anchorCueId,
      harness.firstParagraph.anchorCueId,
    );
    harness.coordinator.closeDiff();
    expect(harness.coordinator.diffSource, isNull);
    expect(harness.coordinator.diffParagraph, isNull);
    await harness.dispose();
  });

  test(
    'listening check replays through the slice seam and counts plays',
    () async {
      final backend = _FakeBackend()
        ..on('GET', '/v1/reading/positions/', null)
        ..on('GET', '/v1/learner/profile', {'l1_language': 'zh'})
        ..on('GET', '/v1/semantic/rubrics/lookup', null);
      final harness = _Harness(api: backend.api);
      await harness.coordinator.open();
      final source = await harness.coordinator.taskSource(
        harness.firstParagraph,
      );
      harness.coordinator.openListeningCheck(
        source!,
        fallbackTemplatePoints: _template,
      );
      expect(harness.coordinator.listeningCheckSource, isNotNull);
      expect(harness.coordinator.listeningPlayCount, 0);
      harness.coordinator.playListeningCheckSegment();
      await Future<void>.delayed(Duration.zero);
      expect(harness.coordinator.listeningPlayCount, 1);
      expect(harness.slicePlaybacks.single['sentence_id'], source.anchorCueId);
      harness.coordinator.closeListeningCheck();
      expect(harness.coordinator.listeningCheckSource, isNull);
      await harness.dispose();
    },
  );

  test('close tears down every reading surface at once', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/reading/positions/', null)
      ..on('GET', '/v1/learner/profile', {'l1_language': 'zh'})
      ..on('GET', '/v1/semantic/rubrics/lookup', null);
    final harness = _Harness(api: backend.api);
    await harness.coordinator.open();
    await harness.coordinator.openTask(
      harness.firstParagraph,
      templatePoints: _template,
    );
    await harness.coordinator.openDiff(harness.firstParagraph);
    final source = await harness.coordinator.taskSource(harness.firstParagraph);
    harness.coordinator.openListeningCheck(
      source!,
      fallbackTemplatePoints: _template,
    );
    await harness.coordinator.openWord(
      harness.subtitle.primaryTrack!.cues.first.tokens.first,
      harness.subtitle.primaryTrack!.cues.first,
    );
    expect(harness.coordinator.wordInspectorOpen, isTrue);
    expect(harness.openedWords, isNotEmpty);

    await harness.coordinator.close();
    expect(harness.coordinator.isOpen, isFalse);
    expect(harness.coordinator.taskStudioSource, isNull);
    expect(harness.coordinator.diffSource, isNull);
    expect(harness.coordinator.listeningCheckSource, isNull);
    expect(harness.coordinator.wordInspectorOpen, isFalse);
    await harness.dispose();
  });

  test('playRange builds the occurrence off the primary cursor', () async {
    final harness = _Harness();
    await harness.coordinator.playRange(
      const Duration(milliseconds: 500),
      const Duration(milliseconds: 1500),
      'cue-0',
      'First paragraph here.',
    );
    final occurrence = harness.slicePlaybacks.single;
    expect(occurrence['track_id'], 'track-1');
    expect(occurrence['media_id'], 'media-1');
    expect(occurrence['sentence_id'], 'cue-0');
    expect(occurrence['start_ms_snapshot'], 500);
    expect(occurrence['end_ms_snapshot'], 1500);
    await harness.dispose();
  });

  test('cursor writes are debounced and de-duplicated', () async {
    final backend = _FakeBackend()
      ..on('GET', '/v1/reading/positions/', null)
      ..on('PUT', '/v1/reading/positions/', {
        'track_id': 'track-1',
        'anchor_cue_id': 'cue-1',
        'paragraph_index': 1,
        'updated_at_ms': 0,
      });
    final harness = _Harness(api: backend.api);
    await harness.coordinator.open();
    harness.reading.markPosition('cue-0');
    harness.reading.markPosition('cue-1');
    // Bursts collapse: only the resting anchor reaches the backend.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final writes = backend.requests
        .where((request) => request.$1 == 'PUT')
        .toList();
    expect(writes, hasLength(1));
    expect(writes.single.$3?['anchor_cue_id'], 'cue-1');

    // A second settle on the same anchor is not worth another round trip.
    await harness.coordinator.savePosition();
    expect(backend.requests.where((r) => r.$1 == 'PUT'), hasLength(1));
    await harness.dispose();
  });
}
