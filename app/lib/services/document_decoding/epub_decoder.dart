import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;

/// Upper bound on the total decompressed size of one EPUB, guarding against
/// decompression bombs (independent of the source byte cap).
const int maxEpubDecompressedBytes = 1 << 26;

/// Upper bound on the number of spine items decoded for text extraction.
const int maxEpubSpineItems = 512;

/// A decoded EPUB: the preserved container facts plus the spine's chapters in
/// reading order. Only the chapter HTML and title are exposed; every decoded
/// string is plain untrusted content for the restricted renderer.
class EpubDocument {
  EpubDocument({required this.title, required List<EpubChapter> chapters})
    : chapters = List.unmodifiable(chapters);

  final String? title;
  final List<EpubChapter> chapters;
}

/// One EPUB spine chapter in reading order.
class EpubChapter {
  const EpubChapter({required this.title, required this.html});

  final String? title;
  final String html;
}

/// Decodes EPUB container bytes against OCF 2.0.1 facts.
///
/// Pure Dart and fully deterministic: zip validation, `mimetype` verification,
/// `container.xml` rootfile resolution, `content.opf` manifest/spine reading,
/// and spine-ordered chapter extraction. A corrupt, encrypted, or path-
/// escaping archive throws [EpubDecodeFailure] and creates no half-valid
/// result.
class EpubDecoder {
  const EpubDecoder();

  EpubDocument decode(List<int> bytes) {
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4B ||
        bytes[2] != 0x03 ||
        bytes[3] != 0x04) {
      throw const EpubDecodeFailure('not a ZIP archive');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Exception {
      throw const EpubDecodeFailure('ZIP container is corrupt or encrypted');
    }
    _validateContainer(archive);
    final rootfile = _rootfilePath(archive);
    final opf = _file(archive, rootfile, 'container.xml rootfile');
    // Manifest hrefs are relative to the OPF's own directory.
    final opfDirectory = _directoryOf(rootfile);
    final (manifest, spineOrder) = _readOpf(
      utf8.decode(opf.content, allowMalformed: true),
    );
    final title = _readTitle(opf.content);
    final chapters = <EpubChapter>[];
    var decompressedBytes = 0;
    var extracted = 0;
    for (final idref in spineOrder) {
      final href = manifest[idref];
      if (href == null) continue;
      final path = _joinHref(opfDirectory, href);
      final file = _file(archive, path, 'spine item "$idref"');
      final chapter = utf8.decode(file.content, allowMalformed: true);
      decompressedBytes += chapter.length * 2;
      if (decompressedBytes > maxEpubDecompressedBytes) {
        throw const EpubDecodeFailure('EPUB exceeds the decompressed bound');
      }
      chapters.add(
        EpubChapter(
          title: _chapterTitle(chapter),
          html: chapter,
        ),
      );
      if (++extracted >= maxEpubSpineItems) break;
    }
    if (chapters.isEmpty) {
      throw const EpubDecodeFailure('EPUB has no readable spine items');
    }
    return EpubDocument(title: title, chapters: chapters);
  }

  /// The spine's chapters as one plain-text reading string (headings and
  /// paragraphs joined by line breaks), for the Document Rendition's inline
  /// text. Rendering never uses this — it renders the original chapter HTML.
  static String spineText(EpubDocument document) {
    final buffer = StringBuffer();
    for (final chapter in document.chapters) {
      if (chapter.title != null) {
        buffer.writeln(chapter.title!);
      }
      buffer.writeln(_htmlToText(chapter.html));
    }
    return buffer.toString();
  }

  static String _htmlToText(String html) {
    final document = html_parser.parse(html);
    final buffer = StringBuffer();
    for (final block in [
      ...document.querySelectorAll('h1,h2,h3,h4,h5,h6,p,li,blockquote,pre'),
    ]) {
      buffer.writeln(block.text);
    }
    return buffer.toString();
  }

  static String? _chapterTitle(String chapterHtml) {
    final document = html_parser.parse(chapterHtml);
    return document.querySelector('h1,h2,h3,title')?.text;
  }

  static String? _readTitle(List<int> opfBytes) {    final opf = utf8.decode(opfBytes, allowMalformed: true);
    final document = html_parser.parse(opf);
    return document.querySelector('dc\\:title, title')?.text;
  }

  void _validateContainer(Archive archive) {
    final mimetype = archive.findFile('mimetype');
    if (mimetype == null || !mimetype.isFile) {
      throw const EpubDecodeFailure('EPUB is missing its mimetype entry');
    }
    final declared = utf8
        .decode(mimetype.content, allowMalformed: true)
        .trim();
    if (declared != 'application/epub+zip') {
      throw EpubDecodeFailure(
        'EPUB declares a non-EPUB mimetype "$declared"',
      );
    }
  }

  String _rootfilePath(Archive archive) {
    final container = _file(archive, 'META-INF/container.xml', 'container.xml');
    final document = html_parser.parse(
      utf8.decode(container.content, allowMalformed: true),
    );
    final rootfile = document.querySelector('rootfile');
    final path = rootfile?.attributes['full-path'];
    if (path == null || path.trim().isEmpty) {
      throw const EpubDecodeFailure('container.xml declares no rootfile');
    }
    return path;
  }

  /// Returns the OPF's manifest (id -> href) and the spine order (idrefs).
  (Map<String, String>, List<String>) _readOpf(String opf) {
    final document = html_parser.parse(opf);
    final manifest = <String, String>{};
    // Descendant selector, not `>`: the html5 parser mishandles sibling
    // self-closing XML elements under a child combinator.
    for (final item in document.querySelectorAll('manifest item')) {
      final id = item.attributes['id'];
      final href = item.attributes['href'];
      if (id != null && href != null) manifest[id] = href;
    }
    final spine = document.querySelector('spine');
    final order = <String>[];
    if (spine != null) {
      for (final ref in spine.querySelectorAll('itemref')) {
        final idref = ref.attributes['idref'];
        if (idref != null) order.add(idref);
      }
    }
    return (manifest, order);
  }

  /// Resolves [path] inside the archive with traversal protection: the
  /// normalized name must stay inside the package root.
  ArchiveFile _file(Archive archive, String path, String what) {
    final normalized = _normalize(path);
    final file = archive.findFile(normalized);
    if (file == null || !file.isFile) {
      throw EpubDecodeFailure('EPUB $what "$path" is missing');
    }
    return file;
  }

  /// Normalizes an entry name and rejects escapes: no absolute paths, no
  /// `..` traversal, no backslash tricks.
  static String _normalize(String path) {
    final parts = <String>[];
    for (final part in path.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        throw const EpubDecodeFailure('EPUB entry escapes the package root');
      }
      parts.add(part);
    }
    if (parts.isEmpty) {
      throw const EpubDecodeFailure('EPUB entry name is empty');
    }
    return parts.join('/');
  }

  /// The directory part of a package-relative path (`OEBPS/content.opf` ->
  /// `OEBPS`; a bare name -> empty).
  static String _directoryOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  /// Resolves a manifest href (relative to the OPF directory) into a
  /// package-relative path, with the same traversal protection.
  static String _joinHref(String opfDirectory, String href) {
    if (href.startsWith('/')) return _normalize(href.substring(1));
    return opfDirectory.isEmpty
        ? _normalize(href)
        : _normalize('$opfDirectory/$href');
  }
}

/// A typed EPUB decode failure. The message is a stable diagnostic; it is
/// never rendered as user-facing prose.
final class EpubDecodeFailure implements Exception {
  const EpubDecodeFailure(this.message);

  final String message;

  @override
  String toString() => 'EpubDecodeFailure: $message';
}

/// Strips the heading/paragraph text of [html] (untrusted content) into one
/// plain reading string. Used by intake for the inline rendition text; the
/// restricted renderer never sees the raw markup.
String htmlToPlainText(String html) {
  final document = html_parser.parse(html);
  final buffer = StringBuffer();
  for (final element in document.querySelectorAll('body *')) {
    buffer.write(element.text);
    buffer.write('\n');
  }
  return buffer.toString();
}

/// The first heading of an HTML document, used as a fallback title.
String? htmlHeading(String html) {
  final document = html_parser.parse(html);
  return document.querySelector('h1,h2,h3,title')?.text;
}
