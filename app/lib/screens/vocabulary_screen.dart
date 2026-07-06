import 'dart:async';

import 'package:flutter/material.dart';

import '../localization.dart';
import '../models/types.dart';
import '../models/practice.dart';
import '../services/api_service.dart';
import '../widgets/panels/word_learning_panel.dart';
import '../widgets/vocabulary/vocabulary_book_view.dart';
import '../widgets/vocabulary/vocabulary_transfer_actions.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.api,
    required this.language,
    required this.onExport,
    required this.onImport,
  });

  final LocalApi api;
  final String language;
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
    final values = await widget.api.listVocabulary(
      status,
      language: widget.language,
      search: search,
    );
    if (mounted) {
      setState(() {
        words = values;
        loading = false;
      });
    }
  }

  Future<void> _details(Map<String, dynamic> value) async {
    final entry = LexicalEntry.fromJson(value['entry'] as Map<String, dynamic>);
    final details = LexicalEntryDetails.fromJson(
      await widget.api.lexicalEntryDetails(entry.id),
    );
    List<UpgradeSuggestion> suggestions;
    try {
      suggestions = await widget.api.upgradeSuggestions(
        lexicalEntryId: entry.id,
      );
    } catch (_) {
      suggestions = const [];
    }
    final dictionary = DictionaryLookupBundle.fromJson(
      await widget.api.lookupDictionary(
        entry.normalizedForm,
        language: widget.language,
      ),
    );
    final pronunciation = WordPronunciation.fromJson(
      await widget.api.lookupPronunciation(entry.displayForm),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.displayForm),
        content: SizedBox(
          width: 700,
          height: 650,
          child: WordLearningPanel(
            details: details,
            dictionary: dictionary,
            pronunciation: pronunciation,
            onStatus: (value) async {
              await widget.api.upsertWordLexicalEntry(
                entry.normalizedForm,
                entry.displayForm,
                value,
                language: widget.language,
              );
              if (context.mounted) Navigator.pop(context);
              await _load();
            },
            onSave: (definition, note) async {
              await widget.api.updateLexicalLearningContent(
                entry.id,
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
        actions: [
          if (suggestions.isNotEmpty) ...[
            TextButton(
              onPressed: () async {
                await widget.api.rejectUpgradeSuggestion(suggestions.first.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('暂不升级'),
            ),
            FilledButton(
              onPressed: () async {
                await widget.api.confirmUpgradeSuggestion(suggestions.first.id);
                if (context.mounted) Navigator.pop(context);
                await _load();
              },
              child: Text(
                '确认已能听出（${suggestions.first.evidenceContextCount} 个语境）',
              ),
            ),
          ],
          TextButton.icon(
            onPressed: () async {
              try {
                await widget.api.createReviewItem(
                  CreateReviewItem(
                    source: ReviewSource(
                      kind: 'lexical_entry',
                      id: entry.id,
                      lexicalEntryId: entry.id,
                    ),
                    anchors: const [],
                    promptSnapshot: entry.displayForm,
                  ),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(
                  this.context,
                ).showSnackBar(const SnackBar(content: Text('已加入声音复习')));
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  this.context,
                ).showSnackBar(SnackBar(content: Text('加入复习失败：$error')));
              }
            },
            icon: const Icon(Icons.headphones_outlined),
            label: const Text('加入复习'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
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
