import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/listen_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// The four learning postures offered for the current sentence, as a fixed 2×2
/// grid (§3.7 item 3).
///
/// Two things were wrong with the row of four outlined buttons this replaces.
/// It was a [Wrap], so the panel width broke it into 3+1 — a ragged shape that
/// reads as "three things, and one other thing" when the four are siblings of
/// equal standing. And every label was a question ending in the same mark
/// (`Understand? / Test? / Shadow? / Read?`), which made them sound alike
/// while telling nobody what Shadow does that Read does not.
///
/// So the grid is fixed rather than responsive — the pairing is the
/// information — and each cell carries an action name plus one line of what
/// happens. Extracted from `SidePanel` so the shape can be tested without
/// standing up the panel's eight controllers.
class PostureActions extends StatelessWidget {
  const PostureActions({
    super.key,
    required this.hasCue,
    required this.canCloze,
    required this.canChunkDictation,
    required this.canRead,
    required this.onDiagnose,
    required this.onCloze,
    required this.onChunkDictation,
    required this.onSentenceDictation,
    required this.onShadow,
    required this.onRead,
  });

  /// Three of the four act on the current sentence; without one they are
  /// disabled rather than hidden, so the grid never changes shape underfoot.
  final bool hasCue;

  /// Whether cloze and chunk dictation have the timing data they need. Both
  /// stay listed either way: the menu says why in the subtitle instead of
  /// silently dropping the row.
  final bool canCloze;
  final bool canChunkDictation;

  /// Reading needs a transcript, not a current sentence, so it can be
  /// available where the other three are not.
  final bool canRead;

  final VoidCallback onDiagnose;
  final VoidCallback onCloze;
  final VoidCallback onChunkDictation;
  final VoidCallback onSentenceDictation;
  final VoidCallback onShadow;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const cellGap = SizedBox(width: ListenSpacing.gap8);
    return Padding(
      padding: ListenPadding.row,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No CrossAxisAlignment.stretch here: this grid is laid out inside a
          // Column, where its height is unbounded, and stretching would ask
          // each cell to be infinitely tall. The cells match anyway — every one
          // is an icon beside exactly two single-line texts.
          Row(
            children: [
              Expanded(
                child: PostureCell(
                  key: const Key('posture-understand'),
                  icon: Icons.analytics_outlined,
                  title: l.text('postureUnderstandTitle'),
                  description: l.text('postureUnderstandHint'),
                  enabled: hasCue,
                  onTap: onDiagnose,
                ),
              ),
              cellGap,
              Expanded(child: _testCell(context, l)),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap8),
          Row(
            children: [
              Expanded(
                child: PostureCell(
                  key: const Key('posture-shadow'),
                  icon: Icons.mic_none,
                  title: l.text('postureShadowTitle'),
                  description: l.text('postureShadowHint'),
                  enabled: hasCue,
                  onTap: onShadow,
                ),
              ),
              cellGap,
              Expanded(
                child: PostureCell(
                  key: const Key('posture-read'),
                  icon: Icons.chrome_reader_mode_outlined,
                  title: l.text('postureReadTitle'),
                  description: l.text('postureReadHint'),
                  enabled: canRead && onRead != null,
                  onTap: onRead,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _testCell(BuildContext context, AppLocalizations l) =>
      PopupMenuButton<String>(
        enabled: hasCue,
        tooltip: l.text('postureTestHint'),
        onSelected: (value) {
          switch (value) {
            case 'cloze':
              onCloze();
            case 'chunk':
              onChunkDictation();
            case 'sentence':
              onSentenceDictation();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'cloze',
            enabled: canCloze,
            child: ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(l.text('clozePractice')),
              subtitle: Text(
                canCloze
                    ? l.text('practiceClozeTooltip')
                    : l.text('practiceClozeUnavailable'),
              ),
            ),
          ),
          PopupMenuItem(
            value: 'chunk',
            child: ListTile(
              leading: const Icon(Icons.segment),
              title: Text(l.text('chunkDictation')),
              subtitle: Text(
                canChunkDictation
                    ? l.text('practiceChunkTooltip')
                    : l.text('practiceChunkFallbackTooltip'),
              ),
            ),
          ),
          PopupMenuItem(
            value: 'sentence',
            child: ListTile(
              leading: const Icon(Icons.short_text),
              title: Text(l.text('sentenceDictation')),
            ),
          ),
        ],
        // The cell itself is inert; the enclosing PopupMenuButton owns the tap,
        // so Test looks and measures exactly like its three siblings.
        child: PostureCell(
          key: const Key('posture-test'),
          icon: Icons.fact_check_outlined,
          title: l.text('postureTestTitle'),
          description: l.text('postureTestHint'),
          enabled: hasCue,
          hasMenu: true,
        ),
      );
}

/// One cell of the posture grid: an action name, one line of what it does, and
/// the icon that leads them.
///
/// L2 in the surface ladder (§1.4) — a bordered surface, because it is a
/// clickable object rather than a section. [onTap] is null for the Test cell,
/// whose tap belongs to the [PopupMenuButton] wrapping it; [hasMenu] is what
/// tells the reader a menu is coming instead of the action firing.
class PostureCell extends StatelessWidget {
  const PostureCell({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    this.onTap,
    this.hasMenu = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final VoidCallback? onTap;
  final bool hasMenu;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = enabled ? colors.onSurface : colors.disabledForeground;
    final secondary = enabled
        ? colors.onSurfaceVariant
        : colors.disabledForeground;
    return Material(
      color: Colors.transparent,
      borderRadius: ListenRadii.panelBorder,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: ListenRadii.panelBorder,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: ListenPadding.row,
            child: Row(
              children: [
                Icon(icon, size: ListenIconSize.control, color: secondary),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: secondary),
                      ),
                    ],
                  ),
                ),
                if (hasMenu)
                  Icon(
                    Icons.arrow_drop_down,
                    size: ListenIconSize.control,
                    color: secondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
