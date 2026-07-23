import 'package:flutter/material.dart';

import '../../controllers/reading_task_controller.dart';
import '../../localization.dart';
import '../../services/api_service.dart';
import '../../theme/breakpoints.dart';
import '../../theme/spacing.dart';
import 'reading_task_sheet.dart';
import '../../theme/typography.dart';

/// Stage-adaptive whole-scene host for semantic tasks. The controller owns
/// the durable task lifecycle; this widget only chooses an honest layout for
/// the current phase and keeps the source snapshot available without a modal.
class ReadingTaskStudio extends StatelessWidget {
  const ReadingTaskStudio({
    super.key,
    required this.controller,
    required this.api,
    required this.source,
    required this.audioPlayCount,
    required this.onClose,
    this.onPlaySegment,
  });

  final ReadingTaskController controller;
  final LocalApi api;
  final ReadingTaskSource source;
  final int Function() audioPlayCount;
  final VoidCallback onClose;
  final VoidCallback? onPlaySegment;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final colors = Theme.of(context).colorScheme;
      return Material(
        color: colors.surface,
        child: Column(
          children: [
            _header(context, state, colors),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < ListenBreakpoints.readingCompact;
                  final sourcePane = _SourceSnapshot(
                    source: source,
                    hideText: state.isListening,
                    compact:
                        state.phase == 'assessing' || state.phase == 'done',
                  );
                  final taskPane = ReadingTaskSheet(
                    controller: controller,
                    api: api,
                    audioPlayCount: audioPlayCount,
                    onPlaySegment: onPlaySegment,
                    onClose: onClose,
                    expanded: true,
                  );
                  if (compact) {
                    return Column(
                      children: [
                        Flexible(flex: 2, child: sourcePane),
                        Divider(height: 1, color: colors.outlineVariant),
                        Flexible(flex: 5, child: taskPane),
                      ],
                    );
                  }
                  final sourceFlex =
                      state.phase == 'assessing' || state.phase == 'done'
                      ? 2
                      : 4;
                  return Row(
                    children: [
                      Flexible(flex: sourceFlex, child: sourcePane),
                      VerticalDivider(width: 1, color: colors.outlineVariant),
                      Flexible(flex: 7, child: taskPane),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _header(
    BuildContext context,
    ReadingTaskState state,
    ColorScheme colors,
  ) {
    final l = AppLocalizations.of(context);
    final phases = state.isListening
        ? const ['editing', 'answering', 'assessing', 'done']
        : const ['editing', 'answering', 'assessing', 'done'];
    final current = phases.indexOf(state.phase).clamp(0, phases.length - 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('reading-task-back'),
              tooltip: l.text('readingTaskClose'),
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: ListenSpacing.gap4),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < phases.length; i++) ...[
                    _StageBadge(
                      index: i + 1,
                      label: l.text(switch (phases[i]) {
                        'editing' => 'taskStageRubric',
                        'answering' => 'taskStageAnswer',
                        'assessing' => 'taskStageAssess',
                        _ => 'taskStageDone',
                      }),
                      active: i == current,
                      complete: i < current,
                    ),
                    if (i != phases.length - 1)
                      Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: colors.outline,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({
    required this.index,
    required this.label,
    required this.active,
    required this.complete,
  });

  final int index;
  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: active,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: complete || active
                ? colors.primary
                : colors.surfaceContainerHighest,
            foregroundColor: complete || active
                ? colors.onPrimary
                : colors.onSurfaceVariant,
            child: complete
                ? const Icon(Icons.check, size: 15)
                : Text('$index', style: ListenType.body),
          ),
          const SizedBox(width: ListenSpacing.gap6),
          Text(
            label,
            style: TextStyle(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceSnapshot extends StatelessWidget {
  const _SourceSnapshot({
    required this.source,
    required this.hideText,
    required this.compact,
  });

  final ReadingTaskSource source;
  final bool hideText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLowest,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.text('taskSourceSnapshot'),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: ListenSpacing.gap12),
            Text(
              hideText
                  ? l.text('taskSourceHiddenForListening')
                  : source.transcriptSnapshot,
              maxLines: compact ? 5 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                height: 1.7,
                fontFamily: hideText ? null : 'Georgia',
                color: hideText ? colors.onSurfaceVariant : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
