import 'package:flutter/foundation.dart';

import '../player_adapter.dart';

const _unset = Object();

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
    Object? mediaId = _unset,
    Object? mediaPath = _unset,
    Object? mediaTitle = _unset,
    Object? mediaFingerprint = _unset,
    String? status,
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? muted,
    double? rate,
    double? volume,
    List<dynamic>? audioTracks,
    Object? selectedAudioId = _unset,
    List<dynamic>? embeddedSubtitleTracks,
    Object? selectedEmbeddedSubtitleId = _unset,
    double? downloadProgress,
    Object? downloadedMediaPath = _unset,
    Object? sourceLoopStart = _unset,
    Object? sourceLoopEnd = _unset,
  }) => PlayerState(
    mediaId: identical(mediaId, _unset) ? this.mediaId : mediaId as String?,
    mediaPath: identical(mediaPath, _unset)
        ? this.mediaPath
        : mediaPath as String?,
    mediaTitle: identical(mediaTitle, _unset)
        ? this.mediaTitle
        : mediaTitle as String?,
    mediaFingerprint: identical(mediaFingerprint, _unset)
        ? this.mediaFingerprint
        : mediaFingerprint as String?,
    status: status ?? this.status,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    playing: playing ?? this.playing,
    muted: muted ?? this.muted,
    rate: rate ?? this.rate,
    volume: volume ?? this.volume,
    audioTracks: audioTracks ?? this.audioTracks,
    selectedAudioId: identical(selectedAudioId, _unset)
        ? this.selectedAudioId
        : selectedAudioId as String?,
    embeddedSubtitleTracks:
        embeddedSubtitleTracks ?? this.embeddedSubtitleTracks,
    selectedEmbeddedSubtitleId: identical(selectedEmbeddedSubtitleId, _unset)
        ? this.selectedEmbeddedSubtitleId
        : selectedEmbeddedSubtitleId as String?,
    downloadProgress: downloadProgress ?? this.downloadProgress,
    downloadedMediaPath: identical(downloadedMediaPath, _unset)
        ? this.downloadedMediaPath
        : downloadedMediaPath as String?,
    sourceLoopStart: identical(sourceLoopStart, _unset)
        ? this.sourceLoopStart
        : sourceLoopStart as Duration?,
    sourceLoopEnd: identical(sourceLoopEnd, _unset)
        ? this.sourceLoopEnd
        : sourceLoopEnd as Duration?,
  );

  double get positionFraction => duration == Duration.zero
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
  String? get mediaTitle => _state.mediaTitle;
  String? get mediaFingerprint => _state.mediaFingerprint;
  String get status => _state.status;
  bool get playing => _state.playing;
  bool get muted => _state.muted;
  Duration get position => _state.position;
  Duration get duration => _state.duration;
  double get rate => _state.rate;
  double get volume => _state.volume;
  double get downloadProgress => _state.downloadProgress;
  String? get downloadedMediaPath => _state.downloadedMediaPath;
  Duration? get sourceLoopStart => _state.sourceLoopStart;
  Duration? get sourceLoopEnd => _state.sourceLoopEnd;
  List<dynamic> get audioTracks => _state.audioTracks;
  String? get selectedAudioId => _state.selectedAudioId;
  List<dynamic> get embeddedSubtitleTracks => _state.embeddedSubtitleTracks;
  String? get selectedEmbeddedSubtitleId => _state.selectedEmbeddedSubtitleId;

  void _update(PlayerState Function(PlayerState) fn) {
    _state = fn(_state);
    notifyListeners();
  }

  void setPosition(Duration position) =>
      _update((s) => s.copyWith(position: position));
  void setDuration(Duration duration) =>
      _update((s) => s.copyWith(duration: duration));
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

  void setSelectedAudioId(String? id) =>
      _update((s) => s.copyWith(selectedAudioId: id));

  void setSelectedEmbeddedSubtitleId(String? id) =>
      _update((s) => s.copyWith(selectedEmbeddedSubtitleId: id));

  void setAudioTracks(List<PlayerTrack> tracks) =>
      _update((s) => s.copyWith(audioTracks: tracks));

  void setEmbeddedSubtitleTracks(List<PlayerTrack> tracks) =>
      _update((s) => s.copyWith(embeddedSubtitleTracks: tracks));

  void setMediaTitle(String title) =>
      _update((s) => s.copyWith(mediaTitle: title));

  void setMediaFingerprint(String fingerprint) =>
      _update((s) => s.copyWith(mediaFingerprint: fingerprint));

  void setMediaPath(String path) => _update((s) => s.copyWith(mediaPath: path));

  /// Toggle the playing state. Does NOT interact with the adapter directly;
  /// callers must also call [DesktopPlayerAdapter.playOrPause].
  void togglePlayPause() => _update((s) => s.copyWith(playing: !s.playing));
}
