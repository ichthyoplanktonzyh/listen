part of '../api_service.dart';

// Transcription providers, models, and jobs.
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

  Future<List<TranscriptionJobView>> transcriptionJobs() async =>
      ((await _request('GET', '/v1/transcription/jobs')) as List<dynamic>)
          .map(
            (value) =>
                TranscriptionJobView.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<TranscriptionJobView> createTranscriptionJob({
    required String mediaId,
    required String modelId,
    required bool secondary,
    required bool translate,
    String? language,
    int? audioTrack,
    bool force = false,
  }) async => TranscriptionJobView.fromJson(
    (await _request('POST', '/v1/transcription/jobs', {
          'media_id': mediaId,
          'model_id': modelId,
          'destination': secondary ? 'secondary' : 'primary',
          'purpose': translate ? 'translate_to_english' : 'transcribe',
          'language': language,
          'audio_track': audioTrack,
          'force': force,
        }))
        as Map<String, dynamic>,
  );

  Future<TranscriptionJobView> cancelTranscriptionJob(String jobId) async =>
      TranscriptionJobView.fromJson(
        (await _request(
              'POST',
              '/v1/transcription/jobs/${Uri.encodeComponent(jobId)}/cancel',
            ))
            as Map<String, dynamic>,
      );

  Future<TranscriptionJobView> retryTranscriptionJob(String jobId) async =>
      TranscriptionJobView.fromJson(
        (await _request(
              'POST',
              '/v1/transcription/jobs/${Uri.encodeComponent(jobId)}/retry',
            ))
            as Map<String, dynamic>,
      );

  Future<TranscriptionJobView> archiveTranscriptionJob(String jobId) async =>
      TranscriptionJobView.fromJson(
        (await _request(
              'POST',
              '/v1/transcription/jobs/${Uri.encodeComponent(jobId)}/archive',
            ))
            as Map<String, dynamic>,
      );
}
