import 'package:flutter/material.dart';

import '../../theme/icon_size.dart';
import '../../theme/listen_theme.dart';
import '../../theme/spacing.dart';

/// One row inside a popup menu: glyph, title, and an optional second line.
///
/// The second line is where a *reason* goes — why an item is unavailable —
/// rather than the item silently greying out. Same rule as
/// `ContentChannelAvailability`: an unavailable thing says why.
class ListenMenuRow extends StatelessWidget {
  const ListenMenuRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// The title greys out for free via [PopupMenuItem]'s inherited text style;
  /// the icon and subtitle carry explicit colors, so they follow this flag.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final secondary = enabled
        ? colors.onSurfaceVariant
        : colors.disabledForeground;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260),
      child: Row(
        children: [
          Icon(icon, size: ListenIconSize.control, color: secondary),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: secondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A non-selectable label that groups the rows under it.
class ListenMenuHeader extends PopupMenuItem<String> {
  ListenMenuHeader({super.key, required String label})
    : super(
        enabled: false,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
