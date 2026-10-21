import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/extensive_listening_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/hunting_session_controller.dart';
import 'package:llplayer_next/controllers/review_controller.dart';
import 'package:llplayer_next/data/repositories/review_repository.dart';
import 'package:llplayer_next/data/repositories/hunting_repository.dart';
import 'package:llplayer_next/data/repositories/listening_repository.dart';
import 'package:llplayer_next/models/named_failure.dart';
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
      '{"code":"validation_error","message":"listening request was '
      'rejected","correlation_id":"api-853","retryable":false}';

  const leaks = [
    'HttpException',
    'Exception',
    'correlation_id',
    'api-853',
    '127.0.0.1',
    '62645',
    'validation_error',
    'listening request was rejected',
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

  void expectNamedState(Object? error, String expected) {
    final message = error is NamedFailure ? error.messageKey : error as String?;
    expect(message, expected);
    for (final leak in leaks) {
      expect(
        message,
        isNot(contains(leak)),
        reason:
            '"$leak" is transport detail; a task studio notice is not a place '
            'to print it.',
      );
    }
  }

  test('a review queue that cannot be loaded names the state', () async {
    // GET /v1/review/items?limit=20 → 500.
    final controller = ReviewController(LocalReviewRepository(failingApi()));
    addTearDown(controller.dispose);

    await controller.load();

    expectNamedState(controller.state.error, 'Could not load review queue');
  });

  test('a hunting list that cannot be loaded names the state', () async {
    final api = failingApi();
    final controller = HuntingController(
      repository: LocalHuntingRepository(() => api),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expectNamedState(controller.state.error, 'huntingLoadFailed');
  });

  test('hunting targets that cannot be located name the state', () async {
    final api = failingApi();
    final controller = HuntingSessionController(
      repository: LocalHuntingRepository(() => api),
    );
    addTearDown(controller.dispose);

    await controller.start(sessionId: 'session-1', mediaId: 'media-1');

    expectNamedState(controller.state.error, 'huntingOccurrencesFailed');
  });

  test(
    'an extensive-listening session that cannot start names the state',
    () async {
      final api = failingApi();
      final controller = ExtensiveListeningController(
        repository: LocalListeningRepository(() => api),
      );
      addTearDown(controller.dispose);

      await controller.startSession(mediaId: 'media-1', trackId: 'track-1');

      expectNamedState(
        controller.state.error,
        'Could not start extensive listening',
      );
    },
  );
}
