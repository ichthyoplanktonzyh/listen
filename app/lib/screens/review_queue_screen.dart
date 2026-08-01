import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/occurrence_media_resolver.dart';
import '../controllers/review_controller.dart';
import '../controllers/slice_player_controller.dart';
import '../data/repositories/review_repository.dart';
import '../localization.dart';
import '../models/practice.dart';
import '../state/builder.dart';
import '../theme/breakpoints.dart';
import '../theme/icon_size.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/common/listen_error_state.dart';
import '../widgets/common/listen_loading.dart';

class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({
    super.key,
    required this.repository,
    required this.onStartShadowing,
    required this.onStartDelayedRetelling,
    this.onPauseBackgroundPlayback,
    this.controller,
    this.resolver,
    this.createSlicePlaybackAdapter,
  });

  final Future<void> Function(ReviewQueueEntry entry) onStartShadowing;
  final Future<void> Function(ReviewQueueEntry entry) onStartDelayedRetelling;

  /// Silences the primary player so a review clip owns audio focus alone. The
  /// clip runs on a second decoder ([SlicePlayerController]) that is otherwise
  /// completely independent of the main player (S5 · R1).
  final Future<void> Function()? onPauseBackgroundPlayback;

  final ReviewRepository repository;
  final ReviewController? controller;

  /// The clip resolver. Production builds one from [repository] exactly like the
  /// vocabulary dictionary's; tests inject a stub so a clip can resolve
  /// without a real file on disk.
  final OccurrenceMediaResolver? resolver;

  /// The second-decoder adapter factory, overridable so tests inject a fake
  /// instead of opening a real video_player instance.
  final CreateSlicePlaybackAdapter? createSlicePlaybackAdapter;

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  late final ReviewController controller =
      widget.controller ?? ReviewController(widget.repository);
  late final bool _ownsController = widget.controller == null;

  /// The review card plays its source clip on its own decoder, so a card is
  /// reviewable even when no media (or a different one) is loaded in the main
  /// player — the fix for the whole-queue "clip unavailable" state (S5 · R1).
  late final SlicePlayerController _slicePlayer = SlicePlayerController(
    createAdapter: widget.createSlicePlaybackAdapter,
  );

  late final OccurrenceMediaResolver _resolver =
      widget.resolver ?? OccurrenceMediaResolver(repository: widget.repository);

  @override
  void initState() {
    super.initState();
    unawaited(controller.load());
  }

  @override
  void dispose() {
    _slicePlayer.dispose();
    if (_ownsController) controller.dispose();
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
          return _ReviewCard(
            key: ValueKey(entry.item.id),
            entry: entry,
            clipAvailable: _clipAvailable(entry),
            shadowAvailable: _canShadow(entry),
            revealed: state.revealed,
            busy: state.busy,
            error: state.error,
            slicePlayer: _slicePlayer,
            onPlayClip: () => unawaited(_playClip(entry)),
            onShadowing: () async {
              await _slicePlayer.close();
              if (!context.mounted) return;
              Navigator.of(context).pop();
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
        },
      ),
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
        _GradeRow(busy: widget.busy, onRate: widget.onRate),
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

/// R2: the card head names *which channel* the card trains (derived from its
/// kind, a durable backend fact) with the shared capability graphic language,
/// instead of a raw stock icon that said nothing about the practice. The
/// per-word three-state ring is deferred — the queue entry carries no
/// capability profile, and fetching one would be new backend work (波次 D).
class _CardHead extends StatelessWidget {
  const _CardHead({required this.entry});

  final ReviewQueueEntry entry;

  /// Every review kind trains one channel; the mapping is presentation, not a
  /// new judgment (the kinds themselves are generated by the backend).
  static String _channel(String kind) => switch (kind) {
    'delayed_retelling' || 'source_sentence_recall' => 'speaking',
    _ => 'listening',
  };

  static ({String labelKey, IconData icon}) _channelFace(String channel) =>
      switch (channel) {
        'speaking' => (
          labelKey: 'capabilitySpeaking',
          icon: Icons.record_voice_over_outlined,
        ),
        'reading' => (
          labelKey: 'capabilityReading',
          icon: Icons.menu_book_outlined,
        ),
        'writing' => (labelKey: 'capabilityWriting', icon: Icons.edit_outlined),
        _ => (labelKey: 'capabilityListening', icon: Icons.hearing_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final card = entry.card;
    final face = _channelFace(_channel(card.kind));
    return Row(
      children: [
        Icon(face.icon, size: ListenIconSize.control, color: colors.primary),
        const SizedBox(width: ListenSpacing.gap8),
        Expanded(
          child: Text(
            '${l.text(face.labelKey)} · ${_kindLabel(l, card.kind)}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Text(
          entry.schedule.lapseCount == 0
              ? l.text('reviewNewCard')
              : l
                    .text('reviewRelearnCount')
                    .replaceAll('{count}', '${entry.schedule.lapseCount}'),
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      ],
    );
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

class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.busy, required this.onRate});

  final bool busy;
  final Future<bool> Function(String rating) onRate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget grade(String rating, String labelKey, {bool emphasized = false}) {
      final child = Text(
        l.text(labelKey),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
              state.error ??
                  (state.completedCount == 0
                      ? l.text('reviewNoDueCards')
                      : l
                            .text('reviewRoundCompleted')
                            .replaceAll('{count}', '${state.completedCount}')),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: ListenSpacing.gap8),
            if (state.error == null)
              Text(l.text('reviewDueInfoNote'))
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
