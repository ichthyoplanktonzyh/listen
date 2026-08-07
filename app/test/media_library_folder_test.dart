import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/media_import_file_service.dart';
import 'package:llplayer_next/settings.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/settings/media_library_settings.dart';

/// A settings folder that was chosen and then vanished (renamed, deleted, or
/// sitting on a disk that is no longer mounted) must read as *missing*, not as
/// *never chosen* — the two send the user to two different remedies.
void main() {
  test('the media library path survives the persisted shape', () {
    const settings = AppSettings(mediaLibraryPath: '/Volumes/Study/media');

    // Round-tripped through the map `save` writes, so a key typo in either
    // direction fails here rather than at the user's next launch.
    final reloaded = AppSettings.fromJson(settings.toJson());

    expect(reloaded.mediaLibraryPath, '/Volumes/Study/media');
    // A settings file written before this setting existed has no folder.
    expect(AppSettings.fromJson({'version': 8}).mediaLibraryPath, isEmpty);
    expect(const AppSettings().mediaLibraryPath, isEmpty);
  });

  test('setting, reading back and clearing the folder', () async {
    final directory = await Directory.systemTemp.createTemp('media-library');
    addTearDown(() => directory.delete(recursive: true));
    final controller = _InMemorySettingsController();
    addTearDown(controller.dispose);

    expect(controller.mediaLibraryFolder, (
      path: '',
      state: MediaLibraryFolderState.unset,
    ));

    await controller.setMediaLibraryPath(directory.path);
    expect(controller.mediaLibraryFolder, (
      path: directory.path,
      state: MediaLibraryFolderState.ready,
    ));
    expect(controller.settings.mediaLibraryPath, directory.path);
    expect(controller.saves, 1);

    await controller.clearMediaLibraryFolder();
    expect(controller.mediaLibraryFolder, (
      path: '',
      state: MediaLibraryFolderState.unset,
    ));
    expect(controller.saves, 2);
  });

  test('a folder that is gone reads as missing, not as unset', () async {
    final directory = await Directory.systemTemp.createTemp('media-library');
    final controller = _InMemorySettingsController();
    addTearDown(controller.dispose);
    await controller.setMediaLibraryPath(directory.path);

    await directory.delete(recursive: true);
    await controller.refreshMediaLibraryFolderState();

    expect(controller.mediaLibraryFolder, (
      path: directory.path,
      state: MediaLibraryFolderState.missing,
    ));
    // The path is kept: the user chose it, and the drive may come back.
    expect(controller.settings.mediaLibraryPath, directory.path);
  });

  test('a cancelled picker leaves the chosen folder alone', () async {
    final directory = await Directory.systemTemp.createTemp('media-library');
    addTearDown(() => directory.delete(recursive: true));
    final picker = _FakeFolderPicker();
    final controller = _InMemorySettingsController(files: picker);
    addTearDown(controller.dispose);

    picker.next = directory.path;
    final chosen = await controller.chooseMediaLibraryFolder(
      confirmButtonText: 'Use this folder',
    );
    expect(chosen, (
      path: directory.path,
      state: MediaLibraryFolderState.ready,
    ));
    expect(picker.confirmButtonTexts, ['Use this folder']);

    picker.next = null;
    final afterCancel = await controller.chooseMediaLibraryFolder(
      confirmButtonText: 'Use this folder',
    );
    expect(afterCancel, (
      path: directory.path,
      state: MediaLibraryFolderState.ready,
    ));
    expect(controller.saves, 1);
  });

  testWidgets('the unset folder offers a choice and nothing to clear', (
    tester,
  ) async {
    await _pump(tester, (path: '', state: MediaLibraryFolderState.unset));

    expect(find.text('No folder chosen yet'), findsOneWidget);
    expect(find.text('Choose folder…'), findsOneWidget);
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('a missing folder shows the path and says why it is not there', (
    tester,
  ) async {
    await _pump(tester, (
      path: '/Volumes/Study/media',
      state: MediaLibraryFolderState.missing,
    ));

    expect(find.text('/Volumes/Study/media'), findsOneWidget);
    expect(find.textContaining('not on disk right now'), findsOneWidget);
    // Never the unset copy: the user did choose a folder.
    expect(find.text('No folder chosen yet'), findsNothing);
    expect(find.text('Change folder…'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    final context = tester.element(find.byType(MediaLibrarySettings));
    final icon = tester.widget<Icon>(find.byIcon(Icons.warning_amber_outlined));
    expect(icon.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('a folder that is present renders without a warning', (
    tester,
  ) async {
    await _pump(tester, (
      path: '/Volumes/Study/media',
      state: MediaLibraryFolderState.ready,
    ));

    expect(find.text('/Volumes/Study/media'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    expect(find.textContaining('not on disk right now'), findsNothing);
    // The macOS permission prompt is explained up front, not discovered as an
    // empty folder later.
    expect(find.textContaining('macOS asks for permission'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, MediaLibraryFolder folder) async {
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
        body: MediaLibrarySettings(
          folder: folder,
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
