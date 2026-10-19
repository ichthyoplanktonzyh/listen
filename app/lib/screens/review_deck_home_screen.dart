import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/review_deck_controller.dart';
import '../localization.dart';
import '../models/review_deck.dart';
import '../services/anki_package_file_service.dart';
import '../state/builder.dart';
import '../theme/breakpoints.dart';
import '../theme/icon_size.dart';
import '../theme/listen_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/common/listen_error_state.dart';
import '../widgets/common/listen_loading.dart';

/// The review home: what is waiting, in which decks, under what budget, and
/// the ways to practise beyond the schedule.
///
/// It deliberately does **not** reuse `CapabilityCompass`. The compass's rings
/// mean acquired / not acquired / unassessed *capability*; a deck's counts mean
/// new / learning / due *cards*. Pouring the second set into the first would
/// paint a due count in the "acquired" colour and make the ring state something
/// untrue — the redesign asked for the compass here, but not at that price.
class ReviewDeckHomeScreen extends StatefulWidget {
  const ReviewDeckHomeScreen({
    super.key,
    required this.controller,
    required this.fileService,
    required this.onStartSession,
    required this.onStartCustomStudy,
  });

  final ReviewDeckController controller;
  final AnkiPackageFileService fileService;

  /// Starts the day's scheduled queue.
  final VoidCallback onStartSession;

  /// Starts a one-shot custom-study round.
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
      appBar: AppBar(
        title: Text(l.text('reviewTitle')),
        actions: [
          IconButton(
            onPressed: () => unawaited(_import()),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: l.text('reviewImportAnkiDeck'),
          ),
          IconButton(
            onPressed: () => unawaited(_export()),
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: l.text('reviewExportAnkiDeck'),
          ),
        ],
      ),
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
                    if (state.importSummary != null) ...[
                      const SizedBox(height: ListenSpacing.gap16),
                      _ImportReport(
                        summary: state.importSummary!,
                        onDismiss: controller.dismissReports,
                      ),
                    ],
                    if (state.exportSummary != null) ...[
                      const SizedBox(height: ListenSpacing.gap16),
                      _ExportReport(
                        summary: state.exportSummary!,
                        onDismiss: controller.dismissReports,
                      ),
                    ],
                    const SizedBox(height: ListenSpacing.gap32),
                    _SectionTitle(l.text('reviewNativeDeck')),
                    const SizedBox(height: ListenSpacing.gap8),
                    _NativeDeckRow(counts: overview.nativeCounts),
                    if (overview.importedDecks.isNotEmpty) ...[
                      const SizedBox(height: ListenSpacing.gap32),
                      _SectionTitle(l.text('reviewImportedDecks')),
                      const SizedBox(height: ListenSpacing.gap8),
                      for (final deck in _sortedImported(
                        overview.importedDecks,
                      ))
                        _ImportedDeckRow(
                          deck: deck,
                          depth: _depthOf(deck, overview.importedDecks),
                        ),
                    ],
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

  /// Anki deck names are a `::`-separated tree. Sorting by name keeps a child
  /// directly under its parent, which is what makes the indent readable.
  static List<ReviewImportedDeck> _sortedImported(
    List<ReviewImportedDeck> decks,
  ) => [...decks]..sort((a, b) => a.name.compareTo(b.name));

  /// Nesting depth, measured by how many ancestors the deck actually has in
  /// this response rather than by counting `::` in a name — a deck whose
  /// parent was not imported is a root here, and drawing it indented under
  /// nothing would invent a tree.
  static int _depthOf(ReviewImportedDeck deck, List<ReviewImportedDeck> all) {
    final byId = {for (final value in all) value.deckId: value};
    var depth = 0;
    var parentId = deck.parentDeckId;
    while (parentId != null && byId.containsKey(parentId) && depth < 8) {
      depth++;
      parentId = byId[parentId]!.parentDeckId;
    }
    return depth;
  }

  Future<void> _import() async {
    final path = await widget.fileService.pickPackageToImport();
    if (path == null) return;
    final mediaDirectory = await widget.fileService.mediaDirectoryFor(path);
    await controller.importAnkiPackage(
      packagePath: path,
      mediaDirectory: mediaDirectory,
    );
  }

  Future<void> _export() async {
    // The disclosure comes before the file dialog: the learner decides whether
    // to export at all *knowing what will be lost*, rather than after having
    // already chosen where to put it.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _ExportDisclosureDialog(),
    );
    if (confirmed != true) return;
    final path = await widget.fileService.pickExportDestination();
    if (path == null) return;
    await controller.exportAnkiPackage(
      AnkiPackageExportRequest(packagePath: path),
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

/// Anki's three numbers, in the three colours the session already uses for the
/// same three states.
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

class _ImportedDeckRow extends StatelessWidget {
  const _ImportedDeckRow({required this.deck, required this.depth});

  final ReviewImportedDeck deck;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // The leaf name only: the tree is drawn by the indent, so repeating the
    // full `Parent::Child` path on every row would say it twice.
    final name = deck.name.split('::').last;
    return Padding(
      padding: ListenPadding.row.add(
        EdgeInsets.only(left: depth * ListenSpacing.gap16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: ListenIconSize.inline,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(child: Text(name)),
          _CountsRow(counts: deck.counts),
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

  static String _channelLabelKey(String channel) => switch (channel) {
    'speaking' => 'capabilitySpeaking',
    'reading' => 'capabilityReading',
    'writing' => 'capabilityWriting',
    _ => 'capabilityListening',
  };

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
                  child: Text(l.text(_channelLabelKey(deck.channel))),
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

/// What an `.apkg` export cannot carry, said before the learner commits to it.
class _ExportDisclosureDialog extends StatelessWidget {
  const _ExportDisclosureDialog();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.text('reviewExportAnkiDeck')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ListenBreakpoints.formColumnMax,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.text('reviewExportDisclosureIntro')),
            const SizedBox(height: ListenSpacing.gap12),
            for (final key in const [
              'reviewExportLossVideo',
              'reviewExportLossShadowing',
              'reviewExportLossSourceJump',
              'reviewExportLossCapability',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: ListenSpacing.gap4),
                child: Text('· ${l.text(key)}'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.text('reviewExportConfirm')),
        ),
      ],
    );
  }
}

class _ImportReport extends StatelessWidget {
  const _ImportReport({required this.summary, required this.onDismiss});

  final AnkiPackageImportSummary summary;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _ReportCard(
      title: l.text('reviewImportReport'),
      lines: [
        l
            .text('reviewImportCounts')
            .replaceAll('{imported}', '${summary.importedCards}')
            .replaceAll('{updated}', '${summary.updatedCards}')
            .replaceAll('{skipped}', '${summary.skippedCards}'),
        l
            .text('reviewImportDetails')
            .replaceAll('{decks}', '${summary.importedDecks}')
            .replaceAll('{revlog}', '${summary.importedRevlogEntries}')
            .replaceAll('{media}', '${summary.importedMediaFiles}'),
        ...summary.warnings,
      ],
      onDismiss: onDismiss,
    );
  }
}

class _ExportReport extends StatelessWidget {
  const _ExportReport({required this.summary, required this.onDismiss});

  final AnkiPackageExportSummary summary;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fidelity = summary.fidelity;
    return _ReportCard(
      title: l.text('reviewExportReport'),
      lines: [
        l
            .text('reviewExportCounts')
            .replaceAll('{cards}', '${summary.exportedCards}')
            .replaceAll('{revlog}', '${summary.exportedRevlogEntries}')
            .replaceAll('{media}', '${summary.exportedMediaFiles}'),
        // The measured loss, not the generic warning the dialog showed.
        if (fidelity.videoSlicesRenderedAsAudio > 0)
          l
              .text('reviewExportVideoRendered')
              .replaceAll('{count}', '${fidelity.videoSlicesRenderedAsAudio}'),
        if (fidelity.mediaRenderFailures > 0)
          l
              .text('reviewExportMediaFailed')
              .replaceAll('{count}', '${fidelity.mediaRenderFailures}'),
        if (fidelity.omittedCapabilities.isNotEmpty)
          l
              .text('reviewExportOmitted')
              .replaceAll('{items}', fidelity.omittedCapabilities.join(', ')),
        ...summary.warnings,
      ],
      onDismiss: onDismiss,
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.title,
    required this.lines,
    required this.onDismiss,
  });

  final String title;
  final List<String> lines;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: ListenPadding.card,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: ListenRadii.surfaceBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: ListenSpacing.gap8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: ListenSpacing.gap4),
              child: Text(line),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onDismiss,
              child: Text(l.text('dismiss')),
            ),
          ),
        ],
      ),
    );
  }
}
