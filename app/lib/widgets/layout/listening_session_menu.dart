import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/menu_rows.dart';

/// The extensive-listening session: start and finish it, hunt, capture what
/// went past, stop to deal with it.
///
/// These were on the transport, next to play and volume, which put a session
/// that spans a whole sitting among controls that act on the next 200
/// milliseconds. They belong with the other things that are true of this
/// session as a whole, on the session header.
class ListeningSessionMenu extends StatelessWidget {
  const ListeningSessionMenu({
    super.key,
    required this.active,
    required this.huntingActive,
    required this.markEnabled,
    required this.inboxCount,
    required this.onToggleListening,
    required this.onToggleHunting,
    required this.onCaptureInbox,
    required this.onHardInterrupt,
    this.onViewInbox,
  });

  final bool active;
  final bool huntingActive;

  /// Marking and interrupting need a current sentence to attach to.
  final bool markEnabled;
  final int inboxCount;
  final VoidCallback onToggleListening;
  final VoidCallback? onToggleHunting;
  final VoidCallback onCaptureInbox;
  final VoidCallback onHardInterrupt;

  /// Opens the box the marks land in. Null where the host cannot show it;
  /// the row then greys out with the same empty reason as an empty box.
  final VoidCallback? onViewInbox;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    // A running session is a state the learner is in, so it lights up; idle
    // sits with the rest of the chrome.
    final tint = active ? colors.primary : colors.onSurfaceVariant;
    return PopupMenuButton<String>(
      key: const Key('listening-session-menu'),
      tooltip: l.text('listeningMode'),
      onSelected: (value) {
        switch (value) {
          case 'toggle-listening':
            onToggleListening();
          case 'toggle-hunting':
            onToggleHunting?.call();
          case 'mark-inbox':
            onCaptureInbox();
          case 'view-inbox':
            onViewInbox?.call();
          case 'hard-interrupt':
            onHardInterrupt();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'toggle-listening',
          child: ListenMenuRow(
            icon: active ? Icons.hearing : Icons.hearing_outlined,
            title: active
                ? l.text('finishExtensiveListening')
                : l.text('startExtensiveListening'),
          ),
        ),
        PopupMenuItem(
          value: 'toggle-hunting',
          enabled: markEnabled && onToggleHunting != null,
          child: ListenMenuRow(
            enabled: markEnabled && onToggleHunting != null,
            icon: huntingActive ? Icons.gps_fixed : Icons.gps_not_fixed,
            title: huntingActive
                ? l.text('huntingStopMode')
                : l.text('huntingStartMode'),
          ),
        ),
        PopupMenuItem(
          value: 'mark-inbox',
          enabled: markEnabled,
          child: ListenMenuRow(
            enabled: markEnabled,
            icon: Icons.bookmark_add_outlined,
            title: l.text('markListeningInbox'),
          ),
        ),
        PopupMenuItem(
          value: 'view-inbox',
          enabled: onViewInbox != null && inboxCount > 0,
          child: ListenMenuRow(
            enabled: onViewInbox != null && inboxCount > 0,
            icon: Icons.inbox_outlined,
            title: l.text('viewListeningInbox'),
            subtitle: inboxCount > 0 ? null : l.text('listeningInboxEmpty'),
          ),
        ),
        PopupMenuItem(
          value: 'hard-interrupt',
          enabled: markEnabled,
          child: ListenMenuRow(
            enabled: markEnabled,
            icon: Icons.pause_circle_outline,
            title: l.text('hardInterruptListening'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ListenSpacing.gap8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.hearing : Icons.hearing_outlined,
              size: ListenIconSize.chrome,
              color: tint,
            ),
            if (inboxCount > 0) ...[
              const SizedBox(width: ListenSpacing.gap4),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: ListenRadii.pillBorder,
                ),
                child: Padding(
                  padding: ListenPadding.tight,
                  child: Text(
                    '$inboxCount',
                    key: const Key('listening-inbox-badge'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: ListenSpacing.gap2),
            Icon(
              Icons.arrow_drop_down,
              size: ListenIconSize.control,
              color: tint,
            ),
          ],
        ),
      ),
    );
  }
}
