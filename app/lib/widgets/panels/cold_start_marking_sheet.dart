import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/cold_start_marking_view_model.dart';
import '../../localization.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/listen_empty_state.dart';
import '../common/listen_loading.dart';

class ColdStartMarkingSheet extends StatefulWidget {
  const ColdStartMarkingSheet({
    super.key,
    required this.viewModel,
    required this.onDone,
  });

  final VoidCallback onDone;
  final ColdStartMarkingViewModel viewModel;

  @override
  State<ColdStartMarkingSheet> createState() => _ColdStartMarkingSheetState();
}

class _ColdStartMarkingSheetState extends State<ColdStartMarkingSheet> {
  ColdStartMarkingViewModel get _viewModel => widget.viewModel;
  bool _didFinish = false;

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_handleViewModelChange);
    unawaited(_viewModel.load());
  }

  @override
  void dispose() {
    _viewModel.removeListener(_handleViewModelChange);
    super.dispose();
  }

  void _handleViewModelChange() {
    if (!_viewModel.state.finished || _didFinish || !mounted) return;
    _didFinish = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onDone();
      Navigator.of(context).pop();
    });
  }

  void _finish() {
    _viewModel.finish();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => Dialog(
        child: ConstrainedBox(
          // A column of decisions, not of reading: one word and three verdicts.
          // `maxHeight` is a viewport budget rather than a column measure, so it
          // stays a literal.
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.formColumnMax,
            maxHeight: 420,
          ),
          child: Padding(
            padding: ListenPadding.card,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.text('coldStartQuickMarking'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: ListenIconSize.control,
                      ),
                      onPressed: _finish,
                    ),
                  ],
                ),
                const SizedBox(height: ListenSpacing.gap16),
                Expanded(child: _body(context, l, colors)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, ColorScheme colors) {
    final state = _viewModel.state;
    if (state.loading) {
      return const Center(child: ListenLoading());
    }
    final candidates = state.candidates;
    if (candidates.isEmpty) {
      return ListenEmptyState(
        icon: Icons.checklist,
        message: l.text('coldStartEmpty'),
      );
    }
    final candidate = state.current!;
    final progress = l
        .text('coldStartProgress')
        .replaceAll('{current}', '${state.currentIndex + 1}')
        .replaceAll('{total}', '${candidates.length}');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          progress,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: ListenSpacing.gap16),
        Text(
          // The word under judgement is the largest thing on this sheet, so it
          // takes the one hero size. `ListenType.hero` already carries w600;
          // the old w700 override came with the unmapped Material slot.
          candidate.displayForm,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: ListenSpacing.gap24),
        _ActionButton(
          label: l.text('coldStartKnownRecognized'),
          color: colors.primary,
          onPressed: state.submitting
              ? null
              : () => _viewModel.mark('known_recognized'),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        _ActionButton(
          label: l.text('coldStartKnownNotRecognized'),
          color: colors.tertiary,
          onPressed: state.submitting
              ? null
              : () => _viewModel.mark('known_not_recognized'),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        _ActionButton(
          label: l.text('coldStartUnknownMeaning'),
          color: colors.error,
          onPressed: state.submitting
              ? null
              : () => _viewModel.mark('unknown_meaning'),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        TextButton(
          onPressed: state.submitting ? null : _viewModel.skip,
          child: Text(l.text('coldStartSkip')),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}
