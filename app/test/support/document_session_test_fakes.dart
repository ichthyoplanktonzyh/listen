import 'dart:async';

import 'package:llplayer_next/data/repositories/learning_material_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'dart:io';

import 'package:llplayer_next/services/document_intake_service.dart';
import 'package:llplayer_next/services/document_reference_store.dart';
import 'package:llplayer_next/services/document_source_resolver.dart';
import 'package:llplayer_next/services/managed_asset_store.dart';

import 'learning_material_fixtures.dart';

/// In-memory [ManagedAssetStoreService] for tests.
class FakeManagedAssetStoreService implements ManagedAssetStoreService {
  final Map<String, List<int>> contents = {};
  int copyCalls = 0;
  bool unavailable = false;
  Exception? copyError;

  /// When set, [readBytes] answers these bytes regardless of path.
  List<int>? readBytesResult;

  @override
  Future<ManagedAssetCopy> copyIntoStore({
    required String sourcePath,
    String? mediaKind,
  }) async {
    // The controller only ever copies bytes; a path-based copy means the test
    // composition is wrong.
    throw StateError('unexpected path-based copy');
  }

  @override
  Future<ManagedAssetCopy> copyBytesIntoStore({
    required List<int> bytes,
    required String mediaKind,
  }) async {
    copyCalls += 1;
    if (unavailable) throw const ManagedStoreUnavailable();
    if (copyError case final error?) throw error;
    final digest = 'd${bytes.length}';
    contents[digest] = bytes;
    return ManagedAssetCopy(
      path: '/store/$digest',
      createdNew: true,
      mediaKind: mediaKind,
    );
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    final result = readBytesResult;
    if (result != null) return result;
    final name = path.split('/').last;
    return contents[name];
  }

  @override
  bool contains(String path) => path.startsWith('/store/');

  @override
  Future<void> deleteStoreCopy(String path) async {
    final name = path.split('/').last;
    contents.remove(name);
  }
}

/// In-memory [DocumentReferenceStore] for tests.
class FakeDocumentReferenceStore extends DocumentReferenceStore {
  FakeDocumentReferenceStore()
    : super(file: File('/unused/document-references.json'));

  final Map<String, String> references = {};
  bool saveFails = false;

  @override
  Future<String?> resolve(String referenceKey) async => references[referenceKey];

  @override
  Future<void> save(String referenceKey, String path) async {
    if (saveFails) throw StateError('save failed');
    references[referenceKey] = path;
  }

  @override
  Future<void> remove(String referenceKey) async {
    references.remove(referenceKey);
  }
}

/// Controllable [DocumentSourceResolver] for tests.
class FakeDocumentSourceResolver implements DocumentSourceResolver {
  DocumentSourceBytes result = const DocumentSourceUnavailable();
  SourceAsset? lastAsset;

  /// Exact bytes by Source Asset digest; a hit wins over [result] so a test
  /// can drive the direct view's exact bytes without per-asset setup.
  final Map<String, List<int>> bytesByDigest = {};

  @override
  Future<DocumentSourceBytes> bytesFor(SourceAsset asset) async {
    lastAsset = asset;
    final bytes = bytesByDigest[asset.sha256Digest];
    if (bytes != null) return DocumentSourceAvailable(bytes);
    return result;
  }
}

/// Controllable [LearningMaterialRepository] for document-session tests.
///
/// Every operation either answers from an injected handler, throws a typed
/// [ApiFailure], or blocks on a gate [Completer] the test releases later —
/// no timers, no sleeps.
class FakeLearningMaterialRepository implements LearningMaterialRepository {
  FakeLearningMaterialRepository({this.available = true});

  bool available;

  /// When set, [createLearningMaterial] throws it (through [failureDetail]).
  ApiFailure? createFailure;

  /// When set, [createLearningMaterial] blocks until the test completes it.
  Completer<MaterialDetails>? createGate;

  /// Completes (once) when [createLearningMaterial] is first invoked — proof
  /// the create reached the transport seam without any timer.
  Completer<void>? createStarted;

  MaterialDetails Function(CreateLearningMaterialInput input)? onCreate;

  /// When set, retention operations throw it (through [failureDetail]).
  ApiFailure? retentionFailure;

  /// When set, retention operations block until the test completes them.
  Completer<MaterialDetails>? retentionGate;

  MaterialDetails Function(String materialId)? onRetain;
  MaterialDetails Function(String materialId)? onUnretain;

  /// When set, [listMaterialCapabilities] answers it; otherwise a read
  /// projection with `available` for every requested capability.
  Future<List<MaterialCapabilityProjection>> Function(String materialId)?
      onListCapabilities;

  int createCalls = 0;
  int retainCalls = 0;
  int unretainCalls = 0;
  CreateLearningMaterialInput? lastCreateInput;
  MaterialRetainDirective? lastRetainDirective;
  String? lastRetainedMaterialId;
  String? lastUnretainedMaterialId;

  @override
  bool get isAvailable => available;

  @override
  ApiFailure failureDetail(Object error) => error is ApiFailure
      ? error
      : ApiFailure(raw: error.toString(), correlationId: 'api-1');

  @override
  Future<MaterialDetails> createLearningMaterial(
    CreateLearningMaterialInput input, {
    MaterialRetainDirective retain = const MaterialRetainOmitted(),
  }) async {
    createCalls += 1;
    lastCreateInput = input;
    lastRetainDirective = retain;
    // One-shot, and the field stays set so a test can read the future after
    // the fact — never complete a completed completer.
    final started = createStarted;
    if (started != null && !started.isCompleted) started.complete();
    if (createFailure case final failure?) throw failure;
    if (createGate != null) return createGate!.future;
    if (onCreate case final handler?) return handler(input);
    return _detailsFor(
      input.title,
      sourceAssets: [
        for (final asset in input.sourceAssets)
          sourceAsset(
            mediaType: asset.mediaType,
            byteLength: asset.byteLength,
            sha256Digest: asset.sha256Digest,
            binding: asset.binding,
          ),
      ],
      documentRenditions: _renditionsFrom(input),
      retainedAtMs: null,
    );
  }

  @override
  Future<MaterialDetails> retainLearningMaterial(String materialId) async {
    retainCalls += 1;
    lastRetainedMaterialId = materialId;
    if (retentionGate != null) return retentionGate!.future;
    if (onRetain case final handler?) return handler(materialId);
    if (retentionFailure case final failure?) throw failure;
    return retained(materialId);
  }

  @override
  Future<MaterialDetails> unretainLearningMaterial(String materialId) async {
    unretainCalls += 1;
    lastUnretainedMaterialId = materialId;
    if (retentionGate != null) return retentionGate!.future;
    if (onUnretain case final handler?) return handler(materialId);
    if (retentionFailure case final failure?) throw failure;
    return retained(materialId, retainedAtMs: null);
  }

  @override
  Future<List<MaterialDetails>> listLearningMaterials() async => const [];

  @override
  Future<MaterialDetails> readLearningMaterial(String materialId) async =>
      retained(materialId);

  @override
  Future<MaterialDetails> appendMaterialRevision(
    String materialId,
    AppendMaterialRevisionInput input,
  ) async => _detailsFor(input.title, retainedAtMs: 42);

  /// Converts typed document-rendition inputs to the renditions a create
  /// returns, keeping the submitted byte facts for the exact-match check.
  static List<DocumentRendition> _renditionsFrom(
    CreateLearningMaterialInput input,
  ) => [
    for (final (index, rendition) in input.documentRenditions.indexed)
      documentRendition(
        id: 'document-$index',
        mediaType: rendition.mediaType,
        digest: rendition.digest,
        byteSize: rendition.byteSize,
        language: rendition.language,
        sourceAssetId: rendition.sourceAssetIndex == null
            ? null
            : input.sourceAssets[rendition.sourceAssetIndex!].sha256Digest,
      ),
  ];

  @override
  Future<MaterialRevision> readMaterialRevision(
    String materialId,
    String revisionId,
  ) async => throw StateError('unexpected readMaterialRevision');

  @override
  Future<MaterialDetails> resolveMaterialForMedia(String mediaId) async =>
      throw StateError('unexpected resolveMaterialForMedia');

  @override
  Future<MaterialRevision> updateSourceAssetAvailability(
    String materialId,
    String sourceAssetId,
    SourceAssetAvailability availability,
  ) async => throw StateError('unexpected updateSourceAssetAvailability');

  @override
  Future<List<MaterialCapabilityProjection>> listMaterialCapabilities(
    String materialId,
  ) async {
    final handler = onListCapabilities;
    if (handler != null) return handler(materialId);
    return const [
      MaterialCapabilityProjection(
        capability: MaterialCapability.read,
        status: MaterialCapabilityStatus.available,
        latestAttempt: null,
      ),
    ];
  }

  /// A retained (or, with [retainedAtMs] null, Temporary) sample material.
  static MaterialDetails retained(
    String materialId, {
    int? retainedAtMs = 42,
  }) => _detailsFor('Sample', materialId: materialId, retainedAtMs: retainedAtMs);

  static MaterialDetails _detailsFor(
    String title, {
    List<SourceAsset>? sourceAssets,
    List<DocumentRendition>? documentRenditions,
    String materialId = 'material-1',
    int? retainedAtMs,
  }) => MaterialDetails(
    material: LearningMaterial(
      id: materialId,
      currentRevisionId: 'revision-1',
      retainedAtMs: retainedAtMs,
      createdAtMs: 1,
      updatedAtMs: 1,
    ),
    currentRevision: MaterialRevision(
      id: 'revision-1',
      materialId: materialId,
      title: title,
      sourceAssets: sourceAssets ?? [sourceAsset()],
      documentRenditions: documentRenditions ?? [documentRendition()],
      mediaRenditions: const [],
      createdAtMs: 1,
    ),
    shape: MaterialShape.text,
  );
}

/// Controllable [DocumentIntakeFileService]: returns queued [DocumentFileRead]
/// results in order, or a cancelled picker when the queue is empty.
class FakeDocumentIntakeFileService implements DocumentIntakeFileService {
  FakeDocumentIntakeFileService([List<DocumentFileRead>? results])
    : results = [...?results];

  final List<DocumentFileRead> results;
  int pickCalls = 0;
  String Function(String path)? basenameFn;

  /// When set, [pickAndReadTextFile] throws it before serving any result —
  /// the platform-picker failure mode the controller must fold into a typed
  /// unreadable state.
  Exception? pickError;

  @override
  Future<DocumentFileRead> pickAndReadDocumentFile() async {
    pickCalls += 1;
    final error = pickError;
    if (error != null) throw error;
    if (results.isEmpty) return const DocumentFileCancelled();
    final result = results.removeAt(0);
    if (result is GatedDocumentFileRead) return result.completer.future;
    return result;
  }

  /// Answers [readDocumentFile] with the queued result (or a cancelled read
  /// when the queue is empty), like the picker path serves its results.
  @override
  Future<DocumentFileRead> readDocumentFile(String path) async {
    final readCalls = ++readCount;
    readPaths[path] = readCalls;
    if (results.isEmpty) return const DocumentFileCancelled();
    final result = results.removeAt(0);
    if (result is GatedDocumentFileRead) return result.completer.future;
    return result;
  }

  /// Every path [readDocumentFile] was asked for, in call order.
  final readPaths = <String, int>{};
  int readCount = 0;

  @override
  String basename(String path) =>
      basenameFn?.call(path) ?? path.split('/').last;
}

/// A [DocumentFileRead] the fake serves after the test completes it, so a
/// picker can be held open deterministically.
class GatedDocumentFileRead extends DocumentFileRead {
  GatedDocumentFileRead();

  final Completer<DocumentFileRead> completer = Completer<DocumentFileRead>();
}
