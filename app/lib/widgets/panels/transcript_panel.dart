import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../utils/format_duration.dart';
import '../subtitle/token_line.dart';

class TranscriptPanel extends StatelessWidget {
  const TranscriptPanel({
    super.key,
    required this.track,
    required this.scrollController,
    required this.itemExtent,
    required this.currentCue,
    required this.wordProfiles,
    required this.showStyles,
    required this.baseColor,
    required this.onWord,
    required this.onSeekCue,
  });

  final SubtitleTrack? track;
  final ScrollController scrollController;
  final double itemExtent;
  final Cue? currentCue;
  final Map<String, Map<String, dynamic>> wordProfiles;
  final bool showStyles;
  final Color baseColor;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(Cue? cue) onSeekCue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: const Color(0xff151a20),
      child: track == null
          ? Center(child: Text(l.text('importSubtitleHint')))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemExtent: itemExtent,
                    itemCount: track!.cues.length,
                    itemBuilder: (context, index) {
                      final cue = track!.cues[index];
                      final selected = cue.id == currentCue?.id;
                      return ListTile(
                        selected: selected,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.55),
                        leading: Text(formatDuration(cue.start)),
                        title: TokenLine(
                          cue: cue,
                          profiles: wordProfiles,
                          showStyles: showStyles,
                          baseColor: baseColor,
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
