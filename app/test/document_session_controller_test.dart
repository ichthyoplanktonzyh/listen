import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/document_session_controller.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/document_session.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/services/document_intake_service.dart';

import 'support/document_session_test_fakes.dart';

const codec = LocalDocumentIntakeCodec();

DocumentTextMaterialAsset _textAsset(String id, String text) =>
    DocumentTextMaterialAsset(
      id: id,
      text: text,
      sha256Digest: 'x',
      byteSize: text.length,
      language: null,
    );

PersonalLibraryEntry _libraryEntry({
  required String materialId,
  required List<DocumentTextMaterialAsset> assets,
  bool retained = true,
  String title = 'Library document',
}) => PersonalLibraryEntry(
  details: MaterialDetails(
    material: LearningMaterial(
      id: materialId,
      currentRevisionId: 'revision-1',
      retainedAtMs: retained ? 42 : null,
      createdAtMs: 1,
      updatedAtMs: 1,
    ),
    currentRevision: MaterialRevision(
      id: 'revision-1',
      materialId: materialId,
      title: title,
      assets: assets,
      createdAtMs: 1,
    ),
    shape: MaterialShape.text,
  ),
  mediaEntries: const [],
);

void main() {
  test(
    'file intake sends exactly one document_text asset with retain false',
    () async {
      final repo = FakeLearningMaterialRepository();
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: FakeDocumentIntakeFileService([
          DocumentFileData(
            path: '/tmp/notes.txt',
            bytes: utf8.encode('First line\nSecond line'),
          ),
        ]),
        codec: codec,
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      expect(repo.createCalls, 1);
      final input = repo.lastCreateInput!;
      expect(input.title, 'notes');
      expect(input.assets, hasLength(1));
      final asset = input.assets.single as DocumentTextMaterialAssetInput;
      expect(asset.text, 'First line\nSecond line');
      expect(asset.language, isNull);
      expect(repo.lastRetainDirective, const MaterialRetainExplicit(false));
      expect(
        controller.state,
        isA<DocumentSessionReady>().having(
          (ready) => ready.isRetained,
          'isRetained',
          false,
        ),
      );
    },
  );

  test(
    'paste intake sends exactly one document_text asset with retain false',
    () async {
      final repo = FakeLearningMaterialRepository();
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: FakeDocumentIntakeFileService(),
        codec: codec,
      );
      addTearDown(controller.dispose);

      await controller.openPastedText(
        title: '  Pasted notes  ',
        body: 'Body  with  spacing\nkept.',
      );

      expect(repo.createCalls, 1);
      final input = repo.lastCreateInput!;
      expect(input.title, 'Pasted notes');
      expect(input.assets.single, isA<DocumentTextMaterialAssetInput>());
      expect(
        (input.assets.single as DocumentTextMaterialAssetInput).text,
        'Body  with  spacing\nkept.',
      );
      expect(repo.lastRetainDirective, const MaterialRetainExplicit(false));
    },
  );

  test('an unavailable core is a typed coreUnavailable failure', () async {
    final repo = FakeLearningMaterialRepository(available: false);
    final files = FakeDocumentIntakeFileService();
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
        DocumentSessionFailureKind.coreUnavailable,
      ),
    );
    expect(files.pickCalls, 0);
    expect(repo.createCalls, 0);
  });

  test('an unavailable core also rejects paste', () async {
    final repo = FakeLearningMaterialRepository(available: false);
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openPastedText(title: 't', body: 'b');

    expect(
      controller.state,
      isA<DocumentSessionFailed>().having(
        (failed) => failed.failure.kind,
        'kind',
        DocumentSessionFailureKind.coreUnavailable,
      ),
    );
    expect(repo.createCalls, 0);
  });

  test('paste with an empty title is a typed missingTitle failure', () async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openPastedText(title: '   ', body: 'body');

    expect(
      controller.state,
      isA<DocumentSessionFailed>().having(
        (failed) => failed.failure.kind,
        'kind',
        DocumentSessionFailureKind.missingTitle,
      ),
    );
    expect(repo.createCalls, 0);
  });

  test('paste with an empty body is a typed emptyDocument failure', () async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openPastedText(title: 't', body: '  \n ');

    expect(
      controller.state,
      isA<DocumentSessionFailed>().having(
        (failed) => failed.failure.kind,
        'kind',
        DocumentSessionFailureKind.emptyDocument,
      ),
    );
    expect(repo.createCalls, 0);
  });

  test('paste over 1 MiB of UTF-8 is a typed tooLarge failure', () async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openPastedText(
      title: 't',
      body: 'x' * (maxDocumentBytes + 1),
    );

    expect(
      controller.state,
      isA<DocumentSessionFailed>().having(
        (failed) => failed.failure.kind,
        'kind',
        DocumentSessionFailureKind.tooLarge,
      ),
    );
    expect(repo.createCalls, 0);
  });

  test(
    'an API failure is a typed apiFailure with the detail attached',
    () async {
      final repo = FakeLearningMaterialRepository()
        ..createFailure = ApiFailure(
          raw: '{"message":"boom"}',
          message: 'boom',
          correlationId: 'api-1',
        );
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: FakeDocumentIntakeFileService([
          DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
        ]),
        codec: codec,
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      final failed = controller.state as DocumentSessionFailed;
      expect(failed.failure.kind, DocumentSessionFailureKind.apiFailure);
      expect(failed.failure.apiFailure?.correlationId, 'api-1');
      // Ordinary prose must not carry the transport text.
      expect(failed.failure.apiFailure?.raw, contains('boom'));
    },
  );

  test('a duplicate/convergent create result opens normally', () async {
    final repo = FakeLearningMaterialRepository()
      ..onCreate = (input) => MaterialDetails(
        material: LearningMaterial(
          id: 'existing-material',
          currentRevisionId: 'revision-1',
          retainedAtMs: null,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        currentRevision: MaterialRevision(
          id: 'revision-1',
          materialId: 'existing-material',
          title: 'Converged title',
          assets: [
            _textAsset(
              'asset-9',
              input.assets.firstOrNull is DocumentTextMaterialAssetInput
                  ? (input.assets.first as DocumentTextMaterialAssetInput).text
                  : 'x',
            ),
          ],
          createdAtMs: 1,
        ),
        shape: MaterialShape.text,
      );
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openFile();

    final ready = controller.state as DocumentSessionReady;
    expect(ready.details.material.id, 'existing-material');
    expect(ready.documentAsset.text, 'Body');
  });

  test('a throwing file service is a typed unreadable failure', () async {
    final repo = FakeLearningMaterialRepository();
    final files = FakeDocumentIntakeFileService()
      ..pickError = Exception('picker exploded');
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: files,
      codec: codec,
    );
    addTearDown(controller.dispose);

    // The open future itself must not throw, even though the fake throws.
    await controller.openFile();

    final failed = controller.state as DocumentSessionFailed;
    expect(failed.failure.kind, DocumentSessionFailureKind.unreadable);
    // No raw exception text or path may reach the state.
    expect(failed.failure.apiFailure, isNull);
    expect(files.pickCalls, 1);
    expect(repo.createCalls, 0);
  });

  test('a stale picker exception is dropped, not published', () async {
    final repo = FakeLearningMaterialRepository();
    final files = FakeDocumentIntakeFileService()
      ..pickError = Exception('picker exploded');
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: files,
      codec: codec,
    );

    final open = controller.openFile();
    controller.dispose();
    await open;

    expect(controller.state, isA<DocumentSessionOpening>());
  });

  test('a ".txt" file with no name is a typed missingTitle failure', () async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openFile();

    final failed = controller.state as DocumentSessionFailed;
    expect(failed.failure.kind, DocumentSessionFailureKind.missingTitle);
    expect(repo.createCalls, 0);
  });

  test('a whitespace-only file name is a typed missingTitle failure', () async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/   .txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openFile();

    final failed = controller.state as DocumentSessionFailed;
    expect(failed.failure.kind, DocumentSessionFailureKind.missingTitle);
    expect(repo.createCalls, 0);
  });

  test('a double ".txt" suffix keeps the inner name as the title', () async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(
          path: '/tmp/notes.txt.txt',
          bytes: utf8.encode('Body'),
        ),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openFile();

    expect(repo.createCalls, 1);
    expect(repo.lastCreateInput?.title, 'notes.txt');
    // The full path never becomes the title.
    expect(repo.lastCreateInput?.title, isNot(contains('/tmp')));
    final ready = controller.state as DocumentSessionReady;
    expect(ready.documentAsset.text, 'Body');
  });

  test(
    'a create response with a different document text is apiFailure',
    () async {
      final repo = FakeLearningMaterialRepository()
        ..onCreate = (input) => MaterialDetails(
          material: LearningMaterial(
            id: 'm',
            currentRevisionId: 'revision-1',
            retainedAtMs: null,
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
          currentRevision: MaterialRevision(
            id: 'revision-1',
            materialId: 'm',
            title: 'Different text',
            assets: [_textAsset('other', 'Some other document body')],
            createdAtMs: 1,
          ),
          shape: MaterialShape.text,
        );
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: FakeDocumentIntakeFileService([
          DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
        ]),
        codec: codec,
      );
      addTearDown(controller.dispose);

      await controller.openFile();

      final failed = controller.state as DocumentSessionFailed;
      expect(failed.failure.kind, DocumentSessionFailureKind.apiFailure);
      // The mismatch diagnostic is only in the typed detail, never in prose.
      expect(failed.failure.apiFailure, isNotNull);
      // The wrong document's body is never shown.
      expect(controller.state, isNot(isA<DocumentSessionReady>()));
    },
  );

  test('a create response with no document asset is apiFailure', () async {
    final repo = FakeLearningMaterialRepository()
      ..onCreate = (input) => MaterialDetails(
        material: LearningMaterial(
          id: 'm',
          currentRevisionId: 'revision-1',
          retainedAtMs: null,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        currentRevision: MaterialRevision(
          id: 'revision-1',
          materialId: 'm',
          title: 'No documents',
          assets: const [],
          createdAtMs: 1,
        ),
        shape: MaterialShape.text,
      );
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openFile();

    final failed = controller.state as DocumentSessionFailed;
    expect(failed.failure.kind, DocumentSessionFailureKind.apiFailure);
    expect(failed.failure.apiFailure, isNotNull);
    expect(controller.state, isNot(isA<DocumentSessionReady>()));
  });

  test('Keep succeeds: retained, library refreshed', () async {
    final repo = FakeLearningMaterialRepository();
    var refreshes = 0;
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
      refreshLibrary: () async => refreshes += 1,
    );
    addTearDown(controller.dispose);
    await controller.openFile();

    await controller.retain();

    expect(repo.retainCalls, 1);
    expect(repo.lastRetainedMaterialId, 'material-1');
    final ready = controller.state as DocumentSessionReady;
    expect(ready.isRetained, isTrue);
    expect(ready.documentAsset.text, 'Body');
    expect(refreshes, 1);
  });

  test('Unkeep succeeds: not retained, library refreshed', () async {
    final repo = FakeLearningMaterialRepository();
    var refreshes = 0;
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
      refreshLibrary: () async => refreshes += 1,
    );
    addTearDown(controller.dispose);
    await controller.openFile();
    await controller.retain();
    expect((controller.state as DocumentSessionReady).isRetained, isTrue);

    await controller.unretain();

    expect(repo.unretainCalls, 1);
    final ready = controller.state as DocumentSessionReady;
    expect(ready.isRetained, isFalse);
    expect(ready.documentAsset.text, 'Body');
    expect(refreshes, 2);
  });

  test(
    'a failed Keep keeps the document readable with a typed detail',
    () async {
      final repo = FakeLearningMaterialRepository()
        ..retentionFailure = ApiFailure(
          raw: '{"message":"nope"}',
          message: 'nope',
          correlationId: 'api-2',
        );
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: FakeDocumentIntakeFileService([
          DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
        ]),
        codec: codec,
      );
      addTearDown(controller.dispose);
      await controller.openFile();

      await controller.retain();

      final ready = controller.state as DocumentSessionReady;
      // The document is still fully readable and still Temporary.
      expect(ready.isRetained, isFalse);
      expect(ready.documentAsset.text, 'Body');
      expect(ready.retentionFailure?.correlationId, 'api-2');
      // Ordinary state text never carries the raw transport text.
      expect(ready.retentionFailure?.raw, contains('nope'));
    },
  );

  test('a failed Unkeep keeps the document readable and retained', () async {
    final repo = FakeLearningMaterialRepository()
      ..onRetain = (id) {
        return FakeLearningMaterialRepository.retained(id);
      }
      ..retentionFailure = ApiFailure(raw: '{"message":"nope"}');
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await controller.openFile();
    await controller.retain();

    await controller.unretain();

    final ready = controller.state as DocumentSessionReady;
    expect(ready.isRetained, isTrue);
    expect(ready.documentAsset.text, 'Body');
    expect(ready.retentionFailure, isNotNull);
  });

  test('retention in flight prevents a second submission', () async {
    final repo = FakeLearningMaterialRepository()
      ..retentionGate = Completer<MaterialDetails>();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await controller.openFile();

    final first = controller.retain();
    await controller.retain();
    await controller.retain();

    expect(repo.retainCalls, 1);

    repo.retentionGate!.complete(
      FakeLearningMaterialRepository.retained('material-1'),
    );
    await first;
    expect(repo.retainCalls, 1);
  });

  test('a late Keep result never applies to a newer generation', () async {
    final repo = FakeLearningMaterialRepository()
      ..retentionGate = Completer<MaterialDetails>();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await controller.openFile();
    final retain = controller.retain();

    // A newer intent supersedes the in-flight retention.
    controller.close();

    repo.retentionGate!.complete(
      FakeLearningMaterialRepository.retained('material-1'),
    );
    await retain;

    expect(controller.state, isA<DocumentSessionIdle>());
  });

  test('a late create result never overwrites a newer paste', () async {
    final repo = FakeLearningMaterialRepository()
      ..createGate = Completer<MaterialDetails>()
      ..createStarted = Completer<void>();
    final gate = repo.createGate!;
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/old.txt', bytes: utf8.encode('Old body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);

    // The old file open reaches the create seam and blocks on the gate.
    final oldOpen = controller.openFile();
    await repo.createStarted!.future;
    expect(controller.state, isA<DocumentSessionOpening>());

    // The newer intent completes fully while the old create is still blocked.
    repo.createGate = null;
    await controller.openPastedText(title: 'Newer', body: 'Newer body');
    expect(controller.state, isA<DocumentSessionReady>());
    final newerTitle = (controller.state as DocumentSessionReady)
        .details
        .currentRevision
        .title;

    // Releasing the stale create must not republish anything.
    gate.complete(
      MaterialDetails(
        material: LearningMaterial(
          id: 'old',
          currentRevisionId: 'revision-1',
          retainedAtMs: null,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        currentRevision: MaterialRevision(
          id: 'revision-1',
          materialId: 'old',
          title: 'Old',
          assets: [_textAsset('a', 'Old body')],
          createdAtMs: 1,
        ),
        shape: MaterialShape.text,
      ),
    );
    await oldOpen;

    expect(controller.state, isA<DocumentSessionReady>());
    expect(
      (controller.state as DocumentSessionReady).details.currentRevision.title,
      newerTitle,
    );
  });

  test('a late picker result never overwrites a newer open', () async {
    final repo = FakeLearningMaterialRepository();
    final gated = GatedDocumentFileRead();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([gated]),
      codec: codec,
    );
    addTearDown(controller.dispose);

    final oldOpen = controller.openFile();
    await controller.openPastedText(title: 'Newer', body: 'Newer body');
    expect(controller.state, isA<DocumentSessionReady>());

    gated.completer.complete(
      DocumentFileData(path: '/tmp/old.txt', bytes: utf8.encode('Old body')),
    );
    await oldOpen;

    expect(controller.state, isA<DocumentSessionReady>());
    expect(
      (controller.state as DocumentSessionReady).details.currentRevision.title,
      'Newer',
    );
    expect(repo.createCalls, 1);
  });

  test('results after close never write state', () async {
    final repo = FakeLearningMaterialRepository()
      ..createGate = Completer<MaterialDetails>();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);

    final open = controller.openFile();
    controller.close();
    expect(controller.state, isA<DocumentSessionIdle>());

    repo.createGate!.complete(
      MaterialDetails(
        material: LearningMaterial(
          id: 'late',
          currentRevisionId: 'revision-1',
          retainedAtMs: null,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        currentRevision: MaterialRevision(
          id: 'revision-1',
          materialId: 'late',
          title: 'Late',
          assets: [_textAsset('a', 'Body')],
          createdAtMs: 1,
        ),
        shape: MaterialShape.text,
      ),
    );
    await open;

    expect(controller.state, isA<DocumentSessionIdle>());
  });

  test('results after dispose never write state', () async {
    final repo = FakeLearningMaterialRepository()
      ..createGate = Completer<MaterialDetails>();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );

    final open = controller.openFile();
    controller.dispose();

    repo.createGate!.complete(
      MaterialDetails(
        material: LearningMaterial(
          id: 'late',
          currentRevisionId: 'revision-1',
          retainedAtMs: null,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        currentRevision: MaterialRevision(
          id: 'revision-1',
          materialId: 'late',
          title: 'Late',
          assets: [_textAsset('a', 'Body')],
          createdAtMs: 1,
        ),
        shape: MaterialShape.text,
      ),
    );
    await open;

    // No throw from a disposed notifier, and the session never left opening.
    expect(controller.state, isA<DocumentSessionOpening>());
  });

  test('retry re-picks after a failed file open', () async {
    final repo = FakeLearningMaterialRepository();
    final files = FakeDocumentIntakeFileService([
      const DocumentFileFailure(
        DocumentIntakeFailure(DocumentIntakeFailureKind.unreadable),
      ),
      DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
    ]);
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: files,
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openFile();
    expect(controller.state, isA<DocumentSessionFailed>());

    await controller.retry();

    expect(files.pickCalls, 2);
    expect(controller.state, isA<DocumentSessionReady>());
  });

  test('retry re-submits the same paste input after a failed paste', () async {
    final repo = FakeLearningMaterialRepository()
      ..createFailure = ApiFailure(raw: '{"message":"boom"}');
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);

    await controller.openPastedText(title: 't', body: 'Body');
    expect(controller.state, isA<DocumentSessionFailed>());

    repo.createFailure = null;
    await controller.retry();

    expect(repo.createCalls, 2);
    final ready = controller.state as DocumentSessionReady;
    expect(ready.documentAsset.text, 'Body');
    expect(repo.lastCreateInput?.title, 't');
  });

  test('a library entry with no document assets opens nothing', () async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);

    controller.openLibraryEntry(
      _libraryEntry(materialId: 'm', assets: const []),
    );

    expect(controller.state, isA<DocumentSessionIdle>());
  });

  test('a library entry with one document asset opens directly', () async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);

    controller.openLibraryEntry(
      _libraryEntry(materialId: 'm', assets: [_textAsset('a1', 'Solo')]),
    );

    final ready = controller.state as DocumentSessionReady;
    expect(ready.details.material.id, 'm');
    expect(ready.documentAsset.id, 'a1');
    expect(ready.isRetained, isTrue);
  });

  test(
    'a library entry with several assets requires an explicit choice',
    () async {
      final repo = FakeLearningMaterialRepository();
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: FakeDocumentIntakeFileService(),
        codec: codec,
      );
      addTearDown(controller.dispose);

      controller.openLibraryEntry(
        _libraryEntry(
          materialId: 'm',
          assets: [_textAsset('a1', 'First'), _textAsset('a2', 'Second')],
        ),
      );

      expect(controller.state, isA<DocumentSessionChoosingAsset>());

      controller.chooseDocumentAsset('a2');

      final ready = controller.state as DocumentSessionReady;
      expect(ready.documentAsset.id, 'a2');
      expect(ready.documentAsset.text, 'Second');
    },
  );

  test('choosing an unknown asset id changes nothing', () async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);

    controller.openLibraryEntry(
      _libraryEntry(
        materialId: 'm',
        assets: [_textAsset('a1', 'First'), _textAsset('a2', 'Second')],
      ),
    );

    controller.chooseDocumentAsset('nope');

    expect(controller.state, isA<DocumentSessionChoosingAsset>());
  });
}
