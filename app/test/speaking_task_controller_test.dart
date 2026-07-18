import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/speaking_task_controller.dart';
import 'package:llplayer_next/models/semantic_task.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';

const _source = SpeakingTaskSource(
  anchorCueId: 'cue-1',
  mediaId: 'media-1',
  trackId: 'track-1',
  startMs: 1000,
  endMs: 9000,
  language: 'en',
  transcriptSnapshot: 'A storm delayed the ferry until Tuesday.',
);

const _points = [
  RubricPointView(
    pointId: 'main-idea',
    importance: 'required',
    statement: 'State the main event.',
  ),
  RubricPointView(
    pointId: 'detail',
    importance: 'required',
    statement: 'Include the timing detail.',
  ),
];

Map<String, dynamic> _rubricJson() => {
  'id': 'rubric-1',
  'purpose': 'l2_retelling',
  'source': {
    'media_id': 'media-1',
    'track_id': 'track-1',
    'start_ms': 1000,
    'end_ms': 9000,
    'language': 'en',
    'transcript_snapshot': _source.transcriptSnapshot,
  },
  'response_language': 'en',
  'points': [for (final point in _points) point.toJson()],
  'version': 1,
  'provenance': {'kind': 'manual'},
  'created_at_ms': 1,
};

Map<String, dynamic> _modelJson({bool englishOnly = true}) => {
  'id': englishOnly ? 'base.en' : 'base',
  'display_name': 'Base',
  'revision': 'r1',
  'size_bytes': 1,
  'quality': 'balanced',
  'english_only': englishOnly,
  'state': 'installed',
  'installed_bytes': 1,
  'license': 'MIT',
};

Map<String, dynamic> _recordingJson() => {
  'id': 'recording-1',
  'file_path': '/tmp/speaking.wav',
  'created_at_ms': 2,
  'duration_ms': 4200,
  'practice_attempt_id': null,
  'target': {
    'kind': 'segment',
    'id': null,
    'sentence_id': null,
    'chunk_id': null,
    'start_ms': 1000,
    'end_ms': 9000,
  },
  'source_segment': {
    'media_id': 'media-1',
    'start_ms': 1000,
    'end_ms': 9000,
    'label': 'retelling source',
    'subtitle_snapshot': _source.transcriptSnapshot,
    'availability': 'available',
  },
  'language': 'en',
  'audio': {
    'container': 'wav',
    'codec': 'pcm_s16le',
    'sample_rate_hz': 16000,
    'channels': 1,
    'sample_format': 's16',
    'byte_length': 44,
    'content_sha256': 'abc',
  },
  'recorder_version': 'macos-avfoundation-pcm16-v1',
};

Map<String, dynamic> _jobJson(String status, {String? transcript}) => {
  'id': 'job-1',
  'recording_asset_id': 'recording-1',
  'status': status,
  'raw_transcript': transcript,
  'segments': <dynamic>[],
  'provenance': {
    'provider_id': 'whisper.cpp',
    'provider_version': '1',
    'runtime_id': 'whisper-cli',
    'runtime_version': '1',
    'model_id': 'base.en',
    'model_revision': 'r1',
    'model_checksum_sha256': 'model-sha',
    'recording_content_sha256': 'abc',
    'requested_language': 'en',
    'detected_language': 'en',
  },
  'error_code': null,
  'error_message': null,
  'created_at_ms': 2,
  'started_at_ms': 3,
  'completed_at_ms': status == 'completed' ? 4 : null,
  'latency_ms': status == 'completed' ? 100 : null,
};

Map<String, dynamic> _attemptJson(String corrected) => {
  'id': 'attempt-1',
  'kind': 'l2_retelling',
  'rubric_id': 'rubric-1',
  'rubric_version': 1,
  'conditions': {
    'source_text_visible': false,
    'audio_play_count': 1,
    'notes_allowed': false,
    'speaking_assistance': null,
    'speaking_recall': 'immediate',
    'prompt_snapshot': null,
  },
  'responses': [
    {
      'revision': 1,
      'raw_transcript': 'The storm delayed the fairy to Tuesday.',
      'transcript': corrected,
      'source': 'asr',
      'recording_asset_id': 'recording-1',
      'asr_reliability': 'suspect',
      'language': 'en',
      'recorded_at_ms': 10,
    },
  ],
  'status': 'completed',
  'started_at_ms': 5,
  'ended_at_ms': 10,
};

Map<String, dynamic> _reviewItemJson() => {
  'id': 'review-speaking-1',
  'source': {
    'kind': 'speaking_attempt',
    'id': 'attempt-1',
    'practice_attempt_id': null,
    'lexical_entry_id': null,
    'media_id': 'media-1',
    'track_id': 'track-1',
  },
  'anchors': <dynamic>[],
  'prompt_snapshot': _source.transcriptSnapshot,
  'status': 'active',
  'created_at_ms': 21,
  'updated_at_ms': 21,
};

Map<String, dynamic> _providerJson({
  List<String> allowedUses = const ['semantic_judgment'],
}) => {
  'id': 'prov-1',
  'display_name': 'Test',
  'adapter_kind': 'openai_chat_completions',
  'base_url': 'http://x',
  'model_id': 'm',
  'has_credential': true,
  'timeout_ms': 30000,
  'max_retries': 0,
  'retention': 'unknown',
  'allowed_uses': allowedUses,
  'capability': <String, dynamic>{},
  'created_at_ms': 1,
};

Map<String, dynamic> _llmJudgmentJson() => {
  'id': 'llm-judgment-1',
  'attempt_id': 'attempt-1',
  'response_revision': 1,
  'rubric_id': 'rubric-1',
  'rubric_version': 1,
  'rubric_source_sha256': 'h1',
  'response_transcript_sha256': 'h2',
  'points': [
    {'point_id': 'main-idea', 'verdict': 'covered'},
    {'point_id': 'detail', 'verdict': 'missing'},
  ],
  'abstain': null,
  'provenance': {'kind': 'llm', 'model_id': 'm'},
  'evidence_class': 'heuristic_proxy',
  'created_at_ms': 25,
};

class _FakeBackend {
  final requests = <(String, String, Map<String, dynamic>?)>[];
  List<Map<String, dynamic>> providers = [];

  LocalApi get api => LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'tok',
    transport: (method, path, body) async {
      final decoded = body == null
          ? null
          : jsonDecode(body) as Map<String, dynamic>;
      requests.add((method, path, decoded));
      final response = switch ((method, path)) {
        ('GET', final p) when p.startsWith('/v1/semantic/rubrics/lookup') =>
          null,
        ('POST', '/v1/semantic/rubrics') => _rubricJson(),
        ('GET', '/v1/transcription/models') => [_modelJson()],
        ('POST', '/v1/recordings') => _recordingJson(),
        ('GET', '/v1/recordings/recording-1/audio-facts') => {
          'recording_id': 'recording-1',
          'duration_ms': 4200,
          'pauses': [
            {'start_ms': 1000, 'end_ms': 1400},
          ],
          'waveform': {
            'duration_ms': 4200,
            'bucket_ms': 100,
            'peaks': [0.5],
            'rms': [0.2],
          },
        },
        ('POST', '/v1/recording-transcriptions') => _jobJson('queued'),
        ('GET', '/v1/recording-transcriptions/job-1') => _jobJson(
          'completed',
          transcript: 'The storm delayed the fairy to Tuesday.',
        ),
        ('POST', '/v1/semantic/attempts') => _attemptJson(
          decoded!['responses'][0]['transcript'] as String,
        ),
        ('POST', '/v1/review/items') => _reviewItemJson(),
        ('POST', '/v1/semantic/attempts/attempt-1/speaking-targets') => null,
        ('GET', '/v1/llm/providers') => providers,
        ('POST', '/v1/llm/providers/prov-1/judge') => _llmJudgmentJson(),
        ('POST', '/v1/semantic/adjudications') => {
          'id': 'adjudication-1',
          'judgment_id': decoded!['judgment_id'],
          'point_id': decoded['point_id'],
          'prior_verdict': decoded['prior_verdict'],
          'user_verdict': decoded['user_verdict'],
          'note': decoded['note'],
          'occurred_at_ms': 22,
        },
        ('POST', '/v1/semantic/judgments') => {
          'id': 'judgment-1',
          'attempt_id': 'attempt-1',
          'response_revision': 1,
          'rubric_id': 'rubric-1',
          'rubric_version': 1,
          'rubric_source_sha256': 'h1',
          'response_transcript_sha256': 'h2',
          'points': [
            {'point_id': 'main-idea', 'verdict': 'covered'},
            {'point_id': 'detail', 'verdict': 'partial'},
          ],
          'abstain': null,
          'provenance': {'kind': 'manual'},
          'evidence_class': 'self_assessment',
          'created_at_ms': 20,
        },
        _ => throw StateError('Unexpected request: $method $path'),
      };
      return (statusCode: 200, body: jsonEncode(response));
    },
  );
}

class _FakeRecorder implements ShadowingRecorder {
  _FakeRecorder(this.permission);

  MicrophonePermissionStatus permission;
  bool requested = false;
  bool started = false;
  bool cancelled = false;

  @override
  Future<MicrophonePermissionStatus> permissionStatus() async => permission;

  @override
  Future<MicrophonePermissionStatus> requestPermission() async {
    requested = true;
    return permission = MicrophonePermissionStatus.granted;
  }

  @override
  Future<void> start() async => started = true;

  @override
  Future<CapturedRecording> stop() async => const CapturedRecording(
    path: '/tmp/speaking.wav',
    durationMs: 4200,
    byteLength: 44,
    contentSha256: 'abc',
  );

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> openSettings() async {}
}

void main() {
  test('permission rejection happens before audio focus handoff', () async {
    final backend = _FakeBackend();
    final recorder = _FakeRecorder(MicrophonePermissionStatus.denied);
    final controller = SpeakingTaskController(recorder: recorder);
    await controller.openTask(
      backend.api,
      source: _source,
      fixedRubricPoints: _points,
    );
    var focusAcquired = false;
    final started = await controller.beginRecording(
      acquireAudioFocus: () async => focusAcquired = true,
    );

    expect(started, isFalse);
    expect(focusAcquired, isFalse);
    expect(recorder.started, isFalse);
    expect(controller.state.phase, 'listening');
  });

  test(
    'record, transcribe, correct, then explicitly request self-assessment',
    () async {
      final backend = _FakeBackend();
      final recorder = _FakeRecorder(MicrophonePermissionStatus.granted);
      final controller = SpeakingTaskController(
        recorder: recorder,
        delay: (_) async {},
      );
      await controller.openTask(
        backend.api,
        source: _source,
        fixedRubricPoints: _points,
      );
      controller.noteSourcePlayback();
      var focusAcquired = false;
      expect(
        await controller.beginRecording(
          acquireAudioFocus: () async => focusAcquired = true,
        ),
        isTrue,
      );
      expect(focusAcquired, isTrue);
      expect(controller.state.phase, 'recording');

      await controller.stopRecording(backend.api);
      expect(controller.state.phase, 'reviewing');
      expect(controller.state.audioFacts?.pauses, hasLength(1));
      expect(controller.state.audioFacts?.totalPauseMs, 400);
      expect(
        controller.state.rawTranscript,
        'The storm delayed the fairy to Tuesday.',
      );
      final requestCountBeforeClose = backend.requests.length;
      await controller.closeTask();
      expect(controller.state.phase, 'idle');
      await controller.openTask(
        backend.api,
        source: _source,
        fixedRubricPoints: _points,
      );
      expect(controller.state.phase, 'reviewing');
      expect(backend.requests, hasLength(requestCountBeforeClose));
      controller.updateCorrectedTranscript(
        'The storm delayed the ferry until Tuesday.',
      );
      controller.setAsrReliability('suspect');
      await controller.acceptTranscript(backend.api);

      expect(controller.state.phase, 'ready_feedback');
      expect(controller.state.feedbackRequested, isFalse);
      final attemptBody = backend.requests
          .firstWhere((request) => request.$2 == '/v1/semantic/attempts')
          .$3!;
      final response = attemptBody['responses'][0] as Map<String, dynamic>;
      expect(
        response['raw_transcript'],
        'The storm delayed the fairy to Tuesday.',
      );
      expect(
        response['transcript'],
        'The storm delayed the ferry until Tuesday.',
      );
      expect(response['asr_reliability'], 'suspect');

      controller.requestFeedback();
      expect(controller.state.phase, 'assessing');
      expect(controller.state.feedbackRequested, isTrue);
      controller.setVerdict('main-idea', 'covered');
      controller.setVerdict('detail', 'partial');
      await controller.submitSelfAssessment(backend.api);
      expect(controller.state.phase, 'done');
      expect(controller.state.canRetry, isTrue);

      await controller.confirmSpeakingTarget(
        backend.api,
        lexicalEntryId: 'lexical-until-tuesday',
        surfaceForm: 'until Tuesday',
      );
      expect(
        controller.state.confirmedTargetIds,
        contains('lexical-until-tuesday'),
      );

      await controller.adjudicate(
        backend.api,
        pointId: 'detail',
        userVerdict: 'covered',
      );
      expect(controller.state.effectiveVerdict('detail'), 'covered');
      final adjudicationBody = backend.requests
          .firstWhere((request) => request.$2 == '/v1/semantic/adjudications')
          .$3!;
      expect(adjudicationBody['prior_verdict'], 'partial');
      expect(adjudicationBody['user_verdict'], 'covered');

      await controller.scheduleDelayedRetelling(backend.api);
      expect(controller.state.delayedReviewItemId, 'review-speaking-1');
      final reviewBody = backend.requests
          .firstWhere((request) => request.$2 == '/v1/review/items')
          .$3!;
      expect(reviewBody['source']['kind'], 'speaking_attempt');
      expect(reviewBody['source']['id'], 'attempt-1');
      expect(reviewBody['prompt_snapshot'], _source.transcriptSnapshot);

      controller.retryOnce();
      expect(controller.state.phase, 'listening');
      expect(controller.state.retryCount, 1);
      expect(controller.state.rawTranscript, isEmpty);
      expect(controller.state.canRetry, isFalse);
    },
  );

  test(
    'role reply requires an honest prompt and assistance snapshot',
    () async {
      final controller = SpeakingTaskController(
        recorder: _FakeRecorder(MicrophonePermissionStatus.granted),
      );
      expect(
        () => controller.openTask(
          _FakeBackend().api,
          source: _source,
          fixedRubricPoints: _points,
          kind: SpeakingTaskController.roleReplyKind,
          assistance: 'keywords',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'personal pattern uses the speaking resident with explicit assistance',
    () async {
      final backend = _FakeBackend();
      final controller = SpeakingTaskController(
        recorder: _FakeRecorder(MicrophonePermissionStatus.granted),
      );
      await controller.openTask(
        backend.api,
        source: const SpeakingTaskSource(
          anchorCueId: 'pattern-1',
          startMs: 0,
          endMs: 1,
          language: 'en',
          transcriptSnapshot: 'I ended up fixing it.',
          promptSnapshot: 'I ended up {result}.',
        ),
        fixedRubricPoints: _points,
        kind: SpeakingTaskController.patternProductionKind,
        assistance: 'no_text',
      );
      final request = backend.requests.firstWhere(
        (value) => value.$2 == '/v1/semantic/rubrics',
      );
      expect(request.$3!['purpose'], 'pattern_production');
      expect(controller.state.assistance, 'no_text');
    },
  );

  test(
    'LLM assist: judge spoken attempt, correct it, stays honest heuristic',
    () async {
      final backend = _FakeBackend()..providers = [_providerJson()];
      final controller = SpeakingTaskController(
        recorder: _FakeRecorder(MicrophonePermissionStatus.granted),
        delay: (_) async {},
      );
      await controller.openTask(
        backend.api,
        source: _source,
        fixedRubricPoints: _points,
      );
      await controller.beginRecording(acquireAudioFocus: () async {});
      await controller.stopRecording(backend.api);
      await controller.acceptTranscript(backend.api);
      // A judgment-capable provider was discovered, but nothing is judged yet.
      expect(controller.state.phase, 'ready_feedback');
      expect(controller.state.judgeProviderId, 'prov-1');
      expect(controller.state.llmJudgment, isNull);

      await controller.requestLlmJudgment(backend.api);
      final judgment = controller.state.llmJudgment!;
      expect(judgment.id, 'llm-judgment-1');
      // Never gold: an unqualified provider verdict stays a heuristic proxy,
      // and it does not touch the manual self-assessment slot.
      expect(judgment.evidenceClass, 'heuristic_proxy');
      expect(judgment.provenance.kind, 'llm');
      expect(controller.state.judgment, isNull);

      // The judge request cites the stored attempt + revision.
      final judgeBody = backend.requests
          .firstWhere((r) => r.$2 == '/v1/llm/providers/prov-1/judge')
          .$3!;
      expect(judgeBody['attempt_id'], 'attempt-1');
      expect(judgeBody['response_revision'], 1);

      // Correcting the LLM verdict appends an adjudication citing the LLM row.
      await controller.adjudicateLlm(
        backend.api,
        pointId: 'detail',
        userVerdict: 'partial',
      );
      expect(controller.state.llmAdjudications, hasLength(1));
      final adjBody = backend.requests
          .firstWhere((r) => r.$2 == '/v1/semantic/adjudications')
          .$3!;
      expect(adjBody['judgment_id'], 'llm-judgment-1');
      expect(adjBody['prior_verdict'], 'missing');
      expect(adjBody['user_verdict'], 'partial');
    },
  );

  test('LLM assist stays hidden without a judgment-capable provider', () async {
    final backend = _FakeBackend()
      ..providers = [
        _providerJson(allowedUses: ['rubric_generation']),
      ];
    final controller = SpeakingTaskController(
      recorder: _FakeRecorder(MicrophonePermissionStatus.granted),
      delay: (_) async {},
    );
    await controller.openTask(
      backend.api,
      source: _source,
      fixedRubricPoints: _points,
    );
    await controller.beginRecording(acquireAudioFocus: () async {});
    await controller.stopRecording(backend.api);
    await controller.acceptTranscript(backend.api);
    expect(controller.state.phase, 'ready_feedback');
    expect(controller.state.judgeProviderId, isNull);
    // Requesting without a provider is a no-op; no judge call is recorded.
    await controller.requestLlmJudgment(backend.api);
    expect(controller.state.llmJudgment, isNull);
    expect(backend.requests.where((r) => r.$2.endsWith('/judge')), isEmpty);
  });

  test('future-stage intents cannot skip recording and review', () async {
    final backend = _FakeBackend();
    final controller = SpeakingTaskController(
      recorder: _FakeRecorder(MicrophonePermissionStatus.granted),
    );
    await controller.openTask(
      backend.api,
      source: _source,
      fixedRubricPoints: _points,
    );
    await controller.acceptTranscript(backend.api);
    controller.requestFeedback();
    controller.setVerdict('main-idea', 'covered');
    await controller.submitSelfAssessment(backend.api);

    expect(controller.state.phase, 'listening');
    expect(
      backend.requests.where(
        (request) => request.$2 == '/v1/semantic/attempts',
      ),
      isEmpty,
    );
  });
}
