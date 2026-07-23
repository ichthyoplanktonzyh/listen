import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';
import '../../theme/spacing.dart';
import '../common/listen_loading.dart';

class ColdStartMarkingSheet extends StatefulWidget {
  const ColdStartMarkingSheet({
    super.key,
    required this.api,
    required this.trackId,
    required this.language,
    required this.onDone,
  });

  final LocalApi api;
  final String trackId;
  final String language;
  final VoidCallback onDone;

  @override
  State<ColdStartMarkingSheet> createState() => _ColdStartMarkingSheetState();
}

class _ColdStartMarkingSheetState extends State<ColdStartMarkingSheet> {
  List<ColdStartWordCandidate>? _candidates;
  int _currentIndex = 0;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final candidates = await widget.api.coldStartWords(widget.trackId);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _candidates = const [];
        _loading = false;
      });
    }
  }

  Future<void> _mark(String status) async {
    if (_submitting) return;
    final candidate = _candidates![_currentIndex];
    setState(() => _submitting = true);
    try {
      await widget.api.upsertWordLexicalEntry(
        candidate.displayForm,
        candidate.displayForm,
        status,
        language: widget.language,
      );
    } catch (_) {}
    if (!mounted) return;
    _advance();
  }

  void _skip() {
    _advance();
  }

  void _advance() {
    if (_currentIndex + 1 >= _candidates!.length) {
      _finish();
    } else {
      setState(() {
        _currentIndex += 1;
        _submitting = false;
      });
    }
  }

  void _finish() {
    widget.onDone();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.text('coldStartQuickMarking'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
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
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, ColorScheme colors) {
    if (_loading) {
      return const Center(child: ListenLoading());
    }
    final candidates = _candidates!;
    if (candidates.isEmpty) {
      return Center(
        child: Text(
          l.text('coldStartEmpty'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }
    final candidate = candidates[_currentIndex];
    final progress = l
        .text('coldStartProgress')
        .replaceAll('{current}', '${_currentIndex + 1}')
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
          candidate.displayForm,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ListenSpacing.gap24),
        _ActionButton(
          label: l.text('coldStartKnownRecognized'),
          color: colors.primary,
          onPressed: _submitting ? null : () => _mark('known_recognized'),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        _ActionButton(
          label: l.text('coldStartKnownNotRecognized'),
          color: colors.tertiary,
          onPressed: _submitting ? null : () => _mark('known_not_recognized'),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        _ActionButton(
          label: l.text('coldStartUnknownMeaning'),
          color: colors.error,
          onPressed: _submitting ? null : () => _mark('unknown_meaning'),
        ),
        const SizedBox(height: ListenSpacing.gap8),
        TextButton(
          onPressed: _submitting ? null : _skip,
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
