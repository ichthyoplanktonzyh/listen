import 'dart:io';

import 'package:video_player/video_player.dart';

/// Opaque presentation handle for the platform-backed video surface.
abstract interface class SlicePlaybackRenderHandle {
  double get aspectRatio;
}

/// Read-only rendering handle understood by widgets that use video_player.
/// Playback commands stay on [SlicePlaybackSession].
final class VideoPlayerSliceRenderHandle implements SlicePlaybackRenderHandle {
  const VideoPlayerSliceRenderHandle(this.controller);

  final VideoPlayerController controller;

  @override
  double get aspectRatio => controller.value.aspectRatio;
}

/// One initialized, independently controlled source-clip playback session.
abstract interface class SlicePlaybackSession {
  SlicePlaybackRenderHandle? get renderHandle;
  bool get isPlaying;
  Future<Duration?> readPosition();
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> dispose();
}

/// Creates playback sessions and owns path/platform interpretation.
abstract interface class SlicePlaybackService {
  Future<SlicePlaybackSession> open(String path);
  String displayName(String path);
}

typedef SlicePlaybackAdapter = SlicePlaybackSession;
typedef CreateSlicePlaybackAdapter =
    Future<SlicePlaybackSession> Function(String path);

class VideoPlayerSlicePlaybackService implements SlicePlaybackService {
  const VideoPlayerSlicePlaybackService();

  @override
  Future<SlicePlaybackSession> open(String path) async {
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    return _VideoPlayerSlicePlaybackSession(controller);
  }

  @override
  String displayName(String path) => File(path).uri.pathSegments.last;
}

/// Compatibility adapter for callers and tests that inject a session factory.
class CallbackSlicePlaybackService implements SlicePlaybackService {
  const CallbackSlicePlaybackService(this._create);

  final CreateSlicePlaybackAdapter _create;

  @override
  Future<SlicePlaybackSession> open(String path) => _create(path);

  @override
  String displayName(String path) => Uri.file(path).pathSegments.last;
}

class _VideoPlayerSlicePlaybackSession implements SlicePlaybackSession {
  _VideoPlayerSlicePlaybackSession(this._controller)
    : _renderHandle = VideoPlayerSliceRenderHandle(_controller);

  final VideoPlayerController _controller;
  final VideoPlayerSliceRenderHandle _renderHandle;

  @override
  SlicePlaybackRenderHandle get renderHandle => _renderHandle;

  @override
  bool get isPlaying => _controller.value.isPlaying;

  @override
  Future<Duration?> readPosition() => _controller.position;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seek(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setRate(double rate) => _controller.setPlaybackSpeed(rate);

  @override
  Future<void> dispose() => _controller.dispose();
}
