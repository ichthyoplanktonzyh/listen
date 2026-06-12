import 'dart:async';

import 'package:flutter/material.dart';

import '../localization.dart';
import '../services/api_service.dart';
import '../widgets/panels/word_learning_panel.dart';
import '../widgets/vocabulary/vocabulary_book_view.dart';
import '../widgets/vocabulary/vocabulary_transfer_actions.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.api,
    required this.onExport,
    required this.onImport,
  });

  final LocalApi api;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  static const statuses = [
    'unknown_meaning',
    'known_not_recognized',
    'known_recognized',
  ];
  String status = statuses.first;
  String search = '';
  bool loading = true;
  List<Map<String, dynamic>> words = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final values = await widget.api.listVocabulary(status, search: search);
    if (mounted) {
      setState(() {
        words = values;
        loading = false;
      });
    }
  }

  Future<void> _details(Map<String, dynamic> value) async {
    final profile = value['profile'] as Map<String, dynamic>;
    final details = await widget.api.wordDetails(profile['id'] as String);
    final dictionary = await widget.api.lookupDictionary(
      profile['normalized_lemma'] as String,
    );
    final pronunciation = await widget.api.lookupPronunciation(
      profile['display_form'] as String,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(profile['display_form'] as String),
        content: SizedBox(
          width: 700,
          height: 650,
          child: WordLearningPanel(
            details: details,
            dictionary: dictionary,
            pronunciation: pronunciation,
            onStatus: (value) async {
              await widget.api.updateWordProfile(
                profile['normalized_lemma'] as String,
                profile['display_form'] as String,
                value,
              );
              if (context.mounted) Navigator.pop(context);
              await _load();
            },
            onSave: (definition, note) async {
              await widget.api.updateLearningContent(
                profile['id'] as String,
                userDefinition: definition,
                personalNote: note,
              );
            },
            onSource: (occurrence) {
              Navigator.pop(context);
              Navigator.pop(this.context, occurrence);
            },
            onHeard: () {},
            onNotHeard: () {},
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context).text('vocabularyBooks')),
      actions: [
        VocabularyTransferActions(
          onExport: widget.onExport,
          onImport: widget.onImport,
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              for (final value in statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(AppLocalizations.of(context).status(value)),
                    selected: status == value,
                    onSelected: (_) {
                      status = value;
                      unawaited(_load());
                    },
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: AppLocalizations.of(
                      context,
                    ).text('searchVocabulary'),
                  ),
                  onChanged: (value) {
                    search = value;
                    unawaited(_load());
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : VocabularyBookView(words: words, onWord: _details),
        ),
      ],
    ),
  );
}
