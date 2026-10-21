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

MediaItem _media(
  String id,
  String title,
  int updatedAtMs, {
  String kind = 'video',
}) => MediaItem(
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
  triageIntent: null,
  fit: null,
);

MaterialDetails _details(
  String id,
  String title, {
  int updatedAtMs = 1,
  List<MediaRendition> mediaRenditions = const [],
  MaterialShape shape = MaterialShape.audio,
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
    mediaRenditions: mediaRenditions,
    createdAtMs: 1,
  ),
  shape: shape,
);

/// A media-only library row bound to a registered media row.
PersonalLibraryEntry _mediaEntry(
  String id,
  String title, {
  int updatedAtMs = 1,
  String kind = 'audio',
}) => PersonalLibraryEntry(
  details: _details(
    id,
    title,
    updatedAtMs: updatedAtMs,
    mediaRenditions: [
      mediaRendition(
        id: '$id-media',
        mediaId: 'media-$id',
        kind: kind == 'audio'
            ? MediaRenditionKind.audio
            : MediaRenditionKind.video,
        mediaType: kind == 'audio' ? 'audio/mpeg' : 'video/mp4',
        fingerprint: 'fp',
      ),
    ],
    shape: kind == 'audio' ? MaterialShape.audio : MaterialShape.video,
  ),
  mediaEntries: [
    _entry('media-$id', title, updatedAtMs: updatedAtMs, kind: kind),
  ],
);

PersonalLibraryEntry _mixedMediaEntry(String id, String title) =>
    PersonalLibraryEntry(
      details: _details(
        id,
        title,
        mediaRenditions: [
          mediaRendition(
            id: '$id-audio',
            mediaId: 'media-$id-audio',
            kind: MediaRenditionKind.audio,
          ),
          mediaRendition(
            id: '$id-video',
            mediaId: 'media-$id-video',
            kind: MediaRenditionKind.video,
            mediaType: 'video/mp4',
          ),
        ],
        shape: MaterialShape.mixed,
      ),
      mediaEntries: [
        _entry('media-$id-audio', title, kind: 'audio'),
        _entry('media-$id-video', title, kind: 'video'),
      ],
    );

void main() {
  Widget app({
    required VoidCallback onOpenMedia,
    VoidCallback? onOpenOnline,
    List<PersonalLibraryEntry>? personalLibrary,
    List<PersonalLibraryEntry>? offlineEntries,
    void Function(PersonalLibraryEntry entry)? onOpenLibraryEntry,
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
        personalLibrary: personalLibrary,
        offlineEntries: offlineEntries,
        onOpenLibraryEntry: onOpenLibraryEntry ?? (_) {},
        onStartExtensiveEntry: (_) {},
        onStartIntensiveEntry: (_) {},
        onSetLibraryIntent: (_, _) {},
      ),
    ),
  );

  testWidgets('home shows the content sections and opens local media', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openMediaCalls = 0;
    await tester.pumpWidget(app(onOpenMedia: () => openMediaCalls += 1));
    await tester.pumpAndSettle();

    expect(find.text('资料库'), findsOneWidget);
    expect(find.text('导入材料'), findsOneWidget);
    // The library no longer answers "what should I do now" — the continue
    // card belongs to Home, while this page manages retained materials.
    expect(find.text('继续当前内容会话'), findsNothing);

    // The import action offers AV files and supported online media.
    await tester.tap(find.text('导入材料'));
    await tester.pumpAndSettle();
    expect(find.text('打开视频或音频'), findsOneWidget);
    expect(find.text('打开网址'), findsOneWidget);

    await tester.tap(find.text('打开视频或音频'));
    await tester.pumpAndSettle();
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
                  of: find.text('资料库'),
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
          )
          .padding;
    }

    expect(await pageInsetAt(const Size(1200, 800)), ListenPadding.page);
    // Below `homeSidebar` the page folds to the narrow role used by the
    // vocabulary detail.
    expect(await pageInsetAt(const Size(640, 700)), ListenPadding.pageCompact);
    expect(ListenPadding.pageCompact.horizontal / 2, ListenSpacing.gap24);

    // And the content column takes the shared wide cap rather than the 920 it
    // invented, so "how wide may the home column grow" is one decision.
    expect(
      tester
          .widget<ConstrainedBox>(
            find
                .ancestor(
                  of: find.text('资料库'),
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

    expect(find.text('资料库'), findsOneWidget);
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

    await tester.tap(find.text('导入材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开网址'));
    await tester.pumpAndSettle();
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

    // The filter is a view, not a destination: All restores the full library.
    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
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

  testWidgets('audio and video filters view the same AV library', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final audio = _mediaEntry('audio-1', 'An Audio File', kind: 'audio');
    final video = _mediaEntry('video-1', 'A Video File', kind: 'video');
    final mixed = _mixedMediaEntry('mixed-1', 'An AV Material');
    await tester.pumpWidget(
      app(onOpenMedia: () {}, personalLibrary: [audio, video, mixed]),
    );
    await tester.pumpAndSettle();

    // All shows every row.
    expect(find.text('An Audio File'), findsOneWidget);
    expect(find.text('A Video File'), findsOneWidget);
    expect(find.text('An AV Material'), findsOneWidget);

    // Audio keeps audio and combined AV materials.
    await tester.tap(find.widgetWithText(ChoiceChip, '音频'));
    await tester.pumpAndSettle();

    expect(find.text('An Audio File'), findsOneWidget);
    expect(find.text('An AV Material'), findsOneWidget);
    expect(find.text('A Video File'), findsNothing);

    // A mixed source is classified by its primary audio rendition.
    await tester.tap(find.widgetWithText(ChoiceChip, '视频'));
    await tester.pumpAndSettle();

    expect(find.text('An Audio File'), findsNothing);
    expect(find.text('An AV Material'), findsNothing);
    expect(find.text('A Video File'), findsOneWidget);

    // Clearing the view restores the full library.
    await tester.tap(find.widgetWithText(ChoiceChip, '全部类型'));
    await tester.pumpAndSettle();

    expect(find.text('An Audio File'), findsOneWidget);
    expect(find.text('A Video File'), findsOneWidget);
    expect(find.text('An AV Material'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an AV row enters the one workbench session', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var opens = 0;
    await tester.pumpWidget(
      app(
        onOpenMedia: () {},
        personalLibrary: [_mixedMediaEntry('mixed-1', 'An AV Material')],
        onOpenLibraryEntry: (_) => opens += 1,
      ),
    );
    await tester.pumpAndSettle();

    // One primary entry, and no second "read it instead" door hiding in the
    // overflow: the workbench decides what the mixed AV material shows.
    expect(find.text('混合材料'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '继续学习'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '继续学习'));
    expect(opens, 1);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('阅读'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
