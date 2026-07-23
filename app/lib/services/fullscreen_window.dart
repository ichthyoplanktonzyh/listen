import 'dart:io';

import 'package:flutter/services.dart';

/// #25-A: the Dart face of the window's system-fullscreen state.
///
/// The window is the source of truth: [setFullScreen] only *requests* a
/// transition, and every actual change — whether we asked for it or the user
/// hit the green traffic-light button / a system gesture — arrives through
/// [onChanged]. Callers mirror, they never assume.
abstract interface class FullscreenWindow {
  /// Fired after the window actually entered (`true`) or left (`false`)
  /// system fullscreen.
  set onChanged(ValueChanged<bool>? listener);

  Future<void> setFullScreen(bool value);
}

class MacosFullscreenWindow implements FullscreenWindow {
  MacosFullscreenWindow({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_handleCall);
  }

  static const _channelName = 'app.llplayernext/fullscreen';
  final MethodChannel _channel;
  ValueChanged<bool>? _onChanged;

  @override
  set onChanged(ValueChanged<bool>? listener) => _onChanged = listener;

  @override
  Future<void> setFullScreen(bool value) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<bool>('setFullScreen', value);
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method == 'onFullScreenChanged') {
      final value = call.arguments;
      if (value is bool) _onChanged?.call(value);
    }
    return null;
  }
}
