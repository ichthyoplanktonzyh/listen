import 'dart:io';

import 'package:video_player/video_player.dart';

abstract interface class AuxiliaryAudioPlayer {
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}

/// Stateless factory that keeps the platform player plugin out of controllers.
abstract interface class AuxiliaryAudioPlaybackService {
  AuxiliaryAudioPlayer createRemote(Uri source);
  AuxiliaryAudioPlayer createLocalFile(String path);
}

final class VideoAuxiliaryAudioPlaybackService
    implements AuxiliaryAudioPlaybackService {
  const VideoAuxiliaryAudioPlaybackService();

  @override
  AuxiliaryAudioPlayer createRemote(Uri source) =>
      _VideoAuxiliaryAudioPlayer(VideoPlayerController.networkUrl(source));

  @override
  AuxiliaryAudioPlayer createLocalFile(String path) =>
      _VideoAuxiliaryAudioPlayer(VideoPlayerController.file(File(path)));
}

final class _VideoAuxiliaryAudioPlayer implements AuxiliaryAudioPlayer {
  _VideoAuxiliaryAudioPlayer(this._controller);

  final VideoPlayerController _controller;

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> dispose() => _controller.dispose();
}
