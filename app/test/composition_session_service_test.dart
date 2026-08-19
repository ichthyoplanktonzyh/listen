import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/models/adopted_composition.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/composition_session_service.dart';
import 'package:llplayer_next/services/core_timeline_export.dart';

void main() {
  test(
    'a document composition uses its verified detached subtitle payload',
    () async {
      final repository = _FakeCapabilityRepository(
        _adoptedComposition(detached: true),
        payloads: {
          'structured-1': _structuredReadingPayload(),
          'subtitle-1': _subtitlePayload(),
          ..._richPayloads(),
        },
      );
      final service = CompositionSessionService(
        repository: repository,
        resources: _FakeResourceRepository(),
      );

      final resolved = await service.resolveComposition('material-1');

      expect(resolved, isNotNull);
      expect(resolved!.transcript, isNotNull);
      expect(
        resolved.transcript!.source,
        'composition:detached:subtitle_text_track',
      );
      expect(resolved.transcript!.cues.single.text, 'Listen, carefully!');
      expect(resolved.transcript!.cues.single.tokens[0].text, 'Listen');
      expect(resolved.transcript!.cues.single.start.inMilliseconds, 100);
      expect(resolved.enhancements.timingsBySentence['sentence-0'], isNotEmpty);
      expect(
        resolved.enhancements.senseGroupsBySentence['sentence-0'],
        isNotEmpty,
      );
      expect(
        resolved.enhancements.chunkPartitionsBySentence['sentence-0']!.chunks,
        isNotEmpty,
      );
      expect(
        resolved.enhancements.acousticsBySentence['sentence-0'],
        isNotEmpty,
      );
      expect(
        resolved.enhancements.prosodyAnchorsBySentence['sentence-0'],
        hasLength(2),
      );
      expect(resolved.enhancements.phonesBySentence['sentence-0'], isNotEmpty);
    },
  );

  test('a Core-landed source-media track wins over detached payload', () async {
    final repository = _FakeCapabilityRepository(
      _adoptedComposition(detached: false),
      payloads: {
        'structured-1': _structuredReadingPayload(),
        'subtitle-1': _subtitlePayload(),
      },
    );
    final resources = _FakeResourceRepository(
      tracks: [
        SubtitleTrack(
          id: 'global-track',
          source: 'package:subtitle_text_track',
          cues: [
            Cue(
              id: 'global-sentence',
              index: 0,
              start: const Duration(milliseconds: 200),
              end: const Duration(milliseconds: 600),
              text: 'Global track.',
              tokens: const [
                SubtitleToken(
                  index: 0,
                  kind: 'word',
                  text: 'Global',
                  normalized: 'global',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final service = CompositionSessionService(
      repository: repository,
      resources: resources,
    );

    final resolved = await service.resolveComposition('material-1');

    expect(resolved!.transcript!.id, 'global-track');
    expect(resolved.transcript!.source, 'package:subtitle_text_track');
    expect(resolved.transcript!.cues.single.text, 'Global track.');
  });

  test(
    'a missing optional rich family keeps the verified document transcript usable',
    () async {
      final repository = _FakeCapabilityRepository(
        _adoptedComposition(detached: true, includeRichResources: false),
        payloads: {
          'structured-1': _structuredReadingPayload(),
          'subtitle-1': _subtitlePayload(),
        },
      );
      final service = CompositionSessionService(
        repository: repository,
        resources: _FakeResourceRepository(),
      );

      final resolved = await service.resolveComposition('material-1');

      expect(resolved, isNotNull);
      expect(resolved!.transcript, isNotNull);
      expect(resolved.transcript!.source, contains('detached'));
      expect(resolved.enhancements.timingsBySentence, isEmpty);
      expect(resolved.enhancements.senseGroupsBySentence, isEmpty);
      expect(resolved.enhancements.acousticsBySentence, isEmpty);
      expect(resolved.enhancements.prosodyAnchorsBySentence, isEmpty);
      expect(resolved.enhancements.phonesBySentence, isEmpty);
    },
  );

  test('an unknown rich payload schema degrades only that family', () async {
    final repository = _FakeCapabilityRepository(
      _adoptedComposition(
        detached: true,
        senseGroupSchema: 'listen.payload.sense-group-analysis.v2',
      ),
      payloads: {
        'structured-1': _structuredReadingPayload(),
        'subtitle-1': _subtitlePayload(),
        ..._richPayloads(),
      },
    );
    final service = CompositionSessionService(
      repository: repository,
      resources: _FakeResourceRepository(),
    );

    final resolved = await service.resolveComposition('material-1');

    expect(resolved, isNotNull);
    expect(resolved!.transcript, isNotNull);
    expect(resolved.enhancements.timingsBySentence, isNotEmpty);
    expect(resolved.enhancements.senseGroupsBySentence, isEmpty);
    expect(resolved.enhancements.acousticsBySentence, isNotEmpty);
    expect(resolved.enhancements.prosodyAnchorsBySentence, isNotEmpty);
    expect(resolved.enhancements.phonesBySentence, isNotEmpty);
  });

  test('malformed optional rich fields never throw', () async {
    final payloads = _richPayloads();
    payloads['sense-1'] = utf8.encode(
      jsonEncode({
        'groups': [
          {
            'sentence_id': 'sentence-0',
            'group_index': 0,
            'start_token_index': 0,
            'end_token_index_exclusive': 4,
            'confidence': 0.8,
            'sources': ['rule'],
            'label': 42,
          },
        ],
      }),
    );
    payloads['prosody-1'] = utf8.encode(
      jsonEncode({
        'anchors': [
          {
            'word_ref': {'sentence_id': 'sentence-0', 'token_index': 0},
            'lexical_stress': 42,
            'realized_prominence': 0.8,
            'utterance_role': 'nucleus',
            'evidence': ['energy'],
            'confidence': 0.8,
          },
        ],
      }),
    );
    payloads['phone-1'] = utf8.encode(
      jsonEncode({
        'phone_set': 'ipa',
        'precision': 'aligned',
        'phones': [
          {
            'symbol': 'l',
            'display_ipa': 42,
            'start_ms': 120,
            'end_ms': 180,
            'word_ref': {'sentence_id': 'sentence-0', 'token_index': 0},
          },
        ],
      }),
    );
    final repository = _FakeCapabilityRepository(
      _adoptedComposition(detached: true),
      payloads: {
        'structured-1': _structuredReadingPayload(),
        'subtitle-1': _subtitlePayload(),
        ...payloads,
      },
    );
    final service = CompositionSessionService(
      repository: repository,
      resources: _FakeResourceRepository(),
    );

    final resolved = await service.resolveComposition('material-1');

    expect(resolved, isNotNull);
    expect(resolved!.transcript, isNotNull);
    expect(resolved.enhancements.senseGroupsBySentence, isEmpty);
    expect(resolved.enhancements.prosodyAnchorsBySentence, isEmpty);
    expect(resolved.enhancements.phonesBySentence, isEmpty);
  });

  test(
    'malformed detached payload remains an honest missing transcript',
    () async {
      final repository = _FakeCapabilityRepository(
        _adoptedComposition(detached: true),
        payloads: {
          'structured-1': _structuredReadingPayload(),
          'subtitle-1': utf8.encode('{"sentences":[{"id":"broken"}]}'),
        },
      );
      final service = CompositionSessionService(
        repository: repository,
        resources: _FakeResourceRepository(),
      );

      final resolved = await service.resolveComposition('material-1');

      expect(resolved, isNotNull);
      expect(resolved!.transcript, isNull);
    },
  );
}

AdoptedComposition _adoptedComposition({
  required bool detached,
  String? senseGroupSchema,
  bool includeRichResources = true,
}) => AdoptedComposition(
  materialId: 'material-1',
  materialRevisionId: 'revision-1',
  releaseId: 'release-1',
  editionId: 'edition-1',
  title: 'Lesson',
  targetLanguage: 'en',
  supportLanguages: const [],
  adoptedAtMs: 1,
  resources: [
    _resource('structured-1', 'structured_reading'),
    _resource('subtitle-1', 'subtitle_text_track'),
    if (includeRichResources) ...[
      _resource('word-1', 'word_timeline'),
      _resource('sense-1', 'sense_group_analysis', schema: senseGroupSchema),
      _resource('acoustics-1', 'word_acoustics'),
      _resource('prosody-1', 'prosody_analysis'),
      _resource('phone-1', 'phone_timeline'),
    ],
  ],
  renditions: [
    if (!detached)
      const AdoptedCompositionRendition(
        renditionId: 'source-media-1',
        kind: 'media',
        origin: 'source',
        mediaType: 'audio/wav',
        language: 'en',
        digest: 'digest',
        byteSize: 1,
        blobAvailable: false,
        binding: AdoptedCompositionMediaBinding(mediaId: 'media-1'),
        producerToolId: 'source',
      ),
  ],
);

AdoptedCompositionResource _resource(
  String id,
  String kind, {
  String? schema,
}) => AdoptedCompositionResource(
  resourceId: id,
  kind: kind,
  schema:
      schema ??
      switch (kind) {
        'subtitle_text_track' => 'listen.payload.subtitle-text-track.v1',
        'word_timeline' => 'listen.payload.word-timeline.v1',
        'sense_group_analysis' => 'listen.payload.sense-group-analysis.v1',
        'word_acoustics' => 'listen.payload.word-acoustics.v1',
        'prosody_analysis' => 'listen.payload.prosody-analysis.v1',
        'phone_timeline' => 'listen.payload.phone-timeline.v1',
        _ => 'listen.$kind.v1',
      },
  role: 'base',
  required: kind == 'structured_reading',
  availability: 'available',
  contentLanguage: 'en',
  supportLanguages: const [],
  payloadDigest: 'digest-$id',
  payloadSizeBytes: 1,
  reviewStatus: 'verified',
);

List<int> _structuredReadingPayload() => utf8.encode(
  jsonEncode({
    'text': 'Listen, carefully!',
    'anchors': [
      {
        'anchor_id': 'sentence-0',
        'kind': 'sentence',
        'start_offset': 0,
        'end_offset': 18,
      },
    ],
  }),
);

List<int> _subtitlePayload() => utf8.encode(
  jsonEncode({
    'language': 'en',
    'sentences': [
      {
        'id': 'sentence-0',
        'index': 0,
        'display_text': 'Listen, carefully!',
        'start_ms': 100,
        'end_ms': 1200,
        'tokens': [
          {
            'index': 0,
            'kind': 'word',
            'text': 'Listen',
            'normalized': 'listen',
            'start_char': 0,
            'end_char': 6,
          },
          {
            'index': 1,
            'kind': 'punctuation',
            'text': ',',
            'normalized': null,
            'start_char': 6,
            'end_char': 7,
          },
          {
            'index': 2,
            'kind': 'whitespace',
            'text': ' ',
            'normalized': null,
            'start_char': 7,
            'end_char': 8,
          },
          {
            'index': 3,
            'kind': 'word',
            'text': 'carefully',
            'normalized': 'carefully',
            'start_char': 8,
            'end_char': 17,
          },
          {
            'index': 4,
            'kind': 'punctuation',
            'text': '!',
            'normalized': null,
            'start_char': 17,
            'end_char': 18,
          },
        ],
      },
    ],
  }),
);

Map<String, List<int>> _richPayloads() => {
  'word-1': utf8.encode(
    jsonEncode({
      'words': [
        {
          'sentence_id': 'sentence-0',
          'token_index': 0,
          'start_ms': 120,
          'end_ms': 350,
          'timing_source': 'forced_aligned',
          'confidence': 0.9,
        },
        {
          'sentence_id': 'sentence-0',
          'token_index': 3,
          'start_ms': 500,
          'end_ms': 900,
          'timing_source': 'forced_aligned',
          'confidence': 0.9,
        },
      ],
    }),
  ),
  'sense-1': utf8.encode(
    jsonEncode({
      'groups': [
        {
          'sentence_id': 'sentence-0',
          'group_index': 0,
          'start_token_index': 0,
          'end_token_index_exclusive': 4,
          'confidence': 0.8,
          'sources': ['rule'],
        },
      ],
    }),
  ),
  'acoustics-1': utf8.encode(
    jsonEncode({
      'sample_rate_hz': 16000,
      'energy_baseline': 'sentence_median_dbfs',
      'pitch_baseline': 'sentence_median_f0_hz',
      'measurements': [
        {
          'word_ref': {'sentence_id': 'sentence-0', 'token_index': 0},
          'energy': {'rms_dbfs': -20.0},
          'pitch': {'median_f0_hz': 180.0},
          'duration': {'duration_ms': 230},
          'voiced_frame_ratio': 0.9,
        },
      ],
    }),
  ),
  'prosody-1': utf8.encode(
    jsonEncode({
      'chunks': [
        {
          'sentence_id': 'sentence-0',
          'chunk_index': 0,
          'start_token_index': 0,
          'end_token_index_exclusive': 4,
          'nucleus_token_index': 0,
          'confidence': 0.8,
        },
      ],
      'anchors': [
        {
          'word_ref': {'sentence_id': 'sentence-0', 'token_index': 0},
          'lexical_stress': 'primary',
          'realized_prominence': 0.8,
          'utterance_role': 'nucleus',
          'evidence': ['energy'],
          'confidence': 0.8,
        },
        {
          'word_ref': {'sentence_id': 'sentence-0', 'token_index': 0},
          'syllable_index': 1,
          'lexical_stress': 'secondary',
          'realized_prominence': 0.4,
          'utterance_role': 'prenuclear',
          'evidence': ['lexical_stress'],
          'confidence': 0.6,
        },
      ],
    }),
  ),
  'phone-1': utf8.encode(
    jsonEncode({
      'phone_set': 'ipa',
      'precision': 'aligned',
      'phones': [
        {
          'symbol': 'l',
          'display_ipa': 'l',
          'start_ms': 120,
          'end_ms': 180,
          'confidence': 0.8,
          'word_ref': {'sentence_id': 'sentence-0', 'token_index': 0},
        },
      ],
    }),
  ),
};

final class _FakeCapabilityRepository implements CapabilityRepository {
  _FakeCapabilityRepository(this.adopted, {required this.payloads});

  final AdoptedComposition adopted;
  final Map<String, List<int>> payloads;

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', code: 'unexpected');

  @override
  Future<AdoptedComposition> readAdoptedComposition(String materialId) async =>
      adopted;

  @override
  Future<List<int>> readCompositionResourcePayload(
    String materialId,
    String resourceId,
  ) async => payloads[resourceId]!;

  @override
  Future<List<int>> readCompositionRenditionBlob(
    String materialId,
    String renditionId,
  ) async => throw StateError('unexpected rendition read');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeResourceRepository implements ResourceRepository {
  _FakeResourceRepository({this.tracks = const []});

  final List<SubtitleTrack> tracks;

  @override
  bool get isAvailable => true;

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', code: 'unexpected');

  @override
  Future<List<SubtitleTrack>> mediaSubtitles(String mediaId) async => tracks;

  @override
  Future<CoreTimelineExport> exportTimelineJson(String trackId) async =>
      CoreTimelineExport(const {});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
