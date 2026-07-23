import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/spacing.dart';

class VocabularyDetailsView extends StatelessWidget {
  const VocabularyDetailsView({
    super.key,
    required this.entry,
    required this.occurrences,
    required this.history,
    required this.onSource,
  });

  final Map<String, dynamic> entry;
  final List<Map<String, dynamic>> occurrences;
  final List<Map<String, dynamic>> history;
  final ValueChanged<Map<String, dynamic>> onSource;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 620,
    height: 480,
    child: ListView(
      children: [
        Text(
          '${AppLocalizations.of(context).text('currentStatus')}: ${AppLocalizations.of(context).status(entry['status'] as String?)}',
        ),
        const SizedBox(height: ListenSpacing.gap16),
        Text(
          AppLocalizations.of(context).text('sources'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final occurrence in occurrences)
          ListTile(
            title: Text(occurrence['sentence_text_snapshot'] as String),
            subtitle: Text(
              '${occurrence['media_title_snapshot']} · encountered ${occurrence['encounter_count']} times',
            ),
            trailing: Icon(
              occurrence['media_id'] == null
                  ? Icons.link_off
                  : Icons.play_arrow,
            ),
            onTap: () => onSource(occurrence),
          ),
        const Divider(),
        Text(
          AppLocalizations.of(context).text('statusHistory'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final item in history)
          ListTile(
            dense: true,
            title: Text('${item['previous_status']} → ${item['new_status']}'),
            subtitle: Text(
              '${item['change_source']} · ${item['changed_at_ms']}',
            ),
          ),
      ],
    ),
  );
}
