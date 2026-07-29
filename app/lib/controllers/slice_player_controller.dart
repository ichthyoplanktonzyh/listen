import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../state/store.dart';

const _unset = Object();

class SlicePlayerState {
  const SlicePlayerState({
    this.open = false,
    this.loading = false,
    this.playing = false,
    this.looping = true,
    this.showVideo = false,
    this.path,
    this.mediaId,
    this.trackId,
    this.sentenceId,
    this.wordForm,
    this.mediaTitle,
    this.sentence,
    this.start = Duration.zero,
    this.end = Duration.zero,
    this.position = Duration.zero,
    this.error,
  });

  final bool open;
  final bool loading;
  final bool playing;
  final bool looping;
  final bool showVideo;
  final String? path;
  final String? mediaId;
  final String? trackId;
  final String? sentenceId;
  final String? wordForm;
  final String? mediaTitle;
  final String? sentence;
  final Duration start;
  final Duration end;
  final Duration position;
  final String? error;

  SlicePlayerState copyWith({
    bool? open,
    bool? loading,
    bool? playing,
    bool? looping,
    bool? showVideo,
    Object? path = _unset,
    Object? mediaId = _unset,
    Object? trackId = _unset,
    Object? sentenceId = _unset,
    Object? wordForm = _unset,
    Object? mediaTitle = _unset,
    Object? sentence = _unset,
    Duration? start,
    Duration? end,
    Duration? position,
    Object? error = _unset,
  }) => SlicePlayerState(
    open: open ?? this.open,
    loading: loading ?? this.loading,
    playing: playing ?? this.playing,
    looping: looping ?? this.looping,
    showVideo: showVideo ?? this.showVideo,
    path: identical(path, _unset) ? this.path : path as String?,
    mediaId: identical(mediaId, _unset) ? this.mediaId : mediaId as String?,
    trackId: identical(trackId, _unset) ? this.trackId : trackId as String?,
    sentenceId: identical(sentenceId, _unset)
        ? this.sentenceId
        : sentenceId as String?,
    wordForm: identical(wordForm, _unset) ? this.wordForm : wordForm as String?,
    mediaTitle: identical(mediaTitle, _unset)
        ? this.mediaTitle
        : mediaTitle as String?,
    sentence: identical(sentence, _unset) ? this.sentence : sentence as String?,
    start: start ?? this.start,
    end: end ?? this.end,
    position: position ?? this.position,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

abstract interface class SlicePlaybackAdapter {
  VideoPlayerController? get videoController;
  bool get isPlaying;
  Future<Duration?> readPosition();
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> dispose();
}

class VideoPlayerSlicePlaybackAdapter implements SlicePlaybackAdapter {
  VideoPlayerSlicePlaybackAdapter._(this._controller);

  final VideoPlayerController _controller;

  static Future<VideoPlayerSlicePlaybackAdapter> create(String path) async {
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    return VideoPlayerSlicePlaybackAdapter._(controller);
  }

  @override
  VideoPlayerController get videoController => _controller;
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

typedef CreateSlicePlaybackAdapter =
    Future<SlicePlaybackAdapter> Function(String path);

/// Owns the second fvp/video_player instance used only for a lexical source
/// slice. It deliberately has no connection to primary-player state.
class SlicePlayerController extends ChangeNotifier {
  SlicePlayerController({CreateSlicePlaybackAdapter? createAdapter})
    : _createAdapter = createAdapter ?? VideoPlayerSlicePlaybackAdapter.create,
      _store = Store(const SlicePlayerState()) {
    _store.addListener(notifyListeners);
  }

  final CreateSlicePlaybackAdapter _createAdapter;
  final Store<SlicePlayerState> _store;
  SlicePlaybackAdapter? _adapter;
  Timer? _positionTimer;
  int _generation = 0;
  double _rate = 1.0;

  Store<SlicePlayerState> get store => _store;
  SlicePlayerState get state => _store.state;
  VideoPlayerController? get videoController => _adapter?.videoController;

  Future<void> open({
    required Map<String, dynamic> occurrence,
    required String path,
  }) async {
    final startMs = occurrence['start_ms_snapshot'];
    final endMs = occurrence['end_ms_snapshot'];
    if (startMs is! int || endMs is! int || endMs <= startMs) {
      _store.replace(
        const SlicePlayerState(
          open: true,
          error: 'This source clip has an invalid time range',
        ),
      );
      return;
    }
    await close();
    final generation = ++_generation;
    final start = Duration(milliseconds: startMs);
    final end = Duration(milliseconds: endMs);
    _store.replace(
      SlicePlayerState(
        open: true,
        loading: true,
        path: path,
        mediaId: occurrence['media_id'] as String?,
        trackId: occurrence['track_id'] as String?,
        sentenceId: occurrence['sentence_id'] as String?,
        wordForm: occurrence['original_form'] as String?,
        mediaTitle:
            occurrence['media_title_snapshot'] as String? ??
            File(path).uri.pathSegments.last,
        sentence: occurrence['sentence_text_snapshot'] as String?,
        start: start,
        end: end,
        position: start,
      ),
    );
    try {
      final adapter = await _createAdapter(path);
      if (generation != _generation) {
        await adapter.dispose();
        return;
      }
      _adapter = adapter;
      await adapter.setRate(_rate);
      await adapter.seek(start);
      await adapter.play();
      if (generation != _generation) return;
      _store.update((state) => state.copyWith(loading: false, playing: true));
      _positionTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => unawaited(_pollPlayback(generation)),
      );
    } catch (error) {
      if (generation == _generation) {
        _store.update(
          (state) => state.copyWith(
            loading: false,
            playing: false,
            error: 'Could not load source clip',
          ),
        );
      }
    }
  }

  /// Keeps file-location and fingerprint failures visible in the same surface
  /// as a playable clip instead of relegating them to a transient host status.
  Future<void> showError(
    String message, {
    Map<String, dynamic>? occurrence,
  }) async {
    await close();
    _store.replace(
      SlicePlayerState(
        open: true,
        wordForm: occurrence?['original_form'] as String?,
        mediaTitle: occurrence?['media_title_snapshot'] as String?,
        sentence: occurrence?['sentence_text_snapshot'] as String?,
        error: message,
      ),
    );
  }

  Future<void> _pollPlayback(int generation) async {
    if (generation != _generation) return;
    final adapter = _adapter;
    if (adapter == null) return;
    final position = await adapter.readPosition();
    if (position == null || generation != _generation) return;
    if (position >= state.end) {
      if (state.looping) {
        await adapter.seek(state.start);
        if (!adapter.isPlaying) await adapter.play();
      } else {
        await adapter.pause();
      }
    }
    if (generation == _generation) {
      _store.update(
        (current) => current.copyWith(
          position: position >= current.end && current.looping
              ? current.start
              : position,
          playing: adapter.isPlaying,
        ),
      );
    }
  }

  @visibleForTesting
  Future<void> pollNow() => _pollPlayback(_generation);

  Future<void> togglePlayback() async {
    final adapter = _adapter;
    if (adapter == null) return;
    if (adapter.isPlaying) {
      await adapter.pause();
    } else {
      await adapter.play();
    }
    _store.update((state) => state.copyWith(playing: adapter.isPlaying));
  }

  Future<void> pause() async {
    final adapter = _adapter;
    if (adapter == null || !adapter.isPlaying) return;
    await adapter.pause();
    _store.update((state) => state.copyWith(playing: false));
  }

  Future<void> replay() async {
    final adapter = _adapter;
    if (adapter == null) return;
    await adapter.seek(state.start);
    await adapter.play();
    _store.update(
      (state) => state.copyWith(position: state.start, playing: true),
    );
  }

  void toggleLooping() =>
      _store.update((state) => state.copyWith(looping: !state.looping));

  void setLooping(bool value) =>
      _store.update((state) => state.copyWith(looping: value));

  Future<void> setRate(double value) async {
    _rate = value;
    await _adapter?.setRate(value);
  }

  void toggleVideo() =>
      _store.update((state) => state.copyWith(showVideo: !state.showVideo));

  /// Dictionary detail uses video as the default source-card surface; other
  /// consumers may still opt into audio-first by calling this explicitly.
  void setShowVideo(bool value) =>
      _store.update((state) => state.copyWith(showVideo: value));

  Future<void> close() async {
    _generation++;
    _positionTimer?.cancel();
    _positionTimer = null;
    final adapter = _adapter;
    _adapter = null;
    if (adapter != null) await adapter.dispose();
    _store.replace(const SlicePlayerState());
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    final adapter = _adapter;
    _adapter = null;
    if (adapter != null) unawaited(adapter.dispose());
    _store.dispose();
    super.dispose();
  }
}
