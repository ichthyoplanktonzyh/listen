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
  discovery,
  resources,
  history,
  vocabulary,
  expression,
  review,
  coach,
}

/// Persistent application navigation, grouped by user intent: content (what
/// to listen to), learning (what to practise), insight (what the profile
/// says). One rail owns every standing destination — page-level rails and
/// their duplicates are gone.
///
/// The rail carries two kinds of entry, and draws them differently on
/// purpose: destinations (the grouped list, one of them always selected) and
/// the single launch action at the foot, which opens the conversation stage
/// over the shell and therefore never shows a selection state.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentRoute,
    required this.onRouteSelected,
    required this.onOpenConversation,
    this.onOpenSettings,
  });

  final AppRoute currentRoute;
  final ValueChanged<AppRoute> onRouteSelected;

  /// Launches the immersive conversation stage. Separate from
  /// [onRouteSelected] because the shell never renders conversation as a pane.
  final VoidCallback onOpenConversation;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 240,
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
                _SidebarSectionTitle(title: l.text('sidebarSectionContent')),
                _SidebarItem(
                  icon: Icons.explore_outlined,
                  label: l.text('sidebarToday'),
                  isSelected: currentRoute == AppRoute.discovery,
                  onTap: () => onRouteSelected(AppRoute.discovery),
                ),
                _SidebarItem(
                  icon: Icons.folder_outlined,
                  label: l.text('sidebarMyResources'),
                  isSelected: currentRoute == AppRoute.resources,
                  onTap: () => onRouteSelected(AppRoute.resources),
                ),
                _SidebarItem(
                  icon: Icons.history,
                  label: l.text('sidebarHistory'),
                  isSelected: currentRoute == AppRoute.history,
                  onTap: () => onRouteSelected(AppRoute.history),
                ),
                const SizedBox(height: ListenSpacing.gap16),
                _SidebarSectionTitle(title: l.text('sidebarSectionLearning')),
                _SidebarItem(
                  icon: Icons.menu_book_outlined,
                  label: l.text('sidebarVocabulary'),
                  isSelected: currentRoute == AppRoute.vocabulary,
                  onTap: () => onRouteSelected(AppRoute.vocabulary),
                ),
                _SidebarItem(
                  icon: Icons.format_quote_outlined,
                  label: l.text('sidebarExpression'),
                  isSelected: currentRoute == AppRoute.expression,
                  onTap: () => onRouteSelected(AppRoute.expression),
                ),
                _SidebarItem(
                  icon: Icons.headphones_outlined,
                  label: l.text('review'),
                  isSelected: currentRoute == AppRoute.review,
                  onTap: () => onRouteSelected(AppRoute.review),
                ),
                const SizedBox(height: ListenSpacing.gap16),
                _SidebarSectionTitle(title: l.text('sidebarSectionInsight')),
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

class _SidebarSectionTitle extends StatelessWidget {
  const _SidebarSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ListenSpacing.gap12,
        vertical: ListenSpacing.gap8,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
