import 'dart:async';

import 'package:flutter/material.dart';

import 'data/repositories/transcription_repository.dart';
import 'localization.dart';
import 'models/runtime_resources.dart';
import 'models/timeline.dart';
import 'models/named_failure.dart';
import 'services/transcription_file_service.dart';
import 'widgets/common/api_failure_disclosure.dart';
import 'widgets/common/listen_empty_state.dart';
import 'widgets/common/listen_error_state.dart';

typedef LoadGeneratedTrack =
    Future<void> Function(SubtitleTrack track, bool secondary);

Future<bool> showGenerateSubtitles({
  required BuildContext context,
  required TranscriptionRepository repository,
  required String mediaId,
  required bool secondary,
  String preferredQuality = 'balanced',
  String preferredLanguage = 'auto',
  bool force = false,
}) async {
  final l = AppLocalizations.of(context);
  final models = await repository.models();
  final installed = models
      .where((model) => model.state == 'installed' || model.state == 'custom')
      .toList(growable: false);
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
  final preferred = installed
      .where((model) => model.quality == preferredQuality)
      .firstOrNull;
  var modelId = (preferred ?? installed.first).id;
  var language = preferredLanguage;
  var translate = false;
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
                initialValue: modelId,
                decoration: InputDecoration(labelText: l.text('model')),
                items: installed
                    .map(
                      (model) => DropdownMenuItem(
                        value: model.id,
                        child: Text('${model.displayName} · ${model.quality}'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => refresh(() => modelId = value ?? modelId),
              ),
              DropdownButtonFormField<String>(
                initialValue: language,
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
                onChanged: (value) => refresh(() => language = value ?? 'auto'),
              ),
              SwitchListTile(
                value: translate,
                title: Text(l.text('translateEnglish')),
                onChanged: (value) => refresh(() => translate = value),
              ),
              Text(
                secondary
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
              await repository.createJob(
                mediaId: mediaId,
                modelId: modelId,
                secondary: secondary,
                translate: translate,
                language: language == 'auto' ? null : language,
                force: force,
              );
              created = true;
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class TranscriptionCenter extends StatefulWidget {
  const TranscriptionCenter({
    required this.repository,
    required this.loadTrack,
    this.fileService = const LocalTranscriptionFileService(),
    super.key,
  });

  final TranscriptionRepository repository;
  final LoadGeneratedTrack loadTrack;
  final TranscriptionFileService fileService;

  @override
  State<TranscriptionCenter> createState() => _TranscriptionCenterState();
}

class _TranscriptionCenterState extends State<TranscriptionCenter> {
  List<TranscriptionModelView> models = const [];
  List<TranscriptionJobView> jobs = const [];
  List<TranscriptionProviderView> providers = const [];
  Timer? timer;
  NamedFailure? failure;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final providerValues = await widget.repository.providers();
      final modelValues = await widget.repository.models();
      final jobValues = await widget.repository.jobs();
      if (!mounted) return;
      setState(() {
        providers = providerValues;
        models = modelValues;
        jobs = jobValues;
        failure = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => failure = NamedFailure(
            'transcriptionLoadFailed',
            detail: widget.repository.failureDetail(error),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: failure != null
            ? ListenErrorState(
                message: l.text(failure!.messageKey),
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: _refresh,
                      child: Text(l.text('retry')),
                    ),
                    if (ApiFailureDisclosure.hasDetail(failure!.detail))
                      ApiFailureDisclosure(failure: failure!.detail!),
                  ],
                ),
              )
            : TabBarView(children: [_models(l), _jobs(l)]),
      ),
    );
  }

  Widget _models(AppLocalizations l) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final path = await widget.fileService.pickCustomModel();
              if (path != null) {
                await widget.repository.registerCustomModel(path);
                await _refresh();
              }
            },
            icon: const Icon(Icons.add_link),
            label: Text(l.text('registerCustomModel')),
          ),
        ),
      ),
      for (final provider in providers)
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
          itemCount: models.length,
          itemBuilder: (context, index) {
            final model = models[index];
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
                    await widget.repository.installModel(model.id);
                    await _refresh();
                  },
                  icon: const Icon(Icons.download),
                ),
                'installing' => IconButton(
                  tooltip: l.text('cancel'),
                  onPressed: () async {
                    await widget.repository.cancelModelInstall(model.id);
                    await _refresh();
                  },
                  icon: const Icon(Icons.cancel_outlined),
                ),
                _ => IconButton(
                  tooltip: l.text('remove'),
                  onPressed: () async {
                    await widget.repository.deleteModel(model.id);
                    await _refresh();
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

  Widget _jobs(AppLocalizations l) => jobs.isEmpty
      ? ListenEmptyState(
          icon: Icons.subtitles_outlined,
          message: l.text('noTranscriptionJobs'),
        )
      : ListView.builder(
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
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
                      onPressed: () => widget.repository.cancelJob(job.id),
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  if (status == 'failed' || status == 'cancelled')
                    IconButton(
                      tooltip: l.text('retry'),
                      onPressed: () async {
                        await widget.repository.retryJob(job.id);
                        await _refresh();
                      },
                      icon: const Icon(Icons.replay),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('loadGeneratedSubtitle'),
                      onPressed: () async {
                        final track = await widget.repository.readSubtitle(
                          job.generatedTrackId!,
                        );
                        await widget.loadTrack(
                          track,
                          job.destination == 'secondary',
                        );
                      },
                      icon: const Icon(Icons.subtitles),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('exportSrt'),
                      onPressed: () async {
                        final content = await widget.repository
                            .exportSubtitleSrt(job.generatedTrackId!);
                        await widget.fileService.saveSrt(
                          suggestedName: '${job.mediaTitle}.generated.srt',
                          content: content,
                        );
                      },
                      icon: const Icon(Icons.file_download_outlined),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('regenerate'),
                      onPressed: () async {
                        final created = await showGenerateSubtitles(
                          context: context,
                          repository: widget.repository,
                          mediaId: job.mediaId,
                          secondary: job.destination == 'secondary',
                          force: true,
                        );
                        if (created) await _refresh();
                      },
                      icon: const Icon(Icons.auto_fix_high),
                    ),
                  if (!active)
                    IconButton(
                      tooltip: l.text('archive'),
                      onPressed: () async {
                        await widget.repository.archiveJob(job.id);
                        await _refresh();
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
