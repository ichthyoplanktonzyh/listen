import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'models/timeline.dart';
import 'models/runtime_resources.dart';
import 'services/api_service.dart';
import 'localization.dart';

typedef LoadGeneratedTrack =
    Future<void> Function(SubtitleTrack track, bool secondary);

Future<bool> showGenerateSubtitles({
  required BuildContext context,
  required LocalApi api,
  required String mediaId,
  required bool secondary,
  String preferredQuality = 'balanced',
  String preferredLanguage = 'auto',
  bool force = false,
}) async {
  final l = AppLocalizations.of(context);
  final models = await api.transcriptionModels();
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
              await api.createTranscriptionJob(
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
    required this.api,
    required this.loadTrack,
    super.key,
  });

  final LocalApi api;
  final LoadGeneratedTrack loadTrack;

  @override
  State<TranscriptionCenter> createState() => _TranscriptionCenterState();
}

class _TranscriptionCenterState extends State<TranscriptionCenter> {
  List<TranscriptionModelView> models = const [];
  List<TranscriptionJobView> jobs = const [];
  List<TranscriptionProviderView> providers = const [];
  Timer? timer;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final providerValues = await widget.api.transcriptionProviders();
      final modelValues = await widget.api.transcriptionModels();
      final jobValues = await widget.api.transcriptionJobs();
      if (!mounted) return;
      setState(() {
        providers = providerValues;
        models = modelValues;
        jobs = jobValues;
        error = null;
      });
    } catch (value) {
      if (mounted) setState(() => error = value.toString());
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
        body: error != null
            ? Center(child: Text(error!))
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
              final file = await openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(label: 'Whisper model', extensions: ['bin']),
                ],
              );
              if (file != null) {
                await widget.api.registerCustomTranscriptionModel(file.path);
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
                    await widget.api.installTranscriptionModel(model.id);
                    await _refresh();
                  },
                  icon: const Icon(Icons.download),
                ),
                'installing' => IconButton(
                  tooltip: l.text('cancel'),
                  onPressed: () async {
                    await widget.api.cancelTranscriptionModelInstall(model.id);
                    await _refresh();
                  },
                  icon: const Icon(Icons.cancel_outlined),
                ),
                _ => IconButton(
                  tooltip: l.text('remove'),
                  onPressed: () async {
                    await widget.api.deleteTranscriptionModel(model.id);
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
      ? Center(child: Text(l.text('noTranscriptionJobs')))
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
                      onPressed: () =>
                          widget.api.cancelTranscriptionJob(job.id),
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  if (status == 'failed' || status == 'cancelled')
                    IconButton(
                      tooltip: l.text('retry'),
                      onPressed: () async {
                        await widget.api.retryTranscriptionJob(job.id);
                        await _refresh();
                      },
                      icon: const Icon(Icons.replay),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('loadGeneratedSubtitle'),
                      onPressed: () async {
                        final track = await widget.api.readSubtitle(
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
                        final location = await getSaveLocation(
                          suggestedName: '${job.mediaTitle}.generated.srt',
                        );
                        if (location == null) return;
                        final content = await widget.api.exportSubtitleSrt(
                          job.generatedTrackId!,
                        );
                        await File(location.path).writeAsString(content);
                      },
                      icon: const Icon(Icons.file_download_outlined),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('regenerate'),
                      onPressed: () async {
                        final created = await showGenerateSubtitles(
                          context: context,
                          api: widget.api,
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
                        await widget.api.archiveTranscriptionJob(job.id);
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
