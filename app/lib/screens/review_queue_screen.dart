import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/occurrence_media_resolver.dart';
import '../controllers/review_controller.dart';
import '../controllers/slice_player_controller.dart';
import '../localization.dart';
import '../models/practice.dart';
import '../models/review_deck.dart';
import '../state/builder.dart';
import '../theme/breakpoints.dart';
import '../theme/icon_size.dart';
import '../theme/listen_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/common/listen_error_state.dart';
import '../widgets/common/listen_loading.dart';

class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({
    super.key,
    required this.controller,
    required this.resolver,
    required this.slicePlayer,
    required this.onStartShadowing,
    required this.onStartDelayedRetelling,
    this.onPauseBackgroundPlayback,
    this.autoLoad = true,
  });

  /// Whether the screen loads a queue on mount. False when the caller already
  /// started the round — a custom-study queue would otherwise be replaced by
  /// the day's schedule the moment the screen appeared.
  final bool autoLoad;

  final Future<void> Function(ReviewQueueEntry entry) onStartShadowing;
  final Future<void> Function(ReviewQueueEntry entry) onStartDelayedRetelling;

  /// Silences the primary player so a review clip owns audio focus alone. The
  /// clip runs on a second decoder ([SlicePlayerController]) that is otherwise
  /// completely independent of the main player (S5 · R1).
  final Future<void> Function()? onPauseBackgroundPlayback;

  final ReviewController controller;

  /// Resolves review occurrences without exposing the repository to the View.
  final OccurrenceMediaResolver resolver;
  final SlicePlayerController slicePlayer;

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  ReviewController get controller => widget.controller;

  /// The review card plays its source clip on its own decoder, so a card is
  /// reviewable even when no media (or a different one) is loaded in the main
  /// player — the fix for the whole-queue "clip unavailable" state (S5 · R1).
  SlicePlayerController get _slicePlayer => widget.slicePlayer;

  OccurrenceMediaResolver get _resolver => widget.resolver;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) unawaited(controller.load());
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.text('reviewTitle')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: StoreBuilder<ReviewState, ReviewState>(
            store: controller.store,
            select: (state) => state,
            builder: (context, state) {
              final total = state.queue.length;
              // Indeterminate only while the first load is still in flight;
              // once the queue is known the bar reports real progress.
              final value = state.busy && total == 0
                  ? null
                  : total == 0
                  ? 0.0
                  : state.index / total;
              return LinearProgressIndicator(value: value, minHeight: 3);
            },
          ),
        ),
        actions: [
          StoreBuilder<ReviewState, ReviewState>(
            store: controller.store,
            select: (state) => state,
            builder: (context, state) {
              final total = state.queue.length;
              // R4: while reviewing, "card N of M" places the learner in the
              // round; on the finished/empty screen the remaining count is the
              // honest read instead.
              final label = state.current != null
                  ? l
                        .text('reviewRoundProgress')
                        .replaceAll('{index}', '${state.index + 1}')
                        .replaceAll('{total}', '$total')
                  : l
                        .text('reviewDueCount')
                        .replaceAll('{count}', '${state.remaining}');
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ListenSpacing.gap16,
                ),
                child: Center(child: Text(label)),
              );
            },
          ),
        ],
      ),
      body: StoreBuilder<ReviewState, ReviewState>(
        store: controller.store,
        select: (state) => state,
        builder: (context, state) {
          if (state.busy && state.queue.isEmpty) {
            return const Center(child: ListenLoading());
          }
          if (state.current == null) {
            return _Finished(
              state: state,
              onRetry: controller.load,
              onResolve: (id, confirm) =>
                  controller.resolveUpgradeSuggestion(id, confirm: confirm),
            );
          }
          final entry = state.current!;
          final customStudy = state.customStudy;
          if (customStudy != null) {
            // A custom-study round is not the day's schedule, and whether it
            // moves the real one is the backend's answer, not an assumption.
            return Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: ListenPadding.card,
                    child: Text(
                      l.text(
                        state.advancesNormalSchedule == true
                            ? 'reviewCustomStudyAdvancesSchedule'
                            : 'reviewCustomStudyExtraPractice',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
                Expanded(child: _card(context, state, entry)),
              ],
            );
          }
          return _card(context, state, entry);
        },
      ),
    );
  }

  Widget _card(
    BuildContext context,
    ReviewState state,
    ReviewQueueEntry entry,
  ) {
    return _ReviewCard(
      key: ValueKey(entry.item.id),
      entry: entry,
      clipAvailable: _clipAvailable(entry),
      shadowAvailable: _canShadow(entry),
      revealed: state.revealed,
      busy: state.busy,
      previews: state.previews,
      error: state.error,
      slicePlayer: _slicePlayer,
      onPlayClip: () => unawaited(_playClip(entry)),
      onShadowing: () async {
        await _slicePlayer.close();
        if (!context.mounted) return;
        // As a shell route there is nothing to pop; only pushed
        // contexts (deep links, tests) dismiss themselves.
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        if (entry.card.kind == 'delayed_retelling') {
          await widget.onStartDelayedRetelling(entry);
        } else {
          await widget.onStartShadowing(entry);
        }
      },
      onReveal: controller.reveal,
      onRate: (rating) async {
        await _slicePlayer.close();
        return controller.rate(rating);
      },
    );
  }

  /// A clip can be *attempted* whenever the source names a media and a bounded
  /// range; whether the local file is actually reachable is resolved on tap
  /// and reported in place, never guessed up front against the main player.
  bool _clipAvailable(ReviewQueueEntry entry) {
    final start = entry.playbackStartMs;
    final end = entry.playbackEndMs;
    return entry.item.source.mediaId != null &&
        start != null &&
        end != null &&
        end > start;
  }

  bool _canShadow(ReviewQueueEntry entry) =>
      entry.item.source.mediaId != null &&
      entry.playbackStartMs != null &&
      entry.playbackEndMs != null;

  Future<void> _playClip(ReviewQueueEntry entry) async {
    final source = entry.item.source;
    final mediaId = source.mediaId;
    final startMs = entry.playbackStartMs;
    final endMs = entry.playbackEndMs;
    if (mediaId == null ||
        startMs == null ||
        endMs == null ||
        endMs <= startMs) {
      return;
    }
    // The source snapshot needs the media fingerprint for the resolver to
    // locate the local file. Read it through the resolver's own `readMedia`
    // so production and tests share a single media source.
    final fingerprint = await _resolver.mediaFingerprint(mediaId);
    if (!mounted) return;
    final occurrence = currentMediaSliceOccurrence(
      mediaId: mediaId,
      trackId: source.trackId,
      sentenceId: source.id ?? entry.item.id,
      textSnapshot: entry.card.answer,
      startMs: startMs,
      endMs: endMs,
      mediaFingerprint: fingerprint,
    );
    await widget.onPauseBackgroundPlayback?.call();
    final resolution = await _resolver.resolve(
      occurrence,
      currentMediaFingerprint: null,
      currentMediaPath: null,
      filterMediaExtensions: true,
    );
    if (!mounted) return;
    if (resolution is UnresolvedOccurrenceMedia) {
      await _slicePlayer.showError(resolution.message, occurrence: occurrence);
      return;
    }
    await _slicePlayer.open(
      path: (resolution as ResolvedOccurrenceMedia).path,
      occurrence: occurrence,
    );
    // Review is audio-first; the clip's video track stays hidden.
    _slicePlayer.setShowVideo(false);
  }
}

class _ReviewCard extends StatefulWidget {
  const _ReviewCard({
    super.key,
    required this.entry,
    required this.clipAvailable,
    required this.shadowAvailable,
    required this.revealed,
    required this.busy,
    required this.previews,
    required this.slicePlayer,
    required this.onPlayClip,
    required this.onShadowing,
    required this.onReveal,
    required this.onRate,
    this.error,
  });

  final ReviewQueueEntry entry;
  final bool clipAvailable;
  final bool shadowAvailable;
  final bool revealed;
  final bool busy;
  final List<ReviewIntervalPreview> previews;
  final String? error;
  final SlicePlayerController slicePlayer;
  final VoidCallback onPlayClip;
  final Future<void> Function() onShadowing;
  final VoidCallback onReveal;
  final Future<bool> Function(String rating) onRate;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  final _clozeController = TextEditingController();

  AppLocalizations get l => AppLocalizations.of(context);
  String? _presenceChoice;

  @override
  void dispose() {
    _clozeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.entry.card;
    return Center(
      child: SingleChildScrollView(
        padding: ListenPadding.pageCompact,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.cardColumnMax,
          ),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CardHead(entry: widget.entry),
                  const SizedBox(height: ListenSpacing.gap12),
                  Text(
                    _instruction(l, card.kind),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: ListenSpacing.gap32),
                  // #73: an imported Anki card carries no listening evidence of
                  // its own. The backend says so in `has_listening_enhancements`
                  // and the card obeys: no slice player, no shadowing, and the
                  // head says where the card came from — rather than offering
                  // affordances that would silently do nothing.
                  if (widget.entry.origin.hasListeningEnhancements) ...[
                    _PlaybackControls(
                      slicePlayer: widget.slicePlayer,
                      clipAvailable: widget.clipAvailable,
                      onPlayClip: widget.onPlayClip,
                    ),
                    const SizedBox(height: ListenSpacing.gap8),
                    OutlinedButton.icon(
                      onPressed: widget.shadowAvailable && !widget.busy
                          ? () => unawaited(widget.onShadowing())
                          : null,
                      icon: Icon(
                        card.kind == 'delayed_retelling'
                            ? Icons.record_voice_over_outlined
                            : Icons.mic_none,
                      ),
                      label: Text(
                        card.kind == 'delayed_retelling'
                            ? l.text('reviewStartDelayedRetelling')
                            : l.text('reviewShadowClip'),
                      ),
                    ),
                  ],
                  const SizedBox(height: ListenSpacing.gap24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: widget.revealed
                        ? _revealedContent(context)
                        : _promptContent(context),
                  ),
                  if (widget.error != null) ...[
                    const SizedBox(height: ListenSpacing.gap16),
                    ListenErrorNotice(message: widget.error!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _promptContent(BuildContext context) {
    final card = widget.entry.card;
    return switch (card.kind) {
      'chunk_cloze' => Column(
        key: const ValueKey('chunk-cloze-prompt'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            card.cue ?? '____',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: ListenSpacing.gap16),
          TextField(
            controller: _clozeController,
            enabled: !widget.busy,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l.text('reviewClozeFieldLabel'),
            ),
            onSubmitted: (_) => widget.busy ? null : widget.onReveal(),
          ),
          const SizedBox(height: ListenSpacing.gap12),
          OutlinedButton(
            onPressed: widget.busy ? null : widget.onReveal,
            child: Text(l.text('reviewCheckAnswer')),
          ),
        ],
      ),
      'phrase_presence' => Column(
        key: const ValueKey('phrase-presence-prompt'),
        children: [
          Text(
            l.text('reviewTargetPhrase'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: ListenSpacing.gap8),
          Text(
            card.cue ?? card.target ?? '',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: ListenSpacing.gap16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: widget.busy
                      ? null
                      : () => _choosePresence('present'),
                  child: Text(l.text('reviewPresencePresent')),
                ),
              ),
              const SizedBox(width: ListenSpacing.gap12),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.busy
                      ? null
                      : () => _choosePresence('absent'),
                  child: Text(l.text('reviewPresenceAbsent')),
                ),
              ),
            ],
          ),
        ],
      ),
      'word_recognition' => OutlinedButton(
        key: const ValueKey('word-recognition-prompt'),
        onPressed: widget.busy ? null : widget.onReveal,
        child: Text(l.text('reviewShowHeardWord')),
      ),
      // R3: the delayed-retelling card used to collapse to an empty box here.
      // It gives no answer to flip (the learner retells, then enters speaking),
      // so it shows the task framing and that the source stays hidden.
      'delayed_retelling' => Container(
        key: const ValueKey('delayed-retelling-prompt'),
        width: double.infinity,
        padding: const EdgeInsets.all(ListenSpacing.gap16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: ListenRadii.surfaceBorder,
        ),
        child: Text(
          l.text('reviewRetellPromptNote'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      _ => OutlinedButton(
        key: const ValueKey('source-sentence-prompt'),
        onPressed: widget.busy ? null : widget.onReveal,
        child: Text(l.text('reviewShowSourceSentence')),
      ),
    };
  }

  Widget _revealedContent(BuildContext context) {
    final card = widget.entry.card;
    final typed = _clozeController.text.trim();
    return Column(
      key: const ValueKey('review-answer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (card.kind == 'chunk_cloze' && typed.isNotEmpty) ...[
          Text(
            l.text('reviewYourTyped').replaceAll('{typed}', typed),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ListenSpacing.gap8),
        ],
        if (card.kind == 'phrase_presence' && _presenceChoice != null) ...[
          Text(
            l
                .text('reviewPresenceJudgement')
                .replaceAll(
                  '{choice}',
                  l.text(
                    _presenceChoice == 'present'
                        ? 'reviewPresencePresent'
                        : 'reviewPresenceAbsent',
                  ),
                )
                .replaceAll('{answer}', l.text('reviewPresencePresent')),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ListenSpacing.gap8),
        ],
        if (card.target != null && card.kind == 'chunk_cloze') ...[
          Text(
            l
                .text('reviewTargetChunk')
                .replaceAll('{target}', '${card.target}'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: ListenSpacing.gap8),
        ],
        Text(
          card.answer,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: ListenSpacing.gap24),
        // R5: four grades (Again/Hard/Good/Easy). The backend `ReviewRating`
        // enum has always had four; the frontend previously exposed three and
        // never let a learner press Easy. Descriptive labels are kept (P4 —
        // no guilt), Good stays the emphasized default.
        _GradeRow(
          busy: widget.busy,
          previews: widget.previews,
          onRate: widget.onRate,
        ),
      ],
    );
  }

  void _choosePresence(String choice) {
    setState(() => _presenceChoice = choice);
    widget.onReveal();
  }

  static String _instruction(AppLocalizations l, String kind) =>
      l.text(switch (kind) {
        'word_recognition' => 'reviewHintWordRecognition',
        'chunk_cloze' => 'reviewHintChunkCloze',
        'phrase_presence' => 'reviewHintPhrasePresence',
        'source_sentence_recall' => 'reviewHintSourceRecall',
        'delayed_retelling' => 'reviewHintDelayedRetelling',
        _ => 'reviewHintGeneric',
      });
}

/// The card head names what this card is and where its schedule stands.
///
/// It used to open with a capability channel too, derived here from
/// `card.kind`. That claim is gone, for three reasons. It was **wrong**: the
/// backend files a card under a channel by `source.kind` (a Sentence-sourced
/// card is Reading), so the head and the deck it was counted in disagreed
/// about the same card. It was **narrower than it looked**: this rule could
/// only ever return listening or speaking, so two of the four faces were
/// unreachable. And it was **redundant**: the card kind beside it already says
/// what the learner is about to do, more precisely and without a second rule
/// to drift.
class _CardHead extends StatelessWidget {
  const _CardHead({required this.entry});

  final ReviewQueueEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final card = entry.card;
    final imported = entry.origin.isImportedAnki;
    final detail = _scheduleDetail(l, entry.schedule);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              imported ? Icons.inventory_2_outlined : Icons.hearing_outlined,
              size: ListenIconSize.control,
              color: imported ? colors.onSurfaceVariant : colors.primary,
            ),
            const SizedBox(width: ListenSpacing.gap8),
            Expanded(
              child: Text(
                _kindLabel(l, card.kind),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            _StateChip(state: entry.state),
          ],
        ),
        if (entry.origin.isImportedAnki) ...[
          const SizedBox(height: ListenSpacing.gap4),
          Text(
            entry.origin.deckName == null
                ? l.text('reviewOriginImportedAnki')
                : l
                      .text('reviewOriginImportedAnkiDeck')
                      .replaceAll('{deck}', '${entry.origin.deckName}'),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
        if (detail != null) ...[
          const SizedBox(height: ListenSpacing.gap4),
          Text(
            detail,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  /// The durable scheduling facts the backend already sends and the card head
  /// used to throw away: the current interval, and the lapse count when the
  /// card has actually lapsed. A card with no interval yet gets no line —
  /// there is nothing true to say about its spacing.
  static String? _scheduleDetail(AppLocalizations l, ReviewSchedule schedule) {
    final parts = <String>[];
    final interval = schedule.intervalDays;
    if (interval != null) {
      parts.add(
        l
            .text('reviewIntervalLabel')
            .replaceAll('{interval}', _intervalText(l, interval)),
      );
    }
    if (schedule.lapseCount > 0) {
      parts.add(
        l
            .text('reviewRelearnCount')
            .replaceAll('{count}', '${schedule.lapseCount}'),
      );
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _kindLabel(AppLocalizations l, String kind) =>
      l.text(switch (kind) {
        'word_recognition' => 'reviewKindWordRecognition',
        'chunk_cloze' => 'reviewKindChunkCloze',
        'phrase_presence' => 'reviewKindPhrasePresence',
        'source_sentence_recall' => 'reviewKindSourceRecall',
        'delayed_retelling' => 'reviewKindDelayedRetelling',
        _ => 'reviewKindGeneric',
      });
}

/// `interval_days` is a fraction of a day for cards in sub-day steps, so it is
/// spelled in whatever unit keeps the number readable rather than being
/// rounded to a misleading "0 days". Shared by the card head (the interval the
/// card carries now) and the grade row (the interval each rating would give
/// it).
String _intervalText(AppLocalizations l, double days) {
  String plug(String key, num count) =>
      l.text(key).replaceAll('{count}', '${count.round()}');
  if (days < 1) {
    final minutes = days * 24 * 60;
    if (minutes < 60) {
      return plug('reviewIntervalMinutes', minutes < 1 ? 1 : minutes);
    }
    return plug('reviewIntervalHours', days * 24);
  }
  if (days < 30) return plug('reviewIntervalDays', days);
  return plug('reviewIntervalMonths', days / 30);
}

/// Diameter of the state dot. Large enough that the hue is unambiguous beside
/// a label-sized word, small enough that it marks the state rather than
/// competing with the channel name it sits opposite.
const _stateDotSize = 8.0;

/// S11: the card's scheduling state, as a colour that *is* the state — 月蓝
/// for first sight, amber for the sub-day learning loop (the same amber #47
/// uses for a practice target), signal teal for a card that has reached
/// day-scale intervals. The state is the scheduler's own `state` field; the
/// head previously said "New card" for every card with zero lapses, which is
/// a different question entirely.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final ReviewCardState state;

  /// The three hues are content status, not chrome, so they read straight off
  /// the palette like the vocabulary list's status bar does — the same colour
  /// has to mean the same thing in both places under either brightness.
  static Color _color(ReviewCardState state) => switch (state) {
    ReviewCardState.newCard => ListenColors.moonBlue,
    ReviewCardState.learning ||
    ReviewCardState.relearning => ListenColors.learningNeedsReview,
    ReviewCardState.review => ListenColors.learningRecognized,
  };

  static String _labelKey(ReviewCardState state) => switch (state) {
    ReviewCardState.newCard => 'reviewNewCard',
    ReviewCardState.learning => 'reviewStateLearning',
    ReviewCardState.relearning => 'reviewStateRelearning',
    ReviewCardState.review => 'reviewStateReview',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _stateDotSize,
          height: _stateDotSize,
          decoration: BoxDecoration(
            color: _color(state),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: ListenSpacing.gap6),
        Text(
          AppLocalizations.of(context).text(_labelKey(state)),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// R1: the play button is backed by the independent second decoder, so it
/// plays a source clip on its own regardless of the main player's state, and
/// reports resolution failures in place instead of graying out the whole card.
class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.slicePlayer,
    required this.clipAvailable,
    required this.onPlayClip,
  });

  final SlicePlayerController slicePlayer;
  final bool clipAvailable;
  final VoidCallback onPlayClip;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: slicePlayer.store,
      builder: (context, _) {
        final state = slicePlayer.state;
        final loading = state.open && state.loading;
        final playing = state.open && state.playing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: !clipAvailable || loading
                  ? null
                  : () {
                      // A fresh card, or one whose last attempt errored, starts
                      // a new resolution; an open clip toggles in place.
                      if (!state.open || state.error != null) {
                        onPlayClip();
                      } else if (state.playing) {
                        unawaited(slicePlayer.pause());
                      } else {
                        unawaited(slicePlayer.togglePlayback());
                      }
                    },
              icon: Icon(
                !clipAvailable
                    ? Icons.volume_off_outlined
                    : playing
                    ? Icons.pause
                    : Icons.volume_up_outlined,
              ),
              label: Text(
                !clipAvailable
                    ? l.text('reviewClipNoSource')
                    : playing
                    ? l.text('reviewPauseClip')
                    : l.text('reviewPlayClip'),
              ),
            ),
            if (state.open && state.error != null) ...[
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The four grades, each carrying FSRS's prediction of where it would put the
/// card. The prediction is a pure read (`/interval-preview`, no schedule
/// write); when it has not arrived or the call failed, [previews] is empty and
/// the buttons render bare rather than with an invented number.
class _GradeRow extends StatelessWidget {
  const _GradeRow({
    required this.busy,
    required this.previews,
    required this.onRate,
  });

  final bool busy;
  final List<ReviewIntervalPreview> previews;
  final Future<bool> Function(String rating) onRate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final byRating = {for (final preview in previews) preview.rating: preview};
    Widget grade(String rating, String labelKey, {bool emphasized = false}) {
      final preview = byRating[rating];
      final child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.text(labelKey),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (preview != null)
            Text(
              _intervalText(l, preview.intervalDays),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      );
      final onPressed = busy ? null : () => onRate(rating);
      return Expanded(
        child: emphasized
            ? FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: child,
              )
            : OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: child,
              ),
      );
    }

    return Row(
      children: [
        grade('again', 'reviewGradeMissed'),
        const SizedBox(width: ListenSpacing.gap6),
        grade('hard', 'reviewGradeFuzzy'),
        const SizedBox(width: ListenSpacing.gap6),
        grade('good', 'reviewGradeGot', emphasized: true),
        const SizedBox(width: ListenSpacing.gap6),
        grade('easy', 'reviewGradeEasy'),
      ],
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({
    required this.state,
    required this.onRetry,
    required this.onResolve,
  });

  final ReviewState state;
  final Future<bool> Function() onRetry;
  final Future<bool> Function(String id, bool confirm) onResolve;

  /// An empty queue has three different causes and they must not be told as
  /// one story: the day's budget is spent, a custom-study round ended, or
  /// there is genuinely nothing due. Only `limit_status` can distinguish the
  /// first, so the limit wording appears only when the backend reported it.
  static String _headline(AppLocalizations l, ReviewState state) {
    if (state.customStudy != null) {
      return l
          .text('reviewCustomStudyCompleted')
          .replaceAll('{count}', '${state.completedCount}');
    }
    if (state.completedCount > 0) {
      return l
          .text('reviewRoundCompleted')
          .replaceAll('{count}', '${state.completedCount}');
    }
    final limits = state.limitStatus;
    if (limits != null && limits.anyLimitReached) {
      return l.text('reviewDailyLimitReached');
    }
    return l.text('reviewNoDueCards');
  }

  static String _note(AppLocalizations l, ReviewState state) {
    if (state.customStudy != null) {
      return l.text(
        state.advancesNormalSchedule == true
            ? 'reviewCustomStudyAdvancedSchedule'
            : 'reviewCustomStudyLeftScheduleAlone',
      );
    }
    final limits = state.limitStatus;
    if (limits != null && limits.anyLimitReached) {
      return l
          .text('reviewDailyLimitNote')
          .replaceAll('{new}', '${limits.newCompleted}')
          .replaceAll('{newLimit}', '${limits.limits.newCards}')
          .replaceAll('{reviews}', '${limits.reviewsCompleted}')
          .replaceAll('{reviewLimit}', '${limits.limits.reviews}');
    }
    return l.text('reviewDueInfoNote');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: ListenPadding.pageCompact,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.error == null
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              // Illustration, not a control: this is the whole subject of the
              // round-finished / nothing-due screen, carrying its meaning on
              // its own rather than labelling anything, and nothing here is
              // tappable.
              size: ListenIconSize.illustration,
            ),
            const SizedBox(height: ListenSpacing.gap12),
            Text(
              state.error ?? _headline(l, state),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: ListenSpacing.gap8),
            if (state.error == null)
              Text(_note(l, state), textAlign: TextAlign.center)
            else
              TextButton(onPressed: onRetry, child: Text(l.text('retry'))),
            if (state.upgradeSuggestions.isNotEmpty) ...[
              const SizedBox(height: ListenSpacing.gap24),
              Text(
                l.text('reviewStatusSuggestions'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: ListenSpacing.gap8),
              for (final suggestion in state.upgradeSuggestions)
                Card(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ListenBreakpoints.formColumnMax,
                    ),
                    child: Padding(
                      padding: ListenPadding.card,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            AppLocalizations.of(context)
                                .text('listeningUpgradeSuggestion')
                                .replaceAll(
                                  '{count}',
                                  '${suggestion.evidenceContextCount}',
                                )
                                .replaceAll(
                                  '{word}',
                                  suggestion.lexicalDisplayForm,
                                ),
                          ),
                          const SizedBox(height: ListenSpacing.gap12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: state.busy
                                    ? null
                                    : () => onResolve(suggestion.id, false),
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).text('deferUpgrade'),
                                ),
                              ),
                              const SizedBox(width: ListenSpacing.gap8),
                              FilledButton(
                                onPressed: state.busy
                                    ? null
                                    : () => onResolve(suggestion.id, true),
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).text('confirmListeningAcquired'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
