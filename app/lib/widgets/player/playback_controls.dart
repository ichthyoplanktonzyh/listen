import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/task_status.dart';
import '../../player_adapter.dart';
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: const Color(0xff11161c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Text(formatDuration(position)),
                Expanded(
                  child: Slider(
                    value: position.inMilliseconds
                        .clamp(0, duration.inMilliseconds.clamp(1, 1 << 31))
                        .toDouble(),
                    max: duration.inMilliseconds.clamp(1, 1 << 31).toDouble(),
                    onChanged: (value) =>
                        onSeek(Duration(milliseconds: value.round())),
                  ),
                ),
                Text(formatDuration(duration)),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    tooltip: l.text('previousSentence'),
                    onPressed: onSeekToPreviousCue,
                    icon: const Icon(Icons.skip_previous),
                  ),
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
                    tooltip: l.text('stop'),
                    onPressed: onStop,
                    icon: const Icon(Icons.stop),
                  ),
                  IconButton(
                    tooltip: l.text('nextSentence'),
                    onPressed: onSeekToNextCue,
                    icon: const Icon(Icons.skip_next),
                  ),
                  FilterChip(
                    label: Text(l.text('loopSentence')),
                    selected: loopCue,
                    onSelected: onLoopCueChanged,
                  ),
                  IconButton(
                    tooltip: chunkControlsEnabled
                        ? l.text('previousChunk')
                        : l.text('chunkReplayUnavailableControl'),
                    onPressed: chunkControlsEnabled
                        ? onSeekToPreviousChunk
                        : null,
                    icon: const Icon(Icons.keyboard_double_arrow_left),
                  ),
                  IconButton(
                    tooltip: chunkControlsEnabled
                        ? l.text('nextChunk')
                        : l.text('chunkReplayUnavailableControl'),
                    onPressed: chunkControlsEnabled ? onSeekToNextChunk : null,
                    icon: const Icon(Icons.keyboard_double_arrow_right),
                  ),
                  Tooltip(
                    message: chunkControlsEnabled
                        ? l.text('loopChunk')
                        : l.text('chunkReplayUnavailableControl'),
                    child: FilterChip(
                      label: Text(l.text('loopChunk')),
                      selected: chunkLoopActive,
                      onSelected: chunkControlsEnabled
                          ? (_) => onLoopCurrentChunk()
                          : null,
                    ),
                  ),
                  Tooltip(
                    message: chunkControlsEnabled
                        ? l.text('expandChunk')
                        : l.text('chunkReplayUnavailableControl'),
                    child: TextButton.icon(
                      onPressed: chunkControlsEnabled
                          ? onLoopExpandedChunk
                          : null,
                      icon: const Icon(Icons.unfold_more),
                      label: Text(l.text('expandChunk')),
                    ),
                  ),
                  if (sourceLoopStart != null)
                    TextButton(
                      onPressed: onStopSourceLoop,
                      child: Text(l.text('stopSourceLoop')),
                    ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(l.text('wordStyles')),
                    selected: statusStylesVisible,
                    onSelected: onStatusStylesChanged,
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(l.text('subtitles')),
                    selected: subtitlesVisible,
                    onSelected: onSubtitlesVisibleChanged,
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: secondarySubtitlesAvailable
                        ? l.text('secondary')
                        : l.text('secondarySubtitleUnavailable'),
                    child: FilterChip(
                      label: Text(l.text('secondary')),
                      selected:
                          secondarySubtitlesAvailable &&
                          secondarySubtitlesVisible,
                      onSelected: secondarySubtitlesAvailable
                          ? onSecondaryVisibleChanged
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<double>(
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
                      if (value == null) return;
                      onRateChanged(value);
                    },
                  ),
                  const SizedBox(width: 12),
                  if (audioTracks.length > 1)
                    DropdownButton<String>(
                      hint: Text(l.text('audioTrack')),
                      value:
                          audioTracks.any(
                            (track) => track.id == selectedAudioId,
                          )
                          ? selectedAudioId
                          : null,
                      items: audioTracks
                          .map(
                            (track) => DropdownMenuItem(
                              value: track.id,
                              child: Text(
                                track.title ??
                                    track.language ??
                                    'Audio ${track.id}',
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (id) {
                        final matches = audioTracks.where(
                          (track) => track.id == id,
                        );
                        if (matches.isEmpty) return;
                        onAudioTrackChanged(matches.first);
                      },
                    ),
                  if (audioTracks.length > 1) const SizedBox(width: 12),
                  if (embeddedSubtitleTracks.isNotEmpty)
                    DropdownButton<String>(
                      hint: Text(l.text('embeddedSubtitles')),
                      value:
                          embeddedSubtitleTracks.any(
                            (track) => track.id == selectedEmbeddedSubtitleId,
                          )
                          ? selectedEmbeddedSubtitleId
                          : null,
                      items: embeddedSubtitleTracks
                          .map(
                            (track) => DropdownMenuItem(
                              value: track.id,
                              child: Text(
                                track.title ??
                                    track.language ??
                                    'Subtitle ${track.id}',
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (id) {
                        final matches = embeddedSubtitleTracks.where(
                          (track) => track.id == id,
                        );
                        if (matches.isEmpty) return;
                        onEmbeddedSubtitleTrackChanged(matches.first);
                      },
                    ),
                  if (embeddedSubtitleTracks.isNotEmpty)
                    const SizedBox(width: 12),
                  IconButton(
                    tooltip: muted ? 'Unmute' : 'Mute',
                    onPressed: onMuteToggle,
                    icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  ),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: volume,
                      max: 100,
                      onChanged: onVolumeChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(l.text('primaryOffset')),
                  IconButton(
                    onPressed: () => onPrimaryOffsetChanged(
                      primarySubtitleOffset - const Duration(milliseconds: 100),
                    ),
                    icon: const Icon(Icons.remove),
                  ),
                  Text('${primarySubtitleOffset.inMilliseconds} ms'),
                  IconButton(
                    onPressed: () => onPrimaryOffsetChanged(
                      primarySubtitleOffset + const Duration(milliseconds: 100),
                    ),
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 12),
                  Text(l.text('secondaryOffset')),
                  IconButton(
                    onPressed: secondarySubtitlesAvailable
                        ? () => onSecondaryOffsetChanged(
                            secondarySubtitleOffset -
                                const Duration(milliseconds: 100),
                          )
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('${secondarySubtitleOffset.inMilliseconds} ms'),
                  IconButton(
                    onPressed: secondarySubtitlesAvailable
                        ? () => onSecondaryOffsetChanged(
                            secondarySubtitleOffset +
                                const Duration(milliseconds: 100),
                          )
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      children: [
                        for (final task in taskStatuses)
                          _TaskStatusChip(status: task),
                      ],
                    ),
                  ),
                  if (taskStatuses.isNotEmpty) const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
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
    final color = _stateColor(status.state);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          '${l.text(status.titleKey)} · ${l.text(status.stateKey)} · '
          '${status.progress.clamp(0, 100)}%',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Color _stateColor(UserTaskState state) => switch (state) {
    UserTaskState.working => const Color(0xff6da8e8),
    UserTaskState.success => const Color(0xff38b88f),
    UserTaskState.warning => const Color(0xffd89a4a),
    UserTaskState.error => const Color(0xffe06c75),
    UserTaskState.cancelled => const Color(0xff8fa1b3),
    UserTaskState.unknown => const Color(0xff8fa1b3),
  };
}
