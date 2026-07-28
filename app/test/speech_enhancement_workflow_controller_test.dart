import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/services/api_service.dart';

/// Characterizes the graceful-degradation logic of `loadTimelineResource`:
/// each of the four sub-resources is loaded independently, only a total failure
/// is reported as unavailable, and partial failures degrade to a warning.
/// Reachable as unit tests only because of the A1 transport seam.
void main() {
  group('SpeechEnhancementWorkflowController.loadTimelineResource', () {
    test('reports unavailable when all four sub-resources fail', () async {
      final controller = SpeechEnhancementWorkflowController();
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async =>
            (statusCode: 500, body: 'boom'),
      );

      final result = await controller.loadTimelineResource(
        service: api,
        trackId: 't1',
        previous: const ExistingTimelineResourceState(),
      );

      expect(result.unavailable, isTrue);
      expect(result.error, contains('Timeline resource unavailable'));
      expect(result.wordSummaries, isEmpty);
      expect(result.phoneSummaries, isEmpty);
      expect(result.chunkSummaries, isEmpty);
    });

    test('degrades to a warning when only some sub-resources fail', () async {
      final controller = SpeechEnhancementWorkflowController();
      // Summaries decode as empty lists (200 `[]`); the LLTimeline export
      // decode fails, so exactly one sub-resource errors.
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async => (statusCode: 200, body: '[]'),
      );

      final result = await controller.loadTimelineResource(
        service: api,
        trackId: 't1',
        previous: const ExistingTimelineResourceState(),
      );

      expect(result.unavailable, isFalse);
      expect(result.wordSummaries, isEmpty);
      expect(result.error, isNotNull);
      expect(result.error, contains('warning'));
    });

    test(
      'keeps fresh rhythm frames while preserving imported artifacts',
      () async {
        final controller = SpeechEnhancementWorkflowController();
        final exported =
            jsonDecode(
                  File(
                    'test/fixtures/rhythm-frame/'
                    'fixture-no-phone-rhythm.lltimeline.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final exportedDocument = LLTimelineDocument.fromJson(exported);
        expect(exportedDocument.rhythmFrames, isNotEmpty);
        expect(exportedDocument.artifacts, isEmpty);

        final previous = LLTimelineDocument(
          schema: exportedDocument.schema,
          metadata: exportedDocument.metadata,
          activeWordTimelineId: exportedDocument.activeWordTimelineId,
          activePhoneTimelineId: exportedDocument.activePhoneTimelineId,
          activeChunkTimelineId: exportedDocument.activeChunkTimelineId,
          rhythmFrames: const [],
          artifacts: const [
            LLTimelineArtifact(
              kind: 'imported-note',
              payload: {'source': 'older-import'},
            ),
          ],
        );
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) async =>
              path.endsWith('/lltimeline/export')
              ? (statusCode: 200, body: jsonEncode(exported))
              : (statusCode: 200, body: '[]'),
        );

        final result = await controller.loadTimelineResource(
          service: api,
          trackId: 't1',
          previous: ExistingTimelineResourceState(document: previous),
        );

        expect(result.error, isNull);
        expect(result.document!.rhythmFrames, isNotEmpty);
        expect(result.document!.artifacts, hasLength(1));
        expect(result.document!.artifacts.single.kind, 'imported-note');
      },
    );
  });

  group('SpeechEnhancementWorkflowController sense-group fallback', () {
    test(
      'generates, activates, and reloads when the active result is empty',
      () async {
        final requests = <String>[];
        var senseGroupLoads = 0;
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) async {
            requests.add('$method $path');
            if (method == 'GET' && path.endsWith('/sense-group-analyses')) {
              senseGroupLoads++;
              return (
                statusCode: 200,
                body: senseGroupLoads == 1
                    ? '[]'
                    : jsonEncode([_senseGroupAnalysisJson(status: 'active')]),
              );
            }
            if (method == 'POST' && path.endsWith('/sense-group-analyses')) {
              expect(jsonDecode(body!), {'status': 'candidate'});
              return (
                statusCode: 200,
                body: jsonEncode(_senseGroupAnalysisJson(status: 'candidate')),
              );
            }
            if (method == 'POST' && path.endsWith('/activate')) {
              return (
                statusCode: 200,
                body: jsonEncode(_senseGroupAnalysisJson(status: 'active')),
              );
            }
            return (statusCode: 200, body: '[]');
          },
        );

        final result = await _loadSpeechEnhancements(
          SpeechEnhancementWorkflowController(),
          api,
        );

        expect(result.senseGroupsBySentence['sentence-1'], hasLength(1));
        expect(senseGroupLoads, 2);
        expect(
          requests,
          containsAllInOrder([
            'GET /v1/subtitles/t1/sense-group-analyses',
            'POST /v1/subtitles/t1/sense-group-analyses',
            'POST /v1/sense-group-analyses/analysis-1/activate',
            'GET /v1/subtitles/t1/sense-group-analyses',
          ]),
        );
        expect(result.errors, isNot(contains(startsWith('sense group'))));
      },
    );

    test('generation failure records an error and is not retried', () async {
      var generationRequests = 0;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (method == 'POST' && path.endsWith('/sense-group-analyses')) {
            generationRequests++;
            return (statusCode: 422, body: 'no groups');
          }
          return (statusCode: 200, body: '[]');
        },
      );
      final controller = SpeechEnhancementWorkflowController();

      final first = await _loadSpeechEnhancements(controller, api);
      final second = await _loadSpeechEnhancements(controller, api);

      expect(first.senseGroupsBySentence, isEmpty);
      expect(
        first.errors,
        contains(
          predicate<String>(
            (error) => error.startsWith('sense group fallback:'),
          ),
        ),
      );
      expect(second.senseGroupsBySentence, isEmpty);
      expect(generationRequests, 1);
    });

    test('existing active groups do not trigger generation', () async {
      final requests = <String>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          requests.add('$method $path');
          if (method == 'GET' && path.endsWith('/sense-group-analyses')) {
            return (
              statusCode: 200,
              body: jsonEncode([_senseGroupAnalysisJson(status: 'active')]),
            );
          }
          return (statusCode: 200, body: '[]');
        },
      );

      final result = await _loadSpeechEnhancements(
        SpeechEnhancementWorkflowController(),
        api,
      );

      expect(result.senseGroupsBySentence['sentence-1'], hasLength(1));
      expect(
        requests.where(
          (request) => request == 'POST /v1/subtitles/t1/sense-group-analyses',
        ),
        isEmpty,
      );
    });
  });
}

Future<SpeechEnhancementLoadResult> _loadSpeechEnhancements(
  SpeechEnhancementWorkflowController controller,
  LocalApi api,
) => controller.loadSpeechEnhancements(
  service: api,
  trackId: 't1',
  previousTimeline: const ExistingTimelineResourceState(),
);

Map<String, dynamic> _senseGroupAnalysisJson({required String status}) => {
  'id': 'analysis-1',
  'track_id': 't1',
  'media_id': 'media-1',
  'parent_word_timeline_id': null,
  'provider_id': 'text-rules',
  'provider_version': '1',
  'algorithm': 'text-rules-v1',
  'created_by': 'system',
  'status': status,
  'metrics_json': const <String, dynamic>{},
  'groups': [
    {
      'id': 'group-1',
      'sentence_id': 'sentence-1',
      'group_index': 0,
      'start_token_index': 0,
      'end_token_index': 1,
      'text': 'Hello world',
      'label': null,
      'head_token_index': null,
      'confidence': 0.8,
      'sources': ['punctuation'],
    },
  ],
  'created_at_ms': 1,
  'updated_at_ms': 2,
};
