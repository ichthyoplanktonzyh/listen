import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/review_due_controller.dart';
import 'package:llplayer_next/data/repositories/review_repository.dart';
import 'package:llplayer_next/models/review_deck.dart';

/// The shell's due count is the number the today pane draws, so this is where
/// "0 due" and "not loaded yet" have to stay different facts. A controller
/// that settled on zero on failure, on disconnect, or before its first read
/// would hand the pane a lie the pane has no way to detect.
ReviewDeckOverview _overview(int newCards, int dueCards) =>
    ReviewDeckOverview.fromJson({
      'channels': [
        {
          'channel': 'listening',
          'counts': {'new': newCards, 'learning': 0, 'due': dueCards},
        },
      ],
      'imported_decks': <Map<String, dynamic>>[],
      'limit_status': {
        'limits': {'new_cards': 20, 'reviews': 200},
        'new_completed': 0,
        'reviews_completed': 0,
        'new_limit_reached': false,
        'review_limit_reached': false,
      },
    });

class _Repository implements ReviewRepository {
  _Repository(this.responses);

  final List<Future<ReviewDeckOverview>> responses;
  var calls = 0;

  @override
  Future<ReviewDeckOverview> deckOverview() => responses[calls++];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  test('nothing is known before the first read', () {
    final controller = ReviewDueController(_Repository(const []));
    addTearDown(controller.dispose);

    expect(controller.state.status, ReviewDueStatus.unknown);
    expect(
      controller.state.count,
      isNull,
      reason: 'a count nobody reported must not exist, not even as zero',
    );
  });

  test('a loaded read carries the reported total', () async {
    final controller = ReviewDueController(
      _Repository([Future.value(_overview(3, 9))]),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state.status, ReviewDueStatus.loaded);
    expect(controller.state.count, 12);
  });

  test('a genuine zero is loaded, not unknown', () async {
    final controller = ReviewDueController(
      _Repository([Future.value(_overview(0, 0))]),
    );
    addTearDown(controller.dispose);

    await controller.load();

    // The pane draws this as "0", and it is allowed to: the backend said so.
    expect(controller.state.status, ReviewDueStatus.loaded);
    expect(controller.state.count, 0);
  });

  test('failure drops the count rather than degrading it to zero', () async {
    final controller = ReviewDueController(
      _Repository([Future.error(StateError('core is gone'))]),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state.status, ReviewDueStatus.failed);
    expect(controller.state.count, isNull);
  });

  test('reset clears a number from a previous session', () async {
    final controller = ReviewDueController(
      _Repository([Future.value(_overview(1, 1))]),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.state.count, 2);

    // The core disconnected: yesterday's number is not today's fact.
    controller.reset();
    expect(controller.state.status, ReviewDueStatus.unknown);
    expect(controller.state.count, isNull);
  });

  test('a read that lost its race cannot overwrite a newer one', () async {
    final slow = Completer<ReviewDeckOverview>();
    final controller = ReviewDueController(
      _Repository([slow.future, Future.value(_overview(0, 5))]),
    );
    addTearDown(controller.dispose);

    final first = controller.load();
    await controller.load();
    expect(controller.state.count, 5);

    slow.complete(_overview(0, 99));
    await first;

    expect(
      controller.state.count,
      5,
      reason: 'the stale read is dropped, not written over the current one',
    );
  });
}
