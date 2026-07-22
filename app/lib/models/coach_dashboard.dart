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
  const CoachSuggestionDestination({required this.kind, this.language});

  factory CoachSuggestionDestination.fromJson(Map<String, dynamic> json) =>
      CoachSuggestionDestination(
        kind: json['kind'] as String,
        language: json['language'] as String?,
      );

  final String kind;
  final String? language;
}

class CoachReturnContext {
  const CoachReturnContext({
    required this.days,
    required this.language,
    required this.scrollOffset,
    this.suggestionId,
  });

  final int days;
  final String language;
  final double scrollOffset;
  final String? suggestionId;
}

class CoachSuggestion {
  const CoachSuggestion({
    required this.kind,
    required this.id,
    required this.titleKey,
    required this.reasonKey,
    required this.destination,
    required this.evidenceSource,
    required this.evidenceCount,
  });
  factory CoachSuggestion.fromJson(Map<String, dynamic> json) =>
      CoachSuggestion(
        kind: json['kind'] as String,
        id: json['id'] as String,
        titleKey: json['title_key'] as String,
        reasonKey: json['reason_key'] as String,
        destination: CoachSuggestionDestination.fromJson(
          json['destination'] as Map<String, dynamic>,
        ),
        evidenceSource: json['evidence_source'] as String,
        evidenceCount: json['evidence_count'] as int,
      );
  final String id, kind, titleKey, reasonKey, evidenceSource;
  final CoachSuggestionDestination destination;
  final int evidenceCount;
}

class CoachChannelSummary {
  const CoachChannelSummary({
    required this.channel,
    required this.status,
    required this.metrics,
    required this.effectiveAssessments,
    this.unavailableReason,
  });
  factory CoachChannelSummary.fromJson(Map<String, dynamic> json) =>
      CoachChannelSummary(
        channel: json['channel'] as String,
        status: json['status'] as String,
        unavailableReason: json['unavailable_reason'] as String?,
        metrics: (json['metrics'] as List<dynamic>)
            .map((e) => CoachMetric.fromJson(e as Map<String, dynamic>))
            .toList(),
        effectiveAssessments: CoachAssessmentSummary.fromJson(
          json['effective_assessments'] as Map<String, dynamic>,
        ),
      );
  final String channel, status;
  final String? unavailableReason;
  final List<CoachMetric> metrics;
  final CoachAssessmentSummary effectiveAssessments;
}

class CoachAssessmentSummary {
  const CoachAssessmentSummary({
    required this.acquired,
    required this.notAcquired,
    required this.unassessed,
  });

  factory CoachAssessmentSummary.fromJson(Map<String, dynamic> json) =>
      CoachAssessmentSummary(
        acquired: json['acquired'] as int,
        notAcquired: json['not_acquired'] as int,
        unassessed: json['unassessed'] as int,
      );

  final int acquired;
  final int notAcquired;
  final int unassessed;
}

class CoachDashboard {
  const CoachDashboard({
    required this.channels,
    required this.suggestions,
    required this.starterChecklist,
    required this.materials,
    required this.periodStartMs,
    required this.periodEndMs,
    required this.generatedAtMs,
    required this.features,
  });
  factory CoachDashboard.fromJson(Map<String, dynamic> json) => CoachDashboard(
    periodStartMs: json['period_start_ms'] as int,
    periodEndMs: json['period_end_ms'] as int,
    generatedAtMs: json['generated_at_ms'] as int,
    channels: (json['channels'] as List<dynamic>)
        .map((e) => CoachChannelSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
    suggestions: (json['suggestions'] as List<dynamic>)
        .map((e) => CoachSuggestion.fromJson(e as Map<String, dynamic>))
        .toList(),
    starterChecklist: (json['starter_checklist'] as List<dynamic>)
        .cast<String>(),
    materials: ((json['materials'] as List<dynamic>?) ?? const [])
        .map((e) => CoachMaterialInsight.fromJson(e as Map<String, dynamic>))
        .toList(),
    features: ((json['features'] as List<dynamic>?) ?? const [])
        .map(
          (e) => CoachFeatureAvailability.fromJson(e as Map<String, dynamic>),
        )
        .toList(),
  );
  final int periodStartMs, periodEndMs, generatedAtMs;
  final List<CoachChannelSummary> channels;
  final List<CoachSuggestion> suggestions;
  final List<String> starterChecklist;
  final List<CoachMaterialInsight> materials;
  final List<CoachFeatureAvailability> features;
}

class CoachFeatureAvailability {
  const CoachFeatureAvailability({
    required this.feature,
    required this.status,
    required this.reason,
  });

  factory CoachFeatureAvailability.fromJson(Map<String, dynamic> json) =>
      CoachFeatureAvailability(
        feature: json['feature'] as String,
        status: json['status'] as String,
        reason: json['reason'] as String,
      );

  final String feature, status, reason;
}

class CoachMaterialInsight {
  const CoachMaterialInsight({
    required this.mediaId,
    required this.title,
    required this.reportCount,
    required this.reportsUnderstoodAll,
    required this.reportsGotTheGist,
    required this.reportsUnclear,
    required this.practiceAttempts,
    required this.practiceCorrect,
    required this.graduationCandidate,
    this.firstReport,
    this.latestReport,
    this.triageIntent,
    this.recommendedIntent,
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
        recommendedIntent: json['recommended_intent'] as String?,
        graduationCandidate: json['graduation_candidate'] as bool,
      );
  final String mediaId, title;
  final int reportCount,
      reportsUnderstoodAll,
      reportsGotTheGist,
      reportsUnclear,
      practiceAttempts,
      practiceCorrect;
  final String? firstReport, latestReport, triageIntent, recommendedIntent;
  final bool graduationCandidate;
}

class CoachEvidenceItem {
  const CoachEvidenceItem({
    required this.id,
    required this.occurredAtMs,
    required this.result,
    required this.sourceKind,
    required this.snapshot,
    required this.sourceAvailable,
    this.unavailableReason,
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
  final String id, result;
  final String sourceKind, snapshot;
  final bool sourceAvailable;
  final String? unavailableReason;
  final int occurredAtMs;
}
