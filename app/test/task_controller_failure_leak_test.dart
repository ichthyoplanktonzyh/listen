import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/coach_dashboard_controller.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/hunting_session_controller.dart';
import 'package:llplayer_next/controllers/reading_diff_controller.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/controllers/review_controller.dart';
import 'package:llplayer_next/controllers/speaking_task_controller.dart';
import 'package:llplayer_next/controllers/writing_task_controller.dart';
import 'package:llplayer_next/models/semantic_task.dart';
import 'package:llplayer_next/services/api_service.dart';

/// The task controllers' `state.error`, which panels render verbatim.
///
/// These were the worst of the ~130 sites: most of them assigned
/// `error: '$error'` — no sentence at all, just the exception — so a learner
/// whose sidecar rejected a request read a raw `HttpException`, complete with
/// error code, `correlation_id`, loopback port and internal route, inside the
/// studio's error notice.
///
/// Every case drives a *real* failure through the *real* transport, served
/// from `127.0.0.1:62645` so the exception's own `toString` appends the
/// sidecar URI exactly as it did in the field. Asserting against a hand-built
/// state would prove nothing: the leak lived in the exception's `toString`,
/// not in the widget.
void main() {
  /// The body the field actually reported, verbatim.
  const envelope =
      '{"code":"validation_error","message":"recording metadata must not be '
      'empty","correlation_id":"api-853","retryable":false}';

  const leaks = [
    'HttpException',
    'Exception',
    'correlation_id',
    'api-853',
    '127.0.0.1',
    '62645',
    'validation_error',
    'recording metadata must not be empty',
    'uri =',
    'retryable',
    '/v1/',
  ];

  /// A core that rejects every request with the field's own envelope.
  LocalApi failingApi() => LocalApi.withTransport(
    baseUrl: 'http://127.0.0.1:62645',
    token: 'token',
    transport: (method, path, body) async => (statusCode: 500, body: envelope),
  );

  void expectNamedState(String? error, String expected) {
    expect(error, expected);
    for (final leak in leaks) {
      expect(
        error,
        isNot(contains(leak)),
        reason:
            '"$leak" is transport detail; a task studio notice is not a place '
            'to print it.',
      );
    }
  }

  const readingSource = ReadingTaskSource(
    anchorCueId: 'cue-1',
    mediaId: 'media-1',
    trackId: 'track-1',
    startMs: 1000,
    endMs: 9000,
    sourceLanguage: 'en',
    responseLanguage: 'zh',
    transcriptSnapshot: 'A quake struck Mindanao on Monday morning.',
  );
  const writingSource = WritingTaskSource(
    anchorCueId: 'cue-1',
    mediaId: 'media-1',
    trackId: 'track-1',
    startMs: 1000,
    endMs: 9000,
    sourceLanguage: 'en',
    responseLanguage: 'en',
    transcriptSnapshot: 'A storm delayed the ferry until Tuesday.',
  );
  const points = [
    RubricPointView(
      pointId: 'main-idea',
      importance: 'required',
      statement: 'Main idea',
    ),
  ];

  test('a reading task whose rubric lookup fails names the state', () async {
    // GET /v1/semantic/rubrics?… → 500.
    final controller = ReadingTaskController();
    addTearDown(controller.dispose);

    await controller.openTask(
      failingApi(),
      source: readingSource,
      templatePoints: points,
    );

    expectNamedState(
      controller.state.error,
      'This reading task could not be opened',
    );
    expect(controller.state.phase, 'idle');
  });

  test('a writing task that cannot be opened names the state', () async {
    final controller = WritingTaskController();
    addTearDown(controller.dispose);

    await controller.openTask(
      failingApi(),
      source: writingSource,
      kind: 'summary',
      promptSnapshot: 'Summarise the report.',
      fixedRubricPoints: points,
    );

    expectNamedState(
      controller.state.error,
      'This writing task could not be opened',
    );
  });

  test('a speaking task that cannot be opened names the state', () async {
    final controller = SpeakingTaskController();
    addTearDown(controller.dispose);

    await controller.openTask(
      failingApi(),
      source: const SpeakingTaskSource(
        anchorCueId: 'cue-1',
        mediaId: 'media-1',
        trackId: 'track-1',
        startMs: 1000,
        endMs: 9000,
        language: 'en',
        transcriptSnapshot: 'A storm delayed the ferry until Tuesday.',
      ),
      fixedRubricPoints: points,
    );

    expectNamedState(
      controller.state.error,
      'This speaking task could not be opened',
    );
  });

  test('a review queue that cannot be loaded names the state', () async {
    // GET /v1/review/items?limit=20 → 500.
    final controller = ReviewController();
    addTearDown(controller.dispose);

    await controller.load(failingApi());

    expectNamedState(controller.state.error, 'Could not load review queue');
  });

  test('a coach view that cannot be loaded names the state', () async {
    final controller = CoachDashboardController();
    addTearDown(controller.dispose);

    await controller.load(failingApi());

    expectNamedState(
      controller.state.error,
      'Your coach view could not be loaded',
    );
  });

  test('a hunting list that cannot be loaded names the state', () async {
    final controller = HuntingController();
    addTearDown(controller.dispose);

    await controller.load(failingApi());

    expectNamedState(controller.state.error, 'Could not load hunting list');
  });

  test('hunting targets that cannot be located name the state', () async {
    final controller = HuntingSessionController();
    addTearDown(controller.dispose);

    await controller.start(
      api: failingApi(),
      sessionId: 'session-1',
      mediaId: 'media-1',
    );

    expectNamedState(
      controller.state.error,
      'Could not locate hunting targets',
    );
  });

  test(
    'an extensive-listening session that cannot start names the state',
    () async {
      final controller = ExtensiveListeningController();
      addTearDown(controller.dispose);

      await controller.startSession(
        api: failingApi(),
        mediaId: 'media-1',
        trackId: 'track-1',
      );

      expectNamedState(
        controller.state.error,
        'Could not start extensive listening',
      );
    },
  );

  test('a comparison that cannot be built names the state', () async {
    final controller = ReadingDiffController();
    addTearDown(controller.dispose);

    await controller.loadDiff(failingApi(), readingSource);

    expectNamedState(
      controller.state.error,
      'This comparison could not be built',
    );
  });
}
