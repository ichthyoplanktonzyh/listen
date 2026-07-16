import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

      expect(exported, document);
      expect(exported['future_extension'], {'preserved': true});
    });

    test('production corpus search builds the query and decodes hits', () async {
      String? seenPath;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          seenPath = path;
          return (
            statusCode: 200,
            body: jsonEncode([
              {
                'document': {
                  'id': 'document-1',
                  'language': 'en',
                  'channel': 'written',
                  'assistance': 'content_anchored',
                  'attempt_id': 'attempt-1',
                  'rubric_id': 'rubric-1',
                  'response_revision': 1,
                  'task_kind': 'opinion',
                  'media_id': null,
                  'start_ms': 0,
                  'end_ms': 1000,
                  'response_text': 'A useful proposal.',
                  'produced_at_ms': 42,
                },
                'entry': {
                  'id': 'entry-1',
                  'document_id': 'document-1',
                  'normalized_key': 'proposal',
                  'display_text': 'proposal',
                  'start_char': 9,
                  'end_char': 17,
                },
              },
            ]),
          );
        },
      );

      final hits = await api.searchProductionCorpus(
        language: 'en',
        query: 'useful proposal',
      );

      expect(
        seenPath,
        '/v1/production-corpus/search?language=en&query=useful+proposal&limit=50&offset=0',
      );
      expect(hits.single.document.responseText, 'A useful proposal.');
      expect(hits.single.entry!.normalizedKey, 'proposal');
    });

    test('production gap review decodes starter and ranked target', () async {
      String? seenPath;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          seenPath = path;
          return (
            statusCode: 200,
            body: jsonEncode({
              'language': 'en',
              'channel': 'written',
              'readiness': 'starter',
              'document_count': 1,
              'token_count': 4,
              'lemma_count': 4,
              'candidate_count': 1,
              'ranking_version': 'production-gap-ranking-v1',
              'targets': [
                {
                  'lexical_entry_id': 'entry-enjoy',
                  'normalized_key': 'enjoy',
                  'display_form': 'enjoy',
                  'frequency_rank': 685,
                  'frequency_band': 1,
                  'evidence_strength': 3,
                  'recency_band': 2,
                  'reading_acquired': true,
                  'listening_acquired': false,
                  'reading_successes': 0,
                  'listening_successes': 0,
                  'recognition_contexts': 0,
                  'latest_receptive_at_ms': 42,
                  'explanation': ['BNC frequency rank 685'],
                },
              ],
            }),
          );
        },
      );

      final review = await api.productionGapReview(language: 'en');

      expect(
        seenPath,
        '/v1/production-gap/review?language=en&channel=written&limit=10',
      );
      expect(review.readiness, 'starter');
      expect(review.targets.single.frequencyRank, 685);
    });

    test(
      'short recording transcription keeps raw ASR and provenance typed',
      () async {
        String? seenBody;
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) async {
            seenBody = body;
            return (
              statusCode: 200,
              body: jsonEncode({
                'id': 'rt-1',
                'recording_asset_id': 'recording-1',
                'status': 'completed',
                'raw_transcript': 'hello there',
                'segments': [
                  {'start_ms': 0, 'end_ms': 800, 'text': 'hello there'},
                ],
                'provenance': {
                  'provider_id': 'whisper.cpp',
                  'provider_version': 'whisper-cli',
                  'runtime_id': 'whisper.cpp-cli',
                  'runtime_version': 'whisper-cli',
                  'model_id': 'base.en',
                  'model_revision': 'pinned',
                  'model_checksum_sha256': 'model-sha',
                  'recording_content_sha256': 'recording-sha',
                  'requested_language': 'en',
                  'detected_language': 'en',
                },
                'error_code': null,
                'error_message': null,
                'created_at_ms': 10,
                'started_at_ms': 12,
                'completed_at_ms': 42,
                'latency_ms': 30,
              }),
            );
          },
        );

        final job = await api.createRecordingTranscription(
          recordingId: 'recording-1',
          modelId: 'base.en',
          language: 'en',
        );

        expect(jsonDecode(seenBody!), {
          'recording_id': 'recording-1',
          'model_id': 'base.en',
          'language': 'en',
        });
        expect(job.rawTranscript, 'hello there');
        expect(job.segments.single.endMs, 800);
        expect(job.provenance.detectedLanguage, 'en');
        expect(job.latencyMs, 30);
      },
    );

    test(
      'spoken attempt keeps raw and corrected transcripts separate',
      () async {
        Map<String, dynamic>? request;
        final api = LocalApi.withTransport(
          baseUrl: 'http://test',
          token: 'tok',
          transport: (method, path, body) async {
            request = jsonDecode(body!) as Map<String, dynamic>;
            return (
              statusCode: 200,
              body: jsonEncode({...request!, 'id': 'attempt-speaking-1'}),
            );
          },
        );

        final attempt = await api.createSpokenSemanticAttempt(
          kind: 'role_reply',
          target: {
            'kind': 'segment',
            'id': 'segment-1',
            'sentence_id': null,
            'chunk_id': null,
            'start_ms': 0,
            'end_ms': 8000,
          },
          rubricId: 'rubric-role-1',
          rubricVersion: 1,
          audioPlayCount: 1,
          speakingAssistance: 'keywords',
          speakingRecall: 'immediate',
          promptSnapshot: 'Reply to the shop clerk',
          recordingAssetId: 'recording-1',
          rawTranscript: 'I need two ticket',
          correctedTranscript: 'I need two tickets',
          asrReliability: 'suspect',
          responseLanguage: 'en',
          startedAtMs: 10,
          endedAtMs: 20,
        );

        final response =
            (request!['responses'] as List<dynamic>).single
                as Map<String, dynamic>;
        expect(response['raw_transcript'], 'I need two ticket');
        expect(response['transcript'], 'I need two tickets');
        expect(response['recording_asset_id'], 'recording-1');
        expect(
          request!['conditions'],
          containsPair('speaking_assistance', 'keywords'),
        );
        expect(
          request!['conditions'],
          containsPair('speaking_recall', 'immediate'),
        );
        expect(attempt.responses.single.rawTranscript, 'I need two ticket');
        expect(attempt.responses.single.transcript, 'I need two tickets');
      },
    );
  });
}
