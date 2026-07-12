import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/coach_dashboard_controller.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test(
    'loads channel-ready coach envelope through the transport seam',
    () async {
      final requestedPaths = <String>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'test',
        transport: (method, path, body) async {
          requestedPaths.add(path);
          if (method == 'POST') return (statusCode: 200, body: '{}');
          if (path.startsWith('/v1/coach/evidence')) {
            return (
              statusCode: 200,
              body: jsonEncode([
                {'id': 'attempt-1', 'occurred_at_ms': 2, 'result': 'correct'},
              ]),
            );
          }
          return (
            statusCode: 200,
            body: jsonEncode({
              'period_start_ms': 1,
              'period_end_ms': 2,
              'generated_at_ms': 2,
              'channels': [
                {
                  'channel': 'listening',
                  'status': 'available',
                  'metrics': [
                    {
                      'key': 'practice_attempts',
                      'value': 4,
                      'source': 'practice_attempts',
                    },
                  ],
                },
                {
                  'channel': 'reading',
                  'status': 'unassessed',
                  'unavailable_reason': 'no_active_validation',
                  'metrics': [],
                },
              ],
              'suggestions': [
                {
                  'kind': 'due_review',
                  'title_key': 'coachSuggestionReview',
                  'reason_key': 'coachSuggestionReviewReason',
                  'action': 'open_review',
                  'evidence_source': 'review_schedules',
                  'evidence_count': 3,
                },
              ],
              'starter_checklist': <String>[],
              'materials': [
                {
                  'media_id': 'media-1',
                  'title': 'Episode 1',
                  'report_count': 2,
                  'first_report': 'got_the_gist',
                  'latest_report': 'understood_all',
                  'reports_understood_all': 1,
                  'reports_got_the_gist': 1,
                  'reports_unclear': 0,
                  'practice_attempts': 2,
                  'practice_correct': 2,
                  'triage_intent': null,
                  'graduation_candidate': true,
                },
              ],
            }),
          );
        },
      );
      final controller = CoachDashboardController();
      addTearDown(controller.dispose);
      await controller.load(api);
      expect(requestedPaths.single, '/v1/coach/dashboard?days=7');
      expect(controller.state.dashboard!.channels[1].status, 'unassessed');
      expect(
        controller.state.dashboard!.suggestions.single.evidenceSource,
        'review_schedules',
      );
      expect(
        controller.state.dashboard!.materials.single.graduationCandidate,
        isTrue,
      );
      await api.graduateCoachMaterial('media-1');
      expect(requestedPaths.last, '/v1/coach/materials/media-1/graduate');
      final evidence = await api.coachEvidence('practice_attempts');
      expect(evidence.single.id, 'attempt-1');
    },
  );
}
