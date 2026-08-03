import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/occurrence_media_resolver.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/review_controller.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/data/repositories/review_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/practice.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/screens/review_queue_screen.dart';
import 'package:llplayer_next/services/occurrence_media_file_service.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/flows/shell_learning_routes.dart';

/// The learning shell routes: hosts own a composition-root-built controller
/// bundle for one visit. These cases pin the ownership contract — the
/// unavailable pane while the core is disconnected, the screen once a bundle
/// is supplied, and the rebuild when the core connects or disconnects again.

class _FakeReviewRepository implements ReviewRepository {
  int loadCalls = 0;

  @override
  Future<List<ReviewQueueEntry>> dueItems({int limit = 20}) async {
    loadCalls++;
    return const [];
  }

  @override
  Future<List<UpgradeSuggestion>> pendingUpgradeSuggestions() async => const [];

  @override
  Future<ReviewSubmission> submitRating(String itemId, String rating) =>
      throw UnimplementedError('not used by these tests');

  @override
  Future<void> resolveUpgradeSuggestion(
    String id, {
    required bool confirm,
  }) async {}

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

  testWidgets('ReviewRouteHost builds the queue once a bundle is supplied', (
    tester,
  ) async {
    final repository = _FakeReviewRepository();

    await tester.pumpWidget(
      _harness(
        ReviewRouteHost(
          create: () => _reviewBundle(repository),
          language: 'en',
          pauseBackgroundPlayback: () async {},
          onStartShadowing: (_) async {},
          onStartDelayedRetelling: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReviewQueueScreen), findsOneWidget);
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
    expect(find.byType(ReviewQueueScreen), findsOneWidget);
    expect(repository.loadCalls, 1);

    // The core drops again: the bundle is disposed and the pane returns.
    connected = false;
    setConnected(() {});
    await tester.pumpAndSettle();
    expect(find.text('Connect the local core first'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
