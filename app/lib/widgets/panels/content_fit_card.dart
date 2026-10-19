import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Media-level dual-dimension content fit (ADR 0018).
///
/// Interaction-layer rules (shared-context invariant 18 + phase guardrails):
/// bands and reasons only — no formulas, no raw densities as verdicts; copy is
/// expectation management, never "too hard for you"; the card never hides,
/// locks, or discourages material. When the vocabulary profile covers too
/// little of the transcript the honest-degradation notice replaces confident
/// framing.
class ContentFitCard extends StatelessWidget {
  const ContentFitCard({
    super.key,
    required this.profile,
    this.onStartColdStart,
  });

  final ContentDifficultyProfile profile;
  final VoidCallback? onStartColdStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: ListenRadii.controlBorder,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune_outlined,
                  size: ListenIconSize.control,
                  color: colors.primary,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    l.text('contentFit'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  profile.usageCalibrated
                      ? l.text('contentFitCalibrated')
                      : l.text('contentFitInitialEstimate'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l.text('contentFitWhy'),
                  icon: const Icon(
                    Icons.info_outline,
                    size: ListenIconSize.control,
                  ),
                  onPressed: () => _showDetail(context),
                ),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap6),
            Row(
              children: [
                FitChip(
                  label: l.text('contentFitMeaning'),
                  fit: profile.meaning.fit,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                FitChip(
                  label: l.text('contentFitSound'),
                  fit: profile.sound.fit,
                ),
              ],
            ),
            if (profile.isIntensiveListeningTarget) ...[
              const SizedBox(height: ListenSpacing.gap8),
              _NoteLine(
                icon: Icons.headphones_outlined,
                text: l.text('contentFitIntensiveTarget'),
                color: colors.primary,
              ),
            ],
            if (!profile.hasSufficientVocabularyProfile) ...[
              const SizedBox(height: ListenSpacing.gap8),
              _NoteLine(
                icon: Icons.info_outline,
                text: l.text('contentFitLowProfile'),
                color: colors.onSurfaceVariant,
              ),
              if (onStartColdStart != null) ...[
                const SizedBox(height: ListenSpacing.gap6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(
                      Icons.bolt_outlined,
                      size: ListenIconSize.control,
                    ),
                    label: Text(l.text('coldStartQuickMarking')),
                    onPressed: onStartColdStart,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => ContentFitDetailDialog(profile: profile),
  );
}

class FitChip extends StatelessWidget {
  const FitChip({super.key, required this.label, required this.fit});

  final String label;
  final String fit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: ListenRadii.pillBorder,
      ),
      child: Padding(
        padding: ListenPadding.tight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(width: ListenSpacing.gap6),
            Text(
              l.text('fit_$fit'),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: ListenIconSize.inline, color: color),
      const SizedBox(width: ListenSpacing.gap6),
      Expanded(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ),
    ],
  );
}

class ContentFitDetailDialog extends StatelessWidget {
  const ContentFitDetailDialog({super.key, required this.profile});

  final ContentDifficultyProfile profile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.text('contentFitWhy')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DimensionDetail(
                title: l.text('contentFitMeaning'),
                dimension: profile.meaning,
              ),
              const SizedBox(height: ListenSpacing.gap12),
              _DimensionDetail(
                title: l.text('contentFitSound'),
                dimension: profile.sound,
              ),
              const SizedBox(height: ListenSpacing.gap12),
              Text(
                profile.usageCalibrated
                    ? l.text('contentFitCalibrated')
                    : l.text('contentFitInitialEstimate'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (!profile.hasSufficientVocabularyProfile) ...[
                const SizedBox(height: ListenSpacing.gap6),
                Text(
                  l.text('contentFitLowProfile'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}

class _DimensionDetail extends StatelessWidget {
  const _DimensionDetail({required this.title, required this.dimension});

  final String title;
  final DifficultyDimension dimension;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Text(
              l.text('fit_${dimension.fit}'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: ListenSpacing.gap6),
        for (final signal in dimension.signals)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  signal.decisive
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: ListenIconSize.inline,
                  color: signal.decisive
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    l.text('fit_signal_${signal.kind}'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  _formatValue(signal),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (signal.decisive) ...[
                  const SizedBox(width: ListenSpacing.gap6),
                  Text(
                    l.text('contentFitDecisive'),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: colors.primary),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _formatValue(FitSignal signal) => switch (signal.kind) {
    'speech_rate_wpm' => signal.value.toStringAsFixed(0),
    'mean_chunk_length' => signal.value.toStringAsFixed(1),
    _ => '${(signal.value * 100).toStringAsFixed(1)}%',
  };
}
