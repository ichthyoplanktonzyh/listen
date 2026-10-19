import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/media_import_file_service.dart';
import 'package:llplayer_next/settings.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/settings/managed_store_settings.dart';

/// The managed asset store location: no custom path is the app-managed
/// *default* under Application Support, a chosen location that vanished is
/// *missing* (never "you never chose one"), and clearing returns to the
/// default. The two send the user to two different remedies.
void main() {
  test('the managed store path survives the persisted shape', () {
    const settings = AppSettings(mediaLibraryPath: '/Volumes/Study/media');

    // Round-tripped through the map `save` writes, so a key typo in either
    // direction fails here rather than at the user's next launch.
    final reloaded = AppSettings.fromJson(settings.toJson());

    expect(reloaded.mediaLibraryPath, '/Volumes/Study/media');
    // A settings file written before this setting existed has no custom path.
    expect(AppSettings.fromJson({'version': 8}).mediaLibraryPath, isEmpty);
    expect(const AppSettings().mediaLibraryPath, isEmpty);
  });

  test('the app-managed default store lives under Application Support', () {
    final home = Platform.environment['HOME'];
    expect(
      AppSettings.defaultManagedStorePath,
      '$home/Library/Application Support/listen/managed-assets',
    );
  });

  test('setting, reading back and clearing the custom location', () async {
    final directory = await Directory.systemTemp.createTemp('managed-store');
    addTearDown(() => directory.delete(recursive: true));
    final controller = _InMemorySettingsController();
    addTearDown(controller.dispose);

    // No custom path: the default store, which is a real location.
    expect(controller.managedStoreLocation, (
      path: AppSettings.defaultManagedStorePath,
      state: StorageLocationState.appManaged,
    ));

    await controller.setManagedStorePath(directory.path);
    expect(controller.managedStoreLocation, (
      path: directory.path,
      state: StorageLocationState.ready,
    ));
    expect(controller.settings.mediaLibraryPath, directory.path);
    expect(controller.saves, 1);

    await controller.clearManagedStoreLocation();
    expect(controller.managedStoreLocation, (
      path: AppSettings.defaultManagedStorePath,
      state: StorageLocationState.appManaged,
    ));
    expect(controller.settings.mediaLibraryPath, isEmpty);
    expect(controller.saves, 2);
  });

  test(
    'a custom location that is gone reads as missing, not as default',
    () async {
      final directory = await Directory.systemTemp.createTemp('managed-store');
      final controller = _InMemorySettingsController();
      addTearDown(controller.dispose);
      await controller.setManagedStorePath(directory.path);

      await directory.delete(recursive: true);
      await controller.refreshManagedStoreState();

      expect(controller.managedStoreLocation, (
        path: directory.path,
        state: StorageLocationState.missing,
      ));
      // The path is kept: the user chose it, and the drive may come back.
      expect(controller.settings.mediaLibraryPath, directory.path);
    },
  );

  test('a cancelled picker leaves the chosen location alone', () async {
    final directory = await Directory.systemTemp.createTemp('managed-store');
    addTearDown(() => directory.delete(recursive: true));
    final picker = _FakeFolderPicker();
    final controller = _InMemorySettingsController(files: picker);
    addTearDown(controller.dispose);

    picker.next = directory.path;
    final chosen = await controller.chooseManagedStoreLocation(
      confirmButtonText: 'Use this folder',
    );
    expect(chosen, (path: directory.path, state: StorageLocationState.ready));
    expect(picker.confirmButtonTexts, ['Use this folder']);

    picker.next = null;
    final afterCancel = await controller.chooseManagedStoreLocation(
      confirmButtonText: 'Use this folder',
    );
    expect(afterCancel, (path: directory.path, state: StorageLocationState.ready));
    expect(controller.saves, 1);
  });

  test('the downloads path survives the persisted shape', () {
    const settings = AppSettings(downloadsPath: '/Volumes/Study/downloads');

    final reloaded = AppSettings.fromJson(settings.toJson());

    expect(reloaded.downloadsPath, '/Volumes/Study/downloads');
    // A settings file written before this setting existed has no custom path,
    // and falls to the app-managed default rather than to "ask every launch".
    expect(AppSettings.fromJson({'version': 8}).downloadsPath, isEmpty);
    expect(const AppSettings().downloadsPath, isEmpty);
  });

  test('the app-managed downloads folder is beside the store, not in it', () {
    final home = Platform.environment['HOME'];
    expect(
      AppSettings.defaultDownloadsPath,
      '$home/Library/Application Support/listen/downloads',
    );
    // Two folders, because they mean two things: the store is
    // content-addressed and holds what was kept; downloads keep the
    // publisher's filenames and are not library membership.
    expect(
      AppSettings.defaultDownloadsPath,
      isNot(AppSettings.defaultManagedStorePath),
    );
  });

  test('an acquisition writes to the remembered folder without asking',
      () async {
    // The picker used to reopen on the first download of every launch,
    // because the answer lived in a field on the view model and died with it.
    final directory = await Directory.systemTemp.createTemp('downloads');
    addTearDown(() => directory.delete(recursive: true));
    final picker = _FakeFolderPicker();
    final controller = _InMemorySettingsController(files: picker);
    addTearDown(controller.dispose);
    await controller.setDownloadsPath(directory.path);

    expect(
      await controller.resolveDownloadsDirectory(confirmButtonText: 'Select'),
      directory.path,
    );
    expect(
      await controller.resolveDownloadsDirectory(confirmButtonText: 'Select'),
      directory.path,
    );
    expect(picker.confirmButtonTexts, isEmpty);
  });

  test('a downloads folder that went off disk is asked about once', () async {
    // Silently falling back to the default would scatter a learner's episodes
    // across two folders without telling them the drive is gone.
    final directory = await Directory.systemTemp.createTemp('downloads');
    final replacement = await Directory.systemTemp.createTemp('downloads-2');
    addTearDown(() => replacement.delete(recursive: true));
    final picker = _FakeFolderPicker();
    final controller = _InMemorySettingsController(files: picker);
    addTearDown(controller.dispose);
    await controller.setDownloadsPath(directory.path);
    await directory.delete(recursive: true);

    picker.next = replacement.path;
    expect(
      await controller.resolveDownloadsDirectory(confirmButtonText: 'Select'),
      replacement.path,
    );
    expect(picker.confirmButtonTexts, ['Select']);
    expect(controller.downloadsLocation, (
      path: replacement.path,
      state: StorageLocationState.ready,
    ));

    // Remembered: the next acquisition does not ask again.
    expect(
      await controller.resolveDownloadsDirectory(confirmButtonText: 'Select'),
      replacement.path,
    );
    expect(picker.confirmButtonTexts, ['Select']);
  });

  test('a declined chooser leaves the acquisition without a folder', () async {
    final directory = await Directory.systemTemp.createTemp('downloads');
    final picker = _FakeFolderPicker();
    final controller = _InMemorySettingsController(files: picker);
    addTearDown(controller.dispose);
    await controller.setDownloadsPath(directory.path);
    await directory.delete(recursive: true);

    picker.next = null;
    expect(
      await controller.resolveDownloadsDirectory(confirmButtonText: 'Select'),
      isNull,
    );
    // The path they chose is kept: the drive may come back.
    expect(controller.settings.downloadsPath, directory.path);
  });

  testWidgets('the downloads location speaks its own sentences', (
    tester,
  ) async {
    await _pump(
      tester,
      (path: '/Volumes/Study/downloads', state: StorageLocationState.ready),
      copy: downloadsLocationCopy,
    );

    // The shape is shared with the managed store; the words are not. A learner
    // reading "kept material is copied here" under Downloads would conclude
    // downloading is keeping.
    expect(find.textContaining('Downloading is not keeping'), findsOneWidget);
    expect(find.textContaining('Kept material is copied'), findsNothing);
  });

  testWidgets('the default store offers a choice and no clear', (tester) async {
    await _pump(tester, (
      path: AppSettings.defaultManagedStorePath,
      state: StorageLocationState.appManaged,
    ));

    expect(find.text('Default app-managed folder'), findsOneWidget);
    expect(find.text(AppSettings.defaultManagedStorePath), findsOneWidget);
    expect(find.text('Choose folder…'), findsOneWidget);
    expect(find.text('Back to default'), findsNothing);
  });

  testWidgets('a missing custom location shows the path and says why', (
    tester,
  ) async {
    await _pump(tester, (
      path: '/Volumes/Study/media',
      state: StorageLocationState.missing,
    ));

    expect(find.text('/Volumes/Study/media'), findsOneWidget);
    expect(find.textContaining('not on disk right now'), findsOneWidget);
    // Never the default copy: the user did choose a location.
    expect(find.text('Default app-managed folder'), findsNothing);
    expect(find.text('Change folder…'), findsOneWidget);
    expect(find.text('Back to default'), findsOneWidget);

    final context = tester.element(find.byType(ManagedStoreSettings));
    final icon = tester.widget<Icon>(find.byIcon(Icons.warning_amber_outlined));
    expect(icon.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('a custom location that is present renders without a warning', (
    tester,
  ) async {
    await _pump(tester, (
      path: '/Volumes/Study/media',
      state: StorageLocationState.ready,
    ));

    expect(find.text('/Volumes/Study/media'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    expect(find.textContaining('not on disk right now'), findsNothing);
    // The macOS permission prompt is explained up front, not discovered as an
    // empty folder later.
    expect(find.textContaining('macOS asks for permission'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ManagedStoreLocation location, {
  StorageLocationCopy copy = managedStoreCopy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ListenTheme.dark(),
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: ManagedStoreSettings(
          location: location,
          copy: copy,
          onChoose: () {},
          onClear: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Keeps persistence out of the test run — `save` would write over the real
/// settings file of whoever runs the suite.
class _InMemorySettingsController extends SettingsController {
  _InMemorySettingsController({
    super.files = const LocalMediaImportFileService(),
  });

  int saves = 0;

  @override
  Future<void> save() async => saves++;
}

class _FakeFolderPicker implements MediaImportFileService {
  String? next;
  final confirmButtonTexts = <String>[];

  @override
  Future<String?> pickDownloadDirectory({
    required String confirmButtonText,
  }) async {
    confirmButtonTexts.add(confirmButtonText);
    return next;
  }

  @override
  String basename(String path) => path.split(Platform.pathSeparator).last;


  @override
  Future<String?> pickMedia() async => null;

  @override
  Future<String?> pickSubtitle() async => null;

  @override
  Future<String?> pickLearningPackage() async => null;

  @override
  Future<TimelineFileDocument?> pickTimeline() async => null;
}
