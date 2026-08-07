import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../listen_wordmark.dart';

/// The shell's renderable destinations — every value here swaps the main pane
/// in place and carries the sidebar's selection state.
///
/// The enum is deliberately closed to destinations only. Conversation is the
/// one launched experience — an immersive stage pushed over the shell, like
/// the player workbench — so it is not a route value at all: it reaches the
/// shell as [AppSidebar.onOpenConversation]. Keeping it out of the type is
/// what lets the shell's route `switch` stay exhaustive without an
/// unreachable arm, and stops the rail from offering a selection state that
/// could never be true.
enum AppRoute {
  /// The one opening question: what should I do now.
  today,

  /// Where material comes from and what is already here — discovery and the
  /// media library are two segments of one page, because they end in the same
  /// library.
  listen,

  /// The language the learner has collected, and the practice on it:
  /// vocabulary, expressions and review as segments of one page.
  language,

  /// What the evidence says about the four channels.
  coach,
}

/// Persistent application navigation: four destinations, no group headings.
///
/// The rail used to carry seven destinations under three headings (content /
/// learning / insight). Those headings were the symptom, not the structure —
/// they existed to explain a list nobody could hold in their head, and they
/// grouped by the system's object model (media, words, patterns, cards,
/// profile) rather than by what the learner came to do. Four destinations
/// need no headings to explain themselves.
///
/// The rail carries three kinds of entry, and draws them differently on
/// purpose: destinations (the list, one of them always selected); the single
/// launch action at the foot, which opens the conversation stage over the
/// shell and therefore never shows a selection state; and below that the
/// utilities — tools and settings — which are things you *do*, not places you
/// can be, and so never draw a selection either.
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
    required this.onOpenConversation,
    this.onOpenSettings,
    this.toolsMenu,
  });

  final AppRoute currentRoute;
  final ValueChanged<AppRoute> onRouteSelected;

  /// Launches the immersive conversation stage. Separate from
  /// [onRouteSelected] because the shell never renders conversation as a pane.
  final VoidCallback onOpenConversation;
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
                  icon: Icons.wb_sunny_outlined,
                  label: l.text('sidebarToday'),
                  isSelected: currentRoute == AppRoute.today,
                  onTap: () => onRouteSelected(AppRoute.today),
                ),
                _SidebarItem(
                  icon: Icons.headphones_outlined,
                  label: l.text('sidebarListen'),
                  isSelected: currentRoute == AppRoute.listen,
                  onTap: () => onRouteSelected(AppRoute.listen),
                ),
                _SidebarItem(
                  icon: Icons.menu_book_outlined,
                  label: l.text('sidebarMyLanguage'),
                  isSelected: currentRoute == AppRoute.language,
                  onTap: () => onRouteSelected(AppRoute.language),
                ),
                _SidebarItem(
                  icon: Icons.insights_outlined,
                  label: l.text('coachDashboard'),
                  isSelected: currentRoute == AppRoute.coach,
                  onTap: () => onRouteSelected(AppRoute.coach),
                ),
              ],
            ),
          ),
          // Below the destination list the rail changes grammar: the divider
          // marks where "places you can be" ends and "things you can start"
          // begins.
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ListenSpacing.gap8,
              vertical: ListenSpacing.gap8,
            ),
            child: _SidebarLaunchAction(
              icon: Icons.forum_outlined,
              label: l.text('sidebarStartConversation'),
              onTap: onOpenConversation,
            ),
          ),
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

/// The rail's one launch affordance: it opens an experience over the shell
/// rather than swapping the pane, so it is drawn as a door — outlined instead
/// of fillable, tinted with the primary role, and tipped with a leaving arrow.
/// It takes no `isSelected`, because nothing it opens can ever be "where you
/// are" in the rail.
class _SidebarLaunchAction extends StatelessWidget {
  const _SidebarLaunchAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
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
          border: Border.all(color: colors.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: ListenSpacing.gap12,
          vertical: ListenSpacing.gap8,
        ),
        child: Row(
          children: [
            Icon(icon, size: ListenIconSize.control, color: colors.primary),
            const SizedBox(width: ListenSpacing.gap12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // The arrow says the shell is left behind, not re-rendered.
            Icon(
              Icons.arrow_outward,
              size: ListenIconSize.inline,
              color: colors.primary,
            ),
          ],
        ),
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
