import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/task_status.dart';
import '../../player_adapter.dart';
import '../../theme/listen_theme.dart';
import '../../utils/format_duration.dart';

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.adapter,
    required this.position,
    required this.duration,
    required this.playing,
    required this.loopCue,
    this.sourceLoopStart,
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
    required this.taskStatuses,
    required this.extensiveListeningActive,
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
    required this.onCaptureListeningInbox,
    required this.onHardInterruptListening,
  });

  final DesktopPlayerAdapter adapter;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool loopCue;
  final Duration? sourceLoopStart;
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
  final List<UserTaskStatus> taskStatuses;
  final bool extensiveListeningActive;
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
  final VoidCallback onCaptureListeningInbox;
  final VoidCallback onHardInterruptListening;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final roomy = constraints.maxWidth >= 1080;
            final veryRoomy = constraints.maxWidth >= 1320;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 38,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 54,
                          child: Text(
                            formatDuration(position),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: position.inMilliseconds
                                .clamp(
                                  0,
                                  duration.inMilliseconds.clamp(1, 1 << 31),
                                )
                                .toDouble(),
                            max: duration.inMilliseconds
                                .clamp(1, 1 << 31)
                                .toDouble(),
                            onChanged: (value) =>
                                onSeek(Duration(milliseconds: value.round())),
                          ),
                        ),
                        SizedBox(
                          width: 54,
                          child: Text(
                            formatDuration(duration),
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 58,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: l.text('previousSentence'),
                          onPressed: onSeekToPreviousCue,
                          icon: const Icon(Icons.skip_previous),
                        ),
                        if (roomy)
                          IconButton(
                            tooltip: l.text('restartMedia'),
                            onPressed: onSeekToZero,
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
                          icon: const Icon(Icons.skip_next),
                        ),
                        const SizedBox(width: 8),
                        _ToggleIcon(
                          tooltip: l.text('loopSentence'),
                          selected: loopCue,
                          onPressed: () => onLoopCueChanged(!loopCue),
                          icon: Icons.repeat_one,
                        ),
                        if (roomy) ...[
                          IconButton(
                            tooltip: extensiveListeningActive
                                ? l.text('finishExtensiveListening')
                                : l.text('startExtensiveListening'),
                            onPressed: onToggleExtensiveListening,
                            icon: Icon(
                              extensiveListeningActive
                                  ? Icons.hearing
                                  : Icons.hearing_disabled,
                            ),
                          ),
                          IconButton(
                            tooltip: l.text('markListeningInbox'),
                            onPressed: listeningMarkEnabled
                                ? onCaptureListeningInbox
                                : null,
                            icon: Badge.count(
                              count: listeningInboxCount,
                              isLabelVisible: listeningInboxCount > 0,
                              child: const Icon(Icons.bookmark_add_outlined),
                            ),
                          ),
                          IconButton(
                            tooltip: l.text('hardInterruptListening'),
                            onPressed: listeningMarkEnabled
                                ? onHardInterruptListening
                                : null,
                            icon: const Icon(Icons.pause_circle_outline),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: l.text('previousChunk'),
                            onPressed: chunkControlsEnabled
                                ? onSeekToPreviousChunk
                                : null,
                            icon: const Icon(Icons.keyboard_double_arrow_left),
                          ),
                          _ToggleIcon(
                            tooltip: l.text('loopChunk'),
                            selected: chunkLoopActive,
                            onPressed: chunkControlsEnabled
                                ? onLoopCurrentChunk
                                : null,
                            icon: Icons.segment,
                          ),
                          IconButton(
                            tooltip: l.text('nextChunk'),
                            onPressed: chunkControlsEnabled
                                ? onSeekToNextChunk
                                : null,
                            icon: const Icon(Icons.keyboard_double_arrow_right),
                          ),
                          if (veryRoomy)
                            IconButton(
                              tooltip: l.text('expandChunk'),
                              onPressed: chunkControlsEnabled
                                  ? onLoopExpandedChunk
                                  : null,
                              icon: const Icon(Icons.unfold_more),
                            ),
                        ] else
                          IconButton(
                            tooltip: l.text('markListeningInbox'),
                            onPressed: listeningMarkEnabled
                                ? onCaptureListeningInbox
                                : null,
                            icon: Badge.count(
                              count: listeningInboxCount,
                              isLabelVisible: listeningInboxCount > 0,
                              child: const Icon(Icons.bookmark_add_outlined),
                            ),
                          ),
                        const Spacer(),
                        _ToggleIcon(
                          tooltip: l.text('subtitles'),
                          selected: subtitlesVisible,
                          onPressed: () =>
                              onSubtitlesVisibleChanged(!subtitlesVisible),
                          icon: Icons.subtitles_outlined,
                        ),
                        if (roomy)
                          _ToggleIcon(
                            tooltip: secondarySubtitlesAvailable
                                ? l.text('secondary')
                                : l.text('secondarySubtitleUnavailable'),
                            selected:
                                secondarySubtitlesAvailable &&
                                secondarySubtitlesVisible,
                            onPressed: secondarySubtitlesAvailable
                                ? () => onSecondaryVisibleChanged(
                                    !secondarySubtitlesVisible,
                                  )
                                : null,
                            icon: Icons.closed_caption_outlined,
                          ),
                        const SizedBox(width: 4),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<double>(
                            value: rate,
                            borderRadius: BorderRadius.circular(8),
                            items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('${value}x'),
                                  ),
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
                            muted
                                ? Icons.volume_off_outlined
                                : Icons.volume_up_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: l.text('playbackSettings'),
                          onPressed: () => _showPlaybackSettings(context),
                          icon: const Icon(Icons.tune),
                        ),
                      ],
                    ),
                  ),
                ),
                if (taskStatuses.isNotEmpty || status.isNotEmpty)
                  SizedBox(
                    height: 28,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
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
                            const SizedBox(width: 8),
                          if (status.isNotEmpty)
                            Flexible(
                              child: Text(
                                status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
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

  Future<void> _showPlaybackSettings(BuildContext context) async {
    final l = AppLocalizations.of(context);
    var localWordStyles = statusStylesVisible;
    var localSubtitles = subtitlesVisible;
    var localSecondary = secondarySubtitlesVisible;
    var localVolume = volume;
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
                      value: rate,
                      items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('${value}x'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) onRateChanged(value);
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

class _TaskStatusChip extends StatelessWidget {
  const _TaskStatusChip({required this.status});

  final UserTaskStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = _stateColor(status.state);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
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

  Color _stateColor(UserTaskState state) => switch (state) {
    UserTaskState.working => ListenColors.info,
    UserTaskState.success => ListenColors.primary,
    UserTaskState.warning => ListenColors.accent,
    UserTaskState.error => ListenColors.error,
    UserTaskState.cancelled => ListenColors.muted,
    UserTaskState.unknown => ListenColors.muted,
  };
}
