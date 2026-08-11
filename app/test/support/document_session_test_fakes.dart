import 'dart:async';

import 'package:llplayer_next/data/repositories/learning_material_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/document_intake_service.dart';

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
      _assetsFrom(input.assets),
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
  ) async =>
      _detailsFor(input.title, _assetsFrom(input.assets), retainedAtMs: 42);

  /// Converts typed asset inputs to the asset models a create returns.
  static List<MaterialAsset> _assetsFrom(List<MaterialAssetInput> inputs) => [
    for (final input in inputs)
      switch (input) {
        DocumentTextMaterialAssetInput(:final text, :final language) =>
          DocumentTextMaterialAsset(
            id: 'text-1',
            text: text,
            sha256Digest: 'x',
            byteSize: text.length,
            language: language,
          ),
        MediaRenditionMaterialAssetInput() => throw StateError(
          'no media assets in document fakes',
        ),
      },
  ];

  @override
  Future<MaterialRevision> readMaterialRevision(
    String materialId,
    String revisionId,
  ) async => throw StateError('unexpected readMaterialRevision');

  @override
  Future<MaterialDetails> resolveMaterialForMedia(String mediaId) async =>
      throw StateError('unexpected resolveMaterialForMedia');

  /// A retained (or, with [retainedAtMs] null, Temporary) sample material.
  static MaterialDetails retained(
    String materialId, {
    int? retainedAtMs = 42,
  }) => _detailsFor(
    'Sample',
    [
      DocumentTextMaterialAsset(
        id: 'text-1',
        text: 'Sample text',
        sha256Digest: 'x',
        byteSize: 11,
        language: null,
      ),
    ],
    materialId: materialId,
    retainedAtMs: retainedAtMs,
  );

  static MaterialDetails _detailsFor(
    String title,
    List<MaterialAsset> assets, {
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
      assets: assets,
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
  Future<DocumentFileRead> pickAndReadTextFile() async {
    pickCalls += 1;
    final error = pickError;
    if (error != null) throw error;
    if (results.isEmpty) return const DocumentFileCancelled();
    final result = results.removeAt(0);
    if (result is GatedDocumentFileRead) return result.completer.future;
    return result;
  }

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
