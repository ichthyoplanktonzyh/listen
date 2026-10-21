part of '../api_service.dart';

RecordingTranscriptionJobView _recordingTranscriptionFromJson(
  Map<String, dynamic> json,
) {
  final provenance = json['provenance'] as Map<String, dynamic>;
  return RecordingTranscriptionJobView(
    id: json['id'] as String,
    recordingAssetId: json['recording_asset_id'] as String,
    status: json['status'] as String,
    rawTranscript: json['raw_transcript'] as String?,
    segments: (json['segments'] as List<dynamic>)
        .map((value) {
          final segment = value as Map<String, dynamic>;
          return RecordingTranscriptSegment(
            startMs: (segment['start_ms'] as num).toInt(),
            endMs: (segment['end_ms'] as num).toInt(),
            text: segment['text'] as String,
          );
        })
        .toList(growable: false),
    provenance: RecordingTranscriptProvenanceView(
      providerId: provenance['provider_id'] as String,
      providerVersion: provenance['provider_version'] as String,
      runtimeId: provenance['runtime_id'] as String,
      runtimeVersion: provenance['runtime_version'] as String,
      modelId: provenance['model_id'] as String,
      modelRevision: provenance['model_revision'] as String,
      modelChecksumSha256: provenance['model_checksum_sha256'] as String,
      recordingContentSha256: provenance['recording_content_sha256'] as String,
      requestedLanguage: provenance['requested_language'] as String?,
      detectedLanguage: provenance['detected_language'] as String?,
    ),
    errorCode: json['error_code'] as String?,
    errorMessage: json['error_message'] as String?,
    createdAtMs: (json['created_at_ms'] as num).toInt(),
    startedAtMs: (json['started_at_ms'] as num?)?.toInt(),
    completedAtMs: (json['completed_at_ms'] as num?)?.toInt(),
    latencyMs: (json['latency_ms'] as num?)?.toInt(),
  );
}

// Transcription providers, models, and learner recording/realtime jobs.
// Whole-media transcription jobs are gone: the app prepares transcripts
// through the pinned listen-gen package journey, never through Core's
// whole-media transcription job surface.
// Split out of api_service.dart (mechanical decomposition).

extension TranscriptionApi on LocalApi {
  Future<List<TranscriptionProviderView>> transcriptionProviders() async =>
      ((await _request('GET', '/v1/transcription/providers')) as List<dynamic>)
          .map(
            (value) => TranscriptionProviderView.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);

  Future<List<TranscriptionModelView>> transcriptionModels() async =>
      ((await _request('GET', '/v1/transcription/models')) as List<dynamic>)
          .map(
            (value) =>
                TranscriptionModelView.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<void> installTranscriptionModel(String modelId) async {
    await _request('POST', '/v1/transcription/models/install', {
      'model_id': modelId,
    });
  }

  Future<TranscriptionModelView> registerCustomTranscriptionModel(
    String path,
  ) async => TranscriptionModelView.fromJson(
    (await _request('POST', '/v1/transcription/models/register-custom', {
          'path': path,
        }))
        as Map<String, dynamic>,
  );

  Future<TranscriptionModelView> cancelTranscriptionModelInstall(
    String modelId,
  ) async => TranscriptionModelView.fromJson(
    (await _request(
          'POST',
          '/v1/transcription/models/${Uri.encodeComponent(modelId)}/cancel-install',
        ))
        as Map<String, dynamic>,
  );

  Future<void> deleteTranscriptionModel(String modelId) async {
    await _request(
      'DELETE',
      '/v1/transcription/models/${Uri.encodeComponent(modelId)}',
    );
  }

  Future<RecordingTranscriptionJobView> createRecordingTranscription({
    required String recordingId,
    required String modelId,
    String? language,
  }) async => _recordingTranscriptionFromJson(
    (await _request('POST', '/v1/recording-transcriptions', {
          'recording_id': recordingId,
          'model_id': modelId,
          'language': language,
        }))
        as Map<String, dynamic>,
  );

  Future<RecordingTranscriptionJobView> recordingTranscriptionJob(
    String jobId,
  ) async => _recordingTranscriptionFromJson(
    (await _request(
          'GET',
          '/v1/recording-transcriptions/${Uri.encodeComponent(jobId)}',
        ))
        as Map<String, dynamic>,
  );

  Future<RecordingTranscriptionJobView> cancelRecordingTranscription(
    String jobId,
  ) async => _recordingTranscriptionFromJson(
    (await _request(
          'POST',
          '/v1/recording-transcriptions/${Uri.encodeComponent(jobId)}/cancel',
        ))
        as Map<String, dynamic>,
  );
}
