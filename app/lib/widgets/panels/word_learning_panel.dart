import 'package:flutter/material.dart';

import '../../localization.dart';
import '../vocabulary/pronunciation_button.dart';

class WordLearningPanel extends StatefulWidget {
  const WordLearningPanel({
    super.key,
    required this.details,
    required this.dictionary,
    this.pronunciation,
    required this.onStatus,
    required this.onSave,
    required this.onSource,
    required this.onHeard,
    required this.onNotHeard,
  });

  final Map<String, dynamic> details;
  final Map<String, dynamic>? dictionary;
  final Map<String, dynamic>? pronunciation;
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final results =
        (widget.dictionary?['results'] as List<dynamic>? ?? const []);
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
        if (widget.pronunciation != null) ...[
          Text(
            l.text('pronunciation'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final raw in widget.pronunciation!['variants'] as List<dynamic>)
            ListTile(
              dense: true,
              title: Text(
                (raw as Map<String, dynamic>)['display_ipa'] as String,
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
