import 'package:flutter/material.dart';
import '../../controllers/coach_dashboard_controller.dart';
import '../../localization.dart';
import '../../models/coach_dashboard.dart';
import '../../services/api_service.dart';

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({
    super.key,
    required this.api,
    required this.onOpenReview,
    required this.onOpenHunting,
  });
  final LocalApi api;
  final VoidCallback onOpenReview, onOpenHunting;
  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  final controller = CoachDashboardController();
  @override
  void initState() {
    super.initState();
    controller.load(widget.api);
  }

  @override
  void dispose() {
    controller.dispose();
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
          return const Center(child: CircularProgressIndicator());
        }
        if (state.error != null) return Center(child: Text(state.error!));
        final dashboard = state.dashboard!;
        final listening = dashboard.channels.first;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              AppLocalizations.of(context).text('coachThisWeek'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: listening.metrics
                  .map(
                    (m) =>
                        _MetricCard(metric: m, onTap: () => _showEvidence(m)),
                  )
                  .toList(),
            ),
            const SizedBox(height: 28),
            Text(
              AppLocalizations.of(context).text('coachNextSteps'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
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
                  onTap: () {
                    if (s.action == 'open_review') widget.onOpenReview();
                    if (s.action == 'open_hunting') widget.onOpenHunting();
                    if (s.action == 'close_dashboard') Navigator.pop(context);
                  },
                ),
              ),
            ),
            if (dashboard.starterChecklist.isNotEmpty) ...[
              const SizedBox(height: 24),
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
              const SizedBox(height: 28),
              Text(
                AppLocalizations.of(context).text('coachMaterials'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
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
            const SizedBox(height: 24),
            ...dashboard.channels
                .skip(1)
                .map(
                  (c) => ListTile(
                    leading: const Icon(Icons.hourglass_empty),
                    title: Text(c.channel),
                    subtitle: Text(
                      AppLocalizations.of(context).text('coachUnassessed'),
                    ),
                  ),
                ),
          ],
        );
      },
    ),
  );

  String _reportLabel(String? report) =>
      AppLocalizations.of(context).text('coachReport_${report ?? 'unknown'}');

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
    if (mounted) await controller.load(widget.api);
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
    if (mounted) await controller.load(widget.api);
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
                          title: Text(item.result),
                          subtitle: Text(item.id),
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
                const SizedBox(height: 8),
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
