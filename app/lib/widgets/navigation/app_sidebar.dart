import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../listen_wordmark.dart';

/// Top-level application routes shown in the navigation sidebar.
///
/// Routes split by what they are, not by feature age: destinations
/// (discovery, resources, history, vocabulary, expression, review, coach)
/// swap the shell pane in place and carry the sidebar's selection state;
/// [AppRoute.conversation] is the one launched experience — an immersive
/// stage pushed over the shell, like the player workbench — so it reads as
/// an activity door rather than a place.
enum AppRoute {
  discovery,
  resources,
  history,
  vocabulary,
  expression,
  review,
  coach,
  conversation,
}

/// Persistent application navigation, grouped by user intent: content (what
/// to listen to), learning (what to practise), insight (what the profile
/// says). One rail owns every standing destination — page-level rails and
/// their duplicates are gone.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentRoute,
    required this.onRouteSelected,
    this.onOpenSettings,
  });

  final AppRoute currentRoute;
  final ValueChanged<AppRoute> onRouteSelected;
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
                _SidebarItem(
                  icon: Icons.forum_outlined,
                  label: l.text('conversation'),
                  isSelected: currentRoute == AppRoute.conversation,
                  onTap: () => onRouteSelected(AppRoute.conversation),
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
          if (onOpenSettings != null)
            Padding(
              padding: const EdgeInsets.all(ListenSpacing.gap8),
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
