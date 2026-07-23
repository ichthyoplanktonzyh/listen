import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/immersive_mode_controller.dart';
import 'package:llplayer_next/services/fullscreen_window.dart';

/// #25-A: the immersive state machine. The window is the source of truth —
/// these tests pin the mirror in both directions and the media gate.
class _FakeFullscreenWindow implements FullscreenWindow {
  final requests = <bool>[];
  ValueChanged<bool>? _listener;

  @override
  set onChanged(ValueChanged<bool>? listener) => _listener = listener;

  @override
  Future<void> setFullScreen(bool value) async => requests.add(value);

  /// Simulates the window actually transitioning (bridge notification).
  void reportTransition(bool fullscreen) => _listener?.call(fullscreen);
}

void main() {
  late _FakeFullscreenWindow window;
  late ImmersiveModeController controller;
  var hasMedia = true;
  var notifications = 0;

  setUp(() {
    window = _FakeFullscreenWindow();
    hasMedia = true;
    notifications = 0;
    controller = ImmersiveModeController(
      window: window,
      canEnter: () => hasMedia,
    );
    controller.addListener(() => notifications++);
  });

  tearDown(() => controller.dispose());

  test(
    'enter flips immersive first, then asks for system fullscreen',
    () async {
      await controller.enter();
      expect(controller.immersive, isTrue);
      expect(window.requests, [true]);
      expect(notifications, 1);
    },
  );

  test('exit leaves immersive and system fullscreen', () async {
    await controller.enter();
    await controller.exit();
    expect(controller.immersive, isFalse);
    expect(window.requests, [true, false]);
  });

  test('toggle round-trips', () async {
    await controller.toggle();
    expect(controller.immersive, isTrue);
    await controller.toggle();
    expect(controller.immersive, isFalse);
  });

  test('no media on the stage means no immersive entry', () async {
    hasMedia = false;
    await controller.enter();
    expect(controller.immersive, isFalse);
    expect(window.requests, isEmpty, reason: '被拒的进入不该碰系统全屏');
    expect(notifications, 0);
  });

  test('enter and exit are idempotent', () async {
    await controller.enter();
    await controller.enter();
    expect(window.requests, [true]);
    await controller.exit();
    await controller.exit();
    expect(window.requests, [true, false]);
  });

  test('the green button entering fullscreen mirrors into immersive', () {
    window.reportTransition(true);
    expect(controller.immersive, isTrue);
    expect(window.requests, isEmpty, reason: '镜像不该再向窗口发请求');
  });

  test('the green button exiting fullscreen leaves immersive', () async {
    await controller.enter();
    window.reportTransition(false);
    expect(controller.immersive, isFalse);
  });

  test('a fullscreen window without media stays non-immersive', () {
    hasMedia = false;
    window.reportTransition(true);
    expect(controller.immersive, isFalse);
    expect(notifications, 0);
  });

  test('the confirming notification after enter is silent', () async {
    await controller.enter();
    window.reportTransition(true);
    expect(notifications, 1, reason: '窗口确认已在沉浸态,不该重复通知');
  });

  test('dispose detaches the window listener', () {
    controller.dispose();
    window.reportTransition(true);
    expect(controller.immersive, isFalse);
    // tearDown will dispose again; replace with a fresh controller.
    controller = ImmersiveModeController(
      window: window,
      canEnter: () => hasMedia,
    );
  });
}
