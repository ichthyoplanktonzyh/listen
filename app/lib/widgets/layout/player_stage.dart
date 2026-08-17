import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../player_adapter.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/subtitle_style.dart';
import '../subtitle/token_line.dart';

/// The media stage: video surface plus every playback overlay (primary and
/// secondary subtitles, word sync, chunk grouping, rhythm/phoneme ribbons,
/// listening-structure layers). Extracted from the composition root; state
/// getters mirror the host's controller field names so the overlay tree reads
/// identically at both sites. Phone-evidence expansion is owned here as
/// ephemeral overlay state.
class PlayerStage extends StatefulWidget {
  const PlayerStage({
    super.key,
    required this.adapter,
    required this.playerController,
    required this.subtitleController,
    required this.learningController,
    required this.settingsController,
    required this.onSeekCue,
    required this.onSeekChunk,
    required this.onOpenWord,
    required this.onOpenPhrase,
    required this.onSaveSettings,
    required this.onOpenMedia,
    this.onToggleFullscreen,
  });

  final DesktopPlayerAdapter adapter;
  final PlayerController playerController;
  final SubtitleController subtitleController;
  final LearningController learningController;
  final SettingsController settingsController;
  final Future<void> Function(Cue? cue) onSeekCue;
  final Future<void> Function(DisplayChunk chunk) onSeekChunk;
  final Future<void> Function(SubtitleToken token, Cue cue) onOpenWord;
  final Future<void> Function(PhraseCandidate candidate, Cue cue) onOpenPhrase;
  final Future<void> Function() onSaveSettings;
  final Future<void> Function() onOpenMedia;

  /// #25-A: double-clicking the bare video surface toggles the fullscreen
  /// immersive state. The gesture lives on the surface only — never as an
  /// ancestor of the subtitle overlays, whose word taps must not wait out a
  /// double-tap timeout in the gesture arena.
  final VoidCallback? onToggleFullscreen;

  @override
  State<PlayerStage> createState() => _PlayerStageState();
}

class _PlayerStageState extends State<PlayerStage> {
  DesktopPlayerAdapter get adapter => widget.adapter;
  PlayerController get playerController => widget.playerController;
  SubtitleController get subtitleController => widget.subtitleController;
  LearningController get learningController => widget.learningController;
  SettingsController get settingsController => widget.settingsController;
  AppLocalizations get l => AppLocalizations.of(context);

  Future<void> _seekCue(Cue? cue) => widget.onSeekCue(cue);
  Future<void> _seekChunk(DisplayChunk chunk) => widget.onSeekChunk(chunk);
  Future<void> _openWord(SubtitleToken token, Cue cue) =>
      widget.onOpenWord(token, cue);
  Future<void> _openPhrase(PhraseCandidate candidate, Cue cue) =>
      widget.onOpenPhrase(candidate, cue);
  Future<void> _saveSettings() => widget.onSaveSettings();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final primarySize = responsiveSubtitleSize(
        width: constraints.maxWidth,
        scale: subtitleController.primaryFontSize,
        preset: subtitleController.preset,
        textLength: subtitleController.currentPrimaryCue?.text.length ?? 1,
      );
      final secondarySize = responsiveSubtitleSize(
        width: constraints.maxWidth,
        scale: subtitleController.secondaryFontSize,
        preset: subtitleController.preset,
        textLength: subtitleController.currentSecondaryCue?.text.length ?? 1,
        secondary: true,
      );
      final backgroundFactor = subtitleController.preset == 'watching'
          ? 0.45
          : subtitleController.preset == 'compact'
          ? 0.3
          : 1.0;
      final subtitlePosition = Offset(
        subtitleController.positionX,
        subtitleController.positionY,
      );
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('player-stage-surface'),
              behavior: HitTestBehavior.opaque,
              onDoubleTap: widget.onToggleFullscreen,
              child: ColoredBox(
                color: Colors.black,
                child: PlayerSurface(adapter: adapter),
              ),
            ),
          ),
          if (subtitleController.visible &&
              (subtitleController.currentPrimaryCue != null ||
                  (subtitleController.secondaryVisible &&
                      subtitleController.currentSecondaryCue != null)))
            Align(
              alignment: Alignment(
                subtitlePosition.dx * 2 - 1,
                subtitlePosition.dy * 2 - 1,
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  // Opaque, not translucent: the subtitle box must swallow its
                  // hits so they never fall through to the video surface's
                  // double-tap recognizer — a competing double-tap in the
                  // arena would delay every word tap by the double-tap
                  // timeout (#25-A).
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    subtitleController.movePosition(
                      details.delta.dx,
                      details.delta.dy,
                      constraints.biggest.width,
                      constraints.biggest.height,
                    );
                  },
                  onPanEnd: (_) => unawaited(_saveSettings()),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.82,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha:
                              subtitleController.backgroundOpacity *
                              backgroundFactor,
                        ),
                        borderRadius: ListenRadii.controlBorder,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: subtitleController.preset == 'compact'
                              ? ListenSpacing.gap8
                              : ListenSpacing.gap16,
                          vertical: subtitleController.preset == 'compact'
                              ? ListenSpacing.gap6
                              : ListenSpacing.gap12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subtitleController.currentPrimaryCue != null)
                              GestureDetector(
                                onTap: () => _seekCue(
                                  subtitleController.currentPrimaryCue,
                                ),
                                // Chunk highlight is the only reason the token
                                // line needs the live position; when it is off,
                                // only the speech-rate word/chunk cursors
                                // drive rebuilds.
                                child: ListenableBuilder(
                                  listenable: Listenable.merge([
                                    if (settingsController.chunkHighlightActive)
                                      playerController.positionListenable,
                                    subtitleController
                                        .currentWordTokenListenable,
                                    subtitleController
                                        .currentChunkIndexListenable,
                                  ]),
                                  builder: (context, _) {
                                    final cueId = subtitleController
                                        .currentPrimaryCue!
                                        .id;
                                    // Display-only (#31): the caption's ‿
                                    // ties read the same rhythm frame the
                                    // ribbons already consume — no new
                                    // analysis path.
                                    final tieFrame =
                                        subtitleController.llTimelineDocument
                                            ?.rhythmFrameForSentence(cueId) ??
                                        subtitleController
                                            .phoneticAnalysisBySentence[cueId]
                                            ?.soundAnalysis
                                            ?.rhythmFrame;
                                    return TokenLine(
                                      cue:
                                          subtitleController.currentPrimaryCue!,
                                      profiles: learningController.wordEntries,
                                      capabilityProfiles:
                                          learningController.capabilityProfiles,
                                      phraseCandidates:
                                          learningController.phraseCandidates,
                                      phraseEntries:
                                          learningController.phraseEntries,
                                      showStyles: subtitleController
                                          .statusStylesVisible,
                                      fontSize: primarySize,
                                      fontFamily: _subtitleFont(
                                        subtitleController.primaryFontFamily,
                                      ),
                                      baseColor:
                                          settingsController.primaryColor,
                                      currentTokenIndex:
                                          subtitleController.currentWordToken,
                                      groupingMode:
                                          settingsController.groupingMode,
                                      // Both grouping layers flow in independently
                                      // (ADR 0016); TokenLine draws one per mode.
                                      chunkPartition:
                                          subtitleController
                                              .chunkPartitionsBySentence[subtitleController
                                              .currentPrimaryCue!
                                              .id],
                                      currentChunkIndex:
                                          settingsController
                                              .chunkHighlightActive
                                          ? subtitleController.currentChunkIndex
                                          : null,
                                      chunkDisplayStyle:
                                          settingsController.chunkDisplayStyle,
                                      chunkHighlightStyle: settingsController
                                          .chunkHighlightStyle,
                                      currentWordStyle:
                                          settingsController.wordHighlightStyle,
                                      currentWordIntensity: settingsController
                                          .wordAnimationIntensity,
                                      senseGroups:
                                          subtitleController
                                              .senseGroupsBySentence[subtitleController
                                              .currentPrimaryCue!
                                              .id] ??
                                          const [],
                                      wordTimings:
                                          subtitleController
                                              .timingsBySentence[subtitleController
                                              .currentPrimaryCue!
                                              .id] ??
                                          const [],
                                      mediaPosition:
                                          settingsController
                                              .chunkHighlightActive
                                          ? playerController.position
                                          : null,
                                      subtitleOffset: subtitleController
                                          .primarySubtitleOffset,
                                      connectedSpeechRefs:
                                          tieFrame?.connectedSpeechRefs ??
                                          const [],
                                      onWord: _openWord,
                                      onPhrase: _openPhrase,
                                      onChunk: _seekChunk,
                                    );
                                  },
                                ),
                              ),
                            if (subtitleController.secondaryVisible &&
                                subtitleController.currentSecondaryCue != null)
                              GestureDetector(
                                onTap: () => adapter.seek(
                                  subtitleController.secondaryCursor.mediaStart(
                                    subtitleController.currentSecondaryCue!,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    subtitleController
                                        .currentSecondaryCue!
                                        .text,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: secondarySize,
                                      fontFamily: _subtitleFont(
                                        subtitleController.secondaryFontFamily,
                                      ),
                                      color: settingsController.secondaryColor,
                                    ),
                                  ),
                                ),
                              )
                            // Secondary enabled but no track at all: say so, so an
                            // empty secondary line is not silently confusing.
                            // A gap within an existing track stays intentionally
                            // empty.
                            else if (subtitleController.secondaryVisible &&
                                subtitleController.secondaryTrack == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  l.text('noSecondarySubtitle'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: secondarySize * 0.7,
                                    fontFamily: _subtitleFont(
                                      subtitleController.secondaryFontFamily,
                                    ),
                                    color: settingsController.secondaryColor
                                        .withAlpha(140),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (playerController.mediaPath == null)
            Center(
              child: FilledButton.icon(
                onPressed: widget.onOpenMedia,
                icon: const Icon(Icons.folder_open),
                label: Text(l.text('openVideoAudio')),
              ),
            ),
        ],
      );
    },
  );

  String? _subtitleFont(String value) => switch (value) {
    'serif' => 'Georgia',
    'monospace' => 'Menlo',
    _ => null,
  };
}
