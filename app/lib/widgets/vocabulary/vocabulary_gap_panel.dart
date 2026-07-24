import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/production_corpus.dart';
import '../../models/projection_review.dart';
import '../../theme/breakpoints.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../common/capability_viz.dart';
import '../common/listen_empty_state.dart';
import '../common/listen_loading.dart';

/// The gap instrument room — the vocabulary workbench's default right pane.
///
/// gap-(c) ("which words does output lag input on") has two backend sources —
/// cross-channel review candidates and the production gap — that were each
/// buried behind their own unnamed app-bar icon and dialog. They answer the
/// same question, so this panel juxtaposes them as one list. Rendering only:
/// each source keeps its own semantics and query; nothing is merged or
/// recomputed in the frontend. Candidate rows carry an entry-scale capability
/// ring (the #47 graphic language) instead of the raw four-channel strings.
class VocabularyGapPanel extends StatelessWidget {
  const VocabularyGapPanel({
    super.key,
    required this.loading,
    required this.candidates,
    required this.candidatesError,
    required this.production,
    required this.productionError,
    required this.onOpenEntry,
    this.highlightCandidates = false,
    this.scrollController,
  });

  final bool loading;

  /// Cross-channel review candidates (`GET /v1/review/cross-modal`). `null`
  /// while still loading; empty is an honest "no gaps" answer.
  final List<CrossModalReviewCandidateView>? candidates;
  final String? candidatesError;

  /// The production gap review (`/v1/production-gap/*`). `null` while loading.
  final ProductionGapReviewView? production;
  final String? productionError;

  final ValueChanged<String> onOpenEntry;

  /// When arriving from the coach's cross-modal hand-off, the candidates
  /// section is emphasised so the number the coach clicked lands on its list.
  final bool highlightCandidates;

  final ScrollController? scrollController;

  Map<String, String> _candidateAssessments(
    CrossModalReviewCandidateView candidate,
  ) => {
    'listening': candidate.listening,
    'reading': candidate.reading,
    'speaking': candidate.speaking,
    'writing': candidate.writing,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    if (loading) {
      return const Center(child: ListenLoading());
    }

    final candidateList = candidates ?? const <CrossModalReviewCandidateView>[];
    final targets = production?.targets ?? const <ProductionGapTargetView>[];
    final bothEmpty =
        candidatesError == null &&
        productionError == null &&
        candidateList.isEmpty &&
        targets.isEmpty &&
        (production == null || production!.readiness != 'empty');
    if (bothEmpty) {
      return ListenEmptyState(
        icon: Icons.hub_outlined,
        message: l.text('gapPaneEmpty'),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ListenBreakpoints.contentColumnMax,
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(l.text('gapPaneTitle'), style: ListenType.title),
            const SizedBox(height: ListenSpacing.gap4),
            Text(
              l
                  .text('gapPaneSubtitle')
                  .replaceAll('{candidates}', '${candidateList.length}')
                  .replaceAll('{targets}', '${targets.length}'),
              style: ListenType.caption.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: ListenSpacing.gap16),

            // ── Source 1: cross-channel candidates ──
            _SectionHeader(
              label: l.text('gapPaneCandidatesSection'),
              emphasised: highlightCandidates,
            ),
            if (candidatesError != null)
              _InlineNotice(
                text: l
                    .text('crossModalReviewUnavailable')
                    .replaceAll('{error}', candidatesError!),
              )
            else if (candidateList.isEmpty)
              _InlineNotice(text: l.text('crossModalReviewEmpty'))
            else
              for (final candidate in candidateList)
                _CandidateRow(
                  displayForm: candidate.displayForm,
                  reason: candidate.reason,
                  assessments: _candidateAssessments(candidate),
                  onOpen: () => onOpenEntry(candidate.lexicalEntryId),
                ),

            const SizedBox(height: ListenSpacing.gap24),

            // ── Source 2: production gap ──
            _SectionHeader(label: l.text('gapPaneProductionSection')),
            if (productionError != null)
              _InlineNotice(
                text: l
                    .text('productionGapUnavailable')
                    .replaceAll('{error}', productionError!),
              )
            else if (production == null)
              const SizedBox.shrink()
            else if (production!.readiness == 'empty')
              _InlineNotice(text: l.text('productionGapEmpty'))
            else ...[
              if (production!.readiness == 'starter')
                Padding(
                  padding: const EdgeInsets.only(bottom: ListenSpacing.gap8),
                  child: Text(
                    l.text('productionGapStarter'),
                    style: ListenType.caption.copyWith(color: colors.tertiary),
                  ),
                ),
              if (targets.isEmpty)
                _InlineNotice(text: l.text('productionGapNoCandidates'))
              else
                for (final target in targets)
                  _ProductionRow(
                    target: target,
                    onOpen: () => onOpenEntry(target.lexicalEntryId),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.emphasised = false});

  final String label;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: ListenSpacing.gap8),
      child: Text(
        label,
        style: ListenType.caption.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: emphasised ? colors.secondary : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: ListenSpacing.gap8),
      child: Text(
        text,
        style: ListenType.body.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.displayForm,
    required this.reason,
    required this.assessments,
    required this.onOpen,
  });

  final String displayForm;
  final String reason;
  final Map<String, String> assessments;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ListenSpacing.gap4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CapabilityRing(assessments: assessments, size: 22, withTooltip: true),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayForm, style: ListenType.body),
                if (reason.trim().isNotEmpty)
                  Text(
                    reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ListenType.caption.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ListenSpacing.gap8),
          TextButton(
            onPressed: onOpen,
            child: Text(l.text('gapPaneViewEntry')),
          ),
        ],
      ),
    );
  }
}

class _ProductionRow extends StatelessWidget {
  const _ProductionRow({required this.target, required this.onOpen});

  final ProductionGapTargetView target;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: ListenRadii.controlBorder),
      title: Text(target.displayForm, style: ListenType.body),
      subtitle: Text(
        l
            .text('productionGapTargetReason')
            .replaceAll(
              '{frequency}',
              target.frequencyRank == null
                  ? l.text('productionGapFrequencyUnavailable')
                  : 'BNC #${target.frequencyRank}',
            )
            .replaceAll('{evidence}', '${target.evidenceStrength}')
            .replaceAll('{recency}', '${target.recencyBand}'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: onOpen,
        child: Text(l.text('productionGapOpenTarget')),
      ),
    );
  }
}
