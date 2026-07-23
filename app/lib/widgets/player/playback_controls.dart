import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/task_status.dart';
import '../../player_adapter.dart';
import '../../theme/breakpoints.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../../theme/typography.dart';

/// One receded look for both transport progress bars (#30): a thin track that
/// nearly sinks into the bar, where only the played portion and the handle
/// carry the signal teal. Shared so the compact and full forms cannot drift.
SliderThemeData _progressSliderTheme(
  BuildContext context,
  ColorScheme colors,
) => SliderThemeData(
  trackHeight: 3,
  trackShape: const RectangularSliderTrackShape(),
  thumbShape: _GlowThumbShape(
    glowColor: colors.primary.withValues(alpha: 0.33),
    glow: !MediaQuery.highContrastOf(context),
  ),
  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
  activeTrackColor: colors.primary,
  inactiveTrackColor: colors.outlineVariant.withValues(alpha: 0.4),
  thumbColor: colors.primary,
);

/// The transport handle from the charter's dimmed room: a small solid dot
/// with a soft static halo, so progress reads as the one lit thing on an
/// otherwise receded bar. Legibility never depends on the halo — it is pure
/// decoration and high-contrast mode drops it.
class _GlowThumbShape extends RoundSliderThumbShape {
  const _GlowThumbShape({required this.glowColor, required this.glow})
    : super(enabledThumbRadius: 5);

  final Color glowColor;
  final bool glow;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (glow) {
      final halo = Paint()
        ..color = glowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      context.canvas.drawCircle(center, 8, halo);
    }
    super.paint(
      context,
      center,
      activationAnimation: activationAnimation,
      enableAnimation: enableAnimation,
      isDiscrete: isDiscrete,
      labelPainter: labelPainter,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      textDirection: textDirection,
      value: value,
      textScaleFactor: textScaleFactor,
      sizeWithOverflow: sizeWithOverflow,
    );
  }
}

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.adapter,
    required this.position,
    required this.duration,
    required this.playing,
    required this.loopCue,
    this.sourceLoopStart,
    this.sourceLoopLabel,
    required this.statusStylesVisible,
    required this.subtitlesVisible,
    required this.secondarySubtitlesVisible,
    required this.secondarySubtitlesAvailable,
    required this.rate,
    required this.volume,
    required this.muted,
    required this.audioTracks,
    required this.selectedAudioId,
    required this.embeddedSubtitleTracks,
    required this.selectedEmbeddedSubtitleId,
    required this.primarySubtitleOffset,
    required this.secondarySubtitleOffset,
    required this.status,
    this.statusIsError = false,
    required this.taskStatuses,
    required this.extensiveListeningActive,
    this.huntingActive = false,
    required this.listeningMarkEnabled,
    required this.listeningInboxCount,
    required this.onSeek,
    required this.onSeekToPreviousCue,
    required this.onSeekToZero,
    required this.onPlayPause,
    required this.onStop,
    required this.onSeekToNextCue,
    required this.chunkControlsEnabled,
    required this.chunkLoopActive,
    required this.onSeekToPreviousChunk,
    required this.onSeekToNextChunk,
    required this.onLoopCurrentChunk,
    required this.onLoopExpandedChunk,
    required this.onLoopCueChanged,
    required this.onStopSourceLoop,
    required this.onStatusStylesChanged,
    required this.onSubtitlesVisibleChanged,
    required this.onSecondaryVisibleChanged,
    required this.onRateChanged,
    required this.onVolumeChanged,
    required this.onMuteToggle,
    required this.onAudioTrackChanged,
    required this.onEmbeddedSubtitleTrackChanged,
    required this.onPrimaryOffsetChanged,
    required this.onSecondaryOffsetChanged,
    required this.onToggleExtensiveListening,
    this.onToggleHunting,
    required this.onCaptureListeningInbox,
    required this.onHardInterruptListening,
    this.isCompact = false,
    this.mediaTitle,
    this.onExpand,
  });

  final DesktopPlayerAdapter adapter;

  /// Live playback position. Only the progress slider and the time labels
  /// subscribe to it, so 10Hz ticks never rebuild the rest of the bar.
  final ValueListenable<Duration> position;
  final Duration duration;
  final bool playing;
  final bool loopCue;
  final Duration? sourceLoopStart;
  final String? sourceLoopLabel;
  final bool statusStylesVisible;
  final bool subtitlesVisible;
  final bool secondarySubtitlesVisible;
  final bool secondarySubtitlesAvailable;
  final double rate;
  final double volume;
  final bool muted;
  final List<PlayerTrack> audioTracks;
  final String? selectedAudioId;
  final List<PlayerTrack> embeddedSubtitleTracks;
  final String? selectedEmbeddedSubtitleId;
  final Duration primarySubtitleOffset;
  final Duration secondarySubtitleOffset;
  final String status;

  /// Error statuses render in the error color with a leading icon.
  final bool statusIsError;
  final List<UserTaskStatus> taskStatuses;
  final bool extensiveListeningActive;
  final bool huntingActive;
  final bool listeningMarkEnabled;
  final int listeningInboxCount;
  final bool chunkControlsEnabled;
  final bool chunkLoopActive;

  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekToPreviousCue;
  final VoidCallback onSeekToZero;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onSeekToNextCue;
  final VoidCallback onSeekToPreviousChunk;
  final VoidCallback onSeekToNextChunk;
  final VoidCallback onLoopCurrentChunk;
  final VoidCallback onLoopExpandedChunk;
  final ValueChanged<bool> onLoopCueChanged;
  final VoidCallback onStopSourceLoop;
  final ValueChanged<bool> onStatusStylesChanged;
  final ValueChanged<bool> onSubtitlesVisibleChanged;
  final ValueChanged<bool> onSecondaryVisibleChanged;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMuteToggle;
  final ValueChanged<PlayerTrack> onAudioTrackChanged;
  final ValueChanged<PlayerTrack> onEmbeddedSubtitleTrackChanged;
  final ValueChanged<Duration> onPrimaryOffsetChanged;
  final ValueChanged<Duration> onSecondaryOffsetChanged;
  final VoidCallback onToggleExtensiveListening;
  final VoidCallback? onToggleHunting;
  final VoidCallback onCaptureListeningInbox;
  final VoidCallback onHardInterruptListening;
  final bool isCompact;
  final String? mediaTitle;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    if (isCompact) return _buildCompact(context, l, colors);
    return _buildFull(context, l, colors);
  }

  Widget _buildCompact(
    BuildContext context,
    AppLocalizations l,
    ColorScheme colors,
  ) {
    final maxMs = duration.inMilliseconds.clamp(1, 1 << 31).toDouble();
    return Material(
      color: colors.surfaceContainerLowest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow =
                constraints.maxWidth < ListenBreakpoints.playbackControlsNarrow;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 12,
                  child: SliderTheme(
                    data: _progressSliderTheme(context, colors),
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: position,
                      builder: (context, positionValue, _) => Slider(
                        padding: EdgeInsets.zero,
                        value: positionValue.inMilliseconds
                            .clamp(0, maxMs.toInt())
                            .toDouble(),
                        max: maxMs,
                        onChanged: (value) =>
                            onSeek(Duration(milliseconds: value.round())),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 76,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(narrow ? 12 : 20, 4, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            key: const Key('compact-player-media-info'),
                            onTap: onExpand,
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colors.primaryContainer,
                                  ),
                                  child: Icon(
                                    playing
                                        ? Icons.equalizer_rounded
                                        : Icons.music_note_rounded,
                                    size: 23,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(width: ListenSpacing.gap12),
                                Flexible(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mediaTitle ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(
                                        height: ListenSpacing.gap2,
                                      ),
                                      ValueListenableBuilder<Duration>(
                                        valueListenable: position,
                                        builder: (context, positionValue, _) =>
                                            Text(
                                              '${formatDuration(positionValue)} / ${formatDuration(duration)}',
                                              maxLines: 1,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l.text('previousSentence'),
                          onPressed: onSeekToPreviousCue,
                          iconSize: 24,
                          color: colors.onSurfaceVariant,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: IconButton.filled(
                            key: const Key('compact-player-play-pause'),
                            tooltip: l.text('playPause'),
                            onPressed: onPlayPause,
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l.text('nextSentence'),
                          onPressed: onSeekToNextCue,
                          iconSize: 24,
                          color: colors.onSurfaceVariant,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        if (!narrow) ...[
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${rate}x',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                                IconButton(
                                  tooltip: muted ? 'Unmute' : 'Mute',
                                  onPressed: onMuteToggle,
                                  iconSize: 21,
                                  icon: Icon(
                                    muted
                                        ? Icons.volume_off_outlined
                                        : Icons.volume_up_outlined,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                IconButton(
                                  tooltip: l.text('expandWorkbench'),
                                  onPressed: onExpand,
                                  iconSize: 22,
                                  icon: Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (narrow)
                          IconButton(
                            tooltip: l.text('expandWorkbench'),
                            onPressed: onExpand,
                            iconSize: 22,
                            icon: Icon(
                              Icons.keyboard_arrow_up_rounded,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFull(
    BuildContext context,
    AppLocalizations l,
    ColorScheme colors,
  ) {
    return Material(
      color: colors.surfaceContainerLowest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final roomy =
                constraints.maxWidth >= ListenBreakpoints.playbackControlsRoomy;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 38,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: position,
                      builder: (context, positionValue, _) => Row(
                        children: [
                          SizedBox(
                            // Fits HH:MM:SS in the mono timecode face.
                            width: 62,
                            child: Text(
                              formatDuration(positionValue),
                              style: ListenType.timecode.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: _progressSliderTheme(context, colors),
                              child: Slider(
                                value: positionValue.inMilliseconds
                                    .clamp(
                                      0,
                                      duration.inMilliseconds.clamp(1, 1 << 31),
                                    )
                                    .toDouble(),
                                max: duration.inMilliseconds
                                    .clamp(1, 1 << 31)
                                    .toDouble(),
                                onChanged: (value) => onSeek(
                                  Duration(milliseconds: value.round()),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            // Fits HH:MM:SS in the mono timecode face.
                            width: 62,
                            child: Text(
                              formatDuration(duration),
                              textAlign: TextAlign.end,
                              style: ListenType.timecode.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 58,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _fullControlRow(context, l, roomy),
                  ),
                ),
                if (sourceLoopStart != null ||
                    taskStatuses.isNotEmpty ||
                    status.isNotEmpty)
                  SizedBox(
                    height: 28,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                      child: Row(
                        children: [
                          if (sourceLoopStart != null)
                            _SourceLoopChip(
                              label: sourceLoopLabel != null
                                  ? l.text(sourceLoopLabel!)
                                  : l.text('loopRange'),
                              onStop: onStopSourceLoop,
                            ),
                          const Spacer(),
                          if (taskStatuses.isNotEmpty)
                            Flexible(
                              child: Wrap(
                                spacing: 6,
                                children: [
                                  for (final task in taskStatuses)
                                    _TaskStatusChip(status: task),
                                ],
                              ),
                            ),
                          if (taskStatuses.isNotEmpty && status.isNotEmpty)
                            const SizedBox(width: ListenSpacing.gap8),
                          if (status.isNotEmpty)
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (statusIsError) ...[
                                    Icon(
                                      Icons.error_outline,
                                      size: 13,
                                      color: colors.error,
                                    ),
                                    const SizedBox(width: ListenSpacing.gap4),
                                  ],
                                  Flexible(
                                    child: Text(
                                      status,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: statusIsError
                                                ? colors.error
                                                : colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _fullControlRow(BuildContext context, AppLocalizations l, bool roomy) {
    final colors = Theme.of(context).colorScheme;
    // Shell recedes (#30): secondary transport steps drop to the variant
    // shade; the play button is the one lit control on this bar.
    return Row(
      children: [
        IconButton(
          tooltip: l.text('previousSentence'),
          onPressed: onSeekToPreviousCue,
          color: colors.onSurfaceVariant,
          icon: const Icon(Icons.skip_previous),
        ),
        if (roomy)
          IconButton(
            tooltip: l.text('restartMedia'),
            onPressed: onSeekToZero,
            color: colors.onSurfaceVariant,
            icon: const Icon(Icons.restart_alt),
          ),
        IconButton.filled(
          tooltip: l.text('playPause'),
          onPressed: onPlayPause,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          tooltip: l.text('nextSentence'),
          onPressed: onSeekToNextCue,
          color: colors.onSurfaceVariant,
          icon: const Icon(Icons.skip_next),
        ),
        const SizedBox(width: ListenSpacing.gap8),
        _ToggleIcon(
          tooltip: l.text('loopSentence'),
          selected: loopCue,
          onPressed: () => onLoopCueChanged(!loopCue),
          icon: Icons.repeat_one,
        ),
        if (roomy) ...[
          const SizedBox(width: ListenSpacing.gap8),
          _PlaybackMenuButton(
            tooltip: l.text('listeningMode'),
            label: l.text('listeningMode'),
            icon: extensiveListeningActive
                ? Icons.hearing
                : Icons.hearing_outlined,
            selected: extensiveListeningActive,
            badgeCount: listeningInboxCount,
            onSelected: (value) {
              if (value == 'toggle-listening') {
                onToggleExtensiveListening();
              }
              if (value == 'toggle-hunting') onToggleHunting?.call();
              if (value == 'mark-inbox') onCaptureListeningInbox();
              if (value == 'hard-interrupt') onHardInterruptListening();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle-listening',
                child: _PlaybackMenuRow(
                  icon: extensiveListeningActive
                      ? Icons.hearing
                      : Icons.hearing_outlined,
                  title: extensiveListeningActive
                      ? l.text('finishExtensiveListening')
                      : l.text('startExtensiveListening'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle-hunting',
                enabled: listeningMarkEnabled && onToggleHunting != null,
                child: _PlaybackMenuRow(
                  icon: huntingActive ? Icons.gps_fixed : Icons.gps_not_fixed,
                  title: huntingActive
                      ? l.text('huntingStopMode')
                      : l.text('huntingStartMode'),
                ),
              ),
              PopupMenuItem(
                value: 'mark-inbox',
                enabled: listeningMarkEnabled && onToggleHunting != null,
                child: _PlaybackMenuRow(
                  icon: Icons.bookmark_add_outlined,
                  title: l.text('markListeningInbox'),
                  trailing: listeningInboxCount > 0
                      ? '$listeningInboxCount'
                      : null,
                ),
              ),
              PopupMenuItem(
                value: 'hard-interrupt',
                enabled: listeningMarkEnabled,
                child: _PlaybackMenuRow(
                  icon: Icons.pause_circle_outline,
                  title: l.text('hardInterruptListening'),
                ),
              ),
            ],
          ),
          _PlaybackMenuButton(
            tooltip: l.text('chunkMode'),
            label: l.text('chunkMode'),
            icon: Icons.segment,
            selected: chunkLoopActive,
            enabled: chunkControlsEnabled,
            onSelected: (value) {
              if (value == 'previous-chunk') onSeekToPreviousChunk();
              if (value == 'loop-chunk') onLoopCurrentChunk();
              if (value == 'next-chunk') onSeekToNextChunk();
              if (value == 'expand-chunk') onLoopExpandedChunk();
              if (value == 'stop-source-loop') onStopSourceLoop();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'previous-chunk',
                child: _PlaybackMenuRow(
                  icon: Icons.keyboard_double_arrow_left,
                  title: l.text('previousChunk'),
                ),
              ),
              PopupMenuItem(
                value: 'loop-chunk',
                child: _PlaybackMenuRow(
                  icon: Icons.segment,
                  title: l.text('loopChunk'),
                ),
              ),
              PopupMenuItem(
                value: 'next-chunk',
                child: _PlaybackMenuRow(
                  icon: Icons.keyboard_double_arrow_right,
                  title: l.text('nextChunk'),
                ),
              ),
              PopupMenuItem(
                value: 'expand-chunk',
                child: _PlaybackMenuRow(
                  icon: Icons.unfold_more,
                  title: l.text('expandChunk'),
                ),
              ),
              if (sourceLoopStart != null) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'stop-source-loop',
                  child: _PlaybackMenuRow(
                    icon: Icons.stop_circle_outlined,
                    title: l.text('stopSourceLoop'),
                  ),
                ),
              ],
            ],
          ),
          _PlaybackMenuButton(
            tooltip: l.text('subtitleMode'),
            label: l.text('subtitleMode'),
            icon: Icons.subtitles_outlined,
            selected: subtitlesVisible || statusStylesVisible,
            onSelected: (value) {
              if (value == 'toggle-primary') {
                onSubtitlesVisibleChanged(!subtitlesVisible);
              }
              if (value == 'toggle-secondary') {
                onSecondaryVisibleChanged(!secondarySubtitlesVisible);
              }
              if (value == 'toggle-status-styles') {
                onStatusStylesChanged(!statusStylesVisible);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle-primary',
                child: _PlaybackMenuRow(
                  icon: subtitlesVisible
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  title: l.text('subtitles'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle-secondary',
                enabled: secondarySubtitlesAvailable,
                child: _PlaybackMenuRow(
                  icon: secondarySubtitlesVisible
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  title: l.text('secondary'),
                  subtitle: secondarySubtitlesAvailable
                      ? null
                      : l.text('secondarySubtitleUnavailable'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle-status-styles',
                child: _PlaybackMenuRow(
                  icon: statusStylesVisible
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  title: l.text('wordStyles'),
                ),
              ),
            ],
          ),
        ] else
          PopupMenuButton<String>(
            tooltip: l.text('moreActions'),
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              switch (value) {
                case 'toggle-listening':
                  onToggleExtensiveListening();
                case 'toggle-hunting':
                  onToggleHunting?.call();
                case 'mark-inbox':
                  onCaptureListeningInbox();
                case 'hard-interrupt':
                  onHardInterruptListening();
                case 'previous-chunk':
                  onSeekToPreviousChunk();
                case 'loop-chunk':
                  onLoopCurrentChunk();
                case 'next-chunk':
                  onSeekToNextChunk();
                case 'expand-chunk':
                  onLoopExpandedChunk();
                case 'stop-source-loop':
                  onStopSourceLoop();
                case 'toggle-primary':
                  onSubtitlesVisibleChanged(!subtitlesVisible);
                case 'toggle-secondary':
                  onSecondaryVisibleChanged(!secondarySubtitlesVisible);
                case 'toggle-status-styles':
                  onStatusStylesChanged(!statusStylesVisible);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  l.text('listeningMode'),
                  style: ListenType.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'toggle-listening',
                child: _PlaybackMenuRow(
                  icon: extensiveListeningActive
                      ? Icons.hearing
                      : Icons.hearing_outlined,
                  title: extensiveListeningActive
                      ? l.text('finishExtensiveListening')
                      : l.text('startExtensiveListening'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle-hunting',
                enabled: listeningMarkEnabled,
                child: _PlaybackMenuRow(
                  icon: huntingActive ? Icons.gps_fixed : Icons.gps_not_fixed,
                  title: huntingActive
                      ? l.text('huntingStopMode')
                      : l.text('huntingStartMode'),
                ),
              ),
              PopupMenuItem(
                value: 'mark-inbox',
                enabled: listeningMarkEnabled,
                child: _PlaybackMenuRow(
                  icon: Icons.bookmark_add_outlined,
                  title: l.text('markListeningInbox'),
                  trailing: listeningInboxCount > 0
                      ? '$listeningInboxCount'
                      : null,
                ),
              ),
              PopupMenuItem(
                value: 'hard-interrupt',
                enabled: listeningMarkEnabled,
                child: _PlaybackMenuRow(
                  icon: Icons.pause_circle_outline,
                  title: l.text('hardInterruptListening'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: false,
                child: Text(
                  l.text('chunkMode'),
                  style: ListenType.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'previous-chunk',
                enabled: chunkControlsEnabled,
                child: _PlaybackMenuRow(
                  icon: Icons.keyboard_double_arrow_left,
                  title: l.text('previousChunk'),
                ),
              ),
              PopupMenuItem(
                value: 'loop-chunk',
                enabled: chunkControlsEnabled,
                child: _PlaybackMenuRow(
                  icon: Icons.segment,
                  title: l.text('loopChunk'),
                ),
              ),
              PopupMenuItem(
                value: 'next-chunk',
                enabled: chunkControlsEnabled,
                child: _PlaybackMenuRow(
                  icon: Icons.keyboard_double_arrow_right,
                  title: l.text('nextChunk'),
                ),
              ),
              PopupMenuItem(
                value: 'expand-chunk',
                enabled: chunkControlsEnabled,
                child: _PlaybackMenuRow(
                  icon: Icons.unfold_more,
                  title: l.text('expandChunk'),
                ),
              ),
              if (sourceLoopStart != null) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'stop-source-loop',
                  child: _PlaybackMenuRow(
                    icon: Icons.stop_circle_outlined,
                    title: l.text('stopSourceLoop'),
                  ),
                ),
              ],
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: false,
                child: Text(
                  l.text('subtitleMode'),
                  style: ListenType.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'toggle-primary',
                child: _PlaybackMenuRow(
                  icon: subtitlesVisible
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  title: l.text('subtitles'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle-secondary',
                enabled: secondarySubtitlesAvailable,
                child: _PlaybackMenuRow(
                  icon: secondarySubtitlesVisible
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  title: l.text('secondary'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle-status-styles',
                child: _PlaybackMenuRow(
                  icon: statusStylesVisible
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  title: l.text('wordStyles'),
                ),
              ),
            ],
          ),
        const Spacer(),
        DropdownButtonHideUnderline(
          child: DropdownButton<double>(
            value: rate,
            borderRadius: ListenRadii.controlBorder,
            items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text('${value}x')),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onRateChanged(value);
            },
          ),
        ),
        IconButton(
          tooltip: muted ? 'Unmute' : 'Mute',
          onPressed: onMuteToggle,
          icon: Icon(
            muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          ),
        ),
        IconButton(
          tooltip: l.text('playbackSettings'),
          onPressed: () => _showPlaybackSettings(context),
          icon: const Icon(Icons.tune),
        ),
      ],
    );
  }

  Future<void> _showPlaybackSettings(BuildContext context) async {
    final l = AppLocalizations.of(context);
    var localWordStyles = statusStylesVisible;
    var localSubtitles = subtitlesVisible;
    var localSecondary = secondarySubtitlesVisible;
    var localVolume = volume;
    var localRate = rate;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l.text('playbackSettings')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: localWordStyles,
                    title: Text(l.text('wordStyles')),
                    onChanged: (value) {
                      setDialogState(() => localWordStyles = value);
                      onStatusStylesChanged(value);
                    },
                  ),
                  SwitchListTile(
                    value: localSubtitles,
                    title: Text(l.text('subtitles')),
                    onChanged: (value) {
                      setDialogState(() => localSubtitles = value);
                      onSubtitlesVisibleChanged(value);
                    },
                  ),
                  SwitchListTile(
                    value: secondarySubtitlesAvailable && localSecondary,
                    title: Text(l.text('secondarySubtitle')),
                    onChanged: secondarySubtitlesAvailable
                        ? (value) {
                            setDialogState(() => localSecondary = value);
                            onSecondaryVisibleChanged(value);
                          }
                        : null,
                  ),
                  ListTile(
                    title: Text(l.text('rate')),
                    trailing: DropdownButton<double>(
                      value: localRate,
                      items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('${value}x'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => localRate = value);
                        onRateChanged(value);
                      },
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      muted ? Icons.volume_off : Icons.volume_up_outlined,
                    ),
                    title: Slider(
                      value: localVolume,
                      max: 100,
                      onChanged: (value) {
                        setDialogState(() => localVolume = value);
                        onVolumeChanged(value);
                      },
                    ),
                  ),
                  if (audioTracks.length > 1)
                    _TrackSelector(
                      label: l.text('audioTrack'),
                      tracks: audioTracks,
                      selectedId: selectedAudioId,
                      onChanged: onAudioTrackChanged,
                    ),
                  if (embeddedSubtitleTracks.isNotEmpty)
                    _TrackSelector(
                      label: l.text('embeddedSubtitles'),
                      tracks: embeddedSubtitleTracks,
                      selectedId: selectedEmbeddedSubtitleId,
                      onChanged: onEmbeddedSubtitleTrackChanged,
                    ),
                  _OffsetControl(
                    label: l.text('primaryOffset'),
                    value: primarySubtitleOffset,
                    enabled: true,
                    onChanged: onPrimaryOffsetChanged,
                  ),
                  _OffsetControl(
                    label: l.text('secondaryOffset'),
                    value: secondarySubtitleOffset,
                    enabled: secondarySubtitlesAvailable,
                    onChanged: onSecondaryOffsetChanged,
                  ),
                  if (sourceLoopStart != null)
                    ListTile(
                      leading: const Icon(Icons.stop_circle_outlined),
                      title: Text(l.text('stopSourceLoop')),
                      onTap: () {
                        onStopSourceLoop();
                        Navigator.of(context).pop();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.stop),
                    title: Text(l.text('stop')),
                    onTap: () {
                      onStop();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.text('close')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackMenuButton extends StatelessWidget {
  const _PlaybackMenuButton({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
    required this.itemBuilder,
    this.enabled = true,
    this.badgeCount = 0,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final int badgeCount;
  final PopupMenuItemSelected<String> onSelected;
  final PopupMenuItemBuilder<String> itemBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Unselected toggles sit with the shell (variant shade); only a selected
    // state carries the signal teal (#30).
    final foreground = enabled
        ? selected
              ? colors.primary
              : colors.onSurfaceVariant
        : colors.onSurfaceVariant.withValues(alpha: 0.55);
    final iconWidget = Icon(icon, size: 18, color: foreground);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: PopupMenuButton<String>(
        tooltip: tooltip,
        enabled: enabled,
        onSelected: onSelected,
        itemBuilder: itemBuilder,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerLow,
            borderRadius: ListenRadii.controlBorder,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge.count(
                  count: badgeCount,
                  isLabelVisible: badgeCount > 0,
                  child: iconWidget,
                ),
                const SizedBox(width: ListenSpacing.gap6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: ListenSpacing.gap2),
                Icon(Icons.arrow_drop_down, size: 18, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackMenuRow extends StatelessWidget {
  const _PlaybackMenuRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 250),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: ListenSpacing.gap12),
            Text(
              trailing!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    isSelected: selected,
    onPressed: onPressed,
    // Unselected toggles recede with the shell; selection is what lights up.
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    icon: Icon(icon),
    selectedIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
    style: selected
        ? IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          )
        : null,
  );
}

class _TrackSelector extends StatelessWidget {
  const _TrackSelector({
    required this.label,
    required this.tracks,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<PlayerTrack> tracks;
  final String? selectedId;
  final ValueChanged<PlayerTrack> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    trailing: DropdownButton<String>(
      value: tracks.any((track) => track.id == selectedId) ? selectedId : null,
      items: tracks
          .map(
            (track) => DropdownMenuItem(
              value: track.id,
              child: Text(track.title ?? track.language ?? track.id),
            ),
          )
          .toList(growable: false),
      onChanged: (id) {
        final matches = tracks.where((track) => track.id == id);
        if (matches.isNotEmpty) onChanged(matches.first);
      },
    ),
  );
}

class _OffsetControl extends StatelessWidget {
  const _OffsetControl({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final Duration value;
  final bool enabled;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    subtitle: Text('${value.inMilliseconds} ms'),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: enabled
              ? () => onChanged(value - const Duration(milliseconds: 100))
              : null,
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          onPressed: enabled
              ? () => onChanged(value + const Duration(milliseconds: 100))
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
  );
}

class _SourceLoopChip extends StatelessWidget {
  const _SourceLoopChip({required this.label, required this.onStop});

  final String label;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.15),
        borderRadius: ListenRadii.controlBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.loop,
              size: 13,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: ListenSpacing.gap4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            SizedBox(
              width: 22,
              height: 22,
              child: IconButton(
                onPressed: onStop,
                padding: EdgeInsets.zero,
                iconSize: 14,
                icon: Icon(
                  Icons.close,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                tooltip: AppLocalizations.of(context).text('stopSourceLoop'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskStatusChip extends StatelessWidget {
  const _TaskStatusChip({required this.status});

  final UserTaskStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = _stateColor(Theme.of(context).colorScheme, status.state);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: ListenRadii.controlBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          '${l.text(status.titleKey)} · ${status.progress.clamp(0, 100)}%',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }

  Color _stateColor(ColorScheme colors, UserTaskState state) => switch (state) {
    UserTaskState.working => colors.tertiary,
    UserTaskState.success => colors.primary,
    UserTaskState.warning => colors.secondary,
    UserTaskState.error => colors.error,
    UserTaskState.cancelled => colors.onSurfaceVariant,
    UserTaskState.unknown => colors.onSurfaceVariant,
  };
}
