import 'package:flutter/material.dart';

import '../../controllers/hunting_session_controller.dart';
import '../../localization.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

class HuntingPromptCard extends StatelessWidget {
  const HuntingPromptCard({
    super.key,
    required this.controller,
    required this.onAnswer,
    required this.onReindex,
  });

  final HuntingSessionController controller;
  final ValueChanged<String> onAnswer;
  final VoidCallback onReindex;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      if (!state.enabled) return const SizedBox.shrink();
      final l = AppLocalizations.of(context);
      if (state.loaded && !state.indexed) {
        return _PromptShell(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.manage_search_outlined),
              const SizedBox(width: ListenSpacing.gap8),
              Flexible(child: Text(l.text('huntingIndexNeeded'))),
              const SizedBox(width: ListenSpacing.gap8),
              OutlinedButton(
                onPressed: state.busy ? null : onReindex,
                child: Text(l.text('dictionaryReindex')),
              ),
            ],
          ),
        );
      }
      final current = state.current;
      if (current == null) return const SizedBox.shrink();
      if (state.phase == 'priming') {
        return _PromptShell(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hearing_outlined),
              const SizedBox(width: ListenSpacing.gap8),
              Text(
                l
                    .text('huntingListenFor')
                    .replaceAll('{target}', current.targetSnapshot),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        );
      }
      return _PromptShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l
                  .text('huntingDidYouHear')
                  .replaceAll('{target}', current.targetSnapshot),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: ListenSpacing.gap8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: state.busy ? null : () => onAnswer('recognized'),
                  child: Text(l.text('huntingAnswerYes')),
                ),
                OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => onAnswer('not_recognized'),
                  child: Text(l.text('huntingAnswerNo')),
                ),
                TextButton(
                  onPressed: state.busy ? null : () => onAnswer('not_noticed'),
                  child: Text(l.text('huntingAnswerNotNoticed')),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _PromptShell extends StatelessWidget {
  const _PromptShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    borderRadius: ListenRadii.panelBorder,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}
