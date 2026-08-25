import 'package:flutter/material.dart';

import '../../services/document_decoding/document_blocks.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Renders the pure [RestrictedDocument] block model. Receives only blocks —
/// never raw markup, URLs, or attributes — so untrusted input cannot reach
/// network, file, or script contexts from here.
class DocumentBlockView extends StatelessWidget {
  const DocumentBlockView({super.key, required this.document});

  final RestrictedDocument document;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final block in document.blocks) ...[
            _blockWidget(block, textTheme, colors),
            const SizedBox(height: ListenSpacing.gap8),
          ],
        ],
      ),
    );
  }

  Widget _blockWidget(
    DocumentBlock block,
    TextTheme textTheme,
    ColorScheme colors,
  ) => switch (block) {
    DocumentHeadingBlock(:final level, :final text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: switch (level) {
          1 => textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          2 => textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          3 => textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          _ => textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        },
      ),
    ),
    DocumentParagraphBlock(:final runs) => _InlineRuns(runs: runs),
    DocumentListBlock(:final ordered, :final items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, item) in items.indexed)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ordered ? '${index + 1}.' : '•',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(child: _InlineRuns(runs: item)),
              ],
            ),
          ),
      ],
    ),
    DocumentCodeBlock(:final text) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: ListenRadii.controlBorder,
      ),
      child: SelectableText(
        text,
        style: textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.4,
        ),
      ),
    ),
    DocumentQuoteBlock(:final runs) => Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.outlineVariant, width: 3)),
      ),
      child: _InlineRuns(runs: runs),
    ),
    DocumentThematicBreak() => Divider(color: colors.outlineVariant),
  };
}

/// Renders a paragraph's inline runs. Emphasis and code are styled runs;
/// links render as styled text — the destination is never activated, fetched,
/// or shown.
class _InlineRuns extends StatelessWidget {
  const _InlineRuns({required this.runs});

  final List<DocumentInline> runs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final base = textTheme.bodyMedium;
    return Text.rich(
      TextSpan(
        children: [
          for (final run in runs)
            switch (run) {
              DocumentTextRun(:final text) => TextSpan(text: text),
              DocumentBoldRun(:final text) => TextSpan(
                text: text,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              DocumentItalicRun(:final text) => TextSpan(
                text: text,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              DocumentCodeRun(:final text) => TextSpan(
                text: text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
              DocumentLinkRun(:final text) => TextSpan(
                text: text,
                style: TextStyle(
                  color: colors.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            },
        ],
        style: base,
      ),
    );
  }
}
