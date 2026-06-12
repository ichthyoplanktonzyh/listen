import 'package:flutter/material.dart';

import '../../localization.dart';

class VocabularyBookView extends StatelessWidget {
  const VocabularyBookView({
    super.key,
    required this.words,
    required this.onWord,
  });

  final List<Map<String, dynamic>> words;
  final ValueChanged<Map<String, dynamic>> onWord;

  @override
  Widget build(BuildContext context) => words.isEmpty
      ? Center(child: Text(AppLocalizations.of(context).text('noWords')))
      : ListView.builder(
          itemCount: words.length,
          itemBuilder: (context, index) {
            final value = words[index];
            final profile = value['profile'] as Map<String, dynamic>;
            final occurrences = value['occurrences'] as List<dynamic>;
            return ListTile(
              title: Text(profile['display_form'] as String),
              subtitle: Text(
                occurrences.isEmpty
                    ? AppLocalizations.of(context).text('noSourceSnapshot')
                    : (occurrences.first
                              as Map<String, dynamic>)['sentence_text_snapshot']
                          as String,
              ),
              trailing: Icon(
                occurrences.isNotEmpty &&
                        (occurrences.first
                                as Map<String, dynamic>)['media_id'] !=
                            null
                    ? Icons.play_arrow
                    : Icons.link_off,
              ),
              onTap: () => onWord(value),
            );
          },
        );
}
