import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/slice_player_controller.dart';
import '../../localization.dart';
import '../../theme/listen_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// A transient, independent playback surface for one vocabulary source clip.
/// It is mounted in the workbench stack just like the practice window, but it
/// owns neither practice state nor the primary player.
class SlicePlaybackWindow extends StatefulWidget {
  const SlicePlaybackWindow({
    super.key,
    required this.controller,
    required this.onClose,
    this.onShadowing,
  });

  final SlicePlayerController controller;
  final Future<void> Function() onClose;
  final Future<void> Function(SlicePlayerState state)? onShadowing;

  @override
  State<SlicePlaybackWindow> createState() => _SlicePlaybackWindowState();
}

class _SlicePlaybackWindowState extends State<SlicePlaybackWindow> {
  Offset _offset = const Offset(44, 48);

  AppLocalizations get l => AppLocalizations.of(context);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final state = widget.controller.state;
    final wantsVideo =
        state.showVideo && widget.controller.videoController != null;
    final width = math.min(560.0, math.max(320.0, size.width - 32));
    final targetHeight = wantsVideo ? 500.0 : 318.0;
    final height = math.min(targetHeight, math.max(270.0, size.height - 32));
    final left = _offset.dx.clamp(
      16.0,
      math.max(16.0, size.width - width - 16),
    );
    final top = _offset.dy.clamp(
      16.0,
      math.max(16.0, size.height - height - 16),
    );
    return Positioned(
      left: left.toDouble(),
      top: top.toDouble(),
      width: width,
      height: height,
      child: Material(
        elevation: 18,
        borderRadius: ListenRadii.panelBorder,
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            _titleBar(size, width, height),
            const Divider(height: 1),
            Expanded(child: _body(wantsVideo)),
            const Divider(height: 1),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _titleBar(
    Size viewport,
    double width,
    double height,
  ) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanUpdate: (details) => setState(() {
      _offset += details.delta;
      _offset = Offset(
        _offset.dx.clamp(16.0, math.max(16.0, viewport.width - width - 16)),
        _offset.dy.clamp(16.0, math.max(16.0, viewport.height - height - 16)),
      );
    }),
    child: SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 6),
        child: Row(
          children: [
            const Icon(Icons.headphones_outlined, size: 20),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: Text(
                widget.controller.state.wordForm?.isNotEmpty == true
                    ? '${widget.controller.state.wordForm} · ${l.text('slicePlayback')}'
                    : l.text('slicePlayback'),
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => unawaited(widget.onClose()),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _body(bool wantsVideo) {
    final state = widget.controller.state;
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            state.error == 'This source clip has an invalid time range'
                ? l.text('slicePlaybackInvalidRange')
                : state.error!,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          state.sentence ?? l.text('slicePlaybackNoSentence'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: ListenSpacing.gap8),
        Text(
          '${state.mediaTitle ?? l.text('slicePlaybackSourceMedia')} · ${_time(state.start)}–${_time(state.end)}',
          style: ListenType.body.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: ListenSpacing.gap16),
        if (wantsVideo)
          _videoSurface(widget.controller.videoController!)
        else
          _audioSurface(),
      ],
    );
  }

  Widget _audioSurface() => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: ListenRadii.surfaceBorder,
    ),
    child: SizedBox(
      height: 110,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.graphic_eq,
              size: 34,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: ListenSpacing.gap8),
            Text(l.text('slicePlaybackAudioFirst')),
          ],
        ),
      ),
    ),
  );

  Widget _videoSurface(VideoPlayerController controller) => AspectRatio(
    aspectRatio: controller.value.aspectRatio,
    child: ClipRRect(
      borderRadius: ListenRadii.surfaceBorder,
      child: ColoredBox(
        color: ListenColors.videoBackdrop,
        child: VideoPlayer(controller),
      ),
    ),
  );

  Widget _controls() {
    final state = widget.controller.state;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: l.text('slicePlaybackReplay'),
            onPressed: state.loading
                ? null
                : () => unawaited(widget.controller.replay()),
            icon: const Icon(Icons.replay),
          ),
          FilledButton.tonalIcon(
            onPressed: state.loading
                ? null
                : () => unawaited(widget.controller.togglePlayback()),
            icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
            label: Text(
              state.playing
                  ? l.text('slicePlaybackPause')
                  : l.text('slicePlaybackPlay'),
            ),
          ),
          if (widget.onShadowing != null) ...[
            const SizedBox(width: ListenSpacing.gap8),
            OutlinedButton.icon(
              onPressed: state.loading || state.error != null
                  ? null
                  : () => unawaited(widget.onShadowing!(state)),
              icon: const Icon(Icons.mic_none),
              label: Text(l.text('shadowPosture')),
            ),
          ],
          const Spacer(),
          IconButton(
            tooltip: state.looping
                ? l.text('slicePlaybackLooping')
                : l.text('slicePlaybackPlayOnce'),
            onPressed: state.loading ? null : widget.controller.toggleLooping,
            icon: Icon(
              Icons.repeat,
              color: state.looping
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: state.showVideo
                ? l.text('slicePlaybackHideVideo')
                : l.text('slicePlaybackShowVideo'),
            onPressed: state.loading ? null : widget.controller.toggleVideo,
            icon: Icon(
              state.showVideo
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
    );
  }

  String _time(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
