import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/media_library_scan_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/home/listening_home.dart';
import 'package:llplayer_next/widgets/home/media_library_section.dart';

MediaLibraryEntry _entry(String path) => MediaLibraryEntry(
  media: MediaItem(
    id: 'id-$path',
    path: path,
    fingerprint: 'fp',
    title: 'Talk',
    kind: 'video',
    durationMs: 60000,
    availability: 'available',
    createdAtMs: 1,
    updatedAtMs: 1,
  ),
  primaryTrackId: null,
  fit: null,
  triageIntent: null,
  familiarMaterial: false,
);

Widget _wrap(Widget child) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _home({
  required MediaLibraryScanState scan,
  List<MediaLibraryEntry>? library,
  VoidCallback? onChooseFolder,
}) => _wrap(
  ListeningHome(
    onOpenMedia: () {},
    onOpenOnline: () {},
    mediaLibrary: library,
    offlineEntries: library,
    scan: scan,
    onScanRefresh: () {},
    onScanCancel: () {},
    onRetryScanRegistrations: () {},
    onChooseManagedStoreLocation: onChooseFolder ?? () {},
    onOpenLibraryEntry: (_) {},
    onStartExtensiveEntry: (_) {},
    onStartIntensiveEntry: (_) {},
    onSetLibraryIntent: (_, _) {},
    onToggleFamiliarSupply: (_) {},
  ),
);

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('an unreachable core never reads as an empty library', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _home(
        scan: MediaLibraryScanState(
          status: MediaLibraryScanStatus.coreUnavailable,
          folderPath: '/media',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本地内核未连接，媒体库里有什么无法确认——这不等于库是空的。'), findsOneWidget);
    expect(find.text('打开过的媒体会出现在这里。'), findsNothing);
  });

  testWidgets(
    'a finished scan of an empty folder may say the library is empty',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _home(
          scan: MediaLibraryScanState(
            status: MediaLibraryScanStatus.completed,
            folderPath: '/media',
          ),
          library: const <MediaLibraryEntry>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('素材库扫描完成。'), findsOneWidget);
      expect(find.text('打开过的媒体会出现在这里。'), findsOneWidget);
    },
  );

  testWidgets('a missing custom store is a different sentence from the '
      'default store', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _home(
        scan: MediaLibraryScanState(
          status: MediaLibraryScanStatus.folderMissing,
          folderPath: '/volumes/gone',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('这个文件夹当前不在磁盘上'), findsOneWidget);
    expect(find.text('/volumes/gone'), findsOneWidget);
    expect(find.text('更换文件夹…'), findsOneWidget);
  });

  testWidgets('a running scan shows its harvest and can be stopped', (
    tester,
  ) async {
    var cancels = 0;
    await tester.pumpWidget(
      _wrap(
        MediaLibraryScanCard(
          state: MediaLibraryScanState(
            status: MediaLibraryScanStatus.scanning,
            folderPath: '/media',
            discovered: 4,
            registered: 3,
            unchanged: 12,
            skipped: 1,
          ),
          onRefresh: () {},
          onCancel: () => cancels++,
          onRetryFailures: () {},
          onChooseFolder: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('正在扫描受管素材库…'), findsOneWidget);
    expect(find.text('新增 3 · 未变化 12 · 跳过 1'), findsOneWidget);
    await tester.tap(find.text('停止'));
    expect(cancels, 1);
  });

  testWidgets('files Core refused stay visible and retryable', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _wrap(
        MediaLibraryScanCard(
          state: MediaLibraryScanState(
            status: MediaLibraryScanStatus.completed,
            folderPath: '/media',
            discovered: 2,
            registered: 1,
            registrationFailures: [
              const MediaRegistrationFailure(
                path: '/media/bad.mp4',
                fileName: 'bad.mp4',
                failure: ApiFailure(raw: 'x', correlationId: 'api-1'),
              ),
            ],
          ),
          onRefresh: () {},
          onCancel: () {},
          onRetryFailures: () => retries++,
          onChooseFolder: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('有 1 个文件没能加入媒体库。'), findsOneWidget);
    expect(find.text('bad.mp4'), findsOneWidget);
    await tester.tap(find.text('重试这些文件'));
    expect(retries, 1);
  });

  testWidgets('a sidecar subtitle is stated as a fact on the row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _home(
        scan: MediaLibraryScanState(
          status: MediaLibraryScanStatus.completed,
          folderPath: '/media',
          sidecarSubtitlePaths: const {'/media/talk.mp4'},
        ),
        library: [_entry('/media/talk.mp4'), _entry('/media/other.mp4')],
      ),
    );
    await tester.pumpAndSettle();

    // One row carries the fact, the other does not — and the badge says the
    // file is there, never that the media is ready to learn from.
    expect(find.text('旁边有字幕文件'), findsOneWidget);
  });
}
