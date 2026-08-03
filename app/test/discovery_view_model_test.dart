import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/discovery_view_model.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';
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
    expect(vm.state.downloads.clear, throwsUnsupportedError);
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

  testWidgets(
    'startGeneration marks failed when the generator fails',
    (tester) async {
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
    },
  );
}
