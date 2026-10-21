import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The listening transcript is produced from AV media through Gen's material
/// capability flow. AI conversation can still transcribe short learner turns;
/// whole-media transcription remains retired.
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
    'whole-media transcription stays retired while AI turn transcription remains',
    () {
      for (final path in [
        'lib/screens/transcription_center_screen.dart',
        'lib/widgets/flows/whole_media_transcription_dialog.dart',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: '$path is retired');
      }

      final api = File(
        'lib/services/api/transcription.dart',
      ).readAsStringSync();
      expect(api, contains('/v1/recording-transcriptions'));
      expect(api, isNot(contains('/v1/transcription/jobs')));

      final realtimeApi = File(
        'lib/services/api/realtime.dart',
      ).readAsStringSync();
      for (final route in [
        '/v1/realtime/providers',
        '/v1/realtime/sessions',
        '/v1/recordings',
      ]) {
        expect(realtimeApi, contains(route));
      }
    },
  );
}
