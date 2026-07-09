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
  static const capabilities = ['reading', 'listening', 'speaking', 'writing'];
  static const assessmentFilters = ['acquired', 'not_acquired', 'unassessed'];

  // The four-channel capability axis is the primary lens. [capability] picks the
  // channel; [assessment] `null` means "all" (no capability filter applied).
  String capability = 'listening';
  String? assessment;
  String search = '';
  bool loading = true;
  List<Map<String, dynamic>> words = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String _capabilityLabelKey(String value) => switch (value) {
    'reading' => 'capabilityReading',
    'listening' => 'capabilityListening',
    'speaking' => 'capabilitySpeaking',
    _ => 'capabilityWriting',
  };

  Future<void> _load() async {
    setState(() => loading = true);
    final values = await widget.api.listVocabulary(
      language: widget.language,
      capability: assessment == null ? null : capability,
      assessment: assessment,
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
    // Phrases may have no dictionary or pronunciation entry; degrade to null
    // rather than failing the whole detail dialog.
    DictionaryLookupBundle? dictionary;
    try {
      dictionary = DictionaryLookupBundle.fromJson(
        await widget.api.lookupDictionary(
          entry.normalizedForm,
          language: widget.language,
        ),
      );
    } catch (_) {
      dictionary = null;
    }
    WordPronunciation? pronunciation;
    try {
      pronunciation = WordPronunciation.fromJson(
        await widget.api.lookupPronunciation(entry.displayForm),
      );
    } catch (_) {
      pronunciation = null;
    }
    if (!mounted) return;
    final l = AppLocalizations.of(context);
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
            onCapabilityOverride: (capability, conclusion) async {
              await widget.api.setCapabilityOverride(
                entry.id,
                capability,
                conclusion: conclusion,
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
              child: Text(l.text('deferUpgrade')),
            ),
            FilledButton(
              onPressed: () async {
                await widget.api.confirmUpgradeSuggestion(suggestions.first.id);
                if (context.mounted) Navigator.pop(context);
                await _load();
              },
              child: Text(l.text('confirmListeningAcquired')),
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.text('vocabularyBooks')),
        actions: [
          VocabularyTransferActions(
            onExport: widget.onExport,
            onImport: widget.onImport,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: l.text('searchVocabulary'),
              ),
              onChanged: (value) {
                search = value;
                unawaited(_load());
              },
            ),
          ),
          // Primary lens: the four-channel capability axis. The channel picker
          // only affects results once a specific assessment is chosen.
          _filterRow(
            children: [
              for (final cap in capabilities)
                ChoiceChip(
                  label: Text(l.text(_capabilityLabelKey(cap))),
                  selected: capability == cap,
                  onSelected: (_) {
                    setState(() => capability = cap);
                    if (assessment != null) unawaited(_load());
                  },
                ),
            ],
          ),
          _filterRow(
            children: [
              _assessmentChip(l.text('vocabFilterAll'), null),
              for (final value in assessmentFilters)
                _assessmentChip(
                  l.text(value),
                  value,
                  color: capabilityAssessmentColor(value),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : VocabularyBookView(words: words, onWord: _details),
          ),
        ],
      ),
    );
  }

  Widget _filterRow({required List<Widget> children}) => SizedBox(
    height: 44,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, index) => Center(child: children[index]),
    ),
  );

  Widget _assessmentChip(String label, String? value, {Color? color}) =>
      ChoiceChip(
        avatar: color == null
            ? null
            : CircleAvatar(backgroundColor: color, radius: 5),
        label: Text(label),
        selected: assessment == value,
        onSelected: (_) {
          setState(() => assessment = value);
          unawaited(_load());
        },
      );
}
