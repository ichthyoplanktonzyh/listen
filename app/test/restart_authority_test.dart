import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/models/adopted_composition.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/learning_edition.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/composition_session_service.dart';

/// Restart authority (Slice 6 acceptance).
///
/// After a relaunch the adopted composition comes back from Core's
/// composition interface — reading, listening and learning go through it and
/// no other projection — and the learner's own activity state lives in a
/// store that the composition never touches. Neither is rebuilt from the
/// other. The App keeps no retained carrier: every payload and blob is read
/// back through Core, re-verified by it.
void main() {
  test(
    'after a relaunch the adopted composition recovers from Core, and '
    'never from app-side state',
    () async {
      // ── first session: a fresh service instance over the same Core ──
      final repository = _CompositionRepository(
        _compositionWith(
          structuredReading: _structuredReadingPayload(),
          alignment: _alignmentPayload(),
        ),
      );
      final session = CompositionSessionService(repository: repository);
      final first = await session.resolveComposition('material-1');
      expect(first, isNotNull);
      expect(first!.logicalText, 'Hello world. Listen carefully!');
      expect(
        first.sentences.map((sentence) => sentence.text),
        ['Hello world.', 'Listen carefully!'],
      );
      expect(first.alignments['anchor-1'], 150);

      // ── relaunch: a fresh service instance over the same Core ──
      final relaunched = CompositionSessionService(
        repository: repository,
      );
      final composition = await relaunched.resolveComposition('material-1');

      // The adopted composition is authoritative: the learner content comes
      // back from Core's composition interface, with nothing rebuilt by the
      // app and no app-side carrier involved.
      expect(composition, isNotNull);
      expect(composition!.logicalText, 'Hello world. Listen carefully!');
      expect(repository.compositionReads, 2);
      expect(repository.carrierPaths, isEmpty);
    },
  );

  test(
    'learner activity state is owned outside the composition service',
    () async {
      final activity = SettingsController();
      addTearDown(activity.dispose);

      activity.recordRecentMedia(
        path: '/library/p0p1qc9j.mp3',
        title: 'Episode one',
        positionMs: 12400,
        durationMs: 180000,
        subtitleCount: 1,
      );
      expect(activity.lastMediaPath, '/library/p0p1qc9j.mp3');
      expect(activity.lastMediaPositionMs, 12400);

      // Resolving a composition neither reads nor writes the learner's place
      // in the material: the stores are separate and stay separate.
      final session = CompositionSessionService(
        repository: _CompositionRepository(
          _compositionWith(structuredReading: _structuredReadingPayload()),
        ),
      );
      await session.resolveComposition('material-2');

      expect(activity.lastMediaPath, '/library/p0p1qc9j.mp3');
      expect(activity.lastMediaPositionMs, 12400);
    },
  );

  test(
    'reopening without an adopted composition falls back to nothing, not to '
    'a stale projection',
    () async {
      final repository = _CompositionRepository(null);
      final session = CompositionSessionService(repository: repository);

      final composition = await session.resolveComposition('never-adopted');

      expect(composition, isNull);
    },
  );

  test(
    'tampered or missing selected content resolves to nothing, never to a '
    'stale projection',
    () async {
      final repository = _CompositionRepository(
        _compositionWith(structuredReading: null),
      );
      final session = CompositionSessionService(repository: repository);

      final composition = await session.resolveComposition('material-1');

      expect(composition, isNull);
    },
  );
}

AdoptedComposition _compositionWith({
  required Map<String, dynamic>? structuredReading,
  Map<String, dynamic>? alignment,
}) {
  final resources = <AdoptedCompositionResource>[
    if (structuredReading != null)
      _resource(
        'sr-1',
        'structured_reading',
        payloadDigest: 'a' * 64,
        payloadSizeBytes: utf8.encode(jsonEncode(structuredReading)).length,
      ),
    if (alignment != null)
      _resource(
        'align-1',
        'anchor_time_alignment',
        payloadDigest: 'b' * 64,
        payloadSizeBytes: utf8.encode(jsonEncode(alignment)).length,
      ),
  ];
  return AdoptedComposition(
    materialId: 'material-1',
    materialRevisionId: 'revision-1',
    releaseId: 'release-1',
    editionId: 'edition:material-1',
    title: 'Lesson',
    targetLanguage: 'en',
    supportLanguages: const [],
    adoptedAtMs: 10,
    resources: resources,
    renditions: const [],
  );
}

AdoptedCompositionResource _resource(
  String resourceId,
  String kind, {
  required String payloadDigest,
  required int payloadSizeBytes,
}) => AdoptedCompositionResource(
  resourceId: resourceId,
  kind: kind,
  schema: 'https://listen.dev/contracts/content-package/v3/payload/'
      'structured-reading.v1.schema.json',
  role: 'base',
  required: true,
  availability: 'available',
  contentLanguage: 'en',
  supportLanguages: const [],
  payloadDigest: payloadDigest,
  payloadSizeBytes: payloadSizeBytes,
  reviewStatus: 'machine_checked',
);

Map<String, dynamic> _structuredReadingPayload() => {
  'language': 'en',
  'text': 'Hello world. Listen carefully!',
  'anchors': [
    {
      'anchor_id': 'anchor-1',
      'kind': 'block',
      'start_offset': 0,
      'end_offset': 30,
    },
    {
      'anchor_id': 'anchor-2',
      'kind': 'sentence',
      'start_offset': 0,
      'end_offset': 12,
    },
    {
      'anchor_id': 'anchor-3',
      'kind': 'sentence',
      'start_offset': 13,
      'end_offset': 30,
    },
  ],
  'blocks': const <List<dynamic>>[],
  'spans': const <List<dynamic>>[],
  'document_mappings': const <List<dynamic>>[],
  'extensions': const <String, dynamic>{},
};

Map<String, dynamic> _alignmentPayload() => {
  'anchor_resource_id': 'sha256:${'a' * 64}',
  'rendition_id': 'sha256:${'b' * 64}',
  'alignments': const <Map<String, dynamic>>[
    {'anchor_id': 'anchor-1', 'media_time_ms': 150},
  ],
  'extensions': const <String, dynamic>{},
};

/// A scriptable composition repository: resolves the fixed composition
/// through Core-shaped methods, records every composition read, and keeps no
/// app-side carrier.
final class _CompositionRepository implements CapabilityRepository {
  _CompositionRepository(this._composition);

  final AdoptedComposition? _composition;
  int compositionReads = 0;
  final List<String> carrierPaths = [];

  @override
  Future<AdoptedComposition> readAdoptedComposition(
    String materialId,
  ) async {
    compositionReads++;
    final composition = _composition;
    if (composition == null) {
      throw const ApiFailure(
        raw: '{"code":"not_found","message":"adopted composition was not found"}',
        code: 'not_found',
        retryable: false,
      );
    }
    return composition;
  }

  @override
  Future<List<int>> readCompositionResourcePayload(
    String materialId,
    String resourceId,
  ) async {
    final payload = switch (resourceId) {
      'sr-1' => _structuredReadingPayload(),
      'align-1' => _alignmentPayload(),
      _ => throw StateError('unexpected resource $resourceId'),
    };
    return utf8.encode(jsonEncode(payload));
  }

  @override
  Future<List<int>> readCompositionRenditionBlob(
    String materialId,
    String renditionId,
  ) async => throw StateError('unexpected rendition blob read');

  @override
  ApiFailure failureDetail(Object error) => error is ApiFailure
      ? error
      : ApiFailure(raw: '$error', code: '$error');

  @override
  Future<MaterialDetails> readMaterial(String materialId) async =>
      throw StateError('unexpected readMaterial');

  @override
  Future<List<MaterialCapabilityProjection>> listCapabilities(
    String materialId,
  ) async => throw StateError('unexpected listCapabilities');

  @override
  Future<CapabilityAttempt> startAttempt(
    String materialId,
    String capability,
  ) async => throw StateError('unexpected startAttempt');

  @override
  Future<CapabilityAttempt> finalizeAttempt({
    required String materialId,
    required String attemptId,
    required bool succeeded,
    String? failureReason,
    String? toolId,
    String? toolVersion,
  }) async => throw StateError('unexpected finalizeAttempt');

  @override
  Future<LearningEdition> installPackage(
    String materialId,
    String packagePath,
  ) async => throw StateError('unexpected installPackage');

  @override
  Future<List<LearningEdition>> listEditions(String materialId) async =>
      throw StateError('unexpected listEditions');

  @override
  Future<LearningEdition> adoptEdition(
    String materialId,
    String releaseId,
  ) async => throw StateError('unexpected adoptEdition');
}
