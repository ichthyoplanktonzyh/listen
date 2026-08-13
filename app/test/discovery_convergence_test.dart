import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/discovery_view_model.dart';
import 'package:llplayer_next/data/repositories/learning_material_repository.dart';
import 'package:llplayer_next/data/repositories/source_identity_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/discovery.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/source_identity.dart';
import 'package:llplayer_next/services/acquisition_ledger.dart';

import 'discovery_test_helpers.dart';
import 'support/learning_material_fixtures.dart';

/// Slice 5 convergence: document items travel the same acquisition path as
/// media, recognition keys are source-scoped, and Source Identity makes a
/// re-read of the same feed item resolve the same Material instead of
/// offering a second download.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('typed evidence never substitutes for identity', () {
    test('a document item carries its own typed evidence fields', () {
      final item = DiscoveryItem(
        id: 'post-7',
        sourceId: 'https://blog.example.com/feed.xml',
        title: 'The title',
        description: '',
        language: 'en',
        publishedOn: '2026-08-03',
        acquisition: AcquisitionMode.article,
        contentKind: ItemContentKind.article,
        entryUrl: 'https://blog.example.com/posts/7',
        publisherId: 'Ada Example',
      );

      final evidence = item.evidence(fileSha256: 'deadbeef');

      expect(
        evidence.map((field) => field.kind),
        [
          SourceItemEvidenceKind.feedItemId,
          SourceItemEvidenceKind.entryUrl,
          SourceItemEvidenceKind.publisherId,
          SourceItemEvidenceKind.title,
          SourceItemEvidenceKind.date,
          SourceItemEvidenceKind.byteFingerprint,
        ],
      );
      expect(
        evidence.firstWhere(
          (field) => field.kind == SourceItemEvidenceKind.feedItemId,
        ).value,
        'post-7',
      );
      expect(
        evidence.firstWhere(
          (field) => field.kind == SourceItemEvidenceKind.byteFingerprint,
        ).value,
        'deadbeef',
      );
    });

    test('an enclosure URL is evidence only on the enclosure path', () {
      // The same URL string on an article item is not enclosure evidence.
      final article = DiscoveryItem(
        id: 'a',
        sourceId: 's',
        title: 't',
        description: '',
        language: 'en',
        publishedOn: '',
        acquisition: AcquisitionMode.article,
        entryUrl: 'https://example.com/a',
      );
      final enclosure = DiscoveryItem(
        id: 'a',
        sourceId: 's',
        title: 't',
        description: '',
        language: 'en',
        publishedOn: '',
        acquisition: AcquisitionMode.enclosure,
        mediaUrl: 'https://example.com/a.mp3',
      );

      expect(
        article.evidence().where(
          (field) => field.kind == SourceItemEvidenceKind.enclosureUrl,
        ),
        isEmpty,
      );
      expect(
        enclosure.evidence().where(
          (field) => field.kind == SourceItemEvidenceKind.enclosureUrl,
        ),
        hasLength(1),
      );
    });
  });

  group('a document item is acquired like a file', () {
    (DiscoveryViewModel, TestMediaImportRepository, TestMediaLibraryRepository)
    articleViewModel({AcquisitionLedger? ledger}) {
      final imports = TestMediaImportRepository();
      final library = TestMediaLibraryRepository();
      final vm = DiscoveryViewModel(
        TestDiscoveryRepository(
          sources: [testContentSource('c-doc', name: 'Blog')],
          entries: {
            'c-doc': [testArticleItem('i-doc-1', 'c-doc')],
          },
        ),
        imports,
        library,
        ledger,
      );
      addTearDown(vm.dispose);
      return (vm, imports, library);
    }

    testWidgets('acquireForLearning fetches the article and adopts it', (
      tester,
    ) async {
      final (vm, imports, _) = articleViewModel();
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      final path = await tester.runAsync(
        () => vm.acquireForLearning('i-doc-1'),
      );

      expect(path, '/path/to/downloaded/[i-doc-1].html');
      expect(imports.articleRequests, ['https://blog.example.com/i-doc-1']);
      expect(imports.downloadedUrls, isEmpty);
      expect(imports.enclosureRequests, isEmpty);
      expect(
        vm.state.acquisitionStateOf('i-doc-1'),
        DiscoveryItemState.available,
      );
      expect(vm.localPathFor('i-doc-1'), path);
    });

    testWidgets('subscription alone never acquires, retains or installs', (
      tester,
    ) async {
      // The catalog lists the item; nothing happens until the learner chooses.
      final (vm, imports, library) = articleViewModel();
      await tester.runAsync(() => vm.load());
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        vm.state.acquisitionStateOf('i-doc-1'),
        DiscoveryItemState.acquirable,
      );
      expect(imports.articleRequests, isEmpty);
      expect(await library.listMediaLibrary(), isEmpty);
    });
  });

  group('recognition is source-scoped', () {
    test('a downloaded item of one feed is not the same item of another feed',
        () async {
        // Two shows both publish an item whose feed id is `ep-001`. What was
        // acquired for one must never answer for the other.
        final ledger = AcquisitionLedger.inMemory();
        final library = TestMediaLibraryRepository(
          seed: [
            TestMediaLibraryRepository.entry(
              id: 'media-npr-ep-001',
              path: '/library/[npr-ep-001].mp3',
            ),
          ],
        );
        final vm = DiscoveryViewModel(
          TestDiscoveryRepository(
            sources: [
              testContentSource('c-npr'),
              testContentSource('c-bbc'),
            ],
            entries: {
              'c-npr': [testPodcastItem('ep-001', 'c-npr')],
              'c-bbc': [testPodcastItem('ep-001', 'c-bbc')],
            },
          ),
          TestMediaImportRepository(),
          library,
          ledger,
        );
        addTearDown(vm.dispose);
        await vm.load();
        // The first channel's `ep-001` was acquired in an earlier session.
        await ledger.record(
          'c-npr\u0000ep-001',
          mediaId: 'media-npr-ep-001',
          path: '/library/[npr-ep-001].mp3',
        );
        await vm.selectChannel('c-npr');
        vm.selectItem('ep-001');
        await pumpEventQueue();

        // NPR's ep-001 is recognized local; BBC's is still remote.
        expect(vm.localPathFor('ep-001'), '/library/[npr-ep-001].mp3');
        expect(
          vm.state.acquisitionStateOf('ep-001'),
          DiscoveryItemState.available,
        );
        await vm.selectChannel('c-bbc');
        vm.selectItem('ep-001');
        await pumpEventQueue();

        expect(vm.localPathFor('ep-001'), isNull);
        expect(
          vm.state.acquisitionStateOf('ep-001'),
          DiscoveryItemState.acquirable,
        );
      },
    );
  });

  group('source identity converges a re-read on the same material', () {
    test(
      'adoption records the mapping once the media resolved to a material',
      () async {
        final imports = TestMediaImportRepository();
        final identities = _TestSourceIdentityRepository();
        final materials = _TestMaterialRepository()
          ..resolvedMaterial = materialDetails(
            materialId: 'material-npr-1',
            mediaRenditions: [mediaRendition(mediaId: 'media-i-bbc-1')],
          );
        final vm = DiscoveryViewModel(
          TestDiscoveryRepository(
            sources: [testContentSource('c-npr', name: 'NPR')],
            entries: {
              'c-npr': [testPodcastItem('ep-1', 'c-npr')],
            },
          ),
          imports,
          TestMediaLibraryRepository(),
          null,
          identities,
          materials,
        );
        addTearDown(vm.dispose);
        await vm.load();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await vm.acquireForLearning('ep-1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          identities.recorded.single.sourceId,
          'c-npr',
          reason: 'intake records the item identity against the material it '
              'converged on',
        );
        expect(identities.recorded.single.itemId, 'ep-1');
        expect(identities.recorded.single.materialId, 'material-npr-1');
      },
    );

    test(
      'a recorded mapping answers a refresh without a second download',
      () async {
        final identities = _TestSourceIdentityRepository();
        identities.mappings['c-npr\u0000ep-1'] = SourceIdentityMapping(
          sourceId: 'c-npr',
          itemId: 'ep-1',
          evidence: const [],
          materialId: 'material-npr-1',
          materialRevisionId: 'revision-1',
          mappedAtMs: 0,
        );
        final materials = _TestMaterialRepository();
        materials.material = materialDetails(
          materialId: 'material-npr-1',
          mediaRenditions: [mediaRendition(mediaId: 'media-npr-1')],
        );
        final library = TestMediaLibraryRepository(
          seed: [
            TestMediaLibraryRepository.entry(
              id: 'media-npr-1',
              path: '/library/[npr-1].mp3',
            ),
          ],
        );
        final vm = DiscoveryViewModel(
          TestDiscoveryRepository(
            sources: [testContentSource('c-npr', name: 'NPR')],
            entries: {
              'c-npr': [testPodcastItem('ep-1', 'c-npr')],
            },
          ),
          TestMediaImportRepository(),
          library,
          null,
          identities,
          materials,
        );
        addTearDown(vm.dispose);
        await vm.load();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          vm.state.acquisitionStateOf('ep-1'),
          DiscoveryItemState.available,
          reason: 'the canonical key resolves to the recorded material, so a '
              're-read of the same item never offers a second download',
        );
        expect(vm.localPathFor('ep-1'), '/library/[npr-1].mp3');
      },
    );

    test('the ledger fallback still answers when the core has no mapping',
        () async {
        // An older core, or a mapping the core lost: recognition falls back
        // to the app's own record of what it downloaded.
        final identities = _TestSourceIdentityRepository();
        final materials = _TestMaterialRepository();
        final ledger = AcquisitionLedger.inMemory();
        final library = TestMediaLibraryRepository(
          seed: [
            TestMediaLibraryRepository.entry(
              id: 'media-npr-1',
              path: '/library/[npr-1].mp3',
            ),
          ],
        );
        final vm = DiscoveryViewModel(
          TestDiscoveryRepository(
            sources: [testContentSource('c-npr', name: 'NPR')],
            entries: {
              'c-npr': [testPodcastItem('ep-1', 'c-npr')],
            },
          ),
          TestMediaImportRepository(),
          library,
          ledger,
          identities,
          materials,
        );
        addTearDown(vm.dispose);
        await vm.load();
        await ledger.record(
          'c-npr\u0000ep-1',
          mediaId: 'media-npr-1',
          path: '/library/[npr-1].mp3',
        );
        vm.selectItem('ep-1');
        await pumpEventQueue();

        expect(
          vm.state.acquisitionStateOf('ep-1'),
          DiscoveryItemState.available,
        );
        expect(vm.localPathFor('ep-1'), '/library/[npr-1].mp3');
      },
    );
  });
}

class _TestSourceIdentityRepository implements SourceIdentityRepository {
  final mappings = <String, SourceIdentityMapping>{};
  final recorded = <SourceIdentityMapping>[];
  bool failResolve = false;

  @override
  bool get isAvailable => true;

  @override
  Future<void> recordMapping({
    required String sourceId,
    required String itemId,
    required List<SourceItemEvidence> evidence,
    required String materialId,
    required String materialRevisionId,
  }) async {
    final mapping = SourceIdentityMapping(
      sourceId: sourceId,
      itemId: itemId,
      evidence: evidence,
      materialId: materialId,
      materialRevisionId: materialRevisionId,
      mappedAtMs: 0,
    );
    recorded.add(mapping);
    mappings['$sourceId\u0000$itemId'] = mapping;
  }

  @override
  Future<SourceIdentityMapping?> resolveMapping({
    required String sourceId,
    required String itemId,
  }) async {
    if (failResolve) throw StateError('identity lookup failed');
    return mappings['$sourceId\u0000$itemId'];
  }
}

class _TestMaterialRepository implements LearningMaterialRepository {
  /// What [resolveMaterialForMedia] returns; when non-null, a resolved
  /// material exists for the adopted media.
  MaterialDetails? resolvedMaterial;

  /// What [readLearningMaterial] returns.
  MaterialDetails? material;

  @override
  bool get isAvailable => true;

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', message: 'refused by fake materials');

  @override
  Future<List<MaterialDetails>> listLearningMaterials() async => [];

  @override
  Future<MaterialDetails> createLearningMaterial(
    CreateLearningMaterialInput input, {
    MaterialRetainDirective retain = const MaterialRetainOmitted(),
  }) async => throw UnimplementedError();

  @override
  Future<MaterialDetails> readLearningMaterial(String materialId) async {
    final value = material;
    if (value == null) throw StateError('no such material $materialId');
    return value;
  }

  @override
  Future<MaterialDetails> appendMaterialRevision(
    String materialId,
    AppendMaterialRevisionInput input,
  ) async => throw UnimplementedError();

  @override
  Future<MaterialRevision> readMaterialRevision(
    String materialId,
    String revisionId,
  ) async => throw UnimplementedError();

  @override
  Future<MaterialDetails> retainLearningMaterial(String materialId) async =>
      throw UnimplementedError();

  @override
  Future<MaterialDetails> unretainLearningMaterial(String materialId) async =>
      throw UnimplementedError();

  @override
  Future<MaterialDetails> resolveMaterialForMedia(String mediaId) async {
    final value = resolvedMaterial;
    if (value == null) {
      throw StateError('no learning material bound to $mediaId');
    }
    return value;
  }

  @override
  Future<MaterialRevision> updateSourceAssetAvailability(
    String materialId,
    String sourceAssetId,
    SourceAssetAvailability availability,
  ) async => throw UnimplementedError();

  @override
  Future<List<MaterialCapabilityProjection>> listMaterialCapabilities(
    String materialId,
  ) async => throw UnimplementedError();
}
