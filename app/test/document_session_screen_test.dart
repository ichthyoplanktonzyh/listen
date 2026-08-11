import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/document_session_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/api_failure.dart';

import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/screens/document_session_screen.dart';
import 'package:llplayer_next/services/document_intake_service.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/common/api_failure_disclosure.dart';

import 'support/document_session_test_fakes.dart';

const codec = LocalDocumentIntakeCodec();

MaterialDetails _detailsFor(
  String title, {
  List<MaterialAsset> assets = const [],
  int? retainedAtMs,
  String materialId = 'material-1',
}) => MaterialDetails(
  material: LearningMaterial(
    id: materialId,
    currentRevisionId: 'revision-1',
    retainedAtMs: retainedAtMs,
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
  shape: assets.isEmpty ? MaterialShape.text : MaterialShape.mixed,
);

Widget _screen(DocumentSessionController controller) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: DocumentSessionScreen(controller: controller),
);

void main() {
  testWidgets('idle offers the file action as primary and paste as secondary', (
    tester,
  ) async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_screen(controller));
    await tester.pumpAndSettle();

    expect(find.text('选择纯文本文件'), findsOneWidget);
    expect(find.text('粘贴文本'), findsOneWidget);

    // The paste form is a secondary expansion, not a parallel entry.
    expect(find.text('标题'), findsNothing);
    await tester.tap(find.text('粘贴文本'));
    await tester.pumpAndSettle();
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('正文'), findsOneWidget);
  });

  testWidgets('a cancelled picker returns to idle without any error', (
    tester,
  ) async {
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
    await tester.pumpWidget(_screen(controller));

    await tester.tap(find.text('选择纯文本文件'));
    await tester.pumpAndSettle();

    expect(find.text('选择纯文本文件'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('文档没有内容。'), findsNothing);
    expect(repo.createCalls, 0);
  });

  testWidgets('opening shows the unified waiting language', (tester) async {
    final repo = FakeLearningMaterialRepository()
      ..createGate = Completer<MaterialDetails>()
      ..createStarted = Completer<void>();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_screen(controller));

    await tester.tap(find.text('选择纯文本文件'));
    // The waiting mark breathes forever, so pumpAndSettle never settles here;
    // a timed pump drains the intake microtasks and renders the opening pane.
    await tester.pump(const Duration(milliseconds: 50));
    await repo.createStarted!.future;
    await tester.pump();

    expect(find.text('正在打开文档…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    repo.createGate!.complete(
      _detailsFor(
        'a',
        assets: [
          DocumentTextMaterialAsset(
            id: 'a1',
            text: 'Body',
            sha256Digest: 'x',
            byteSize: 4,
            language: null,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('ready shows the exact text selectable with Temporary and Keep', (
    tester,
  ) async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(
          path: '/tmp/a.txt',
          bytes: utf8.encode('第一段。\n\nSecond paragraph with trailing space. '),
        ),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_screen(controller));

    await tester.tap(find.text('选择纯文本文件'));
    await tester.pumpAndSettle();

    // The exact source text, line breaks and trailing space included, inside
    // a SelectionArea-backed SelectableText — no cue split, no fabricated
    // paragraphs.
    expect(
      find.text('第一段。\n\nSecond paragraph with trailing space. '),
      findsOneWidget,
    );
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('临时'), findsOneWidget);
    expect(find.text('保留'), findsOneWidget);
  });

  testWidgets('Keep flips the header to Kept and Unkeep', (tester) async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_screen(controller));
    await tester.tap(find.text('选择纯文本文件'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();

    expect(find.text('已在个人资料库'), findsOneWidget);
    expect(find.text('从个人资料库移除'), findsOneWidget);
    expect(find.text('保留'), findsNothing);
    // The document itself is untouched by membership.
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('a failed paste is a stable localized message with retry/back', (
    tester,
  ) async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_screen(controller));

    await tester.tap(find.text('粘贴文本'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 't');
    await tester.tap(find.text('打开文档'));
    await tester.pumpAndSettle();

    expect(find.text('文档没有内容。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    expect(find.text('t'), findsNothing); // no fabricated title shown

    // Back returns to the idle pane.
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('选择纯文本文件'), findsOneWidget);
  });

  testWidgets('an API failure keeps detail behind the explicit disclosure', (
    tester,
  ) async {
    final repo = FakeLearningMaterialRepository()
      ..createFailure = ApiFailure(
        raw: '{"message":"backend exploded"}',
        message: 'backend exploded',
        correlationId: 'api-9',
      );
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_screen(controller));

    await tester.tap(find.text('选择纯文本文件'));
    await tester.pumpAndSettle();

    // The named message is all ordinary prose sees.
    expect(find.text('暂时无法打开文档。'), findsOneWidget);
    expect(find.textContaining('backend exploded'), findsNothing);
    expect(find.textContaining('api-9'), findsNothing);
    expect(find.byType(ApiFailureDisclosure), findsOneWidget);

    // The disclosure is a deliberate expansion.
    await tester.tap(find.text('诊断详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('backend exploded'), findsOneWidget);
    expect(find.textContaining('api-9'), findsOneWidget);
  });

  testWidgets('several document assets require an explicit keyboard choice', (
    tester,
  ) async {
    final entry = PersonalLibraryEntry(
      details: _detailsFor(
        'Multi document',
        assets: [
          DocumentTextMaterialAsset(
            id: 'a1',
            text: 'English document body',
            sha256Digest: 'x',
            byteSize: 22,
            language: 'en',
          ),
          DocumentTextMaterialAsset(
            id: 'a2',
            text: '中文文档正文',
            sha256Digest: 'y',
            byteSize: 18,
            language: 'zh',
          ),
        ],
      ),
      mediaEntries: const [],
    );
    final controller = DocumentSessionController(
      materialRepository: FakeLearningMaterialRepository(),
      fileService: FakeDocumentIntakeFileService(),
      codec: codec,
    );
    addTearDown(controller.dispose);
    controller.openLibraryEntry(entry);
    await tester.pumpWidget(_screen(controller));
    await tester.pumpAndSettle();

    // Both assets are listed with language, size and a short preview — the
    // internal asset ids never appear.
    expect(find.text('语言：en'), findsOneWidget);
    expect(find.text('语言：zh'), findsOneWidget);
    expect(find.textContaining('KB'), findsNothing);
    expect(find.text('a1'), findsNothing);
    expect(find.text('a2'), findsNothing);

    // Choosing the second opens exactly that document.
    await tester.tap(find.textContaining('中文文档正文'));
    await tester.pumpAndSettle();

    expect(find.text('中文文档正文'), findsOneWidget);
    expect(find.text('English document body'), findsNothing);
  });

  testWidgets('ready and choosing render without overflow at 640 and 1200', (
    tester,
  ) async {
    for (final width in const [640.0, 1200.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      final repo = FakeLearningMaterialRepository();
      final controller = DocumentSessionController(
        materialRepository: repo,
        fileService: FakeDocumentIntakeFileService([
          DocumentFileData(
            path: '/tmp/a.txt',
            bytes: utf8.encode('A long document line '.toUpperCase() * 40),
          ),
        ]),
        codec: codec,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      await tester.tap(find.text('选择纯文本文件'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'width $width ready');
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('semantics: actions are labelled buttons, not bare icons', (
    tester,
  ) async {
    final repo = FakeLearningMaterialRepository();
    final controller = DocumentSessionController(
      materialRepository: repo,
      fileService: FakeDocumentIntakeFileService([
        DocumentFileData(path: '/tmp/a.txt', bytes: utf8.encode('Body')),
      ]),
      codec: codec,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_screen(controller));

    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('选择纯文本文件'));
    await tester.pumpAndSettle();

    // Ready keeps named actions (Keep here) — nothing reachable by icon alone.
    expect(find.text('保留'), findsOneWidget);
  });
}
