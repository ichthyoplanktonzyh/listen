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
      state: ManagedStoreState.appManaged,
    ));

    await controller.setManagedStorePath(directory.path);
    expect(controller.managedStoreLocation, (
      path: directory.path,
      state: ManagedStoreState.ready,
    ));
    expect(controller.settings.mediaLibraryPath, directory.path);
    expect(controller.saves, 1);

    await controller.clearManagedStoreLocation();
    expect(controller.managedStoreLocation, (
      path: AppSettings.defaultManagedStorePath,
      state: ManagedStoreState.appManaged,
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
        state: ManagedStoreState.missing,
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
    expect(chosen, (path: directory.path, state: ManagedStoreState.ready));
    expect(picker.confirmButtonTexts, ['Use this folder']);

    picker.next = null;
    final afterCancel = await controller.chooseManagedStoreLocation(
      confirmButtonText: 'Use this folder',
    );
    expect(afterCancel, (path: directory.path, state: ManagedStoreState.ready));
    expect(controller.saves, 1);
  });

  testWidgets('the default store offers a choice and no clear', (tester) async {
    await _pump(tester, (
      path: AppSettings.defaultManagedStorePath,
      state: ManagedStoreState.appManaged,
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
      state: ManagedStoreState.missing,
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
      state: ManagedStoreState.ready,
    ));

    expect(find.text('/Volumes/Study/media'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    expect(find.textContaining('not on disk right now'), findsNothing);
    // The macOS permission prompt is explained up front, not discovered as an
    // empty folder later.
    expect(find.textContaining('macOS asks for permission'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, ManagedStoreLocation location) async {
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
  Future<String?> pickContentPackage() async => null;

  @override
  Future<String?> pickMedia() async => null;

  @override
  Future<String?> pickSubtitle() async => null;

  @override
  Future<TimelineFileDocument?> pickTimeline() async => null;
}
