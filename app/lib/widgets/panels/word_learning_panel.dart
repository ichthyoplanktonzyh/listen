import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/listen_theme.dart';
import '../../utils/format_duration.dart';
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
    this.onCapabilityOverride,
    this.onRecordSource,
    this.onOpenListeningDictionary,
    this.onPlayPronunciationAudio,
    this.onReadingMark,
    this.hasSelectedCue = false,
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
  final Future<void> Function(String capability, String? conclusion)?
  onCapabilityOverride;
  final VoidCallback? onRecordSource;
  final VoidCallback? onOpenListeningDictionary;
  final ValueChanged<String>? onPlayPronunciationAudio;

  /// Explicit reading mark (Phase 3.13); non-null only while the reading
  /// posture is open. `true` = understood while reading.
  final void Function(bool understood)? onReadingMark;
  final bool hasSelectedCue;

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
    final profile = widget.details.capabilityProfile;
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                entry.displayForm,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: ListenColors.selected,
                border: Border.all(color: ListenColors.primary),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Text(
                  l.status(entry.status),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ListenColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.onOpenListeningDictionary != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.onOpenListeningDictionary,
              icon: const Icon(Icons.headphones_outlined, size: 18),
              label: Text(l.text('openListeningDictionary')),
            ),
          ),
        if (widget.onOpenListeningDictionary != null)
          const SizedBox(height: 14),
        _sectionHeader(
          context,
          l.text('capabilityProfile'),
          Icons.school_outlined,
        ),
        const SizedBox(height: 8),
        if (profile != null)
          _capabilityGrid(context, l, profile)
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
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
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.hearing, size: 18),
              onPressed: widget.onHeard,
              label: Text(l.text('heard')),
            ),
            TextButton.icon(
              icon: const Icon(Icons.hearing_disabled, size: 18),
              onPressed: widget.onNotHeard,
              label: Text(l.text('notHeard')),
            ),
            if (widget.onReadingMark != null) ...[
              TextButton.icon(
                key: const ValueKey('reading-mark-understood'),
                icon: const Icon(Icons.chrome_reader_mode_outlined, size: 18),
                onPressed: () => widget.onReadingMark!(true),
                label: Text(l.text('readUnderstood')),
              ),
              TextButton.icon(
                key: const ValueKey('reading-mark-not-understood'),
                icon: const Icon(Icons.help_outline, size: 18),
                onPressed: () => widget.onReadingMark!(false),
                label: Text(l.text('readNotUnderstood')),
              ),
            ],
          ],
        ),
        const Divider(),
        _sectionHeader(
          context,
          l.text('meaningAndPronunciation'),
          Icons.record_voice_over_outlined,
        ),
        if (characterBreakdown.isNotEmpty) ...[
          const SizedBox(height: 10),
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
        ],
        if (pronunciationVariants.isNotEmpty) ...[
          const SizedBox(height: 10),
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
        ],
        const SizedBox(height: 10),
        if (results.isEmpty)
          Text(
            l.text('noDictionary'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
                            ? PronunciationButton(
                                tooltip: l.text('pronunciation'),
                                onPressed:
                                    widget.onPlayPronunciationAudio == null
                                    ? null
                                    : () => widget.onPlayPronunciationAudio!(
                                        value.audioUrl!,
                                      ),
                              )
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
          key: const Key('word-user-definition'),
          controller: definition,
          maxLines: 3,
          decoration: InputDecoration(labelText: l.text('userDefinition')),
        ),
        TextField(
          key: const Key('word-personal-note'),
          controller: note,
          maxLines: 4,
          decoration: InputDecoration(labelText: l.text('personalNote')),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            icon: const Icon(Icons.save_outlined, size: 18),
            onPressed: () => widget.onSave(definition.text, note.text),
            label: Text(l.text('save')),
          ),
        ),
        const Divider(),
        Row(
          children: [
            Expanded(
              child: _sectionHeader(
                context,
                l.text('sourceSentences'),
                Icons.format_quote_outlined,
              ),
            ),
            if (widget.onRecordSource != null)
              TextButton.icon(
                onPressed: widget.hasSelectedCue ? widget.onRecordSource : null,
                icon: const Icon(Icons.add, size: 16),
                label: Text(l.text('recordCurrentSentence')),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        if (occurrences.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l.text('noSourceSentences')),
          ),
        for (final occurrence in occurrences)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(occurrence.sentenceTextSnapshot),
            subtitle: Text(
              [
                occurrence.mediaTitleSnapshot,
                formatDuration(
                  Duration(milliseconds: occurrence.startMsSnapshot),
                ),
                '${l.text('encountered')} ${occurrence.encounterCount} ${l.text('times')}',
              ].join(' · '),
            ),
            trailing: Icon(
              occurrence.mediaId == null ? Icons.link_off : Icons.play_arrow,
            ),
            onTap: () => widget.onSource(occurrence.toJson()),
          ),
        const Divider(),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('word-learning-history'),
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(l.text('learningHistory')),
            subtitle: history.isEmpty ? null : Text('${history.length}'),
            children: [
              if (history.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(l.text('noLearningHistory')),
                  ),
                ),
              for (final item in history)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${l.status(item.previousStatus)} → ${l.status(item.newStatus)}',
                  ),
                  subtitle: Text(
                    [
                      _humanizeSource(item.changeSource),
                      _formatHistoryTime(item.changedAtMs, l),
                    ].where((value) => value.isNotEmpty).join(' · '),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, IconData icon) =>
      Row(
        children: [
          Icon(icon, size: 18, color: ListenColors.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
        ],
      );

  Widget _capabilityGrid(
    BuildContext context,
    AppLocalizations l,
    LexicalCapabilityProfile profile,
  ) {
    const channels = [
      ('reading', 'capabilityReading', Icons.menu_book_outlined),
      ('listening', 'capabilityListening', Icons.hearing_outlined),
      ('speaking', 'capabilitySpeaking', Icons.record_voice_over_outlined),
      ('writing', 'capabilityWriting', Icons.edit_outlined),
    ];
    CapabilityDimensionState dim(String name) => switch (name) {
      'reading' => profile.reading,
      'listening' => profile.listening,
      'speaking' => profile.speaking,
      _ => profile.writing,
    };
    return Column(
      children: [
        for (final (key, labelKey, icon) in channels)
          _capabilityRow(context, l, key, l.text(labelKey), icon, dim(key)),
      ],
    );
  }

  Widget _capabilityRow(
    BuildContext context,
    AppLocalizations l,
    String capability,
    String label,
    IconData icon,
    CapabilityDimensionState state,
  ) {
    final assessment = state.effectiveAssessment;
    final hasOverride = state.userOverride != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: ListenColors.primary),
          const SizedBox(width: 6),
          SizedBox(
            width: 48,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          for (final value in const ['acquired', 'not_acquired'])
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(
                  l.text(value),
                  style: const TextStyle(fontSize: 12),
                ),
                selected: assessment == value,
                visualDensity: VisualDensity.compact,
                onSelected: widget.onCapabilityOverride == null
                    ? null
                    : (_) => widget.onCapabilityOverride!(
                        capability,
                        assessment == value ? null : value,
                      ),
              ),
            ),
          if (assessment == 'unassessed')
            Text(
              l.text('unassessed'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
            ),
          if (hasOverride)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: 'User override',
                child: Icon(
                  Icons.person_outline,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _humanizeSource(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  String _formatHistoryTime(int milliseconds, AppLocalizations l) {
    if (milliseconds < 946684800000) return l.text('earlier');
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }
}
