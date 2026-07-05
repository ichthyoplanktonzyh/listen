import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../utils/format_duration.dart';

class ListeningHome extends StatelessWidget {
  const ListeningHome({
    super.key,
    required this.onOpenMedia,
    required this.onOpenOnline,
    required this.onContinue,
    required this.onOpenSubtitleResources,
    required this.onOpenVocabulary,
    required this.onOpenReview,
    required this.onOpenSettings,
    this.recentMediaTitle,
    this.recentMediaPath,
    this.recentPosition = Duration.zero,
    this.recentDuration = Duration.zero,
    this.recentSubtitleCount = 0,
    this.vocabularyCount = 0,
    this.vocabularyCapped = false,
    this.vocabularyKnown = false,
    this.listeningInboxCount = 0,
    this.statusText = '',
  });

  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback onContinue;
  final VoidCallback onOpenSubtitleResources;
  final VoidCallback onOpenVocabulary;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenSettings;
  final String? recentMediaTitle;
  final String? recentMediaPath;
  final Duration recentPosition;
  final Duration recentDuration;
  final int recentSubtitleCount;
  final int vocabularyCount;
  final bool vocabularyCapped;
  final bool vocabularyKnown;
  final int listeningInboxCount;
  final String statusText;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final showSidebar = constraints.maxWidth >= 760;
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          children: [
            if (showSidebar)
              SizedBox(
                width: 248,
                child: _HomeSidebar(
                  onOpenMedia: onOpenMedia,
                  onOpenOnline: onOpenOnline,
                  onOpenSubtitleResources: onOpenSubtitleResources,
                  onOpenVocabulary: onOpenVocabulary,
                  onOpenReview: onOpenReview,
                  onOpenSettings: onOpenSettings,
                ),
              ),
            Expanded(
              child: _HomeContent(
                compact: !showSidebar,
                onOpenMedia: onOpenMedia,
                onOpenOnline: onOpenOnline,
                onContinue: onContinue,
                onOpenSubtitleResources: onOpenSubtitleResources,
                onOpenVocabulary: onOpenVocabulary,
                onOpenReview: onOpenReview,
                recentMediaTitle: recentMediaTitle,
                recentMediaPath: recentMediaPath,
                recentPosition: recentPosition,
                recentDuration: recentDuration,
                recentSubtitleCount: recentSubtitleCount,
                vocabularyCount: vocabularyCount,
                vocabularyCapped: vocabularyCapped,
                vocabularyKnown: vocabularyKnown,
                listeningInboxCount: listeningInboxCount,
                statusText: statusText,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _HomeSidebar extends StatelessWidget {
  const _HomeSidebar({
    required this.onOpenMedia,
    required this.onOpenOnline,
    required this.onOpenSubtitleResources,
    required this.onOpenVocabulary,
    required this.onOpenReview,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback onOpenSubtitleResources;
  final VoidCallback onOpenVocabulary;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel(label: l.text('listenNow')),
            const SizedBox(height: 8),
            _SidebarItem(
              icon: Icons.home_outlined,
              label: l.text('home'),
              selected: true,
              onTap: () {},
            ),
            _SidebarItem(
              icon: Icons.video_file_outlined,
              label: l.text('openMedia'),
              onTap: onOpenMedia,
            ),
            _SidebarItem(
              icon: Icons.language_outlined,
              label: l.text('openUrl'),
              onTap: onOpenOnline,
            ),
            const SizedBox(height: 24),
            _SectionLabel(label: l.text('myLearning')),
            const SizedBox(height: 8),
            _SidebarItem(
              icon: Icons.inventory_2_outlined,
              label: l.text('subtitleResources'),
              onTap: onOpenSubtitleResources,
            ),
            _SidebarItem(
              icon: Icons.menu_book_outlined,
              label: l.text('vocabulary'),
              onTap: onOpenVocabulary,
            ),
            _SidebarItem(
              icon: Icons.headphones_outlined,
              label: l.text('review'),
              onTap: onOpenReview,
            ),
            const Spacer(),
            _SidebarItem(
              icon: Icons.settings_outlined,
              label: l.text('settings'),
              onTap: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.compact,
    required this.onOpenMedia,
    required this.onOpenOnline,
    required this.onContinue,
    required this.onOpenSubtitleResources,
    required this.onOpenVocabulary,
    required this.onOpenReview,
    required this.recentMediaTitle,
    required this.recentMediaPath,
    required this.recentPosition,
    required this.recentDuration,
    required this.recentSubtitleCount,
    required this.vocabularyCount,
    required this.vocabularyCapped,
    required this.vocabularyKnown,
    required this.listeningInboxCount,
    required this.statusText,
  });

  final bool compact;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback onContinue;
  final VoidCallback onOpenSubtitleResources;
  final VoidCallback onOpenVocabulary;
  final VoidCallback onOpenReview;
  final String? recentMediaTitle;
  final String? recentMediaPath;
  final Duration recentPosition;
  final Duration recentDuration;
  final int recentSubtitleCount;
  final int vocabularyCount;
  final bool vocabularyCapped;
  final bool vocabularyKnown;
  final int listeningInboxCount;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final horizontalPadding = compact ? 24.0 : 48.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        compact ? 28 : 44,
        horizontalPadding,
        40,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.text('library'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              _ContinueLearningCard(
                mediaTitle: recentMediaTitle,
                mediaPath: recentMediaPath,
                position: recentPosition,
                duration: recentDuration,
                onContinue: onContinue,
                onOpenMedia: onOpenMedia,
              ),
              const SizedBox(height: 14),
              _ResourceStatusStrip(
                recentSubtitleCount: recentSubtitleCount,
                hasRecentMedia: (recentMediaPath ?? '').isNotEmpty,
                vocabularyCount: vocabularyCount,
                vocabularyCapped: vocabularyCapped,
                vocabularyKnown: vocabularyKnown,
                listeningInboxCount: listeningInboxCount,
                statusText: statusText,
              ),
              const SizedBox(height: 32),
              Text(
                l.text('startListening'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _ResponsiveActionGrid(
                compact: compact,
                children: [
                  _SourceAction(
                    icon: Icons.folder_open_outlined,
                    label: l.text('openVideoAudio'),
                    sourceLabel: l.text('localSource'),
                    onTap: onOpenMedia,
                    primary: true,
                  ),
                  _SourceAction(
                    icon: Icons.link_outlined,
                    label: l.text('openUrl'),
                    sourceLabel: l.text('onlineSource'),
                    onTap: onOpenOnline,
                  ),
                ],
              ),
              const SizedBox(height: 36),
              Text(
                l.text('learningTools'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _ResponsiveActionGrid(
                compact: compact,
                children: [
                  _SourceAction(
                    icon: Icons.inventory_2_outlined,
                    label: l.text('subtitleResources'),
                    sourceLabel: l.text('subtitleResourceSummary'),
                    onTap: onOpenSubtitleResources,
                  ),
                  _SourceAction(
                    icon: Icons.menu_book_outlined,
                    label: l.text('vocabulary'),
                    sourceLabel: l.text('vocabularySummary'),
                    onTap: onOpenVocabulary,
                  ),
                  _SourceAction(
                    icon: Icons.headphones_outlined,
                    label: l.text('review'),
                    sourceLabel: l.text('audioFirstReview'),
                    onTap: onOpenReview,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsiveActionGrid extends StatelessWidget {
  const _ResponsiveActionGrid({required this.compact, required this.children});

  final bool compact;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          Expanded(child: children[index]),
          if (index != children.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _ContinueLearningCard extends StatelessWidget {
  const _ContinueLearningCard({
    required this.mediaTitle,
    required this.mediaPath,
    required this.position,
    required this.duration,
    required this.onContinue,
    required this.onOpenMedia,
  });

  final String? mediaTitle;
  final String? mediaPath;
  final Duration position;
  final Duration duration;
  final VoidCallback onContinue;
  final VoidCallback onOpenMedia;

  bool get _hasMedia => (mediaTitle ?? mediaPath ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final title = _hasMedia
        ? mediaTitle ?? mediaPath!.split('/').last
        : l.text('noRecentMedia');
    final progress = duration.inMilliseconds <= 0
        ? l.text('openMediaToContinue')
        : '${formatDuration(position)} / ${formatDuration(duration)}';
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _hasMedia ? onContinue : onOpenMedia,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _hasMedia
                      ? Icons.play_circle_outline
                      : Icons.folder_open_outlined,
                  color: colors.onPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.text('continueLearning'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      progress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _hasMedia ? onContinue : onOpenMedia,
                icon: Icon(_hasMedia ? Icons.play_arrow : Icons.add),
                label: Text(
                  _hasMedia ? l.text('continuePlayback') : l.text('openMedia'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceStatusStrip extends StatelessWidget {
  const _ResourceStatusStrip({
    required this.recentSubtitleCount,
    required this.hasRecentMedia,
    required this.vocabularyCount,
    required this.vocabularyCapped,
    required this.vocabularyKnown,
    required this.listeningInboxCount,
    required this.statusText,
  });

  final int recentSubtitleCount;
  final bool hasRecentMedia;
  final int vocabularyCount;
  final bool vocabularyCapped;
  final bool vocabularyKnown;
  final int listeningInboxCount;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final items = [
          _StatusItem(
            icon: Icons.subtitles_outlined,
            label: l.text('subtitleReadiness'),
            value: !hasRecentMedia
                ? '—'
                : recentSubtitleCount == 0
                ? l.text('notReadyYet')
                : '$recentSubtitleCount',
          ),
          _StatusItem(
            icon: Icons.menu_book_outlined,
            label: l.text('savedWords'),
            value: !vocabularyKnown
                ? '—'
                : vocabularyCapped
                ? '$vocabularyCount+'
                : '$vocabularyCount',
          ),
          _StatusItem(
            icon: Icons.inbox_outlined,
            label: l.text('listeningInbox'),
            value: '$listeningInboxCount',
          ),
          _StatusItem(
            icon: Icons.memory_outlined,
            label: l.text('localCore'),
            value: statusText.isEmpty ? l.text('coreReady') : statusText,
          ),
        ];
        if (compact) {
          return Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                _StatusTile(item: items[index]),
                if (index != items.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              Expanded(child: _StatusTile(item: items[index])),
              if (index != items.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }
}

class _StatusItem {
  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.item});

  final _StatusItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(item.icon, size: 18, color: colors.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceAction extends StatelessWidget {
  const _SourceAction({
    required this.icon,
    required this.label,
    required this.sourceLabel,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String sourceLabel;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: primary
          ? colors.primaryContainer.withValues(alpha: 0.42)
          : colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: primary
              ? colors.primary.withValues(alpha: 0.42)
              : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 112,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primary ? colors.primary : colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    icon,
                    color: primary
                        ? colors.onPrimary
                        : colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        sourceLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? colors.primary : colors.onSurface,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
