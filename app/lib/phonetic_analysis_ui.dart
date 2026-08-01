import 'package:flutter/material.dart';

import 'controllers/phonetic_analysis_view_model.dart';
import 'localization.dart';
import 'models/runtime_resources.dart';
import 'theme/icon_size.dart';
import 'theme/radii.dart';
import 'theme/spacing.dart';
import 'theme/typography.dart';
import 'widgets/common/api_failure_disclosure.dart';
import 'widgets/common/listen_empty_state.dart';
import 'widgets/common/listen_error_state.dart';
import 'widgets/common/listen_loading.dart';

class PhoneticAnalysisCenter extends StatefulWidget {
  const PhoneticAnalysisCenter({required this.viewModel, super.key});

  final PhoneticAnalysisViewModel viewModel;

  @override
  State<PhoneticAnalysisCenter> createState() => _PhoneticAnalysisCenterState();
}

class _PhoneticAnalysisCenterState extends State<PhoneticAnalysisCenter> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.start();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final state = widget.viewModel.state;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(l.text('phoneticAnalysisCenter')),
              bottom: TabBar(
                tabs: [
                  Tab(text: l.text('models')),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.text('jobs')),
                        if (state.jobs.isNotEmpty) ...[
                          const SizedBox(width: ListenSpacing.gap6),
                          _jobCountBadge(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  onPressed: widget.viewModel.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: state.failure != null
                ? ListenErrorState(
                    message: l.text(state.failure!.messageKey),
                    action: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: widget.viewModel.refresh,
                          child: Text(l.text('retry')),
                        ),
                        if (ApiFailureDisclosure.hasDetail(
                          state.failure!.detail,
                        ))
                          ApiFailureDisclosure(failure: state.failure!.detail!),
                      ],
                    ),
                  )
                : TabBarView(children: [_models(l), _jobs(l)]),
          ),
        );
      },
    );
  }

  Widget _jobCountBadge() {
    final jobs = widget.viewModel.state.jobs;
    final active = jobs
        .where((job) => PhoneticAnalysisViewModel.isActive(job.status))
        .length;
    final failed = jobs.where((job) => job.status == 'failed').length;
    final color = failed > 0
        ? Theme.of(context).colorScheme.error
        : active > 0
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: ListenPadding.tight,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: ListenRadii.controlBorder,
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        '${jobs.length}',
        style: ListenType.caption.copyWith(color: color),
      ),
    );
  }

  // --- Models tab ---

  double? _installProgress(PhoneticModelView model) {
    final size = model.sizeBytes.toDouble();
    final installed = model.installedBytes.toDouble();
    if (size <= 0) return null;
    return (installed / size).clamp(0.0, 1.0);
  }

  Future<void> _installModel(String modelId) async {
    await widget.viewModel.installModel(modelId);
  }

  Widget _models(AppLocalizations l) => ListView(
    children: [
      for (final provider in widget.viewModel.state.providers)
        ListTile(
          leading: Icon(
            provider.available ? Icons.science_outlined : Icons.error_outline,
          ),
          title: Text(
            '${provider.displayName} · '
            '${provider.experimental ? l.text('experimental') : l.text('ready')}',
          ),
          subtitle: Text(
            provider.diagnostic ??
                '${provider.runtimeId} ${provider.runtimeVersion}',
          ),
        ),
      for (final model in widget.viewModel.state.models)
        ListTile(
          leading: const Icon(Icons.memory_outlined),
          title: Text('${model.displayName} · ${model.state}'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (model.state == 'installing')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: LinearProgressIndicator(
                    value: _installProgress(model),
                  ),
                ),
              if (model.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    model.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Text(
                '${model.license} · ${model.revision}\n'
                '${model.trainingDataProvenance}\n'
                '${model.applicationVerified ? l.text('applicationVerified') : l.text('notApplicationVerified')} · '
                '${model.distributionAllowed ? l.text('distributionAllowed') : l.text('distributionNotAllowed')}',
              ),
            ],
          ),
          isThreeLine: true,
          trailing: _modelAction(model, l),
        ),
    ],
  );

  Widget? _modelAction(PhoneticModelView model, AppLocalizations l) {
    final state = model.state;
    final id = model.id;
    if (state == 'downloadable' || state == 'failed') {
      return IconButton(
        tooltip: l.text('download'),
        onPressed: () => _installModel(id),
        icon: const Icon(Icons.download),
      );
    }
    if (state == 'installing') {
      return const ListenLoading.inline();
    }
    if (state == 'custom' || state == 'installed') {
      return Icon(
        Icons.check_circle_outline,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return null;
  }

  // --- Jobs tab ---

  Widget _jobs(AppLocalizations l) {
    final jobs = widget.viewModel.state.jobs;
    if (jobs.isEmpty) {
      return ListenEmptyState(
        icon: Icons.graphic_eq,
        message: l.text('noPhoneticAnalysisJobs'),
      );
    }
    return Column(
      children: [
        if (widget.viewModel.hasTerminalJobs)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _confirmClearTerminal(l),
                  icon: const Icon(
                    Icons.clear_all,
                    size: ListenIconSize.control,
                  ),
                  label: Text(l.text('clearCompleted')),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: jobs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _jobTile(jobs[index], l),
          ),
        ),
      ],
    );
  }

  Widget _jobTile(PhoneticJobView job, AppLocalizations l) {
    final status = job.status;
    final active = PhoneticAnalysisViewModel.isActive(status);
    final terminal = PhoneticAnalysisViewModel.isTerminal(status);
    final progress = job.phaseProgress / 100;
    final errorMsg = job.errorMessage;
    final scope = job.scope;
    final createdAt = job.createdAtMs;

    return ListTile(
      leading: _statusIcon(status),
      title: Row(
        children: [
          Expanded(child: Text(scope, overflow: TextOverflow.ellipsis)),
          _statusChip(status, l),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: ListenSpacing.gap4),
          if (active)
            ClipRRect(
              borderRadius: ListenRadii.tightBorder,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          if (active) const SizedBox(height: ListenSpacing.gap4),
          if (status == 'completed')
            Text(
              '${job.providerId} · ${job.modelRevision}',
              style: ListenType.body,
            ),
          if (errorMsg != null && errorMsg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                errorMsg,
                style: ListenType.body.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _formatTimestamp(createdAt),
              style: ListenType.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              ),
            ),
          ),
        ],
      ),
      trailing: _jobActions(job, status, active, terminal, l),
      isThreeLine: true,
    );
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icon(
          Icons.check_circle,
          color: Theme.of(context).colorScheme.primary,
          size: ListenIconSize.chrome,
        );
      case 'failed':
        return Icon(
          Icons.error,
          color: Theme.of(context).colorScheme.error,
          size: ListenIconSize.chrome,
        );
      case 'cancelled':
        return Icon(
          Icons.cancel,
          color: Theme.of(context).colorScheme.secondary,
          size: ListenIconSize.chrome,
        );
      case 'interrupted':
        return Icon(
          Icons.warning_amber,
          color: Theme.of(context).colorScheme.secondary,
          size: ListenIconSize.chrome,
        );
      case 'queued':
        return Icon(
          Icons.schedule,
          color: Theme.of(context).colorScheme.tertiary,
          size: ListenIconSize.chrome,
        );
      default:
        // The spinner stands in for whichever status icon will replace it,
        // so it reads the same step: at any other size the row would resize
        // the moment the job settled.
        return const ListenLoading.inline(size: ListenIconSize.chrome);
    }
  }

  Widget _statusChip(String status, AppLocalizations l) {
    final (label, color) = switch (status) {
      'completed' => (
        l.text('jobCompleted'),
        Theme.of(context).colorScheme.primary,
      ),
      'failed' => (l.text('jobFailed'), Theme.of(context).colorScheme.error),
      'cancelled' => (
        l.text('jobCancelled'),
        Theme.of(context).colorScheme.secondary,
      ),
      'interrupted' => (
        l.text('jobInterrupted'),
        Theme.of(context).colorScheme.secondary,
      ),
      'queued' => (l.text('jobQueued'), Theme.of(context).colorScheme.tertiary),
      'extracting' => (
        l.text('jobExtracting'),
        Theme.of(context).colorScheme.tertiary,
      ),
      'recognizing_phones' => (
        l.text('jobRecognizingPhones'),
        Theme.of(context).colorScheme.tertiary,
      ),
      'aligning' => (
        l.text('jobAligning'),
        Theme.of(context).colorScheme.tertiary,
      ),
      'analyzing' => (
        l.text('jobAnalyzing'),
        Theme.of(context).colorScheme.tertiary,
      ),
      _ => (status, Theme.of(context).colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: ListenRadii.tightBorder,
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(label, style: ListenType.caption.copyWith(color: color)),
    );
  }

  Widget? _jobActions(
    PhoneticJobView job,
    String status,
    bool active,
    bool terminal,
    AppLocalizations l,
  ) {
    final id = job.id;
    if (active) {
      return IconButton(
        tooltip: l.text('cancel'),
        onPressed: () => widget.viewModel.cancelJob(id),
        icon: const Icon(Icons.stop_circle_outlined),
      );
    }
    if (terminal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != 'completed')
            IconButton(
              tooltip: l.text('retry'),
              onPressed: () => widget.viewModel.retryJob(id),
              icon: const Icon(Icons.refresh, size: ListenIconSize.control),
            ),
          IconButton(
            tooltip: l.text('deleteJob'),
            onPressed: () => _confirmDeleteJob(id, l),
            icon: Icon(
              Icons.delete_outline,
              size: ListenIconSize.control,
              color: Theme.of(context).colorScheme.error.withAlpha(180),
            ),
          ),
        ],
      );
    }
    return null;
  }

  // --- Confirmations ---

  Future<void> _confirmDeleteJob(String id, AppLocalizations l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.text('deleteJob')),
        content: Text(l.text('confirmDeleteJob')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.text('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l.text('deleteJob'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.viewModel.deleteJob(id);
    }
  }

  Future<void> _confirmClearTerminal(AppLocalizations l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.text('clearCompleted')),
        content: Text(l.text('confirmClearJobs')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.text('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l.text('clearCompleted'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.viewModel.clearTerminalJobs();
    }
  }

  // --- Helpers ---

  String _formatTimestamp(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
