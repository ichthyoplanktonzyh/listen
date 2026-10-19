import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/core_session_controller.dart';
import 'package:llplayer_next/data/repositories/core_session_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/backend_event.dart';

void main() {
  test('connect publishes immutable languages and typed events', () async {
    final repository = _Repository(languages: const ['en', 'zh']);
    final controller = _controllerFor(repository);
    final received = <BackendEvent>[];
    final subscription = controller.events.listen(received.add);

    await controller.connect();
    await pumpEventQueue();
    repository.eventController.add({
      'event': 'service-started',
      'payload': const <String, dynamic>{},
    });
    await pumpEventQueue();

    expect(controller.state.status, CoreConnectionStatus.connected);
    expect(controller.state.availableLanguages, ['en', 'zh']);
    expect(
      () => controller.state.availableLanguages.add('ja'),
      throwsUnsupportedError,
    );
    expect(received.single, isA<ServiceStartedEvent>());

    await subscription.cancel();
    await controller.shutdown();
    controller.dispose();
  });

  test('failed connect can reconnect with a new generation', () async {
    final repository = _Repository(connectFailures: 1);
    final controller = _controllerFor(repository);

    await controller.connect();
    expect(controller.state.status, CoreConnectionStatus.failed);
    expect(controller.state.failure?.raw, contains('connect failed'));

    await controller.connect();
    expect(controller.state.status, CoreConnectionStatus.connected);
    expect(controller.state.connectionGeneration, 1);
    expect(repository.connectCalls, 2);

    await controller.shutdown();
    controller.dispose();
  });

  test(
    'event stream completion leaves connected state and stops ticks',
    () async {
      final repository = _Repository();
      var ticks = 0;
      final controller = _controllerFor(
        repository,
        progressInterval: const Duration(milliseconds: 5),
        onProgressTick: () => ticks++,
      );
      await controller.connect();
      await Future<void>.delayed(const Duration(milliseconds: 12));

      await repository.eventController.close();
      await pumpEventQueue();
      final ticksAtClose = ticks;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(controller.state.status, CoreConnectionStatus.disconnected);
      expect(ticks, ticksAtClose);
      await controller.shutdown();
      controller.dispose();
    },
  );

  test('periodic save and bookkeeping failures do not escape', () async {
    final repository = _Repository(saveError: StateError('disk'));
    final controller = _controllerFor(
      repository,
      progressInterval: const Duration(milliseconds: 5),
      onProgressTick: () => throw StateError('recent media'),
    );

    await controller.connect();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    expect(repository.saveCalls, greaterThan(0));
    expect(controller.state.status, CoreConnectionStatus.connected);
    await controller.shutdown();
    controller.dispose();
  });

  test('shutdown saves final progress before requesting stop', () async {
    final saveCompleter = Completer<void>();
    final repository = _Repository(saveCompleter: saveCompleter);
    final controller = _controllerFor(repository);
    await controller.connect();

    final shutdown = controller.shutdown();
    await pumpEventQueue();
    expect(repository.operations, ['save']);

    saveCompleter.complete();
    await shutdown;
    expect(repository.operations, ['save', 'stop']);
    controller.dispose();
  });

  test('shutdown timeout still requests stop after the deadline', () async {
    final repository = _Repository(saveCompleter: Completer<void>());
    final controller = _controllerFor(
      repository,
      finalSaveTimeout: const Duration(milliseconds: 5),
    );
    await controller.connect();

    await controller.shutdown();

    expect(repository.operations, ['save', 'stop']);
    controller.dispose();
  });

  test(
    'late connect completion after dispose closes the stale session',
    () async {
      final connectCompleter = Completer<void>();
      final repository = _Repository(connectCompleter: connectCompleter);
      final controller = _controllerFor(repository);

      final pending = controller.connect();
      controller.dispose();
      connectCompleter.complete();
      await pending;
      await pumpEventQueue();

      expect(repository.closeCalls, 1);
      expect(controller.state.status, CoreConnectionStatus.connecting);
    },
  );
}

CoreSessionController _controllerFor(
  _Repository repository, {
  Duration progressInterval = const Duration(days: 1),
  Duration finalSaveTimeout = const Duration(seconds: 1),
  FutureOr<void> Function()? onProgressTick,
}) => CoreSessionController(
  repository: repository,
  currentMediaId: () => 'media-1',
  currentPosition: () => const Duration(seconds: 12),
  onProgressTick: onProgressTick ?? () {},
  progressInterval: progressInterval,
  finalSaveTimeout: finalSaveTimeout,
);

final class _Repository implements CoreSessionRepository {
  _Repository({
    this.languages = const [],
    this.connectFailures = 0,
    this.connectCompleter,
    this.saveCompleter,
    this.saveError,
  });

  final List<String> languages;
  int connectFailures;
  final Completer<void>? connectCompleter;
  final Completer<void>? saveCompleter;
  final Object? saveError;
  final eventController = StreamController<Map<String, dynamic>>();
  final operations = <String>[];
  int connectCalls = 0;
  int closeCalls = 0;
  int saveCalls = 0;
  bool connected = false;

  @override
  bool get isConnected => connected;
  @override
  String? get diagnosticLogPath => '/core.log';
  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '$error');

  @override
  Future<void> connect() async {
    connectCalls++;
    if (connectFailures > 0) {
      connectFailures--;
      throw StateError('connect failed');
    }
    await connectCompleter?.future;
    connected = true;
  }

  @override
  Stream<Map<String, dynamic>> events() => eventController.stream;
  @override
  Future<List<String>> listLanguages() async => languages;

  @override
  Future<void> saveProgress(String mediaId, Duration position) async {
    saveCalls++;
    operations.add('save');
    if (saveError case final error?) throw error;
    await saveCompleter?.future;
  }

  @override
  void requestStop() {
    operations.add('stop');
    connected = false;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    connected = false;
  }
}
