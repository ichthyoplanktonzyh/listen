import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';

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

  final Diagnosis diagnosis;
  final PronunciationAnalysis? pronunciation;
  final String ruleHintsLevel;
  final List<PronunciationProvider> pronunciationProviders;
  final String? timingQuality;
  final PhoneticAnalysis? phoneticAnalysis;
  final DetectedPhone? currentDetectedPhone;
  final VoidCallback? onAnalyzePhonetics;
  final VoidCallback? onAnalyzeTrackPhonetics;
  final ValueChanged<DetectedPhone>? onLoopDetectedPhone;
  final ValueChanged<PhoneticFinding>? onLoopFinding;
  final void Function(PhoneticFinding finding, String value)? onFindingFeedback;

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
                '${provider.displayName} ${provider.version} · '
                '${provider.degraded ? l.text('degraded') : l.text('ready')}'
                '${provider.diagnostic == null ? '' : ' · ${provider.diagnostic}'}',
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
              '${phoneticAnalysis!.providerId} · '
              '${phoneticAnalysis!.modelRevision} · '
              '${phoneticAnalysis!.phoneSet}',
            ),
            if (phoneticAnalysis!.soundAnalysis?.rhythmFrame != null)
              _rhythmFrame(
                context,
                phoneticAnalysis!.soundAnalysis!.rhythmFrame!,
              ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final phone in phoneticAnalysis!.detectedPhones)
                  ActionChip(
                    label: Text(
                      '${phone.displayIpa} '
                      '${((phone.confidence ?? 0) * 100).round()}%',
                    ),
                    onPressed: onLoopDetectedPhone == null
                        ? null
                        : () => onLoopDetectedPhone!(phone),
                  ),
              ],
            ),
            if (currentDetectedPhone != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${l.text('currentDetectedPhone')}: '
                  '${currentDetectedPhone!.displayIpa} '
                  '(${((currentDetectedPhone!.confidence ?? 0) * 100).round()}%)',
                ),
              ),
            for (final finding in phoneticAnalysis!.findings)
              _finding(context, finding, onLoopFinding, onFindingFeedback),
          ],
          for (final hint in diagnosis.hints)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ${l.diagnosis(hint.kind)}'),
                  if (hint.reasons.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2),
                      child: Text(
                        '${l.text('possibleListeningFactors')} '
                        '${hint.reasons.map(l.diagnosisReason).join(' · ')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xffaab4c0),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (ruleHintsLevel != 'off' &&
              (pronunciation?.rules.isNotEmpty ?? false))
            _section(
              l.text('rulePrediction'),
              l.text('rulePredictionDisclaimer'),
            ),
          if (ruleHintsLevel != 'off')
            for (final rule in pronunciation?.rules ?? const [])
              if (ruleHintsLevel == 'all' || rule.status == 'likely_by_context')
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '• ${rule.ruleFamily}: ${rule.reason} '
                    '(${(rule.confidence * 100).round()}%)',
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

  Widget _rhythmFrame(BuildContext context, RhythmFrame frame) {
    final l = AppLocalizations.of(context);
    final quality = (frame.quality.rhythmConfidence * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.text('listeningRhythm'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (frame.nuclei.isNotEmpty)
            _chipLine(
              'Nucleus',
              frame.nuclei.map(
                (nucleus) => _confidenceLabel(
                  nucleus.label,
                  nucleus.confidence,
                  nucleus.claimStatus,
                ),
              ),
              const Color(0xffff7da8),
            ),
          if (frame.stressAnchors.isNotEmpty)
            _chipLine(
              l.text('stressAnchors'),
              frame.stressAnchors.map(
                (anchor) => _confidenceLabel(
                  anchor.label,
                  anchor.confidence,
                  anchor.claimStatus,
                ),
              ),
              const Color(0xff6fb6ff),
            ),
          if (frame.weakGroups.isNotEmpty)
            _chipLine(
              l.text('weakGroups'),
              frame.weakGroups.map(
                (group) => _confidenceLabel(
                  group.label,
                  group.confidence,
                  group.claimStatus,
                ),
              ),
              const Color(0xff9fb0bd),
            ),
          if (frame.compressionSpans.isNotEmpty)
            _chipLine(
              l.text('compressedSpans'),
              frame.compressionSpans.map(
                (span) => _confidenceLabel(
                  span.label,
                  span.confidence,
                  span.claimStatus,
                ),
              ),
              const Color(0xffffbf69),
            ),
          if (frame.listeningHotspots.isNotEmpty)
            _chipLine(
              l.text('listeningHotspots'),
              frame.listeningHotspots
                  .take(4)
                  .map(
                    (hotspot) => _confidenceLabel(
                      hotspot.label,
                      hotspot.confidence,
                      hotspot.claimStatus,
                    ),
                  ),
              const Color(0xffffd166),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${l.text('rhythmQuality')}: $quality% · '
              '${frame.quality.timingSource.replaceAll('_', ' ')} · '
              'prominence ${_sourceLabel(frame.quality.prominenceSources)} · '
              'boundary ${_sourceLabel(frame.quality.boundarySources)}',
              style: const TextStyle(fontSize: 12, color: Color(0xffaab4c0)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipLine(String label, Iterable<String> values, Color color) {
    final chips = values
        .where((value) => value.trim().isNotEmpty)
        .map(
          (value) => Chip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: color.withAlpha(42),
            side: BorderSide(color: color.withAlpha(115)),
            label: Text(
              value,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(growable: false);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$label:', style: const TextStyle(fontSize: 12)),
          ...chips,
        ],
      ),
    );
  }

  String _confidenceLabel(String label, double confidence, String claimStatus) {
    final percent = (confidence * 100).round();
    final status = claimStatus == 'audio_supported' ? 'audible' : 'predicted';
    return '$label $percent% $status';
  }

  String _sourceLabel(List<String> values) {
    if (values.isEmpty) return 'unknown';
    return values.map((value) => value.replaceAll('_', ' ')).join('/');
  }

  Widget _finding(
    BuildContext context,
    PhoneticFinding finding,
    ValueChanged<PhoneticFinding>? onLoop,
    void Function(PhoneticFinding, String)? onFeedback,
  ) {
    final l = AppLocalizations.of(context);
    final confidence = finding.confidence * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${finding.findingType} · ${finding.status} · '
              '${confidence.round()}%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(finding.evidence),
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
