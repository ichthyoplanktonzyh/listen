import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../models/practice.dart';
import '../../models/projection_review.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_loading.dart';

/// Listening-only, explicitly confirmable status suggestions.
class ListeningStatusSuggestions extends StatelessWidget {
  const ListeningStatusSuggestions({
    super.key,
    required this.suggestions,
    required this.suggestionsLoading,
    required this.suggestionsFailure,
    required this.proposals,
    required this.proposalsLoading,
    required this.proposalsFailure,
    required this.onConfirmSuggestion,
    required this.onRejectSuggestion,
    required this.onDecideProposal,
  });

  final List<UpgradeSuggestion> suggestions;
  final bool suggestionsLoading;
  final ApiFailure? suggestionsFailure;
  final List<ProjectionProposalView> proposals;
  final bool proposalsLoading;
  final ApiFailure? proposalsFailure;
  final Future<ApiFailure?> Function(UpgradeSuggestion) onConfirmSuggestion;
  final Future<ApiFailure?> Function(UpgradeSuggestion) onRejectSuggestion;
  final Future<ApiFailure?> Function(
    ProjectionProposalView proposal,
    String decision,
  )
  onDecideProposal;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final listeningSuggestions = suggestions
        .where((suggestion) => suggestion.isListening)
        .toList(growable: false);
    final listeningProposals = proposals
        .where((proposal) => proposal.isListening)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.text('dictionaryUpgradeSuggestions'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: ListenSpacing.gap8),
        if (suggestionsFailure != null)
          ApiFailureDisclosure(failure: suggestionsFailure!)
        else if (suggestionsLoading)
          const ListenLoading.inline()
        else if (listeningSuggestions.isEmpty)
          Text(
            l.text('dictionaryNoUpgradeSuggestions'),
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final suggestion in listeningSuggestions)
            _UpgradeSuggestionCard(
              suggestion: suggestion,
              onConfirm: () => onConfirmSuggestion(suggestion),
              onReject: () => onRejectSuggestion(suggestion),
            ),
        const SizedBox(height: ListenSpacing.gap16),
        Text(
          l.text('dictionaryListeningProposals'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: ListenSpacing.gap8),
        if (proposalsFailure != null)
          ApiFailureDisclosure(failure: proposalsFailure!)
        else if (proposalsLoading)
          const ListenLoading.inline()
        else if (listeningProposals.isEmpty)
          Text(
            l.text('dictionaryNoListeningProposals'),
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final proposal in listeningProposals)
            _ProjectionProposalCard(
              proposal: proposal,
              onConfirm: proposal.isPending
                  ? () => onDecideProposal(proposal, 'confirm')
                  : null,
              onReject: proposal.isPending
                  ? () => onDecideProposal(proposal, 'reject')
                  : null,
            ),
      ],
    );
  }
}

class _UpgradeSuggestionCard extends StatefulWidget {
  const _UpgradeSuggestionCard({
    required this.suggestion,
    required this.onConfirm,
    required this.onReject,
  });

  final UpgradeSuggestion suggestion;
  final Future<ApiFailure?> Function() onConfirm;
  final Future<ApiFailure?> Function() onReject;

  @override
  State<_UpgradeSuggestionCard> createState() => _UpgradeSuggestionCardState();
}

class _UpgradeSuggestionCardState extends State<_UpgradeSuggestionCard> {
  bool _busy = false;
  ApiFailure? _failure;

  Future<void> _resolve(Future<ApiFailure?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final suggestion = widget.suggestion;
    final previous = suggestion.previousAssessment ?? suggestion.previousStatus;
    final proposed =
        suggestion.suggestedAssessment ?? suggestion.suggestedStatus;
    return Card(
      child: Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l
                  .text('dictionaryUpgradeSuggestion')
                  .replaceAll('{count}', '${suggestion.evidenceContextCount}'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: ListenSpacing.gap4),
            Text(
              '${l.text(previous ?? 'unassessed')} → ${l.text(proposed ?? 'unassessed')}',
            ),
            const SizedBox(height: ListenSpacing.gap8),
            Wrap(
              spacing: ListenSpacing.gap8,
              children: [
                OutlinedButton(
                  key: Key('upgrade-reject-${suggestion.id}'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_resolve(widget.onReject)),
                  child: Text(l.text('deferUpgrade')),
                ),
                FilledButton.tonal(
                  key: Key('upgrade-confirm-${suggestion.id}'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_resolve(widget.onConfirm)),
                  child: Text(l.text('confirmUpgrade')),
                ),
              ],
            ),
            if (_busy) const ListenLoading.inline(),
            if (_failure != null) ApiFailureDisclosure(failure: _failure!),
          ],
        ),
      ),
    );
  }
}

class _ProjectionProposalCard extends StatefulWidget {
  const _ProjectionProposalCard({
    required this.proposal,
    required this.onConfirm,
    required this.onReject,
  });

  final ProjectionProposalView proposal;
  final Future<ApiFailure?> Function()? onConfirm;
  final Future<ApiFailure?> Function()? onReject;

  @override
  State<_ProjectionProposalCard> createState() =>
      _ProjectionProposalCardState();
}

class _ProjectionProposalCardState extends State<_ProjectionProposalCard> {
  bool _busy = false;
  ApiFailure? _failure;

  Future<void> _decide(Future<ApiFailure?> Function()? action) async {
    if (_busy || action == null) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final proposal = widget.proposal;
    return Card(
      child: Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.hearing_outlined,
                  size: ListenIconSize.control,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Text(
                    l
                        .text('dictionaryProjectionProposal')
                        .replaceAll(
                          '{status}',
                          l.text(proposal.proposedConclusion),
                        ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(l.text('projection_${proposal.status}')),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap4),
            Text(proposal.rationale),
            const SizedBox(height: ListenSpacing.gap4),
            Text(
              l
                  .text('dictionaryProjectionEvidenceCount')
                  .replaceAll('{count}', '${proposal.evidence.length}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (proposal.isPending)
              Wrap(
                spacing: ListenSpacing.gap8,
                children: [
                  OutlinedButton(
                    key: Key('projection-reject-${proposal.id}'),
                    onPressed: _busy
                        ? null
                        : () => unawaited(_decide(widget.onReject)),
                    child: Text(l.text('rejectProposal')),
                  ),
                  FilledButton.tonal(
                    key: Key('projection-confirm-${proposal.id}'),
                    onPressed: _busy
                        ? null
                        : () => unawaited(_decide(widget.onConfirm)),
                    child: Text(l.text('confirmProposal')),
                  ),
                ],
              ),
            if (_busy) const ListenLoading.inline(),
            if (_failure != null) ApiFailureDisclosure(failure: _failure!),
          ],
        ),
      ),
    );
  }
}
