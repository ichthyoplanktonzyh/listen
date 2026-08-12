import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/home/listening_home.dart';

import 'support/learning_material_fixtures.dart';

MediaItem _media(String id, String title, int updatedAtMs, {String kind = 'video'}) => MediaItem(
  id: id,
  path: '/media/$id.mp4',
  fingerprint: 'fp-$id',
  title: title,
  kind: kind,
  durationMs: 60000,
  availability: 'available',
  createdAtMs: 1,
  updatedAtMs: updatedAtMs,
);

MediaLibraryEntry _entry(
  String id,
  String title, {
  int updatedAtMs = 1,
  String kind = 'video',
}) => MediaLibraryEntry(
  media: _media(id, title, updatedAtMs, kind: kind),
  primaryTrackId: null,
  fit: null,
  triageIntent: null,
  familiarMaterial: false,
);

MaterialDetails _details(
  String id,
  String title, {
  int updatedAtMs = 1,
  List<SourceAsset> sourceAssets = const [],
  List<DocumentRendition> documentRenditions = const [],
  List<MediaRendition> mediaRenditions = const [],
  MaterialShape shape = MaterialShape.text,
}) => MaterialDetails(
  material: LearningMaterial(
    id: id,
    currentRevisionId: 'revision-$id',
    retainedAtMs: 42,
    createdAtMs: 1,
    updatedAtMs: updatedAtMs,
  ),
  currentRevision: MaterialRevision(
    id: 'revision-$id',
    materialId: id,
    title: title,
    sourceAssets: sourceAssets,
    documentRenditions: documentRenditions,
    mediaRenditions: mediaRenditions,
    createdAtMs: 1,
  ),
  shape: shape,
);

DocumentRendition _textAsset(String id) => documentRendition(
  id: '$id-text',
  text: 'Readable text',
);

MediaRendition _mediaAsset(String id) => mediaRendition(
  id: '$id-media',
  mediaId: 'media-$id',
  kind: MediaRenditionKind.audio,
  fingerprint: 'fp',
);

/// A text-only library row.
PersonalLibraryEntry _textEntry(
  String id,
  String title, {
  int updatedAtMs = 1,
}) => PersonalLibraryEntry(
  details: _details(
    id,
    title,
    updatedAtMs: updatedAtMs,
    documentRenditions: [_textAsset(id)],
  ),
  mediaEntries: const [],
);

/// A media-only library row bound to a registered media row.
PersonalLibraryEntry _mediaEntry(
  String id,
  String title, {
  int updatedAtMs = 1,
}) => PersonalLibraryEntry(
  details: _details(
    id,
    title,
    updatedAtMs: updatedAtMs,
    mediaRenditions: [_mediaAsset(id)],
    shape: MaterialShape.audio,
  ),
  mediaEntries: [
    _entry('media-$id', title, updatedAtMs: updatedAtMs, kind: 'audio'),
  ],
);

/// A mixed row: both Read and Listen/Watch.
PersonalLibraryEntry _mixedEntry(
  String id,
  String title, {
  int updatedAtMs = 1,
}) => PersonalLibraryEntry(
  details: _details(
    id,
    title,
    updatedAtMs: updatedAtMs,
    documentRenditions: [_textAsset(id)],
    mediaRenditions: [_mediaAsset(id)],
    shape: MaterialShape.mixed,
  ),
  mediaEntries: [
    _entry('media-$id', title, updatedAtMs: updatedAtMs, kind: 'audio'),
  ],
);

void main() {
  Widget app({
    required VoidCallback onOpenMedia,
    VoidCallback? onOpenOnline,
    VoidCallback? onOpenDocument,
    List<PersonalLibraryEntry>? personalLibrary,
    List<PersonalLibraryEntry>? offlineEntries,
    void Function(PersonalLibraryEntry entry)? onOpenLibraryDocument,
    void Function(PersonalLibraryEntry entry)? onOpenLibraryMedia,
  }) => MaterialApp(
    theme: ListenTheme.light(),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: ListeningHome(
        onOpenMedia: onOpenMedia,
        onOpenOnline: onOpenOnline ?? () {},
        onOpenDocument: onOpenDocument,
        personalLibrary: personalLibrary,
        offlineEntries: offlineEntries,
        familiarSupplyEnabled: true,
        onOpenLibraryDocument: onOpenLibraryDocument ?? (_) {},
        onOpenLibraryMedia: onOpenLibraryMedia ?? (_) {},
        onStartExtensiveEntry: (_) {},
        onStartIntensiveEntry: (_) {},
        onSetLibraryIntent: (_, _) {},
        onToggleFamiliarSupply: (_) {},
      ),
    ),
  );

  testWidgets('home shows the content sections and opens local media', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openMediaCalls = 0;
    var openDocumentCalls = 0;

    await tester.pumpWidget(
      app(
        onOpenMedia: () => openMediaCalls += 1,
        onOpenDocument: () => openDocumentCalls += 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加内容来源'), findsOneWidget);
    // The library is a segment of "listen" now: it carries no page title of
    // its own, and no longer answers "what should I do now" — the continue
    // card and the status strip moved to the today pane.
    expect(find.text('继续当前内容会话'), findsNothing);

    // The document entry is a first-class primary action beside the existing
    // media and URL entries.
    expect(find.text('打开文档'), findsOneWidget);
    expect(find.text('打开视频或音频'), findsOneWidget);
    expect(find.text('打开网址'), findsOneWidget);

    await tester.tap(find.text('打开文档'));
    expect(openDocumentCalls, 1);
    await tester.tap(find.text('打开视频或音频'));
    expect(openMediaCalls, 1);
    expect(tester.takeException(), isNull);
  });

  // The headline of the S2 migration for this file. The home page used to
  // measure its own margin — `fromLTRB(24|48, 28|44, 24|48, 40)`, four
  // directions, four numbers, three of them off any ladder — which is why it
  // never matched the coach dashboard or the vocabulary detail. Both of those
  // inset at 24, so `pageCompact`/`page` is what makes the three agree.
  testWidgets('the home page margin is a page role at both widths', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<EdgeInsetsGeometry?> pageInsetAt(Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(app(onOpenMedia: () {}));
      await tester.pumpAndSettle();
      return tester
          .widget<SingleChildScrollView>(
            find
                .ancestor(
                  of: find.text('添加内容来源'),
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
          )
          .padding;
    }

    expect(await pageInsetAt(const Size(1200, 800)), ListenPadding.page);
    // Below `homeSidebar` the page folds to the narrow role, the same one the
    // vocabulary detail and the coach dashboard use.
    expect(await pageInsetAt(const Size(640, 700)), ListenPadding.pageCompact);
    expect(ListenPadding.pageCompact.horizontal / 2, ListenSpacing.gap24);

    // And the content column takes the shared wide cap rather than the 920 it
    // invented, so "how wide may the home column grow" is one decision.
    expect(
      tester
          .widget<ConstrainedBox>(
            find
                .ancestor(
                  of: find.text('添加内容来源'),
                  matching: find.byType(ConstrainedBox),
                )
                .first,
          )
          .constraints
          .maxWidth,
      ListenBreakpoints.wideColumnMax,
    );
  });

  testWidgets('home renders clean at a short height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 384));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(app(onOpenMedia: () {}));
    await tester.pumpAndSettle();

    expect(find.text('添加内容来源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact home stacks source actions without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openOnlineCalls = 0;

    await tester.pumpWidget(
      app(onOpenMedia: () {}, onOpenOnline: () => openOnlineCalls += 1),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开网址'));
    expect(openOnlineCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline filter narrows the library to the offline subset', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final online = _mediaEntry('online-1', 'Online Media One');
    final offline = _mediaEntry('offline-1', 'Offline Media One');
    await tester.pumpWidget(
      app(
        onOpenMedia: () {},
        personalLibrary: [online, offline],
        offlineEntries: [offline],
      ),
    );
    await tester.pumpAndSettle();

    // The library section and its filter live on the home only when a library
    // is present; both entries are listed before the filter is applied.
    expect(find.text('离线下载'), findsOneWidget);
    expect(find.text('Online Media One'), findsOneWidget);
    expect(find.text('Offline Media One'), findsOneWidget);

    await tester.tap(find.text('离线下载'));
    await tester.pumpAndSettle();

    expect(find.text('Online Media One'), findsNothing);
    expect(find.text('Offline Media One'), findsOneWidget);

    // The filter is a view, not a destination: clearing it restores the full
    // library.
    await tester.tap(find.text('离线下载'));
    await tester.pumpAndSettle();

    expect(find.text('Online Media One'), findsOneWidget);
    expect(find.text('Offline Media One'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // History used to be a sidebar destination whose whole body was this list
  // sorted by `updatedAtMs`. One data source and one `sort` apart is an
  // ordering, not a place — this pins it as one. The timestamp is the
  // retained material's, not a media row's.
  testWidgets('recently-studied is an ordering on the library, not a room', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final older = _mediaEntry('older', 'Older Media', updatedAtMs: 1000);
    final newer = _mediaEntry('newer', 'Newer Media', updatedAtMs: 2000);
    await tester.pumpWidget(
      app(onOpenMedia: () {}, personalLibrary: [older, newer]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('最近学过'));
    await tester.pumpAndSettle();

    // Same rows, newest first — nothing is filtered away by an ordering.
    expect(find.text('Older Media'), findsOneWidget);
    expect(find.text('Newer Media'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Newer Media')).dy,
      lessThan(tester.getTopLeft(find.text('Older Media')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('capability filters are views: All, Read, Listen/Watch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final text = _textEntry('text-1', 'A Text Document');
    final media = _mediaEntry('media-1', 'A Media File');
    final mixed = _mixedEntry('mixed-1', 'A Mixed Material');
    await tester.pumpWidget(
      app(onOpenMedia: () {}, personalLibrary: [text, media, mixed]),
    );
    await tester.pumpAndSettle();

    // All shows every row.
    expect(find.text('A Text Document'), findsOneWidget);
    expect(find.text('A Media File'), findsOneWidget);
    expect(find.text('A Mixed Material'), findsOneWidget);

    // Read keeps text and mixed; media-only disappears.
    await tester.tap(find.widgetWithText(ChoiceChip, '阅读'));
    await tester.pumpAndSettle();

    expect(find.text('A Text Document'), findsOneWidget);
    expect(find.text('A Mixed Material'), findsOneWidget);
    expect(find.text('A Media File'), findsNothing);

    // Listen keeps audio media and mixed; text-only disappears.
    await tester.tap(find.widgetWithText(ChoiceChip, '听'));
    await tester.pumpAndSettle();

    expect(find.text('A Media File'), findsOneWidget);
    expect(find.text('A Mixed Material'), findsOneWidget);
    expect(find.text('A Text Document'), findsNothing);

    // Watch keeps only materials with a usable video media.
    await tester.tap(find.widgetWithText(ChoiceChip, '看'));
    await tester.pumpAndSettle();

    expect(find.text('A Media File'), findsNothing);
    expect(find.text('A Mixed Material'), findsNothing);
    expect(find.text('A Text Document'), findsNothing);

    // Clearing the view restores the full library.
    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.pumpAndSettle();

    expect(find.text('A Text Document'), findsOneWidget);
    expect(find.text('A Media File'), findsOneWidget);
    expect(find.text('A Mixed Material'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a mixed row states Read and Listen/Watch explicitly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var documentOpens = 0;
    var mediaOpens = 0;
    await tester.pumpWidget(
      app(
        onOpenMedia: () {},
        personalLibrary: [_mixedEntry('mixed-1', 'A Mixed Material')],
        onOpenLibraryDocument: (_) => documentOpens += 1,
        onOpenLibraryMedia: (_) => mediaOpens += 1,
      ),
    );
    await tester.pumpAndSettle();

    // Both capabilities are named — the row never guesses from a bare tap.
    expect(find.widgetWithText(TextButton, '阅读'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '打开媒体'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '阅读'));
    expect(documentOpens, 1);
    await tester.tap(find.widgetWithText(TextButton, '打开媒体'));
    expect(mediaOpens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text-only rows open the document, not media actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var documentOpens = 0;
    await tester.pumpWidget(
      app(
        onOpenMedia: () {},
        personalLibrary: [_textEntry('text-1', 'A Text Document')],
        onOpenLibraryDocument: (_) => documentOpens += 1,
      ),
    );
    await tester.pumpAndSettle();

    // Read is present; no media action, no media triage menu, no extensive or
    // intensive buttons for a row with nothing to play.
    expect(find.widgetWithText(TextButton, '阅读'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '打开媒体'), findsNothing);
    expect(find.text('泛听'), findsNothing);
    expect(find.text('精听'), findsNothing);
    expect(find.byTooltip('更多操作'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, '阅读'));
    expect(documentOpens, 1);
    expect(tester.takeException(), isNull);
  });
}
