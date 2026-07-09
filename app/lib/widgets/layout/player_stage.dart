import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/capability_readiness.dart'
    show rhythmFrameHasAudioSupport;
import '../../models/types.dart';
import '../../player_adapter.dart';
import '../../utils/subtitle_style.dart';
import '../subtitle/connected_speech_reference_ribbon.dart';
import '../subtitle/expected_pronunciation_reference.dart';
import '../subtitle/phoneme_ribbon.dart';
import '../subtitle/rhythm_frame_ribbon.dart';
import '../subtitle/sound_pattern_mode_toggle.dart';
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
    required this.onLoopSoundRibbonFinding,
    required this.onLoopRhythmCue,
    required this.onSetSoundPatternDisplayMode,
    required this.onSaveSettings,
    required this.onOpenMedia,
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
  final Future<void> Function(
    PhonemeRibbonFinding finding,
    List<DetectedPhone> phones,
  )
  onLoopSoundRibbonFinding;
  final Future<void> Function(Duration start, Duration end, String label)
  onLoopRhythmCue;
  final Future<void> Function(String mode) onSetSoundPatternDisplayMode;
  final Future<void> Function() onSaveSettings;
  final Future<void> Function() onOpenMedia;

  @override
  State<PlayerStage> createState() => _PlayerStageState();
}

class _PlayerStageState extends State<PlayerStage> {
  bool _phoneEvidenceExpanded = false;
  String? _lastCueId;

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
  Future<void> _loopSoundRibbonFinding(
    PhonemeRibbonFinding finding,
    List<DetectedPhone> phones,
  ) => widget.onLoopSoundRibbonFinding(finding, phones);
  Future<void> _loopRhythmCue(Duration start, Duration end, String label) =>
      widget.onLoopRhythmCue(start, end, label);
  Future<void> _setSoundPatternDisplayMode(String mode) =>
      widget.onSetSoundPatternDisplayMode(mode);
  Future<void> _saveSettings() => widget.onSaveSettings();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Phone-evidence expansion is ephemeral overlay state; it only exists
      // inside Rhythm reference C ("actual"), so leaving that mode drops it.
      if (settingsController.soundPatternDisplayMode != 'actual' ||
          subtitleController.currentPrimaryCue?.id != _lastCueId) {
        _lastCueId = subtitleController.currentPrimaryCue?.id;
        _phoneEvidenceExpanded = false;
      }
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
            child: ColoredBox(
              color: Colors.black,
              child: PlayerSurface(adapter: adapter),
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
                  behavior: HitTestBehavior.translucent,
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: subtitleController.preset == 'compact'
                              ? 10
                              : 18,
                          vertical: subtitleController.preset == 'compact'
                              ? 6
                              : 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subtitleController.currentPrimaryCue != null)
                              GestureDetector(
                                onTap: () => _seekCue(
                                  subtitleController.currentPrimaryCue,
                                ),
                                child: TokenLine(
                                  cue: subtitleController.currentPrimaryCue!,
                                  profiles: learningController.wordEntries,
                                  capabilityProfiles:
                                      learningController.capabilityProfiles,
                                  phraseCandidates:
                                      learningController.phraseCandidates,
                                  phraseEntries:
                                      learningController.phraseEntries,
                                  showStyles:
                                      subtitleController.statusStylesVisible,
                                  fontSize: primarySize,
                                  fontFamily: _subtitleFont(
                                    subtitleController.primaryFontFamily,
                                  ),
                                  baseColor: settingsController.primaryColor,
                                  currentTokenIndex:
                                      subtitleController.currentWordToken,
                                  chunkPartition:
                                      settingsController.showChunkGrouping
                                      ? subtitleController
                                            .chunkPartitionsBySentence[subtitleController
                                            .currentPrimaryCue!
                                            .id]
                                      : null,
                                  currentChunkIndex:
                                      settingsController.highlightCurrentChunk
                                      ? subtitleController.currentChunkIndex
                                      : null,
                                  chunkDisplayStyle:
                                      settingsController.chunkDisplayStyle,
                                  chunkHighlightStyle:
                                      settingsController.chunkHighlightStyle,
                                  currentWordStyle:
                                      settingsController.wordHighlightStyle,
                                  currentWordIntensity:
                                      settingsController.wordAnimationIntensity,
                                  senseGroups:
                                      settingsController.showSenseGrouping
                                      ? subtitleController
                                              .senseGroupsBySentence[
                                            subtitleController
                                                .currentPrimaryCue!
                                                .id] ??
                                          const []
                                      : const [],
                                  onWord: _openWord,
                                  onPhrase: _openPhrase,
                                  onChunk: _seekChunk,
                                ),
                              ),
                            if (settingsController.phonemeRibbonVisible &&
                                subtitleController.currentPrimaryCue != null)
                              Builder(
                                builder: (_) {
                                  final cueId =
                                      subtitleController.currentPrimaryCue!.id;
                                  final analysis = subtitleController
                                      .phoneticAnalysisBySentence[cueId];
                                  final phones = buildLearningPhones(
                                    pronunciation: subtitleController
                                        .pronunciationBySentence[cueId]
                                        ?.toJson(),
                                    wordTimings: subtitleController
                                        .timingsBySentence[cueId],
                                    observedPhones:
                                        analysis?.detectedPhones ?? const [],
                                    allowObservedOnlyFallback: false,
                                  );
                                  if (phones.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: PhonemeRibbon(
                                      phones: phones,
                                      position: playerController.position,
                                      fontSize: primarySize * 0.45,
                                      height: primarySize * 1.1,
                                      style:
                                          settingsController.phonemeRibbonStyle,
                                      tooltip: l.text('textPhonemeRibbonHint'),
                                    ),
                                  );
                                },
                              ),
                            if (settingsController.soundPatternRibbonVisible &&
                                subtitleController.currentPrimaryCue != null)
                              Builder(
                                builder: (_) {
                                  final cueId =
                                      subtitleController.currentPrimaryCue!.id;
                                  final analysis = subtitleController
                                      .phoneticAnalysisBySentence[cueId];
                                  final pronunciation = subtitleController
                                      .pronunciationBySentence[cueId];
                                  final soundAnalysis = analysis?.soundAnalysis;
                                  final rhythmFrame =
                                      subtitleController.llTimelineDocument
                                          ?.rhythmFrameForSentence(cueId) ??
                                      soundAnalysis?.rhythmFrame;
                                  final phones = soundAnalysis == null
                                      ? const <DetectedPhone>[]
                                      : buildSoundPatternPhones(soundAnalysis);
                                  final findings = soundAnalysis == null
                                      ? const <PhonemeRibbonFinding>[]
                                      : buildPhonemeRibbonFindings(
                                          rawFindings:
                                              analysis?.findings
                                                  .map(
                                                    (value) => value.toJson(),
                                                  )
                                                  .toList(growable: false) ??
                                              const [],
                                          phones: phones,
                                          soundAnalysis: soundAnalysis,
                                        );
                                  final hasPhoneEvidence = phones.isNotEmpty;
                                  Widget soundPatternLayer(
                                    Widget child, {
                                    bool offerPhoneEvidence = false,
                                  }) => Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: child,
                                        ),
                                        if (offerPhoneEvidence) ...[
                                          const SizedBox(width: 4),
                                          Tooltip(
                                            message: hasPhoneEvidence
                                                ? l.text(
                                                    _phoneEvidenceExpanded
                                                        ? 'hidePhoneEvidence'
                                                        : 'showPhoneEvidence',
                                                  )
                                                : l.text(
                                                    'soundPatternUnavailableTooltip',
                                                  ),
                                            child: IconButton(
                                              onPressed: hasPhoneEvidence
                                                  ? () => setState(
                                                      () => _phoneEvidenceExpanded =
                                                          !_phoneEvidenceExpanded,
                                                    )
                                                  : null,
                                              icon: Icon(
                                                _phoneEvidenceExpanded
                                                    ? Icons.graphic_eq
                                                    : Icons.graphic_eq_outlined,
                                              ),
                                              isSelected:
                                                  _phoneEvidenceExpanded,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  BoxConstraints.tightFor(
                                                    width: primarySize * 0.95,
                                                    height: primarySize * 0.95,
                                                  ),
                                              padding: EdgeInsets.zero,
                                              iconSize: primarySize * 0.52,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 4),
                                        RhythmReferenceToggle(
                                          mode: settingsController
                                              .soundPatternDisplayMode,
                                          citationTooltip: l.text(
                                            'rhythmReferenceCitationTooltip',
                                          ),
                                          connectedTooltip: l.text(
                                            'rhythmReferenceConnectedTooltip',
                                          ),
                                          actualTooltip: l.text(
                                            'rhythmReferenceActualTooltip',
                                          ),
                                          semanticsLabel: l.text(
                                            'soundPatternDisplayMode',
                                          ),
                                          size: primarySize * 0.95,
                                          onChanged: (value) => unawaited(
                                            _setSoundPatternDisplayMode(value),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  final mode = settingsController
                                      .soundPatternDisplayMode;
                                  if (mode == 'citation') {
                                    return soundPatternLayer(
                                      pronunciation == null
                                          ? SoundPatternUnavailableRibbon(
                                              message: l.text(
                                                'citationPronunciationUnavailable',
                                              ),
                                              fontSize: primarySize * 0.34,
                                              height: primarySize * 0.9,
                                            )
                                          : ExpectedPronunciationReference(
                                              analysis: pronunciation,
                                              title: l.text(
                                                'rhythmReferenceCitation',
                                              ),
                                              currentTokenIndex:
                                                  subtitleController
                                                      .currentWordToken,
                                              fontSize: primarySize * 0.34,
                                              height: primarySize * 0.86,
                                              tooltip: l.text(
                                                'expectedPronunciationTooltip',
                                              ),
                                            ),
                                    );
                                  }

                                  final connectedReferences =
                                      rhythmFrame?.connectedSpeechRefs
                                          .where(
                                            (reference) => reference
                                                .signalSources
                                                .contains('text_prior'),
                                          )
                                          .toList(growable: false) ??
                                      const <RhythmConnectedSpeechRef>[];
                                  if (mode == 'connected') {
                                    return soundPatternLayer(
                                      connectedReferences.isEmpty
                                          ? SoundPatternUnavailableRibbon(
                                              message: l.text(
                                                'connectedSpeechUnavailable',
                                              ),
                                              fontSize: primarySize * 0.34,
                                              height: primarySize * 0.9,
                                            )
                                          : ConnectedSpeechReferenceRibbon(
                                              references: connectedReferences,
                                              tokens: subtitleController
                                                  .currentPrimaryCue!
                                                  .tokens,
                                              title: l.text(
                                                'connectedSpeechReference',
                                              ),
                                              currentTokenIndex:
                                                  subtitleController
                                                      .currentWordToken,
                                              fontSize: primarySize * 0.44,
                                              height: primarySize * 1.1,
                                              tooltip: l.text(
                                                'connectedSpeechReferenceTooltip',
                                              ),
                                            ),
                                    );
                                  }

                                  if (rhythmFrame == null) {
                                    return soundPatternLayer(
                                      SoundPatternUnavailableRibbon(
                                        message: l.text(
                                          'rhythmFrameUnavailable',
                                        ),
                                        tooltip: l.text(
                                          'soundPatternUnavailableTooltip',
                                        ),
                                        fontSize: primarySize * 0.34,
                                        height: primarySize * 0.9,
                                      ),
                                      offerPhoneEvidence: true,
                                    );
                                  }
                                  final predicted = !rhythmFrameHasAudioSupport(
                                    rhythmFrame,
                                  );
                                  final actualView = RhythmFrameRibbon(
                                    frame: rhythmFrame,
                                    pronunciation: pronunciation,
                                    position: playerController.position,
                                    title: l.text('rhythmReferenceActual'),
                                    anchorLabel: l.text('stressAnchors'),
                                    weakGroupLabel: l.text('weakGroups'),
                                    compressionLabel: l.text('compressedSpans'),
                                    hotspotLabel: l.text('listeningHotspots'),
                                    fontSize: primarySize * 0.44,
                                    height: primarySize * 1.15,
                                    tooltip: predicted
                                        ? l.text('listeningPredictedTooltip')
                                        : l.text('rhythmRibbonHint'),
                                    predicted: predicted,
                                    predictedLabel: l.text(
                                      'listeningPredictedBadge',
                                    ),
                                    onLoopCue: (start, end, label) => unawaited(
                                      _loopRhythmCue(start, end, label),
                                    ),
                                  );
                                  return soundPatternLayer(
                                    _phoneEvidenceExpanded &&
                                            hasPhoneEvidence &&
                                            soundAnalysis != null
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              actualView,
                                              const SizedBox(height: 4),
                                              PhonemeRibbon(
                                                phones: phones,
                                                position:
                                                    playerController.position,
                                                fontSize: primarySize * 0.42,
                                                height: primarySize,
                                                style: settingsController
                                                    .phonemeRibbonStyle,
                                                syllables:
                                                    soundAnalysis.syllables,
                                                prosodicPhrases: soundAnalysis
                                                    .prosodicPhrases,
                                                findings: findings,
                                                lane: PhonemeRibbonLane.sound,
                                                tooltip: l.text(
                                                  'soundPatternRibbonHint',
                                                ),
                                                onLoopFinding: (finding) =>
                                                    unawaited(
                                                      _loopSoundRibbonFinding(
                                                        finding,
                                                        phones,
                                                      ),
                                                    ),
                                              ),
                                            ],
                                          )
                                        : actualView,
                                    offerPhoneEvidence: true,
                                  );
                                },
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
