import 'dart:async';

import 'package:flutter/material.dart';

import 'localization.dart';
import 'services/api_service.dart';

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
  final Future<List<Map<String, dynamic>>> Function()? loadProviders;
  final Future<List<Map<String, dynamic>>> Function()? loadModels;
  final Future<List<Map<String, dynamic>>> Function()? loadJobs;
  final Future<Map<String, dynamic>> Function(String id)? cancelJob;
  final Future<Map<String, dynamic>> Function(String id)? retryJob;

  @override
  State<PhoneticAnalysisCenter> createState() => _PhoneticAnalysisCenterState();
}

class _PhoneticAnalysisCenterState extends State<PhoneticAnalysisCenter> {
  List<Map<String, dynamic>> providers = const [];
  List<Map<String, dynamic>> models = const [];
  List<Map<String, dynamic>> jobs = const [];
  Timer? timer;
  String? error;

  bool get _hasActiveJobs => jobs.any((j) => _isActive(j['status'] as String));
  bool get _hasTerminalJobs =>
      jobs.any((j) => _isTerminal(j['status'] as String));

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
    final interval =
        _hasActiveJobs
            ? const Duration(seconds: 1)
            : const Duration(seconds: 5);
    timer = Timer.periodic(interval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final values = await Future.wait([
        widget.loadProviders?.call() ?? widget.api!.phoneticAnalysisProviders(),
        widget.loadModels?.call() ?? widget.api!.phoneticAnalysisModels(),
        widget.loadJobs?.call() ?? widget.api!.phoneticAnalysisJobs(),
      ]);
      if (!mounted) return;
      final hadActive = _hasActiveJobs;
      setState(() {
        providers = values[0];
        models = values[1];
        jobs = values[2];
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
                      const SizedBox(width: 6),
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
        body:
            error != null
                ? Center(child: Text(error!))
                : TabBarView(children: [_models(l), _jobs(l)]),
      ),
    );
  }

  Widget _jobCountBadge() {
    final active = jobs.where((j) => _isActive(j['status'] as String)).length;
    final failed = jobs.where((j) => j['status'] == 'failed').length;
    final color =
        failed > 0
            ? Colors.red
            : active > 0
                ? Colors.blue
                : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        '${jobs.length}',
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }

  // --- Models tab ---

  double? _installProgress(Map<String, dynamic> model) {
    final size = (model['size_bytes'] as num?)?.toDouble() ?? 0.0;
    final installed = (model['installed_bytes'] as num?)?.toDouble() ?? 0.0;
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
            provider['available'] == true
                ? Icons.science_outlined
                : Icons.error_outline,
          ),
          title: Text(
            '${provider['display_name']} · '
            '${provider['experimental'] == true ? l.text('experimental') : l.text('ready')}',
          ),
          subtitle: Text(
            provider['diagnostic'] as String? ??
                '${provider['runtime_id']} ${provider['runtime_version']}',
          ),
        ),
      for (final model in models)
        ListTile(
          leading: const Icon(Icons.memory_outlined),
          title: Text('${model['display_name']} · ${model['state']}'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (model['state'] == 'installing')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: LinearProgressIndicator(
                    value: _installProgress(model),
                  ),
                ),
              if (model['error'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${model['error']}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Text(
                '${model['license']} · ${model['revision']}\n'
                '${model['training_data_provenance']}\n'
                '${model['application_verified'] == true ? l.text('applicationVerified') : l.text('notApplicationVerified')} · '
                '${model['distribution_allowed'] == true ? l.text('distributionAllowed') : l.text('distributionNotAllowed')}',
              ),
            ],
          ),
          isThreeLine: true,
          trailing: _modelAction(model, l),
        ),
    ],
  );

  Widget? _modelAction(Map<String, dynamic> model, AppLocalizations l) {
    final state = model['state'] as String?;
    final id = model['id'] as String?;
    if (state == 'downloadable' || state == 'failed') {
      return IconButton(
        tooltip: l.text('download'),
        onPressed: id == null ? null : () => _installModel(id),
        icon: const Icon(Icons.download),
      );
    }
    if (state == 'installing') {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (state == 'custom' || state == 'installed') {
      return const Icon(Icons.check_circle_outline, color: Colors.green);
    }
    return null;
  }

  // --- Jobs tab ---

  Widget _jobs(AppLocalizations l) {
    if (jobs.isEmpty) {
      return Center(child: Text(l.text('noPhoneticAnalysisJobs')));
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

  Widget _jobTile(Map<String, dynamic> job, AppLocalizations l) {
    final status = job['status'] as String;
    final active = _isActive(status);
    final terminal = _isTerminal(status);
    final progress = (job['phase_progress'] as num).toDouble() / 100;
    final errorMsg = job['error_message'] as String?;
    final scope = job['scope'] as String;
    final createdAt = job['created_at_ms'] as num?;

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
          const SizedBox(height: 4),
          if (active)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white10,
              ),
            ),
          if (active) const SizedBox(height: 4),
          if (status == 'completed')
            Text(
              '${job['provider_id']} · ${job['model_revision']}',
              style: const TextStyle(fontSize: 12),
            ),
          if (errorMsg != null && errorMsg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                errorMsg,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatTimestamp(createdAt.toInt()),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withAlpha(120),
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
        return const Icon(Icons.check_circle, color: Colors.green, size: 22);
      case 'failed':
        return const Icon(Icons.error, color: Colors.red, size: 22);
      case 'cancelled':
        return Icon(
          Icons.cancel,
          color: Colors.orange.shade300,
          size: 22,
        );
      case 'interrupted':
        return Icon(
          Icons.warning_amber,
          color: Colors.orange.shade300,
          size: 22,
        );
      case 'queued':
        return Icon(Icons.schedule, color: Colors.blue.shade300, size: 22);
      default:
        return SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.blue.shade300,
          ),
        );
    }
  }

  Widget _statusChip(String status, AppLocalizations l) {
    final (label, color) = switch (status) {
      'completed' => (l.text('jobCompleted'), Colors.green),
      'failed' => (l.text('jobFailed'), Colors.red),
      'cancelled' => (l.text('jobCancelled'), Colors.orange),
      'interrupted' => (l.text('jobInterrupted'), Colors.orange),
      'queued' => (l.text('jobQueued'), Colors.blue),
      'extracting' => (l.text('jobExtracting'), Colors.blue),
      'recognizing_phones' => (l.text('jobRecognizingPhones'), Colors.blue),
      'aligning' => (l.text('jobAligning'), Colors.blue),
      'analyzing' => (l.text('jobAnalyzing'), Colors.blue),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  Widget? _jobActions(
    Map<String, dynamic> job,
    String status,
    bool active,
    bool terminal,
    AppLocalizations l,
  ) {
    final id = job['id'] as String;
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
      builder:
          (ctx) => AlertDialog(
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
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
      builder:
          (ctx) => AlertDialog(
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
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

  static bool _isTerminal(String status) =>
      const {'completed', 'cancelled', 'failed', 'interrupted'}
          .contains(status);

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
