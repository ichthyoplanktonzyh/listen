class ProjectionEvidenceRefView {
  const ProjectionEvidenceRefView({
    required this.observationId,
    this.sourceRef,
    required this.taskType,
    required this.outcome,
    required this.occurredAtMs,
    required this.snapshot,
  });

  factory ProjectionEvidenceRefView.fromJson(Map<String, dynamic> json) =>
      ProjectionEvidenceRefView(
        observationId: json['observation_id'] as String,
        sourceRef: json['source_ref'] as String?,
        taskType: json['task_type'] as String,
        outcome: json['outcome'] as String,
        occurredAtMs: json['occurred_at_ms'] as int,
        snapshot: json['snapshot'] as String,
      );

  final String observationId;
  final String? sourceRef;
  final String taskType;
  final String outcome;
  final int occurredAtMs;
  final String snapshot;
}

class ProjectionProposalView {
  const ProjectionProposalView({
    required this.id,
    required this.lexicalEntryId,
    required this.capability,
    required this.proposedConclusion,
    required this.algorithmVersion,
    required this.evidence,
    required this.rationale,
    required this.status,
  });

  factory ProjectionProposalView.fromJson(
    Map<String, dynamic> json,
  ) => ProjectionProposalView(
    id: json['id'] as String,
    lexicalEntryId: json['lexical_entry_id'] as String,
    capability: json['capability'] as String,
    proposedConclusion: json['proposed_conclusion'] as String,
    algorithmVersion: json['algorithm_version'] as String,
    evidence: (json['evidence'] as List<dynamic>)
        .map(
          (value) =>
              ProjectionEvidenceRefView.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    rationale: json['rationale'] as String,
    status: json['status'] as String,
  );

  final String id;
  final String lexicalEntryId;
  final String capability;
  final String proposedConclusion;
  final String algorithmVersion;
  final List<ProjectionEvidenceRefView> evidence;
  final String rationale;
  final String status;
}

class CrossModalReviewCandidateView {
  const CrossModalReviewCandidateView({
    required this.lexicalEntryId,
    required this.displayForm,
    required this.reading,
    required this.listening,
    required this.speaking,
    required this.writing,
    required this.reviewKind,
    required this.reason,
    required this.source,
  });

  factory CrossModalReviewCandidateView.fromJson(Map<String, dynamic> json) =>
      CrossModalReviewCandidateView(
        lexicalEntryId: json['lexical_entry_id'] as String,
        displayForm: json['display_form'] as String,
        reading: json['reading'] as String,
        listening: json['listening'] as String,
        speaking: json['speaking'] as String,
        writing: json['writing'] as String,
        reviewKind: json['review_kind'] as String,
        reason: json['reason'] as String,
        source: ProjectionEvidenceRefView.fromJson(
          json['source'] as Map<String, dynamic>,
        ),
      );

  final String lexicalEntryId;
  final String displayForm;
  final String reading;
  final String listening;
  final String speaking;
  final String writing;
  final String reviewKind;
  final String reason;
  final ProjectionEvidenceRefView source;
}
