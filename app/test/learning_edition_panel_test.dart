import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_edition_controller.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/learning_edition.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/services/media_import_file_service.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/panels/learning_edition_panel.dart';

void main() {
  testWidgets('shows the adopted package and all eight resource states', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
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
    await tester.tap(find.byKey(const Key('learning-edition-adopt-btn')));
    await tester.pumpAndSettle();

    expect(repository.adoptedReleaseIds, ['release-2']);
    expect(refreshes, 1);
    expect(controller.adoptedEdition?.releaseId, 'release-2');
    expect(find.text('5 / 8'), findsOneWidget);
  });

  testWidgets('re-generate button in header triggers onRegenerate', (
    tester,
  ) async {
    var regenerations = 0;
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
      _app(
        LearningEditionDialog(
          controller: controller,
          onRegenerate: () async => regenerations++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final regenerateBtn = find.byKey(
      const Key('learning-edition-regenerate'),
    );
    expect(regenerateBtn, findsOneWidget);
    await tester.tap(regenerateBtn);
    await tester.pumpAndSettle();

    expect(regenerations, 1);
  });

  testWidgets('deleting candidate version opens confirm dialog and deletes', (
    tester,
  ) async {
    final repository = _FakeCapabilityRepository([
      _edition(
        releaseId: 'release-1',
        adopted: true,
        resourceKinds: learningResourceKinds,
      ),
      _edition(
        releaseId: 'release-2',
        adopted: false,
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

    // Switch to release-2 which is not adopted
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('release-2').last);
    await tester.pumpAndSettle();

    // Now delete button is enabled for release-2
    final deleteBtn = find.byKey(const Key('learning-edition-delete-btn'));
    expect(deleteBtn, findsOneWidget);
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // Confirm dialog is shown
    expect(find.text('Delete this package version?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete version'));
    await tester.pumpAndSettle();

    expect(repository.deletedReleaseIds, ['release-2']);
    expect(controller.editions.length, 1);
  });

  testWidgets('import package picks file and installs edition', (
    tester,
  ) async {
    final repository = _FakeCapabilityRepository([
      _edition(
        releaseId: 'release-1',
        adopted: true,
        resourceKinds: learningResourceKinds,
      ),
    ]);
    final fakeFileService = _FakeMediaImportFileService()
      ..packageToPick = '/path/to/test.listenpkg';
    final controller = LearningEditionController(repository: repository);
    addTearDown(controller.dispose);
    await controller.load('material-1');

    await tester.pumpWidget(
      _app(
        LearningEditionDialog(
          controller: controller,
          fileService: fakeFileService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final importBtn = find.byKey(const Key('learning-edition-import'));
    expect(importBtn, findsOneWidget);
    await tester.tap(importBtn);
    await tester.pumpAndSettle();

    expect(repository.installedPackagePaths, ['/path/to/test.listenpkg']);
    expect(controller.adoptedEdition?.releaseId, 'imported-release');
  });

  testWidgets('shows generation status card when generation is active', (
    tester,
  ) async {
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

    var cancelled = false;
    const runView = CapabilityRunView(
      materialId: 'material-1',
      capability: MaterialCapability.read,
      phase: CapabilityRunPhase.generating,
      stage: 'aligning phonemes',
    );

    await tester.pumpWidget(
      _app(
        LearningEditionDialog(
          controller: controller,
          isGenerating: () => true,
          runView: () => runView,
          onCancelGeneration: () async => cancelled = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('aligning phonemes'), findsOneWidget);
    expect(find.text('Cancel generation'), findsOneWidget);

    await tester.tap(find.text('Cancel generation'));
    await tester.pump();
    expect(cancelled, isTrue);
  });

  testWidgets('an absent package offers generation and import', (
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
    expect(find.byKey(const Key('learning-edition-import-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('learning-edition-generate')));
    await tester.pumpAndSettle();
    expect(generations, 1);
    expect(find.text('Manual review'), findsNothing);
  });
}

final class _FakeMediaImportFileService implements MediaImportFileService {
  String? packageToPick;

  @override
  Future<String?> pickLearningPackage() async => packageToPick;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  final deletedReleaseIds = <String>[];
  final installedPackagePaths = <String>[];

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
  Future<void> deleteEdition(String materialId, String releaseId) async {
    deletedReleaseIds.add(releaseId);
    editions = editions.where((e) => e.releaseId != releaseId).toList();
  }

  @override
  Future<LearningEdition> installPackage(
    String materialId,
    String packagePath,
  ) async {
    installedPackagePaths.add(packagePath);
    final newEdition = _edition(
      releaseId: 'imported-release',
      adopted: false,
      resourceKinds: learningResourceKinds,
    );
    editions.add(newEdition);
    return newEdition;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
