import 'dart:async';

import 'package:flutter/material.dart';

import 'localization.dart';
import 'data/repositories/learning_assets_repository.dart';
import 'data/repositories/personal_expression_repository.dart';
import 'models/personal_expression.dart';
import 'models/runtime_resources.dart';
import 'models/types.dart';
import 'screens/personal_expression_screen.dart';
import 'theme/spacing.dart';
import 'widgets/common/listen_loading.dart';

class LearningAssetsScreen extends StatefulWidget {
  const LearningAssetsScreen({
    super.key,
    required this.repository,
    required this.personalExpressionRepository,
    required this.language,
    this.onPlayExpressionSource,
    this.onStartExpressionSpeaking,
  });

  final LearningAssetsRepository repository;
  final PersonalExpressionRepository personalExpressionRepository;
  final String language;
  final Future<void> Function(PersonalExpressionSourceView source)?
  onPlayExpressionSource;
  final Future<void> Function(SentencePatternAssetView pattern)?
  onStartExpressionSpeaking;

  @override
  State<LearningAssetsScreen> createState() => _LearningAssetsScreenState();
}

class _LearningAssetsScreenState extends State<LearningAssetsScreen> {
  List<LexicalEntryDetails> values = const [];
  String kind = 'phrase';
  String? status;
  String search = '';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final next = await widget.repository.lexicalEntries(
      language: widget.language,
      kind: kind,
      status: status,
      search: search,
    );
    if (mounted) setState(() => values = next);
  }

  Future<void> _details(LexicalEntryDetails details) async {
    final entry = details.entry;
    var selectedStatus = entry.status ?? 'known_not_recognized';
    final definition = TextEditingController(text: entry.userDefinition ?? '');
    final note = TextEditingController(text: entry.personalNote ?? '');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(entry.displayForm),
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
                      for (final occurrence in details.occurrences)
                        ListTile(
                          title: Text(occurrence.sentenceTextSnapshot),
                          subtitle: Text(
                            '${occurrence.mediaTitleSnapshot} · ${occurrence.encounterCount}',
                          ),
                          trailing: const Icon(Icons.play_arrow),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pop(this.context, occurrence.toJson());
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
                await widget.repository.upsertLexicalEntry({
                  'language': entry.language,
                  'kind': entry.kind,
                  'canonical_form': entry.normalizedForm,
                  'display_form': entry.displayForm,
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.auto_stories_outlined),
                // Both strings already existed in `localization.dart` for
                // this same destination — the compact home card reads them —
                // so this tile was showing a second, hand-written subtitle for
                // one place. Reading the keys fixes the i18n hole and makes the
                // two surfaces agree on what 我的表达 is for.
                title: Text(l.text('personalExpressions')),
                subtitle: Text(l.text('personalExpressionSummary')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => PersonalExpressionScreen(
                        repository: widget.personalExpressionRepository,
                        language: widget.language,
                        onPlaySource: widget.onPlayExpressionSource,
                        onStartSpeaking: widget.onStartExpressionSpeaking,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
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
                const SizedBox(width: ListenSpacing.gap12),
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
  const LearningResourceScreen({super.key, required this.repository});
  final LearningAssetsRepository repository;

  @override
  State<LearningResourceScreen> createState() => _LearningResourceScreenState();
}

class _LearningResourceScreenState extends State<LearningResourceScreen> {
  List<LearningResourceDescriptor> resources = const [];
  String? busy;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final values = await widget.repository.learningResources();
    if (mounted) setState(() => resources = values);
  }

  Future<void> _toggle(LearningResourceDescriptor value) async {
    final id = value.id;
    setState(() => busy = id);
    try {
      if (value.state == 'installed') {
        await widget.repository.removeLearningResource(id);
      } else {
        await widget.repository.installLearningResource(id);
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
            busy: busy == value.id,
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

  final LexicalEntryDetails details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = details.entry;
    return ListTile(
      title: Text(entry.displayForm),
      subtitle: Text(
        '${l.text(entry.kind)} · '
        '${l.status(entry.status)}',
      ),
      trailing: Text('${details.occurrences.length} ${l.text('sources')}'),
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

  final LearningResourceDescriptor value;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(value.displayName),
    subtitle: Text(
      '${value.version} · ${value.license} · ${value.state}\n'
      '${value.checksumSha256}',
    ),
    isThreeLine: true,
    trailing: busy
        ? const ListenLoading.inline()
        : IconButton(
            icon: Icon(
              value.state == 'installed'
                  ? Icons.delete_outline
                  : Icons.download,
            ),
            onPressed: onToggle,
          ),
  );
}

Future<LexicalEntryDetails?> showPhraseCandidate({
  required BuildContext context,
  required LearningAssetsRepository repository,
  required PhraseCandidate candidate,
  required Map<String, dynamic> source,
  String? initialStatus,
}) async {
  var status = initialStatus ?? 'known_not_recognized';
  LexicalEntryDetails? saved;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(candidate.displayForm),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).text('phraseCandidatesHint')),
              const SizedBox(height: ListenSpacing.gap12),
              Text(candidate.reason ?? ''),
              const SizedBox(height: ListenSpacing.gap12),
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
              saved = await repository.upsertLexicalEntry({
                'language': source['language'] as String? ?? 'en',
                'kind': 'phrase',
                'canonical_form': candidate.canonicalForm,
                'display_form': candidate.displayForm,
                'status': status,
                'source': {
                  ...source,
                  'original_form': candidate.displayForm,
                  'token_start': candidate.tokenStart,
                  'token_end': candidate.tokenEnd,
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
  required LearningAssetsRepository repository,
  required String apiKey,
  required String initialTitle,
  required String initialFilename,
  required String? mediaPath,
}) async {
  final controller = TextEditingController(text: initialTitle);
  var values = <OpenSubtitleCandidate>[];
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
                              ? await repository.openSubtitlesMovieHash(
                                  mediaPath,
                                )
                              : null;
                          values = await repository.searchOpenSubtitles(
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
                        title: Text(value.release),
                        subtitle: Text(
                          '${value.language} · rating ${value.rating} · ${value.downloadCount} downloads',
                        ),
                        onTap: () async {
                          selected = await repository.downloadOpenSubtitle(
                            apiKey: apiKey,
                            fileId: value.fileId,
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
