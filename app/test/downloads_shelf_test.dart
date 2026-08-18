import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/downloads_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/acquisition_ledger.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/home/downloads_section.dart';

import 'discovery_test_helpers.dart';

/// The downloads shelf: acquired media that is on this machine and not in the
/// Personal Library.
///
/// The state it shows had nowhere to live. Adoption registers a download as
/// Temporary Material, which Core leaves out of both the media library and the
/// materials listing, so a downloaded episode existed only as a line in
/// [AcquisitionLedger] and a chip on its feed row. Keeping is still explicit —
/// nothing here joins the library on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MediaLibraryEntry row({
    required String id,
    required String path,
    bool retained = false,
  }) => TestMediaLibraryRepository.entry(
    id: id,
    path: path,
    retained: retained,
  );

  Future<AcquisitionLedger> ledgerWith(
    List<({String source, String item, String mediaId, String path})> rows,
  ) async {
    final ledger = AcquisitionLedger.inMemory();
    await ledger.load();
    for (final row in rows) {
      await ledger.record(
        AcquisitionLedger.keyFor(sourceId: row.source, itemId: row.item),
        mediaId: row.mediaId,
        path: row.path,
      );
    }
    return ledger;
  }

  group('what the shelf holds', () {
    test('a downloaded episode is listed even though no library lists it',
        () async {
      final library = TestMediaLibraryRepository(
        seed: [row(id: 'm-1', path: '/downloads/ep-1.mp3')],
      );
      final controller = DownloadsController(
        ledger: await ledgerWith([
          (
            source: 'https://feed',
            item: 'ep-1',
            mediaId: 'm-1',
            path: '/downloads/ep-1.mp3',
          ),
        ]),
        repository: library,
        fileService: TestMediaFileService(),
      );
      addTearDown(controller.dispose);

      // Core agrees it is nowhere: acquisition is not retention.
      expect(await library.listMediaLibrary(), isEmpty);

      await controller.refresh();

      expect(controller.entries, hasLength(1));
      expect(controller.entries!.single.path, '/downloads/ep-1.mp3');
      expect(controller.entries!.single.sourceId, 'https://feed');
      expect(controller.entries!.single.itemId, 'ep-1');
    });

    test('a download that was kept leaves the shelf but keeps its record',
        () async {
      // Keeping moves it into the Personal Library, and the same file showing
      // up in both places would say two opposite things about one episode. The
      // ledger row stays: Discovery still recognises the feed item by it.
      final ledger = await ledgerWith([
        (
          source: 'https://feed',
          item: 'ep-1',
          mediaId: 'm-1',
          path: '/store/digest',
        ),
      ]);
      final controller = DownloadsController(
        ledger: ledger,
        repository: TestMediaLibraryRepository(
          seed: [row(id: 'm-1', path: '/store/digest', retained: true)],
        ),
        fileService: TestMediaFileService(),
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.entries, isEmpty);
      expect(
        ledger[AcquisitionLedger.keyFor(
          sourceId: 'https://feed',
          itemId: 'ep-1',
        )],
        isNotNull,
      );
    });

    test('a record whose file is gone is dropped from the ledger too',
        () async {
      final ledger = await ledgerWith([
        (
          source: 'https://feed',
          item: 'ep-1',
          mediaId: 'm-1',
          path: '/downloads/ep-1.mp3',
        ),
      ]);
      final files = TestMediaFileService()..remove('/downloads/ep-1.mp3');
      final controller = DownloadsController(
        ledger: ledger,
        repository: TestMediaLibraryRepository(
          seed: [row(id: 'm-1', path: '/downloads/ep-1.mp3')],
        ),
        fileService: files,
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.entries, isEmpty);
      expect(
        ledger[AcquisitionLedger.keyFor(
          sourceId: 'https://feed',
          itemId: 'ep-1',
        )],
        isNull,
      );
    });

    test('a listing that could not be made is a failure, not an empty shelf',
        () async {
      final controller = DownloadsController(
        ledger: await ledgerWith([
          (
            source: 'https://feed',
            item: 'ep-1',
            mediaId: 'm-1',
            path: '/downloads/ep-1.mp3',
          ),
        ]),
        repository: TestMediaLibraryRepository(failListing: true),
        fileService: TestMediaFileService(),
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.failure, isNotNull);
      expect(
        controller.entries,
        isNull,
        reason: 'a half-checked list must not render as the whole shelf',
      );
    });

    test('without Core the shelf says nothing rather than nothing-downloaded',
        () async {
      final controller = DownloadsController(
        ledger: await ledgerWith([
          (
            source: 'https://feed',
            item: 'ep-1',
            mediaId: 'm-1',
            path: '/downloads/ep-1.mp3',
          ),
        ]),
        repository: TestMediaLibraryRepository(available: false),
        fileService: TestMediaFileService(),
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.entries, isNull);
      expect(controller.failure, isNull);
    });
  });

  group('reclaiming the space', () {
    test('deleting removes the file, the row and the record', () async {
      final ledger = await ledgerWith([
        (
          source: 'https://feed',
          item: 'ep-1',
          mediaId: 'm-1',
          path: '/downloads/ep-1.mp3',
        ),
      ]);
      final files = TestMediaFileService();
      final controller = DownloadsController(
        ledger: ledger,
        repository: TestMediaLibraryRepository(
          seed: [row(id: 'm-1', path: '/downloads/ep-1.mp3')],
        ),
        fileService: files,
      );
      addTearDown(controller.dispose);
      await controller.refresh();

      expect(
        await controller.deleteDownload(controller.entries!.single),
        isTrue,
      );

      expect(controller.entries, isEmpty);
      expect(files.exists('/downloads/ep-1.mp3'), isFalse);
      expect(
        ledger[AcquisitionLedger.keyFor(
          sourceId: 'https://feed',
          itemId: 'ep-1',
        )],
        isNull,
      );
    });

    test('a file that would not delete keeps its row and its record', () async {
      final ledger = await ledgerWith([
        (
          source: 'https://feed',
          item: 'ep-1',
          mediaId: 'm-1',
          path: '/downloads/ep-1.mp3',
        ),
      ]);
      final controller = DownloadsController(
        ledger: ledger,
        repository: TestMediaLibraryRepository(
          seed: [row(id: 'm-1', path: '/downloads/ep-1.mp3')],
        ),
        fileService: _RefusingFileService(),
      );
      addTearDown(controller.dispose);
      await controller.refresh();

      expect(
        await controller.deleteDownload(controller.entries!.single),
        isFalse,
      );

      // Saying the space was reclaimed while the file is still there is the
      // one thing this action must never do.
      expect(controller.entries, hasLength(1));
      expect(
        ledger[AcquisitionLedger.keyFor(
          sourceId: 'https://feed',
          itemId: 'ep-1',
        )],
        isNotNull,
      );
    });
  });

  group('what the section says', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<DownloadedMedia>? entries,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ListenTheme.dark(),
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: DownloadsSection(
                entries: entries,
                failure: null,
                onOpen: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a row states it is not library membership', (tester) async {
      await pump(
        tester,
        entries: [
          DownloadedMedia(
            entryId: 'k',
            sourceId: 'https://feed',
            itemId: 'ep-1',
            media: const MediaItem(
              id: 'm-1',
              path: '/downloads/ep-1.mp3',
              fingerprint: 'fp',
              title: '6 Minute English',
              kind: 'audio',
              durationMs: 360000,
              availability: 'available',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ),
        ],
      );

      expect(find.text('已下载'), findsOneWidget);
      expect(find.text('6 Minute English'), findsOneWidget);
      expect(find.textContaining('不在资料库里'), findsOneWidget);
      expect(find.textContaining('要不要保留'), findsOneWidget);
    });

    testWidgets('an unknown shelf is silent, an empty one says so', (
      tester,
    ) async {
      await pump(tester, entries: null);
      expect(find.text('已下载'), findsNothing);

      await pump(tester, entries: const []);
      expect(find.text('已下载'), findsOneWidget);
      expect(find.text('目前没有已下载的内容。'), findsOneWidget);
    });
  });
}

/// A disk that refuses the delete — a permission, a busy volume.
class _RefusingFileService extends TestMediaFileService {
  @override
  Future<bool> delete(String path) async => false;
}
