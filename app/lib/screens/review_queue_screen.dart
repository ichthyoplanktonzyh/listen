import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/review_controller.dart';
import '../localization.dart';
import '../models/practice.dart';
import '../services/api_service.dart';
import '../state/builder.dart';

class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({
    super.key,
    required this.api,
    required this.onPlayRange,
    required this.onPausePlayback,
    required this.onStartShadowing,
    required this.onStartDelayedRetelling,
    this.currentMediaId,
  });

  final LocalApi api;
  final Future<void> Function(int startMs, int endMs) onPlayRange;
  final Future<void> Function() onPausePlayback;
  final Future<void> Function(ReviewQueueEntry entry) onStartShadowing;
  final Future<void> Function(ReviewQueueEntry entry) onStartDelayedRetelling;
  final String? currentMediaId;

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  final controller = ReviewController();

  @override
  void initState() {
    super.initState();
    unawaited(controller.load(widget.api));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context).text('reviewTitle')),
      actions: [
        StoreBuilder<ReviewState, int>(
          store: controller.store,
          select: (state) => state.remaining,
          builder: (context, remaining) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(
              child: Text(
                AppLocalizations.of(
                  context,
                ).text('reviewDueCount').replaceAll('{count}', '$remaining'),
              ),
            ),
          ),
        ),
      ],
    ),
    body: StoreBuilder<ReviewState, ReviewState>(
      store: controller.store,
      select: (state) => state,
      builder: (context, state) {
        if (state.busy && state.queue.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.current == null) {
          return _Finished(
            state: state,
            onRetry: () => controller.load(widget.api),
            onResolve: (id, confirm) => controller.resolveUpgradeSuggestion(
              widget.api,
              id,
              confirm: confirm,
            ),
          );
        }
        return _ReviewCard(
          key: ValueKey(state.current!.item.id),
          entry: state.current!,
          audioAvailable: _canPlay(state.current!),
          shadowAvailable: _canShadow(state.current!),
          revealed: state.revealed,
          busy: state.busy,
          error: state.error,
          onPlay: () => _play(state.current!),
          onPause: widget.onPausePlayback,
          onShadowing: () async {
            final entry = state.current!;
            await widget.onPausePlayback();
            if (!context.mounted) return;
            Navigator.of(context).pop();
            if (entry.card.kind == 'delayed_retelling') {
              await widget.onStartDelayedRetelling(entry);
            } else {
              await widget.onStartShadowing(entry);
            }
          },
          onReveal: controller.reveal,
          onRate: (rating) => controller.rate(widget.api, rating),
        );
      },
    ),
  );

  Future<void> _play(ReviewQueueEntry entry) async {
    final start = entry.playbackStartMs;
    final end = entry.playbackEndMs;
    if (start == null || end == null || end <= start) return;
    await widget.onPlayRange(start, end);
  }

  bool _canPlay(ReviewQueueEntry entry) =>
      widget.currentMediaId != null &&
      entry.item.source.mediaId == widget.currentMediaId &&
      entry.playbackStartMs != null &&
      entry.playbackEndMs != null;

  bool _canShadow(ReviewQueueEntry entry) =>
      entry.item.source.mediaId != null &&
      entry.playbackStartMs != null &&
      entry.playbackEndMs != null;
}

class _ReviewCard extends StatefulWidget {
  const _ReviewCard({
    super.key,
    required this.entry,
    required this.audioAvailable,
    required this.shadowAvailable,
    required this.revealed,
    required this.busy,
    required this.onPlay,
    required this.onPause,
    required this.onShadowing,
    required this.onReveal,
    required this.onRate,
    this.error,
  });

  final ReviewQueueEntry entry;
  final bool audioAvailable;
  final bool shadowAvailable;
  final bool revealed;
  final bool busy;
  final String? error;
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
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
  bool _playing = false;

  @override
  void dispose() {
    if (_playing) unawaited(widget.onPause());
    _clozeController.dispose();
    super.dispose();
  }

  bool get playable {
    final start = widget.entry.playbackStartMs;
    final end = widget.entry.playbackEndMs;
    return widget.audioAvailable && start != null && end != null && end > start;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final card = widget.entry.card;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(_kindIcon(card.kind), color: colors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _kindLabel(l, card.kind),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Text(
                        widget.entry.schedule.lapseCount == 0
                            ? l.text('reviewNewCard')
                            : l
                                  .text('reviewRelearnCount')
                                  .replaceAll(
                                    '{count}',
                                    '${widget.entry.schedule.lapseCount}',
                                  ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _instruction(l, card.kind),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: playable ? _togglePlayback : null,
                    icon: Icon(
                      playable
                          ? _playing
                                ? Icons.pause
                                : Icons.volume_up_outlined
                          : Icons.volume_off_outlined,
                    ),
                    label: Text(
                      playable
                          ? _playing
                                ? l.text('reviewPauseClip')
                                : l.text('reviewPlayClip')
                          : l.text('reviewClipUnavailable'),
                    ),
                  ),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 26),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: widget.revealed
                        ? _revealedContent(context)
                        : _promptContent(context),
                  ),
                  if (widget.error != null) ...[
                    const SizedBox(height: 18),
                    Text(widget.error!, style: TextStyle(color: colors.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await widget.onPause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await widget.onPlay();
    if (mounted) setState(() => _playing = true);
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
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 8),
          Text(
            card.cue ?? card.target ?? '',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
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
              const SizedBox(width: 12),
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
      'delayed_retelling' => const SizedBox.shrink(),
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
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
        ],
        if (card.target != null && card.kind == 'chunk_cloze') ...[
          Text(
            l
                .text('reviewTargetChunk')
                .replaceAll('{target}', '${card.target}'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
        ],
        Text(
          card.answer,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.busy ? null : () => widget.onRate('again'),
                child: Text(l.text('reviewGradeMissed')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: widget.busy ? null : () => widget.onRate('hard'),
                child: Text(l.text('reviewGradeFuzzy')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: widget.busy ? null : () => widget.onRate('good'),
                child: Text(l.text('reviewGradeGot')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _choosePresence(String choice) {
    setState(() => _presenceChoice = choice);
    widget.onReveal();
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

  static String _instruction(AppLocalizations l, String kind) =>
      l.text(switch (kind) {
        'word_recognition' => 'reviewHintWordRecognition',
        'chunk_cloze' => 'reviewHintChunkCloze',
        'phrase_presence' => 'reviewHintPhrasePresence',
        'source_sentence_recall' => 'reviewHintSourceRecall',
        'delayed_retelling' => 'reviewHintDelayedRetelling',
        _ => 'reviewHintGeneric',
      });

  static IconData _kindIcon(String kind) => switch (kind) {
    'word_recognition' => Icons.hearing_outlined,
    'chunk_cloze' => Icons.space_bar_outlined,
    'phrase_presence' => Icons.rule_outlined,
    'source_sentence_recall' => Icons.record_voice_over_outlined,
    'delayed_retelling' => Icons.event_repeat_outlined,
    _ => Icons.graphic_eq,
  };
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.error == null
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: 52,
            ),
            const SizedBox(height: 14),
            Text(
              state.error ??
                  (state.completedCount == 0
                      ? l.text('reviewNoDueCards')
                      : l
                            .text('reviewRoundCompleted')
                            .replaceAll('{count}', '${state.completedCount}')),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (state.error == null)
              Text(l.text('reviewDueInfoNote'))
            else
              TextButton(onPressed: onRetry, child: Text(l.text('retry'))),
            if (state.upgradeSuggestions.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                l.text('reviewStatusSuggestions'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              for (final suggestion in state.upgradeSuggestions)
                Card(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
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
                          const SizedBox(height: 12),
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
                              const SizedBox(width: 8),
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
