import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/home/listening_home.dart';

MediaItem _media(String id, String title, int updatedAtMs) => MediaItem(
  id: id,
  path: '/media/$id.mp4',
  fingerprint: 'fp-$id',
  title: title,
  kind: 'video',
  durationMs: 60000,
  availability: 'local',
  createdAtMs: 1,
  updatedAtMs: updatedAtMs,
);

MediaLibraryEntry _entry(String id, String title, {int updatedAtMs = 1}) =>
    MediaLibraryEntry(
      media: _media(id, title, updatedAtMs),
      primaryTrackId: null,
      fit: null,
      triageIntent: null,
      familiarMaterial: false,
    );

void main() {
  Widget app({
    required VoidCallback onOpenMedia,
    VoidCallback? onOpenOnline,
    List<MediaLibraryEntry>? mediaLibrary,
    List<MediaLibraryEntry>? offlineEntries,
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
        mediaLibrary: mediaLibrary,
        offlineEntries: offlineEntries,
        familiarSupplyEnabled: true,
        onOpenLibraryEntry: (_) {},
        onStartExtensiveEntry: (_) {},
        onStartIntensiveEntry: (_) {},
        onSetLibraryIntent: (entry, intent) {},
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

    await tester.pumpWidget(app(onOpenMedia: () => openMediaCalls += 1));
    await tester.pumpAndSettle();

    expect(find.text('添加内容来源'), findsOneWidget);
    // The library is a segment of "listen" now: it carries no page title of
    // its own, and no longer answers "what should I do now" — the continue
    // card and the status strip moved to the today pane.
    expect(find.text('继续当前内容会话'), findsNothing);

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

    final online = _entry('online-1', 'Online Media One');
    final offline = _entry('offline-1', 'Offline Media One');
    await tester.pumpWidget(
      app(
        onOpenMedia: () {},
        mediaLibrary: [online, offline],
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
  // ordering, not a place — this pins it as one.
  testWidgets('recently-studied is an ordering on the library, not a room', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final older = _entry('older', 'Older Media', updatedAtMs: 1000);
    final newer = _entry('newer', 'Newer Media', updatedAtMs: 2000);
    await tester.pumpWidget(
      app(onOpenMedia: () {}, mediaLibrary: [older, newer]),
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
}
