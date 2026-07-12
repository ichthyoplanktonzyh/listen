class CoachMetric {
  const CoachMetric({
    required this.key,
    required this.value,
    required this.source,
  });
  factory CoachMetric.fromJson(Map<String, dynamic> json) => CoachMetric(
    key: json['key'] as String,
    value: json['value'] as int,
    source: json['source'] as String,
  );
  final String key;
  final int value;
  final String source;
}

class CoachSuggestion {
  const CoachSuggestion({
    required this.kind,
    required this.titleKey,
    required this.reasonKey,
    required this.action,
    required this.evidenceSource,
    required this.evidenceCount,
  });
  factory CoachSuggestion.fromJson(Map<String, dynamic> json) =>
      CoachSuggestion(
        kind: json['kind'] as String,
        titleKey: json['title_key'] as String,
        reasonKey: json['reason_key'] as String,
        action: json['action'] as String,
        evidenceSource: json['evidence_source'] as String,
        evidenceCount: json['evidence_count'] as int,
      );
  final String kind, titleKey, reasonKey, action, evidenceSource;
  final int evidenceCount;
}

class CoachChannelSummary {
  const CoachChannelSummary({
    required this.channel,
    required this.status,
    required this.metrics,
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
      );
  final String channel, status;
  final String? unavailableReason;
  final List<CoachMetric> metrics;
}

class CoachDashboard {
  const CoachDashboard({
    required this.channels,
    required this.suggestions,
    required this.starterChecklist,
    required this.materials,
  });
  factory CoachDashboard.fromJson(Map<String, dynamic> json) => CoachDashboard(
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
  );
  final List<CoachChannelSummary> channels;
  final List<CoachSuggestion> suggestions;
  final List<String> starterChecklist;
  final List<CoachMaterialInsight> materials;
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
  });
  factory CoachEvidenceItem.fromJson(Map<String, dynamic> json) =>
      CoachEvidenceItem(
        id: json['id'] as String,
        occurredAtMs: json['occurred_at_ms'] as int,
        result: json['result'] as String,
      );
  final String id, result;
  final int occurredAtMs;
}
