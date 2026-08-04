import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/discovery_view_model.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/models/discovery.dart';
import 'discovery_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  (DiscoveryViewModel, TestContentPackageRepository) viewModel() {
    final repo = TestContentPackageRepository();
    final vm = DiscoveryViewModel(
      FixtureDiscoveryRepository(),
      TestMediaImportRepository(),
      repo,
      TestMediaLibraryRepository(),
    );
    addTearDown(vm.dispose);
    return (vm, repo);
  }

  test('load selects the first source and its first entry', () async {
    final (vm, _) = viewModel();
    await vm.load();

    final state = vm.state;
    expect(state.loading, isFalse);
    expect(state.sources, hasLength(7));
    expect(state.selectedSourceId, 'c-bbc-learning');
    expect(state.selectedSource?.name, 'BBC Learning English');
    expect(state.entries, hasLength(3));
    expect(state.selectedEntryId, 'i-bbc-1');
  });

  test('selectChannel swaps entries and clears the detail selection', () async {
    final (vm, _) = viewModel();
    await vm.load();

    await vm.selectChannel('c-ted-ed');

    expect(vm.state.selectedSourceId, 'c-ted-ed');
    expect(vm.state.selectedEntryId, 'i-ted-1');
    expect(vm.state.entries.map((entry) => entry.sourceId).toSet(), {
      'c-ted-ed',
    });
  });

  test('selectItem updates the highlighted entry', () async {
    final (vm, _) = viewModel();
    await vm.load();

    vm.selectItem('i-bbc-3');

    expect(vm.state.selectedEntryId, 'i-bbc-3');
  });

  test('an in-flight load completing after dispose stays silent', () async {
    final repo = TestContentPackageRepository();
    final vm = DiscoveryViewModel(
      FixtureDiscoveryRepository(),
      TestMediaImportRepository(),
      repo,
      TestMediaLibraryRepository(),
    );
    final load = vm.load();
    vm.dispose();
    await load;
  });

  test('state snapshots never expose mutable collections', () async {
    final (vm, _) = viewModel();
    await vm.load();

    expect(vm.state.sources.clear, throwsUnsupportedError);
    expect(vm.state.entries.clear, throwsUnsupportedError);
    expect(vm.state.downloadSnapshots.clear, throwsUnsupportedError);
  });

  group('a download that does not succeed', () {
    DiscoveryViewModel failing({bool failRegister = false}) {
      final vm = DiscoveryViewModel(
        FixtureDiscoveryRepository(),
        TestMediaImportRepository(downloadFails: !failRegister),
        TestContentPackageRepository(),
        TestMediaLibraryRepository(failRegister: failRegister),
      );
      addTearDown(vm.dispose);
      return vm;
    }

    testWidgets('keeps the failure on the row instead of reverting to none', (
      tester,
    ) async {
      final vm = failing();
      await tester.runAsync(() => vm.load());

      vm.startDownload('i-bbc-1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.failed);
      expect(vm.state.downloadFailureOf('i-bbc-1'), isNotNull);

      // And it stays: a row the learner is still reading must not time out.
      await tester.pump(const Duration(seconds: 30));
      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.failed);
    });

    testWidgets('a failed row can be retried in place', (tester) async {
      final vm = failing();
      await tester.runAsync(() => vm.load());

      vm.startDownload('i-bbc-1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.failed);

      vm.startDownload('i-bbc-1');
      await tester.pump();
      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.downloading);

      // The retry really re-runs, so this attempt fails on its own terms.
      await tester.pump(const Duration(milliseconds: 120));
      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.failed);
    });

    testWidgets('a rejected registration is reported, not swallowed', (
      tester,
    ) async {
      final vm = failing(failRegister: true);
      await tester.runAsync(() => vm.load());

      vm.startDownload('i-bbc-1');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.failed);
      expect(vm.state.downloadFailureOf('i-bbc-1'), isNotNull);
    });
  });

  testWidgets('a download completing after cancel does not revive the row', (
    tester,
  ) async {
    final imports = TestMediaImportRepository(holdDownload: true);
    final vm = DiscoveryViewModel(
      FixtureDiscoveryRepository(),
      imports,
      TestContentPackageRepository(),
      TestMediaLibraryRepository(),
    );
    addTearDown(vm.dispose);
    await tester.runAsync(() => vm.load());

    vm.startDownload('i-bbc-1');
    await tester.pump();
    expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.downloading);

    vm.cancelDownload('i-bbc-1');
    expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.none);

    // The subprocess wins the race and reports success anyway.
    imports.completers['i-bbc-1']!.complete('/path/to/[i-bbc-1].mp4');
    await tester.pump(const Duration(seconds: 2));

    expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.none);
  });

  testWidgets('startDownload simulates progress until done', (tester) async {
    final (vm, _) = viewModel();
    await tester.runAsync(() => vm.load());

    vm.startDownload('i-bbc-1');
    await tester.pump();
    expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.downloading);

    await tester.pump(const Duration(milliseconds: 480));
    final progress = vm.state.downloadProgressOf('i-bbc-1');
    expect(progress, greaterThan(0));
    expect(progress, lessThan(1));

    await tester.pump(const Duration(seconds: 2));
    expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.done);
    expect(vm.state.downloadProgressOf('i-bbc-1'), 1);
  });

  testWidgets('cancelDownload stops the timer and clears progress', (
    tester,
  ) async {
    final (vm, _) = viewModel();
    await tester.runAsync(() => vm.load());

    vm.startDownload('i-bbc-1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    vm.cancelDownload('i-bbc-1');
    expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.none);

    await tester.pump(const Duration(seconds: 2));
    expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.none);
  });

  testWidgets(
    'startGeneration surfaces machine phases, imports, and marks the package available',
    (tester) async {
      final (vm, repo) = viewModel();
      await tester.runAsync(() => vm.load());

      // Initially checks package
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      expect(vm.state.packageStatusOf('i-bbc-2'), PackageStatus.unknown);

      // Select item and wait for check package to complete in the real event loop
      await tester.runAsync(() async {
        vm.selectItem('i-bbc-2');
        await vm.startDownload('i-bbc-2');
        // Wait for download simulation (completes in 500ms)
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(vm.state.packageStatusOf('i-bbc-2'), PackageStatus.notAvailable);

      vm.startGeneration('i-bbc-2');
      await tester.pump();
      expect(
        vm.state.generationStatusOf('i-bbc-2'),
        ContentGenerationStatus.preparing,
      );

      final run = repo.runs.single;
      expect(repo.requests.single.mediaPath, contains('[i-bbc-2]'));
      expect(repo.requests.single.mediaKind, 'video');
      expect(repo.requests.single.durationMs, 300000);

      run.emitRunning();
      await tester.pump();
      expect(
        vm.state.generationStatusOf('i-bbc-2'),
        ContentGenerationStatus.generating,
      );
      expect(vm.state.generatorPhaseOf('i-bbc-2'), 'transcribing');

      run.completeSuccessfully();
      await tester.pump();
      await tester.pump();
      expect(
        vm.state.generationStatusOf('i-bbc-2'),
        ContentGenerationStatus.completed,
      );
      expect(vm.state.packageStatusOf('i-bbc-2'), PackageStatus.available);
    },
  );

  testWidgets('cancelGeneration cancels the generator run', (tester) async {
    final (vm, repo) = viewModel();
    await tester.runAsync(() => vm.load());

    // Download first to register mediaId
    await tester.runAsync(() async {
      vm.selectItem('i-bbc-2');
      await vm.startDownload('i-bbc-2');
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });

    await tester.pump();
    vm.startGeneration('i-bbc-2');
    await tester.pump();
    expect(
      vm.state.generationStatusOf('i-bbc-2'),
      ContentGenerationStatus.preparing,
    );

    vm.cancelGeneration('i-bbc-2');
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(
      vm.state.generationStatusOf('i-bbc-2'),
      ContentGenerationStatus.cancelled,
    );
    expect(vm.state.packageStatusOf('i-bbc-2'), PackageStatus.notAvailable);
  });

  testWidgets('startGeneration marks failed when the generator fails', (
    tester,
  ) async {
    final (vm, repo) = viewModel();
    await tester.runAsync(() => vm.load());

    await tester.runAsync(() async {
      vm.selectItem('i-bbc-2');
      await vm.startDownload('i-bbc-2');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });

    vm.startGeneration('i-bbc-2');
    await tester.pump();
    repo.runs.single.failWith('provider_failed');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(
      vm.state.generationStatusOf('i-bbc-2'),
      ContentGenerationStatus.failed,
    );
    expect(vm.state.packageStatusOf('i-bbc-2'), PackageStatus.notAvailable);
  });

  testWidgets(
    'startGeneration probes real media duration when the library has none',
    (tester) async {
      final repo = TestContentPackageRepository();
      final vm = DiscoveryViewModel(
        FixtureDiscoveryRepository(),
        TestMediaImportRepository(probedDurationMs: 400660),
        repo,
        TestMediaLibraryRepository(mediaDurationMs: null),
      );
      addTearDown(vm.dispose);
      await tester.runAsync(() => vm.load());

      // Register the download with a media library entry that has no
      // duration, so the generation path must fall back to probing.
      await tester.runAsync(() async {
        vm.selectItem('i-bbc-2');
        await vm.startDownload('i-bbc-2');
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });

      vm.startGeneration('i-bbc-2');
      await tester.pump();
      expect(repo.requests, hasLength(1));
      expect(repo.requests.single.durationMs, 400660);
      repo.runs.single.emitRunning();
      await tester.pump();
      repo.runs.single.completeSuccessfully();
      await tester.pump();
      await tester.pump();
      expect(
        vm.state.generationStatusOf('i-bbc-2'),
        ContentGenerationStatus.completed,
      );
    },
  );

  testWidgets(
    'downloaded media exposes its probed duration via durationMsFor',
    (tester) async {
      final vm = DiscoveryViewModel(
        FixtureDiscoveryRepository(),
        TestMediaImportRepository(probedDurationMs: 400660),
        TestContentPackageRepository(),
        TestMediaLibraryRepository(mediaDurationMs: null),
      );
      addTearDown(vm.dispose);
      await tester.runAsync(() => vm.load());

      await tester.runAsync(() async {
        vm.selectItem('i-bbc-2');
        await vm.startDownload('i-bbc-2');
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });

      expect(vm.durationMsFor('i-bbc-2'), 400660);
    },
  );

  group('honest channel states', () {
    DiscoveryViewModel viewModelFor(
      TestDiscoveryRepository repository, {
      TestMediaImportRepository? importRepository,
      TestMediaLibraryRepository? libraryRepository,
    }) {
      final vm = DiscoveryViewModel(
        repository,
        importRepository ?? TestMediaImportRepository(),
        TestContentPackageRepository(),
        libraryRepository ?? TestMediaLibraryRepository(),
      );
      addTearDown(vm.dispose);
      return vm;
    }

    TestDiscoveryRepository twoChannels({List<MediaEntry> second = const []}) =>
        TestDiscoveryRepository(
          sources: [testMediaSource('c-one'), testMediaSource('c-two')],
          entries: {
            'c-one': [testMediaEntry('e-one', 'c-one')],
            'c-two': second,
          },
        );

    test(
      'switching to an empty channel drops the previous selection',
      () async {
        final vm = viewModelFor(twoChannels());
        await vm.load();
        expect(vm.state.selectedEntryId, 'e-one');

        await vm.selectChannel('c-two');

        expect(vm.state.entries, isEmpty);
        expect(vm.state.selectedEntryId, isNull);
        expect(vm.state.selectedEntry, isNull);
        expect(vm.state.entriesFailure, isNull);
      },
    );

    test('a channel in flight reports loading, not the old shelf', () async {
      final repository = twoChannels(
        second: [testMediaEntry('e-two', 'c-two')],
      );
      final gate = Completer<void>();
      repository.gates['c-two'] = gate;
      final vm = viewModelFor(repository);
      await vm.load();

      final switching = vm.selectChannel('c-two');
      await pumpEventQueue();

      expect(vm.state.entriesLoading, isTrue);
      expect(
        vm.state.entries,
        isEmpty,
        reason: 'no stale cards under the new header',
      );
      expect(vm.state.loading, isFalse);

      gate.complete();
      await switching;

      expect(vm.state.entriesLoading, isFalse);
      expect(vm.state.entries.single.id, 'e-two');
    });

    test('a failed feed is a failure, not an empty channel', () async {
      final repository = twoChannels(
        second: [testMediaEntry('e-two', 'c-two')],
      );
      repository.failingSources.add('c-two');
      final vm = viewModelFor(repository);
      await vm.load();

      await vm.selectChannel('c-two');

      expect(vm.state.entriesFailure, isNotNull);
      expect(vm.state.entries, isEmpty);
      expect(vm.state.entriesLoading, isFalse);

      repository.failingSources.clear();
      await vm.retryEntries();

      expect(vm.state.entriesFailure, isNull);
      expect(vm.state.entries.single.id, 'e-two');
    });

    test('a failed source list stops the spinner and says so', () async {
      final repository = twoChannels()..failSources = true;
      final vm = viewModelFor(repository);

      await vm.load();

      expect(vm.state.loading, isFalse);
      expect(vm.state.sourcesFailure, isNotNull);
      expect(vm.state.sources, isEmpty);

      repository.failSources = false;
      await vm.load();

      expect(vm.state.sourcesFailure, isNull);
      expect(vm.state.selectedSourceId, 'c-one');
    });

    test(
      'a disconnected core leaves the package status undetermined',
      () async {
        final vm = viewModelFor(
          twoChannels(),
          libraryRepository: TestMediaLibraryRepository(available: false),
        );

        await vm.load();
        await pumpEventQueue();

        expect(vm.state.packageStatusOf('e-one'), PackageStatus.undetermined);
      },
    );

    test(
      'a failing library listing leaves the package status undetermined',
      () async {
        final vm = viewModelFor(
          twoChannels(),
          libraryRepository: TestMediaLibraryRepository(failListing: true),
        );

        await vm.load();
        await pumpEventQueue();

        expect(vm.state.packageStatusOf('e-one'), PackageStatus.undetermined);
      },
    );

    testWidgets('switching channels abandons the previous duration workers', (
      tester,
    ) async {
      final repository = TestDiscoveryRepository(
        sources: [testMediaSource('c-one'), testMediaSource('c-two')],
        entries: {
          'c-one': [
            for (var index = 0; index < 6; index++)
              testMediaEntry('e-one-$index', 'c-one'),
          ],
          'c-two': const [],
        },
      );
      final gate = Completer<void>();
      final importRepository = TestMediaImportRepository(
        resolvedDurationMs: 120000,
        resolveGate: gate,
      );
      final vm = viewModelFor(repository, importRepository: importRepository);

      await tester.runAsync(() async {
        await vm.load();
        await pumpEventQueue();
        // Three workers are parked on the gate; the other three entries are
        // still queued behind them.
        expect(importRepository.resolvedUrls, hasLength(3));

        await vm.selectChannel('c-two');
      });

      // Releasing the gate lets the parked workers look at their queue again.
      gate.complete();
      await tester.idle();
      await tester.pump();

      expect(
        importRepository.resolvedUrls,
        hasLength(3),
        reason: 'workers for an off-screen channel must not keep going',
      );
    });
  });

  testWidgets(
    'feed entry durations resolve in the background from the remote video',
    (tester) async {
      final vm = DiscoveryViewModel(
        _FeedRepositoryWithDurations(),
        TestMediaImportRepository(resolvedDurationMs: 247000),
        TestContentPackageRepository(),
        TestMediaLibraryRepository(),
      );
      addTearDown(vm.dispose);
      await tester.runAsync(() async {
        await vm.load();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      expect(vm.durationMsFor('feed-1'), 247000);
      expect(vm.durationMsFor('feed-2'), 247000);
    },
  );
}

/// Feed whose entries carry real YouTube page URLs so the background duration
/// resolution path can fetch metadata for them.
class _FeedRepositoryWithDurations implements DiscoveryRepository {
  static final _source = MediaSource(
    id: 'c-feed',
    name: 'Feed',
    language: 'en',
    description: '',
    cover: ChannelCoverTone.slate,
    type: MediaSourceType.youtube,
    avatarUrl: null,
  );

  static List<MediaEntry> _entry(String id) => [
    MediaEntry(
      id: id,
      sourceId: _source.id,
      title: 'Feed entry $id',
      description: '',
      durationMs: 300000,
      language: 'en',
      publishedOn: '2026-08-01',
      thumbnailUrl: null,
      viewCount: 0,
      hasPackage: false,
      videoUrl: 'https://www.youtube.com/watch?v=$id',
    ),
  ];

  @override
  Future<List<MediaSource>> sources() async => [_source];

  @override
  Future<List<MediaEntry>> entriesFor(String sourceId) async => [
    ..._entry('feed-1'),
    ..._entry('feed-2'),
  ];

  @override
  Future<PackageStatus> checkPackage(String entryId) async =>
      PackageStatus.notAvailable;

  @override
  Future<MediaEntry> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => throw UnimplementedError();

  @override
  Future<MediaSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) => throw UnimplementedError();
}
