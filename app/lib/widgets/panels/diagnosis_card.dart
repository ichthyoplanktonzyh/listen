import 'package:flutter/material.dart';

import '../../localization.dart';

class DiagnosisCard extends StatelessWidget {
  const DiagnosisCard({super.key, required this.diagnosis});

  final Map<String, dynamic> diagnosis;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 190),
      padding: const EdgeInsets.all(12),
      color: const Color(0xff202832),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'Current sentence diagnosis',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final hint in diagnosis['hints'] as List<dynamic>)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• ${l.diagnosis(hint['kind'] as String)}'),
            ),
        ],
      ),
    );
  }
}
