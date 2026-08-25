import 'document_blocks.dart';

/// A restricted Markdown parser.
///
/// Parses a safe subset — ATX headings, fenced and inline code, emphasis,
/// links (as styled text only), unordered/ordered lists, block quotes,
/// thematic breaks, and paragraphs — into [RestrictedDocument]. Everything the
/// subset does not understand becomes plain text; nothing here can reach a
/// network, filesystem, or script context.
class MarkdownParser {
  const MarkdownParser();

  RestrictedDocument parse(String source) {
    final lines = source.split('\n');
    final blocks = <DocumentBlock>[];
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        index += 1;
        continue;
      }
      final heading = _heading(trimmed);
      if (heading != null) {
        blocks.add(heading);
        index += 1;
        continue;
      }
      if (_isThematicBreak(trimmed)) {
        blocks.add(const DocumentThematicBreak());
        index += 1;
        continue;
      }
      if (trimmed.startsWith('```')) {
        final (code, next) = _fencedCode(lines, index);
        blocks.add(DocumentCodeBlock(code));
        index = next;
        continue;
      }
      if (_isListMarker(trimmed)) {
        final (ordered, items, next) = _list(lines, index);
        blocks.add(
          DocumentListBlock(
            ordered: ordered,
            items: [
              for (final item in items) _inlineRuns(item),
            ],
          ),
        );
        index = next;
        continue;
      }
      if (trimmed.startsWith('>')) {
        final (quote, next) = _quote(lines, index);
        blocks.add(DocumentQuoteBlock(runs: _inlineRuns(quote)));
        index = next;
        continue;
      }
      final (paragraph, next) = _paragraph(lines, index);
      blocks.add(DocumentParagraphBlock(runs: _inlineRuns(paragraph)));
      index = next;
    }
    return RestrictedDocument(blocks: blocks);
  }

  static DocumentHeadingBlock? _heading(String line) {
    final match = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (match == null) return null;
    return DocumentHeadingBlock(
      level: match.group(1)!.length,
      text: _inlineText(match.group(2)!),
    );
  }

  static bool _isThematicBreak(String line) =>
      RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line);

  static bool _isListMarker(String line) =>
      RegExp(r'^\s*(?:[-*+]|\d+\.)\s+').hasMatch(line);

  static (String, int) _fencedCode(List<String> lines, int start) {
    final buffer = StringBuffer();
    var index = start + 1;
    while (index < lines.length && !lines[index].trimLeft().startsWith('```')) {
      buffer.writeln(lines[index]);
      index += 1;
    }
    return (buffer.toString(), index + 1);
  }

  static (bool, List<String>, int) _list(List<String> lines, int start) {
    var index = start;
    var ordered = RegExp(r'^\s*\d+\.\s+').hasMatch(lines[index]);
    final items = <String>[];
    while (index < lines.length) {
      final line = lines[index];
      final marker = RegExp(
        ordered ? r'^\s*\d+\.\s+(.*)$' : r'^\s*[-*+]\s+(.*)$',
      );
      final match = marker.firstMatch(line);
      if (match == null) break;
      items.add(match.group(1)!);
      index += 1;
    }
    return (ordered, items, index);
  }

  static (String, int) _quote(List<String> lines, int start) {
    final buffer = StringBuffer();
    var index = start;
    while (index < lines.length &&
        lines[index].trimRight().startsWith('>')) {
      buffer.writeln(lines[index].trimRight().substring(1).trimLeft());
      index += 1;
    }
    return (buffer.toString(), index);
  }

  static (String, int) _paragraph(List<String> lines, int start) {
    final buffer = StringBuffer();
    var index = start;
    while (index < lines.length) {
      final line = lines[index].trimRight();
      if (line.isEmpty) break;
      if (_heading(line) != null) break;
      if (_isThematicBreak(line)) break;
      if (_isListMarker(line)) break;
      if (line.startsWith('>')) break;
      buffer.writeln(line);
      index += 1;
    }
    return (buffer.toString(), index);
  }

  /// Inline rendering: emphasis, code, and links become styled runs; the
  /// link destination is discarded and never dereferenced.
  static List<DocumentInline> _inlineRuns(String text) {
    final runs = <DocumentInline>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isNotEmpty) {
        runs.add(DocumentTextRun(buffer.toString()));
        buffer.clear();
      }
    }

    var index = 0;
    while (index < text.length) {
      final rest = text.substring(index);
      final code = RegExp(r'^`([^`]+)`').firstMatch(rest);
      if (code != null) {
        flush();
        runs.add(DocumentCodeRun(code.group(1)!));
        index += code.group(0)!.length;
        continue;
      }
      final link = RegExp(r'^\[([^\]]+)\]\([^)]*\)').firstMatch(rest);
      if (link != null) {
        flush();
        runs.add(DocumentLinkRun(link.group(1)!));
        index += link.group(0)!.length;
        continue;
      }
      final bold = RegExp(r'^\*\*([^*]+)\*\*').firstMatch(rest);
      if (bold != null) {
        flush();
        runs.add(DocumentBoldRun(bold.group(1)!));
        index += bold.group(0)!.length;
        continue;
      }
      final italic = RegExp(r'^\*([^*\n]+)\*').firstMatch(rest);
      if (italic != null) {
        flush();
        runs.add(DocumentItalicRun(italic.group(1)!));
        index += italic.group(0)!.length;
        continue;
      }
      buffer.write(text[index]);
      index += 1;
    }
    flush();
    return runs;
  }

  static String _inlineText(String text) => text
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
      .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
      .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')
      .replaceAll(RegExp(r'`([^`]+)`'), r'$1');
}
