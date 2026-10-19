import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/slice_player_controller.dart';
import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/icon_size.dart';
import '../../theme/listen_theme.dart';
import '../../theme/spacing.dart';
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
    this.onShadowing,
  });

  final SlicePlayerController controller;
  final LexicalOccurrence occurrence;
  final String target;
  final VoidCallback onClose;
  final Future<void> Function()? onShadowing;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.store,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final state = controller.state;
      final renderHandle = controller.renderHandle;
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
                  const SizedBox(width: ListenSpacing.gap8),
                  Expanded(
                    child: Text(
                      l
                          .text('dictionaryClipPlayerTitle')
                          .replaceFirst('{word}', target),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                occurrence.sentenceTextSnapshot,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: ListenSpacing.gap6),
              Text(
                '${occurrence.mediaTitleSnapshot} · '
                '${formatDuration(Duration(milliseconds: occurrence.startMsSnapshot))}–'
                '${formatDuration(Duration(milliseconds: occurrence.endMsSnapshot))}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap12),
              if (state.error != null)
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (state.showVideo && renderHandle != null)
                SizedBox(
                  height: 320,
                  width: double.infinity,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: renderHandle.aspectRatio,
                      child: ColoredBox(
                        color: ListenColors.videoBackdrop,
                        child: switch (renderHandle) {
                          VideoPlayerSliceRenderHandle(:final controller) =>
                            VideoPlayer(controller),
                          _ => const SizedBox.shrink(),
                        },
                      ),
                    ),
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                  ),
                  child: SizedBox(
                    height: 88,
                    child: Center(
                      child: Icon(
                        // Audio-only clip: the icon stands in for the missing
                        // picture rather than labelling a control, so it is
                        // the illustration step.
                        Icons.graphic_eq,
                        size: ListenIconSize.illustration,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: ListenSpacing.gap6),
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
                    label: Text(
                      l.text(
                        state.playing
                            ? 'dictionaryClipPause'
                            : 'dictionaryClipPlay',
                      ),
                    ),
                  ),
                  if (onShadowing != null) ...[
                    const SizedBox(width: ListenSpacing.gap8),
                    OutlinedButton.icon(
                      onPressed: state.loading
                          ? null
                          : () => unawaited(onShadowing!()),
                      icon: const Icon(Icons.mic_none),
                      label: Text(l.text('dictionaryClipShadow')),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    onPressed: state.loading ? null : controller.toggleLooping,
                    icon: Icon(
                      Icons.repeat,
                      color: state.looping
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
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
