import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../controllers/subtitle_controller.dart';
import '../../models/timeline.dart';
import '../../settings.dart';
import '../../utils/subtitle_style.dart';
import '../../player_adapter.dart';
import '../subtitle/token_line.dart';

/// Renders the video player surface with subtitle overlay.
///
/// Extracted from the monolithic `_playerSurface()` in main.dart
/// to reduce the orchestrator's build method complexity.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.subtitleController,
    required this.learningController,
    required this.settings,
    required this.adapter,
    required this.tokenLineFontFamily,
    required this.onWord,
    required this.onPhrase,
    required this.onChunk,
    required this.onSeekCue,
    required this.onSaveSettings,
  });

  final SubtitleController subtitleController;
  final LearningController learningController;
  final AppSettings settings;
  final DesktopPlayerAdapter adapter;
  final String? Function(String) tokenLineFontFamily;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(Map<String, dynamic> candidate, Cue cue) onPhrase;
  final Future<void> Function(DisplayChunk chunk) onChunk;
  final Future<void> Function(Cue cue) onSeekCue;
  final Future<void> Function() onSaveSettings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sc = subtitleController;
        final lc = learningController;
        final showChunk = settings.showChunkGrouping;
        final highlightChunk = settings.highlightCurrentChunk;
        final cue = sc.currentPrimaryCue;

        final primarySize = responsiveSubtitleSize(
          width: constraints.maxWidth,
          scale: sc.primaryFontSize,
          preset: sc.preset,
          textLength: cue?.text.length ?? 1,
        );
        final secondarySize = responsiveSubtitleSize(
          width: constraints.maxWidth,
          scale: sc.secondaryFontSize,
          preset: sc.preset,
          textLength: sc.currentSecondaryCue?.text.length ?? 1,
          secondary: true,
        );
        final backgroundFactor = switch (sc.preset) {
          'watching' => 0.45,
          'compact' => 0.3,
          _ => 1.0,
        };
        final subtitlePosition = Offset(sc.positionX, sc.positionY);

        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            const Positioned.fill(
              child: ColoredBox(color: Colors.black),
            ),
            if (sc.visible && (cue != null || (sc.secondaryVisible && sc.currentSecondaryCue != null)))
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
                      sc.movePosition(
                        details.delta.dx,
                        details.delta.dy,
                        constraints.biggest.width,
                        constraints.biggest.height,
                      );
                    },
                    onPanEnd: (_) => onSaveSettings(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.82,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: sc.backgroundOpacity * backgroundFactor,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: sc.preset == 'compact' ? 10 : 18,
                            vertical: sc.preset == 'compact' ? 6 : 12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (cue != null)
                                GestureDetector(
                                  onTap: () => onSeekCue(cue),
                                  child: TokenLine(
                                    cue: cue,
                                    profiles: lc.wordProfiles,
                                    phraseCandidates: lc.phraseCandidates,
                                    phraseProfiles: lc.phraseProfiles,
                                    showStyles: sc.statusStylesVisible,
                                    fontSize: primarySize,
                                    fontFamily: tokenLineFontFamily(
                                      sc.primaryFontFamily,
                                    ),
                                    baseColor: Color(settings.primaryColor),
                                    currentTokenIndex: sc.currentWordToken,
                                    chunkPartition: showChunk
                                        ? sc.chunkPartitionsBySentence[cue.id]
                                        : null,
                                    currentChunkIndex: highlightChunk
                                        ? sc.currentChunkIndex
                                        : null,
                                    chunkDisplayStyle:
                                        settings.chunkDisplayStyle,
                                    chunkHighlightStyle:
                                        settings.chunkHighlightStyle,
                                    currentWordStyle:
                                        settings.wordHighlightStyle,
                                    currentWordIntensity:
                                        settings.wordAnimationIntensity,
                                    onWord: onWord,
                                    onPhrase: onPhrase,
                                    onChunk: onChunk,
                                  ),
                                ),
                              if (cue != null &&
                                  sc.pronunciationBySentence[cue.id] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _pronunciationText(
                                      sc.pronunciationBySentence[cue.id]!,
                                    ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: primarySize * 0.55,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              if (sc.secondaryVisible &&
                                  sc.currentSecondaryCue != null)
                                GestureDetector(
                                  onTap: () => adapter.seek(
                                    sc.secondaryCursor.mediaStart(
                                      sc.currentSecondaryCue!,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      sc.currentSecondaryCue!.text,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: secondarySize,
                                        fontFamily: tokenLineFontFamily(
                                          sc.secondaryFontFamily,
                                        ),
                                        color: Color(settings.secondaryColor),
                                      ),
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
          ],
        );
      },
    );
  }

  String _pronunciationText(Map<String, dynamic> analysis) {
    return analysis['display_ipa'] as String;
  }
}
