import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/coach_dashboard_controller.dart';
import '../../localization.dart';
import '../../models/coach_dashboard.dart';
import '../../models/types.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_empty_state.dart';
import '../common/listen_error_state.dart';
import '../common/listen_loading.dart';

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({
    super.key,
    required this.controller,
    required this.language,
    required this.onOpenReview,
    required this.onOpenHunting,
    required this.onOpenContentHome,
  });

  final CoachDashboardController controller;
  final String language;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenHunting;
  final VoidCallback onOpenContentHome;

  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load(language: widget.language));
  }

  @override
  void didUpdateWidget(covariant CoachDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.language != oldWidget.language) {
      unawaited(widget.controller.load(language: widget.language));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.text('coachDashboard')),
        actions: [
          IconButton(
            tooltip: l.text('refresh'),
            onPressed: widget.controller.state.loading
                ? null
                : () => widget.controller.load(language: widget.language),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final state = widget.controller.state;
          if (state.loading && state.dashboard == null) {
            return const Center(child: ListenLoading());
          }
          if (state.dashboard == null) {
            return ListenErrorState(
              message: l.text('coachDashboardUnavailable'),
              action: OutlinedButton(
                onPressed: () =>
                    widget.controller.load(language: widget.language),
                child: Text(l.text('retry')),
              ),
            );
          }
          return _dashboard(context, state);
        },
      ),
    );
  }

  Widget _dashboard(BuildContext context, CoachDashboardState state) {
    final l = AppLocalizations.of(context);
    final dashboard = state.dashboard!;
    return ListView(
      key: const Key('coach-dashboard-listening-only'),
      padding: const EdgeInsets.all(ListenSpacing.gap24),
      children: [
        Text(
          l
              .text('coachPeriod')
              .replaceAll('{days}', '${_periodDays(dashboard)}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (state.error != null) ...[
          const SizedBox(height: ListenSpacing.gap8),
          ApiFailureDisclosure(failure: state.error!),
        ],
        const SizedBox(height: ListenSpacing.gap16),
        _SectionTitle(l.text('coachListeningActivity')),
        const SizedBox(height: ListenSpacing.gap8),
        if (dashboard.listeningMetrics.isEmpty)
          ListenEmptyState(
            icon: Icons.hearing_outlined,
            message: l.text('coachNoListeningActivity'),
          )
        else
          for (final metric in dashboard.listeningMetrics)
            _MetricCard(
              metric: metric,
              feed: state.evidence[metric.key],
              onLoadEvidence: () =>
                  widget.controller.loadEvidencePage(metric.key),
            ),
        if (dashboard.suggestions.isNotEmpty) ...[
          const SizedBox(height: ListenSpacing.gap16),
          _SectionTitle(l.text('coachNextSteps')),
          const SizedBox(height: ListenSpacing.gap8),
          for (final suggestion in dashboard.suggestions)
            _SuggestionCard(
              suggestion: suggestion,
              onPressed: () => _openSuggestion(suggestion),
            ),
        ],
        if (dashboard.starterChecklist.isNotEmpty) ...[
          const SizedBox(height: ListenSpacing.gap16),
          _SectionTitle(l.text('coachStarter')),
          for (final key in dashboard.starterChecklist)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(l.text(key)),
            ),
        ],
        if (dashboard.materials.isNotEmpty) ...[
          const SizedBox(height: ListenSpacing.gap16),
          _SectionTitle(l.text('coachMaterials')),
          const SizedBox(height: ListenSpacing.gap8),
          for (final material in dashboard.materials)
            _MaterialCard(
              material: material,
              busy: state.actionBusy,
              onSetIntent: (intent) => _setIntent(material, intent),
              onGraduate: () => _graduate(material),
            ),
        ],
        const SizedBox(height: ListenSpacing.gap16),
        _SectionTitle(l.text('contentFitCalibration')),
        const SizedBox(height: ListenSpacing.gap4),
        Text(
          l.text('contentFitCalibrationDescription'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: ListenSpacing.gap8),
        if (state.calibrationFailure != null)
          ApiFailureDisclosure(failure: state.calibrationFailure!)
        else if (state.calibrationLoading)
          const Center(child: ListenLoading.inline())
        else if (state.calibrationSamples == null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('load-fit-calibration'),
              onPressed: () => widget.controller.loadCalibrationSamples(),
              icon: const Icon(Icons.analytics_outlined),
              label: Text(l.text('contentFitCalibrationLoad')),
            ),
          )
        else if (state.calibrationSamples!.isEmpty)
          Text(l.text('contentFitCalibrationEmpty'))
        else ...[
          Text(
            l
                .text('contentFitCalibrationCount')
                .replaceAll('{count}', '${state.calibrationSamples!.length}'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          for (final sample in state.calibrationSamples!)
            _CalibrationSampleCard(sample: sample),
        ],
        if (state.actionFailure != null) ...[
          const SizedBox(height: ListenSpacing.gap12),
          ApiFailureDisclosure(failure: state.actionFailure!),
        ],
      ],
    );
  }

  int _periodDays(CoachDashboard dashboard) =>
      ((dashboard.periodEndMs - dashboard.periodStartMs) /
              Duration.millisecondsPerDay)
          .ceil();

  void _openSuggestion(CoachSuggestion suggestion) {
    switch (suggestion.destination.kind) {
      case 'review_queue':
        widget.onOpenReview();
      case 'hunting_list':
        widget.onOpenHunting();
      case 'content_home':
        widget.onOpenContentHome();
    }
  }

  Future<void> _setIntent(CoachMaterialInsight material, String? intent) async {
    final failure = await widget.controller.setMaterialIntent(
      material.mediaId,
      intent,
    );
    if (!mounted || failure == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).text('coachActionFailed')),
      ),
    );
  }

  Future<void> _graduate(CoachMaterialInsight material) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('coachGraduateTitle')),
        content: Text(l.text('coachGraduatePrompt')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.text('coachGraduateAction')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final failure = await widget.controller.graduateMaterial(material.mediaId);
    if (!mounted || failure == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.text('coachActionFailed'))));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
    required this.feed,
    required this.onLoadEvidence,
  });

  final CoachMetric metric;
  final CoachEvidenceFeed? feed;
  final VoidCallback onLoadEvidence;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.text('coachMetric_${metric.key}'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  metric.key == 'extensive_listening_ms'
                      ? formatDuration(Duration(milliseconds: metric.value))
                      : '${metric.value}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: feed?.loading == true || feed?.exhausted == true
                    ? null
                    : onLoadEvidence,
                child: Text(
                  feed?.items.isNotEmpty == true
                      ? l.text('coachMoreEvidence')
                      : l.text('coachShowEvidence'),
                ),
              ),
            ),
            if (feed?.failure != null)
              ApiFailureDisclosure(failure: feed!.failure!)
            else if (feed?.loading == true)
              const ListenLoading.inline()
            else if (feed != null)
              for (final item in feed!.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: ListenSpacing.gap4),
                  child: Text(
                    item.sourceAvailable
                        ? '${l.text('coachEvidence_${item.result}')} · ${item.sourceKind}'
                        : l.text('coachEvidenceUnavailable'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.onPressed});

  final CoachSuggestion suggestion;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.lightbulb_outline),
        title: Text(l.text(suggestion.titleKey)),
        subtitle: Text(
          l
              .text(suggestion.reasonKey)
              .replaceAll('{count}', '${suggestion.evidenceCount}'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onPressed,
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({
    required this.material,
    required this.busy,
    required this.onSetIntent,
    required this.onGraduate,
  });

  final CoachMaterialInsight material;
  final bool busy;
  final ValueChanged<String?> onSetIntent;
  final VoidCallback onGraduate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(material.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: ListenSpacing.gap4),
            Text(
              l
                  .text('coachMaterialEvidence')
                  .replaceAll('{reports}', '${material.reportCount}')
                  .replaceAll('{attempts}', '${material.practiceAttempts}')
                  .replaceAll('{correct}', '${material.practiceCorrect}'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (material.recommendedIntent != null &&
                material.recommendedIntent != material.triageIntent) ...[
              const SizedBox(height: ListenSpacing.gap8),
              OutlinedButton(
                key: Key('coach-intent-${material.mediaId}'),
                onPressed: busy
                    ? null
                    : () => onSetIntent(material.recommendedIntent),
                child: Text(
                  l
                      .text('coachApplyIntent')
                      .replaceAll(
                        '{intent}',
                        l.text('triage_${material.recommendedIntent}'),
                      ),
                ),
              ),
            ],
            if (material.graduationCandidate &&
                material.triageIntent != 'graduated')
              FilledButton.tonal(
                key: Key('coach-graduate-${material.mediaId}'),
                onPressed: busy ? null : onGraduate,
                child: Text(l.text('coachGraduateAction')),
              ),
          ],
        ),
      ),
    );
  }
}

class _CalibrationSampleCard extends StatelessWidget {
  const _CalibrationSampleCard({required this.sample});
  final ContentFitCalibrationSample sample;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.equalizer_outlined),
        title: Text(l.text('fit_${sample.predictedMeaningBand}')),
        subtitle: Text(
          l
              .text('contentFitCalibrationSampleSummary')
              .replaceAll('{language}', sample.language)
              .replaceAll(
                '{observed}',
                sample.observedDifficulty?.toStringAsFixed(2) ?? '—',
              )
              .replaceAll(
                '{reports}',
                '${sample.reportsUnderstoodAll + sample.reportsGotTheGist + sample.reportsUnclear}',
              )
              .replaceAll('{attempts}', '${sample.practiceAttempts}'),
        ),
      ),
    );
  }
}
