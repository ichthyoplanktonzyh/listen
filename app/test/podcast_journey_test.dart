import 'dart:io';

import 'package:llplayer_next/services/acquisition_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/discovery_view_model.dart';
import 'package:llplayer_next/data/repositories/composite_discovery_repository.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/data/repositories/feed_discovery_repository.dart';
import 'package:llplayer_next/models/discovery.dart';

import 'discovery_test_helpers.dart';

/// The podcast journey: feed listing through acquisition into local media.
///
/// What these pin is that the source's own facts drive the journey rather than
/// the app's first source doing so by default. Discovery, playback and
/// acquisition are separate capabilities, so an entry says how — and whether —
/// its bytes may be obtained, and the view model follows that rather than
/// reaching for the external tool every time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const podcastSource = ContentSource(
    id: 'https://feeds.example.com/show.xml',
    name: 'Daily Listening',
    language: 'en',
    description: '',
    cover: ChannelCoverTone.amber,
    kind: ContentSourceKind.podcast,
    avatarUrl: null,
  );

  (DiscoveryViewModel, TestMediaImportRepository) podcastViewModel({
    List<DiscoveryItem>? entries,
    TestMediaLibraryRepository? library,
    AcquisitionLedger? ledger,
    TestMediaFileService? fileService,
    Future<String?> Function()? downloadsDirectory,
  }) {
    final imports = TestMediaImportRepository();
    final vm = DiscoveryViewModel(
      TestDiscoveryRepository(
        sources: const [podcastSource],
        entries: {
          podcastSource.id:
              entries ?? [testPodcastItem('i-bbc-1', podcastSource.id)],
        },
      ),
      importRepository: imports,
      mediaLibraryRepository: library ?? TestMediaLibraryRepository(),
      ledger: ledger,
      fileService: fileService ?? TestMediaFileService(),
      downloadsDirectory: downloadsDirectory,
    );
    addTearDown(vm.dispose);
    return (vm, imports);
  }

  group('acquiring a podcast episode', () {
    testWidgets('fetches the enclosure instead of running the external tool', (
      tester,
    ) async {
      final (vm, imports) = podcastViewModel();
      await vm.load();

      await vm.startDownload('i-bbc-1');
      await tester.pump();

      expect(imports.enclosureRequests, hasLength(1));
      expect(
        imports.enclosureRequests.single.url,
        'https://cdn.example.com/i-bbc-1.mp3',
      );
      expect(imports.downloadedUrls, isEmpty);

      vm.cancelDownload('i-bbc-1');
    });

    testWidgets('passes the advertised size along for the progress fraction', (
      tester,
    ) async {
      final (vm, imports) = podcastViewModel();
      await vm.load();

      await vm.startDownload('i-bbc-1');
      await tester.pump();

      expect(imports.enclosureRequests.single.expectedBytes, 8123456);

      vm.cancelDownload('i-bbc-1');
    });

    testWidgets('does not start an acquisition for an item with no enclosure', (
      tester,
    ) async {
      final (vm, imports) = podcastViewModel(
        entries: [testUnacquirableItem('i-notes', podcastSource.id)],
      );
      await vm.load();

      await vm.startDownload('i-notes');
      await tester.pump();

      expect(imports.enclosureRequests, isEmpty);
      expect(imports.downloadedUrls, isEmpty);
      expect(
        vm.state.acquisitionStateOf('i-notes'),
        DiscoveryItemState.discoverable,
        reason: 'an item with nothing to acquire is discoverable, not '
            'acquirable',
      );
    });

    testWidgets('does not run duration workers against enclosure URLs', (
      tester,
    ) async {
      final (vm, imports) = podcastViewModel();
      await vm.load();
      await tester.pump(const Duration(milliseconds: 100));

      // The feed already stated the duration; spawning yt-dlp at an enclosure
      // URL would be both pointless and wrong.
      expect(imports.resolvedUrls, isEmpty);
      expect(vm.state.entryById('i-bbc-1')?.durationMs, 360000);
    });
  });

  group('start learning an episode', () {
    testWidgets(
      'acquireForLearning fetches the enclosure, registers it, and returns the path',
      (tester) async {
        final (vm, imports) = podcastViewModel();
        await tester.runAsync(() => vm.load());
        await tester.pump(const Duration(milliseconds: 20));

        final path = await tester.runAsync(
          () => vm.acquireForLearning('i-bbc-1'),
        );

        expect(path?.mediaPath, '/path/to/downloaded/[i-bbc-1].mp4');
        expect(imports.enclosureRequests, hasLength(1));
        expect(imports.downloadedUrls, isEmpty);
        expect(
          vm.state.acquisitionStateOf('i-bbc-1'),
          DiscoveryItemState.available,
        );
      },
    );

    testWidgets('two start-learning intents share one enclosure fetch', (
      tester,
    ) async {
      final (vm, imports) = podcastViewModel();
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      // Both intents live inside runAsync so the fake handle's timer runs on
      // the real event loop.
      final result = await tester.runAsync(() async {
        final first = vm.acquireForLearning('i-bbc-1');
        final second = vm.acquireForLearning('i-bbc-1');
        final a = await first;
        final b = await second;
        return (a, b);
      });

      expect(result, isNotNull);
      expect(result!.$1, isNotNull);
      expect(result.$2, same(result.$1));
      expect(imports.enclosureRequests, hasLength(1));
    });
  });

  group('CompositeDiscoveryRepository', () {
    test('lists podcast sources before YouTube ones', () async {
      final composite = CompositeDiscoveryRepository(
        FeedDiscoveryRepository(),
        TestDiscoveryRepository(sources: [testContentSource('c-yt')]),
      );

      final sources = await composite.sources();

      expect(sources.first.kind, ContentSourceKind.podcast);
      expect(sources.last.id, 'c-yt');
    });

    test(
      'routes a feed URL to the podcast side and a channel id to YouTube',
      () async {
        final youtube = TestDiscoveryRepository(
          sources: [testContentSource('c-yt')],
          entries: {
            'c-yt': [testDiscoveryItem('v-1', 'c-yt')],
          },
        );
        final composite = CompositeDiscoveryRepository(
          FeedDiscoveryRepository(),
          youtube,
        );

        expect(await composite.entriesFor('c-yt'), hasLength(1));
        // The podcast side owns anything URL-shaped, so this reaches its fetch
        // and fails there rather than being handed to the YouTube feed.
        await expectLater(
          composite.entriesFor('https://feeds.example.invalid/show.xml'),
          throwsA(isNot(isA<TypeError>())),
        );
      },
    );

    test('sends a pasted YouTube link to the channel resolver', () async {
      final youtube = _RecordingDiscoveryRepository();
      final composite = CompositeDiscoveryRepository(
        FeedDiscoveryRepository(),
        youtube,
      );

      await composite.resolveCustomChannel(
        'https://www.youtube.com/@example',
        TestMediaImportRepository(),
      );

      expect(youtube.resolvedChannels, ['https://www.youtube.com/@example']);
    });
  });

  group('where an acquisition writes', () {
    testWidgets('every download uses the remembered folder, never the chooser',
        (tester) async {
      // The folder chooser used to open on the first download of every launch,
      // and the answer was cached on the view model rather than persisted.
      final asked = <int>[];
      final (vm, imports) = podcastViewModel(
        entries: [
          testPodcastItem('i-bbc-1', podcastSource.id),
          testPodcastItem('i-bbc-2', podcastSource.id),
        ],
        downloadsDirectory: () async {
          asked.add(asked.length);
          return '/remembered/downloads';
        },
      );
      await tester.runAsync(() async {
        await vm.load();
        await vm.startDownload('i-bbc-1');
        await vm.startDownload('i-bbc-2');
      });

      expect(imports.pickerPrompts, isEmpty);
      expect(asked, hasLength(2), reason: 'read per download, so a settings '
          'change takes effect without a restart');
      expect(
        imports.enclosureRequests, hasLength(2),
      );
      vm.cancelDownload('i-bbc-1');
      vm.cancelDownload('i-bbc-2');
    });

    testWidgets('no folder means no acquisition, not a guess', (tester) async {
      final (vm, imports) = podcastViewModel(
        downloadsDirectory: () async => null,
      );
      await tester.runAsync(() async {
        await vm.load();
        await vm.startDownload('i-bbc-1');
      });

      expect(imports.enclosureRequests, isEmpty);
      expect(imports.pickerPrompts, isEmpty);
      expect(
        vm.state.acquisitionStateOf('i-bbc-1'),
        DiscoveryItemState.acquirable,
      );
    });
  });

  group('recognising media a previous session acquired', () {
    test('a podcast episode downloaded before is not offered again', () async {
      // The filename convention that answers this on the YouTube path does not
      // exist for an enclosure: the file is `p0p1qc9j.mp3`, the guid is
      // `urn:bbc:podcast:p0p1qc9j`. Restarting therefore offered the download
      // again, and taking it wrote `episode (2).mp3`.
      final directory = Directory.systemTemp.createTempSync('journey-ledger-');
      addTearDown(() => directory.deleteSync(recursive: true));

      final first = AcquisitionLedger(directory: directory);
      await first.load();
      await first.record(
        '${podcastSource.id}\u0000i-bbc-1',
        mediaId: 'm-1',
        path: '/library/p0p1qc9j.mp3',
      );

      // A fresh instance, as a relaunch would build.
      final restarted = AcquisitionLedger(directory: directory);
      final library = TestMediaLibraryRepository(
        seed: [
          TestMediaLibraryRepository.entry(
            id: 'm-1',
            path: '/library/p0p1qc9j.mp3',
          ),
        ],
      );
      final (vm, _) = podcastViewModel(library: library, ledger: restarted);
      await vm.load();
      await vm.selectChannel(podcastSource.id);
      vm.selectItem('i-bbc-1');
      await pumpEventQueue();

      expect(vm.state.acquisitionStateOf('i-bbc-1'), DiscoveryItemState.available);
      expect(vm.localPathFor('i-bbc-1'), '/library/p0p1qc9j.mp3');
    });

    testWidgets(
      'a download is still recognised after a restart, though the Personal '
      'Library never lists it',
      (tester) async {
        // The real shape of the bug, end to end. Adoption registers a
        // download as Temporary Material (`retain: false` — acquisition is
        // not retention, CONTEXT.md Retention Decision), and Core's Personal
        // Library projection lists retained media only. Recognition used to
        // confirm its ledger row against that projection, never found the
        // episode there, deleted the row as stale, and offered the very
        // download that had already happened — writing `episode (2).mp3` when
        // it was taken.
        final directory = Directory.systemTemp.createTempSync('journey-restart-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final library = TestMediaLibraryRepository();
        final files = TestMediaFileService();

        final (vm, imports) = podcastViewModel(
          library: library,
          ledger: AcquisitionLedger(directory: directory),
          fileService: files,
        );
        await tester.runAsync(() async {
          await vm.load();
          await vm.startDownload('i-bbc-1');
          await Future<void>.delayed(const Duration(milliseconds: 700));
        });

        expect(imports.enclosureRequests, hasLength(1));
        expect(
          vm.state.acquisitionStateOf('i-bbc-1'),
          DiscoveryItemState.available,
        );
        expect(
          await library.listMediaLibrary(),
          isEmpty,
          reason: 'an adopted download is Temporary Material: registered and '
              'readable, but not Personal Library membership',
        );

        // Relaunch: fresh view model, fresh ledger instance reading the same
        // file, the same Core.
        final (restarted, restartedImports) = podcastViewModel(
          library: library,
          ledger: AcquisitionLedger(directory: directory),
          fileService: files,
        );
        await tester.runAsync(() async {
          await restarted.load();
          await pumpEventQueue();
        });

        expect(
          restarted.state.acquisitionStateOf('i-bbc-1'),
          DiscoveryItemState.available,
          reason: 'the episode is on this machine; the row must not offer to '
              'download it a second time',
        );
        expect(
          restarted.localPathFor('i-bbc-1'),
          '/path/to/downloaded/[i-bbc-1].mp4',
        );

        // And the intent opens what is there rather than fetching again.
        final target = await tester.runAsync(
          () => restarted.acquireForLearning('i-bbc-1'),
        );
        expect(target?.mediaPath, '/path/to/downloaded/[i-bbc-1].mp4');
        expect(restartedImports.enclosureRequests, isEmpty);
      },
    );

    test('a record whose file was deleted from disk is dropped', () async {
      // Core records a path, never the file's continued existence. A row that
      // still claimed "on this device" after the folder was emptied would be
      // the same confident lie in the other direction.
      final ledger = AcquisitionLedger.inMemory();
      await ledger.load();
      await ledger.record(
        '${podcastSource.id}\u0000i-bbc-1',
        mediaId: 'm-1',
        path: '/library/p0p1qc9j.mp3',
      );
      final files = TestMediaFileService()..remove('/library/p0p1qc9j.mp3');

      final (vm, _) = podcastViewModel(
        library: TestMediaLibraryRepository(
          seed: [
            TestMediaLibraryRepository.entry(
              id: 'm-1',
              path: '/library/p0p1qc9j.mp3',
              // Retained on purpose: Core knows this media by every route
              // there is, so the only fact that can refute the row is the
              // file itself being gone.
              retained: true,
            ),
          ],
        ),
        ledger: ledger,
        fileService: files,
      );
      await vm.load();
      vm.selectItem('i-bbc-1');
      await pumpEventQueue();

      expect(
        vm.state.acquisitionStateOf('i-bbc-1'),
        DiscoveryItemState.acquirable,
      );
      expect(ledger['${podcastSource.id}\u0000i-bbc-1'], isNull);
    });

    test('every row of the shelf reports its own local state', () async {
      // Only the selected entry used to be reconciled, so a shelf of episodes
      // the learner had already downloaded rendered a download button on every
      // row but one — the answer was in the ledger the whole time.
      final ledger = AcquisitionLedger.inMemory();
      await ledger.load();
      await ledger.record(
        '${podcastSource.id}\u0000i-bbc-3',
        mediaId: 'm-3',
        path: '/library/three.mp3',
      );

      final (vm, _) = podcastViewModel(
        entries: [
          testPodcastItem('i-bbc-1', podcastSource.id),
          testPodcastItem('i-bbc-2', podcastSource.id),
          testPodcastItem('i-bbc-3', podcastSource.id),
        ],
        library: TestMediaLibraryRepository(
          seed: [
            TestMediaLibraryRepository.entry(
              id: 'm-3',
              path: '/library/three.mp3',
            ),
          ],
        ),
        ledger: ledger,
      );
      await vm.load();
      await pumpEventQueue();

      expect(vm.state.selectedEntryId, 'i-bbc-1');
      expect(
        vm.state.acquisitionStateOf('i-bbc-3'),
        DiscoveryItemState.available,
        reason: 'a downloaded episode reads as downloaded without being '
            'selected first',
      );
      expect(vm.localPathFor('i-bbc-3'), '/library/three.mp3');
      expect(
        vm.state.acquisitionStateOf('i-bbc-2'),
        DiscoveryItemState.acquirable,
      );
    });

    test('a record whose file Core no longer knows is dropped', () async {
      // The ledger says what was acquired, not what survives. A row that
      // claimed a file that is gone would be the confident lie it exists to
      // avoid, and re-checking it forever would be the other failure.
      final directory = Directory.systemTemp.createTempSync('journey-ledger-');
      addTearDown(() => directory.deleteSync(recursive: true));

      final ledger = AcquisitionLedger(directory: directory);
      await ledger.load();
      await ledger.record(
        '${podcastSource.id}\u0000i-bbc-1',
        mediaId: 'm-gone',
        path: '/gone.mp3',
      );

      final (vm, _) = podcastViewModel(
        library: TestMediaLibraryRepository(),
        ledger: ledger,
      );
      await vm.load();
      await vm.selectChannel(podcastSource.id);
      vm.selectItem('i-bbc-1');
      await pumpEventQueue();

      expect(vm.state.acquisitionStateOf('i-bbc-1'), DiscoveryItemState.acquirable);
      expect(ledger['i-bbc-1'], isNull);
    });
  });
}

class _RecordingDiscoveryRepository implements DiscoveryRepository {
  final resolvedChannels = <String>[];

  @override
  Future<List<ContentSource>> sources() async => const [];

  @override
  Future<List<DiscoveryItem>> entriesFor(String sourceId) async => const [];

  @override
  Future<void> refreshSource(String sourceId) async {}

  @override
  Future<DiscoveryItem> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => throw UnimplementedError();

  @override
  Future<ContentSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) async {
    resolvedChannels.add(url);
    return testContentSource('c-resolved');
  }
}
