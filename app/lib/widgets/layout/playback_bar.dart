import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/media_session_coordinator.dart';
import '../../controllers/playback_actions_coordinator.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/extensive_listening_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/task_status.dart';
import '../../player_adapter.dart';
import '../player/playback_controls.dart';

/// The bottom playback bar: transport controls with chunk navigation when
/// media is loaded, or the open-media hint row otherwise. Extracted from the
/// composition root; getter names mirror the host's controller fields.
class PlaybackBar extends StatefulWidget {
  const PlaybackBar({
    super.key,
    required this.adapter,
    required this.playerController,
    required this.extensiveListeningController,
    required this.subtitleController,
    required this.mediaSession,
    required this.playbackActions,
    required this.taskStatuses,
    required this.onSeekCue,
    required this.onToggleExtensiveListening,
    required this.onCaptureListeningInbox,
    required this.onHardInterruptListening,
    required this.onSaveSettings,
  });

  final DesktopPlayerAdapter adapter;
  final PlayerController playerController;
  final ExtensiveListeningController extensiveListeningController;
  final SubtitleController subtitleController;
  final MediaSessionCoordinator mediaSession;
  final PlaybackActionsCoordinator playbackActions;
  final List<UserTaskStatus> taskStatuses;
  final Future<void> Function(Cue? cue) onSeekCue;
  final Future<void> Function() onToggleExtensiveListening;
  final Future<void> Function() onCaptureListeningInbox;
  final Future<void> Function() onHardInterruptListening;
  final Future<void> Function() onSaveSettings;

  @override
  State<PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends State<PlaybackBar> {
  DesktopPlayerAdapter get adapter => widget.adapter;
  PlayerController get playerController => widget.playerController;
  ExtensiveListeningController get extensiveListeningController =>
      widget.extensiveListeningController;
  SubtitleController get subtitleController => widget.subtitleController;
  MediaSessionCoordinator get mediaSession => widget.mediaSession;
  PlaybackActionsCoordinator get playbackActions => widget.playbackActions;
  AppLocalizations get l => AppLocalizations.of(context);
  String get status => playerController.status;
  List<UserTaskStatus> get taskStatuses => widget.taskStatuses;

  Future<void> _seekCue(Cue? cue) => widget.onSeekCue(cue);
  Future<void> _toggleExtensiveListening() =>
      widget.onToggleExtensiveListening();
  Future<void> _captureListeningInbox() => widget.onCaptureListeningInbox();
  Future<void> _hardInterruptListening() => widget.onHardInterruptListening();
  Future<void> _saveSettings() => widget.onSaveSettings();

  @override
  Widget build(BuildContext context) {
    if (playerController.mediaPath == null) return _noMediaControls();
    final currentChunk = playbackActions.currentChunkRef();
    return PlaybackControls(
      adapter: adapter,
      position: playerController.position,
      duration: playerController.duration,
      playing: playerController.playing,
      loopCue: subtitleController.loopCue,
      sourceLoopStart: playerController.sourceLoopStart,
      statusStylesVisible: subtitleController.statusStylesVisible,
      subtitlesVisible: subtitleController.visible,
      secondarySubtitlesVisible: subtitleController.secondaryVisible,
      secondarySubtitlesAvailable: subtitleController.secondaryTrack != null,
      rate: playerController.rate,
      volume: playerController.volume,
      muted: playerController.muted,
      audioTracks: playerController.audioTracks,
      selectedAudioId: playerController.selectedAudioId,
      embeddedSubtitleTracks: playerController.embeddedSubtitleTracks,
      selectedEmbeddedSubtitleId: playerController.selectedEmbeddedSubtitleId,
      primarySubtitleOffset: subtitleController.primarySubtitleOffset,
      secondarySubtitleOffset: subtitleController.secondarySubtitleOffset,
      status: status,
      taskStatuses: taskStatuses,
      extensiveListeningActive: extensiveListeningController.active,
      listeningMarkEnabled: subtitleController.currentPrimaryCue != null,
      listeningInboxCount: extensiveListeningController.activeItemCount,
      onSeek: (value) => adapter.seek(value),
      onSeekToPreviousCue: () => _seekCue(
        subtitleController.primaryCursor.previous(
          subtitleController.currentPrimaryCue,
        ),
      ),
      onSeekToZero: () => adapter.seek(Duration.zero),
      onPlayPause: adapter.playOrPause,
      onStop: adapter.stop,
      onSeekToNextCue: () => _seekCue(
        subtitleController.primaryCursor.next(
          subtitleController.currentPrimaryCue,
        ),
      ),
      chunkControlsEnabled: currentChunk != null,
      chunkLoopActive:
          playerController.sourceLoopStart != null &&
          currentChunk?.start == playerController.sourceLoopStart,
      onSeekToPreviousChunk: () => playbackActions.seekAdjacentChunk(-1),
      onSeekToNextChunk: () => playbackActions.seekAdjacentChunk(1),
      onLoopCurrentChunk: playbackActions.loopCurrentChunk,
      onLoopExpandedChunk: playbackActions.loopExpandedChunk,
      onLoopCueChanged: (value) {
        subtitleController.setLoopCue(value);
        if (value) playerController.setSourceLoop(null, null);
      },
      onStopSourceLoop: () => playerController.setSourceLoop(null, null),
      onStatusStylesChanged: (value) {
        subtitleController.setStatusStylesVisible(value);
        unawaited(_saveSettings());
      },
      onSubtitlesVisibleChanged: (value) {
        subtitleController.setVisible(value);
        unawaited(_saveSettings());
      },
      onSecondaryVisibleChanged: (value) {
        subtitleController.setSecondaryVisible(value);
        unawaited(_saveSettings());
      },
      onRateChanged: (value) {
        playerController.setRate(value);
        adapter.setRate(value);
        unawaited(_saveSettings());
      },
      onVolumeChanged: (value) {
        playerController.setVolume(value);
        if (!playerController.muted) adapter.setVolume(value);
        unawaited(_saveSettings());
      },
      onMuteToggle: () {
        final newMuted = !playerController.muted;
        playerController.setMuted(newMuted);
        adapter.setVolume(newMuted ? 0 : playerController.volume);
      },
      onAudioTrackChanged: (track) {
        playerController.setSelectedAudioId(track.id);
        adapter.selectAudio(track);
      },
      onEmbeddedSubtitleTrackChanged: (track) {
        playerController.setSelectedEmbeddedSubtitleId(track.id);
        adapter.selectSubtitle(track);
      },
      onPrimaryOffsetChanged: (offset) {
        subtitleController.setPrimarySubtitleOffset(offset);
        unawaited(_saveSettings());
      },
      onSecondaryOffsetChanged: (offset) {
        subtitleController.setSecondarySubtitleOffset(offset);
        unawaited(_saveSettings());
      },
      onToggleExtensiveListening: () => unawaited(_toggleExtensiveListening()),
      onCaptureListeningInbox: () => unawaited(_captureListeningInbox()),
      onHardInterruptListening: () => unawaited(_hardInterruptListening()),
    );
  }

  Widget _noMediaControls() => Material(
    color: const Color(0xff11161c),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${l.text('noMediaControlsHint')} · $status',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: mediaSession.openMedia,
            icon: const Icon(Icons.folder_open),
            label: Text(l.text('openVideoAudio')),
          ),
        ],
      ),
    ),
  );
}
