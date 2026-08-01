import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/learning_assets_view_models.dart';
import 'localization.dart';
import 'models/runtime_resources.dart';
import 'models/types.dart';
import 'theme/spacing.dart';
import 'widgets/common/listen_loading.dart';
import 'widgets/common/api_failure_disclosure.dart';

class LearningAssetsScreen extends StatefulWidget {
  const LearningAssetsScreen({
    super.key,
    required this.viewModel,
    required this.personalExpressionBuilder,
  });

  final LearningAssetsViewModel viewModel;
  final WidgetBuilder personalExpressionBuilder;

  @override
  State<LearningAssetsScreen> createState() => _LearningAssetsScreenState();
}

class _LearningAssetsScreenState extends State<LearningAssetsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.load());
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
                await widget.viewModel.saveEntry(
                  entry: entry,
                  status: selectedStatus,
                  definition: definition.text,
                  note: note.text,
                );
                if (context.mounted) Navigator.pop(context);
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
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final state = widget.viewModel.state;
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
                          builder: widget.personalExpressionBuilder,
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
                        ButtonSegment(
                          value: 'word',
                          label: Text(l.text('words')),
                        ),
                        ButtonSegment(
                          value: 'phrase',
                          label: Text(l.text('phrases')),
                        ),
                      ],
                      selected: {state.kind},
                      onSelectionChanged: (value) {
                        unawaited(widget.viewModel.setKind(value.first));
                      },
                    ),
                    const SizedBox(width: ListenSpacing.gap12),
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: l.text('searchVocabulary'),
                        ),
                        onChanged: (value) =>
                            unawaited(widget.viewModel.setSearch(value)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final details in state.values)
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
      },
    );
  }
}

class LearningResourceScreen extends StatefulWidget {
  const LearningResourceScreen({super.key, required this.viewModel});
  final LearningResourcesViewModel viewModel;

  @override
  State<LearningResourceScreen> createState() => _LearningResourceScreenState();
}

class _LearningResourceScreenState extends State<LearningResourceScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.load());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).text('resources')),
      ),
      body: ListView(
        children: [
          for (final value in widget.viewModel.state.resources)
            LearningResourceTile(
              value: value,
              busy: widget.viewModel.state.busyId == value.id,
              onToggle: () => widget.viewModel.toggle(value),
            ),
        ],
      ),
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
  required PhraseCandidateViewModel viewModel,
}) async {
  LexicalEntryDetails? saved;
  await showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => AlertDialog(
        title: Text(viewModel.candidate.displayForm),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).text('phraseCandidatesHint')),
              const SizedBox(height: ListenSpacing.gap12),
              Text(viewModel.candidate.reason ?? ''),
              const SizedBox(height: ListenSpacing.gap12),
              DropdownButtonFormField<String>(
                initialValue: viewModel.status,
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
                onChanged: (value) {
                  if (value != null) viewModel.setStatus(value);
                },
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
              saved = await viewModel.save();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context).text('confirmPhrase')),
          ),
        ],
      ),
    ),
  );
  viewModel.dispose();
  return saved;
}

Future<String?> showOpenSubtitlesSearch({
  required BuildContext context,
  required OpenSubtitlesSearchViewModel viewModel,
}) async {
  final controller = TextEditingController(text: viewModel.state.query);
  String? selected;
  await showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('openSubtitles')),
        content: SizedBox(
          width: 680,
          height: 480,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: viewModel.state.mode,
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
                  if (value == null) return;
                  viewModel.setMode(value);
                  controller.text = viewModel.state.query;
                },
              ),
              if (viewModel.state.mode != 'hash')
                TextField(
                  controller: controller,
                  onChanged: viewModel.setQuery,
                ),
              FilledButton(
                onPressed: viewModel.state.loading ? null : viewModel.search,
                child: Text(AppLocalizations.of(context).text('search')),
              ),
              if (viewModel.state.loading) const LinearProgressIndicator(),
              if (viewModel.state.failure != null) ...[
                Text(
                  AppLocalizations.of(
                    context,
                  ).text(viewModel.state.failure!.messageKey),
                ),
                if (ApiFailureDisclosure.hasDetail(
                  viewModel.state.failure!.detail,
                ))
                  ApiFailureDisclosure(
                    failure: viewModel.state.failure!.detail!,
                  ),
              ],
              Expanded(
                child: ListView(
                  children: [
                    for (final value in viewModel.state.values)
                      ListTile(
                        title: Text(value.release),
                        subtitle: Text(
                          '${value.language} · rating ${value.rating} · ${value.downloadCount} downloads',
                        ),
                        onTap: () async {
                          selected = await viewModel.download(value.fileId);
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
  viewModel.dispose();
  return selected;
}
