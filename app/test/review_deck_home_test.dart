import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/review_deck_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/review_deck.dart';
import 'package:llplayer_next/screens/review_deck_home_screen.dart';
import 'package:llplayer_next/services/anki_package_file_service.dart';
import 'package:llplayer_next/theme/listen_theme.dart';

import 'support/review_repository_fake.dart';

/// The review home reports counts the backend measured and a budget it was
/// told about. These cases pin the two things it must never do: invent a
/// number, and blur "nothing due" into "you are done for today".

class _FakeDeckRepository extends FakeReviewRepositoryBase {
  _FakeDeckRepository({this.overview, this.exportSummary, this.importSummary});

  ReviewDeckOverview? overview;
  AnkiPackageExportSummary? exportSummary;
  AnkiPackageImportSummary? importSummary;

  int overviewCalls = 0;
  ReviewDailyLimits? savedLimits;
  AnkiPackageExportRequest? exportRequest;
  ({String packagePath, String mediaDirectory})? importRequest;

  @override
  Future<ReviewDeckOverview> deckOverview() async {
    overviewCalls++;
    final value = overview;
    if (value == null) throw StateError('no overview');
    return value;
  }

  @override
  Future<ReviewDailyLimits> updateDailyLimits(ReviewDailyLimits limits) async {
    savedLimits = limits;
    return limits;
  }

  @override
  Future<AnkiPackageExportSummary> exportAnkiPackage(
    AnkiPackageExportRequest request,
  ) async {
    exportRequest = request;
    return exportSummary!;
  }

  @override
  Future<AnkiPackageImportSummary> importAnkiPackage({
    required String packagePath,
    required String mediaDirectory,
  }) async {
    importRequest = (packagePath: packagePath, mediaDirectory: mediaDirectory);
    return importSummary!;
  }
}

class _FakeAnkiFileService implements AnkiPackageFileService {
  _FakeAnkiFileService({this.importPath, this.exportPath});

  final String? importPath;
  final String? exportPath;

  @override
  Future<String?> pickPackageToImport() async => importPath;

  @override
  Future<String> mediaDirectoryFor(String packagePath) async =>
      '$packagePath-media';

  @override
  Future<String?> pickExportDestination() async => exportPath;
}

ReviewStateCounts _counts({int newCards = 0, int learning = 0, int due = 0}) =>
    ReviewStateCounts(newCards: newCards, learning: learning, due: due);

ReviewDeckOverview _overview({
  List<ReviewChannelDeck>? channels,
  List<ReviewImportedDeck> importedDecks = const [],
  ReviewLimitStatus? limitStatus,
}) => ReviewDeckOverview(
  channels:
      channels ??
      [
        ReviewChannelDeck(
          channel: 'listening',
          counts: _counts(newCards: 12, learning: 3, due: 9),
        ),
        ReviewChannelDeck(
          channel: 'speaking',
          counts: _counts(newCards: 6, learning: 2, due: 4),
        ),
      ],
  importedDecks: importedDecks,
  limitStatus: limitStatus ?? fakeLimitStatus(),
);

Future<void> _pump(
  WidgetTester tester, {
  required _FakeDeckRepository repository,
  AnkiPackageFileService? fileService,
  void Function(CustomStudyRequest request)? onStartCustomStudy,
  VoidCallback? onStartSession,
}) async {
  final controller = ReviewDeckController(repository);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ListenTheme.light(),
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ReviewDeckHomeScreen(
        controller: controller,
        fileService: fileService ?? _FakeAnkiFileService(),
        onStartSession: onStartSession ?? () {},
        onStartCustomStudy: onStartCustomStudy ?? (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('native cards are one deck carrying the summed counts', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(overview: _overview());
    await _pump(tester, repository: repository);

    expect(find.text('Cards from your media'), findsOneWidget);
    // Listening 12/3/9 plus speaking 6/2/4 = 18 new · 5 learning · 13 due,
    // totalling the 36 in the header.
    expect(find.text('18'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    expect(find.text('waiting today'), findsOneWidget);
  });

  testWidgets('the channel split is gone from the deck list, because every '
      'row led to the same session', (tester) async {
    final repository = _FakeDeckRepository(overview: _overview());
    await _pump(tester, repository: repository);

    // The channels survive only as custom-study filters further down; they are
    // no longer rows in the deck list, and there is exactly one deck row.
    expect(find.text('Cards from your media'), findsOneWidget);
    expect(find.byIcon(Icons.hearing_outlined), findsOneWidget);
  });

  testWidgets('the imported deck tree keeps the shape Anki gave it', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(
      overview: _overview(
        importedDecks: [
          ReviewImportedDeck(
            deckId: 'deck-1',
            name: 'German',
            parentDeckId: null,
            counts: _counts(due: 4),
          ),
          ReviewImportedDeck(
            deckId: 'deck-2',
            name: 'German::Nouns',
            parentDeckId: 'deck-1',
            counts: _counts(newCards: 7),
          ),
        ],
      ),
    );
    await _pump(tester, repository: repository);

    expect(find.text('Imported decks'), findsOneWidget);
    expect(find.text('German'), findsOneWidget);
    // The leaf name only — the indent already says who the parent is.
    expect(find.text('Nouns'), findsOneWidget);
    expect(find.text('German::Nouns'), findsNothing);

    final parent = tester.getTopLeft(find.text('German')).dx;
    final child = tester.getTopLeft(find.text('Nouns')).dx;
    expect(
      child,
      greaterThan(parent),
      reason: 'a child deck is indented under its parent',
    );
  });

  testWidgets('a spent budget is named as such, not as an empty queue', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(
      overview: _overview(
        channels: const [],
        limitStatus: fakeLimitStatus(
          newCompleted: 20,
          reviewsCompleted: 200,
          newLimitReached: true,
          reviewLimitReached: true,
        ),
      ),
    );
    await _pump(tester, repository: repository);

    expect(find.text('That is enough for today'), findsOneWidget);
    expect(find.text('No sound cards due right now'), findsNothing);
    expect(find.textContaining('20/20 new · 200/200 reviews'), findsOneWidget);
  });

  testWidgets('an empty queue under an unspent budget says nothing is due', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(
      overview: _overview(channels: const []),
    );
    await _pump(tester, repository: repository);

    expect(find.text('No sound cards due right now'), findsOneWidget);
    expect(find.text('That is enough for today'), findsNothing);
  });

  testWidgets('a failed load shows the failure instead of zero counts', (
    tester,
  ) async {
    final repository = _FakeDeckRepository();
    await _pump(tester, repository: repository);

    expect(find.text('Could not load review decks'), findsOneWidget);
    // A page that has been told nothing must not render a confident "0".
    expect(find.text('0'), findsNothing);
    expect(find.text('waiting today'), findsNothing);
  });

  testWidgets('custom study asks for the kind the learner picked', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(overview: _overview());
    final requests = <CustomStudyRequest>[];
    await _pump(
      tester,
      repository: repository,
      onStartCustomStudy: requests.add,
    );

    await tester.tap(find.text('Ten more new'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redo the forgotten'));
    await tester.pumpAndSettle();
    // The channel is a way to pick extra practice now, not a deck row.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Speaking'));
    await tester.pumpAndSettle();

    expect(requests.map((request) => request.kind), [
      CustomStudyKind.moreNew,
      CustomStudyKind.forgotten,
      CustomStudyKind.channel,
    ]);
    expect(requests.last.channel, 'speaking');
  });

  testWidgets('a channel with nothing in it is offered as disabled, not as a '
      'button that returns an empty round', (tester) async {
    final repository = _FakeDeckRepository(
      overview: _overview(
        channels: [
          ReviewChannelDeck(channel: 'listening', counts: _counts(due: 4)),
          ReviewChannelDeck(channel: 'writing', counts: _counts()),
        ],
      ),
    );
    await _pump(tester, repository: repository);

    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Writing'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Listening'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('editing the daily limits saves them and re-reads the counts', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(overview: _overview());
    await _pump(tester, repository: repository);
    expect(repository.overviewCalls, 1);

    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New cards per day'),
      '5',
    );
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.savedLimits?.newCards, 5);
    expect(repository.savedLimits?.reviews, 200);
    expect(
      repository.overviewCalls,
      2,
      reason: 'a changed budget moves every count on the page',
    );
  });

  testWidgets('export discloses the losses before asking where to write', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(overview: _overview());
    final fileService = _FakeAnkiFileService(exportPath: '/tmp/out.apkg');
    await _pump(tester, repository: repository, fileService: fileService);

    await tester.tap(find.byTooltip('Export to Anki (.apkg)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('will not survive the trip'), findsOneWidget);
    expect(
      find.text('· Video slices are rendered down to audio.'),
      findsOneWidget,
    );
    expect(
      find.text('· Shadowing and delayed retelling are lost.'),
      findsOneWidget,
    );

    // Declining leaves the file untouched.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(repository.exportRequest, isNull);
  });

  testWidgets('the export report carries the fidelity the backend measured', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(
      overview: _overview(),
      exportSummary: const AnkiPackageExportSummary(
        exportedCards: 42,
        exportedRevlogEntries: 130,
        exportedMediaFiles: 40,
        fidelity: AnkiExportFidelity(
          cardsWithMediaSlices: 40,
          videoSlicesRenderedAsAudio: 31,
          mediaRenderFailures: 2,
          omittedCapabilities: ['shadowing', 'source_jump'],
        ),
        warnings: ['One card had no answer field.'],
      ),
    );
    final fileService = _FakeAnkiFileService(exportPath: '/tmp/out.apkg');
    await _pump(tester, repository: repository, fileService: fileService);

    await tester.tap(find.byTooltip('Export to Anki (.apkg)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export anyway'));
    await tester.pumpAndSettle();

    expect(repository.exportRequest?.packagePath, '/tmp/out.apkg');
    // The measured loss, not the generic warning the dialog showed.
    expect(
      find.text('31 video slices were rendered as audio.'),
      findsOneWidget,
    );
    expect(find.text('2 media files could not be rendered.'), findsOneWidget);
    expect(
      find.text('Not carried across: shadowing, source_jump'),
      findsOneWidget,
    );
    expect(find.text('One card had no answer field.'), findsOneWidget);
  });

  testWidgets('import reports its counts and warnings, then re-reads decks', (
    tester,
  ) async {
    final repository = _FakeDeckRepository(
      overview: _overview(),
      importSummary: const AnkiPackageImportSummary(
        importedCards: 120,
        updatedCards: 5,
        skippedCards: 3,
        importedDecks: 4,
        importedRevlogEntries: 900,
        importedMediaFiles: 60,
        warnings: ['2 notes used an unsupported template.'],
      ),
    );
    final fileService = _FakeAnkiFileService(importPath: '/tmp/deck.apkg');
    await _pump(tester, repository: repository, fileService: fileService);

    await tester.tap(find.byTooltip('Import an Anki deck (.apkg)'));
    await tester.pumpAndSettle();

    expect(repository.importRequest?.packagePath, '/tmp/deck.apkg');
    expect(repository.importRequest?.mediaDirectory, '/tmp/deck.apkg-media');
    expect(
      find.text('120 cards imported · 5 updated · 3 skipped'),
      findsOneWidget,
    );
    expect(find.text('2 notes used an unsupported template.'), findsOneWidget);
    expect(
      repository.overviewCalls,
      2,
      reason: 'an import changes what is in the decks',
    );
  });
}
