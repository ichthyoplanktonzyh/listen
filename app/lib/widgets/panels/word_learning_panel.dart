import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../vocabulary/pronunciation_button.dart';

class WordLearningPanel extends StatefulWidget {
  const WordLearningPanel({
    super.key,
    required this.details,
    required this.dictionary,
    this.pronunciation,
    this.languageProfile,
    required this.onStatus,
    required this.onSave,
    required this.onSource,
    required this.onHeard,
    required this.onNotHeard,
  });

  final LexicalEntryDetails details;
  final DictionaryLookupBundle? dictionary;
  final WordPronunciation? pronunciation;
  final LanguageProfile? languageProfile;
  final ValueChanged<String?> onStatus;
  final Future<void> Function(String?, String?) onSave;
  final ValueChanged<Map<String, dynamic>> onSource;
  final VoidCallback onHeard;
  final VoidCallback onNotHeard;

  @override
  State<WordLearningPanel> createState() => _WordLearningPanelState();
}

class _WordLearningPanelState extends State<WordLearningPanel> {
  late final TextEditingController definition;
  late final TextEditingController note;

  LexicalEntry get entry => widget.details.entry;

  @override
  void initState() {
    super.initState();
    definition = TextEditingController(text: entry.userDefinition ?? '');
    note = TextEditingController(text: entry.personalNote ?? '');
  }

  @override
  void didUpdateWidget(covariant WordLearningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details != widget.details) {
      definition.text = entry.userDefinition ?? '';
      note.text = entry.personalNote ?? '';
    }
  }

  @override
  void dispose() {
    definition.dispose();
    note.dispose();
    super.dispose();
  }

  /// Per-character breakdown for a multi-character Chinese word: pinyin + meaning
  /// per character. Prefers backend-supplied `character_breakdowns` from the
  /// dictionary provider (which does per-char CC-CEDICT lookups), falling back to
  /// client-side pinyin syllable splitting when the backend field is absent.
  /// Gated on `pronunciation == 'zh.pinyin'` from the language profile (exposed
  /// via the capability matrix API) rather than a hardcoded language check, so
  /// any future language with per-character pronunciation routes through the same
  /// path. Empty for non-Chinese, single-character words, or mismatched counts.
  List<({String character, String pinyin, String meaning})>
  _hanCharacterBreakdown() {
    if (widget.languageProfile?.pronunciation != 'zh.pinyin') {
      return const [];
    }
    final word = entry.displayForm;
    final characters = word.runes.map(String.fromCharCode).toList();
    if (characters.length < 2) return const [];
    final backend = _backendCharacterBreakdowns();
    if (backend.isNotEmpty) return backend;
    final pinyin = _firstChinesePinyin();
    if (pinyin == null) return const [];
    final syllables = pinyin
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList();
    if (syllables.length != characters.length) return const [];
    return [
      for (var index = 0; index < characters.length; index += 1)
        (character: characters[index], pinyin: syllables[index], meaning: ''),
    ];
  }

  List<({String character, String pinyin, String meaning})>
  _backendCharacterBreakdowns() {
    for (final result in widget.dictionary?.results ?? const []) {
      final breakdowns = result.lookup?.characterBreakdowns ?? const [];
      if (breakdowns.isEmpty) continue;
      return [
        for (final value in breakdowns)
          (
            character: value.character,
            pinyin: value.phonetic,
            meaning: value.meaning,
          ),
      ];
    }
    return const [];
  }

  String? _firstChinesePinyin() {
    for (final result in widget.dictionary?.results ?? const []) {
      for (final phonetic in result.lookup?.phonetics ?? const []) {
        final text = phonetic.text.trim();
        if (phonetic.region == 'zh' && text.isNotEmpty) return text;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final results = widget.dictionary?.results ?? const [];
    final characterBreakdown = _hanCharacterBreakdown();
    // Only IPA-bearing variants are worth a section. Languages without an IPA
    // pronunciation provider (e.g. Chinese, whose pinyin arrives via the
    // dictionary phonetics below) yield empty variants, so the section hides
    // instead of showing a blank row.
    final pronunciationVariants = [
      for (final variant in widget.pronunciation?.variants ?? const [])
        if (variant.displayIpa.isNotEmpty) variant,
    ];
    final occurrences = widget.details.occurrences;
    final history = widget.details.history;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text(
          entry.displayForm,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text('${l.text('currentStatus')}: ${l.status(entry.status)}'),
        Wrap(
          spacing: 6,
          children: [
            for (final value in const [
              null,
              'unknown_meaning',
              'known_not_recognized',
              'known_recognized',
            ])
              ChoiceChip(
                label: Text(l.status(value)),
                selected: entry.status == value,
                onSelected: (_) => widget.onStatus(value),
              ),
          ],
        ),
        const Divider(),
        if (characterBreakdown.isNotEmpty) ...[
          Text(
            l.text('characters'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final entry in characterBreakdown)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.character,
                        style: const TextStyle(fontSize: 22),
                      ),
                      Text(entry.pinyin, style: const TextStyle(fontSize: 13)),
                      if (entry.meaning.isNotEmpty)
                        Text(
                          entry.meaning,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).textTheme.bodySmall?.color
                                ?.withValues(alpha: 0.7),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(),
        ],
        if (pronunciationVariants.isNotEmpty) ...[
          Text(
            l.text('pronunciation'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final variant in pronunciationVariants)
            ListTile(
              dense: true,
              title: Text(variant.displayIpa),
              subtitle: Text(
                '${variant.isFallback ? 'deterministic fallback' : 'CMUdict'} · '
                '${variant.phonemes.map((value) => value.symbol).join(' ')}',
              ),
            ),
          const Divider(),
        ],
        Text(
          l.text('dictionary'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (results.isEmpty) Text(l.text('noDictionary')),
        for (final result in results)
          Builder(
            builder: (context) {
              final lookup = result.lookup;
              return ExpansionTile(
                initiallyExpanded: true,
                title: Text(result.provider.displayName),
                subtitle: result.error == null
                    ? null
                    : Text(l.text('providerUnavailable')),
                children: [
                  if (result.error != null)
                    ListTile(title: Text(result.error!)),
                  if (lookup != null)
                    for (final value in lookup.phonetics)
                      ListTile(
                        dense: true,
                        title: Text(value.text),
                        trailing:
                            value.audioUrl != null && value.audioUrl!.isNotEmpty
                            ? PronunciationButton(audioUrl: value.audioUrl!)
                            : null,
                      ),
                  if (lookup != null)
                    for (final value in lookup.definitions)
                      ListTile(
                        dense: true,
                        title: Text(value.text),
                        subtitle: Text(value.partOfSpeech ?? ''),
                      ),
                ],
              );
            },
          ),
        TextField(
          controller: definition,
          maxLines: 3,
          decoration: InputDecoration(labelText: l.text('userDefinition')),
        ),
        TextField(
          controller: note,
          maxLines: 4,
          decoration: InputDecoration(labelText: l.text('personalNote')),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => widget.onSave(definition.text, note.text),
            child: Text(l.text('save')),
          ),
        ),
        Row(
          children: [
            TextButton(onPressed: widget.onHeard, child: Text(l.text('heard'))),
            TextButton(
              onPressed: widget.onNotHeard,
              child: Text(l.text('notHeard')),
            ),
          ],
        ),
        const Divider(),
        Text(
          l.text('sources'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final occurrence in occurrences)
          ListTile(
            title: Text(occurrence.sentenceTextSnapshot),
            subtitle: Text(
              '${occurrence.mediaTitleSnapshot} · ${l.text('encountered')} ${occurrence.encounterCount} ${l.text('times')}',
            ),
            trailing: Icon(
              occurrence.mediaId == null ? Icons.link_off : Icons.play_arrow,
            ),
            onTap: () => widget.onSource(occurrence.toJson()),
          ),
        const Divider(),
        Text(
          l.text('statusHistory'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final item in history)
          ListTile(
            dense: true,
            title: Text(
              '${l.status(item.previousStatus)} → ${l.status(item.newStatus)}',
            ),
            subtitle: Text('${item.changeSource} · ${item.changedAtMs}'),
          ),
      ],
    );
  }
}
