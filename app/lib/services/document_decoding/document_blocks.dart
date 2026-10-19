/// Pure block model for restricted document rendering.
///
/// Parsers produce these blocks from untrusted input; the widget renderer
/// renders exactly this model and nothing else. No block may carry a URL to
/// dereference, an image source, or executable content.
library;

/// One inline run of text inside a [DocumentParagraph]-like block.
sealed class DocumentInline {
  const DocumentInline();
}

final class DocumentTextRun extends DocumentInline {
  const DocumentTextRun(this.text);

  final String text;
}

final class DocumentBoldRun extends DocumentInline {
  const DocumentBoldRun(this.text);

  final String text;
}

final class DocumentItalicRun extends DocumentInline {
  const DocumentItalicRun(this.text);

  final String text;
}

final class DocumentCodeRun extends DocumentInline {
  const DocumentCodeRun(this.text);

  final String text;
}

/// A link's label as styled text. The destination is deliberately discarded:
/// a restricted renderer never activates, fetches, or dereferences it.
final class DocumentLinkRun extends DocumentInline {
  const DocumentLinkRun(this.text);

  final String text;
}

/// One top-level block of a restricted document.
sealed class DocumentBlock {
  const DocumentBlock();
}

final class DocumentHeadingBlock extends DocumentBlock {
  const DocumentHeadingBlock({required this.level, required this.text});

  /// 1..6; parsed from `#`..`######` or `h1`..`h6`.
  final int level;
  final String text;
}

final class DocumentParagraphBlock extends DocumentBlock {
  DocumentParagraphBlock({required List<DocumentInline> runs})
    : runs = List.unmodifiable(runs);

  final List<DocumentInline> runs;
}

final class DocumentListBlock extends DocumentBlock {
  DocumentListBlock({
    required this.ordered,
    required List<List<DocumentInline>> items,
  }) : items = List.unmodifiable(items);

  final bool ordered;
  final List<List<DocumentInline>> items;
}

final class DocumentCodeBlock extends DocumentBlock {
  const DocumentCodeBlock(this.text);

  final String text;
}

final class DocumentQuoteBlock extends DocumentBlock {
  DocumentQuoteBlock({required List<DocumentInline> runs})
    : runs = List.unmodifiable(runs);

  final List<DocumentInline> runs;
}

final class DocumentThematicBreak extends DocumentBlock {
  const DocumentThematicBreak();
}

/// A restricted document: the ordered block list, plus optional title
/// metadata for containers.
class RestrictedDocument {
  RestrictedDocument({required List<DocumentBlock> blocks, this.title})
    : blocks = List.unmodifiable(blocks);

  final List<DocumentBlock> blocks;
  final String? title;
}
