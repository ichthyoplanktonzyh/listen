import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/review_deck_controller.dart';
import '../localization.dart';
import '../models/review_deck.dart';
import '../state/builder.dart';
import '../theme/breakpoints.dart';
import '../theme/icon_size.dart';
import '../theme/listen_theme.dart';
import '../theme/spacing.dart';
import '../widgets/common/listen_error_state.dart';
import '../widgets/common/listen_loading.dart';

/// Listening review counts, custom study and the daily budget.
class ReviewDeckHomeScreen extends StatefulWidget {
  const ReviewDeckHomeScreen({
    super.key,
    required this.controller,
    required this.onStartSession,
    required this.onStartCustomStudy,
  });

  final ReviewDeckController controller;
  final VoidCallback onStartSession;
  final void Function(CustomStudyRequest request) onStartCustomStudy;

  @override
  State<ReviewDeckHomeScreen> createState() => _ReviewDeckHomeScreenState();
}

class _ReviewDeckHomeScreenState extends State<ReviewDeckHomeScreen> {
  ReviewDeckController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.text('reviewTitle'))),
      body: StoreBuilder<ReviewDeckState, ReviewDeckState>(
        store: controller.store,
        select: (state) => state,
        builder: (context, state) {
          final overview = state.overview;
          if (state.busy && overview == null) {
            return const Center(child: ListenLoading());
          }
          if (overview == null) {
            return Center(
              child: ListenErrorState(
                message: state.error ?? l.text('reviewDeckLoadFailed'),
                action: TextButton(
                  onPressed: () => unawaited(controller.load()),
                  child: Text(l.text('retry')),
                ),
              ),
            );
          }
          return Center(
            child: SingleChildScrollView(
              padding: ListenPadding.pageCompact,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ListenBreakpoints.formColumnMax,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TodayHeader(
                      overview: overview,
                      onStart: widget.onStartSession,
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: ListenSpacing.gap16),
                      ListenErrorNotice(message: state.error!),
                    ],
                    const SizedBox(height: ListenSpacing.gap32),
                    _SectionTitle(l.text('reviewNativeDeck')),
                    const SizedBox(height: ListenSpacing.gap8),
                    _NativeDeckRow(counts: overview.nativeCounts),
                    const SizedBox(height: ListenSpacing.gap32),
                    _SectionTitle(l.text('reviewCustomStudy')),
                    const SizedBox(height: ListenSpacing.gap8),
                    _CustomStudyChips(
                      channels: overview.channels,
                      onStart: widget.onStartCustomStudy,
                    ),
                    const SizedBox(height: ListenSpacing.gap32),
                    _DailyLimitsCard(
                      limits: overview.limitStatus.limits,
                      saving: state.savingLimits,
                      onSave: (limits) =>
                          unawaited(controller.updateDailyLimits(limits)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);
}

/// The one number the page exists to answer, plus the budget that shaped it.
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.overview, required this.onStart});

  final ReviewDeckOverview overview;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final status = overview.limitStatus;
    final total = overview.dueTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$total',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: ListenSpacing.gap4),
        Text(
          l.text('reviewDueToday'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: ListenSpacing.gap4),
        Text(
          l
              .text('reviewBudgetSpent')
              .replaceAll('{new}', '${status.newCompleted}')
              .replaceAll('{newLimit}', '${status.limits.newCards}')
              .replaceAll('{reviews}', '${status.reviewsCompleted}')
              .replaceAll('{reviewLimit}', '${status.limits.reviews}'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: ListenSpacing.gap16),
        FilledButton(
          onPressed: total == 0 ? null : onStart,
          child: Text(
            total == 0
                ? l.text(
                    status.anyLimitReached
                        ? 'reviewDailyLimitReached'
                        : 'reviewNoDueCards',
                  )
                : l.text('reviewStartSession'),
          ),
        ),
      ],
    );
  }
}

/// The three schedule counts in the colours used for the same states in a
/// listening session.
class _CountsRow extends StatelessWidget {
  const _CountsRow({required this.counts});

  final ReviewStateCounts counts;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget count(int value, Color color, String tooltipKey) => Tooltip(
      message: l.text(tooltipKey),
      child: Text(
        '$value',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        count(counts.newCards, ListenColors.moonBlue, 'reviewNewCard'),
        const SizedBox(width: ListenSpacing.gap8),
        count(
          counts.learning,
          ListenColors.learningNeedsReview,
          'reviewStateLearning',
        ),
        const SizedBox(width: ListenSpacing.gap8),
        count(counts.due, ListenColors.learningRecognized, 'reviewStateReview'),
      ],
    );
  }
}

/// Every native card as one row.
///
/// This used to be four rows, one per capability channel. They were dropped
/// because the split changed nothing a learner could do: the scheduled queue
/// is global (`/v1/review/queue` takes no channel), so all four rows led to
/// the same session, and the only per-channel action available was custom
/// study — which now lives in the custom-study section where it belongs. The
/// channel is a way to *pick extra practice*, not the shape of the day's work.
class _NativeDeckRow extends StatelessWidget {
  const _NativeDeckRow({required this.counts});

  final ReviewStateCounts counts;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: ListenPadding.row,
      child: Row(
        children: [
          Icon(
            Icons.hearing_outlined,
            size: ListenIconSize.control,
            color: colors.primary,
          ),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(child: Text(l.text('reviewNativeDeckName'))),
          _CountsRow(counts: counts),
        ],
      ),
    );
  }
}

class _CustomStudyChips extends StatelessWidget {
  const _CustomStudyChips({required this.channels, required this.onStart});

  /// Per-channel counts. Not rendered as numbers here — they decide which
  /// channel is worth offering, so a channel with nothing in it is offered as
  /// disabled rather than as a button that returns an empty round.
  final List<ReviewChannelDeck> channels;
  final void Function(CustomStudyRequest request) onStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: ListenSpacing.gap8,
          runSpacing: ListenSpacing.gap8,
          children: [
            for (final option
                in <({String labelKey, CustomStudyRequest request})>[
                  (
                    labelKey: 'reviewCustomStudyMoreNew',
                    request: CustomStudyRequest(
                      kind: CustomStudyKind.moreNew,
                      limit: 10,
                    ),
                  ),
                  (
                    labelKey: 'reviewCustomStudyReviewAhead',
                    request: CustomStudyRequest(
                      kind: CustomStudyKind.reviewAhead,
                      limit: 10,
                    ),
                  ),
                  (
                    labelKey: 'reviewCustomStudyForgotten',
                    request: CustomStudyRequest(
                      kind: CustomStudyKind.forgotten,
                      minimumLapses: 1,
                      limit: 10,
                    ),
                  ),
                ])
              OutlinedButton(
                onPressed: () => onStart(option.request),
                child: Text(l.text(option.labelKey)),
              ),
          ],
        ),
        if (channels.isNotEmpty) ...[
          const SizedBox(height: ListenSpacing.gap12),
          Text(
            l.text('reviewPractiseOneChannel'),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: ListenSpacing.gap8),
          Wrap(
            spacing: ListenSpacing.gap8,
            runSpacing: ListenSpacing.gap8,
            children: [
              for (final deck in channels)
                OutlinedButton(
                  onPressed: deck.counts.total == 0
                      ? null
                      : () => onStart(
                          CustomStudyRequest(
                            kind: CustomStudyKind.channel,
                            channel: deck.channel,
                            limit: 10,
                          ),
                        ),
                  child: Text(l.text('capabilityListening')),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DailyLimitsCard extends StatefulWidget {
  const _DailyLimitsCard({
    required this.limits,
    required this.saving,
    required this.onSave,
  });

  final ReviewDailyLimits limits;
  final bool saving;
  final void Function(ReviewDailyLimits limits) onSave;

  @override
  State<_DailyLimitsCard> createState() => _DailyLimitsCardState();
}

class _DailyLimitsCardState extends State<_DailyLimitsCard> {
  late final _newCards = TextEditingController(
    text: '${widget.limits.newCards}',
  );
  late final _reviews = TextEditingController(text: '${widget.limits.reviews}');

  @override
  void dispose() {
    _newCards.dispose();
    _reviews.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.text('reviewDailyLimits'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: ListenSpacing.gap12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCards,
                    enabled: !widget.saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l.text('reviewLimitNewCards'),
                    ),
                  ),
                ),
                const SizedBox(width: ListenSpacing.gap12),
                Expanded(
                  child: TextField(
                    controller: _reviews,
                    enabled: !widget.saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l.text('reviewLimitReviews'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ListenSpacing.gap12),
            FilledButton(
              onPressed: widget.saving ? null : _save,
              child: Text(l.text('save')),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final newCards = int.tryParse(_newCards.text.trim());
    final reviews = int.tryParse(_reviews.text.trim());
    if (newCards == null || reviews == null) return;
    widget.onSave(ReviewDailyLimits(newCards: newCards, reviews: reviews));
  }
}
