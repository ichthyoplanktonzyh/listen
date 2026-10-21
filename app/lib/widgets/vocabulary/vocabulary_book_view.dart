import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import '../../theme/motion.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../common/capability_viz.dart';
import '../common/listen_empty_state.dart';

/// The single state a word row carries on its left edge.
///
/// The listening state a word row carries on its left edge. A single state is
/// easier to scan in the list than a small multi-part indicator; detail stays
/// available in the selected entry.
enum VocabularyRowStatus {
  /// Nothing has been measured for listening yet — the word is in the book
  /// but no listening evidence has been recorded about it. 月蓝, the charter's fifth
  /// colour, reserved for the "first seen" state.
  firstSeen,

  /// Listening reads acquired.
  acquired,

  /// Listening reads not acquired — a practice target, not a failure.
  notAcquired,

  /// Listening has no manual or observed conclusion yet.
  unassessed,
}

/// The row status uses the listening assessment only.
VocabularyRowStatus vocabularyRowStatus(LexicalCapabilityProfile? profile) {
  if (profile == null) return VocabularyRowStatus.firstSeen;
  return switch (profile.listening.effectiveAssessment) {
    'acquired' => VocabularyRowStatus.acquired,
    'not_acquired' => VocabularyRowStatus.notAcquired,
    _ => VocabularyRowStatus.unassessed,
  };
}

/// The colour that *is* the status. `firstSeen` reads 月蓝 — a content light
/// source read straight from the palette like月白, not a chrome role — and the
/// the listening conclusions use the same palette throughout the app.
Color vocabularyRowStatusColor(
  ColorScheme colors,
  VocabularyRowStatus status,
) => switch (status) {
  VocabularyRowStatus.firstSeen => ListenColors.moonBlue,
  VocabularyRowStatus.acquired => capabilityAssessmentColor(colors, 'acquired'),
  VocabularyRowStatus.notAcquired => capabilityAssessmentColor(
    colors,
    'not_acquired',
  ),
  VocabularyRowStatus.unassessed => capabilityAssessmentColor(
    colors,
    'unassessed',
  ),
};

/// Width of the status bar. Wide enough that the hue is unambiguous at a
/// glance down a dense list, narrow enough that it reads as an edge marking
/// the row rather than a block competing with it.
const _statusBarWidth = 3.0;

String _statusLabel(AppLocalizations l, VocabularyRowStatus status) {
  if (status == VocabularyRowStatus.firstSeen) {
    return l.text('vocabStatusFirstSeen');
  }
  final state = switch (status) {
    VocabularyRowStatus.acquired => 'acquired',
    VocabularyRowStatus.notAcquired => 'not_acquired',
    _ => 'unassessed',
  };
  return '${l.text('capabilityListening')}: ${l.text(state)}';
}

class VocabularyBookView extends StatelessWidget {
  const VocabularyBookView({
    super.key,
    required this.words,
    required this.onWord,
    this.selectedEntryId,
  });

  final List<LexicalEntryDetails> words;
  final ValueChanged<LexicalEntryDetails> onWord;

  /// The entry currently open in the detail pane, highlighted in the list so
  /// the two-pane workbench shows which word the detail belongs to.
  final String? selectedEntryId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    if (words.isEmpty) {
      return ListenEmptyState(
        icon: Icons.menu_book_outlined,
        message: l.text('noWords'),
      );
    }
    return ListView.separated(
      itemCount: words.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final value = words[index];
        final entry = value.entry;
        final occurrences = value.occurrences;
        final isPhrase = entry.kind == 'phrase';
        final snapshot = occurrences.isEmpty
            ? l.text('noSourceSnapshot')
            : occurrences.first.sentenceTextSnapshot;
        final hasMedia =
            occurrences.isNotEmpty && occurrences.first.mediaId != null;
        final status = vocabularyRowStatus(value.capabilityProfile);
        final statusLabel = _statusLabel(l, status);
        return Semantics(
          label: statusLabel,
          child: Tooltip(
            // Colour is the only visual encoding of the status, so the name
            // of it has to stay reachable — by hover here and by assistive
            // tech through the label above. The wait keeps it from firing
            // while the pointer is merely crossing a dense list.
            message: statusLabel,
            waitDuration: ListenMotion.slow,
            child: DecoratedBox(
              key: ValueKey('vocabulary-row-status-${entry.id}'),
              // A border stretches to the row's own height, so the bar always
              // spans exactly the row it marks without measuring it.
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: vocabularyRowStatusColor(colors, status),
                    width: _statusBarWidth,
                  ),
                ),
              ),
              child: ListTile(
                selected:
                    selectedEntryId != null && entry.id == selectedEntryId,
                selectedTileColor: colors.primary.withValues(alpha: 0.08),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.displayForm,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPhrase) ...[
                      const SizedBox(width: ListenSpacing.gap8),
                      _KindBadge(label: l.text('phrase')),
                    ],
                  ],
                ),
                subtitle: Text(
                  snapshot,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ListenType.body.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  hasMedia ? Icons.play_arrow : Icons.link_off,
                  color: colors.onSurfaceVariant,
                ),
                onTap: () => onWord(value),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: ListenRadii.tightBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ListenSpacing.gap6,
          vertical: ListenSpacing.gap2,
        ),
        child: Text(
          label,
          style: ListenType.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
