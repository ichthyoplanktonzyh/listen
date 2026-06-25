import 'package:flutter/foundation.dart';

import '../player_adapter.dart';
import '../state/store.dart';

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
  final List<PlayerTrack> audioTracks;
  final String? selectedAudioId;
  final List<PlayerTrack> embeddedSubtitleTracks;
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
    List<PlayerTrack>? audioTracks,
    Object? selectedAudioId = _unset,
    List<PlayerTrack>? embeddedSubtitleTracks,
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
/// Uses [Store] internally for fine-grained reactive state.
/// Keeps [ChangeNotifier] for backward compatibility.
class PlayerController extends ChangeNotifier {
  final Store<PlayerState> _store;

  PlayerController() : _store = Store(const PlayerState());

  /// The reactive store — allows fine-grained field subscriptions via [Store.select].
  Store<PlayerState> get store => _store;

  /// The current immutable state snapshot.
  PlayerState get state => _store.state;

  // ── Convenience accessors ──

  String? get mediaId => _store.state.mediaId;
  String? get mediaPath => _store.state.mediaPath;
  String? get mediaTitle => _store.state.mediaTitle;
  String? get mediaFingerprint => _store.state.mediaFingerprint;
  String get status => _store.state.status;
  bool get playing => _store.state.playing;
  bool get muted => _store.state.muted;
  Duration get position => _store.state.position;
  Duration get duration => _store.state.duration;
  double get rate => _store.state.rate;
  double get volume => _store.state.volume;
  double get downloadProgress => _store.state.downloadProgress;
  String? get downloadedMediaPath => _store.state.downloadedMediaPath;
  Duration? get sourceLoopStart => _store.state.sourceLoopStart;
  Duration? get sourceLoopEnd => _store.state.sourceLoopEnd;
  List<PlayerTrack> get audioTracks => _store.state.audioTracks;
  String? get selectedAudioId => _store.state.selectedAudioId;
  List<PlayerTrack> get embeddedSubtitleTracks =>
      _store.state.embeddedSubtitleTracks;
  String? get selectedEmbeddedSubtitleId =>
      _store.state.selectedEmbeddedSubtitleId;

  /// Create a [ValueNotifier] that tracks a specific derived value.
  /// The notifier only fires when the selected value changes.
  ValueNotifier<R> select<R>(R Function(PlayerState) selector) =>
      _store.select(selector);

  void setPosition(Duration position) =>
      _store.update((s) => s.copyWith(position: position));

  void setDuration(Duration duration) =>
      _store.update((s) => s.copyWith(duration: duration));

  void setPlaying(bool playing) =>
      _store.update((s) => s.copyWith(playing: playing));

  /// Set download progress (0.0–1.0) and reset when complete.
  void setDownloadProgress(double progress) {
    if (progress >= 1.0) {
      _store.update((s) => s.copyWith(downloadProgress: 0.0));
    } else {
      _store.update((s) => s.copyWith(downloadProgress: progress));
    }
  }

  /// Set media metadata after a successful open.
  void setMedia({
    required String id,
    required String path,
    required String title,
    required String fingerprint,
  }) {
    _store.update(
      (s) => s.copyWith(
        mediaId: id,
        mediaPath: path,
        mediaTitle: title,
        mediaFingerprint: fingerprint,
      ),
    );
  }

  void clearMedia() => _store.update(
    (s) => s.copyWith(
      mediaId: null,
      mediaPath: null,
      mediaTitle: null,
      mediaFingerprint: null,
    ),
  );

  void setMuted(bool muted) =>
      _store.update((s) => s.copyWith(muted: muted));

  void setRate(double rate) =>
      _store.update((s) => s.copyWith(rate: rate));

  void setVolume(double volume) =>
      _store.update((s) => s.copyWith(volume: volume));

  void setStatus(String status) =>
      _store.update((s) => s.copyWith(status: status));

  void setDownloadedMediaPath(String path) =>
      _store.update((s) => s.copyWith(downloadedMediaPath: path));

  void setAudioTracks(List<PlayerTrack> tracks) =>
      _store.update((s) => s.copyWith(audioTracks: tracks));

  void setSelectedAudioId(String? id) =>
      _store.update((s) => s.copyWith(selectedAudioId: id));

  void setEmbeddedSubtitleTracks(List<PlayerTrack> tracks) =>
      _store.update((s) => s.copyWith(embeddedSubtitleTracks: tracks));

  void setSelectedEmbeddedSubtitleId(String? id) =>
      _store.update((s) => s.copyWith(selectedEmbeddedSubtitleId: id));

  void setSourceLoop(Duration? start, Duration? end) =>
      _store.update((s) => s.copyWith(sourceLoopStart: start, sourceLoopEnd: end));

  void setMediaPath(String path) =>
      _store.update((s) => s.copyWith(mediaPath: path));
}
