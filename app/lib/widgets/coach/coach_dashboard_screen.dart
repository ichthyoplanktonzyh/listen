import 'package:flutter/material.dart';

import '../../controllers/coach_dashboard_controller.dart';
import '../../localization.dart';
import '../../models/coach_dashboard.dart';
import '../../services/api_service.dart';
import '../../theme/spacing.dart';
import '../common/capability_viz.dart';
import '../common/listen_error_state.dart';
import '../common/listen_loading.dart';

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({
    super.key,
    required this.api,
    required this.language,
    required this.onNavigate,
  });
  final LocalApi api;
  final String language;
  final Future<void> Function(
    CoachSuggestionDestination destination,
    CoachReturnContext returnContext,
  )
  onNavigate;
  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  final controller = CoachDashboardController();
  final scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    controller.load(widget.api, language: widget.language);
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context).text('coachDashboard')),
    ),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        if (state.loading) {
          return const Center(child: ListenLoading());
        }
        if (state.error != null) {
          return ListenErrorState(
            message: state.error!,
            action: OutlinedButton(
              onPressed: () =>
                  controller.load(widget.api, language: widget.language),
              child: Text(AppLocalizations.of(context).text('retry')),
            ),
          );
        }
        final dashboard = state.dashboard!;
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              AppLocalizations.of(context).text('capabilityPortraitTitle'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              AppLocalizations.of(context)
                  .text('coachGeneratedAt')
                  .replaceFirst(
                    '{time}',
                    DateTime.fromMillisecondsSinceEpoch(
                      dashboard.generatedAtMs,
                    ).toLocal().toString().substring(0, 16),
                  ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: ListenSpacing.gap16),
            // The portrait (#47): compass overview + echo-bar channel detail
            // carry the three-state story; the cards below are pure metric
            // drill-down and only render when a channel has evidence to show.
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CapabilityPortrait(
                  channels: dashboard.channels,
                  gapCount: crossModalGapCount(dashboard),
                ),
              ),
            ),
            ...dashboard.channels
                .where((channel) => channel.metrics.any((m) => m.value > 0))
                .map(
                  (channel) =>
                      _ChannelCard(channel: channel, onMetric: _showEvidence),
                ),
            const SizedBox(height: ListenSpacing.gap24),
            Text(
              AppLocalizations.of(context).text('coachNextSteps'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: ListenSpacing.gap8),
            if (dashboard.suggestions.isEmpty)
              Text(AppLocalizations.of(context).text('coachNoSuggestions')),
            ...dashboard.suggestions.map(
              (s) => Card(
                child: ListTile(
                  title: Text(AppLocalizations.of(context).text(s.titleKey)),
                  subtitle: Text(
                    '${AppLocalizations.of(context).text(s.reasonKey)} · ${s.evidenceCount} · ${s.evidenceSource}',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () => _openSuggestion(s),
                ),
              ),
            ),
            if (dashboard.starterChecklist.isNotEmpty) ...[
              const SizedBox(height: ListenSpacing.gap24),
              Text(
                AppLocalizations.of(context).text('coachStarter'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ...dashboard.starterChecklist.map(
                (item) => ListTile(
                  leading: const Icon(Icons.radio_button_unchecked),
                  title: Text(
                    AppLocalizations.of(context).text('coachStarter_$item'),
                  ),
                ),
              ),
            ],
            if (dashboard.materials.isNotEmpty) ...[
              const SizedBox(height: ListenSpacing.gap24),
              Text(
                AppLocalizations.of(context).text('coachMaterials'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: ListenSpacing.gap8),
              ...dashboard.materials.map(
                (material) => Card(
                  child: ListTile(
                    title: Text(material.title),
                    subtitle: Text(
                      '${AppLocalizations.of(context).text('coachMaterialTrajectory')}: '
                      '${_reportLabel(material.firstReport)} → ${_reportLabel(material.latestReport)} '
                      '· ${material.reportCount}',
                    ),
                    trailing: material.graduationCandidate
                        ? FilledButton.tonal(
                            onPressed: () => _graduate(material),
                            child: Text(
                              AppLocalizations.of(
                                context,
                              ).text('coachGraduate'),
                            ),
                          )
                        : material.recommendedIntent != null &&
                              material.recommendedIntent !=
                                  material.triageIntent
                        ? OutlinedButton(
                            onPressed: () => _setIntent(material),
                            child: Text(
                              AppLocalizations.of(context).text(
                                'coachIntent_${material.recommendedIntent}',
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ],
            if (dashboard.features.isNotEmpty) ...[
              const SizedBox(height: ListenSpacing.gap24),
              ...dashboard.features.map(
                (feature) => ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: Text(
                    AppLocalizations.of(
                      context,
                    ).text('coachFeature_${feature.feature}'),
                  ),
                  subtitle: Text(
                    AppLocalizations.of(
                      context,
                    ).text('coachFeatureStatus_${feature.status}'),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );

  String _reportLabel(String? report) =>
      AppLocalizations.of(context).text('coachReport_${report ?? 'unknown'}');

  Future<void> _openSuggestion(CoachSuggestion suggestion) async {
    if (suggestion.destination.kind == 'content_home') {
      Navigator.pop(context);
      return;
    }
    final offset = scrollController.hasClients ? scrollController.offset : 0.0;
    await widget.onNavigate(
      suggestion.destination,
      CoachReturnContext(
        days: 7,
        language: widget.language,
        scrollOffset: offset,
        suggestionId: suggestion.id,
      ),
    );
    if (!mounted) return;
    await controller.load(widget.api, language: widget.language);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scrollController.hasClients) {
        scrollController.jumpTo(
          offset.clamp(0, scrollController.position.maxScrollExtent),
        );
      }
    });
  }

  Future<void> _graduate(CoachMaterialInsight material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).text('coachGraduateConfirmTitle'),
        ),
        content: Text(
          AppLocalizations.of(context).text('coachGraduateConfirmBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).text('coachGraduate')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.graduateCoachMaterial(material.mediaId);
    if (mounted) {
      await controller.load(widget.api, language: widget.language);
    }
  }

  Future<void> _setIntent(CoachMaterialInsight material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).text('coachMaterialAdjustTitle'),
        ),
        content: Text(
          AppLocalizations.of(context).text('coachMaterialAdjustBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).text('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.setMediaTriageIntent(
      material.mediaId,
      material.recommendedIntent,
    );
    if (mounted) {
      await controller.load(widget.api, language: widget.language);
    }
  }

  Future<void> _showEvidence(CoachMetric metric) async {
    final items = await widget.api.coachEvidence(metric.key);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).text('coachMetric_${metric.key}'),
        ),
        content: SizedBox(
          width: 520,
          child: items.isEmpty
              ? Text(AppLocalizations.of(context).text('coachEvidenceEmpty'))
              : ListView(
                  shrinkWrap: true,
                  children: items
                      .map(
                        (item) => ListTile(
                          dense: true,
                          title: Text(item.snapshot),
                          subtitle: Text(
                            '${item.sourceKind} · ${item.id}'
                            '${item.sourceAvailable ? '' : ' · ${AppLocalizations.of(context).text('coachSourceUnavailable')}'}',
                          ),
                          trailing: Text(
                            DateTime.fromMillisecondsSinceEpoch(
                              item.occurredAtMs,
                            ).toLocal().toString().substring(0, 16),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel, required this.onMetric});

  final CoachChannelSummary channel;
  final Future<void> Function(CoachMetric metric) onMetric;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Three-state counts moved into the portrait above (#47); this card is
    // the channel's metric drill-down only.
    final visibleMetrics = channel.metrics
        .where((metric) => metric.value > 0)
        .toList(growable: false);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  channel.status == 'unassessed'
                      ? Icons.hourglass_empty
                      : Icons.insights_outlined,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Text(
                  l.text('coachChannel_${channel.channel}'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: visibleMetrics
                  .map(
                    (metric) => _MetricCard(
                      metric: metric,
                      onTap: () => onMetric(metric),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.onTap});
  final CoachMetric metric;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final value = metric.key == 'extensive_listening_ms'
        ? '${(metric.value / 60000).round()} min'
        : '${metric.value}';
    return SizedBox(
      width: 210,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(
                    context,
                  ).text('coachMetric_${metric.key}'),
                ),
                const SizedBox(height: ListenSpacing.gap8),
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
                Text(
                  metric.source,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
