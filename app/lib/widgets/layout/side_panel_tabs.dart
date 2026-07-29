import 'package:flutter/material.dart';

import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';

/// One destination of the side panel's tab bar.
typedef SidePanelDestination = ({IconData icon, String label});

/// The side panel's five tabs (§3.7 item 6).
///
/// Five unlabelled glyphs is a memory test: transcript, resources, word,
/// diagnosis and inbox are not conventional enough to be recognised by icon
/// alone, and the panel is where a learner spends the session. From
/// [ListenBreakpoints.sidePanelTabLabels] up, each icon carries its name; below
/// it the label is dropped rather than truncated, and the tooltip — which
/// carries the same wording at every width — is what keeps the name reachable.
///
/// Extracted from `SidePanel` so the label breakpoint can be tested without
/// standing up the panel's eight controllers.
class SidePanelTabs extends StatelessWidget {
  const SidePanelTabs({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<SidePanelDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabels =
              constraints.maxWidth >= ListenBreakpoints.sidePanelTabLabels;
          return SizedBox(
            height: showLabels ? 58 : 52,
            child: Row(
              children: [
                for (var index = 0; index < destinations.length; index++)
                  Expanded(
                    child: _PanelTab(
                      icon: destinations[index].icon,
                      label: destinations[index].label,
                      selected: selectedIndex == index,
                      showLabel: showLabels,
                      onTap: () => onSelected(index),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Shell recedes (#30): the teal underline and glyph carry the
            // selection alone — a filled block made the chrome itself glow.
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: selected ? colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: showLabel
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: ListenIconSize.chrome,
                        color: selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: ListenSpacing.gap2),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Icon(
                    icon,
                    size: ListenIconSize.chrome,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );
  }
}
