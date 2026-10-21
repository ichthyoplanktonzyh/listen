part of '../api_service.dart';

extension ProjectionReviewApi on LocalApi {
  Future<List<ProjectionProposalView>> projectionProposals(
    String lexicalEntryId,
  ) async {
    final values =
        (await _request(
              'GET',
              '/v1/projections/entries/${Uri.encodeComponent(lexicalEntryId)}',
            ))
            as List<dynamic>;
    return values
        .map(
          (value) => ProjectionProposalView.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .where((proposal) => proposal.isListening)
        .toList(growable: false);
  }

  Future<ProjectionProposalView> decideProjectionProposal({
    required String proposalId,
    required String decision,
    String? note,
  }) async => ProjectionProposalView.fromJson(
    (await _request(
          'POST',
          '/v1/projections/proposals/${Uri.encodeComponent(proposalId)}/decision',
          {'decision': decision, 'note': note},
        ))
        as Map<String, dynamic>,
  );
}
