import 'dart:io';

import 'package:fvp/fvp.dart' as fvp;

/// Owns the desktop-specific playback plugin bootstrap.
abstract interface class DesktopPlaybackBootstrap {
  void initialize();
}

final class FvpDesktopPlaybackBootstrap implements DesktopPlaybackBootstrap {
  const FvpDesktopPlaybackBootstrap();

  @override
  void initialize() {
    final bundledFfmpeg = bundledFfmpegPath(Platform.resolvedExecutable);
    fvp.registerWith(
      options: {
        'platforms': ['macos'],
        'global': {'ffmpeg': bundledFfmpeg, 'libffmpeg': bundledFfmpeg},
      },
    );
  }
}

String bundledFfmpegPath(String resolvedExecutable) {
  final executable = File(resolvedExecutable);
  return '${executable.parent.parent.path}'
      '/Frameworks/mdk.framework/Versions/A/libffmpeg.8.dylib';
}
