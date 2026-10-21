import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/models/review_deck.dart';
import 'package:llplayer_next/services/api_service.dart';

/// Exercises the A1 transport seam: `LocalApi.withTransport` lets the client be
/// driven without a live sidecar, so request building, JSON decoding, and error
/// mapping can be unit tested. (Full method/controller coverage builds on this.)
void main() {
  group('LocalApi transport seam', () {
    test(
      'routes a GET through the transport and decodes the JSON body',
      () async {
        String? seenMethod;
        String? seenPath;
        String? seenBody;
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) async {
            seenMethod = method;
            seenPath = path;
            seenBody = body;
            return (
              statusCode: 200,
              body:
                  '{"id":"m1","path":"/clip.mp4","fingerprint":"fp",'
                  '"title":"Clip","kind":"video","duration":1000,'
                  '"availability":"available","created_at_ms":1,'
                  '"updated_at_ms":2}',
            );
          },
        );

        final media = await api.readMedia('m1');

        expect(media.id, 'm1');
        expect(media.title, 'Clip');
        expect(seenMethod, 'GET');
        expect(seenPath, '/v1/media/m1');
        expect(seenBody, isNull, reason: 'a GET carries no request body');
      },
    );

    test('maps a non-2xx response to an HttpException', () async {
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async =>
            (statusCode: 404, body: 'not found'),
      );

      expect(() => api.readMedia('missing'), throwsA(isA<HttpException>()));
    });

    test('encodes the request body and forwards it to the transport', () async {
      String? seenMethod;
      String? seenPath;
      String? seenBody;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          seenMethod = method;
          seenPath = path;
          seenBody = body;
          return (statusCode: 200, body: '');
        },
      );

      await api.saveProgress('m1', const Duration(seconds: 5));

      expect(seenMethod, 'PUT');
      expect(seenPath, '/v1/media/m1/progress');
      expect(jsonDecode(seenBody!), {'position_ms': 5000});
    });

    test(
      'finalizes a cancelled capability attempt with cancelled status only',
      () async {
        Map<String, dynamic>? requestBody;
        String? requestPath;
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) async {
            expect(method, 'PUT');
            requestPath = path;
            requestBody = jsonDecode(body!) as Map<String, dynamic>;
            return (
              statusCode: 200,
              body: jsonEncode({
                'attempt_id': 'attempt/1',
                'status': requestBody!['status'],
                'started_at_ms': 1,
                'finished_at_ms': 2,
                'failure_reason': null,
                'producer_tool_id': null,
                'producer_tool_version': null,
              }),
            );
          },
        );

        final attempt = await api.finalizeCapabilityAttempt(
          materialId: 'material/1',
          attemptId: 'attempt/1',
          status: CapabilityAttemptFinalStatus.cancelled,
        );

        expect(
          requestPath,
          '/v1/materials/material%2F1/capability-attempts/attempt%2F1',
        );
        expect(requestBody, {'status': 'cancelled'});
        expect(attempt.status, 'cancelled');
        expect(attempt.failureReason, isNull);
      },
    );

    test('builds syntax lifecycle and force-rebuild requests', () async {
      final seen = <String>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          seen.add('$method $path ${body ?? ''}');
          return (statusCode: 200, body: '{}');
        },
      );

      await api.syntaxCapability();
      await api.syntaxCapabilityAction('validate');
      await api.runTrackSyntaxAnalysis('track/a', force: true);

      expect(seen[0], 'GET /v1/syntax/capability ');
      expect(seen[1], 'POST /v1/syntax/capability/validate {}');
      expect(seen[2], contains('POST /v1/subtitles/track%2Fa/syntax-analysis'));
      expect(jsonDecode(seen[2].substring(seen[2].indexOf('{'))), {
        'force': true,
      });
    });

    test('builds and decodes speech synthesis requests', () async {
      String? requestBody;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          expect('$method $path', 'POST /v1/speech-synthesis');
          requestBody = body;
          return (
            statusCode: 200,
            body:
                '{"audio_path":"/tmp/a.aiff","mime_type":"audio/aiff",'
                '"provider_id":"macos-system-speech",'
                '"provider_version":"say-v1","voice_id":"Samantha",'
                '"language":"en","rate_words_per_minute":180,'
                '"purpose":"dictionary_pronunciation_fallback",'
                '"content_hash":"hash","cache_hit":true,"synthetic":true}',
          );
        },
      );

      final asset = await api.synthesizeSpeech(
        text: 'hello',
        language: 'en',
        purpose: 'dictionary_pronunciation_fallback',
      );

      expect(asset.providerId, 'macos-system-speech');
      expect(asset.cacheHit, isTrue);
      expect(jsonDecode(requestBody!), containsPair('language', 'en'));
    });

    test('diagnosis resource decodes into a typed result', () async {
      String? seenPath;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          seenPath = path;
          return (
            statusCode: 200,
            body: '{"hints":[],"l1_hints":[],"l1_context":null}',
          );
        },
      );

      final diagnosis = await api.diagnose('sentence/1');

      expect(diagnosis.hints, isEmpty);
      expect(diagnosis.l1Hints, isEmpty);
      expect(seenPath, '/v1/sentences/sentence%2F1/diagnosis');
    });

    test('subtitle resource decodes before leaving the client', () async {
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async => (
          statusCode: 200,
          body: '{"id":"track-1","media_id":"media-1","sentences":[]}',
        ),
      );

      final track = await api.readSubtitle('track/1');

      expect(track.id, 'track-1');
      expect(track.mediaId, 'media-1');
      expect(track.cues, isEmpty);
    });

    test('vocabulary export preserves its open transfer document', () async {
      const document = {
        'version': 7,
        'exported_at_ms': 42,
        'lexical_entries': <Object>[],
        'future_extension': {'preserved': true},
      };
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async =>
            (statusCode: 200, body: jsonEncode(document)),
      );

      final exported = await api.exportVocabulary();

      expect(exported.version, 7);
      expect(exported.exportedAtMs, 42);
      expect(exported.lexicalEntries, isEmpty);
      expect(exported.toJson(), document);
      expect(exported['future_extension'], {'preserved': true});
      expect(
        () => exported.toJson()['new_field'] = true,
        throwsUnsupportedError,
      );
    });

    test('semantic search queries only the listening corpus', () async {
      String? seenPath;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          seenPath = path;
          return (
            statusCode: 200,
            body: jsonEncode({
              'capability': {
                'status': 'ready',
                'indexed_source_count': 2,
                'descriptor': {
                  'model_id': 'all-MiniLM-L6-v2',
                  'model_version': 'revision-a',
                  'dimension': 384,
                  'model_fingerprint': 'abcdef0123456789',
                  'local': true,
                },
              },
              'query': 'a very big room',
              'hits': [
                {
                  'source': {
                    'kind': 'media_corpus',
                    'source_id': 'sentence-1',
                    'language': 'en',
                    'text': 'An enormous hall.',
                    'start_ms': 10,
                    'end_ms': 20,
                  },
                  'similarity': 0.82,
                  'model_fingerprint': 'abcdef0123456789',
                },
              ],
            }),
          );
        },
      );

      final result = await api.semanticSearch(
        query: 'a very big room',
        language: 'en',
      );

      expect(seenPath, contains('/v1/semantic-search?query=a+very+big+room'));
      expect(seenPath, contains('language=en'));
      expect(seenPath, isNot(contains('source=')));
      expect(seenPath, isNot(contains('channel=')));
      expect(result.capability.canSearch, isTrue);
      expect(result.hits.single.source.text, 'An enormous hall.');
      expect(result.hits.single.similarity, closeTo(0.82, 0.001));
    });

    test(
      'custom study sends listening only and rejects other channels early',
      () async {
        final calls = <String>[];
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) async {
            calls.add('$method $path');
            expect(jsonDecode(body!), {
              'kind': 'channel',
              'channel': 'listening',
              'limit': 10,
            });
            return (
              statusCode: 200,
              body: jsonEncode({
                'entries': <Object>[],
                'advances_normal_schedule': false,
              }),
            );
          },
        );

        await expectLater(
          api.customStudy(
            const CustomStudyRequest(
              kind: CustomStudyKind.channel,
              channel: 'speaking',
              limit: 10,
            ),
          ),
          throwsArgumentError,
        );
        expect(calls, isEmpty);

        final queue = await api.customStudy(
          const CustomStudyRequest(
            kind: CustomStudyKind.channel,
            channel: 'listening',
            limit: 10,
          ),
        );

        expect(calls, ['POST /v1/review/custom-study']);
        expect(queue.entries, isEmpty);
        expect(queue.advancesNormalSchedule, isFalse);
      },
    );

    group('Core 5.0 media membership contract', () {
      late Directory temp;
      late String mediaPath;

      setUp(() {
        temp = Directory.systemTemp.createTempSync('retention-contract');
        final file = File('${temp.path}/talk.mp3')
          ..writeAsBytesSync([1, 2, 3, 4, 5]);
        mediaPath = file.path;
      });

      tearDown(() => temp.deleteSync(recursive: true));

      test(
        'opening-style registration is Temporary Material (retain false)',
        () async {
          Map<String, dynamic>? request;
          final api = LocalApi.withTransport(
            baseUrl: 'http://test',
            token: 'tok',
            transport: (method, path, body) async {
              expect(method, 'POST');
              expect(path, '/v1/media');
              request = jsonDecode(body!) as Map<String, dynamic>;
              return (
                statusCode: 200,
                body:
                    '{"id":"media-1","path":"$mediaPath","fingerprint":"fp",'
                    '"title":"talk.mp3","kind":"audio","duration":null,'
                    '"availability":"available","created_at_ms":1,'
                    '"updated_at_ms":2}',
              );
            },
          );

          final media = await api.registerMedia(mediaPath, retain: false);

          expect(request!['path'], mediaPath);
          expect(request!['retain'], isFalse);
          expect(media.isRetained, isFalse);
        },
      );

      test(
        'Keep registration sends retain true and the managed title',
        () async {
          Map<String, dynamic>? request;
          final api = LocalApi.withTransport(
            baseUrl: 'http://test',
            token: 'tok',
            transport: (method, path, body) async {
              request = jsonDecode(body!) as Map<String, dynamic>;
              return (
                statusCode: 200,
                body:
                    '{"id":"media-1","path":"$mediaPath","fingerprint":"fp",'
                    '"title":"Original","kind":"audio","duration":null,'
                    '"availability":"available","created_at_ms":1,'
                    '"updated_at_ms":2,"retained_at_ms":42}',
              );
            },
          );

          final media = await api.registerMedia(
            mediaPath,
            retain: true,
            title: 'Original',
          );

          expect(request!['retain'], isTrue);
          expect(request!['title'], 'Original');
          expect(media.retainedAtMs, 42);
          expect(media.isRetained, isTrue);
        },
      );

      test(
        'retain and unretain parse the library-membership response',
        () async {
          final seen = <String>[];
          final api = LocalApi.withTransport(
            baseUrl: 'http://test',
            token: 'tok',
            transport: (method, path, body) async {
              seen.add('$method $path');
              return (
                statusCode: 200,
                body:
                    '{"id":"media-1","path":"$mediaPath","fingerprint":"fp",'
                    '"title":"talk.mp3","kind":"audio","duration":null,'
                    '"availability":"available","created_at_ms":1,'
                    '"updated_at_ms":2,"retained_at_ms":'
                    '${method == 'PUT' ? '42' : 'null'}}',
              );
            },
          );

          final retained = await api.retainMedia('media/1');
          final unretained = await api.unretainMedia('media/1');

          expect(seen[0], 'PUT /v1/media/media%2F1/library-membership');
          expect(seen[1], 'DELETE /v1/media/media%2F1/library-membership');
          expect(retained.retainedAtMs, 42);
          expect(unretained.retainedAtMs, isNull);
        },
      );

      test('MediaItem tolerates an absent retained_at_ms', () async {
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) async => (
            statusCode: 200,
            body:
                '{"id":"media-1","path":"/t.mp3","fingerprint":"fp",'
                '"title":"T","kind":"audio","duration":null,'
                '"availability":"available","created_at_ms":1,'
                '"updated_at_ms":2}',
          ),
        );

        final media = await api.readMedia('media-1');

        expect(media.retainedAtMs, isNull);
        expect(media.isRetained, isFalse);
      });
    });
  });
}
