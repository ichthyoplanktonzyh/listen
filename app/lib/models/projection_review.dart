/// A durable listening observation referenced by an acquisition proposal.
class ProjectionEvidenceRefView {
  const ProjectionEvidenceRefView({
    required this.observationId,
    required this.sourceRef,
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

/// Core's explainable, explicitly confirmable listening-status proposal.
class ProjectionProposalView {
  ProjectionProposalView({
    required this.id,
    required this.lexicalEntryId,
    required this.capability,
    required this.proposedConclusion,
    required this.algorithmVersion,
    required this.confidence,
    required this.evidenceAsOfMs,
    required List<ProjectionEvidenceRefView> evidence,
    required this.rationale,
    required this.status,
    required this.createdAtMs,
  }) : evidence = List.unmodifiable(evidence);

  factory ProjectionProposalView.fromJson(Map<String, dynamic> json) =>
      ProjectionProposalView(
        id: json['id'] as String,
        lexicalEntryId: json['lexical_entry_id'] as String,
        capability: json['capability'] as String,
        proposedConclusion: json['proposed_conclusion'] as String,
        algorithmVersion: json['algorithm_version'] as String,
        confidence: (json['confidence'] as num?)?.toDouble(),
        evidenceAsOfMs: json['evidence_as_of_ms'] as int,
        evidence: (json['evidence'] as List<dynamic>)
            .map(
              (value) => ProjectionEvidenceRefView.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(growable: false),
        rationale: json['rationale'] as String,
        status: json['status'] as String,
        createdAtMs: json['created_at_ms'] as int,
      );

  final String id;
  final String lexicalEntryId;
  final String capability;
  final String proposedConclusion;
  final String algorithmVersion;
  final double? confidence;
  final int evidenceAsOfMs;
  final List<ProjectionEvidenceRefView> evidence;
  final String rationale;
  final String status;
  final int createdAtMs;

  bool get isListening => capability == 'listening';
  bool get isPending => status == 'pending';
}
