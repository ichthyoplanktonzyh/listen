import 'package:flutter/foundation.dart';

import '../services/fullscreen_window.dart';

/// #25-A: the fullscreen immersive playback state as an explicit UI state —
/// not a side effect of the system window being fullscreen.
///
/// F / double-click / the transport button call [toggle]; Esc calls [exit].
/// Entering asks the window for system fullscreen and flips [immersive]
/// optimistically so the chrome leaves in the same frame as the keypress.
/// The window remains the source of truth: every actual transition it
/// reports (green traffic-light button, system gestures, Mission Control)
/// is mirrored back through [FullscreenWindow.onChanged] — entering only
/// when [canEnter] allows (no media on the stage means a fullscreen window
/// is just a big window, not immersive playback).
class ImmersiveModeController extends ChangeNotifier {
  ImmersiveModeController({required this.window, required this.canEnter}) {
    window.onChanged = _syncFromWindow;
  }

  final FullscreenWindow window;
  final bool Function() canEnter;
  bool _immersive = false;

  bool get immersive => _immersive;

  Future<void> toggle() => _immersive ? exit() : enter();

  Future<void> enter() async {
    if (_immersive || !canEnter()) return;
    _immersive = true;
    notifyListeners();
    await window.setFullScreen(true);
  }

  Future<void> exit() async {
    if (!_immersive) return;
    _immersive = false;
    notifyListeners();
    await window.setFullScreen(false);
  }

  void _syncFromWindow(bool windowFullscreen) {
    final next = windowFullscreen ? canEnter() : false;
    if (next == _immersive) return;
    _immersive = next;
    notifyListeners();
  }

  @override
  void dispose() {
    window.onChanged = null;
    super.dispose();
  }
}
