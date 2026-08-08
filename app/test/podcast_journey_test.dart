import 'dart:io';

import 'package:llplayer_next/services/acquisition_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/discovery_view_model.dart';
import 'package:llplayer_next/data/repositories/composite_discovery_repository.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/data/repositories/podcast_discovery_repository.dart';
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

  const podcastSource = MediaSource(
    id: 'https://feeds.example.com/show.xml',
    name: 'Daily Listening',
    language: 'en',
    description: '',
    cover: ChannelCoverTone.amber,
    type: MediaSourceType.podcast,
    avatarUrl: null,
  );

  (DiscoveryViewModel, TestMediaImportRepository) podcastViewModel({
    List<MediaEntry>? entries,
    TestMediaLibraryRepository? library,
    AcquisitionLedger? ledger,
  }) {
    final imports = TestMediaImportRepository();
    final vm = DiscoveryViewModel(
      TestDiscoveryRepository(
        sources: const [podcastSource],
        entries: {
          podcastSource.id:
              entries ?? [testPodcastEntry('i-bbc-1', podcastSource.id)],
        },
      ),
      imports,
      library ?? TestMediaLibraryRepository(),
      ledger,
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
        entries: [testUnacquirableEntry('i-notes', podcastSource.id)],
      );
      await vm.load();

      await vm.startDownload('i-notes');
      await tester.pump();

      expect(imports.enclosureRequests, isEmpty);
      expect(imports.downloadedUrls, isEmpty);
      expect(vm.state.downloadStateOf('i-notes'), DownloadState.none);
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

        expect(path, '/path/to/downloaded/[i-bbc-1].mp4');
        expect(imports.enclosureRequests, hasLength(1));
        expect(imports.downloadedUrls, isEmpty);
        expect(
          vm.state.mediaAvailabilityOf('i-bbc-1'),
          DiscoveryMediaAvailability.local,
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
        PodcastDiscoveryRepository(),
        TestDiscoveryRepository(sources: [testMediaSource('c-yt')]),
      );

      final sources = await composite.sources();

      expect(sources.first.type, MediaSourceType.podcast);
      expect(sources.last.id, 'c-yt');
    });

    test(
      'routes a feed URL to the podcast side and a channel id to YouTube',
      () async {
        final youtube = TestDiscoveryRepository(
          sources: [testMediaSource('c-yt')],
          entries: {
            'c-yt': [testMediaEntry('v-1', 'c-yt')],
          },
        );
        final composite = CompositeDiscoveryRepository(
          PodcastDiscoveryRepository(),
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
        PodcastDiscoveryRepository(),
        youtube,
      );

      await composite.resolveCustomChannel(
        'https://www.youtube.com/@example',
        TestMediaImportRepository(),
      );

      expect(youtube.resolvedChannels, ['https://www.youtube.com/@example']);
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
        'i-bbc-1',
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

      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.done);
      expect(vm.localPathFor('i-bbc-1'), '/library/p0p1qc9j.mp3');
    });

    test('a record whose file Core no longer knows is dropped', () async {
      // The ledger says what was acquired, not what survives. A row that
      // claimed a file that is gone would be the confident lie it exists to
      // avoid, and re-checking it forever would be the other failure.
      final directory = Directory.systemTemp.createTempSync('journey-ledger-');
      addTearDown(() => directory.deleteSync(recursive: true));

      final ledger = AcquisitionLedger(directory: directory);
      await ledger.load();
      await ledger.record('i-bbc-1', mediaId: 'm-gone', path: '/gone.mp3');

      final (vm, _) = podcastViewModel(
        library: TestMediaLibraryRepository(),
        ledger: ledger,
      );
      await vm.load();
      await vm.selectChannel(podcastSource.id);
      vm.selectItem('i-bbc-1');
      await pumpEventQueue();

      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.none);
      expect(ledger['i-bbc-1'], isNull);
    });
  });
}

class _RecordingDiscoveryRepository implements DiscoveryRepository {
  final resolvedChannels = <String>[];

  @override
  Future<List<MediaSource>> sources() async => const [];

  @override
  Future<List<MediaEntry>> entriesFor(String sourceId) async => const [];

  @override
  Future<MediaEntry> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => throw UnimplementedError();

  @override
  Future<MediaSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) async {
    resolvedChannels.add(url);
    return testMediaSource('c-resolved');
  }
}
