import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../listen_wordmark.dart';

/// The shell's renderable destinations — every value here swaps the main pane
/// in place and carries the sidebar's selection state.
///
enum AppRoute {
  /// Resume the current context or find the next material.
  home,

  /// Manage material already owned and bring new local material into the app.
  library,

  /// The language the learner has collected, and the practice on it:
  /// vocabulary and review as segments of one page.
  language,

  /// Saved language patterns the learner can return to and practise.
  expressions,
}

/// Persistent application navigation: three destinations, no group headings.
///
/// The rail used to carry seven destinations under three headings (content /
/// learning / insight). Those headings were the symptom, not the structure —
/// they existed to explain a list nobody could hold in their head, and they
/// grouped by the system's object model (media, words, patterns, cards,
/// profile) rather than by what the learner came to do. Four destinations
/// need no headings to explain themselves.
///
/// Destinations are followed by tools and settings — things you do, not places
/// you can be.
///
/// The utilities landed here when the shell app bar was deleted. That bar was
/// a fourth navigation: its content and learning menus repeated the native
/// macOS menu bar, this rail, and the pages themselves, its settings button
/// repeated this rail's own footer, and its wordmark repeated this rail's
/// header forty pixels below. What it carried that nothing else did was
/// tools, and tools belong beside settings.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentRoute,
    required this.onRouteSelected,
    this.onOpenSettings,
    this.toolsMenu,
  });

  final AppRoute currentRoute;
  final ValueChanged<AppRoute> onRouteSelected;

  final VoidCallback? onOpenSettings;

  /// The homeless tools (asset centres, diagnostics, data import/export), or
  /// null on a surface with none wired.
  final Widget? toolsMenu;

  /// Fixed: the rail is chrome, not content, so it does not compete with the
  /// pane for width. Exposed because the window minimum has to clear it —
  /// see `window_min_size_test.dart`.
  static const railWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: railWidth,
      color: colors.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ListenSpacing.gap16,
              vertical: ListenSpacing.gap16,
            ),
            child: const ListenWordmark(size: 22),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: ListenSpacing.gap8,
              ),
              children: [
                _SidebarItem(
                  icon: Icons.explore_outlined,
                  label: l.text('sidebarHome'),
                  isSelected: currentRoute == AppRoute.home,
                  onTap: () => onRouteSelected(AppRoute.home),
                ),
                _SidebarItem(
                  icon: Icons.folder_outlined,
                  label: l.text('sidebarLibrary'),
                  isSelected: currentRoute == AppRoute.library,
                  onTap: () => onRouteSelected(AppRoute.library),
                ),
                _SidebarItem(
                  icon: Icons.menu_book_outlined,
                  label: l.text('sidebarMyLanguage'),
                  isSelected: currentRoute == AppRoute.language,
                  onTap: () => onRouteSelected(AppRoute.language),
                ),
                _SidebarItem(
                  icon: Icons.bookmark_border,
                  label: l.text('sidebarExpressions'),
                  isSelected: currentRoute == AppRoute.expressions,
                  onTap: () => onRouteSelected(AppRoute.expressions),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          if (toolsMenu != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ListenSpacing.gap8,
              ),
              child: toolsMenu!,
            ),
          if (onOpenSettings != null)
            Padding(
              padding: const EdgeInsets.only(
                left: ListenSpacing.gap8,
                right: ListenSpacing.gap8,
                bottom: ListenSpacing.gap8,
              ),
              child: _SidebarItem(
                icon: Icons.settings_outlined,
                label: l.text('settings'),
                isSelected: false,
                onTap: onOpenSettings!,
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: ListenRadii.controlBorder,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: ListenRadii.controlBorder,
          color: isSelected ? colors.secondaryContainer : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: ListenSpacing.gap12,
          vertical: ListenSpacing.gap8,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: ListenIconSize.control,
              color: isSelected
                  ? colors.onSecondaryContainer
                  : colors.onSurfaceVariant,
            ),
            const SizedBox(width: ListenSpacing.gap12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isSelected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
