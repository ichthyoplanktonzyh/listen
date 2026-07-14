part of '../api_service.dart';

// Transcription providers, models, and jobs.
// Split out of api_service.dart (mechanical decomposition).

extension TranscriptionApi on LocalApi {
  Future<List<Map<String, dynamic>>> transcriptionProviders() async =>
      ((await _request('GET', '/v1/transcription/providers')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> transcriptionModels() async =>
      ((await _request('GET', '/v1/transcription/models')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<void> installTranscriptionModel(String modelId) async {
    await _request('POST', '/v1/transcription/models/install', {
      'model_id': modelId,
    });
  }

  Future<Map<String, dynamic>> registerCustomTranscriptionModel(
    String path,
  ) async =>
      (await _request('POST', '/v1/transcription/models/register-custom', {
            'path': path,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> cancelTranscriptionModelInstall(
    String modelId,
  ) async =>
      (await _request(
            'POST',
            '/v1/transcription/models/${Uri.encodeComponent(modelId)}/cancel-install',
          ))
          as Map<String, dynamic>;

  Future<void> deleteTranscriptionModel(String modelId) async {
    await _request(
      'DELETE',
      '/v1/transcription/models/${Uri.encodeComponent(modelId)}',
    );
  }

  Future<List<Map<String, dynamic>>> transcriptionJobs() async =>
      ((await _request('GET', '/v1/transcription/jobs')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> createTranscriptionJob({
    required String mediaId,
    required String modelId,
    required bool secondary,
    required bool translate,
    String? language,
    int? audioTrack,
    bool force = false,
  }) async =>
      (await _request('POST', '/v1/transcription/jobs', {
            'media_id': mediaId,
            'model_id': modelId,
            'destination': secondary ? 'secondary' : 'primary',
            'purpose': translate ? 'translate_to_english' : 'transcribe',
            'language': language,
            'audio_track': audioTrack,
            'force': force,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> cancelTranscriptionJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/transcription/jobs/${Uri.encodeComponent(jobId)}/cancel',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> retryTranscriptionJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/transcription/jobs/${Uri.encodeComponent(jobId)}/retry',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> archiveTranscriptionJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/transcription/jobs/${Uri.encodeComponent(jobId)}/archive',
          ))
          as Map<String, dynamic>;
}
