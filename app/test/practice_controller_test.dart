import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/practice.dart';
import 'package:llplayer_next/controllers/practice_controller.dart';
import 'package:llplayer_next/data/repositories/practice_repository.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';

void main() {
  test('practice controller creates cloze item and submits attempt', () async {
    final requests = <({String method, String path, Object? body})>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        final decoded = body == null ? null : jsonDecode(body);
        requests.add((method: method, path: path, body: decoded));
        if (path == '/v1/practice/sessions') {
          return (
            statusCode: 200,
            body:
                '{"id":"session-1","mode":"intensive","media_id":"media-1","track_id":"track-1","source":"current_sentence_practice","started_at_ms":1,"ended_at_ms":null}',
          );
        }
        if (path == '/v1/practice/items') {
          final value = decoded as Map<String, dynamic>;
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': 'item-1',
              'session_id': value['session_id'],
              'kind': value['kind'],
              'target': value['target'],
              'prompt_snapshot': value['prompt_snapshot'],
              'expected_answer': {'text': value['expected_text']},
              'anchors': value['anchors'],
              'created_at_ms': 2,
            }),
          );
        }
        if (path == '/v1/practice/attempts') {
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': 'attempt-1',
              'item_id': 'item-1',
              'submitted_at_ms': 3,
              'input': {'text': 'hard'},
              'result': 'incorrect',
              'score': 0.0,
              'evaluation': {
                'summary': '0/1 tokens matched',
                'token_results': [
                  {'expected': 'heard', 'actual': 'hard', 'result': 'mismatch'},
                ],
                'extra': <String, dynamic>{},
              },
              'generated_observation_ids': ['obs-1'],
              'generated_review_item_ids': <dynamic>[],
            }),
          );
        }
        if (path == '/v1/review/items') {
          final value = decoded as Map<String, dynamic>;
          return (
            statusCode: 200,
            body: jsonEncode({
              'id': 'review-1',
              'source': value['source'],
              'anchors': value['anchors'],
              'prompt_snapshot': value['prompt_snapshot'],
              'status': 'active',
              'created_at_ms': 4,
              'updated_at_ms': 4,
            }),
          );
        }
        return (statusCode: 404, body: 'unexpected $method $path');
      },
    );
    final controller = PracticeController(
      repository: LocalPracticeRepository(() => api),
    );
    const cue = Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration(milliseconds: 100),
      end: Duration(milliseconds: 900),
      text: 'I heard it',
      tokens: [
        SubtitleToken(index: 0, kind: 'word', text: 'I ', normalized: 'i'),
        SubtitleToken(
          index: 1,
          kind: 'word',
          text: 'heard ',
          normalized: 'heard',
        ),
        SubtitleToken(index: 2, kind: 'word', text: 'it', normalized: 'it'),
      ],
    );

    await controller.startCloze(
      cue: cue,
      mediaId: 'media-1',
      trackId: 'track-1',
      wordTimings: const [
        WordTiming(
          sentenceId: 'sentence-1',
          tokenIndex: 1,
          start: Duration(milliseconds: 240),
          end: Duration(milliseconds: 430),
          source: 'forced_aligned',
          provider: 'fixture',
        ),
      ],
      wordEntries: const {
        'heard': LexicalEntry(
          id: 'lexical-heard',
          normalizedForm: 'heard',
          displayForm: 'heard',
          kind: 'word',
          status: 'known_recognized',
          language: 'en',
        ),
      },
      mediaTimeMs: (value) => value.inMilliseconds + 10,
    );

    expect(controller.item?.kind, 'cloze');
    expect(controller.draft?.promptText, 'I ____it');
    expect(controller.draft?.expectedText, 'heard');
    expect(controller.draft?.playbackStartMs, 250);
    expect(
      controller.item?.anchors.any((a) => a.lexicalEntryId == 'lexical-heard'),
      true,
    );

    controller.setAnswer('hard');
    await controller.submit();

    expect(controller.attempt?.result, 'incorrect');
    expect(controller.attempt?.generatedObservationIds, ['obs-1']);

    await controller.saveCurrentFailureToReview();

    expect(controller.attempt?.generatedReviewItemIds, ['review-1']);
    expect(controller.error, isNull);
    expect(
      requests.where((request) => request.path.contains('/summary')),
      isEmpty,
    );
    final itemRequest = requests.firstWhere(
      (r) => r.path == '/v1/practice/items',
    );
    expect(
      (itemRequest.body as Map<String, dynamic>)['expected_text'],
      'heard',
    );
  });

  test(
    'shadowing expands chunk context and records an unscored comparison',
    () async {
      final requests = <({String method, String path, Object? body})>[];
      var itemCounter = 0;
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          final decoded = body == null ? null : jsonDecode(body);
          requests.add((method: method, path: path, body: decoded));
          if (path == '/v1/practice/sessions') {
            return (
              statusCode: 200,
              body:
                  '{"id":"session-shadow","mode":"intensive","media_id":"media-1","track_id":"track-1","source":"current_sentence_practice","started_at_ms":1,"ended_at_ms":null}',
            );
          }
          if (path == '/v1/practice/items') {
            itemCounter++;
            final value = decoded as Map<String, dynamic>;
            return (
              statusCode: 200,
              body: jsonEncode({
                'id': 'shadow-item-$itemCounter',
                'session_id': value['session_id'],
                'kind': value['kind'],
                'target': value['target'],
                'prompt_snapshot': value['prompt_snapshot'],
                'expected_answer': {'text': value['expected_text']},
                'anchors': value['anchors'],
                'created_at_ms': itemCounter + 1,
              }),
            );
          }
          if (path == '/v1/recordings') {
            final value = decoded as Map<String, dynamic>;
            return (
              statusCode: 200,
              body: jsonEncode({
                'id': 'recording-1',
                ...value,
                'created_at_ms': 5,
                'practice_attempt_id': null,
              }),
            );
          }
          if (path == '/v1/practice/shadowing-attempts') {
            final value = decoded as Map<String, dynamic>;
            return (
              statusCode: 200,
              body: jsonEncode({
                'id': 'attempt-shadow',
                'item_id': value['item_id'],
                'submitted_at_ms': 6,
                'input': {'recording_id': value['recording_id']},
                'result': 'completed',
                'score': null,
                'evaluation': {
                  'summary':
                      'Shadowing recording completed without automated scoring.',
                  'token_results': <dynamic>[],
                  'extra': {'evaluation_kind': 'not_scored'},
                },
                'generated_observation_ids': <dynamic>[],
                'generated_review_item_ids': <dynamic>[],
              }),
            );
          }
          if (path == '/v1/shadowing/comparisons') {
            return (
              statusCode: 200,
              body: jsonEncode({
                'attempt_id': 'attempt-shadow',
                'reference_segment': {
                  'media_id': 'media-1',
                  'start_ms': 100,
                  'end_ms': 900,
                  'label': '1 + 2',
                  'subtitle_snapshot': 'Follow this chunk',
                  'availability': 'available',
                },
                'recording_id': 'recording-1',
                'duration_delta_ms': 80,
                'pause_alignment': {
                  'reference_pauses': [
                    {'start_ms': 300, 'end_ms': 450},
                  ],
                  'recording_pauses': [
                    {'start_ms': 340, 'end_ms': 500},
                  ],
                  'mean_absolute_offset_ms': 45,
                },
                'reference_waveform': {
                  'duration_ms': 800,
                  'bucket_ms': 100,
                  'peaks': [0.2, 0.8],
                  'rms': [0.1, 0.5],
                },
                'recording_waveform': {
                  'duration_ms': 880,
                  'bucket_ms': 100,
                  'peaks': [0.3, 0.7],
                  'rms': [0.2, 0.4],
                },
              }),
            );
          }
          return (statusCode: 404, body: 'unexpected $method $path');
        },
      );
      final recorder = _FakeRecorder();
      final controller = PracticeController(
        repository: LocalPracticeRepository(() => api),
        recorder: recorder,
      );
      const cue = Cue(
        id: 'sentence-shadow',
        index: 0,
        start: Duration(milliseconds: 100),
        end: Duration(milliseconds: 1600),
        text: 'Follow this chunk and then finish the sentence.',
        tokens: [],
      );
      const chunks = [
        DisplayChunk(
          index: 0,
          tokenStart: 0,
          tokenEnd: 2,
          text: 'Follow this chunk',
          start: Duration(milliseconds: 100),
          end: Duration(milliseconds: 600),
        ),
        DisplayChunk(
          index: 1,
          tokenStart: 3,
          tokenEnd: 5,
          text: 'and then finish',
          start: Duration(milliseconds: 600),
          end: Duration(milliseconds: 1100),
        ),
        DisplayChunk(
          index: 2,
          tokenStart: 6,
          tokenEnd: 7,
          text: 'the sentence',
          start: Duration(milliseconds: 1100),
          end: Duration(milliseconds: 1600),
        ),
      ];

      await controller.startShadowing(
        cue: cue,
        chunk: chunks.first,
        chunks: chunks,
        mediaId: 'media-1',
        trackId: 'track-1',
        mediaTimeMs: (value) => value.inMilliseconds,
      );
      expect(controller.draft?.shadowingSteps.length, 3);
      expect(controller.item?.target.kind, 'chunk');

      await controller.selectShadowingStep(
        index: 1,
        mediaId: 'media-1',
        trackId: 'track-1',
      );
      expect(controller.draft?.focusLabel, '1 + 2');
      expect(controller.item?.target.kind, 'segment');

      var focusAcquired = false;
      expect(
        await controller.beginShadowingRecording(
          acquireAudioFocus: () async => focusAcquired = true,
        ),
        isTrue,
      );
      expect(focusAcquired, isTrue);
      expect(controller.recordingActive, isTrue);

      await controller.stopShadowingRecording(
        language: 'en',
        mediaId: 'media-1',
        extractReferenceWav: () async => '/tmp/reference.wav',
      );
      expect(controller.attempt?.result, 'completed');
      expect(controller.attempt?.generatedObservationIds, isEmpty);
      expect(controller.recordingAsset?.id, 'recording-1');
      expect(controller.comparison?.durationDeltaMs, 80);
      expect(controller.comparison?.meanAbsolutePauseOffsetMs, 45);
      expect(
        requests.any((request) => request.path == '/v1/shadowing/comparisons'),
        isTrue,
      );
      controller.dispose();
    },
  );

  test('shadowing permission denial does not acquire audio focus', () async {
    final recorder = _FakeRecorder(
      permission: MicrophonePermissionStatus.denied,
    );
    final controller = PracticeController(recorder: recorder);
    var focusAcquired = false;
    expect(
      await controller.beginShadowingRecording(
        acquireAudioFocus: () async => focusAcquired = true,
      ),
      isFalse,
    );
    expect(focusAcquired, isFalse);
    expect(controller.error, contains('Microphone permission'));
    controller.dispose();
  });
}

class _FakeRecorder implements ShadowingRecorder {
  _FakeRecorder({this.permission = MicrophonePermissionStatus.granted});

  final MicrophonePermissionStatus permission;
  bool active = false;

  @override
  Future<void> cancel() async => active = false;

  @override
  Future<void> openSettings() async {}

  @override
  Future<MicrophonePermissionStatus> permissionStatus() async => permission;

  @override
  Future<MicrophonePermissionStatus> requestPermission() async => permission;

  @override
  Future<void> start() async => active = true;

  @override
  Future<CapturedRecording> stop() async {
    active = false;
    return const CapturedRecording(
      path: '/tmp/shadowing-test.wav',
      durationMs: 880,
      byteLength: 28000,
      contentSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  }
}
