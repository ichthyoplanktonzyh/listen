import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/occurrence_media_resolver.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/review_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/review_deck.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/controllers/review_deck_controller.dart';
import 'package:llplayer_next/screens/review_deck_home_screen.dart';
import 'package:llplayer_next/services/anki_package_file_service.dart';
import 'package:llplayer_next/services/occurrence_media_file_service.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/flows/shell_learning_routes.dart';

import 'support/review_repository_fake.dart';

/// The learning shell routes: hosts own a composition-root-built controller
/// bundle for one visit. These cases pin the ownership contract — the
/// unavailable pane while the core is disconnected, the screen once a bundle
/// is supplied, and the rebuild when the core connects or disconnects again.

class _FakeReviewRepository extends FakeReviewRepositoryBase {
  /// The route now opens on the deck home, so the load it makes on entry is
  /// the deck overview rather than a card queue.
  int loadCalls = 0;

  @override
  Future<ReviewDeckOverview> deckOverview() async {
    loadCalls++;
    return ReviewDeckOverview(
      channels: const [],
      importedDecks: const [],
      limitStatus: fakeLimitStatus(),
    );
  }

  @override
  Future<MediaItem> readMedia(String id) async => MediaItem(
    id: id,
    path: '/fake/$id.mp4',
    fingerprint: 'fp-$id',
    title: 'Source $id',
    kind: 'video',
    durationMs: 12000,
    availability: 'available',
    createdAtMs: 1,
    updatedAtMs: 1,
  );

  @override
  Future<String> fingerprintFile(String path) async => 'fp';

  @override
  Future<void> registerMedia(String path) async {}
}

class _FakeAnkiFileService implements AnkiPackageFileService {
  const _FakeAnkiFileService();

  @override
  Future<String?> pickPackageToImport() async => null;

  @override
  Future<String> mediaDirectoryFor(String packagePath) async => '/tmp/media';

  @override
  Future<String?> pickExportDestination() async => null;
}

class _FakeFileService implements OccurrenceMediaFileService {
  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<String?> pickSourceMedia({
    required bool filterMediaExtensions,
  }) async => null;
}

ReviewRouteControllers _reviewBundle(_FakeReviewRepository repository) =>
    ReviewRouteControllers(
      controller: ReviewController(repository),
      deckController: ReviewDeckController(repository),
      resolver: OccurrenceMediaResolver(
        repository: repository,
        fileService: _FakeFileService(),
      ),
      slicePlayer: SlicePlayerController(),
    );

Widget _harness(Widget child) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  testWidgets('every learning route host renders the unavailable pane while '
      'the core is disconnected', (tester) async {
    await tester.pumpWidget(
      _harness(
        Column(
          children: [
            VocabularyRouteHost(
              create: null,
              language: 'en',
              onExport: () async {},
              onImport: () async {},
              huntingController: HuntingController(),
              auxiliaryAudio: AuxiliaryAudioController(),
              pauseBackgroundPlayback: () async {},
            ),
            ExpressionRouteHost(
              create: null,
              language: 'en',
              createDetailViewModel: null,
              onPlaySource: null,
              onStartSpeaking: null,
            ),
            ReviewRouteHost(
              create: null,
              language: 'en',
              fileService: const _FakeAnkiFileService(),
              pauseBackgroundPlayback: () async {},
              onStartShadowing: (_) async {},
              onStartDelayedRetelling: (_) async {},
            ),
            CoachRouteHost(
              create: null,
              language: 'en',
              onNavigate: (_, _) async {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Connect the local core first'),
      findsNWidgets(4),
      reason:
          'each destination names the unavailable core instead of '
          'rendering a dead surface',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ReviewRouteHost builds the deck home once a bundle is '
      'supplied', (tester) async {
    final repository = _FakeReviewRepository();

    await tester.pumpWidget(
      _harness(
        ReviewRouteHost(
          create: () => _reviewBundle(repository),
          language: 'en',
          fileService: const _FakeAnkiFileService(),
          pauseBackgroundPlayback: () async {},
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReviewDeckHomeScreen), findsOneWidget);
    expect(find.text('Connect the local core first'), findsNothing);
    expect(repository.loadCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hosts rebuild the bundle when the core reconnects or drops', (
    tester,
  ) async {
    var connected = false;
    final repository = _FakeReviewRepository();

    late StateSetter setConnected;
    await tester.pumpWidget(
      _harness(
        StatefulBuilder(
          builder: (context, setState) {
            setConnected = setState;
            return ReviewRouteHost(
              create: connected ? () => _reviewBundle(repository) : null,
              language: 'en',
              fileService: const _FakeAnkiFileService(),
              pauseBackgroundPlayback: () async {},
              onStartShadowing: (_) async {},
              onStartDelayedRetelling: (_) async {},
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Disconnected on entry: the pane names the missing core.
    expect(find.text('Connect the local core first'), findsOneWidget);

    // The core connects: the host rebuilds its bundle and swaps to the queue.
    connected = true;
    setConnected(() {});
    await tester.pumpAndSettle();
    expect(find.byType(ReviewDeckHomeScreen), findsOneWidget);
    expect(repository.loadCalls, 1);

    // The core drops again: the bundle is disposed and the pane returns.
    connected = false;
    setConnected(() {});
    await tester.pumpAndSettle();
    expect(find.text('Connect the local core first'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
