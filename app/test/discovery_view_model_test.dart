import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/discovery_view_model.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/models/discovery.dart';
import 'discovery_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DiscoveryViewModel viewModel({
    TestMediaImportRepository? imports,
    TestMediaLibraryRepository? library,
  }) {
    final vm = DiscoveryViewModel(
      FixtureDiscoveryRepository(),
      imports ?? TestMediaImportRepository(),
      library ?? TestMediaLibraryRepository(),
    );
    addTearDown(vm.dispose);
    return vm;
  }

  /// The Stage 2 lock: Discovery's constructor must not know about packages
  /// or generation at all. The strongest proof is structural — the controller
  /// never imports or mentions the capability, so "Gen was not called" is
  /// guaranteed by construction rather than by mocking a generator and
  /// asserting it stayed silent.
  test('DiscoveryViewModel has no package or generator dependency', () {
    final source = File(
      'lib/controllers/discovery_view_model.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('ContentPackageRepository')));
    expect(source, isNot(contains('ListenGen')));
    expect(source, isNot(contains('PackageStatus')));
    expect(source, isNot(contains('ContentGenerationStatus')));
    expect(source, isNot(contains('primaryTrackId')));
  });

  test('load selects the first source and its first entry', () async {
    final vm = viewModel();
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
    final vm = viewModel();
    await vm.load();

    await vm.selectChannel('c-ted-ed');

    expect(vm.state.selectedSourceId, 'c-ted-ed');
    expect(vm.state.selectedEntryId, 'i-ted-1');
    expect(vm.state.entries.map((entry) => entry.sourceId).toSet(), {
      'c-ted-ed',
    });
  });

  test('selectItem updates the highlighted entry', () async {
    final vm = viewModel();
    await vm.load();

    vm.selectItem('i-bbc-3');

    expect(vm.state.selectedEntryId, 'i-bbc-3');
  });

  test('an in-flight load completing after dispose stays silent', () async {
    final vm = DiscoveryViewModel(
      FixtureDiscoveryRepository(),
      TestMediaImportRepository(),
      TestMediaLibraryRepository(),
    );
    final load = vm.load();
    vm.dispose();
    await load;
  });

  test('state snapshots never expose mutable collections', () async {
    final vm = viewModel();
    await vm.load();

    expect(vm.state.sources.clear, throwsUnsupportedError);
    expect(vm.state.entries.clear, throwsUnsupportedError);
    expect(vm.state.downloadSnapshots.clear, throwsUnsupportedError);
    expect(vm.state.mediaAvailability.clear, throwsUnsupportedError);
  });

  group('local media reconciliation', () {
    testWidgets(
      'a library entry with primaryTrackId == null is LOCAL and learnable',
      (tester) async {
        // The exact Stage 2 regression: the old model read `primaryTrackId`
        // and refused to open media without a package. A local entry with no
        // transcript is still local; Workbench owns transcript readiness.
        final library = TestMediaLibraryRepository(
          seed: [
            TestMediaLibraryRepository.entry(
              id: 'media-i-bbc-1',
              path: '/library/[i-bbc-1].mp4',
            ),
          ],
        );
        final vm = viewModel(library: library);
        await tester.runAsync(() => vm.load());

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));

        expect(
          vm.state.mediaAvailabilityOf('i-bbc-1'),
          DiscoveryMediaAvailability.local,
        );
        expect(vm.localPathFor('i-bbc-1'), '/library/[i-bbc-1].mp4');
        expect(
          vm.state.downloadStateOf('i-bbc-1'),
          DownloadState.done,
          reason: 'local media reads as an acquisition already completed',
        );
        // Workbench decides transcript readiness, never Discovery.
        expect(
          vm.state.mediaAvailabilityOf('i-bbc-1'),
          isNot(DiscoveryMediaAvailability.remote),
        );
      },
    );

    testWidgets(
      'acquireForLearning returns the existing path without invoking the downloader',
      (tester) async {
        final imports = TestMediaImportRepository();
        final library = TestMediaLibraryRepository(
          seed: [
            TestMediaLibraryRepository.entry(
              id: 'media-i-bbc-1',
              path: '/library/[i-bbc-1].mp4',
            ),
          ],
        );
        final vm = viewModel(imports: imports, library: library);
        await tester.runAsync(() => vm.load());
        await tester.pump(const Duration(milliseconds: 20));

        final path = await tester.runAsync(
          () => vm.acquireForLearning('i-bbc-1'),
        );

        expect(path, '/library/[i-bbc-1].mp4');
        expect(imports.downloadedUrls, isEmpty);
        expect(imports.enclosureRequests, isEmpty);
      },
    );

    testWidgets('no matching media reads as remote, never "package missing"', (
      tester,
    ) async {
      final vm = viewModel();
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.remote,
      );
      expect(vm.localPathFor('i-bbc-1'), isNull);
    });

    testWidgets('a disconnected core is undetermined, not remote', (
      tester,
    ) async {
      final vm = viewModel(
        library: TestMediaLibraryRepository(available: false),
      );
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.undetermined,
      );
    });

    testWidgets('a failing library listing is undetermined, not remote', (
      tester,
    ) async {
      final vm = viewModel(
        library: TestMediaLibraryRepository(failListing: true),
      );
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.undetermined,
      );
    });
  });

  group('the start-learning acquisition intent', () {
    testWidgets(
      'remote + acquireForLearning: one download, register, ledger, local, path',
      (tester) async {
        final imports = TestMediaImportRepository(probedDurationMs: 400660);
        final library = TestMediaLibraryRepository();
        final vm = viewModel(imports: imports, library: library);
        await tester.runAsync(() => vm.load());
        await tester.pump(const Duration(milliseconds: 20));

        final path = await tester.runAsync(
          () => vm.acquireForLearning('i-bbc-1'),
        );

        expect(path, '/path/to/downloaded/[i-bbc-1].mp4');
        expect(imports.downloadedUrls, ['https://www.youtube.com/watch?v=i-bbc-1']);
        expect(
          vm.state.mediaAvailabilityOf('i-bbc-1'),
          DiscoveryMediaAvailability.local,
        );
        expect(vm.localPathFor('i-bbc-1'), path);
        expect(vm.durationMsFor('i-bbc-1'), 400660);
        expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.done);
      },
    );

    testWidgets('registration failure keeps a typed failure and returns null', (
      tester,
    ) async {
      final vm = viewModel(
        library: TestMediaLibraryRepository(failRegister: true),
      );
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      final path = await tester.runAsync(
        () => vm.acquireForLearning('i-bbc-1'),
      );

      expect(path, isNull);
      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.failed);
      expect(vm.state.downloadFailureOf('i-bbc-1'), isNotNull);
      expect(vm.localPathFor('i-bbc-1'), isNull);
    });

    testWidgets('cancel resolves the intent with no path and no adoption', (
      tester,
    ) async {
      final imports = TestMediaImportRepository(holdDownload: true);
      final vm = viewModel(imports: imports);
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      final pending = vm.acquireForLearning('i-bbc-1');
      await tester.pump();
      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.downloading);

      vm.cancelDownload('i-bbc-1');
      final path = await tester.runAsync(() => pending);
      expect(path, isNull);
      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.none);

      // The subprocess wins the race and reports success anyway; the late
      // completion must not adopt the media or open anything.
      imports.completers['i-bbc-1']!.complete('/path/to/[i-bbc-1].mp4');
      await tester.pump(const Duration(seconds: 2));

      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.none);
      expect(vm.localPathFor('i-bbc-1'), isNull);
      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.remote,
      );
    });

    testWidgets('two acquireForLearning calls share one acquisition', (
      tester,
    ) async {
      final imports = TestMediaImportRepository();
      final vm = viewModel(imports: imports);
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      // Both intents are created inside runAsync so the fake handle's timer
      // runs on the real event loop; created outside, the fake zone would
      // hold a fake timer that runAsync never advances.
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
      expect(imports.downloadedUrls, hasLength(1));
      expect(imports.enclosureRequests, isEmpty);
    });

    testWidgets(
      'a background startDownload plus acquireForLearning is one acquisition',
      (tester) async {
        final imports = TestMediaImportRepository(holdDownload: true);
        final vm = viewModel(imports: imports);
        await tester.runAsync(() => vm.load());
        await tester.pump(const Duration(milliseconds: 20));

        final path = await tester.runAsync(() async {
          final background = vm.startDownload('i-bbc-1');
          final intent = vm.acquireForLearning('i-bbc-1');
          // Let the launch land before asserting the shared in-flight state.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(
            vm.state.downloadStateOf('i-bbc-1'),
            DownloadState.downloading,
          );
          imports.completers['i-bbc-1']!.complete('/path/to/[i-bbc-1].mp4');
          final result = await intent;
          await background;
          return result;
        });

        expect(path, '/path/to/[i-bbc-1].mp4');
        expect(imports.downloadedUrls, hasLength(1));
      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.local,
      );
      },
    );

    testWidgets(
      'established background download + acquireForLearning joins one handle',
      (tester) async {
        final imports = TestMediaImportRepository();
        final vm = viewModel(imports: imports);
        await tester.runAsync(() => vm.load());
        await tester.pump(const Duration(milliseconds: 20));

        final path = await tester.runAsync(() async {
          // The first download fully returns first: the handle is attached
          // and the controller is in `downloading` before the intent exists.
          // A second `startDownload` at this point must join, never relaunch.
          await vm.startDownload('i-bbc-1');
          expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.downloading);

          return vm.acquireForLearning('i-bbc-1');
        });

        expect(path, '/path/to/downloaded/[i-bbc-1].mp4');
        expect(
          imports.downloadedUrls,
          hasLength(1),
          reason: 'the intent must join the established download, not start '
              'a second one',
        );
        expect(imports.enclosureRequests, isEmpty);
        expect(
          vm.state.mediaAvailabilityOf('i-bbc-1'),
          DiscoveryMediaAvailability.local,
        );
      },
    );

    testWidgets('cancel before handle attach cannot revive acquisition', (
      tester,
    ) async {
      final gate = Completer<void>();
      final imports = TestMediaImportRepository(downloadLaunchGate: gate);
      final library = TestMediaLibraryRepository();
      final vm = viewModel(imports: imports, library: library);
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      final result = await tester.runAsync(() async {
        final pending = vm.acquireForLearning('i-bbc-1');
        // Let the launch reach the downloader call: `starting()` has run but
        // the handle is still parked on the gate — the exact race window.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(imports.downloadedUrls, hasLength(1));

        vm.cancelDownload('i-bbc-1');
        final path = await pending;
        expect(path, isNull);

        // Release the launch: the stale handle lands and must be dropped
        // without attach, without adoption, without reviving anything.
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return path;
      });

      expect(result, isNull);
      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.none);
      expect(vm.localPathFor('i-bbc-1'), isNull);
      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.remote,
      );
      expect(
        await library.listMediaLibrary(),
        isEmpty,
        reason: 'a cancelled launch must never reach Core registration',
      );

      // The launch bookkeeping survived the stale attempt: a fresh intent
      // starts and completes a real download on its own terms.
      imports.downloadLaunchGate = null;
      final retry = await tester.runAsync(
        () => vm.acquireForLearning('i-bbc-1'),
      );
      expect(retry, '/path/to/downloaded/[i-bbc-1].mp4');
      expect(imports.downloadedUrls, hasLength(2));
      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.local,
      );
    });

    testWidgets('local → removed → refresh clears stale local path', (
      tester,
    ) async {
      final library = TestMediaLibraryRepository(
        seed: [
          TestMediaLibraryRepository.entry(
            id: 'media-i-bbc-1',
            path: '/library/[i-bbc-1].mp4',
          ),
        ],
      );
      final vm = viewModel(library: library);
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.local,
      );
      expect(vm.localPathFor('i-bbc-1'), '/library/[i-bbc-1].mp4');
      expect(vm.state.downloadStateOf('i-bbc-1'), DownloadState.done);

      // The library row disappears (folder emptied, file gone from Core).
      library.clearEntries();
      await vm.refreshMediaAvailability('i-bbc-1');
      await tester.pump();

      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.remote,
      );
      expect(vm.localPathFor('i-bbc-1'), isNull);
      expect(
        vm.state.downloadStateOf('i-bbc-1'),
        DownloadState.none,
        reason: 'the completed projection must not keep saying "on device"',
      );

      // Start Learning must not resurrect the stale path from an old answer.
      final path = await tester.runAsync(
        () => vm.acquireForLearning('i-bbc-1'),
      );
      expect(path, isNotNull);
      expect(path, isNot('/library/[i-bbc-1].mp4'));
      expect(
        vm.state.mediaAvailabilityOf('i-bbc-1'),
        DiscoveryMediaAvailability.local,
      );
    });

    testWidgets('an unacquirable entry resolves with no path and no download', (
      tester,
    ) async {
      final source = TestDiscoveryRepository(
        sources: [testMediaSource('c-notes')],
        entries: {
          'c-notes': [testUnacquirableEntry('i-notes', 'c-notes')],
        },
      );
      final unacquirable = DiscoveryViewModel(
        source,
        TestMediaImportRepository(),
        TestMediaLibraryRepository(),
      );
      addTearDown(unacquirable.dispose);
      await tester.runAsync(() => unacquirable.load());
      await tester.pump(const Duration(milliseconds: 20));

      final path = await tester.runAsync(
        () => unacquirable.acquireForLearning('i-notes'),
      );

      expect(path, isNull);
      expect(unacquirable.state.downloadStateOf('i-notes'), DownloadState.none);
      expect(unacquirable.state.downloadSnapshots, isEmpty);
    });
  });

  group('a download that does not succeed', () {
    DiscoveryViewModel failing({bool failRegister = false}) {
      final vm = viewModel(
        imports: TestMediaImportRepository(downloadFails: !failRegister),
        library: TestMediaLibraryRepository(failRegister: failRegister),
      );
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
    final vm = viewModel(imports: imports);
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
    final vm = viewModel();
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
    final vm = viewModel();
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
    'downloaded media exposes its probed duration via durationMsFor',
    (tester) async {
      final vm = viewModel(
        imports: TestMediaImportRepository(probedDurationMs: 400660),
        library: TestMediaLibraryRepository(mediaDurationMs: null),
      );
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
      'a disconnected core leaves the media availability undetermined',
      () async {
        final vm = viewModelFor(
          twoChannels(),
          libraryRepository: TestMediaLibraryRepository(available: false),
        );

        await vm.load();
        await pumpEventQueue();

        expect(
          vm.state.mediaAvailabilityOf('e-one'),
          DiscoveryMediaAvailability.undetermined,
        );
      },
    );

    test(
      'a failing library listing leaves the media availability undetermined',
      () async {
        final vm = viewModelFor(
          twoChannels(),
          libraryRepository: TestMediaLibraryRepository(failListing: true),
        );

        await vm.load();
        await pumpEventQueue();

        expect(
          vm.state.mediaAvailabilityOf('e-one'),
          DiscoveryMediaAvailability.undetermined,
        );
      },
    );

    test('refreshSelectedMediaAvailability rechecks the selected entry', () async {
      final library = TestMediaLibraryRepository(available: false);
      final vm = viewModelFor(
        twoChannels(),
        libraryRepository: library,
      );
      await vm.load();
      await pumpEventQueue();
      expect(
        vm.state.mediaAvailabilityOf('e-one'),
        DiscoveryMediaAvailability.undetermined,
      );

      // Core comes up: a fresh connected generation is the meaningful
      // invalidation, and the recheck must turn the stale answer around.
      library.available = true;
      library.addEntry(
        TestMediaLibraryRepository.entry(
          id: 'media-e-one',
          path: '/library/[e-one].mp4',
        ),
      );
      await vm.refreshSelectedMediaAvailability();

      expect(
        vm.state.mediaAvailabilityOf('e-one'),
        DiscoveryMediaAvailability.local,
      );
      expect(vm.localPathFor('e-one'), '/library/[e-one].mp4');
    });

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

/// A feed whose entries carry real YouTube page URLs so the background duration
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
      // The Atom feed states no duration; that is why the workers run.
      durationMs: null,
      language: 'en',
      publishedOn: '2026-08-01',
      thumbnailUrl: null,
      viewCount: 0,
      acquisition: MediaAcquisition.externalTool,
      mediaUrl: 'https://www.youtube.com/watch?v=$id',
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
