import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_edition_controller.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/learning_edition.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/panels/learning_edition_panel.dart';

void main() {
  testWidgets('shows the adopted package and all eight resource states', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeCapabilityRepository([
      _edition(
        releaseId: 'release-1',
        adopted: true,
        resourceKinds: learningResourceKinds,
      ),
    ]);
    final controller = LearningEditionController(repository: repository);
    addTearDown(controller.dispose);
    await controller.load('material-1');

    await tester.pumpWidget(
      _app(LearningEditionDialog(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('8 / 8'), findsOneWidget);
    for (final kind in learningResourceKinds) {
      expect(find.byKey(Key('learning-resource-$kind')), findsOneWidget);
    }
    expect(find.text('In use'), findsWidgets);
    expect(find.text('Manual review'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a version adopts the whole package', (tester) async {
    var refreshes = 0;
    final repository = _FakeCapabilityRepository([
      _edition(
        releaseId: 'release-1',
        adopted: true,
        resourceKinds: learningResourceKinds,
      ),
      _edition(
        releaseId: 'release-2',
        adopted: false,
        resourceKinds: learningResourceKinds.take(5),
      ),
    ]);
    final controller = LearningEditionController(
      repository: repository,
      onAdopted: () async => refreshes++,
    );
    addTearDown(controller.dispose);
    await controller.load('material-1');

    await tester.pumpWidget(
      _app(LearningEditionDialog(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('release-2').last);
    await tester.pumpAndSettle();

    expect(repository.adoptedReleaseIds, ['release-2']);
    expect(refreshes, 1);
    expect(controller.adoptedEdition?.releaseId, 'release-2');
    expect(find.text('5 / 8'), findsOneWidget);
  });

  testWidgets('an absent package offers generation without edit controls', (
    tester,
  ) async {
    var generations = 0;
    final repository = _FakeCapabilityRepository(const []);
    final controller = LearningEditionController(repository: repository);
    addTearDown(controller.dispose);
    await controller.load('material-1');

    await tester.pumpWidget(
      _app(
        LearningEditionDialog(
          controller: controller,
          onGenerate: () async => generations++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No learning package has been generated for this material yet.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('learning-edition-generate')));
    await tester.pumpAndSettle();
    expect(generations, 1);
    expect(find.text('Manual review'), findsNothing);
  });

  testWidgets(
    'reopening while the same generation is active keeps it disabled',
    (tester) async {
      final repository = _FakeCapabilityRepository(const []);
      final controller = LearningEditionController(repository: repository);
      addTearDown(controller.dispose);
      await controller.load('material-1');
      final generation = _GenerationState();
      addTearDown(generation.dispose);
      final pending = Completer<void>();

      Future<void> generate() {
        generation.start();
        return pending.future;
      }

      Widget dialog(Key key) => LearningEditionDialog(
        key: key,
        controller: controller,
        onGenerate: generate,
        generationListenable: generation,
        isGenerating: () => generation.active,
      );

      await tester.pumpWidget(_app(dialog(const Key('first-dialog'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('learning-edition-generate')));
      await tester.pump();

      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
      await tester.pumpWidget(_app(dialog(const Key('reopened-dialog'))));
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('learning-edition-generate')),
      );
      expect(button.onPressed, isNull);

      pending.complete();
      generation.finish();
      await tester.pumpAndSettle();
    },
  );
}

final class _GenerationState extends ChangeNotifier {
  bool active = false;

  void start() {
    active = true;
    notifyListeners();
  }

  void finish() {
    active = false;
    notifyListeners();
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: ListenTheme.light(),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

LearningEdition _edition({
  required String releaseId,
  required bool adopted,
  required Iterable<String> resourceKinds,
}) => LearningEdition(
  materialId: 'material-1',
  materialRevisionId: 'revision-1',
  editionId: 'edition-1',
  releaseId: releaseId,
  title: releaseId,
  targetLanguage: 'en',
  supportLanguages: const [],
  installedAtMs: 1,
  adoptedAtMs: adopted ? 2 : null,
  adopted: adopted,
  resources: [
    for (final kind in resourceKinds)
      LearningEditionResource(
        resourceId: '$releaseId-$kind',
        kind: kind,
        role: 'base',
        required: true,
        availability: 'available',
        reviewStatus: 'not_required',
        contentLanguage: 'en',
        supportLanguages: const [],
      ),
  ],
  renditions: const [],
);

LearningEdition _copyWithAdopted(LearningEdition edition, bool adopted) =>
    LearningEdition(
      materialId: edition.materialId,
      materialRevisionId: edition.materialRevisionId,
      editionId: edition.editionId,
      releaseId: edition.releaseId,
      title: edition.title,
      targetLanguage: edition.targetLanguage,
      supportLanguages: edition.supportLanguages,
      installedAtMs: edition.installedAtMs,
      adoptedAtMs: adopted ? 2 : null,
      adopted: adopted,
      resources: edition.resources,
      renditions: edition.renditions,
    );

final class _FakeCapabilityRepository implements CapabilityRepository {
  _FakeCapabilityRepository(this.editions);

  List<LearningEdition> editions;
  final adoptedReleaseIds = <String>[];

  @override
  Future<List<LearningEdition>> listEditions(String materialId) async =>
      editions;

  @override
  Future<LearningEdition> adoptEdition(
    String materialId,
    String releaseId,
  ) async {
    adoptedReleaseIds.add(releaseId);
    editions = [
      for (final edition in editions)
        _copyWithAdopted(edition, edition.releaseId == releaseId),
    ];
    return editions.singleWhere((edition) => edition.releaseId == releaseId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
