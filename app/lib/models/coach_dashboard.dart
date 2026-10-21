/// Core's listening-only dashboard projection.
///
/// The model intentionally has no channel map or production/reading fields:
/// only listening facts are part of this parked feature's restored scope.
class CoachDashboard {
  CoachDashboard({
    required this.periodStartMs,
    required this.periodEndMs,
    required this.generatedAtMs,
    required List<CoachMetric> listeningMetrics,
    required List<CoachSuggestion> suggestions,
    required List<String> starterChecklist,
    required List<CoachMaterialInsight> materials,
  }) : listeningMetrics = List.unmodifiable(listeningMetrics),
       suggestions = List.unmodifiable(suggestions),
       starterChecklist = List.unmodifiable(starterChecklist),
       materials = List.unmodifiable(materials);

  factory CoachDashboard.fromJson(Map<String, dynamic> json) => CoachDashboard(
    periodStartMs: json['period_start_ms'] as int,
    periodEndMs: json['period_end_ms'] as int,
    generatedAtMs: json['generated_at_ms'] as int,
    listeningMetrics: (json['listening_metrics'] as List<dynamic>)
        .map(
          (value) =>
              CoachMetric.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(growable: false),
    suggestions: (json['suggestions'] as List<dynamic>)
        .map(
          (value) =>
              CoachSuggestion.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .where((suggestion) => suggestion.destination.isSupported)
        .toList(growable: false),
    starterChecklist: (json['starter_checklist'] as List<dynamic>)
        .cast<String>(),
    materials: (json['materials'] as List<dynamic>)
        .map(
          (value) => CoachMaterialInsight.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false),
  );

  final int periodStartMs;
  final int periodEndMs;
  final int generatedAtMs;
  final List<CoachMetric> listeningMetrics;
  final List<CoachSuggestion> suggestions;
  final List<String> starterChecklist;
  final List<CoachMaterialInsight> materials;
}

class CoachMetric {
  const CoachMetric({
    required this.key,
    required this.value,
    required this.source,
    required this.authorityLayer,
  });

  factory CoachMetric.fromJson(Map<String, dynamic> json) => CoachMetric(
    key: json['key'] as String,
    value: json['value'] as int,
    source: json['source'] as String,
    authorityLayer: json['authority_layer'] as String,
  );

  final String key;
  final int value;
  final String source;
  final String authorityLayer;
}

class CoachSuggestionDestination {
  const CoachSuggestionDestination(this.kind);

  factory CoachSuggestionDestination.fromJson(Map<String, dynamic> json) =>
      CoachSuggestionDestination(json['kind'] as String);

  final String kind;
  bool get isSupported =>
      const {'review_queue', 'hunting_list', 'content_home'}.contains(kind);
}

class CoachSuggestion {
  const CoachSuggestion({
    required this.id,
    required this.kind,
    required this.titleKey,
    required this.reasonKey,
    required this.destination,
    required this.evidenceSource,
    required this.evidenceCount,
  });

  factory CoachSuggestion.fromJson(Map<String, dynamic> json) =>
      CoachSuggestion(
        id: json['id'] as String,
        kind: json['kind'] as String,
        titleKey: json['title_key'] as String,
        reasonKey: json['reason_key'] as String,
        destination: CoachSuggestionDestination.fromJson(
          Map<String, dynamic>.from(json['destination'] as Map),
        ),
        evidenceSource: json['evidence_source'] as String,
        evidenceCount: json['evidence_count'] as int,
      );

  final String id;
  final String kind;
  final String titleKey;
  final String reasonKey;
  final CoachSuggestionDestination destination;
  final String evidenceSource;
  final int evidenceCount;
}

class CoachMaterialInsight {
  const CoachMaterialInsight({
    required this.mediaId,
    required this.title,
    required this.reportCount,
    required this.firstReport,
    required this.latestReport,
    required this.reportsUnderstoodAll,
    required this.reportsGotTheGist,
    required this.reportsUnclear,
    required this.practiceAttempts,
    required this.practiceCorrect,
    required this.triageIntent,
    required this.graduationCandidate,
    required this.recommendedIntent,
  });

  factory CoachMaterialInsight.fromJson(Map<String, dynamic> json) =>
      CoachMaterialInsight(
        mediaId: json['media_id'] as String,
        title: json['title'] as String,
        reportCount: json['report_count'] as int,
        firstReport: json['first_report'] as String?,
        latestReport: json['latest_report'] as String?,
        reportsUnderstoodAll: json['reports_understood_all'] as int,
        reportsGotTheGist: json['reports_got_the_gist'] as int,
        reportsUnclear: json['reports_unclear'] as int,
        practiceAttempts: json['practice_attempts'] as int,
        practiceCorrect: json['practice_correct'] as int,
        triageIntent: json['triage_intent'] as String?,
        graduationCandidate: json['graduation_candidate'] as bool,
        recommendedIntent: json['recommended_intent'] as String?,
      );

  final String mediaId;
  final String title;
  final int reportCount;
  final String? firstReport;
  final String? latestReport;
  final int reportsUnderstoodAll;
  final int reportsGotTheGist;
  final int reportsUnclear;
  final int practiceAttempts;
  final int practiceCorrect;
  final String? triageIntent;
  final bool graduationCandidate;
  final String? recommendedIntent;
}

class CoachEvidenceItem {
  const CoachEvidenceItem({
    required this.id,
    required this.occurredAtMs,
    required this.result,
    required this.sourceKind,
    required this.snapshot,
    required this.sourceAvailable,
    required this.unavailableReason,
  });

  factory CoachEvidenceItem.fromJson(Map<String, dynamic> json) =>
      CoachEvidenceItem(
        id: json['id'] as String,
        occurredAtMs: json['occurred_at_ms'] as int,
        result: json['result'] as String,
        sourceKind: json['source_kind'] as String,
        snapshot: json['snapshot'] as String,
        sourceAvailable: json['source_available'] as bool,
        unavailableReason: json['unavailable_reason'] as String?,
      );

  final String id;
  final int occurredAtMs;
  final String result;
  final String sourceKind;
  final String snapshot;
  final bool sourceAvailable;
  final String? unavailableReason;
}
