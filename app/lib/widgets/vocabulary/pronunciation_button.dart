import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../localization.dart';

class PronunciationButton extends StatefulWidget {
  const PronunciationButton({super.key, required this.audioUrl});

  final String audioUrl;

  @override
  State<PronunciationButton> createState() => _PronunciationButtonState();
}

class _PronunciationButtonState extends State<PronunciationButton> {
  VideoPlayerController? player;
  bool busy = false;

  Future<void> _play() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await player?.dispose();
      final next = VideoPlayerController.networkUrl(Uri.parse(widget.audioUrl));
      player = next;
      await next.initialize();
      await next.play();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('pronunciationUnavailable'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppLocalizations.of(context).text('pronunciation'),
    onPressed: busy ? null : _play,
    icon: busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.volume_up_outlined),
  );
}
