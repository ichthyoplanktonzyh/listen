import 'package:flutter/material.dart';

import '../../controllers/review_due_controller.dart';
import '../../localization.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../common/listen_loading.dart';

/// The opening pane: what to do now, and nothing else.
///
/// Charter principle 3 — "present, but never pushy" — is the whole design
/// here. Everything on this page is a *door the learner walks through*, never
/// a task assigned to them: it is read when they arrive, it never pushes,
/// never counts streaks, never accrues guilt. `reviewDueInfoNote` says the
/// same thing on the review home and is repeated here on purpose.
///
/// The doors lead somewhere that exists. The listening inbox is deliberately
/// *not* a door: it lives inside the workbench's listening panel, and a tile
/// that opened the workbench would be a second copy of "continue listening".
/// It states its count and stops there.
class TodayPane extends StatelessWidget {
  const TodayPane({
    super.key,
    required this.recentMediaTitle,
    required this.recentMediaPath,
    required this.recentPosition,
    required this.recentDuration,
    required this.onContinue,
    required this.onOpenMedia,
    required this.reviewDue,
    required this.onOpenReview,
    required this.onRetryReviewDue,
    required this.onOpenVocabulary,
    required this.vocabularyCount,
    required this.vocabularyCapped,
    required this.vocabularyKnown,
    required this.listeningInboxCount,
    required this.recentSubtitleCount,
    required this.coreStatusText,
  });

  final String? recentMediaTitle;
  final String? recentMediaPath;
  final Duration recentPosition;
  final Duration recentDuration;
  final VoidCallback onContinue;
  final VoidCallback onOpenMedia;

  /// Subtitle lines on the recent media. It describes *that* media, so it
  /// rides on the continue card instead of claiming a tile of its own.
  final int recentSubtitleCount;

  /// Health line for the local core. Empty means nothing to report, which
  /// renders as the ready state. A disconnected core is why every other row
  /// on this page may read as unknown, so the line stays visible rather than
  /// appearing only on trouble.
  final String coreStatusText;

  /// How much the shell knows about the due count. Rendered as four
  /// distinguishable states — never flattened to a number.
  final ReviewDueState reviewDue;
  final VoidCallback onOpenReview;
  final VoidCallback onRetryReviewDue;

  final VoidCallback onOpenVocabulary;

  /// Saved-word total. [vocabularyKnown] false means nobody has reported one
  /// yet, which is drawn as unknown rather than as zero.
  final int vocabularyCount;
  final bool vocabularyCapped;
  final bool vocabularyKnown;

  /// Locally tracked, so it is always known — zero here really is zero.
  final int listeningInboxCount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < ListenBreakpoints.homeSidebar;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: SingleChildScrollView(
            padding: compact ? ListenPadding.pageCompact : ListenPadding.page,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ListenBreakpoints.wideColumnMax,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.text('sidebarToday'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: ListenSpacing.gap16),
                    ContinueLearningCard(
                      mediaTitle: recentMediaTitle,
                      mediaPath: recentMediaPath,
                      position: recentPosition,
                      duration: recentDuration,
                      subtitleCount: recentSubtitleCount,
                      onContinue: onContinue,
                      onOpenMedia: onOpenMedia,
                    ),
                    const SizedBox(height: ListenSpacing.gap12),
                    _ReviewDoor(
                      state: reviewDue,
                      onOpen: onOpenReview,
                      onRetry: onRetryReviewDue,
                    ),
                    const SizedBox(height: ListenSpacing.gap12),
                    _TodayTile(
                      icon: Icons.menu_book_outlined,
                      label: l.text('savedWords'),
                      // Unknown stays a dash: the composition root only knows
                      // a total once the core has reported one.
                      value: !vocabularyKnown
                          ? null
                          : vocabularyCapped
                          ? '$vocabularyCount+'
                          : '$vocabularyCount',
                      onOpen: onOpenVocabulary,
                    ),
                    const SizedBox(height: ListenSpacing.gap12),
                    _TodayTile(
                      icon: Icons.inbox_outlined,
                      label: l.text('listeningInbox'),
                      value: '$listeningInboxCount',
                      // Not a door: the inbox is a panel inside the
                      // workbench, so there is nowhere separate to go.
                      onOpen: null,
                    ),
                    const SizedBox(height: ListenSpacing.gap12),
                    _TodayTile(
                      icon: Icons.memory_outlined,
                      label: l.text('localCore'),
                      value: null,
                      counted: false,
                      note: coreStatusText.isEmpty
                          ? l.text('coreReady')
                          : coreStatusText,
                      onOpen: null,
                    ),
                    const SizedBox(height: ListenSpacing.gap16),
                    Text(
                      l.text('reviewDueInfoNote'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The due-count door, drawn once per [ReviewDueStatus].
///
/// The four states are the point of this widget. Collapsing `unknown`,
/// `loading` or `failed` into `0` would tell the learner their day is clear
/// when nobody has said so.
class _ReviewDoor extends StatelessWidget {
  const _ReviewDoor({
    required this.state,
    required this.onOpen,
    required this.onRetry,
  });

  final ReviewDueState state;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (state.status) {
      ReviewDueStatus.unknown => _TodayTile(
        icon: Icons.headphones_outlined,
        label: l.text('reviewDueToday'),
        value: null,
        note: l.text('statusConnectLocalCoreFirst'),
        onOpen: null,
      ),
      ReviewDueStatus.loading => _TodayTile(
        icon: Icons.headphones_outlined,
        label: l.text('reviewDueToday'),
        value: null,
        trailing: const ListenLoading.inline(),
        onOpen: null,
      ),
      // A real zero is still a door: "nothing is due today" is something the
      // review home says better than a disabled tile does.
      ReviewDueStatus.loaded => _TodayTile(
        icon: Icons.headphones_outlined,
        label: l.text('reviewDueToday'),
        value: '${state.count}',
        onOpen: onOpen,
      ),
      ReviewDueStatus.failed => _TodayTile(
        icon: Icons.headphones_outlined,
        label: l.text('reviewDueToday'),
        value: null,
        note: l.text('todayReviewDueFailed'),
        trailing: TextButton(
          onPressed: onRetry,
          child: Text(l.text('retry')),
        ),
        onOpen: null,
      ),
    };
  }
}

/// One row on the today pane. With [onOpen] it is a door (tappable, tipped
/// with a chevron); without it, a statement.
class _TodayTile extends StatelessWidget {
  const _TodayTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onOpen,
    this.counted = true,
    this.note,
    this.trailing,
  });

  final IconData icon;
  final String label;

  /// The number, or null when there is no number to report *yet*. Null
  /// renders an em dash — the app's existing "not known" glyph — never a
  /// zero.
  final String? value;

  /// False for a tile that reports no number at all (the core's health line).
  /// Such a tile draws nothing where the count would go, because an em dash
  /// there would read as "a count that is not known".
  final bool counted;

  final String? note;
  final Widget? trailing;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final body = Padding(
      padding: ListenPadding.row,
      child: Row(
        children: [
          Icon(icon, size: ListenIconSize.control, color: colors.primary),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (note != null) ...[
                  const SizedBox(height: ListenSpacing.gap4),
                  Text(
                    note!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (counted) ...[
            const SizedBox(width: ListenSpacing.gap8),
            Text(
              value ?? '—',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: ListenSpacing.gap8),
            trailing!,
          ],
          if (onOpen != null) ...[
            const SizedBox(width: ListenSpacing.gap8),
            Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          ],
        ],
      ),
    );

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: onOpen == null ? body : InkWell(onTap: onOpen, child: body),
    );
  }
}

/// "Pick up where you stopped" — the first door on the today pane.
///
/// It used to live on the media library page, which is why the library also
/// answered "what should I do now". It answers one question now, in one
/// place.
class ContinueLearningCard extends StatelessWidget {
  const ContinueLearningCard({
    super.key,
    required this.mediaTitle,
    required this.mediaPath,
    required this.position,
    required this.duration,
    required this.subtitleCount,
    required this.onContinue,
    required this.onOpenMedia,
  });

  final String? mediaTitle;
  final String? mediaPath;
  final Duration position;
  final Duration duration;

  /// Subtitle lines on this media — the L1 rung of the learnability ladder.
  /// Zero means the transcript is not there yet, which is a different fact
  /// from "no media at all" and is only shown when there is media.
  final int subtitleCount;

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
    final readiness = !_hasMedia
        ? null
        : subtitleCount == 0
        ? '${l.text('subtitleReadiness')} · ${l.text('notReadyYet')}'
        : '${l.text('subtitleReadiness')} · $subtitleCount';
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.42),
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(color: colors.primary.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _hasMedia ? onContinue : onOpenMedia,
        child: Padding(
          padding: ListenPadding.card,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: ListenRadii.controlBorder,
                ),
                child: Icon(
                  _hasMedia
                      ? Icons.play_circle_outline
                      : Icons.folder_open_outlined,
                  color: colors.onPrimary,
                ),
              ),
              const SizedBox(width: ListenSpacing.gap16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: ListenSpacing.gap4),
                    Text(
                      readiness == null ? progress : '$progress · $readiness',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
