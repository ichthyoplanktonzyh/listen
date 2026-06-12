import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart';
import 'package:video_player/video_player.dart';

class PlayerTrack {
  const PlayerTrack({
    required this.index,
    required this.id,
    this.title,
    this.language,
    this.isDefault = false,
  });

  final int index;
  final String id;
  final String? title;
  final String? language;
  final bool isDefault;
}

class PlayerTracks {
  const PlayerTracks({this.audio = const [], this.subtitle = const []});

  final List<PlayerTrack> audio;
  final List<PlayerTrack> subtitle;
}

class DesktopPlayerAdapter {
  DesktopPlayerAdapter() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final current = _controller;
      if (current != null && current.value.isInitialized) {
        _position.add(current.value.position);
      }
    });
  }

  final controller = ValueNotifier<VideoPlayerController?>(null);
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _tracks = StreamController<PlayerTracks>.broadcast();
  late final Timer _positionTimer;
  double _rate = 1;
  double _volume = 100;
  VideoPlayerController? get _controller => controller.value;

  Stream<Duration> get position => _position.stream;
  Stream<Duration> get duration => _duration.stream;
  Stream<bool> get playing => _playing.stream;
  Stream<String> get errors => _errors.stream;
  Stream<PlayerTracks> get tracks => _tracks.stream;
  Duration get currentPosition => _controller?.value.position ?? Duration.zero;

  Future<void> open(String path, {bool play = true}) async {
    final previous = _controller;
    if (previous != null) {
      previous.removeListener(_notify);
      await previous.dispose();
    }
    final uri = Uri.tryParse(path);
    final next = uri != null && uri.hasScheme && uri.scheme != 'file'
        ? VideoPlayerController.networkUrl(uri)
        : VideoPlayerController.file(File(path));
    controller.value = next;
    next.addListener(_notify);
    try {
      await next.initialize();
      await next.setPlaybackSpeed(_rate);
      await next.setVolume(_volume / 100);
      if (play) await next.play();
      _notify();
      _publishTracks(next);
    } catch (error) {
      _errors.add('Playback failed: $error');
      rethrow;
    }
  }

  void _notify() {
    final value = _controller?.value;
    if (value == null) return;
    _duration.add(value.duration);
    _playing.add(value.isPlaying);
    if (value.hasError) _errors.add(value.errorDescription ?? 'Playback error');
  }

  void _publishTracks(VideoPlayerController value) {
    final dynamic info = value.getMediaInfo();
    if (info == null) {
      _tracks.add(const PlayerTracks());
      return;
    }
    final activeAudio = value.getActiveAudioTracks() ?? const <int>[];
    final audioInfo = (info.audio as Iterable<dynamic>?) ?? const [];
    final subtitleInfo = (info.subtitle as Iterable<dynamic>?) ?? const [];
    final audio = <PlayerTrack>[
      for (final dynamic track in audioInfo)
        PlayerTrack(
          index: track.index as int,
          id: '${track.index}',
          title: track.metadata['title'] as String?,
          language: track.metadata['language'] as String?,
          isDefault: activeAudio.contains(track.index),
        ),
    ];
    final subtitle = <PlayerTrack>[
      for (final dynamic track in subtitleInfo)
        PlayerTrack(
          index: track.index as int,
          id: '${track.index}',
          title: track.metadata['title'] as String?,
          language: track.metadata['language'] as String?,
        ),
    ];
    _tracks.add(PlayerTracks(audio: audio, subtitle: subtitle));
  }

  Future<void> playOrPause() async {
    final value = _controller;
    if (value == null) return;
    value.value.isPlaying ? await value.pause() : await value.play();
  }

  Future<void> play() async => _controller?.play();
  Future<void> stop() async {
    await _controller?.pause();
    await _controller?.seekTo(Duration.zero);
  }

  Future<void> seek(Duration position) async => _controller?.seekTo(position);
  Future<void> setRate(double rate) async {
    _rate = rate;
    await _controller?.setPlaybackSpeed(rate);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _controller?.setVolume(volume / 100);
  }

  Future<void> selectAudio(PlayerTrack track) async =>
      _controller?.setAudioTracks([track.index]);
  Future<void> selectSubtitle(PlayerTrack track) async =>
      _controller?.setSubtitleTracks([track.index]);
  Future<void> disableNativeSubtitles() async =>
      _controller?.setSubtitleTracks(const []);

  Future<void> dispose() async {
    _positionTimer.cancel();
    final value = _controller;
    if (value != null) {
      value.removeListener(_notify);
      await value.dispose();
    }
    controller.dispose();
    await Future.wait([
      _position.close(),
      _duration.close(),
      _playing.close(),
      _errors.close(),
      _tracks.close(),
    ]);
  }
}

class PlayerSurface extends StatelessWidget {
  const PlayerSurface({super.key, required this.adapter});

  final DesktopPlayerAdapter adapter;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlayerController?>(
        valueListenable: adapter.controller,
        builder: (context, controller, _) {
          if (controller == null || !controller.value.isInitialized) {
            return const ColoredBox(color: Colors.black);
          }
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          );
        },
      );
}
