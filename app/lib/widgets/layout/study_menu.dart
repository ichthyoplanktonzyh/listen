import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/workbench_study_mode.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/menu_rows.dart';

/// Listening display and direct listening exercises for the current material.
class StudyMenu extends StatelessWidget {
  const StudyMenu({
    super.key,
    required this.selectedMode,
    required this.onModeSelected,
    required this.hasCue,
    required this.canCloze,
    required this.canChunkDictation,
    required this.onCloze,
    required this.onChunkDictation,
    required this.onSentenceDictation,
  });

  final WorkbenchStudyMode selectedMode;
  final ValueChanged<WorkbenchStudyMode> onModeSelected;
  final bool hasCue;
  final bool canCloze;
  final bool canChunkDictation;
  final VoidCallback onCloze;
  final VoidCallback onChunkDictation;
  final VoidCallback onSentenceDictation;

  static const _modeValuePrefix = 'mode-';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    return PopupMenuButton<String>(
      key: const Key('study-menu'),
      tooltip: l.text('studyMode'),
      onSelected: (value) {
        if (value.startsWith(_modeValuePrefix)) {
          final name = value.substring(_modeValuePrefix.length);
          onModeSelected(
            WorkbenchStudyMode.values.firstWhere((mode) => mode.name == name),
          );
          return;
        }
        switch (value) {
          case 'cloze':
            onCloze();
          case 'chunk':
            onChunkDictation();
          case 'sentence':
            onSentenceDictation();
        }
      },
      itemBuilder: (_) => [
        ListenMenuHeader(label: l.text('studyModeListeningGroup')),
        _modeItem(
          l,
          WorkbenchStudyMode.normal,
          Icons.article_outlined,
          'studyModeNormal',
          'studyModeNormalHint',
        ),
        _modeItem(
          l,
          WorkbenchStudyMode.blindListening,
          Icons.hearing_outlined,
          'studyModeBlind',
          'studyModeBlindHint',
        ),
        const PopupMenuDivider(),
        ListenMenuHeader(label: l.text('studyModeIntensiveGroup')),
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
              _modeIcon(selectedMode),
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

  PopupMenuItem<String> _modeItem(
    AppLocalizations l,
    WorkbenchStudyMode mode,
    IconData icon,
    String title,
    String hint,
  ) {
    final selected = selectedMode == mode;
    return PopupMenuItem(
      key: ValueKey('study-mode-${mode.name}'),
      value: '$_modeValuePrefix${mode.name}',
      child: ListenMenuRow(
        icon: selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        title: l.text(title),
        subtitle: l.text(hint),
      ),
    );
  }

  static IconData _modeIcon(WorkbenchStudyMode mode) => switch (mode) {
    WorkbenchStudyMode.normal => Icons.article_outlined,
    WorkbenchStudyMode.blindListening => Icons.hearing_outlined,
  };
}
