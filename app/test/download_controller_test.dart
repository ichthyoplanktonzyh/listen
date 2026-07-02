import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/download_controller.dart';
import 'package:llplayer_next/widgets/player/download_status_bar.dart';

void main() {
  group('DownloadController', () {
    test('starting clears a stale failed/completed bar', () {
      final controller = DownloadController();
      addTearDown(controller.dispose);

      controller.fail('boom');
      expect(controller.snapshot?.kind, DownloadStatusKind.failed);

      controller.starting();
      expect(controller.snapshot, isNull);
    });

    test('attach reports progress then completes with a path', () async {
      final controller = DownloadController();
      addTearDown(controller.dispose);
      final progress = StreamController<double>();
      final completed = Completer<String?>();
      String? completedPath;

      controller.starting();
      controller.attach(
        progress: progress.stream,
        completed: completed.future,
        cancel: () {},
        onCompleted: (path) => completedPath = path,
      );
      expect(controller.snapshot?.kind, DownloadStatusKind.downloading);

      progress.add(0.5);
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot?.progress, 0.5);

      completed.complete('/tmp/video.mp4');
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot?.kind, DownloadStatusKind.completed);
      expect(controller.snapshot?.downloadedMediaPath, '/tmp/video.mp4');
      expect(controller.downloadedMediaPath, '/tmp/video.mp4');
      expect(completedPath, '/tmp/video.mp4');

      await progress.close();
    });

    test('attach surfaces a failure through the failed snapshot', () async {
      final controller = DownloadController();
      addTearDown(controller.dispose);
      final progress = StreamController<double>();
      final completed = Completer<String?>();
      String? failure;

      controller.attach(
        progress: progress.stream,
        completed: completed.future,
        cancel: () {},
        onFailed: (error) => failure = error,
      );

      completed.completeError(StateError('nope'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot?.kind, DownloadStatusKind.failed);
      expect(failure, contains('nope'));

      await progress.close();
    });

    test('cancel hides the bar, cancels the handle, and drops late completion',
        () async {
      final controller = DownloadController();
      addTearDown(controller.dispose);
      final progress = StreamController<double>();
      final completed = Completer<String?>();
      var cancelled = false;
      var completedCalled = false;

      controller.attach(
        progress: progress.stream,
        completed: completed.future,
        cancel: () => cancelled = true,
        onCompleted: (_) => completedCalled = true,
      );

      controller.cancel();
      expect(cancelled, isTrue);
      expect(controller.snapshot, isNull);

      // A late completion from the cancelled download must not resurrect the bar.
      completed.complete('/tmp/late.mp4');
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot, isNull);
      expect(completedCalled, isFalse);

      await progress.close();
    });

    test('dispose drops late completion without notifying', () async {
      final controller = DownloadController();
      final completed = Completer<String?>();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.attach(
        progress: const Stream<double>.empty(),
        completed: completed.future,
        cancel: () {},
      );
      final notifiedAtAttach = notified;

      controller.dispose();
      completed.complete('/tmp/after-dispose.mp4');
      await Future<void>.delayed(Duration.zero);

      // No notifications (and no throw) after dispose.
      expect(notified, notifiedAtAttach);
    });

    test('failed bar auto-dismisses after the configured delay', () async {
      final controller = DownloadController(
        failedAutoDismiss: const Duration(milliseconds: 30),
      );
      addTearDown(controller.dispose);

      controller.fail('boom');
      expect(controller.snapshot?.kind, DownloadStatusKind.failed);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.snapshot, isNull);
    });

    test('a new download cancels a pending failed auto-dismiss', () async {
      final controller = DownloadController(
        failedAutoDismiss: const Duration(milliseconds: 30),
      );
      addTearDown(controller.dispose);
      final progress = StreamController<double>();
      final completed = Completer<String?>();

      controller.fail('boom');
      controller.starting();
      controller.attach(
        progress: progress.stream,
        completed: completed.future,
        cancel: () {},
      );
      expect(controller.snapshot?.kind, DownloadStatusKind.downloading);

      // The stale failed timer must not clear the new downloading bar.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.snapshot?.kind, DownloadStatusKind.downloading);

      await progress.close();
    });

    test('completed bar persists (Open stays available)', () async {
      final controller = DownloadController(
        failedAutoDismiss: const Duration(milliseconds: 30),
      );
      addTearDown(controller.dispose);
      final progress = StreamController<double>();
      final completed = Completer<String?>();

      controller.attach(
        progress: progress.stream,
        completed: completed.future,
        cancel: () {},
      );
      completed.complete('/tmp/video.mp4');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Completed never auto-dismisses; only Open/dismiss clears it.
      expect(controller.snapshot?.kind, DownloadStatusKind.completed);

      await progress.close();
    });
  });
}
