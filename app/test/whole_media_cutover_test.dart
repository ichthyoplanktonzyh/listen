import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The listening transcript is produced from AV media through Gen's material
/// capability flow. Speaking keeps its recording-specific transcription API;
/// conversational/realtime audio remains out of the app.
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

  test(
    'speaking transcription is recording-scoped and realtime stays absent',
    () {
      for (final path in [
        'lib/controllers/realtime_conversation_controller.dart',
        'lib/services/local_realtime_speech_service.dart',
        'lib/services/realtime_audio_bridge.dart',
        'lib/services/realtime_transport_service.dart',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: '$path is retired');
      }

      final api = File('lib/services/api_service.dart').readAsStringSync();
      final transcription = File(
        'lib/services/api/transcription.dart',
      ).readAsStringSync();
      expect(
        File(
          'lib/data/repositories/transcription_repository.dart',
        ).existsSync(),
        isTrue,
      );
      expect(transcription, contains("'/v1/recording-transcriptions'"));
      expect(transcription, contains("'recording_id': recordingId"));
      expect(transcription, contains("'/v1/transcription/models'"));
      expect(api, isNot(contains('/v1/realtime/')));
    },
  );
}
