/// Learner-facing facts about one installed Learning Edition (Core 4.0
/// package lifecycle). Contains only what the learner journey needs:
/// identities, title, languages, timestamps, adoption evidence, and
/// capability availability. Manifest, dependency edges, source paths,
/// payloads, and producer raw output are never present here.
class LearningEdition {
  LearningEdition({
    required this.materialId,
    required this.materialRevisionId,
    required this.editionId,
    required this.releaseId,
    required this.title,
    required this.targetLanguage,
    required List<String> supportLanguages,
    required this.installedAtMs,
    required this.adoptedAtMs,
    required this.adopted,
    required List<LearningEditionResource> resources,
    required List<LearningEditionRendition> renditions,
  }) : _supportLanguages = List.unmodifiable(supportLanguages),
       _resources = List.unmodifiable(resources),
       _renditions = List.unmodifiable(renditions);

  final String materialId;
  final String materialRevisionId;
  final String editionId;

  /// Immutable release identity; the id the adoption intent references.
  final String releaseId;
  final String title;
  final String targetLanguage;
  final List<String> _supportLanguages;
  List<String> get supportLanguages => List.unmodifiable(_supportLanguages);
  final int installedAtMs;

  /// Original adoption time when this release is currently adopted, null
  /// otherwise. Required but nullable — never coerced.
  final int? adoptedAtMs;
  final bool adopted;

  final List<LearningEditionResource> _resources;
  List<LearningEditionResource> get resources => List.unmodifiable(_resources);
  final List<LearningEditionRendition> _renditions;
  List<LearningEditionRendition> get renditions =>
      List.unmodifiable(_renditions);

  LearningEditionResource? baseResourceOfKind(String kind) {
    for (final resource in _resources) {
      if (resource.kind == kind) return resource;
    }
    return null;
  }

  /// Read is available when the composition carries a readable document
  /// rendition or a structured-reading base resource.
  bool get providesRead =>
      renditions.any((r) => r.kind == 'document' && r.available) ||
      baseResourceOfKind('structured_reading') != null;

  /// A playable media rendition exists in the composition. Whether it is
  /// audio or video is answered against the Material's own media facts by the
  /// capability layer, because the edition view does not carry media types.
  bool get hasAvailableMediaRendition =>
      renditions.any((r) => r.kind == 'media' && r.available);

  bool get providesSynchronizedReadListen =>
      hasAvailableMediaRendition &&
      baseResourceOfKind('anchor_time_alignment') != null;
}

/// One resource-kind capability fact of an installed Edition.
class LearningEditionResource {
  const LearningEditionResource({
    required this.resourceId,
    required this.kind,
    required this.role,
    required this.required,
    required this.availability,
    required this.reviewStatus,
    required this.contentLanguage,
    required this.supportLanguages,
  });

  final String resourceId;
  final String kind;

  /// 'base' | 'assistance'.
  final String role;
  final bool required;

  /// 'available' | 'missing' | 'opaque'.
  final String availability;
  final String reviewStatus;
  final String? contentLanguage;
  final List<String> supportLanguages;
}

/// One rendition availability fact of an installed Edition. Kinds are the
/// package's own: `document` or `media`.
class LearningEditionRendition {
  const LearningEditionRendition({
    required this.renditionId,
    required this.kind,
    required this.available,
  });

  final String renditionId;
  final String kind;
  final bool available;
}
