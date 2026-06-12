import 'package:flutter/foundation.dart';

/// Immutable snapshot of playback state.
/// Used by [PlayerController] to notify listeners.
class PlayerState {
  const PlayerState({
    this.mediaId,
    this.mediaPath,
    this.mediaTitle,
    this.mediaFingerprint,
    this.status = 'Starting local core...',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.muted = false,
    this.rate = 1.0,
    this.volume = 100.0,
    this.audioTracks = const [],
    this.selectedAudioId,
    this.embeddedSubtitleTracks = const [],
    this.selectedEmbeddedSubtitleId,
    this.downloadProgress = 0.0,
    this.downloadedMediaPath,
    this.sourceLoopStart,
    this.sourceLoopEnd,
  });

  final String? mediaId;
  final String? mediaPath;
  final String? mediaTitle;
  final String? mediaFingerprint;
  final String status;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool muted;
  final double rate;
  final double volume;
  final List<dynamic> audioTracks;
  final String? selectedAudioId;
  final List<dynamic> embeddedSubtitleTracks;
  final String? selectedEmbeddedSubtitleId;
  final double downloadProgress;
  final String? downloadedMediaPath;
  final Duration? sourceLoopStart;
  final Duration? sourceLoopEnd;

  PlayerState copyWith({
    String? mediaId,
    String? mediaPath,
    String? mediaTitle,
    String? mediaFingerprint,
    String? status,
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? muted,
    double? rate,
    double? volume,
    List<dynamic>? audioTracks,
    String? selectedAudioId,
    List<dynamic>? embeddedSubtitleTracks,
    String? selectedEmbeddedSubtitleId,
    double? downloadProgress,
    String? downloadedMediaPath,
    Duration? sourceLoopStart,
    Duration? sourceLoopEnd,
  }) =>
      PlayerState(
        mediaId: mediaId ?? this.mediaId,
        mediaPath: mediaPath ?? this.mediaPath,
        mediaTitle: mediaTitle ?? this.mediaTitle,
        mediaFingerprint: mediaFingerprint ?? this.mediaFingerprint,
        status: status ?? this.status,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        playing: playing ?? this.playing,
        muted: muted ?? this.muted,
        rate: rate ?? this.rate,
        volume: volume ?? this.volume,
        audioTracks: audioTracks ?? this.audioTracks,
        selectedAudioId: selectedAudioId ?? this.selectedAudioId,
        embeddedSubtitleTracks:
            embeddedSubtitleTracks ?? this.embeddedSubtitleTracks,
        selectedEmbeddedSubtitleId:
            selectedEmbeddedSubtitleId ?? this.selectedEmbeddedSubtitleId,
        downloadProgress: downloadProgress ?? this.downloadProgress,
        downloadedMediaPath: downloadedMediaPath ?? this.downloadedMediaPath,
        sourceLoopStart: sourceLoopStart ?? this.sourceLoopStart,
        sourceLoopEnd: sourceLoopEnd ?? this.sourceLoopEnd,
      );

  double get positionFraction =>
      duration == Duration.zero
          ? 0.0
          : position.inMilliseconds / duration.inMilliseconds;
}

/// Controls media playback state and actions.
///
/// Wraps [DesktopPlayerAdapter] and exposes a [PlayerState] value object
/// with [ChangeNotifier] for targeted widget rebuilds.
class PlayerController extends ChangeNotifier {
  PlayerState _state = const PlayerState();

  PlayerState get state => _state;

  // Convenience accessors for common fields
  String? get mediaId => _state.mediaId;
  String? get mediaPath => _state.mediaPath;
  bool get playing => _state.playing;
  Duration get position => _state.position;
  Duration get duration => _state.duration;
  double get rate => _state.rate;
  double get volume => _state.volume;
  double get downloadProgress => _state.downloadProgress;

  void _update(PlayerState Function(PlayerState) fn) {
    _state = fn(_state);
    notifyListeners();
  }

  void setPosition(Duration position) => _update((s) => s.copyWith(position: position));
  void setDuration(Duration duration) => _update((s) => s.copyWith(duration: duration));
  void setPlaying(bool playing) => _update((s) => s.copyWith(playing: playing));

  /// Set download progress (0.0–1.0) and reset when complete.
  void setDownloadProgress(double progress) {
    if (progress >= 1.0) {
      _update((s) => s.copyWith(downloadProgress: 0.0));
    } else {
      _update((s) => s.copyWith(downloadProgress: progress));
    }
  }

  /// Set media metadata after a successful open.
  void setMedia({
    required String id,
    required String path,
    required String title,
    required String fingerprint,
  }) {
    _update(
      (s) => s.copyWith(
        mediaId: id,
        mediaPath: path,
        mediaTitle: title,
        mediaFingerprint: fingerprint,
      ),
    );
  }

  void clearMedia() => _update(
    (s) => s.copyWith(
      mediaId: null,
      mediaPath: null,
      mediaTitle: null,
      mediaFingerprint: null,
    ),
  );

  void setMuted(bool muted) => _update((s) => s.copyWith(muted: muted));
  void setRate(double rate) => _update((s) => s.copyWith(rate: rate));
  void setVolume(double volume) => _update((s) => s.copyWith(volume: volume));

  void setStatus(String status) => _update((s) => s.copyWith(status: status));

  void setDownloadedMediaPath(String path) =>
      _update((s) => s.copyWith(downloadedMediaPath: path));

  void setSourceLoop(Duration? start, Duration? end) =>
      _update((s) => s.copyWith(sourceLoopStart: start, sourceLoopEnd: end));
}
