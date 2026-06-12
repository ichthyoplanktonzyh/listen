import 'dart:async';

import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'localization.dart';

class LearningAssetsScreen extends StatefulWidget {
  const LearningAssetsScreen({super.key, required this.api});

  final LocalApi api;

  @override
  State<LearningAssetsScreen> createState() => _LearningAssetsScreenState();
}

class _LearningAssetsScreenState extends State<LearningAssetsScreen> {
  List<Map<String, dynamic>> values = const [];
  String kind = 'phrase';
  String? status;
  String search = '';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final next = await widget.api.lexicalEntries(
      kind: kind,
      status: status,
      search: search,
    );
    if (mounted) setState(() => values = next);
  }

  Future<void> _details(Map<String, dynamic> details) async {
    final entry = details['entry'] as Map<String, dynamic>;
    var selectedStatus = entry['status'] as String? ?? 'known_not_recognized';
    final definition = TextEditingController(
      text: entry['user_definition'] as String? ?? '',
    );
    final note = TextEditingController(
      text: entry['personal_note'] as String? ?? '',
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(entry['display_form'] as String),
          content: SizedBox(
            width: 640,
            height: 520,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  items: [
                    for (final status in const [
                      'unknown_meaning',
                      'known_not_recognized',
                      'known_recognized',
                    ])
                      DropdownMenuItem(
                        value: status,
                        child: Text(
                          AppLocalizations.of(context).status(status),
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => selectedStatus = value ?? selectedStatus),
                ),
                TextField(
                  controller: definition,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    ).text('userDefinition'),
                  ),
                ),
                TextField(
                  controller: note,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    ).text('personalNote'),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final raw in details['occurrences'] as List<dynamic>)
                        ListTile(
                          title: Text(
                            (raw
                                    as Map<
                                      String,
                                      dynamic
                                    >)['sentence_text_snapshot']
                                as String,
                          ),
                          subtitle: Text(
                            '${raw['media_title_snapshot']} · ${raw['encounter_count']}',
                          ),
                          trailing: const Icon(Icons.play_arrow),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pop(this.context, raw);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                await widget.api.upsertLexicalEntry({
                  'language': entry['language'],
                  'kind': entry['kind'],
                  'canonical_form': entry['canonical_form'],
                  'display_form': entry['display_form'],
                  'status': selectedStatus,
                  'user_definition': definition.text,
                  'personal_note': note.text,
                });
                if (context.mounted) Navigator.pop(context);
                await _refresh();
              },
              child: Text(AppLocalizations.of(context).text('save')),
            ),
          ],
        ),
      ),
    );
    definition.dispose();
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.text('learningAssets'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'word', label: Text(l.text('words'))),
                    ButtonSegment(
                      value: 'phrase',
                      label: Text(l.text('phrases')),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: (value) {
                    setState(() => kind = value.first);
                    unawaited(_refresh());
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: l.text('searchVocabulary'),
                    ),
                    onChanged: (value) {
                      search = value;
                      unawaited(_refresh());
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final details in values)
                  LearningAssetTile(
                    details: details,
                    onTap: () => _details(details),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LearningResourceScreen extends StatefulWidget {
  const LearningResourceScreen({super.key, required this.api});
  final LocalApi api;

  @override
  State<LearningResourceScreen> createState() => _LearningResourceScreenState();
}

class _LearningResourceScreenState extends State<LearningResourceScreen> {
  List<Map<String, dynamic>> resources = const [];
  String? busy;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final values = await widget.api.learningResources();
    if (mounted) setState(() => resources = values);
  }

  Future<void> _toggle(Map<String, dynamic> value) async {
    final id = value['id'] as String;
    setState(() => busy = id);
    try {
      if (value['state'] == 'installed') {
        await widget.api.removeLearningResource(id);
      } else {
        await widget.api.installLearningResource(id);
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).text('resources'))),
    body: ListView(
      children: [
        for (final value in resources)
          LearningResourceTile(
            value: value,
            busy: busy == value['id'],
            onToggle: () => _toggle(value),
          ),
      ],
    ),
  );
}

class LearningAssetTile extends StatelessWidget {
  const LearningAssetTile({
    super.key,
    required this.details,
    required this.onTap,
  });

  final Map<String, dynamic> details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = details['entry'] as Map<String, dynamic>;
    return ListTile(
      title: Text(entry['display_form'] as String),
      subtitle: Text(
        '${l.text(entry['kind'] as String)} · '
        '${l.status(entry['status'] as String?)}',
      ),
      trailing: Text(
        '${(details['occurrences'] as List<dynamic>).length} ${l.text('sources')}',
      ),
      onTap: onTap,
    );
  }
}

class LearningResourceTile extends StatelessWidget {
  const LearningResourceTile({
    super.key,
    required this.value,
    required this.busy,
    required this.onToggle,
  });

  final Map<String, dynamic> value;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(value['display_name'] as String),
    subtitle: Text(
      '${value['version']} · ${value['license']} · ${value['state']}\n'
      '${value['checksum_sha256']}',
    ),
    isThreeLine: true,
    trailing: busy
        ? const CircularProgressIndicator()
        : IconButton(
            icon: Icon(
              value['state'] == 'installed'
                  ? Icons.delete_outline
                  : Icons.download,
            ),
            onPressed: onToggle,
          ),
  );
}

Future<void> showPhraseCandidates({
  required BuildContext context,
  required LocalApi api,
  required String sentenceId,
  required Map<String, dynamic> source,
}) async {
  final candidates = await api.phraseCandidates(sentenceId);
  var status = 'known_not_recognized';
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('phraseCandidates')),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: status,
                items: [
                  DropdownMenuItem(
                    value: 'unknown_meaning',
                    child: Text(
                      AppLocalizations.of(context).status('unknown_meaning'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'known_not_recognized',
                    child: Text(
                      AppLocalizations.of(
                        context,
                      ).status('known_not_recognized'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'known_recognized',
                    child: Text(
                      AppLocalizations.of(context).status('known_recognized'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => status = value ?? status),
              ),
              Flexible(
                child: candidates.isEmpty
                    ? Text(
                        AppLocalizations.of(context).text('noPhraseCandidates'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final candidate in candidates)
                            ListTile(
                              title: Text(candidate['display_form'] as String),
                              subtitle: Text(candidate['reason'] as String),
                              trailing: FilledButton(
                                onPressed: () async {
                                  await api.upsertLexicalEntry({
                                    'language': 'en',
                                    'kind': 'phrase',
                                    'canonical_form':
                                        candidate['canonical_form'],
                                    'display_form': candidate['display_form'],
                                    'status': status,
                                    'source': {
                                      ...source,
                                      'original_form':
                                          candidate['display_form'],
                                      'token_start': candidate['token_start'],
                                      'token_end': candidate['token_end'],
                                    },
                                  });
                                  if (context.mounted) Navigator.pop(context);
                                },
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).text('confirmPhrase'),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<Map<String, dynamic>?> showPhraseCandidate({
  required BuildContext context,
  required LocalApi api,
  required Map<String, dynamic> candidate,
  required Map<String, dynamic> source,
  String? initialStatus,
}) async {
  var status = initialStatus ?? 'known_not_recognized';
  Map<String, dynamic>? saved;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(candidate['display_form'] as String),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).text('phraseCandidatesHint')),
              const SizedBox(height: 12),
              Text(candidate['reason'] as String),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                items: [
                  for (final value in const [
                    'unknown_meaning',
                    'known_not_recognized',
                    'known_recognized',
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(AppLocalizations.of(context).status(value)),
                    ),
                ],
                onChanged: (value) => setState(() => status = value ?? status),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).text('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              saved = await api.upsertLexicalEntry({
                'language': 'en',
                'kind': 'phrase',
                'canonical_form': candidate['canonical_form'],
                'display_form': candidate['display_form'],
                'status': status,
                'source': {
                  ...source,
                  'original_form': candidate['display_form'],
                  'token_start': candidate['token_start'],
                  'token_end': candidate['token_end'],
                },
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context).text('confirmPhrase')),
          ),
        ],
      ),
    ),
  );
  return saved;
}

Future<String?> showOpenSubtitlesSearch({
  required BuildContext context,
  required LocalApi api,
  required String apiKey,
  required String initialTitle,
  required String initialFilename,
  required String? mediaPath,
}) async {
  final controller = TextEditingController(text: initialTitle);
  var values = <Map<String, dynamic>>[];
  var loading = false;
  var mode = 'title';
  String? error;
  String? selected;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('openSubtitles')),
        content: SizedBox(
          width: 680,
          height: 480,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: mode,
                items: [
                  DropdownMenuItem(
                    value: 'title',
                    child: Text(AppLocalizations.of(context).text('title')),
                  ),
                  DropdownMenuItem(
                    value: 'filename',
                    child: Text(AppLocalizations.of(context).text('filename')),
                  ),
                  DropdownMenuItem(
                    value: 'hash',
                    child: Text(AppLocalizations.of(context).text('mediaHash')),
                  ),
                ],
                onChanged: (value) {
                  setState(() => mode = value ?? mode);
                  if (mode == 'title') controller.text = initialTitle;
                  if (mode == 'filename') controller.text = initialFilename;
                },
              ),
              if (mode != 'hash') TextField(controller: controller),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        setState(() => loading = true);
                        try {
                          final hash = mode == 'hash' && mediaPath != null
                              ? await api.openSubtitlesMovieHash(mediaPath)
                              : null;
                          values = await api.searchOpenSubtitles(
                            apiKey: apiKey,
                            query: mode == 'hash' ? null : controller.text,
                            moviehash: hash,
                          );
                          error = null;
                        } catch (value) {
                          error = value.toString();
                        } finally {
                          setState(() => loading = false);
                        }
                      },
                child: Text(AppLocalizations.of(context).text('search')),
              ),
              if (loading) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              Expanded(
                child: ListView(
                  children: [
                    for (final value in values)
                      ListTile(
                        title: Text(value['release'] as String),
                        subtitle: Text(
                          '${value['language']} · rating ${value['rating']} · ${value['download_count']} downloads',
                        ),
                        onTap: () async {
                          selected = await api.downloadOpenSubtitle(
                            apiKey: apiKey,
                            fileId: value['file_id'] as int,
                          );
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  controller.dispose();
  return selected;
}
