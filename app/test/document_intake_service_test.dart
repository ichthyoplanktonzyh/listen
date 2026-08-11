import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/document_session_controller.dart';
import 'package:llplayer_next/models/document_session.dart';

import 'package:llplayer_next/services/document_intake_service.dart';

import 'support/document_session_test_fakes.dart';

void main() {
  const codec = LocalDocumentIntakeCodec();

  group('DocumentIntakeCodec', () {
    test('decodes plain UTF-8 text exactly', () {
      final input = codec.decodeDocumentText(
        bytes: utf8.encode('Hello, world.'),
        title: 't',
      );

      expect(input.title, 't');
      expect(input.text, 'Hello, world.');
    });

    test('strips exactly one UTF-8 BOM', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('Hello')];

      final input = codec.decodeDocumentText(bytes: bytes, title: 't');

      expect(input.text, 'Hello');
    });

    test('keeps non-ASCII multilingual text', () {
      final text = '中文段落。\n日本語の段落。\nРусский текст.';
      final input = codec.decodeDocumentText(
        bytes: utf8.encode(text),
        title: 't',
      );

      expect(input.text, text);
    });

    test('preserves newlines and trailing spaces', () {
      // Line breaks and trailing whitespace are content: only a BOM may be
      // removed, and the stored text is never trimmed.
      final text = 'first line  \n\nsecond line\t\nthird line   ';
      final input = codec.decodeDocumentText(
        bytes: utf8.encode(text),
        title: 't',
      );

      expect(input.text, text);
    });

    test('rejects whitespace-only content as emptyDocument', () {
      expect(
        () => codec.decodeDocumentText(
          bytes: utf8.encode('  \n\t \n'),
          title: 't',
        ),
        throwsA(
          isA<DocumentIntakeFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentIntakeFailureKind.emptyDocument,
          ),
        ),
      );
    });

    test('rejects invalid UTF-8 as invalidUtf8', () {
      // 0xFF is never valid UTF-8.
      expect(
        () => codec.decodeDocumentText(
          bytes: [0x48, 0x69, 0xFF, 0x21],
          title: 't',
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

    test('rejects content over 1 MiB as tooLarge', () {
      expect(
        () => codec.decodeDocumentText(
          bytes: List<int>.filled(maxDocumentBytes + 1, 0x41),
          title: 't',
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

    test('a BOM alone still yields an empty document', () {
      expect(
        () => codec.decodeDocumentText(bytes: [0xEF, 0xBB, 0xBF], title: 't'),
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

  group('titleFromFileName', () {
    test('strips one trailing .txt', () {
      expect(titleFromFileName('my notes.txt'), 'my notes');
      expect(titleFromFileName('README.TXT'), 'README');
    });

    test('leaves only the last .txt suffix off', () {
      expect(titleFromFileName('notes.txt.txt'), 'notes.txt');
    });

    test('keeps names without the suffix', () {
      expect(titleFromFileName('report'), 'report');
    });
  });

  group('file intake through the controller', () {
    test(
      'a cancelled picker keeps the session idle, creating nothing',
      () async {
        final repo = FakeLearningMaterialRepository();
        final files = FakeDocumentIntakeFileService([
          const DocumentFileCancelled(),
        ]);
        final controller = DocumentSessionController(
          materialRepository: repo,
          fileService: files,
          codec: codec,
        );
        addTearDown(controller.dispose);

        await controller.openFile();

        expect(controller.state, isA<DocumentSessionIdle>());
        expect(repo.createCalls, 0);
      },
    );

    test('an unreadable file is a typed unreadable failure', () async {
      final repo = FakeLearningMaterialRepository();
      final files = FakeDocumentIntakeFileService([
        const DocumentFileFailure(
          DocumentIntakeFailure(DocumentIntakeFailureKind.unreadable),
        ),
      ]);
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: files,
        codec: codec,
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

    test(
      'a too-large file is a typed tooLarge failure before any read',
      () async {
        final repo = FakeLearningMaterialRepository();
        final files = FakeDocumentIntakeFileService([
          const DocumentFileFailure(
            DocumentIntakeFailure(DocumentIntakeFailureKind.tooLarge),
          ),
        ]);
        final controller = DocumentSessionController(
          materialRepository: repo,
          fileService: files,
          codec: codec,
        );
        addTearDown(controller.dispose);

        await controller.openFile();

        expect(
          controller.state,
          isA<DocumentSessionFailed>().having(
            (failed) => failed.failure.kind,
            'kind',
            DocumentSessionFailureKind.tooLarge,
          ),
        );
        expect(repo.createCalls, 0);
      },
    );

    test('the full path never reaches the session or its title', () async {
      final repo = FakeLearningMaterialRepository();
      final files = FakeDocumentIntakeFileService([
        DocumentFileData(
          path: '/private/secret folder/some 中文.txt',
          bytes: utf8.encode('Body text.'),
        ),
      ]);
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: files,
        codec: codec,
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      // The title is the basename minus .txt — no directory, no extension.
      expect(repo.lastCreateInput?.title, 'some 中文');
      final ready = controller.state as DocumentSessionReady;
      expect(ready.details.currentRevision.title, 'some 中文');
      expect(ready.documentAsset.text, 'Body text.');
      expect(repo.lastCreateInput?.title, isNot(contains('/private')));
      expect(repo.lastCreateInput?.title, isNot(contains('secret')));
    });
  });
}
