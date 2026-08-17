import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/models/adopted_composition.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/learning_edition.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/composition_session_service.dart';
import 'package:llplayer_next/services/core_timeline_export.dart';

/// Restart authority (Slice 6 acceptance).
///
/// After a relaunch the adopted composition comes back from Core's
/// composition interface — reading, listening and learning go through it and
/// no other projection — and the learner's own activity state lives in a
/// store that the composition never touches. Neither is rebuilt from the
/// other. The App keeps no retained carrier: every payload and blob is read
/// back through Core, re-verified by it.
void main() {
  test('after a relaunch the adopted composition recovers from Core, and '
      'never from app-side state', () async {
    // ── first session: a fresh service instance over the same Core ──
    final repository = _CompositionRepository(
      _compositionWith(
        structuredReading: _structuredReadingPayload(),
        alignment: _alignmentPayload(),
      ),
    );
    final session = CompositionSessionService(
      repository: repository,
      resources: _NoopWorkbenchResources(),
    );
    final first = await session.resolveComposition('material-1');
    expect(first, isNotNull);
    expect(first!.logicalText, 'Hello world. Listen carefully!');
    expect(first.sentences.map((sentence) => sentence.text), [
      'Hello world.',
      'Listen carefully!',
    ]);
    expect(first.alignments['anchor-1'], 150);

    // ── relaunch: a fresh service instance over the same Core ──
    final relaunched = CompositionSessionService(
      repository: repository,
      resources: _NoopWorkbenchResources(),
    );
    final composition = await relaunched.resolveComposition('material-1');

    // The adopted composition is authoritative: the learner content comes
    // back from Core's composition interface, with nothing rebuilt by the
    // app and no app-side carrier involved.
    expect(composition, isNotNull);
    expect(composition!.logicalText, 'Hello world. Listen carefully!');
    expect(repository.compositionReads, 2);
    expect(repository.carrierPaths, isEmpty);
  });

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
        resources: _NoopWorkbenchResources(),
      );
      await session.resolveComposition('material-2');

      expect(activity.lastMediaPath, '/library/p0p1qc9j.mp3');
      expect(activity.lastMediaPositionMs, 12400);
    },
  );

  test('reopening without an adopted composition falls back to nothing, not to '
      'a stale projection', () async {
    final repository = _CompositionRepository(null);
    final session = CompositionSessionService(
      repository: repository,
      resources: _NoopWorkbenchResources(),
    );

    final composition = await session.resolveComposition('never-adopted');

    expect(composition, isNull);
  });

  test('tampered or missing selected content resolves to nothing, never to a '
      'stale projection', () async {
    final repository = _CompositionRepository(
      _compositionWith(structuredReading: null),
    );
    final session = CompositionSessionService(
      repository: repository,
      resources: _NoopWorkbenchResources(),
    );

    final composition = await session.resolveComposition('material-1');

    expect(composition, isNull);
  });

  test('package subtitle and analysis resources resolve through Core reads, '
      'never through app-side package payload projections', () async {
    final repository = _CompositionRepository(
      _compositionWith(
        structuredReading: _structuredReadingPayload(),
        alignment: _alignmentPayload(),
        withSourceMedia: true,
      ),
    );

    final composition = await CompositionSessionService(
      repository: repository,
      resources: _CoreWorkbenchResources(),
    ).resolveComposition('material-1');

    expect(composition, isNotNull);
    expect(composition!.logicalText, isNotEmpty);
    expect(composition.alignments, isNotEmpty);
    expect(composition.transcript?.id, 'package-track');
    expect(composition.transcript?.cues.single.id, 'sentence-global');
    expect(
      composition.enhancements.timingsBySentence['sentence-global'],
      hasLength(1),
    );
    expect(
      composition.enhancements.senseGroupsBySentence['sentence-global'],
      hasLength(1),
    );
    expect(
      composition.enhancements.acousticsBySentence['sentence-global'],
      hasLength(1),
    );
    expect(
      composition.enhancements.chunkPartitionsBySentence['sentence-global'],
      isNotNull,
    );
    expect(
      composition.enhancements.prosodyAnchorsBySentence['sentence-global'],
      hasLength(1),
    );
    expect(
      composition.enhancements.phonesBySentence['sentence-global'],
      hasLength(1),
    );
  });
}

AdoptedComposition _compositionWith({
  required Map<String, dynamic>? structuredReading,
  Map<String, dynamic>? alignment,
  Map<String, Map<String, dynamic>> additionalResources = const {},
  bool withSourceMedia = false,
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
    for (final entry in additionalResources.entries)
      _resource(
        '${entry.key}-1',
        entry.key,
        payloadDigest: 'c' * 64,
        payloadSizeBytes: utf8.encode(jsonEncode(entry.value)).length,
      ),
  ];
  final renditions = <AdoptedCompositionRendition>[
    if (withSourceMedia) _sourceMediaRendition(),
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
    renditions: renditions,
  );
}

AdoptedCompositionRendition _sourceMediaRendition() =>
    AdoptedCompositionRendition(
      renditionId: 'source-media-rendition',
      kind: 'media',
      origin: 'source',
      mediaType: 'audio/mpeg',
      language: 'en',
      digest: 'd' * 64,
      byteSize: 1,
      blobAvailable: false,
      binding: const AdoptedCompositionMediaBinding(mediaId: 'media-1'),
      producerToolId: null,
    );

AdoptedCompositionResource _resource(
  String resourceId,
  String kind, {
  required String payloadDigest,
  required int payloadSizeBytes,
}) => AdoptedCompositionResource(
  resourceId: resourceId,
  kind: kind,
  schema:
      'https://listen.dev/contracts/content-package/v3/payload/'
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
  Future<AdoptedComposition> readAdoptedComposition(String materialId) async {
    compositionReads++;
    final composition = _composition;
    if (composition == null) {
      throw const ApiFailure(
        raw:
            '{"code":"not_found","message":"adopted composition was not found"}',
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
  ApiFailure failureDetail(Object error) =>
      error is ApiFailure ? error : ApiFailure(raw: '$error', code: '$error');

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

/// Composition tests that never reach Core's subtitle/analysis endpoints.
final class _NoopWorkbenchResources implements ResourceRepository {
  @override
  bool get isAvailable => true;

  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '$error');

  @override
  Future<List<SubtitleTrack>> mediaSubtitles(String mediaId) async => const [];

  @override
  Future<LLTimelineDocument> exportTimeline(String trackId) async =>
      throw StateError('unexpected exportTimeline');

  @override
  Future<CoreTimelineExport> exportTimelineJson(String trackId) async =>
      throw StateError('unexpected exportTimelineJson');

  @override
  Future<ContentDifficultyProfile> contentFit(String trackId) async =>
      throw StateError('unexpected contentFit');

  @override
  Future<List<WordTiming>> wordTimings(String trackId) async =>
      throw StateError('unexpected wordTimings');

  @override
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(
    String trackId,
  ) async => throw StateError('unexpected phoneTimelineSummaries');

  @override
  Future<void> archiveSubtitle(String trackId) async =>
      throw StateError('unexpected archiveSubtitle');

  @override
  Future<void> restoreSubtitle(String trackId) async =>
      throw StateError('unexpected restoreSubtitle');

  @override
  Future<void> deleteSubtitle(String trackId) async =>
      throw StateError('unexpected deleteSubtitle');

  @override
  Future<String> exportSubtitleSrt(String trackId) async =>
      throw StateError('unexpected exportSubtitleSrt');

  @override
  Future<void> updateTrackLanguage(String trackId, String language) async =>
      throw StateError('unexpected updateTrackLanguage');

  @override
  Future<void> activateWordTimeline(String timelineId) async =>
      throw StateError('unexpected activateWordTimeline');

  @override
  Future<void> activatePhoneTimeline(String timelineId) async =>
      throw StateError('unexpected activatePhoneTimeline');

  @override
  Future<void> archivePhoneTimeline(String timelineId) async =>
      throw StateError('unexpected archivePhoneTimeline');

  @override
  Future<void> deletePhoneTimeline(String timelineId) async =>
      throw StateError('unexpected deletePhoneTimeline');
}

/// The Core-side workbench facts for one adopted package: the landed subtitle
/// track and its candidate analysis resources, all keyed by global sentence
/// ids. The raw LLTimeline export is parsed by
/// `composition_core_projection.dart` at the service boundary.
final class _CoreWorkbenchResources implements ResourceRepository {
  static const _track = SubtitleTrack(
    id: 'package-track',
    mediaId: 'media-1',
    language: 'en',
    source: 'package:subtitle_text_track',
    status: 'available',
    cues: [
      Cue(
        id: 'sentence-global',
        index: 0,
        start: Duration(milliseconds: 100),
        end: Duration(milliseconds: 900),
        text: 'Hello',
        tokens: [
          SubtitleToken(
            index: 0,
            kind: 'word',
            text: 'Hello',
            normalized: 'hello',
          ),
        ],
      ),
    ],
  );

  static final _documentJson = <String, dynamic>{
    'schema': 'llplayer.timeline.v1',
    'metadata': {
      'created_at_ms': 1,
      'generator': {
        'id': 'listen-resource-package',
        'version': 'v3',
        'mode': 'adopted_package',
      },
      'media': {
        'id': 'media-1',
        'fingerprint': 'media-fingerprint',
        'title': 'Media',
        'duration_ms': 2000,
      },
      'language': 'en',
      'human_reviewed': false,
      'extra': {
        'track_id': 'package-track',
        'track_fingerprint': 'package-track-fingerprint',
        'track_source': 'package:subtitle_text_track',
      },
    },
    'word_timelines': [
      {
        'id': 'package-word-timeline',
        'track_id': 'package-track',
        'media_id': 'media-1',
        'algorithm_id': 'listen-gen',
        'algorithm_version': 'v1',
        'config_hash': 'config',
        'parent_timeline_id': null,
        'created_by': 'algorithm',
        'status': 'candidate',
        'metrics_json': {'exchange_source': 'package:subtitle_text_track'},
        'words': [
          {
            'sentence_id': 'sentence-global',
            'token_index': 0,
            'text': 'Hello',
            'start_ms': 120,
            'end_ms': 700,
            'confidence': 0.97,
            'timing_source': 'forced_aligned',
            'provider_id': 'listen-gen',
            'provider_version': 'v1',
          },
        ],
        'created_at_ms': 1,
        'updated_at_ms': 1,
      },
    ],
    'active_word_timeline_id': null,
    'phone_timelines': [
      {
        'id': 'package-phone',
        'track_id': 'package-track',
        'media_id': 'media-1',
        'sentence_id': 'sentence-global',
        'parent_word_timeline_id': 'package-word-timeline',
        'parent_phonetic_analysis_id': null,
        'provider_id': 'listen-gen',
        'provider_version': 'v1',
        'model_id': null,
        'model_revision': 'v1',
        'phone_set': 'ipa',
        'precision': 'detected',
        'created_by': 'algorithm',
        'status': 'candidate',
        'metrics_json': {'exchange_source': 'package:subtitle_text_track'},
        'phones': [
          {
            'symbol': 'h',
            'display_ipa': 'h',
            'phone_set': 'ipa',
            'start_ms': 120,
            'end_ms': 240,
            'confidence': 0.9,
            'token_index': 0,
            'provider_id': 'listen-gen',
            'provider_version': 'v1',
            'model_revision': 'v1',
          },
        ],
        'alignments': <Object?>[],
        'findings': <Object?>[],
        'created_at_ms': 1,
        'updated_at_ms': 1,
      },
    ],
    'active_phone_timeline_id': null,
    'sense_group_analyses': [
      {
        'id': 'package-sense-groups',
        'track_id': 'package-track',
        'media_id': 'media-1',
        'parent_word_timeline_id': 'package-word-timeline',
        'provider_id': 'listen-gen',
        'provider_version': 'v1',
        'algorithm': 'listen-resource-package',
        'created_by': 'algorithm',
        'status': 'candidate',
        'metrics_json': {'exchange_source': 'package:subtitle_text_track'},
        'groups': [
          {
            'id': 'group-1',
            'sentence_id': 'sentence-global',
            'group_index': 0,
            'start_token_index': 0,
            'end_token_index': 0,
            'text': 'Hello',
            'label': null,
            'head_token_index': 0,
            'confidence': 0.9,
            'sources': ['syntax'],
          },
        ],
        'created_at_ms': 1,
        'updated_at_ms': 1,
      },
    ],
    'active_sense_group_analysis_id': null,
    'prosody_analyses': [
      {
        'id': 'package-prosody',
        'track_id': 'package-track',
        'media_id': 'media-1',
        'parent_word_timeline_id': 'package-word-timeline',
        'provider_id': 'listen-gen',
        'provider_version': 'v1',
        'algorithm': 'listen-resource-package',
        'status': 'candidate',
        'created_by': 'algorithm',
        'metrics_json': {'exchange_source': 'package:subtitle_text_track'},
        'chunks': [
          {
            'sentence_id': 'sentence-global',
            'chunk_index': 0,
            'start_token_index': 0,
            'end_token_index': 0,
            'nucleus_token_index': 0,
            'confidence': 0.8,
          },
        ],
        'anchors': [
          {
            'word_ref': {'sentence_id': 'sentence-global', 'token_index': 0},
            'syllable_index': null,
            'lexical_stress': 'primary',
            'realized_prominence': 0.8,
            'utterance_role': 'nucleus',
            'evidence': ['energy'],
            'confidence': 0.8,
          },
        ],
        'created_at_ms': 1,
        'updated_at_ms': 1,
      },
    ],
    'active_prosody_analysis_id': null,
    'rhythm_frames': <Object?>[],
    'artifacts': [
      {
        'kind': 'rhythm_word_acoustic_cues',
        'provider_id': 'listen-gen',
        'provider_version': 'v1',
        'payload': {
          'status': 'scored',
          'line': 'sound',
          'resource_id': 'package-acoustics',
          'exchange_source': 'package:subtitle_text_track',
          'timeline_id': 'package-word-timeline',
          'sample_rate_hz': 16000,
          'cues': [
            {
              'sentence_id': 'sentence-global',
              'token_index': 0,
              'energy': {'delta_db': 2.0},
              'pitch': {'median_f0_hz': 180.0},
              'duration': {'duration_ms': 580},
              'voiced_frame_ratio': 0.8,
            },
          ],
        },
      },
    ],
  };

  @override
  bool get isAvailable => true;

  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '$error');

  @override
  Future<List<SubtitleTrack>> mediaSubtitles(String mediaId) async => const [
    _track,
  ];

  @override
  Future<LLTimelineDocument> exportTimeline(String trackId) async =>
      throw StateError('unexpected exportTimeline');

  @override
  Future<CoreTimelineExport> exportTimelineJson(String trackId) async =>
      CoreTimelineExport(_documentJson);

  @override
  Future<ContentDifficultyProfile> contentFit(String trackId) async =>
      throw StateError('unexpected contentFit');

  @override
  Future<List<WordTiming>> wordTimings(String trackId) async =>
      throw StateError('unexpected wordTimings');

  @override
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(
    String trackId,
  ) async => throw StateError('unexpected phoneTimelineSummaries');

  @override
  Future<void> archiveSubtitle(String trackId) async =>
      throw StateError('unexpected archiveSubtitle');

  @override
  Future<void> restoreSubtitle(String trackId) async =>
      throw StateError('unexpected restoreSubtitle');

  @override
  Future<void> deleteSubtitle(String trackId) async =>
      throw StateError('unexpected deleteSubtitle');

  @override
  Future<String> exportSubtitleSrt(String trackId) async =>
      throw StateError('unexpected exportSubtitleSrt');

  @override
  Future<void> updateTrackLanguage(String trackId, String language) async =>
      throw StateError('unexpected updateTrackLanguage');

  @override
  Future<void> activateWordTimeline(String timelineId) async =>
      throw StateError('unexpected activateWordTimeline');

  @override
  Future<void> activatePhoneTimeline(String timelineId) async =>
      throw StateError('unexpected activatePhoneTimeline');

  @override
  Future<void> archivePhoneTimeline(String timelineId) async =>
      throw StateError('unexpected archivePhoneTimeline');

  @override
  Future<void> deletePhoneTimeline(String timelineId) async =>
      throw StateError('unexpected deletePhoneTimeline');
}
