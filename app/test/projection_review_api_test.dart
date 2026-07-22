import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/api_service.dart';

const _evidence = {
  'observation_id': 'observation-1',
  'source_ref': 'attempt-1',
  'task_type': 'speaking_production',
  'outcome': 'success',
  'occurred_at_ms': 10,
  'snapshot': 'make it work',
};

const _proposal = {
  'id': 'proposal-1',
  'lexical_entry_id': 'entry-1',
  'capability': 'speaking',
  'proposed_conclusion': 'acquired',
  'algorithm_version': 'speaking-proposal-v1',
  'confidence': 0.8,
  'evidence_as_of_ms': 10,
  'evidence': [_evidence],
  'rationale': 'two qualified uses',
  'status': 'pending',
  'created_at_ms': 20,
};

void main() {
  test('typed proposal decision sends an explicit confirmation', () async {
    String? requestBody;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        expect(method, 'POST');
        expect(path, '/v1/projections/proposals/proposal-1/decision');
        requestBody = body;
        return (
          statusCode: 200,
          body: jsonEncode({..._proposal, 'status': 'confirmed'}),
        );
      },
    );
    final result = await api.decideProjectionProposal(
      proposalId: 'proposal-1',
      decision: 'confirm',
    );
    expect(jsonDecode(requestBody!)['decision'], 'confirm');
    expect(result.status, 'confirmed');
    expect(result.evidence.single.sourceRef, 'attempt-1');
  });

  test(
    'cross-modal response preserves unassessed and source snapshot',
    () async {
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async => (
          statusCode: 200,
          body: jsonEncode([
            {
              'lexical_entry_id': 'entry-1',
              'display_form': 'work',
              'reading': 'acquired',
              'listening': 'acquired',
              'speaking': 'not_acquired',
              'writing': 'unassessed',
              'review_kind': 'constructed_speaking',
              'reason': 'receptive-production gap',
              'source': _evidence,
            },
          ]),
        ),
      );
      final result = await api.crossModalReviewGaps(language: 'en');
      expect(result.single.writing, 'unassessed');
      expect(result.single.source.snapshot, 'make it work');
    },
  );
}
