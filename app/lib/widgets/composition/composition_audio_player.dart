import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme/icon_size.dart';

/// The rendering adapter that owns the derived-audio playback of an adopted
/// composition. It is narrowly allow-listed for `video_player` and `dart:io`:
/// the composition screen itself stays free of platform plugins.
class CompositionAudioPlayer extends StatefulWidget {
  const CompositionAudioPlayer({
    super.key,
    required this.mediaPath,
    required this.onPositionChanged,
  });

  final String mediaPath;
  final ValueChanged<Duration> onPositionChanged;

  @override
  State<CompositionAudioPlayer> createState() => _CompositionAudioPlayerState();
}

class _CompositionAudioPlayerState extends State<CompositionAudioPlayer> {
  VideoPlayerController? _player;
  bool _initialized = false;
  bool _playing = false;
  Timer? _positionTicker;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final player = VideoPlayerController.file(File(widget.mediaPath));
    await player.initialize();
    if (!mounted) {
      await player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _initialized = true;
    });
    _positionTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      _sync();
    });
  }

  void _sync() {
    final player = _player;
    if (player == null || !_initialized) return;
    widget.onPositionChanged(player.value.position);
  }

  void _toggle() {
    final player = _player;
    if (player == null || !_initialized) return;
    if (_playing) {
      player.pause();
    } else {
      player.play();
    }
    setState(() => _playing = !_playing);
  }

  @override
  void dispose() {
    _positionTicker?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();
    return Center(
      child: IconButton.filled(
        key: const Key('composition-play-toggle'),
        iconSize: ListenIconSize.illustration,
        icon: Icon(
          _playing ? Icons.pause_circle_outline : Icons.play_circle_outline,
        ),
        onPressed: _toggle,
      ),
    );
  }
}
