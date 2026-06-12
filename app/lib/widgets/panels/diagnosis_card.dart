import 'package:flutter/material.dart';

import '../../localization.dart';

class DiagnosisCard extends StatelessWidget {
  const DiagnosisCard({
    super.key,
    required this.diagnosis,
    this.pronunciation,
    this.ruleHintsLevel = 'likely',
    this.pronunciationProviders = const [],
    this.timingQuality,
  });

  final Map<String, dynamic> diagnosis;
  final Map<String, dynamic>? pronunciation;
  final String ruleHintsLevel;
  final List<Map<String, dynamic>> pronunciationProviders;
  final String? timingQuality;

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
          Text(
            l.text('currentSentenceDiagnosis'),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final provider in pronunciationProviders)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${l.text('pronunciationProvider')}: '
                '${provider['display_name']} ${provider['version']} · '
                '${provider['degraded'] == true ? l.text('degraded') : l.text('ready')}'
                '${provider['diagnostic'] == null ? '' : ' · ${provider['diagnostic']}'}',
              ),
            ),
          if (timingQuality != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${l.text('wordTimingSource')}: $timingQuality'),
            ),
          if (pronunciation != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${l.text('pronunciationCache')}: ${l.text('cacheReusable')}',
              ),
            ),
          for (final hint in diagnosis['hints'] as List<dynamic>)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• ${l.diagnosis(hint['kind'] as String)}'),
            ),
          if (ruleHintsLevel != 'off' && pronunciation?['rules'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                l.text('rulePredictionDisclaimer'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          if (ruleHintsLevel != 'off')
            for (final raw
                in (pronunciation?['rules'] as List<dynamic>? ?? const []))
              if (ruleHintsLevel == 'all' ||
                  (raw as Map<String, dynamic>)['status'] ==
                      'likely_by_context')
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '• ${raw['rule_family']}: ${raw['reason']} '
                    '(${((raw['confidence'] as num) * 100).round()}%)',
                  ),
                ),
        ],
      ),
    );
  }
}
