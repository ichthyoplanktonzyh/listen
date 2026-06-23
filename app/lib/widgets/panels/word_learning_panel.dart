import 'package:flutter/material.dart';

import '../../localization.dart';
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

  final Map<String, dynamic> details;
  final Map<String, dynamic>? dictionary;
  final Map<String, dynamic>? pronunciation;
  final Map<String, dynamic>? languageProfile;
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

  Map<String, dynamic> get profile =>
      widget.details['profile'] as Map<String, dynamic>;

  @override
  void initState() {
    super.initState();
    definition = TextEditingController(
      text: profile['user_definition'] as String? ?? '',
    );
    note = TextEditingController(
      text: profile['personal_note'] as String? ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant WordLearningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details != widget.details) {
      definition.text = profile['user_definition'] as String? ?? '';
      note.text = profile['personal_note'] as String? ?? '';
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
    if (widget.languageProfile?['pronunciation'] != 'zh.pinyin') return const [];
    final word = profile['display_form'] as String;
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
        (
          character: characters[index],
          pinyin: syllables[index],
          meaning: '',
        ),
    ];
  }

  List<({String character, String pinyin, String meaning})>
      _backendCharacterBreakdowns() {
    for (final raw
        in (widget.dictionary?['results'] as List<dynamic>? ?? const [])) {
      final lookup = (raw as Map<String, dynamic>)['lookup'] as Map?;
      final breakdowns =
          lookup?['character_breakdowns'] as List<dynamic>? ?? const [];
      if (breakdowns.isEmpty) continue;
      return [
        for (final entry in breakdowns)
          (
            character: (entry as Map<String, dynamic>)['character'] as String,
            pinyin: entry['phonetic'] as String? ?? '',
            meaning: entry['meaning'] as String? ?? '',
          ),
      ];
    }
    return const [];
  }

  String? _firstChinesePinyin() {
    for (final raw
        in (widget.dictionary?['results'] as List<dynamic>? ?? const [])) {
      final lookup = (raw as Map<String, dynamic>)['lookup'] as Map?;
      for (final phonetic in (lookup?['phonetics'] as List<dynamic>? ?? const [])) {
        final map = phonetic as Map<String, dynamic>;
        final text = (map['text'] as String?)?.trim() ?? '';
        if (map['region'] == 'zh' && text.isNotEmpty) return text;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final results =
        (widget.dictionary?['results'] as List<dynamic>? ?? const []);
    final characterBreakdown = _hanCharacterBreakdown();
    // Only IPA-bearing variants are worth a section. Languages without an IPA
    // pronunciation provider (e.g. Chinese, whose pinyin arrives via the
    // dictionary phonetics below) yield empty variants, so the section hides
    // instead of showing a blank row.
    final pronunciationVariants = [
      for (final raw in (widget.pronunciation?['variants'] as List<dynamic>? ??
          const []))
        if (((raw as Map<String, dynamic>)['display_ipa'] as String?)
                ?.isNotEmpty ??
            false)
          raw,
    ];
    final occurrences = widget.details['occurrences'] as List<dynamic>;
    final history = widget.details['history'] as List<dynamic>;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text(
          profile['display_form'] as String,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          '${l.text('currentStatus')}: ${l.status(profile['status'] as String?)}',
        ),
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
                selected: profile['status'] == value,
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
                      Text(
                        entry.pinyin,
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (entry.meaning.isNotEmpty)
                        Text(
                          entry.meaning,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color
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
          for (final raw in pronunciationVariants)
            ListTile(
              dense: true,
              title: Text(
                raw['display_ipa'] as String,
              ),
              subtitle: Text(
                '${raw['is_fallback'] == true ? 'deterministic fallback' : 'CMUdict'} · '
                '${(raw['phonemes'] as List<dynamic>).map((value) => (value as Map<String, dynamic>)['symbol']).join(' ')}',
              ),
            ),
          const Divider(),
        ],
        Text(
          l.text('dictionary'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (results.isEmpty) Text(l.text('noDictionary')),
        for (final raw in results)
          Builder(
            builder: (context) {
              final result = raw as Map<String, dynamic>;
              final provider = result['provider'] as Map<String, dynamic>;
              final lookup = result['lookup'] as Map<String, dynamic>?;
              return ExpansionTile(
                initiallyExpanded: true,
                title: Text(provider['display_name'] as String),
                subtitle: result['error'] == null
                    ? null
                    : Text(l.text('providerUnavailable')),
                children: [
                  if (result['error'] != null)
                    ListTile(title: Text(result['error'] as String)),
                  if (lookup != null)
                    for (final value in lookup['phonetics'] as List<dynamic>)
                      ListTile(
                        dense: true,
                        title: Text(
                          (value as Map<String, dynamic>)['text'] as String,
                        ),
                        trailing:
                            value['audio_url'] is String &&
                                (value['audio_url'] as String).isNotEmpty
                            ? PronunciationButton(
                                audioUrl: value['audio_url'] as String,
                              )
                            : null,
                      ),
                  if (lookup != null)
                    for (final value in lookup['definitions'] as List<dynamic>)
                      ListTile(
                        dense: true,
                        title: Text(
                          (value as Map<String, dynamic>)['text'] as String,
                        ),
                        subtitle: Text(
                          value['part_of_speech'] as String? ?? '',
                        ),
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
        for (final raw in occurrences)
          ListTile(
            title: Text(
              (raw as Map<String, dynamic>)['sentence_text_snapshot'] as String,
            ),
            subtitle: Text(
              '${raw['media_title_snapshot']} · ${l.text('encountered')} ${raw['encounter_count']} ${l.text('times')}',
            ),
            trailing: Icon(
              raw['media_id'] == null ? Icons.link_off : Icons.play_arrow,
            ),
            onTap: () => widget.onSource(raw),
          ),
        const Divider(),
        Text(
          l.text('statusHistory'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final raw in history)
          ListTile(
            dense: true,
            title: Text(
              '${l.status((raw as Map<String, dynamic>)['previous_status'] as String?)} → ${l.status(raw['new_status'] as String?)}',
            ),
            subtitle: Text('${raw['change_source']} · ${raw['changed_at_ms']}'),
          ),
      ],
    );
  }
}
