import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Listening fit is expectation setting for an AV material, never an access
/// gate or a command to choose a study mode.
class ContentFitCard extends StatelessWidget {
  const ContentFitCard({super.key, required this.profile});

  final ContentDifficultyProfile profile;

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
                  l.text(
                    profile.usageCalibrated
                        ? 'contentFitCalibrated'
                        : 'contentFitInitialEstimate',
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  key: const Key('content-fit-details'),
                  visualDensity: VisualDensity.compact,
                  tooltip: l.text('contentFitWhy'),
                  icon: const Icon(
                    Icons.info_outline,
                    size: ListenIconSize.control,
                  ),
                  onPressed: () => _showDetails(context),
                ),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap6),
            Wrap(
              spacing: ListenSpacing.gap8,
              runSpacing: ListenSpacing.gap4,
              children: [
                FitChip(
                  label: l.text('contentFitMeaning'),
                  fit: profile.meaning.fit,
                ),
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
              ),
            ],
            if (!profile.hasSufficientVocabularyProfile) ...[
              const SizedBox(height: ListenSpacing.gap8),
              _NoteLine(
                icon: Icons.info_outline,
                text: l.text('contentFitLowProfile'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context) => showDialog<void>(
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
  const _NoteLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: ListenIconSize.inline),
      const SizedBox(width: ListenSpacing.gap8),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
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
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ListenBreakpoints.cardColumnMax,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DimensionDetail(
                title: l.text('contentFitMeaning'),
                dimension: profile.meaning,
              ),
              const SizedBox(height: ListenSpacing.gap16),
              _DimensionDetail(
                title: l.text('contentFitSound'),
                dimension: profile.sound,
              ),
              if (profile.featureCoverage != null) ...[
                const SizedBox(height: ListenSpacing.gap16),
                Text(
                  l
                      .text('contentFitCoverage')
                      .replaceAll(
                        '{available}',
                        '${profile.featureCoverage!.availableFeatures}',
                      )
                      .replaceAll(
                        '{total}',
                        '${profile.featureCoverage!.totalFeatures}',
                      ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (profile.featureCoverage!.missingFeatures.isNotEmpty) ...[
                  const SizedBox(height: ListenSpacing.gap4),
                  Text(
                    l
                        .text('contentFitMissingSignals')
                        .replaceAll(
                          '{signals}',
                          profile.featureCoverage!.missingFeatures
                              .map((signal) => l.text('fit_signal_$signal'))
                              .join(', '),
                        ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: ListenSpacing.gap4),
        Text(l.text('fit_${dimension.fit}')),
        const SizedBox(height: ListenSpacing.gap8),
        if (dimension.decisiveSignals.isEmpty)
          Text(l.text('contentFitNoDecisiveSignals'))
        else
          for (final signal in dimension.decisiveSignals)
            Padding(
              padding: const EdgeInsets.only(bottom: ListenSpacing.gap4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.circle,
                    size: ListenIconSize.inline,
                    color: colors.primary,
                  ),
                  const SizedBox(width: ListenSpacing.gap8),
                  Expanded(child: Text(l.text('fit_signal_${signal.kind}'))),
                ],
              ),
            ),
      ],
    );
  }
}
