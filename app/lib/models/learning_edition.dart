/// Learner-facing facts about one installed Learning Edition (Core 5.0
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
    required List<String> availableCapabilities,
  }) : _supportLanguages = List.unmodifiable(supportLanguages),
       _resources = List.unmodifiable(resources),
       _renditions = List.unmodifiable(renditions),
       _availableCapabilities = List.unmodifiable(availableCapabilities);

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
  final List<String> _availableCapabilities;
  List<String> get availableCapabilities =>
      List.unmodifiable(_availableCapabilities);

  LearningEditionResource? baseResourceOfKind(String kind) {
    for (final resource in _resources) {
      if (resource.kind == kind) return resource;
    }
    return null;
  }

  /// Core projects these capabilities from the effective resource roles and
  /// availability; missing or opaque resources do not satisfy the capability.
  bool get providesRead => _availableCapabilities.contains('read');

  /// A playable media rendition exists in the composition. Whether it is
  /// audio or video is answered against the Material's own media facts by the
  /// capability layer, because the edition view does not carry media types.
  bool get hasAvailableMediaRendition =>
      renditions.any((r) => r.kind == 'media' && r.available);

  bool get providesSynchronizedReadListen =>
      _availableCapabilities.contains('synchronized_read_listen');
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

/// One media rendition availability fact of an installed Edition.
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
