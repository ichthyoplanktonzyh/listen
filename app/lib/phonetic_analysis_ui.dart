import 'dart:async';

import 'package:flutter/material.dart';

import 'localization.dart';
import 'models/runtime_resources.dart';
import 'services/api_service.dart';
import 'theme/radii.dart';
import 'theme/spacing.dart';
import 'theme/typography.dart';
import 'widgets/common/listen_empty_state.dart';
import 'widgets/common/listen_loading.dart';

class PhoneticAnalysisCenter extends StatefulWidget {
  const PhoneticAnalysisCenter({
    this.api,
    this.loadProviders,
    this.loadModels,
    this.loadJobs,
    this.cancelJob,
    this.retryJob,
    super.key,
  });

  final LocalApi? api;
  final Future<List<PhoneticProviderView>> Function()? loadProviders;
  final Future<List<PhoneticModelView>> Function()? loadModels;
  final Future<List<PhoneticJobView>> Function()? loadJobs;
  final Future<PhoneticJobView> Function(String id)? cancelJob;
  final Future<PhoneticJobView> Function(String id)? retryJob;

  @override
  State<PhoneticAnalysisCenter> createState() => _PhoneticAnalysisCenterState();
}

class _PhoneticAnalysisCenterState extends State<PhoneticAnalysisCenter> {
  List<PhoneticProviderView> providers = const [];
  List<PhoneticModelView> models = const [];
  List<PhoneticJobView> jobs = const [];
  Timer? timer;
  String? error;

  bool get _hasActiveJobs => jobs.any((job) => _isActive(job.status));
  bool get _hasTerminalJobs => jobs.any((job) => _isTerminal(job.status));

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _scheduleTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _scheduleTimer() {
    timer?.cancel();
    final interval = _hasActiveJobs
        ? const Duration(seconds: 1)
        : const Duration(seconds: 5);
    timer = Timer.periodic(interval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final providerValues =
          await (widget.loadProviders?.call() ??
              widget.api!.phoneticAnalysisProviders());
      final modelValues =
          await (widget.loadModels?.call() ??
              widget.api!.phoneticAnalysisModels());
      final jobValues =
          await (widget.loadJobs?.call() ?? widget.api!.phoneticAnalysisJobs());
      if (!mounted) return;
      final hadActive = _hasActiveJobs;
      setState(() {
        providers = providerValues;
        models = modelValues;
        jobs = jobValues;
        error = null;
      });
      if (hadActive != _hasActiveJobs) _scheduleTimer();
    } catch (value) {
      if (mounted) setState(() => error = value.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                    if (jobs.isNotEmpty) ...[
                      const SizedBox(width: ListenSpacing.gap6),
                      _jobCountBadge(),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: error != null
            ? Center(child: Text(error!))
            : TabBarView(children: [_models(l), _jobs(l)]),
      ),
    );
  }

  Widget _jobCountBadge() {
    final active = jobs.where((job) => _isActive(job.status)).length;
    final failed = jobs.where((job) => job.status == 'failed').length;
    final color = failed > 0
        ? Theme.of(context).colorScheme.error
        : active > 0
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
    try {
      await (widget.api?.installPhoneticAnalysisModel(modelId));
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget _models(AppLocalizations l) => ListView(
    children: [
      for (final provider in providers)
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
      for (final model in models)
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
    if (jobs.isEmpty) {
      return ListenEmptyState(
        icon: Icons.graphic_eq,
        message: l.text('noPhoneticAnalysisJobs'),
      );
    }
    return Column(
      children: [
        if (_hasTerminalJobs)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _confirmClearTerminal(l),
                  icon: const Icon(Icons.clear_all, size: 18),
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
    final active = _isActive(status);
    final terminal = _isTerminal(status);
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
          size: 22,
        );
      case 'failed':
        return Icon(
          Icons.error,
          color: Theme.of(context).colorScheme.error,
          size: 22,
        );
      case 'cancelled':
        return Icon(
          Icons.cancel,
          color: Theme.of(context).colorScheme.secondary,
          size: 22,
        );
      case 'interrupted':
        return Icon(
          Icons.warning_amber,
          color: Theme.of(context).colorScheme.secondary,
          size: 22,
        );
      case 'queued':
        return Icon(
          Icons.schedule,
          color: Theme.of(context).colorScheme.tertiary,
          size: 22,
        );
      default:
        return const ListenLoading.inline(size: 22);
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
        onPressed: () async {
          await (widget.cancelJob?.call(id) ??
              widget.api!.cancelPhoneticAnalysisJob(id));
          await _refresh();
        },
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
              onPressed: () async {
                await (widget.retryJob?.call(id) ??
                    widget.api!.retryPhoneticAnalysisJob(id));
                await _refresh();
              },
              icon: const Icon(Icons.refresh, size: 20),
            ),
          IconButton(
            tooltip: l.text('deleteJob'),
            onPressed: () => _confirmDeleteJob(id, l),
            icon: Icon(
              Icons.delete_outline,
              size: 20,
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
      await widget.api?.deletePhoneticAnalysisJob(id);
      await _refresh();
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
      await widget.api?.clearTerminalPhoneticAnalysisJobs();
      await _refresh();
    }
  }

  // --- Helpers ---

  static bool _isActive(String status) => const {
    'queued',
    'extracting',
    'recognizing_phones',
    'aligning',
    'analyzing',
  }.contains(status);

  static bool _isTerminal(String status) => const {
    'completed',
    'cancelled',
    'failed',
    'interrupted',
  }.contains(status);

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
