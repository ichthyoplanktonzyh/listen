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

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final values = await Future.wait([
        widget.loadProviders?.call() ?? widget.api!.phoneticAnalysisProviders(),
        widget.loadModels?.call() ?? widget.api!.phoneticAnalysisModels(),
        widget.loadJobs?.call() ?? widget.api!.phoneticAnalysisJobs(),
      ]);
      if (!mounted) return;
      setState(() {
        providers = values[0];
        models = values[1];
        jobs = values[2];
        error = null;
      });
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
              Tab(text: l.text('jobs')),
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
                    value: model['size_bytes'] != null &&
                            (model['size_bytes'] as num) > 0
                        ? (model['installed_bytes'] as num?)?.toDouble() ??
                            0.0 /
                            (model['size_bytes'] as num).toDouble()
                        : null,
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

  Widget _jobs(AppLocalizations l) => jobs.isEmpty
      ? Center(child: Text(l.text('noPhoneticAnalysisJobs')))
      : ListView.builder(
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            final status = job['status'] as String;
            final active = const {
              'queued',
              'extracting',
              'recognizing_phones',
              'aligning',
              'analyzing',
            }.contains(status);
            final retryable = const {
              'cancelled',
              'failed',
              'interrupted',
            }.contains(status);
            return ListTile(
              title: Text('${job['scope']} · $status'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: (job['phase_progress'] as num).toDouble() / 100,
                  ),
                  Text(
                    '${job['provider_id']} · ${job['model_revision']}'
                    '${job['error_message'] == null ? '' : '\n${job['error_message']}'}',
                  ),
                ],
              ),
              trailing: active
                  ? IconButton(
                      tooltip: l.text('cancel'),
                      onPressed: () async {
                        await (widget.cancelJob?.call(job['id'] as String) ??
                            widget.api!.cancelPhoneticAnalysisJob(
                              job['id'] as String,
                            ));
                        await _refresh();
                      },
                      icon: const Icon(Icons.cancel_outlined),
                    )
                  : retryable
                  ? IconButton(
                      tooltip: l.text('retry'),
                      onPressed: () async {
                        await (widget.retryJob?.call(job['id'] as String) ??
                            widget.api!.retryPhoneticAnalysisJob(
                              job['id'] as String,
                            ));
                        await _refresh();
                      },
                      icon: const Icon(Icons.refresh),
                    )
                  : null,
            );
          },
        );
}
