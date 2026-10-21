import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The listening transcript is produced from AV media through Gen's material
/// capability flow. Independent recording and realtime transcription surfaces
/// were removed with the other non-listening activities.
void main() {
  test('AV transcript preparation uses the material read capability', () {
    final readiness = File(
      'lib/controllers/transcript_readiness_view_model.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(readiness, contains('MaterialCapability.read'));
    expect(readiness, contains('prepareLearningTranscript'));
    expect(main, contains('_generateSubtitles'));
    expect(main, contains('prepareLearningTranscript'));
    expect(main, isNot(contains('generateSubtitlesFlow')));
  });

  test('standalone recording and realtime transcription APIs are gone', () {
    for (final path in [
      'lib/services/api/transcription.dart',
      'lib/data/repositories/transcription_repository.dart',
      'lib/controllers/realtime_transcription_model_controller.dart',
      'lib/controllers/realtime_conversation_controller.dart',
      'lib/services/local_realtime_speech_service.dart',
      'lib/services/realtime_audio_bridge.dart',
      'lib/services/realtime_transport_service.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: '$path is retired');
    }

    final api = File('lib/services/api_service.dart').readAsStringSync();
    for (final route in [
      '/v1/recording-transcriptions',
      '/v1/transcription/providers',
      '/v1/transcription/models',
      '/v1/realtime/providers',
    ]) {
      expect(api, isNot(contains(route)));
    }
  });
}
