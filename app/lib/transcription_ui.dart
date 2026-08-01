import 'package:flutter/material.dart';

import 'controllers/transcription_view_models.dart';
import 'localization.dart';
import 'widgets/common/api_failure_disclosure.dart';
import 'widgets/common/listen_empty_state.dart';
import 'widgets/common/listen_error_state.dart';

Future<bool> showGenerateSubtitles({
  required BuildContext context,
  required GenerateSubtitlesViewModel viewModel,
}) async {
  final l = AppLocalizations.of(context);
  await viewModel.load();
  final installed = viewModel.state.installedModels;
  if (!context.mounted) return false;
  if (installed.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('modelRequired')),
        content: Text(l.text('installModelFirst')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('close')),
          ),
        ],
      ),
    );
    return false;
  }
  var created = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: Text(l.text('generateSubtitles')),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: viewModel.state.modelId,
                decoration: InputDecoration(labelText: l.text('model')),
                items: installed
                    .map(
                      (model) => DropdownMenuItem(
                        value: model.id,
                        child: Text('${model.displayName} · ${model.quality}'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) refresh(() => viewModel.setModel(value));
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: viewModel.state.language,
                decoration: InputDecoration(
                  labelText: l.text('transcriptionLanguage'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'auto',
                    child: Text(l.text('automatic')),
                  ),
                  const DropdownMenuItem(value: 'en', child: Text('English')),
                  const DropdownMenuItem(value: 'zh', child: Text('中文')),
                ],
                onChanged: (value) =>
                    refresh(() => viewModel.setLanguage(value ?? 'auto')),
              ),
              SwitchListTile(
                value: viewModel.state.translate,
                title: Text(l.text('translateEnglish')),
                onChanged: (value) =>
                    refresh(() => viewModel.setTranslate(value)),
              ),
              Text(
                viewModel.secondary
                    ? l.text('generateSecondaryHint')
                    : l.text('generatePrimaryHint'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              created = await viewModel.create();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l.text('generateWholeMedia')),
          ),
        ],
      ),
    ),
  );
  return created;
}

class TranscriptionCenter extends StatefulWidget {
  const TranscriptionCenter({
    required this.viewModel,
    required this.onRegenerate,
    super.key,
  });

  final TranscriptionCenterViewModel viewModel;
  final RegenerateTranscriptionJob onRegenerate;

  @override
  State<TranscriptionCenter> createState() => _TranscriptionCenterState();
}

class _TranscriptionCenterState extends State<TranscriptionCenter> {
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
              title: Text(l.text('transcriptionCenter')),
              bottom: TabBar(
                tabs: [
                  Tab(text: l.text('models')),
                  Tab(text: l.text('jobs')),
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

  Widget _models(AppLocalizations l) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: widget.viewModel.registerCustomModel,
            icon: const Icon(Icons.add_link),
            label: Text(l.text('registerCustomModel')),
          ),
        ),
      ),
      for (final provider in widget.viewModel.state.providers)
        ListTile(
          leading: Icon(
            provider.available
                ? Icons.check_circle_outline
                : Icons.error_outline,
          ),
          title: Text('${provider.displayName} · ${provider.runtimeId}'),
          subtitle: Text(
            provider.available
                ? '${provider.runtimeVersion} · ${l.text('runtimeReady')}'
                : (provider.diagnostic ?? l.text('providerUnavailable')),
          ),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: widget.viewModel.state.models.length,
          itemBuilder: (context, index) {
            final model = widget.viewModel.state.models[index];
            final state = model.state;
            final installed = model.installedBytes;
            final size = model.sizeBytes;
            return ListTile(
              title: Text('${model.displayName} · ${model.quality}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${state.toUpperCase()} · ${_size(size)} · ${model.englishOnly ? 'English' : l.text('multilingual')}',
                  ),
                  if (state == 'installing')
                    LinearProgressIndicator(
                      value: size == 0 ? null : installed / size,
                    ),
                  if (model.error != null) Text(model.error!),
                ],
              ),
              trailing: switch (state) {
                'downloadable' || 'failed' => IconButton(
                  tooltip: l.text('install'),
                  onPressed: () async {
                    await widget.viewModel.installModel(model.id);
                  },
                  icon: const Icon(Icons.download),
                ),
                'installing' => IconButton(
                  tooltip: l.text('cancel'),
                  onPressed: () async {
                    await widget.viewModel.cancelModelInstall(model.id);
                  },
                  icon: const Icon(Icons.cancel_outlined),
                ),
                _ => IconButton(
                  tooltip: l.text('remove'),
                  onPressed: () async {
                    await widget.viewModel.deleteModel(model.id);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              },
            );
          },
        ),
      ),
    ],
  );

  Widget _jobs(AppLocalizations l) => widget.viewModel.state.jobs.isEmpty
      ? ListenEmptyState(
          icon: Icons.subtitles_outlined,
          message: l.text('noTranscriptionJobs'),
        )
      : ListView.builder(
          itemCount: widget.viewModel.state.jobs.length,
          itemBuilder: (context, index) {
            final job = widget.viewModel.state.jobs[index];
            final status = job.status;
            final active = const {
              'queued',
              'extracting',
              'transcribing',
              'importing',
            }.contains(status);
            return ListTile(
              title: Text(job.mediaTitle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${job.destination} · ${job.modelId} · ${status.toUpperCase()}',
                  ),
                  if (active)
                    LinearProgressIndicator(value: job.phaseProgress / 100),
                  if (job.errorMessage != null) Text(job.errorMessage!),
                ],
              ),
              trailing: Wrap(
                children: [
                  if (active)
                    IconButton(
                      tooltip: l.text('cancel'),
                      onPressed: () => widget.viewModel.cancelJob(job.id),
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  if (status == 'failed' || status == 'cancelled')
                    IconButton(
                      tooltip: l.text('retry'),
                      onPressed: () async {
                        await widget.viewModel.retryJob(job.id);
                      },
                      icon: const Icon(Icons.replay),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('loadGeneratedSubtitle'),
                      onPressed: () async {
                        await widget.viewModel.loadGenerated(job);
                      },
                      icon: const Icon(Icons.subtitles),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('exportSrt'),
                      onPressed: () async {
                        await widget.viewModel.exportSrt(job);
                      },
                      icon: const Icon(Icons.file_download_outlined),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('regenerate'),
                      onPressed: () => widget.onRegenerate(job),
                      icon: const Icon(Icons.auto_fix_high),
                    ),
                  if (!active)
                    IconButton(
                      tooltip: l.text('archive'),
                      onPressed: () async {
                        await widget.viewModel.archiveJob(job.id);
                      },
                      icon: const Icon(Icons.archive_outlined),
                    ),
                ],
              ),
            );
          },
        );

  String _size(int bytes) => bytes >= 1000000000
      ? '${(bytes / 1000000000).toStringAsFixed(1)} GB'
      : '${(bytes / 1000000).round()} MB';
}
