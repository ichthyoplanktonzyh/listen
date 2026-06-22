import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';

class DiagnosisCard extends StatelessWidget {
  const DiagnosisCard({
    super.key,
    required this.diagnosis,
    this.pronunciation,
    this.ruleHintsLevel = 'likely',
    this.pronunciationProviders = const [],
    this.timingQuality,
    this.phoneticAnalysis,
    this.currentDetectedPhone,
    this.onAnalyzePhonetics,
    this.onAnalyzeTrackPhonetics,
    this.onLoopDetectedPhone,
    this.onLoopFinding,
    this.onFindingFeedback,
  });

  final Map<String, dynamic> diagnosis;
  final Map<String, dynamic>? pronunciation;
  final String ruleHintsLevel;
  final List<Map<String, dynamic>> pronunciationProviders;
  final String? timingQuality;
  final Map<String, dynamic>? phoneticAnalysis;
  final DetectedPhone? currentDetectedPhone;
  final VoidCallback? onAnalyzePhonetics;
  final VoidCallback? onAnalyzeTrackPhonetics;
  final ValueChanged<DetectedPhone>? onLoopDetectedPhone;
  final ValueChanged<Map<String, dynamic>>? onLoopFinding;
  final void Function(Map<String, dynamic> finding, String value)?
  onFindingFeedback;

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
            _section(
              l.text('canonicalPronunciation'),
              '${l.text('pronunciationCache')}: ${l.text('cacheReusable')}',
            ),
          if (onAnalyzePhonetics != null)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onAnalyzePhonetics,
                  child: Text(l.text('analyzeRealPronunciation')),
                ),
                if (onAnalyzeTrackPhonetics != null)
                  OutlinedButton(
                    onPressed: onAnalyzeTrackPhonetics,
                    child: Text(l.text('analyzeSubtitleTrack')),
                  ),
              ],
            ),
          if (phoneticAnalysis != null) ...[
            _section(
              l.text('audioDetectionExperimental'),
              '${phoneticAnalysis!['provider_id']} · '
              '${phoneticAnalysis!['model_revision']} · '
              '${phoneticAnalysis!['phone_set']}',
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final raw
                    in phoneticAnalysis!['detected_phones'] as List<dynamic>)
                  ActionChip(
                    label: Text(
                      '${raw['symbol']} '
                      '${(((raw['confidence'] as num?)?.toDouble() ?? 0) * 100).round()}%',
                    ),
                    onPressed: onLoopDetectedPhone == null
                        ? null
                        : () => onLoopDetectedPhone!(
                            DetectedPhone.fromJson(raw as Map<String, dynamic>),
                          ),
                  ),
              ],
            ),
            if (currentDetectedPhone != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${l.text('currentDetectedPhone')}: '
                  '${currentDetectedPhone!.symbol} '
                  '(${((currentDetectedPhone!.confidence ?? 0) * 100).round()}%)',
                ),
              ),
            for (final raw in phoneticAnalysis!['findings'] as List<dynamic>)
              _finding(
                context,
                raw as Map<String, dynamic>,
                onLoopFinding,
                onFindingFeedback,
              ),
          ],
          for (final hint in diagnosis['hints'] as List<dynamic>)
            Builder(
              builder: (context) {
                final map = hint as Map<String, dynamic>;
                final reasons = (map['reasons'] as List<dynamic>? ?? const [])
                    .cast<String>();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ${l.diagnosis(map['kind'] as String)}'),
                      if (reasons.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 2),
                          child: Text(
                            '${l.text('possibleListeningFactors')} '
                            '${reasons.map(l.diagnosisReason).join(' · ')}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xffaab4c0),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          if (ruleHintsLevel != 'off' && pronunciation?['rules'] != null)
            _section(
              l.text('rulePrediction'),
              l.text('rulePredictionDisclaimer'),
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

  Widget _section(String title, String body) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(body),
      ],
    ),
  );

  Widget _finding(
    BuildContext context,
    Map<String, dynamic> finding,
    ValueChanged<Map<String, dynamic>>? onLoop,
    void Function(Map<String, dynamic>, String)? onFeedback,
  ) {
    final l = AppLocalizations.of(context);
    final confidence = ((finding['confidence'] as num?)?.toDouble() ?? 0) * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${finding['finding_type']} · ${finding['status']} · '
              '${confidence.round()}%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(finding['evidence'] as String? ?? ''),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: onLoop == null ? null : () => onLoop(finding),
                  child: Text(l.text('loopEvidence')),
                ),
                TextButton(
                  onPressed: onFeedback == null
                      ? null
                      : () => onFeedback(finding, 'confirmed'),
                  child: Text(l.text('feedbackConfirmed')),
                ),
                TextButton(
                  onPressed: onFeedback == null
                      ? null
                      : () => onFeedback(finding, 'rejected'),
                  child: Text(l.text('feedbackRejected')),
                ),
                TextButton(
                  onPressed: onFeedback == null
                      ? null
                      : () => onFeedback(finding, 'ignored'),
                  child: Text(l.text('feedbackIgnored')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
