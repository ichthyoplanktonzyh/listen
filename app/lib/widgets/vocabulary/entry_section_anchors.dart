import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// One anchored段 of the entry detail: a stable [id], the label the anchor bar
/// shows, an optional count badge, and the section body.
///
/// Sections are *anchors*, not tabs (#82 / V4): every section stays built and
/// co-visible in one scroll view, so evidence and clips can be read side by
/// side. Selecting an anchor only scrolls — it never hides the other four.
class EntryDetailSection {
  const EntryDetailSection({
    required this.id,
    required this.label,
    required this.child,
    required this.anchorKey,
    this.count,
  });

  final String id;
  final String label;

  /// Rendered after the label when the section has a countable inventory
  /// (e.g. "Clips 4"). Null keeps the anchor a bare noun.
  final int? count;
  final Widget child;

  /// Identifies this section's box in the scroll view so the anchor bar can
  /// scroll it into view and so scrolling can report the active section.
  ///
  /// Owned by the hosting State and kept stable across rebuilds — a global key
  /// minted per build would tear down and re-create the whole section every
  /// frame, losing reveals, focus and expansion state.
  final GlobalKey anchorKey;
}

/// The段落 anchor bar: a quiet row of section names above the scrolling detail.
///
/// Never a `TabBar` — a tab bar would claim that only one section exists at a
/// time, which is exactly the "one ListView, eight sections" problem V4 is
/// fixing in the other direction. The active anchor is a *reading position*
/// readout, not a filter.
class EntrySectionAnchorBar extends StatelessWidget {
  const EntrySectionAnchorBar({
    super.key,
    required this.sections,
    required this.activeId,
    required this.onSelect,
  });

  final List<EntryDetailSection> sections;
  final String? activeId;
  final ValueChanged<EntryDetailSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 38,
      child: ListView(
        key: const Key('entry-section-anchors'),
        scrollDirection: Axis.horizontal,
        // Aligned with the detail body's own 20pt gutter.
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(right: ListenSpacing.gap6),
              child: _AnchorChip(
                section: section,
                active: section.id == activeId,
                colors: colors,
                onTap: () => onSelect(section),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnchorChip extends StatelessWidget {
  const _AnchorChip({
    required this.section,
    required this.active,
    required this.colors,
    required this.onTap,
  });

  final EntryDetailSection section;
  final bool active;
  final ColorScheme colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Reduce motion drops the tint/label cross-fade to an instant swap; the
    // anchor never bounces or slides (charter motion discipline).
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : ListenMotion.hover;
    final label = section.count == null
        ? section.label
        : '${section.label} ${section.count}';
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        key: Key('entry-section-anchor-${section.id}'),
        onTap: onTap,
        borderRadius: ListenRadii.controlBorder,
        child: AnimatedContainer(
          duration: duration,
          curve: ListenMotion.move,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: ListenSpacing.gap12,
            vertical: ListenSpacing.gap6,
          ),
          decoration: BoxDecoration(
            color: active ? colors.primary.withValues(alpha: 0.14) : null,
            borderRadius: ListenRadii.controlBorder,
          ),
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: ListenMotion.move,
            style: ListenType.body.copyWith(
              color: active ? colors.primary : colors.onSurfaceVariant,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
