import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/menu_rows.dart';

/// Every way of working this material, in one menu on the session header.
///
/// These used to be spread over four places at once: a 2×2 posture grid above
/// the transcript, a popup inside one of its cells, the content-channel pills
/// in this same header, and two more menus down on the transport. Four
/// locations for one question — *how do I want to work this material* — which
/// meant nobody could say where "cloze" lived without hunting for it.
///
/// The grouping is the information: reading is one way through the whole
/// text, the intensive modes work one sentence hard. (Speaking and writing are
/// still on the channel switcher beside this menu; they join here when the
/// switcher goes.)
class StudyMenu extends StatelessWidget {
  const StudyMenu({
    super.key,
    required this.hasCue,
    required this.canRead,
    required this.canCloze,
    required this.canChunkDictation,
    required this.onRead,
    required this.onShadow,
    required this.onCloze,
    required this.onChunkDictation,
    required this.onSentenceDictation,
  });

  /// The intensive modes work on the sentence being played. Without one they
  /// are listed and disabled rather than hidden, so the menu never changes
  /// shape underfoot.
  final bool hasCue;

  /// Reading needs a transcript, not a current sentence.
  final bool canRead;

  /// Whether cloze and chunk dictation have the timing data they need. Both
  /// stay listed either way; the subtitle says what is missing instead of the
  /// row silently disappearing.
  final bool canCloze;
  final bool canChunkDictation;

  final VoidCallback? onRead;
  final VoidCallback onShadow;
  final VoidCallback onCloze;
  final VoidCallback onChunkDictation;
  final VoidCallback onSentenceDictation;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    return PopupMenuButton<String>(
      key: const Key('study-menu'),
      tooltip: l.text('studyMode'),
      onSelected: (value) {
        switch (value) {
          case 'read':
            onRead?.call();
          case 'shadow':
            onShadow();
          case 'cloze':
            onCloze();
          case 'chunk':
            onChunkDictation();
          case 'sentence':
            onSentenceDictation();
        }
      },
      itemBuilder: (_) => [
        ListenMenuHeader(label: l.text('studyModeReadingGroup')),
        PopupMenuItem(
          value: 'read',
          enabled: canRead && onRead != null,
          child: ListenMenuRow(
            enabled: canRead && onRead != null,
            icon: Icons.chrome_reader_mode_outlined,
            title: l.text('postureReadTitle'),
            subtitle: l.text('postureReadHint'),
          ),
        ),
        const PopupMenuDivider(),
        ListenMenuHeader(label: l.text('studyModeIntensiveGroup')),
        PopupMenuItem(
          value: 'shadow',
          enabled: hasCue,
          child: ListenMenuRow(
            enabled: hasCue,
            icon: Icons.mic_none,
            title: l.text('postureShadowTitle'),
            subtitle: l.text('postureShadowHint'),
          ),
        ),
        PopupMenuItem(
          value: 'cloze',
          enabled: hasCue && canCloze,
          child: ListenMenuRow(
            enabled: hasCue && canCloze,
            icon: Icons.text_fields,
            title: l.text('clozePractice'),
            subtitle: canCloze
                ? l.text('practiceClozeTooltip')
                : l.text('practiceClozeUnavailable'),
          ),
        ),
        PopupMenuItem(
          value: 'chunk',
          enabled: hasCue,
          child: ListenMenuRow(
            enabled: hasCue,
            icon: Icons.segment,
            title: l.text('chunkDictation'),
            subtitle: canChunkDictation
                ? l.text('practiceChunkTooltip')
                : l.text('practiceChunkFallbackTooltip'),
          ),
        ),
        PopupMenuItem(
          value: 'sentence',
          enabled: hasCue,
          child: ListenMenuRow(
            enabled: hasCue,
            icon: Icons.short_text,
            title: l.text('sentenceDictation'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ListenSpacing.gap8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.school_outlined,
              size: ListenIconSize.chrome,
              color: quiet,
            ),
            const SizedBox(width: ListenSpacing.gap2),
            Icon(
              Icons.arrow_drop_down,
              size: ListenIconSize.control,
              color: quiet,
            ),
          ],
        ),
      ),
    );
  }
}
