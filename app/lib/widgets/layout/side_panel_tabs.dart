import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../localization.dart';
import '../../theme/spacing.dart';

/// The side panel's two tabs.
///
/// There were five — transcript, resources, word, diagnosis, inbox — and four
/// of them could replace the transcript with something else. That is what made
/// this a router instead of a reading surface: every lookup cost the reader
/// their place in the text. Now the transcript never leaves, so the tab bar
/// only has to name the one other thing worth switching to.
///
/// Two tabs also means the labels always fit, which is why the icon-only
/// fallback and its breakpoint are gone: five unlabelled glyphs were a memory
/// test, two labelled words at any panel width are not.
class SidePanelTabs extends StatelessWidget {
  const SidePanelTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final SidePanelTab selected;
  final ValueChanged<SidePanelTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            for (final tab in SidePanelTab.values)
              _PanelTab(
                tab: tab,
                label: l.text(switch (tab) {
                  SidePanelTab.transcript => 'transcript',
                  SidePanelTab.notes => 'sessionNotes',
                }),
                selected: selected == tab,
                onTap: () => onSelected(tab),
              ),
          ],
        ),
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.tab,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SidePanelTab tab;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('side-panel-tab-${tab.name}'),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // The underline and the weight carry the selection; a filled block
          // would make the chrome itself the brightest thing on the panel.
          border: Border(
            bottom: BorderSide(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ListenSpacing.gap16,
            vertical: ListenSpacing.gap12,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? colors.primary : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
