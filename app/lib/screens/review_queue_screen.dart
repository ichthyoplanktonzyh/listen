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
    required this.onStartShadowing,
    this.currentMediaId,
  });

  final LocalApi api;
  final Future<void> Function(int startMs, int endMs) onPlayRange;
  final Future<void> Function(ReviewQueueEntry entry) onStartShadowing;
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
      title: const Text('声音复习'),
      actions: [
        StoreBuilder<ReviewState, int>(
          store: controller.store,
          select: (state) => state.remaining,
          builder: (context, remaining) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(child: Text('到期 $remaining')),
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
          onShadowing: () async {
            final entry = state.current!;
            Navigator.of(context).pop();
            await widget.onStartShadowing(entry);
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
  final VoidCallback onPlay;
  final Future<void> Function() onShadowing;
  final VoidCallback onReveal;
  final Future<bool> Function(String rating) onRate;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  final _clozeController = TextEditingController();
  String? _presenceChoice;

  @override
  void dispose() {
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
                          _kindLabel(card.kind),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Text(
                        widget.entry.schedule.lapseCount == 0
                            ? '新卡'
                            : '重学 ${widget.entry.schedule.lapseCount}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _instruction(card.kind),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: playable ? widget.onPlay : null,
                    icon: Icon(
                      playable
                          ? Icons.volume_up_outlined
                          : Icons.volume_off_outlined,
                    ),
                    label: Text(playable ? '播放声音片段' : '原媒体不可播放，使用文字快照'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: widget.shadowAvailable && !widget.busy
                        ? () => unawaited(widget.onShadowing())
                        : null,
                    icon: const Icon(Icons.mic_none),
                    label: const Text('跟一下这个片段'),
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
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '填入听到的语块',
            ),
            onSubmitted: (_) => widget.busy ? null : widget.onReveal(),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: widget.busy ? null : widget.onReveal,
            child: const Text('对照答案'),
          ),
        ],
      ),
      'phrase_presence' => Column(
        key: const ValueKey('phrase-presence-prompt'),
        children: [
          Text('目标短语', style: Theme.of(context).textTheme.labelLarge),
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
                  onPressed: widget.busy ? null : () => _choosePresence('出现'),
                  child: const Text('出现'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.busy ? null : () => _choosePresence('没出现'),
                  child: const Text('没出现'),
                ),
              ),
            ],
          ),
        ],
      ),
      'word_recognition' => OutlinedButton(
        key: const ValueKey('word-recognition-prompt'),
        onPressed: widget.busy ? null : widget.onReveal,
        child: const Text('显示听到的词'),
      ),
      _ => OutlinedButton(
        key: const ValueKey('source-sentence-prompt'),
        onPressed: widget.busy ? null : widget.onReveal,
        child: const Text('显示原句'),
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
          Text('你的填写：$typed', textAlign: TextAlign.center),
          const SizedBox(height: 10),
        ],
        if (card.kind == 'phrase_presence' && _presenceChoice != null) ...[
          Text('你的判断：$_presenceChoice · 答案：出现', textAlign: TextAlign.center),
          const SizedBox(height: 10),
        ],
        if (card.target != null && card.kind == 'chunk_cloze') ...[
          Text(
            '目标语块：${card.target}',
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
                child: const Text('没听出'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: widget.busy ? null : () => widget.onRate('hard'),
                child: const Text('模糊'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: widget.busy ? null : () => widget.onRate('good'),
                child: const Text('听出了'),
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

  static String _kindLabel(String kind) => switch (kind) {
    'word_recognition' => '听音识词',
    'chunk_cloze' => '语块填空',
    'phrase_presence' => '短语判断',
    'source_sentence_recall' => '原句回听',
    _ => '声音卡',
  };

  static String _instruction(String kind) => switch (kind) {
    'word_recognition' => '只听声音，先回忆你听到的是哪个词。',
    'chunk_cloze' => '听完整语块，把空白处补出来。',
    'phrase_presence' => '听原句，判断目标短语是否真的出现。',
    'source_sentence_recall' => '回听原句，先复述意思或原文，再翻面对照。',
    _ => '先听声音，再翻面对照。',
  };

  static IconData _kindIcon(String kind) => switch (kind) {
    'word_recognition' => Icons.hearing_outlined,
    'chunk_cloze' => Icons.space_bar_outlined,
    'phrase_presence' => Icons.rule_outlined,
    'source_sentence_recall' => Icons.record_voice_over_outlined,
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
  Widget build(BuildContext context) => Center(
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
                    ? '现在没有到期声音卡'
                    : '本轮完成 ${state.completedCount} 张'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (state.error == null)
            const Text('到期数量只是信息，不是欠账。')
          else
            TextButton(onPressed: onRetry, child: const Text('重试')),
          if (state.upgradeSuggestions.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text('识别状态建议', style: Theme.of(context).textTheme.titleMedium),
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
