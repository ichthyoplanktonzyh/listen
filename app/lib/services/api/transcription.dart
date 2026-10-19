part of '../api_service.dart';

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
  }) async => RecordingTranscriptionJobView.fromJson(
    (await _request('POST', '/v1/recording-transcriptions', {
          'recording_id': recordingId,
          'model_id': modelId,
          'language': language,
        }))
        as Map<String, dynamic>,
  );

  Future<RecordingTranscriptionJobView> recordingTranscriptionJob(
    String jobId,
  ) async => RecordingTranscriptionJobView.fromJson(
    (await _request(
          'GET',
          '/v1/recording-transcriptions/${Uri.encodeComponent(jobId)}',
        ))
        as Map<String, dynamic>,
  );

  Future<RecordingTranscriptionJobView> cancelRecordingTranscription(
    String jobId,
  ) async => RecordingTranscriptionJobView.fromJson(
    (await _request(
          'POST',
          '/v1/recording-transcriptions/${Uri.encodeComponent(jobId)}/cancel',
        ))
        as Map<String, dynamic>,
  );
}
