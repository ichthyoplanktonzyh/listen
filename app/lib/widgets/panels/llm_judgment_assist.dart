import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/semantic_task.dart';

/// LLM assist block shared by the Reading/Speaking/Writing Studios
/// (Phase 3.12.2): correctable heuristic feedback shown next to the manual
/// self-assessment. Hosts hide it entirely (via [visible]) when no
/// judgment-capable provider is configured; it never writes learning evidence.
class LlmJudgmentAssist extends StatelessWidget {
  const LlmJudgmentAssist({
    super.key,
    required this.visible,
    required this.points,
    required this.judgment,
    required this.adjudications,
    required this.busy,
    required this.keyPrefix,
    required this.onRequest,
    required this.onCorrect,
  });

  final bool visible;
  final List<RubricPointView> points;
  final SemanticJudgmentView? judgment;
  final List<JudgmentAdjudicationView> adjudications;
  final bool busy;

  /// Studio-specific test-key namespace, e.g. `reading-task`.
  final String keyPrefix;
  final VoidCallback onRequest;
  final void Function(String pointId, String userVerdict) onCorrect;

  static const _verdicts = ['covered', 'partial', 'missing', 'uncertain'];

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final judgment = this.judgment;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (judgment == null)
            OutlinedButton.icon(
              key: ValueKey('$keyPrefix-request-ai'),
              onPressed: busy ? null : onRequest,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(l.text('llmAssistRequest')),
            )
          else ...[
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: colors.tertiary),
                const SizedBox(width: 6),
                Text(
                  l.text('llmAssistTitle'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              l.text('llmAssistNote'),
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            if (judgment.isAbstain)
              Text(
                l.text('llmAssistAbstain'),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              )
            else
              for (final point in points) _verdictRow(l, colors, point),
          ],
        ],
      ),
    );
  }

  String _effectiveVerdict(String pointId) {
    for (final adjudication in adjudications.reversed) {
      if (adjudication.pointId == pointId) return adjudication.userVerdict;
    }
    return judgment?.verdictFor(pointId) ?? 'uncertain';
  }

  Widget _verdictRow(
    AppLocalizations l,
    ColorScheme colors,
    RubricPointView point,
  ) {
    final verdict = _effectiveVerdict(point.pointId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(point.statement, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Text(
            _verdictLabel(l, verdict),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: switch (verdict) {
                'covered' => Colors.green.shade700,
                'partial' => Colors.orange.shade800,
                'missing' => colors.error,
                _ => colors.onSurfaceVariant,
              },
            ),
          ),
          PopupMenuButton<String>(
            key: ValueKey('$keyPrefix-adjudicate-ai-${point.pointId}'),
            tooltip: l.text('llmAssistCorrect'),
            icon: const Icon(Icons.edit_outlined, size: 15),
            onSelected: (userVerdict) => onCorrect(point.pointId, userVerdict),
            itemBuilder: (context) => [
              for (final option in _verdicts)
                if (option != verdict)
                  PopupMenuItem(
                    value: option,
                    child: Text(_verdictLabel(l, option)),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  String _verdictLabel(AppLocalizations l, String verdict) =>
      l.text(switch (verdict) {
        'covered' => 'verdictCovered',
        'partial' => 'verdictPartial',
        'missing' => 'verdictMissing',
        _ => 'verdictUncertain',
      });
}
