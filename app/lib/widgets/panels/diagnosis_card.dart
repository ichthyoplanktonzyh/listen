import 'dart:async';

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
    this.rhythmFrame,
    this.phoneticAnalysis,
    this.currentDetectedPhone,
    this.onLoopDetectedPhone,
    this.onLoopHotspot,
    this.onLoopFinding,
    this.onFindingFeedback,
    this.onOpenListeningDictionary,
    this.onLoopL1Span,
    this.onOpenL1Specialty,
  });

  final Diagnosis diagnosis;
  final PronunciationAnalysis? pronunciation;
  final String ruleHintsLevel;
  final List<PronunciationProvider> pronunciationProviders;
  final String? timingQuality;
  final RhythmFrame? rhythmFrame;
  final PhoneticAnalysis? phoneticAnalysis;
  final DetectedPhone? currentDetectedPhone;
  final ValueChanged<DetectedPhone>? onLoopDetectedPhone;
  final ValueChanged<ListeningHotspot>? onLoopHotspot;
  final ValueChanged<PhoneticFinding>? onLoopFinding;
  final void Function(PhoneticFinding finding, String value)? onFindingFeedback;
  final Future<void> Function(String lexicalEntryId)? onOpenListeningDictionary;

  /// Replays one L1 difficulty evidence span (loops real audio).
  final ValueChanged<L1DiagnosisSpan>? onLoopL1Span;

  /// Opens the specialty aggregation for one difficulty category.
  final ValueChanged<L1DiagnosisHint>? onOpenL1Specialty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final activeRhythmFrame =
        rhythmFrame ?? phoneticAnalysis?.soundAnalysis?.rhythmFrame;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            l.text('currentSentenceDiagnosis'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          Text(
            l.text('diagnosisSummary'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (diagnosis.hints.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(l.text('diagnosisNoConclusion')),
            )
          else
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
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (onOpenListeningDictionary != null &&
                        hint.lexicalEntryIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          children: [
                            for (final entryId in hint.lexicalEntryIds)
                              TextButton.icon(
                                onPressed: () => unawaited(
                                  onOpenListeningDictionary!(entryId),
                                ),
                                icon: const Icon(
                                  Icons.headphones_outlined,
                                  size: 16,
                                ),
                                label: Text(l.text('openListeningDictionary')),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          if (diagnosis.l1Context != null && !diagnosis.l1Context!.supported)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l.text('l1UnsupportedPair'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (diagnosis.l1Hints.isNotEmpty) _l1Section(context),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('diagnosis-evidence-section'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(l.text('diagnosisEvidence')),
              leading: const Icon(Icons.manage_search_outlined),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                          child: Text(
                            '${l.text('wordTimingSource')}: $timingQuality',
                          ),
                        ),
                      if (pronunciation != null)
                        _section(
                          l.text('canonicalPronunciation'),
                          '${l.text('pronunciationCache')}: ${l.text('cacheReusable')}',
                        ),
                      if (activeRhythmFrame != null)
                        _rhythmFrame(context, activeRhythmFrame),
                      if (phoneticAnalysis != null) ...[
                        _section(
                          l.text('audioDetectionExperimental'),
                          '${phoneticAnalysis!.providerId} · '
                          '${phoneticAnalysis!.modelRevision} · '
                          '${phoneticAnalysis!.phoneSet}',
                        ),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final phone
                                in phoneticAnalysis!.detectedPhones)
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
                          _finding(
                            context,
                            finding,
                            onLoopFinding,
                            onFindingFeedback,
                          ),
                      ],
                      if (ruleHintsLevel != 'off' &&
                          (pronunciation?.rules.isNotEmpty ?? false))
                        _section(
                          l.text('rulePrediction'),
                          l.text('rulePredictionDisclaimer'),
                        ),
                      if (ruleHintsLevel != 'off')
                        for (final rule in pronunciation?.rules ?? const [])
                          if (ruleHintsLevel == 'all' ||
                              rule.status == 'likely_by_context')
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                '• ${rule.ruleFamily}: ${rule.reason} '
                                '(${(rule.confidence * 100).round()}%)',
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _l1Section(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      key: const Key('diagnosis-l1-section'),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.text('l1HintsTitle'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          for (final hint in diagnosis.l1Hints)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ${l.l1DifficultyName(hint.difficultyKind)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: Text(
                      l.l1Difficulty(hint.difficultyKind, hint.message),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final span in hint.spans)
                          Tooltip(
                            message:
                                '${l.text('l1ListenAgain')} · ${span.label}',
                            child: ActionChip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              avatar: const Icon(Icons.replay, size: 14),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.tertiary.withAlpha(42),
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.tertiary.withAlpha(115),
                              ),
                              label: Text(
                                span.surfaceText.isEmpty
                                    ? span.label
                                    : span.surfaceText,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: onLoopL1Span == null
                                  ? null
                                  : () => onLoopL1Span!(span),
                            ),
                          ),
                        if (onOpenL1Specialty != null)
                          TextButton.icon(
                            onPressed: () => onOpenL1Specialty!(hint),
                            icon: const Icon(
                              Icons.grid_view_outlined,
                              size: 14,
                            ),
                            label: Text(
                              l.text('l1SimilarClips'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
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
              Theme.of(context).colorScheme.error,
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
              Theme.of(context).colorScheme.tertiary,
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
              Theme.of(context).colorScheme.onSurfaceVariant,
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
              Theme.of(context).colorScheme.secondary,
            ),
          if (frame.listeningHotspots.isNotEmpty)
            _hotspotLine(context, frame.listeningHotspots.take(4)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${l.text('rhythmQuality')}: $quality% · '
              '${frame.quality.timingSource.replaceAll('_', ' ')} · '
              'prominence ${_sourceLabel(frame.quality.prominenceSources)} · '
              'boundary ${_sourceLabel(frame.quality.boundarySources)}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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

  Widget _hotspotLine(BuildContext context, Iterable<ListeningHotspot> values) {
    final l = AppLocalizations.of(context);
    final hotspots = values.toList(growable: false);
    if (hotspots.isEmpty) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${l.text('listeningHotspots')}:',
            style: const TextStyle(fontSize: 12),
          ),
          for (final hotspot in hotspots)
            Tooltip(
              message: [
                if (hotspot.hint.isNotEmpty) hotspot.hint,
                '${hotspot.kind.replaceAll('_', ' ')} · '
                    '${(hotspot.confidence * 100).round()}%',
              ].join('\n'),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: color.withAlpha(42),
                side: BorderSide(color: color.withAlpha(115)),
                label: Text(
                  _confidenceLabel(
                    hotspot.label,
                    hotspot.confidence,
                    hotspot.claimStatus,
                  ),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: onLoopHotspot == null
                    ? null
                    : () => onLoopHotspot!(hotspot),
              ),
            ),
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
