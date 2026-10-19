import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

class DiagnosisCard extends StatelessWidget {
  const DiagnosisCard({
    super.key,
    required this.diagnosis,
    this.pronunciation,
    this.ruleHintsLevel = 'likely',
    this.pronunciationProviders = const [],
    this.timingQuality,
    this.phoneticAnalysis,
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
  final PhoneticAnalysis? phoneticAnalysis;
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
    // A column, not a scroll view. This card opens inside the sentence it
    // describes, as one item of the transcript's list, where height is
    // unbounded — a viewport there fails to lay out, and a render box whose
    // layout failed has no size, which turns every later pointer into a hit
    // test error and takes the card's own controls with it. Scrolling is the
    // transcript's job; this is content.
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.text('currentSentenceDiagnosis'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: ListenSpacing.gap8),
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
                            style: ListenType.body.copyWith(
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
                                    size: ListenIconSize.control,
                                  ),
                                  label: Text(
                                    l.text('openListeningDictionary'),
                                  ),
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
                  style: ListenType.body.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (diagnosis.l1Hints.isNotEmpty) _l1Section(context),
            const SizedBox(height: ListenSpacing.gap8),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
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
                        if (timingQuality != null && timingQuality!.isNotEmpty)
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
                        if (phoneticAnalysis != null) ...[
                          _section(
                            l.text('audioDetectionExperimental'),
                            '${phoneticAnalysis!.providerId} · '
                            '${phoneticAnalysis!.modelRevision} · '
                            '${phoneticAnalysis!.phoneSet}',
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
                                padding: const EdgeInsets.only(
                                  top: ListenSpacing.gap4,
                                ),
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
      ),
    );
  }

  Widget _l1Section(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      key: const Key('diagnosis-l1-section'),
      padding: const EdgeInsets.only(top: ListenSpacing.gap8),
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
                      style: ListenType.body,
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
                              avatar: const Icon(
                                Icons.replay,
                                size: ListenIconSize.control,
                              ),
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
                                style: ListenType.body,
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
                              size: ListenIconSize.control,
                            ),
                            label: Text(
                              l.text('l1SimilarClips'),
                              style: ListenType.body,
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
    padding: const EdgeInsets.only(top: ListenSpacing.gap8),
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
