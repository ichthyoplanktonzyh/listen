import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/slice_player_controller.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import '../../utils/format_duration.dart';

/// Dictionary-detail renderer for the shared second-decoder slice player.
/// Unlike [SlicePlaybackWindow], this is ordinary document-flow content.
class DictionaryInlineClipPlayer extends StatelessWidget {
  const DictionaryInlineClipPlayer({
    super.key,
    required this.controller,
    required this.occurrence,
    required this.target,
    required this.onClose,
  });

  final SlicePlayerController controller;
  final LexicalOccurrence occurrence;
  final String target;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.store,
    builder: (context, _) {
      final state = controller.state;
      final video = controller.videoController;
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.headphones_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$target · 当前来源切片',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                occurrence.sentenceTextSnapshot,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${occurrence.mediaTitleSnapshot} · '
                '${formatDuration(Duration(milliseconds: occurrence.startMsSnapshot))}–'
                '${formatDuration(Duration(milliseconds: occurrence.endMsSnapshot))}',
                style: const TextStyle(color: ListenColors.muted),
              ),
              const SizedBox(height: 14),
              if (state.error != null)
                Text(
                  state.error!,
                  style: const TextStyle(color: ListenColors.error),
                )
              else if (state.showVideo && video != null)
                SizedBox(
                  height: 320,
                  width: double.infinity,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: video.value.aspectRatio,
                      child: ColoredBox(
                        color: Colors.black,
                        child: VideoPlayer(video),
                      ),
                    ),
                  ),
                )
              else
                const DecoratedBox(
                  decoration: BoxDecoration(color: ListenColors.fog),
                  child: SizedBox(
                    height: 88,
                    child: Center(
                      child: Icon(
                        Icons.graphic_eq,
                        size: 36,
                        color: ListenColors.accent,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    onPressed: state.loading
                        ? null
                        : () => unawaited(controller.replay()),
                    icon: const Icon(Icons.replay),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: state.loading
                        ? null
                        : () => unawaited(controller.togglePlayback()),
                    icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
                    label: Text(state.playing ? '暂停' : '播放'),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: state.loading ? null : controller.toggleLooping,
                    icon: Icon(
                      Icons.repeat,
                      color: state.looping
                          ? ListenColors.accent
                          : ListenColors.muted,
                    ),
                  ),
                  IconButton(
                    onPressed: state.loading ? null : controller.toggleVideo,
                    icon: Icon(
                      state.showVideo
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
