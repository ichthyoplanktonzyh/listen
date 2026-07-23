import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/typography.dart';

/// One selected action from the specialty clip list: `play` opens the slice
/// playback window (3.5.7), `practice` seeds the practice window (3.5.6) for
/// a clip in the currently loaded track.
class L1SpecialtyAction {
  const L1SpecialtyAction(this.action, this.occurrence);

  final String action;
  final CorpusOccurrence occurrence;
}

/// Same-family clip list for one L1 difficulty category (Phase 3.9). Pure
/// presentation over the aggregation payload; the host owns playback and
/// practice side effects.
Future<L1SpecialtyAction?> showL1SpecialtyDialog({
  required BuildContext context,
  required String difficultyKindName,
  required L1SpecialtyView payload,
  required String? currentTrackId,
}) {
  final occurrences = payload.occurrences;
  final indexed = payload.indexed;
  return showDialog<L1SpecialtyAction>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      return AlertDialog(
        title: Text('${l.text('l1SimilarClips')} · $difficultyKindName'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l.text('l1SpecialtyUnindexed'),
                    style: ListenType.body.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (occurrences.isEmpty)
                Expanded(child: Center(child: Text(l.text('l1SpecialtyEmpty'))))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: occurrences.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final occurrence = occurrences[index];
                      final sameTrack =
                          currentTrackId != null &&
                          occurrence.trackId == currentTrackId;
                      return ListTile(
                        dense: true,
                        title: Text(
                          occurrence.displayText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          occurrence.sourceSnapshot,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ListenType.body.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l.text('l1ListenAgain'),
                              icon: const Icon(Icons.play_circle_outline),
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(L1SpecialtyAction('play', occurrence)),
                            ),
                            IconButton(
                              tooltip: l.text('l1SpecialtyPractice'),
                              icon: const Icon(Icons.school_outlined),
                              onPressed: sameTrack
                                  ? () => Navigator.of(context).pop(
                                      L1SpecialtyAction('practice', occurrence),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.text('close')),
          ),
        ],
      );
    },
  );
}
