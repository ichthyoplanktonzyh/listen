import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';

/// Shared color for a capability channel's effective assessment, used by both
/// the list snapshot icons and the filter chips so the two read as one system.
Color capabilityAssessmentColor(String assessment) => switch (assessment) {
  'acquired' => ListenColors.learningRecognized,
  'not_acquired' => ListenColors.accent,
  _ => ListenColors.muted.withValues(alpha: 0.45),
};

class VocabularyBookView extends StatelessWidget {
  const VocabularyBookView({
    super.key,
    required this.words,
    required this.onWord,
  });

  final List<LexicalEntryDetails> words;
  final ValueChanged<LexicalEntryDetails> onWord;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (words.isEmpty) {
      return Center(child: Text(l.text('noWords')));
    }
    return ListView.separated(
      itemCount: words.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final value = words[index];
        final entry = value.entry;
        final occurrences = value.occurrences;
        final profile = value.capabilityProfile;
        final isPhrase = entry.kind == 'phrase';
        final snapshot = occurrences.isEmpty
            ? l.text('noSourceSnapshot')
            : occurrences.first.sentenceTextSnapshot;
        final hasMedia =
            occurrences.isNotEmpty && occurrences.first.mediaId != null;
        return ListTile(
          title: Row(
            children: [
              Flexible(
                child: Text(entry.displayForm, overflow: TextOverflow.ellipsis),
              ),
              if (isPhrase) ...[
                const SizedBox(width: 8),
                _KindBadge(label: l.text('phrase')),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              _CapabilitySummary(profile: profile),
              const SizedBox(height: 3),
              Text(
                snapshot,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          isThreeLine: true,
          trailing: Icon(
            hasMedia ? Icons.play_arrow : Icons.link_off,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onTap: () => onWord(value),
        );
      },
    );
  }
}

/// Compact four-channel capability snapshot: one icon per channel, colored by
/// the channel's effective assessment (acquired / not_acquired / unassessed).
class _CapabilitySummary extends StatelessWidget {
  const _CapabilitySummary({required this.profile});

  final LexicalCapabilityProfile? profile;

  static const _channels = [
    ('reading', 'capabilityReading', Icons.menu_book_outlined),
    ('listening', 'capabilityListening', Icons.hearing_outlined),
    ('speaking', 'capabilitySpeaking', Icons.record_voice_over_outlined),
    ('writing', 'capabilityWriting', Icons.edit_outlined),
  ];

  String _assessment(String channel) {
    final p = profile;
    if (p == null) return 'unassessed';
    return switch (channel) {
      'reading' => p.reading.effectiveAssessment,
      'listening' => p.listening.effectiveAssessment,
      'speaking' => p.speaking.effectiveAssessment,
      _ => p.writing.effectiveAssessment,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (channel, labelKey, icon) in _channels)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Tooltip(
              message: '${l.text(labelKey)}: ${l.text(_assessment(channel))}',
              child: Icon(
                icon,
                size: 15,
                color: capabilityAssessmentColor(_assessment(channel)),
              ),
            ),
          ),
      ],
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
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
