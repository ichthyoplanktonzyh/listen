import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/services/api_service.dart';

/// Characterizes the graceful-degradation logic of `loadTimelineResource`:
/// each of the four sub-resources is loaded independently, only a total failure
/// is reported as unavailable, and partial failures degrade to a warning.
/// Reachable as unit tests only because of the A1 transport seam.
void main() {
  group('SpeechEnhancementWorkflowController.loadTimelineResource', () {
    test('reports unavailable when all four sub-resources fail', () async {
      final controller = SpeechEnhancementWorkflowController();
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async =>
            (statusCode: 500, body: 'boom'),
      );

      final result = await controller.loadTimelineResource(
        service: api,
        trackId: 't1',
        previous: const ExistingTimelineResourceState(),
      );

      expect(result.unavailable, isTrue);
      expect(result.error, contains('Timeline resource unavailable'));
      expect(result.wordSummaries, isEmpty);
      expect(result.phoneSummaries, isEmpty);
      expect(result.chunkSummaries, isEmpty);
    });

    test('degrades to a warning when only some sub-resources fail', () async {
      final controller = SpeechEnhancementWorkflowController();
      // Summaries decode as empty lists (200 `[]`); the LLTimeline export
      // decode fails, so exactly one sub-resource errors.
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async => (statusCode: 200, body: '[]'),
      );

      final result = await controller.loadTimelineResource(
        service: api,
        trackId: 't1',
        previous: const ExistingTimelineResourceState(),
      );

      expect(result.unavailable, isFalse);
      expect(result.wordSummaries, isEmpty);
      expect(result.error, isNotNull);
      expect(result.error, contains('warning'));
    });
  });
}
