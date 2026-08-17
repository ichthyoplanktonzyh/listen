import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/document_session_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/composition.dart';
import 'package:llplayer_next/models/document_session.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/document_intake_flow.dart';
import 'package:llplayer_next/services/document_intake_service.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/document_workbench.dart';
import 'package:llplayer_next/widgets/layout/media_workbench.dart';

import 'support/document_session_test_fakes.dart';
import 'support/learning_material_fixtures.dart';

/// The workbench is the app's one content surface.
///
/// These are the acceptance criteria of the "one workbench, one material
/// session" restructure, kept executable because a documented rule drifts and
/// a test does not. Each one names the regression it exists to prevent.
final _codec = LocalDocumentIntakeCodec(pdfTextExtractor: _NoPdfText());

class _NoPdfText implements PdfTextExtractor {
  @override
  Future<String?> extractText(List<int> bytes) async => null;
}

String _digestOf(String text) => sha256.convert(utf8.encode(text)).toString();

PersonalLibraryEntry _textEntry(String text, {String materialId = 'm-1'}) {
  final rendition = documentRendition(
    id: 'doc-1',
    digest: _digestOf(text),
    byteSize: utf8.encode(text).length,
  );
  return PersonalLibraryEntry(
    details: materialDetails(
      materialId: materialId,
      title: 'A document',
      documentRenditions: [rendition],
      sourceAssets: [
        sourceAsset(id: 'source-1', sha256Digest: _digestOf(text)),
      ],
      retainedAtMs: 1,
      shape: MaterialShape.text,
    ),
    mediaEntries: const [],
  );
}

DocumentSessionController _controller({
  required String text,
  Future<ResolvedComposition?> Function(String materialId)? resolveComposition,
}) {
  final repo = FakeLearningMaterialRepository();
  final resolver = FakeDocumentSourceResolver()
    ..bytesByDigest[_digestOf(text)] = utf8.encode(text);
  return DocumentSessionController(
    materialRepository: repo,
    fileService: FakeDocumentIntakeFileService(),
    intakeFlow: DocumentIntakeFlow(
      materialRepository: repo,
      codec: _codec,
      store: FakeManagedAssetStoreService(),
      referenceStore: FakeDocumentReferenceStore(),
    ),
    sourceResolver: resolver,
    resolveComposition: resolveComposition,
  );
}

ResolvedComposition _composition({
  String? derivedMediaPath,
  SubtitleTrack? transcript,
}) => ResolvedComposition(
  releaseId: 'release-1',
  editionId: 'edition-1',
  logicalText: 'Hello world.',
  sentences: const [
    CompositionSentence(
      id: 'sentence-000000',
      index: 0,
      text: 'Hello world.',
      startByte: 0,
      endByte: 12,
    ),
  ],
  anchors: const [],
  alignments: const {'sentence-000000': 1000},
  derivedMediaPath: derivedMediaPath,
  transcript: transcript,
);

Widget _host(
  DocumentSessionController controller, {
  CapabilityRunView? listenRun,
  VoidCallback? onRequestListen,
  Widget? timedLearningPanel,
}) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: DocumentWorkbench(
      controller: controller,
      mediaFraction: MediaWorkbench.defaultMediaFraction,
      onMediaFractionChanged: _ignoreFraction,
      onCollapse: _ignoreCollapse,
      listenRun: listenRun,
      onRequestListen: onRequestListen ?? _ignoreCollapse,
      timedLearningPanel: timedLearningPanel,
    ),
  ),
);

void _ignoreFraction(double value) {}
void _ignoreCollapse() {}

void main() {
  testWidgets('a text material mounts no media pane and no splitter', (
    tester,
  ) async {
    // "Text and audio show no empty video box." The workbench is shared, so
    // the temptation is to keep its media half and leave it blank; a blank
    // 16:9 box reads as broken playback, not as "this has no picture".
    final controller = _controller(text: 'Hello world.');
    addTearDown(controller.dispose);
    controller.openLibraryEntry(_textEntry('Hello world.'));

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.byType(MediaWorkbench), findsOneWidget);
    expect(find.byKey(const Key('workbench-media-title')), findsNothing);
    expect(find.byKey(const Key('media-workbench-splitter')), findsNothing);
    expect(
      find.byKey(const Key('document-learning-preparation')),
      findsOneWidget,
    );
    expect(find.text('Hello world.'), findsNothing);
    // Nothing to shadow until a rendition is adopted, so the action is not
    // advertised dead.
    expect(find.byKey(const Key('workbench-shadow')), findsNothing);
  });

  testWidgets('the workbench paints an opaque ground of its own', (
    tester,
  ) async {
    // Real incident: the workbench is stacked over the shell, not pushed as a
    // route, and it painted no background of its own. Every body happened to
    // paint one — until a document body, which paints none — so the rail and
    // the whole library page underneath were legible straight through the
    // open document.
    final controller = _controller(text: 'Hello world.');
    addTearDown(controller.dispose);
    controller.openLibraryEntry(_textEntry('Hello world.'));

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    final ground = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(MediaWorkbench),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      ground.color?.a,
      1.0,
      reason:
          'the workbench layer must be opaque; anything less lets the '
          'shell underneath show through it',
    );
  });

  testWidgets('the document body does not repeat the workbench header', (
    tester,
  ) async {
    // A document used to render its own title and its own Keep button inside
    // the body, directly under the header that already carried both. Two
    // titles on one surface is what made reading a document look like a page
    // stacked inside the workbench rather than the workbench's own text.
    final controller = _controller(text: 'Hello world.');
    addTearDown(controller.dispose);
    controller.openLibraryEntry(_textEntry('Hello world.'));

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('A document'), findsOneWidget);
    expect(find.byKey(const Key('workbench-breadcrumb-title')), findsOneWidget);
  });

  testWidgets('generating listening happens on the workbench, not elsewhere', (
    tester,
  ) async {
    // "Tapping generate does not leave the workbench", and the material id
    // does not change: the request is made against the material already open.
    final controller = _controller(text: 'Hello world.');
    addTearDown(controller.dispose);
    controller.openLibraryEntry(_textEntry('Hello world.', materialId: 'm-42'));

    var requests = 0;
    await tester.pumpWidget(
      _host(controller, onRequestListen: () => requests += 1),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('document-listen-request')));
    await tester.pumpAndSettle();

    expect(requests, 1);
    // Still the same surface, still the same material.
    expect(find.byType(DocumentWorkbench), findsOneWidget);
    final state = controller.state as DocumentSessionReady;
    expect(state.details.material.id, 'm-42');
  });

  testWidgets('a failed generation keeps source available but secondary', (
    tester,
  ) async {
    // "A failed generation does not damage the original material." The text
    // must still be on screen, and the affordance must offer a retry rather
    // than an error state that has swallowed the document.
    final controller = _controller(text: 'Hello world.');
    addTearDown(controller.dispose);
    controller.openLibraryEntry(_textEntry('Hello world.'));

    await tester.pumpWidget(
      _host(
        controller,
        onRequestListen: () {},
        listenRun: const CapabilityRunView(
          materialId: 'm-1',
          capability: MaterialCapability.listen,
          phase: CapabilityRunPhase.failed,
          warnings: [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello world.'), findsNothing);
    expect(
      find.text('Could not generate the learning materials'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('document-listen-retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('document-view-source')));
    await tester.pumpAndSettle();
    expect(find.text('Hello world.'), findsOneWidget);
  });

  testWidgets('audio without tokenized text remains a preparation state', (
    tester,
  ) async {
    // "TTS finishing adds playback and sentence sync to the workbench in
    // place" — the session resolves the adopted composition when the document
    // opens, so reopening a material that was generated before simply has it.
    final controller = _controller(
      text: 'Hello world.',
      resolveComposition: (_) async =>
          _composition(derivedMediaPath: '/tmp/does-not-need-to-exist.m4a'),
    );
    addTearDown(controller.dispose);
    controller.openLibraryEntry(_textEntry('Hello world.'));

    await tester.pumpWidget(_host(controller, onRequestListen: () {}));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('document-learning-preparation')),
      findsOneWidget,
    );
    // Audio alone cannot activate lookup and token-bound analysis.
    expect(find.byKey(const Key('document-listen-request')), findsOneWidget);
  });

  testWidgets('structured text without interaction remains preparation', (
    tester,
  ) async {
    // The degraded package: structure but no derived audio. The sentences are
    // shown and the absence is stated — never a silent, dead player.
    final controller = _controller(
      text: 'Hello world.',
      resolveComposition: (_) async => _composition(),
    );
    addTearDown(controller.dispose);
    controller.openLibraryEntry(_textEntry('Hello world.'));

    await tester.pumpWidget(_host(controller, onRequestListen: () {}));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('document-learning-preparation')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('document-listen-request')), findsOneWidget);
  });

  testWidgets('timed generated text reuses the existing learning panel', (
    tester,
  ) async {
    const transcript = SubtitleTrack(
      id: 'composition:edition-1',
      source: 'composition',
      cues: [
        Cue(
          id: 'sentence-000000',
          index: 0,
          start: Duration(seconds: 1),
          end: Duration(seconds: 2),
          text: 'Hello world.',
          tokens: [
            SubtitleToken(
              index: 0,
              kind: 'word',
              text: 'Hello',
              normalized: 'hello',
            ),
          ],
        ),
      ],
    );
    final controller = _controller(
      text: 'Hello world.',
      resolveComposition: (_) async => _composition(
        derivedMediaPath: '/tmp/generated.m4a',
        transcript: transcript,
      ),
    );
    addTearDown(controller.dispose);
    controller.openLibraryEntry(_textEntry('Hello world.'));

    await tester.pumpWidget(
      _host(
        controller,
        timedLearningPanel: const SizedBox(key: Key('existing-learning-panel')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('existing-learning-panel')), findsOneWidget);
    expect(find.byType(MediaWorkbench), findsOneWidget);

    // The original file remains a secondary verification view and returning
    // restores the very same learning panel.
    await tester.tap(find.byKey(const Key('document-source-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Hello world.'), findsOneWidget);
    expect(find.byKey(const Key('existing-learning-panel')), findsNothing);
    await tester.tap(find.byKey(const Key('document-source-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('existing-learning-panel')), findsOneWidget);
  });

  testWidgets('keeping a document does not drop its adopted composition', (
    tester,
  ) async {
    // Membership and content are different axes. The ready state used to be
    // rebuilt field-by-field on Keep, so any field the rebuild forgot vanished
    // — the composition disappearing on Keep is exactly that class of bug.
    final controller = _controller(
      text: 'Hello world.',
      resolveComposition: (_) async => _composition(),
    );
    addTearDown(controller.dispose);
    controller.openLibraryEntry(_textEntry('Hello world.'));

    await tester.pumpWidget(_host(controller, onRequestListen: () {}));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('document-learning-preparation')),
      findsOneWidget,
    );

    await controller.unretain();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('document-learning-preparation')),
      findsOneWidget,
    );
    expect((controller.state as DocumentSessionReady).composition, isNotNull);
  });

  test('no workbench surface is reachable by pushing a route', () {
    // "Opening a document does not grow the route stack." Reading text,
    // playing media and viewing a generated edition were three pushed pages;
    // they are one workbench layer now, swapped in place. A route push would
    // put a second content surface on top of the first — the exact thing that
    // made three separate session surfaces exist — so the rule is checked at
    // the source rather than trusted.
    const surfaces = [
      'DocumentWorkbench(',
      'MediaWorkbench(',
      // Deleted with the restructure; a reappearance means a page came back.
      'DocumentSessionScreen',
      'CompositionSessionScreen',
    ];
    final routeStart = RegExp(
      r'MaterialPageRoute|Navigator\.(of\(.*?\)\.)?push',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in routeStart.allMatches(source)) {
        // The builder of a route sits just after it. Scanning the window
        // rather than the whole file keeps unrelated routes in the same file
        // — settings, the conversation stage — from reading as offenders.
        final end = (match.start + 400).clamp(0, source.length);
        final builder = source.substring(match.start, end);
        for (final surface in surfaces) {
          if (builder.contains(surface)) {
            offenders.add('${entity.path}: $surface');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A workbench surface must be mounted in place, never pushed as a '
          'route:\n${offenders.join('\n')}',
    );
  });

  test('an unresolvable composition never takes the document away', () async {
    // The read can fail for reasons that say nothing about the document:
    // an unreachable core, a payload that will not parse. The direct view
    // must survive all of them.
    final controller = _controller(
      text: 'Hello world.',
      resolveComposition: (_) async => throw StateError('core unreachable'),
    );
    addTearDown(controller.dispose);

    controller.openLibraryEntry(_textEntry('Hello world.'));
    await Future<void>.delayed(Duration.zero);

    final state = controller.state;
    expect(state, isA<DocumentSessionReady>());
    expect((state as DocumentSessionReady).composition, isNull);
  });
}
