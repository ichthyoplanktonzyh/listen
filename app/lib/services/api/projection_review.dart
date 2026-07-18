part of '../api_service.dart';

extension ProjectionReviewApi on LocalApi {
  Future<List<ProjectionProposalView>> auditProjectionEntry(
    String lexicalEntryId,
  ) async {
    final json =
        await _request(
              'POST',
              '/v1/projections/entries/${Uri.encodeComponent(lexicalEntryId)}',
              const {},
            )
            as Map<String, dynamic>;
    return (json['proposals'] as List<dynamic>)
        .map(
          (value) =>
              ProjectionProposalView.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<List<CrossModalReviewCandidateView>> crossModalReviewGaps({
    required String language,
    int limit = 50,
  }) async {
    final query = Uri(
      queryParameters: {'language': language, 'limit': '$limit'},
    ).query;
    return ((await _request('GET', '/v1/review/cross-modal?$query'))
            as List<dynamic>)
        .map(
          (value) => CrossModalReviewCandidateView.fromJson(
            value as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  Future<List<ProjectionProposalView>> projectionProposals(
    String lexicalEntryId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/projections/entries/${Uri.encodeComponent(lexicalEntryId)}',
              ))
              as List<dynamic>)
          .map(
            (value) =>
                ProjectionProposalView.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<ProjectionProposalView> decideProjectionProposal({
    required String proposalId,
    required String decision,
    String? note,
  }) async => ProjectionProposalView.fromJson(
    await _request(
          'POST',
          '/v1/projections/proposals/${Uri.encodeComponent(proposalId)}/decision',
          {'decision': decision, 'note': note},
        )
        as Map<String, dynamic>,
  );
}
