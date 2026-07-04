import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../utils/format_duration.dart';
import '../subtitle/token_line.dart';

class TranscriptPanel extends StatelessWidget {
  const TranscriptPanel({
    super.key,
    required this.track,
    required this.scrollController,
    required this.itemExtent,
    required this.currentCue,
    required this.wordEntries,
    required this.showStyles,
    required this.baseColor,
    required this.onWord,
    required this.onSeekCue,
  });

  final SubtitleTrack? track;
  final ScrollController scrollController;
  final double itemExtent;
  final Cue? currentCue;
  final Map<String, LexicalEntry> wordEntries;
  final bool showStyles;
  final Color baseColor;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(Cue? cue) onSeekCue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final effectiveBaseColor = baseColor.computeLuminance() > 0.75
        ? colors.onSurface
        : baseColor;
    return Material(
      color: colors.surfaceContainerLowest,
      child: Column(
        children: [
          Expanded(
            child: track == null
                ? Center(child: Text(l.text('importSubtitleHint')))
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: track!.cues.length,
                    itemBuilder: (context, index) {
                      final cue = track!.cues[index];
                      final selected = cue.id == currentCue?.id;
                      return ListTile(
                        selected: selected,
                        selectedTileColor: colors.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        leading: SizedBox(
                          width: 58,
                          child: Text(
                            formatDuration(cue.start),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                        title: TokenLine(
                          cue: cue,
                          profiles: wordEntries,
                          showStyles: showStyles,
                          baseColor: effectiveBaseColor,
                          onWord: onWord,
                        ),
                        onTap: () => onSeekCue(cue),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
