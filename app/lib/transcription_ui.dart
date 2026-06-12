import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'localization.dart';

typedef LoadGeneratedTrack =
    Future<void> Function(Map<String, dynamic> track, bool secondary);

Future<void> showGenerateSubtitles({
  required BuildContext context,
  required LocalApi api,
  required String mediaId,
  required bool secondary,
  String preferredQuality = 'balanced',
  String preferredLanguage = 'auto',
}) async {
  final l = AppLocalizations.of(context);
  final models = await api.transcriptionModels();
  final installed = models
      .where(
        (model) => model['state'] == 'installed' || model['state'] == 'custom',
      )
      .toList(growable: false);
  if (!context.mounted) return;
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
    return;
  }
  final preferred = installed
      .where((model) => model['quality'] == preferredQuality)
      .firstOrNull;
  var modelId = (preferred ?? installed.first)['id'] as String;
  var language = preferredLanguage;
  var translate = false;
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
                        value: model['id'] as String,
                        child: Text(
                          '${model['display_name']} · ${model['quality']}',
                        ),
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
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l.text('generateWholeMedia')),
          ),
        ],
      ),
    ),
  );
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
  List<Map<String, dynamic>> models = const [];
  List<Map<String, dynamic>> jobs = const [];
  List<Map<String, dynamic>> providers = const [];
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
      final values = await Future.wait([
        widget.api.transcriptionProviders(),
        widget.api.transcriptionModels(),
        widget.api.transcriptionJobs(),
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
            provider['available'] == true
                ? Icons.check_circle_outline
                : Icons.error_outline,
          ),
          title: Text(
            '${provider['display_name']} · ${provider['runtime_id']}',
          ),
          subtitle: Text(
            provider['available'] == true
                ? '${provider['runtime_version']} · ${l.text('runtimeReady')}'
                : (provider['diagnostic'] as String? ??
                      l.text('providerUnavailable')),
          ),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: models.length,
          itemBuilder: (context, index) {
            final model = models[index];
            final state = model['state'] as String;
            final installed = model['installed_bytes'] as int? ?? 0;
            final size = model['size_bytes'] as int? ?? 0;
            return ListTile(
              title: Text('${model['display_name']} · ${model['quality']}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${state.toUpperCase()} · ${_size(size)} · ${model['english_only'] == true ? 'English' : l.text('multilingual')}',
                  ),
                  if (state == 'installing')
                    LinearProgressIndicator(
                      value: size == 0 ? null : installed / size,
                    ),
                  if (model['error'] != null) Text(model['error'] as String),
                ],
              ),
              trailing: switch (state) {
                'downloadable' || 'failed' => IconButton(
                  tooltip: l.text('install'),
                  onPressed: () async {
                    await widget.api.installTranscriptionModel(
                      model['id'] as String,
                    );
                    await _refresh();
                  },
                  icon: const Icon(Icons.download),
                ),
                'installing' => IconButton(
                  tooltip: l.text('cancel'),
                  onPressed: () async {
                    await widget.api.cancelTranscriptionModelInstall(
                      model['id'] as String,
                    );
                    await _refresh();
                  },
                  icon: const Icon(Icons.cancel_outlined),
                ),
                _ => IconButton(
                  tooltip: l.text('remove'),
                  onPressed: () async {
                    await widget.api.deleteTranscriptionModel(
                      model['id'] as String,
                    );
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
            final status = job['status'] as String;
            final active = const {
              'queued',
              'extracting',
              'transcribing',
              'importing',
            }.contains(status);
            return ListTile(
              title: Text(job['media_title'] as String),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${job['destination']} · ${job['model_id']} · ${status.toUpperCase()}',
                  ),
                  if (active)
                    LinearProgressIndicator(
                      value: (job['phase_progress'] as int) / 100,
                    ),
                  if (job['error_message'] != null)
                    Text(job['error_message'] as String),
                ],
              ),
              trailing: Wrap(
                children: [
                  if (active)
                    IconButton(
                      tooltip: l.text('cancel'),
                      onPressed: () => widget.api.cancelTranscriptionJob(
                        job['id'] as String,
                      ),
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  if (status == 'failed' || status == 'cancelled')
                    IconButton(
                      tooltip: l.text('retry'),
                      onPressed: () =>
                          widget.api.retryTranscriptionJob(job['id'] as String),
                      icon: const Icon(Icons.replay),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('loadGeneratedSubtitle'),
                      onPressed: () async {
                        final track = await widget.api.readSubtitle(
                          job['generated_track_id'] as String,
                        );
                        await widget.loadTrack(
                          track,
                          job['destination'] == 'secondary',
                        );
                      },
                      icon: const Icon(Icons.subtitles),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('exportSrt'),
                      onPressed: () async {
                        final location = await getSaveLocation(
                          suggestedName: '${job['media_title']}.generated.srt',
                        );
                        if (location == null) return;
                        final content = await widget.api.exportSubtitleSrt(
                          job['generated_track_id'] as String,
                        );
                        await File(location.path).writeAsString(content);
                      },
                      icon: const Icon(Icons.file_download_outlined),
                    ),
                  if (status == 'completed')
                    IconButton(
                      tooltip: l.text('regenerate'),
                      onPressed: () => showGenerateSubtitles(
                        context: context,
                        api: widget.api,
                        mediaId: job['media_id'] as String,
                        secondary: job['destination'] == 'secondary',
                      ),
                      icon: const Icon(Icons.auto_fix_high),
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
