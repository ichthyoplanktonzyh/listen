import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/document_decoding/document_blocks.dart';
import 'package:llplayer_next/services/document_decoding/epub_decoder.dart';
import 'package:llplayer_next/services/document_decoding/html_parser_restricted.dart';
import 'package:llplayer_next/services/document_decoding/markdown_parser.dart';

/// Restricted-rendering security and structure tests: untrusted Markdown,
/// HTML, and EPUB input can reach exactly the pure block model — never a
/// script, network, image, or form context.
void main() {
  group('RestrictedHtmlParser', () {
    const parser = RestrictedHtmlParser();

    test('maps the structural allowlist onto blocks', () {
      const source = '<h1>Title</h1><p>Body <strong>bold</strong> and '
          '<em>italic</em> and <code>x</code>.</p>'
          '<ul><li>One</li><li>Two</li></ul>'
          '<blockquote><p>Quoted</p></blockquote>'
          '<pre>code()</pre><hr/>';

      final document = parser.parse(source);

      expect(document.blocks[0], isA<DocumentHeadingBlock>());
      final paragraph = document.blocks[1] as DocumentParagraphBlock;
      expect(paragraph.runs, contains(isA<DocumentBoldRun>()));
      expect(paragraph.runs, contains(isA<DocumentItalicRun>()));
      expect(paragraph.runs, contains(isA<DocumentCodeRun>()));
      expect(document.blocks[2], isA<DocumentListBlock>());
      expect(document.blocks[3], isA<DocumentQuoteBlock>());
      expect(document.blocks[4], isA<DocumentCodeBlock>());
      expect(document.blocks[5], isA<DocumentThematicBreak>());
    });

    test('drops active content: script, style, iframe, img, form, object',
        () {
      const source = '<p>Safe</p>'
          '<script>alert("xss")</script>'
          '<style>body{display:none}</style>'
          '<iframe src="https://evil.example"></iframe>'
          '<img src="https://evil.example/pixel.png" onerror="steal()">'
          '<form action="https://evil.example/submit"><input type="text">'
          '</form>'
          '<object data="https://evil.example/x.swf"></object>'
          '<video src="https://evil.example/v.mp4"></video>'
          '<link rel="stylesheet" href="https://evil.example/s.css">'
          '<meta http-equiv="refresh" content="0;url=https://evil.example">'
          '<svg onload="alert(1)"><circle/></svg>'
          '<p>After</p>';

      final document = parser.parse(source);

      final texts = document.blocks
          .whereType<DocumentParagraphBlock>()
          .map((block) => block.runs)
          .toList();
      // Only the two safe paragraphs survive; nothing from the active tags
      // is rendered as text.
      expect(texts, hasLength(2));
      expect(texts[0], [isA<DocumentTextRun>()]);
      expect(texts[1], [isA<DocumentTextRun>()]);
      expect(
        texts.map((runs) => runs.joinToString()).join(' | '),
        isNot(contains('alert')),
      );
      expect(
        texts.map((runs) => runs.joinToString()).join(' | '),
        isNot(contains('evil')),
      );
    });

    test('links render as styled text; destinations never survive', () {
      const source = '<p>See <a href="https://evil.example/path?q=1">'
          'the notes</a> now.</p>';

      final document = parser.parse(source);

      final runs = (document.blocks.single as DocumentParagraphBlock).runs;
      expect(runs, contains(isA<DocumentLinkRun>()));
      final link = runs.whereType<DocumentLinkRun>().single;
      expect(link.text, 'the notes');
      expect(runs.joinToString(), isNot(contains('evil')));
    });

    test('unknown elements degrade to plain text', () {
      const source = '<p>Before <custom-tag>inner</custom-tag> after</p>';

      final document = parser.parse(source);

      final runs = (document.blocks.single as DocumentParagraphBlock).runs;
      expect(runs.joinToString(), contains('inner'));
    });
  });

  group('MarkdownParser', () {
    const parser = MarkdownParser();

    test('parses headings, lists, quotes, code, and thematic breaks', () {
      const source = '# Title\n\n## Sub\n\n- one\n- two\n\n1. first\n'
          '2. second\n\n> quoted\n\n```\ncode here\n```\n\n---\n';

      final document = parser.parse(source);

      expect(document.blocks[0], isA<DocumentHeadingBlock>());
      expect((document.blocks[0] as DocumentHeadingBlock).level, 1);
      expect((document.blocks[1] as DocumentHeadingBlock).level, 2);
      expect(document.blocks[2], isA<DocumentListBlock>());
      expect((document.blocks[2] as DocumentListBlock).ordered, isFalse);
      expect(document.blocks[3], isA<DocumentListBlock>());
      expect((document.blocks[3] as DocumentListBlock).ordered, isTrue);
      expect(document.blocks[4], isA<DocumentQuoteBlock>());
      expect(document.blocks[5], isA<DocumentCodeBlock>());
      expect(document.blocks[6], isA<DocumentThematicBreak>());
    });

    test('link destinations are discarded', () {
      const source = 'See [notes](https://evil.example/x).';

      final document = parser.parse(source);

      final runs = (document.blocks.single as DocumentParagraphBlock).runs;
      expect(runs, contains(isA<DocumentLinkRun>()));
      expect(runs.joinToString(), isNot(contains('evil')));
    });

    test('unknown markup becomes plain text, never markup', () {
      const source = '<script>alert(1)</script> and plain words.';

      final document = parser.parse(source);

      final runs = (document.blocks.single as DocumentParagraphBlock).runs;
      expect(runs.joinToString(), contains('<script>alert(1)</script>'));
    });
  });

  group('EpubDecoder hardening', () {
    const decoder = EpubDecoder();

    test('rejects a path-escaping spine href', () {
      final zip = _Zip();
      zip.add('mimetype', 'application/epub+zip');
      zip.add(
        'META-INF/container.xml',
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
        '</container>',
      );
      zip.add(
        'OEBPS/content.opf',
        '<package><manifest><item id="c1" href="../../etc/passwd"/>'
        '</manifest><spine><itemref idref="c1"/></spine></package>',
      );
      zip.add('OEBPS/chapter1.xhtml', '<html><body><p>ok</p></body></html>');

      expect(
        () => decoder.decode(zip.bytes()),
        throwsA(isA<EpubDecodeFailure>()),
      );
    });

    test('rejects an absolute spine href outside the package', () {
      final zip = _Zip();
      zip.add('mimetype', 'application/epub+zip');
      zip.add(
        'META-INF/container.xml',
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="content.opf"/></rootfiles></container>',
      );
      zip.add(
        'content.opf',
        '<package><manifest><item id="c1" href="/etc/passwd"/>'
        '</manifest><spine><itemref idref="c1"/></spine></package>',
      );

      expect(
        () => decoder.decode(zip.bytes()),
        throwsA(isA<EpubDecodeFailure>()),
      );
    });

    test('rejects a zip whose mimetype is not an epub', () {
      final zip = _Zip();
      zip.add('mimetype', 'application/zip');
      zip.add('META-INF/container.xml', '<container/>');

      expect(
        () => decoder.decode(zip.bytes()),
        throwsA(isA<EpubDecodeFailure>()),
      );
    });
  });
}

extension on List<DocumentInline> {
  String joinToString() => map(
    (run) => switch (run) {
      DocumentTextRun(:final text) => text,
      DocumentBoldRun(:final text) => text,
      DocumentItalicRun(:final text) => text,
      DocumentCodeRun(:final text) => text,
      DocumentLinkRun(:final text) => text,
    },
  ).join();
}

/// Stored-only ZIP builder for decoder hardening tests.
class _Zip {
  final _entries = <(String, String)>[];

  void add(String name, String content) => _entries.add((name, content));

  List<int> bytes() {
    final archive = Archive();
    for (final (name, content) in _entries) {
      archive.addFile(ArchiveFile(name, content.length, utf8.encode(content)));
    }
    return ZipEncoder().encode(archive);
  }
}
