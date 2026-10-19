import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/document_session_controller.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/document_session.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/document_decoding/document_format.dart';
import 'package:llplayer_next/services/document_intake_flow.dart';
import 'package:llplayer_next/services/document_intake_service.dart';
import 'package:llplayer_next/services/document_source_resolver.dart';

import 'support/document_session_test_fakes.dart';
import 'support/learning_material_fixtures.dart';

class _FakePdfTextExtractor implements PdfTextExtractor {
  _FakePdfTextExtractor({this.text});

  final String? text;

  @override
  Future<String?> extractText(List<int> bytes) async => text;
}

void main() {
  final codec = LocalDocumentIntakeCodec(
    pdfTextExtractor: _FakePdfTextExtractor(text: 'Extracted PDF text'),
  );

  Future<DocumentIntakeInput> decode(
    String text,
    DocumentFormat format,
  ) => codec.decodeDocument(
    bytes: utf8.encode(text),
    title: 't',
    format: format,
  );

  group('DocumentIntakeCodec · plain text and markdown', () {
    test('decodes plain UTF-8 text exactly', () async {
      final input = await decode('Hello, world.', DocumentFormat.plainText);

      expect(input.title, 't');
      expect(input.text, 'Hello, world.');
      expect(input.mediaType, 'text/plain');
      expect(input.byteLength, utf8.encode('Hello, world.').length);
      expect(input.sha256Digest, hasLength(64));
    });

    test('strips exactly one UTF-8 BOM', () async {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('Hello')];

      final input = await codec.decodeDocument(
        bytes: bytes,
        title: 't',
        format: DocumentFormat.plainText,
      );

      expect(input.text, 'Hello');
    });

    test('keeps non-ASCII multilingual text', () async {
      final text = '中文段落。\n日本語の段落。\nРусский текст.';

      final input = await decode(text, DocumentFormat.plainText);

      expect(input.text, text);
    });

    test('markdown keeps its source markup exactly', () async {
      final source = '# Title\n\n**bold** and `code`.\n';

      final input = await decode(source, DocumentFormat.markdown);

      expect(input.text, source);
      expect(input.mediaType, 'text/markdown');
    });

    test('rejects whitespace-only content as emptyDocument', () async {
      await expectLater(
        decode('  \n\t \n', DocumentFormat.plainText),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.emptyDocument,
          ),
        ),
      );
    });

    test('rejects invalid UTF-8 as invalidUtf8', () async {
      await expectLater(
        codec.decodeDocument(
          bytes: [0x48, 0x69, 0xFF, 0x21],
          title: 't',
          format: DocumentFormat.plainText,
        ),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.invalidUtf8,
          ),
        ),
      );
    });

    test('rejects text over 1 MiB as tooLarge', () async {
      await expectLater(
        codec.decodeDocument(
          bytes: List<int>.filled(maxTextDocumentBytes + 1, 0x41),
          title: 't',
          format: DocumentFormat.plainText,
        ),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.tooLarge,
          ),
        ),
      );
    });
  });

  group('DocumentIntakeCodec · html', () {
    test('keeps the exact source markup as the rendition text', () async {
      final source = '<html><body><h1>Hi</h1><p>Body.</p></body></html>';

      final input = await decode(source, DocumentFormat.html);

      expect(input.text, source);
      expect(input.mediaType, 'text/html');
    });

    test('rejects markup-only html as emptyDocument', () async {
      await expectLater(
        decode('<html><body><div></div></body></html>', DocumentFormat.html),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.emptyDocument,
          ),
        ),
      );
    });
  });

  group('DocumentIntakeCodec · epub', () {
    test('accepts a minimal valid EPUB and extracts spine text', () async {
      final bytes = _epubBytes();

      final input = await codec.decodeDocument(
        bytes: bytes,
        title: 'Book',
        format: DocumentFormat.epub,
      );

      expect(input.mediaType, 'application/epub+zip');
      expect(input.text, contains('Chapter one text'));
      expect(input.text, contains('Chapter two text'));
    });

    test('rejects non-zip bytes as corrupt', () async {
      await expectLater(
        decode('this is not an epub at all', DocumentFormat.epub),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.corrupt,
          ),
        ),
      );
    });

    test('rejects a zip without the epub mimetype as corrupt', () async {
      final bytes = _zipBytes({});
      await expectLater(
        codec.decodeDocument(
          bytes: bytes,
          title: 'Book',
          format: DocumentFormat.epub,
        ),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.corrupt,
          ),
        ),
      );
    });
  });

  group('DocumentIntakeCodec · pdf', () {
    test('accepts a text-layer PDF and carries the extracted text', () async {
      final bytes = _pdfBytes();

      final input = await codec.decodeDocument(
        bytes: bytes,
        title: 'Doc',
        format: DocumentFormat.pdf,
      );

      expect(input.mediaType, 'application/pdf');
      expect(input.text, 'Extracted PDF text');
    });

    test('a scanned PDF carries no rendition text', () async {
      final textless = LocalDocumentIntakeCodec(
        pdfTextExtractor: _FakePdfTextExtractor(),
      );
      final input = await textless.decodeDocument(
        bytes: _pdfBytes(),
        title: 'Doc',
        format: DocumentFormat.pdf,
      );

      expect(input.text, isNull);
      expect(input.byteLength, greaterThan(0));
    });

    test('rejects non-pdf bytes as corrupt', () async {
      await expectLater(
        decode('not a pdf', DocumentFormat.pdf),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.corrupt,
          ),
        ),
      );
    });

    test('rejects an encrypted PDF as encrypted', () async {
      final encrypted = <int>[
        ...utf8.encode('%PDF-1.7\n1 0 obj\n<< /Encrypt 1 0 R >>\n%%EOF'),
        ..._pdfBytes(),
      ];
      await expectLater(
        codec.decodeDocument(
          bytes: encrypted,
          title: 'Doc',
          format: DocumentFormat.pdf,
        ),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.encrypted,
          ),
        ),
      );
    });

    test('rejects an unsupported header as corrupt', () async {
      await expectLater(
        codec.decodeDocument(
          bytes: utf8.encode('%PDF-9.9\n%%EOF'),
          title: 'Doc',
          format: DocumentFormat.pdf,
        ),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.corrupt,
          ),
        ),
      );
    });
  });

  group('document format dispatch', () {
    test('formatForPath maps every supported extension', () {
      expect(formatForPath('a.txt'), DocumentFormat.plainText);
      expect(formatForPath('a.md'), DocumentFormat.markdown);
      expect(formatForPath('a.markdown'), DocumentFormat.markdown);
      expect(formatForPath('a.html'), DocumentFormat.html);
      expect(formatForPath('a.HTM'), DocumentFormat.html);
      expect(formatForPath('a.epub'), DocumentFormat.epub);
      expect(formatForPath('a.pdf'), DocumentFormat.pdf);
    });

    test('formatForPath rejects unknown and extensionless files', () {
      expect(formatForPath('a.exe'), isNull);
      expect(formatForPath('README'), isNull);
      expect(formatForPath('a.txt.bak'), isNull);
    });

    test('titleFromFileName strips one trailing recognized extension', () {
      expect(titleFromFileName('my notes.txt'), 'my notes');
      expect(titleFromFileName('README.TXT'), 'README');
      expect(titleFromFileName('chapter.md'), 'chapter');
      expect(titleFromFileName('book.epub'), 'book');
      expect(titleFromFileName('notes.txt.txt'), 'notes.txt');
      expect(titleFromFileName('report'), 'report');
    });
  });

  group('file intake through the controller', () {
    DocumentSessionController controllerWith({
      required FakeLearningMaterialRepository repo,
      required List<DocumentFileRead> results,
      DocumentIntakeCodec? codec,
      FakeManagedAssetStoreService? store,
      FakeDocumentReferenceStore? references,
      FakeDocumentSourceResolver? resolver,
      bool referenceInPlace = false,
    }) {
      final referenceStore = references ?? FakeDocumentReferenceStore();
      return DocumentSessionController(
        materialRepository: repo,
        fileService: FakeDocumentIntakeFileService(results),
        intakeFlow: DocumentIntakeFlow(
          materialRepository: repo,
          codec: codec ?? LocalDocumentIntakeCodec(
            pdfTextExtractor: _FakePdfTextExtractor(),
          ),
          store: store ?? FakeManagedAssetStoreService(),
          referenceStore: referenceStore,
        ),
        sourceResolver: resolver ?? FakeDocumentSourceResolver(),
        referenceInPlace: referenceInPlace,
      );
    }

    test(
      'a cancelled picker keeps the session idle, creating nothing',
      () async {
        final repo = FakeLearningMaterialRepository();
        final controller = controllerWith(
          repo: repo,
          results: [const DocumentFileCancelled()],
        );
        addTearDown(controller.dispose);

        await controller.openFile();

        expect(controller.state, isA<DocumentSessionIdle>());
        expect(repo.createCalls, 0);
      },
    );

    test('an unreadable file is a typed unreadable failure', () async {
      final repo = FakeLearningMaterialRepository();
      final controller = controllerWith(
        repo: repo,
        results: [
          const DocumentFileFailure(
            DocumentIntakeFailure(DocumentIntakeFailureKind.unreadable),
          ),
        ],
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      final state = controller.state;
      expect(
        state,
        isA<DocumentSessionFailed>().having(
          (failed) => failed.failure.kind,
          'kind',
          DocumentSessionFailureKind.unreadable,
        ),
      );
      expect(repo.createCalls, 0);
    });

    test('an unsupported extension is a typed unsupported failure', () async {
      final repo = FakeLearningMaterialRepository();
      final controller = controllerWith(
        repo: repo,
        results: [
          DocumentFileData(
            path: '/tmp/evil.exe',
            bytes: utf8.encode('nope'),
          ),
        ],
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      expect(
        controller.state,
        isA<DocumentSessionFailed>().having(
          (failed) => failed.failure.kind,
          'kind',
          DocumentSessionFailureKind.unsupported,
        ),
      );
      expect(repo.createCalls, 0);
    });

    test('the full path never reaches the session or its title', () async {
      final repo = FakeLearningMaterialRepository();
      final controller = controllerWith(
        repo: repo,
        results: [
          DocumentFileData(
            path: '/private/secret folder/some 中文.txt',
            bytes: utf8.encode('Body text.'),
          ),
        ],
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      // The title is the basename minus .txt — no directory, no extension.
      expect(repo.lastCreateInput?.title, 'some 中文');
      final ready = controller.state as DocumentSessionReady;
      expect(ready.details.currentRevision.title, 'some 中文');
      expect(ready.documentRendition?.digest, hasLength(64));
      expect(
        ready.documentRendition?.byteSize,
        utf8.encode('Body text.').length,
      );
      expect(repo.lastCreateInput?.title, isNot(contains('/private')));
      expect(repo.lastCreateInput?.title, isNot(contains('secret')));
    });

    test('intake registers the source asset with exact byte facts', () async {
      final repo = FakeLearningMaterialRepository();
      final store = FakeManagedAssetStoreService();
      final controller = controllerWith(
        repo: repo,
        store: store,
        results: [
          DocumentFileData(
            path: '/tmp/doc.txt',
            bytes: utf8.encode('Body text.'),
          ),
        ],
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      expect(repo.lastCreateInput?.sourceAssets, hasLength(1));
      final source = repo.lastCreateInput!.sourceAssets.single;
      expect(source.mediaType, 'text/plain');
      expect(source.byteLength, utf8.encode('Body text.').length);
      expect(source.sha256Digest, hasLength(64));
      expect(source.binding.type, SourceAssetBindingType.managed);
      expect(
        repo.lastCreateInput?.documentRenditions.single.digest,
        source.sha256Digest,
      );
      expect(
        repo.lastCreateInput?.documentRenditions.single.byteSize,
        source.byteLength,
      );
      expect(repo.lastCreateInput?.documentRenditions.single.sourceAssetIndex, 0);
      // The managed copy was verified before the create.
      expect(store.copyCalls, 1);
    });

    test('reference in place binds the app-owned reference key', () async {
      final repo = FakeLearningMaterialRepository();
      final references = FakeDocumentReferenceStore();
      final controller = controllerWith(
        repo: repo,
        references: references,
        results: [
          DocumentFileData(
            path: '/mnt/notes.md',
            bytes: utf8.encode('# Note'),
          ),
        ],
        referenceInPlace: true,
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      final source = repo.lastCreateInput!.sourceAssets.single;
      expect(source.binding.type, SourceAssetBindingType.referenced);
      expect(source.binding.reference, source.sha256Digest);
      expect(references.references[source.sha256Digest], '/mnt/notes.md');
    });

    test('a failed create rolls back its fresh store copy', () async {
      final repo = FakeLearningMaterialRepository()
        ..createFailure = ApiFailure(raw: 'create failed', correlationId: 'x');
      final store = FakeManagedAssetStoreService();
      final controller = controllerWith(
        repo: repo,
        store: store,
        results: [
          DocumentFileData(
            path: '/tmp/doc.txt',
            bytes: utf8.encode('Body text.'),
          ),
        ],
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      expect(store.contents, isEmpty);
      expect(
        controller.state,
        isA<DocumentSessionFailed>().having(
          (failed) => failed.failure.kind,
          'kind',
          DocumentSessionFailureKind.apiFailure,
        ),
      );
    });

    test('a failed create drops the reference mapping', () async {
      final repo = FakeLearningMaterialRepository()
        ..createFailure = ApiFailure(raw: 'create failed', correlationId: 'x');
      final references = FakeDocumentReferenceStore();
      final controller = controllerWith(
        repo: repo,
        references: references,
        results: [
          DocumentFileData(
            path: '/mnt/notes.md',
            bytes: utf8.encode('# Note'),
          ),
        ],
        referenceInPlace: true,
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      expect(references.references, isEmpty);
    });

    test('a scanned PDF opens ready with its rendition bound to the source',
        () async {
      final repo = FakeLearningMaterialRepository()
        ..onCreate = (input) => materialDetails(
          title: input.title,
          sourceAssets: [
            for (final asset in input.sourceAssets)
              sourceAsset(
                mediaType: asset.mediaType,
                sha256Digest: asset.sha256Digest,
              ),
          ],
          documentRenditions: [
            // Core 4.0 binds the Source Document Rendition to the exact
            // Source Asset bytes: same digest, same size.
            for (final rendition in input.documentRenditions)
              documentRendition(
                mediaType: rendition.mediaType,
                digest: rendition.digest,
                byteSize: rendition.byteSize,
                sourceAssetId: input.sourceAssets.single.sha256Digest,
              ),
          ],
          retainedAtMs: null,
        );
      final textless = LocalDocumentIntakeCodec(
        pdfTextExtractor: _FakePdfTextExtractor(),
      );
      final files = FakeDocumentIntakeFileService([
        DocumentFileData(
          path: '/tmp/scan.pdf',
          bytes: _pdfBytes(),
        ),
      ]);
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: files,
        intakeFlow: DocumentIntakeFlow(
          materialRepository: repo,
          codec: textless,
          store: FakeManagedAssetStoreService(),
          referenceStore: FakeDocumentReferenceStore(),
        ),
        sourceResolver: FakeDocumentSourceResolver(),
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      final ready = controller.state as DocumentSessionReady;
      expect(ready.documentRendition, isNotNull);
      expect(ready.documentRendition!.mediaType, 'application/pdf');
      expect(ready.sourceAsset, isNotNull);
      expect(ready.sourceAsset!.mediaType, 'application/pdf');
      expect(ready.sourceAsset!.sha256Digest, ready.documentRendition!.digest);
    });
  group('Keep verification through the controller', () {
    test('a failing managed-store copy fails honestly without creating',
        () async {
      final repo = FakeLearningMaterialRepository();
      final store = FakeManagedAssetStoreService()
        ..unavailable = true;
      final controller = controllerWith(
        repo: repo,
        store: store,
        results: [
          DocumentFileData(
            path: '/tmp/doc.txt',
            bytes: utf8.encode('Body text.'),
          ),
        ],
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      expect(repo.createCalls, 0);
      final state = controller.state as DocumentSessionFailed;
      expect(
        state.failure.kind,
        DocumentSessionFailureKind.apiFailure,
      );
    });

    test('a copied document resolves its bytes for direct rendering', () async {
      final repo = FakeLearningMaterialRepository();
      final store = FakeManagedAssetStoreService();
      final resolver = FakeDocumentSourceResolver()
        ..result = DocumentSourceAvailable(utf8.encode('Body text.'));
      final controller = controllerWith(
        repo: repo,
        store: store,
        resolver: resolver,
        results: [
          DocumentFileData(
            path: '/tmp/doc.txt',
            bytes: utf8.encode('Body text.'),
          ),
        ],
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      final ready = controller.state as DocumentSessionReady;
      final resolved = await controller.resolveSourceBytes(ready.sourceAsset!);
      expect(resolved, isA<DocumentSourceAvailable>());
    });

    test('a referenced file that disappeared resolves unavailable', () async {
      final repo = FakeLearningMaterialRepository();
      final references = FakeDocumentReferenceStore();
      final resolver = FakeDocumentSourceResolver();
      final controller = controllerWith(
        repo: repo,
        references: references,
        resolver: resolver,
        results: [
          DocumentFileData(
            path: '/mnt/notes.md',
            bytes: utf8.encode('# Note'),
          ),
        ],
        referenceInPlace: true,
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      final ready = controller.state as DocumentSessionReady;
      final resolved = await controller.resolveSourceBytes(ready.sourceAsset!);
      expect(resolved, isA<DocumentSourceUnavailable>());
    });
  });
  });
}

/// Builds a minimal valid EPUB: mimetype, container.xml, one OPF, two spine
/// chapters.
List<int> _epubBytes() {
  final zip = ZipBuilderFixture();
  zip.add('mimetype', 'application/epub+zip');
  zip.add(
    'META-INF/container.xml',
    '<?xml version="1.0"?>'
    '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  zip.add(
    'OEBPS/content.opf',
    '<?xml version="1.0"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
    '<metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Book</dc:title></metadata>'
    '<manifest>'
    '<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>'
    '</manifest>'
    '<spine><itemref idref="c1"/><itemref idref="c2"/></spine>'
    '</package>',
  );
  zip.add(
    'OEBPS/chapter1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title></head>'
    '<body><h1>Chapter one</h1><p>Chapter one text here.</p></body></html>',
  );
  zip.add(
    'OEBPS/chapter2.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Two</title></head>'
    '<body><h1>Chapter two</h1><p>Chapter two text here.</p></body></html>',
  );
  return zip.bytes();
}

/// Builds a minimal single-entry zip for negative tests.
List<int> _zipBytes(Map<String, String> entries) {
  final zip = ZipBuilderFixture();
  for (final entry in entries.entries) {
    zip.add(entry.key, entry.value);
  }
  return zip.bytes();
}

/// A minimal PDF that passes the header/EOF checks; the text layer comes from
/// the injected extractor.
List<int> _pdfBytes() => utf8.encode('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF');

/// Tiny ZIP builder for fixtures (stored entries only, deterministic bytes).
class ZipBuilderFixture {
  final _entries = <(String, List<int>)>[];

  void add(String name, String content) =>
      _entries.add((name, utf8.encode(content)));

  List<int> bytes() {
    final archive = Archive();
    for (final (name, content) in _entries) {
      archive.addFile(ArchiveFile(name, content.length, content));
    }
    final zip = ZipEncoder().encode(archive);
    return zip;
  }
}
