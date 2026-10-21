import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  test('coach, fit, hunting, and status review APIs keep listening scope', () async {
    final seen = <({String method, String path, Object? body})>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        seen.add((
          method: method,
          path: path,
          body: body == null ? null : jsonDecode(body),
        ));
        final response = switch (path) {
          '/v1/coach/dashboard?days=14' => _dashboard,
          '/v1/coach/evidence?metric=review_success&days=7&limit=5&offset=0' =>
            [_evidence],
          '/v1/coach/materials/media%2F1/graduate' => _mediaLibraryEntry,
          '/v1/content-fit/calibration-samples?language=en' => [_sample],
          '/v1/subtitles/track%2F1/content-fit' => _contentFit,
          '/v1/hunting/candidates?status=active&limit=100&offset=0' => [
            _candidate,
          ],
          '/v1/hunting/targets' => _huntingTarget,
          '/v1/review/upgrade-suggestions?lexical_entry_id=lexical-1&status=pending&limit=100&offset=0' =>
            [_upgrade],
          '/v1/review/upgrade-suggestions/history?lexical_entry_id=lexical-1&limit=100&offset=0' =>
            [_upgradeResolved],
          '/v1/review/upgrade-suggestions/suggestion%2F1/confirm' =>
            _upgradeResolved,
          '/v1/review/upgrade-suggestions/suggestion%2F1/reject' =>
            _upgradeResolved,
          '/v1/projections/entries/lexical%2F1' => [
            _proposalListening,
            _proposalSpeaking,
          ],
          '/v1/projections/proposals/proposal%2F1/decision' =>
            _proposalResolved,
          _ => throw StateError('unexpected $method $path'),
        };
        return (statusCode: 200, body: jsonEncode(response));
      },
    );

    final dashboard = await api.coachDashboard(days: 14);
    expect(dashboard.listeningMetrics.single.key, 'review_success');
    expect(dashboard.suggestions, hasLength(1));
    expect(dashboard.suggestions.single.destination.kind, 'review_queue');
    expect(dashboard.materials.single.practiceAttempts, 3);
    expect(
      await api.coachEvidence(metric: 'review_success', days: 7, limit: 5),
      hasLength(1),
    );
    expect((await api.graduateCoachMaterial('media/1')).fit, isNull);
    expect(
      await api.contentFitCalibrationSamples(language: 'en'),
      hasLength(1),
    );
    expect((await api.trackContentFit('track/1')).sound.fit, 'challenging');
    expect((await api.huntingCandidates()).single.id, 'candidate-1');
    await api.createHuntingTarget(
      lexicalEntryId: 'lexical-1',
      sourceKind: 'review_candidate',
      sourceId: 'candidate-1',
    );
    expect(
      await api.upgradeSuggestions(lexicalEntryId: 'lexical-1'),
      hasLength(1),
    );
    expect(
      await api.upgradeSuggestionHistory(lexicalEntryId: 'lexical-1'),
      hasLength(1),
    );
    await api.confirmUpgradeSuggestion('suggestion/1');
    await api.rejectUpgradeSuggestion('suggestion/1');
    final proposals = await api.projectionProposals('lexical/1');
    expect(proposals, hasLength(1));
    expect(proposals.single.capability, 'listening');
    await api.decideProjectionProposal(
      proposalId: 'proposal/1',
      decision: 'confirm',
    );

    expect(seen.map((request) => '${request.method} ${request.path}'), [
      'GET /v1/coach/dashboard?days=14',
      'GET /v1/coach/evidence?metric=review_success&days=7&limit=5&offset=0',
      'POST /v1/coach/materials/media%2F1/graduate',
      'GET /v1/content-fit/calibration-samples?language=en',
      'GET /v1/subtitles/track%2F1/content-fit',
      'GET /v1/hunting/candidates?status=active&limit=100&offset=0',
      'POST /v1/hunting/targets',
      'GET /v1/review/upgrade-suggestions?lexical_entry_id=lexical-1&status=pending&limit=100&offset=0',
      'GET /v1/review/upgrade-suggestions/history?lexical_entry_id=lexical-1&limit=100&offset=0',
      'POST /v1/review/upgrade-suggestions/suggestion%2F1/confirm',
      'POST /v1/review/upgrade-suggestions/suggestion%2F1/reject',
      'GET /v1/projections/entries/lexical%2F1',
      'POST /v1/projections/proposals/proposal%2F1/decision',
    ]);
    expect(seen[2].body, <String, dynamic>{});
    expect(seen[6].body, {
      'lexical_entry_id': 'lexical-1',
      'source_kind': 'review_candidate',
      'source_id': 'candidate-1',
    });
    expect(seen[12].body, {'decision': 'confirm', 'note': null});
  });
}

const _dashboard = <String, dynamic>{
  'period_start_ms': 0,
  'period_end_ms': 604800000,
  'generated_at_ms': 9,
  'listening_metrics': [
    {
      'key': 'review_success',
      'value': 2,
      'source': 'review_attempts',
      'authority_layer': 'core',
    },
  ],
  'suggestions': [
    {
      'id': 'next-review',
      'kind': 'review_due',
      'title_key': 'coachNextReview',
      'reason_key': 'coachEvidenceCount',
      'destination': {'kind': 'review_queue'},
      'evidence_source': 'fsrs',
      'evidence_count': 1,
    },
    {
      'id': 'unsupported-writing',
      'kind': 'writing',
      'title_key': 'writing',
      'reason_key': 'coachEvidenceCount',
      'destination': {'kind': 'writing'},
      'evidence_source': 'writing',
      'evidence_count': 1,
    },
  ],
  'starter_checklist': <String>[],
  'materials': [
    {
      'media_id': 'media-1',
      'title': 'Listening material',
      'report_count': 2,
      'first_report': 'got_the_gist',
      'latest_report': 'understood_all',
      'reports_understood_all': 1,
      'reports_got_the_gist': 1,
      'reports_unclear': 0,
      'practice_attempts': 3,
      'practice_correct': 2,
      'triage_intent': 'pin_extensive',
      'graduation_candidate': true,
      'recommended_intent': 'pin_intensive',
    },
  ],
};

const _evidence = <String, dynamic>{
  'id': 'evidence-1',
  'occurred_at_ms': 10,
  'result': 'correct',
  'source_kind': 'review',
  'snapshot': 'audio context',
  'source_available': true,
  'unavailable_reason': null,
};

const _mediaLibraryEntry = <String, dynamic>{
  'media': {
    'id': 'media-1',
    'path': '/media/1.mp3',
    'fingerprint': 'fp-1',
    'title': 'Listening material',
    'kind': 'audio',
    'duration': 1000,
    'availability': 'available',
    'created_at_ms': 1,
    'updated_at_ms': 1,
  },
  'primary_track_id': null,
  'fit': null,
  'triage_intent': 'graduated',
};

const _contentFit = <String, dynamic>{
  'subject_kind': 'media',
  'subject_id': 'media-1',
  'language': 'en',
  'meaning': <String, dynamic>{
    'fit': 'comprehensible',
    'signals': <dynamic>[],
    'score': 0.7,
  },
  'sound': <String, dynamic>{
    'fit': 'challenging',
    'signals': <dynamic>[],
    'score': 0.6,
  },
  'assessed_token_ratio': 0.75,
  'evidence_grade': 'usage_calibrated',
  'algorithm_version': 'v2',
  'computed_at_ms': 100,
  'input_fingerprint': 'fp',
  'feature_snapshot': {'speech_rate': 2.2},
  'feature_coverage': {
    'total_features': 2,
    'available_features': 1,
    'coverage_ratio': 0.5,
    'missing_features': ['lexical_coverage'],
  },
};

const _sample = <String, dynamic>{
  'subject_kind': 'media',
  'subject_id': 'media-1',
  'language': 'en',
  'snapshot': {'speech_rate': 2.2},
  'predicted_meaning_score': 0.6,
  'predicted_sound_score': 0.7,
  'predicted_meaning_band': 'comprehensible',
  'predicted_sound_band': 'challenging',
  'v2_meaning_band': 'comprehensible',
  'v2_sound_band': 'challenging',
  'observed_difficulty': 0.4,
  'reports_understood_all': 1,
  'reports_got_the_gist': 1,
  'reports_unclear': 0,
  'practice_attempts': 3,
  'practice_correct': 2,
  'sampled_at_ms': 10,
};

const _candidate = <String, dynamic>{
  'id': 'candidate-1',
  'lexical_entry_id': 'lexical-1',
  'review_item_id': 'review-item-1',
  'sentence_id': 'sentence-1',
  'media_id': 'media-1',
  'track_id': 'track-1',
  'target_snapshot': 'notice',
  'prompt_snapshot': 'notice',
  'failure_count': 2,
  'status': 'active',
  'created_at_ms': 1,
  'last_failed_at_ms': 2,
};

const _huntingTarget = <String, dynamic>{
  'id': 'target-1',
  'lexical_entry_id': 'lexical-1',
  'source_kind': 'review_candidate',
  'source_id': 'candidate-1',
  'target_snapshot': 'notice',
  'status': 'active',
  'created_at_ms': 1,
  'updated_at_ms': 2,
};

const _upgrade = <String, dynamic>{
  'id': 'suggestion/1',
  'lexical_entry_id': 'lexical-1',
  'lexical_display_form': 'notice',
  'previous_status': null,
  'suggested_status': null,
  'status': 'pending',
  'evidence_context_count': 3,
  'evidence_ids': ['evidence-1'],
  'threshold': 3,
  'evidence_class': 'listening',
  'created_at_ms': 1,
  'resolved_at_ms': null,
  'cooldown_until_ms': null,
  'capability': 'listening',
  'previous_assessment': 'unassessed',
  'suggested_assessment': 'known_recognized',
};

final _upgradeResolved = <String, dynamic>{..._upgrade, 'status': 'accepted'};

const _proposalListening = <String, dynamic>{
  'id': 'proposal/1',
  'lexical_entry_id': 'lexical/1',
  'capability': 'listening',
  'proposed_conclusion': 'acquired',
  'algorithm_version': 'v1',
  'confidence': 0.8,
  'evidence_as_of_ms': 5,
  'evidence': <dynamic>[],
  'rationale': 'listening evidence',
  'status': 'pending',
  'created_at_ms': 6,
};

final _proposalSpeaking = <String, dynamic>{
  ..._proposalListening,
  'id': 'speaking-proposal',
  'capability': 'speaking',
};

final _proposalResolved = <String, dynamic>{
  ..._proposalListening,
  'status': 'confirmed',
};
