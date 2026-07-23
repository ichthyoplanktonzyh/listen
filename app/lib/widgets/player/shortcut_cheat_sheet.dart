import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../player_shortcuts.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// #25: the keyboard cheat sheet. Rendered straight from [playerShortcuts]
/// — the table is the single source, this dialog is only a view of it.
Future<void> showShortcutCheatSheet(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const ShortcutCheatSheet(),
);

class ShortcutCheatSheet extends StatelessWidget {
  const ShortcutCheatSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.text('shortcutsTitle')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final category in PlayerShortcutCategory.values) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: ListenSpacing.gap16,
                    bottom: ListenSpacing.gap6,
                  ),
                  child: Text(
                    l.text(category.labelKey),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final shortcut in playerShortcuts)
                  if (shortcut.category == category)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.text(shortcut.labelKey),
                              style: ListenType.body,
                            ),
                          ),
                          const SizedBox(width: ListenSpacing.gap12),
                          _Keycap(caption: shortcutCaption(shortcut.activator)),
                        ],
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.text('close')),
        ),
      ],
    );
  }
}

class _Keycap extends StatelessWidget {
  const _Keycap({required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: ListenRadii.tightBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          caption,
          style: ListenType.timecode.copyWith(
            fontSize: 11,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
