import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/review_controller.dart';
import '../models/practice.dart';
import '../services/api_service.dart';
import '../state/builder.dart';

class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({
    super.key,
    required this.api,
    required this.onPlayRange,
    this.currentMediaId,
  });

  final LocalApi api;
  final Future<void> Function(int startMs, int endMs) onPlayRange;
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
          );
        }
        return _ReviewCard(
          entry: state.current!,
          audioAvailable: _canPlay(state.current!),
          revealed: state.revealed,
          busy: state.busy,
          error: state.error,
          onPlay: () => _play(state.current!),
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
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.entry,
    required this.audioAvailable,
    required this.revealed,
    required this.busy,
    required this.onPlay,
    required this.onReveal,
    required this.onRate,
    this.error,
  });

  final ReviewQueueEntry entry;
  final bool audioAvailable;
  final bool revealed;
  final bool busy;
  final String? error;
  final VoidCallback onPlay;
  final VoidCallback onReveal;
  final Future<bool> Function(String rating) onRate;

  bool get playable {
    final start = entry.playbackStartMs;
    final end = entry.playbackEndMs;
    return audioAvailable && start != null && end != null && end > start;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
                      Icon(Icons.graphic_eq, color: colors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _sourceLabel(entry.item.source.kind),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Text(
                        entry.schedule.lapseCount == 0
                            ? '新卡'
                            : '重学 ${entry.schedule.lapseCount}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: playable ? onPlay : null,
                    icon: Icon(
                      playable
                          ? Icons.volume_up_outlined
                          : Icons.volume_off_outlined,
                    ),
                    label: Text(playable ? '播放声音片段' : '原媒体不可播放，使用文字快照'),
                  ),
                  const SizedBox(height: 26),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 180),
                    crossFadeState: revealed
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: OutlinedButton(
                      onPressed: busy ? null : onReveal,
                      child: const Text('显示答案'),
                    ),
                    secondChild: Column(
                      children: [
                        Text(
                          entry.item.promptSnapshot,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: busy ? null : () => onRate('again'),
                                child: const Text('没听出'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: busy ? null : () => onRate('hard'),
                                child: const Text('模糊'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: busy ? null : () => onRate('good'),
                                child: const Text('听出了'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 18),
                    Text(error!, style: TextStyle(color: colors.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _sourceLabel(String kind) => switch (kind) {
    'practice_failure' => '精听错题',
    'listening_inbox' => '泛听收件箱',
    'lexical_entry' => '词汇复习',
    'chunk' => '语块复习',
    'sentence' => '原句回听',
    _ => '声音卡',
  };
}

class _Finished extends StatelessWidget {
  const _Finished({required this.state, required this.onRetry});

  final ReviewState state;
  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
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
      ],
    ),
  );
}
