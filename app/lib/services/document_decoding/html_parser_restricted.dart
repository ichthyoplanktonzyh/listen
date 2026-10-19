import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'document_blocks.dart';

/// A restricted HTML parser.
///
/// Parses untrusted HTML through the tolerant `package:html` DOM parser and
/// maps an allowlist of structural elements onto the pure block model.
/// Everything outside the allowlist — scripts, styles, iframes, forms,
/// images, external references, event handlers — is discarded. The renderer
/// can therefore never execute, fetch, or navigate anything the input
/// declares. Links render as styled text with the destination dropped.
class RestrictedHtmlParser {
  const RestrictedHtmlParser();

  RestrictedDocument parse(String html) {
    final document = html_parser.parse(html);
    final blocks = <DocumentBlock>[];
    final title = document.querySelector('title')?.text;
    final body = document.body;
    if (body != null) {
      _walk(body, blocks);
    }
    return RestrictedDocument(blocks: blocks, title: title);
  }

  void _walk(dom.Element element, List<DocumentBlock> blocks) {
    for (final node in element.nodes) {
      if (node is dom.Element) {
        _element(node, blocks);
      } else if (node is dom.Text) {
        final text = node.text;
        if (text.trim().isNotEmpty) {
          blocks.add(DocumentParagraphBlock(runs: [DocumentTextRun(text)]));
        }
      }
    }
  }

  void _element(dom.Element element, List<DocumentBlock> blocks) {
    final tag = element.localName?.toLowerCase() ?? '';
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        blocks.add(
          DocumentHeadingBlock(
            level: int.parse(tag.substring(1)),
            text: _textOf(element),
          ),
        );
      case 'p':
        blocks.add(DocumentParagraphBlock(runs: _inlineRuns(element)));
      case 'ul' || 'ol':
        final items = <List<DocumentInline>>[];
        for (final node in element.nodes) {
          if (node is dom.Element && node.localName == 'li') {
            items.add(_inlineRuns(node));
          }
        }
        blocks.add(DocumentListBlock(ordered: tag == 'ol', items: items));
      case 'blockquote':
        final quoted = <DocumentBlock>[];
        _walk(element, quoted);
        if (quoted.isNotEmpty) {
          blocks.add(
            DocumentQuoteBlock(
              runs: [
                for (final block in quoted)
                  if (block is DocumentParagraphBlock) ...block.runs,
              ],
            ),
          );
        }
      case 'pre':
        final text = element.text.trim();
        if (text.isNotEmpty) blocks.add(DocumentCodeBlock(text));
      case 'hr':
        blocks.add(const DocumentThematicBreak());
      case 'br':
        // A bare break inside a paragraph context is dropped; paragraphs are
        // already split at their own boundaries.
        break;
      case 'script' ||
          'style' ||
          'iframe' ||
          'frame' ||
          'form' ||
          'input' ||
          'button' ||
          'select' ||
          'textarea' ||
          'img' ||
          'picture' ||
          'video' ||
          'audio' ||
          'source' ||
          'embed' ||
          'object' ||
          'canvas' ||
          'svg' ||
          'link' ||
          'meta' ||
          'base' ||
          'applet':
        // Active, fetching, or form content is never rendered.
        break;
      case 'div' || 'section' || 'article' || 'main' || 'header' || 'footer' ||
           'nav' || 'aside' || 'span' || 'body' || 'html':
        _walk(element, blocks);
      default:
        // Unknown elements degrade to their text.
        final text = _textOf(element);
        if (text.trim().isNotEmpty) {
          blocks.add(DocumentParagraphBlock(runs: [DocumentTextRun(text)]));
        }
    }
  }

  /// Inline runs from a paragraph-like element: emphasis and code become
  /// styled runs; links render as styled text with the destination dropped.
  static List<DocumentInline> _inlineRuns(dom.Element element) {
    final runs = <DocumentInline>[];
    void walk(dom.Node node) {
      if (node is dom.Text) {
        final text = node.text;
        if (text.isNotEmpty) runs.add(DocumentTextRun(text));
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName?.toLowerCase() ?? '';
      switch (tag) {
        case 'strong' || 'b':
          final text = _textOf(node);
          if (text.isNotEmpty) runs.add(DocumentBoldRun(text));
        case 'em' || 'i':
          final text = _textOf(node);
          if (text.isNotEmpty) runs.add(DocumentItalicRun(text));
        case 'code':
          final text = _textOf(node);
          if (text.isNotEmpty) runs.add(DocumentCodeRun(text));
        case 'a':
          final text = _textOf(node);
          if (text.isNotEmpty) runs.add(DocumentLinkRun(text));
        case 'br':
        default:
          for (final child in node.nodes) {
            walk(child);
          }
      }
    }

    for (final node in element.nodes) {
      walk(node);
    }
    return runs;
  }

  static String _textOf(dom.Element element) => element.text;
}
