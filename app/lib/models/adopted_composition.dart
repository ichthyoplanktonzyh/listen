/// App domain models for the Core 4.0 adopted-composition surface
/// (`GET /v1/materials/{material_id}/composition`).
///
/// Pure and immutable: no transport or wire-format coupling, no file
/// location, no manifest. JSON decode lives exclusively in
/// `lib/services/api/composition.dart`.
library;

/// The binding behind one selected rendition of the adopted composition.
sealed class AdoptedCompositionBinding {
  const AdoptedCompositionBinding();
}

/// A Source document rendition bound to the managed store copy of its Source
/// Asset.
final class AdoptedCompositionManagedSourceBinding
    extends AdoptedCompositionBinding {
  const AdoptedCompositionManagedSourceBinding({required this.sourceAssetId});

  final String sourceAssetId;
}

/// A Source document rendition bound to the learner-chosen original location
/// of its Source Asset, through the App-owned reference map.
final class AdoptedCompositionReferencedSourceBinding
    extends AdoptedCompositionBinding {
  const AdoptedCompositionReferencedSourceBinding({
    required this.sourceAssetId,
    required this.reference,
    required this.available,
  });

  final String sourceAssetId;

  /// Opaque App-owned reference key.
  final String reference;

  /// Whether the referenced bytes are currently reachable.
  final bool available;
}

/// A Source media rendition bound to its registered media source.
final class AdoptedCompositionMediaBinding extends AdoptedCompositionBinding {
  const AdoptedCompositionMediaBinding({required this.mediaId});

  final String mediaId;
}

/// One selected rendition of the adopted composition, with its exact
/// digest/size facts and Source Asset / Media binding.
class AdoptedCompositionRendition {
  const AdoptedCompositionRendition({
    required this.renditionId,
    required this.kind,
    required this.origin,
    required this.mediaType,
    required this.language,
    required this.digest,
    required this.byteSize,
    required this.blobAvailable,
    required this.binding,
    required this.producerToolId,
  });

  final String renditionId;

  /// The package's own kind: `document` or `media`.
  final String kind;

  /// 'source' | 'derived'.
  final String origin;
  final String mediaType;
  final String? language;

  /// Lowercase hex SHA-256 of the exact rendition bytes.
  final String digest;
  final int byteSize;

  /// Whether the exact bytes are embedded in the adopted composition (a
  /// Source document rendition bound to its Source Asset has no embedded
  /// blob; its bytes resolve through the binding).
  final bool blobAvailable;
  final AdoptedCompositionBinding? binding;
  final String? producerToolId;
}

/// One selected resource of the adopted composition, with its exact
/// digest/size facts.
class AdoptedCompositionResource {
  const AdoptedCompositionResource({
    required this.resourceId,
    required this.kind,
    required this.schema,
    required this.role,
    required this.required,
    required this.availability,
    required this.contentLanguage,
    required this.supportLanguages,
    required this.payloadDigest,
    required this.payloadSizeBytes,
    required this.reviewStatus,
  });

  final String resourceId;
  final String kind;
  final String schema;

  /// 'base' | 'assistance'.
  final String role;
  final bool required;

  /// 'available' | 'missing' | 'opaque'.
  final String availability;
  final String? contentLanguage;
  final List<String> supportLanguages;
  final String payloadDigest;
  final int payloadSizeBytes;
  final String reviewStatus;
}

/// The resolved current adopted composition of a Material: exactly the
/// selected resources and renditions of the current adoption. This is the
/// single Core-owned composition interface; the App never re-parses a
/// `.listenpkg` to read adopted content.
class AdoptedComposition {
  AdoptedComposition({
    required this.materialId,
    required this.materialRevisionId,
    required this.releaseId,
    required this.editionId,
    required this.title,
    required this.targetLanguage,
    required List<String> supportLanguages,
    required this.adoptedAtMs,
    required List<AdoptedCompositionResource> resources,
    required List<AdoptedCompositionRendition> renditions,
  }) : _supportLanguages = List.unmodifiable(supportLanguages),
       _resources = List.unmodifiable(resources),
       _renditions = List.unmodifiable(renditions);

  final String materialId;
  final String materialRevisionId;
  final String releaseId;
  final String editionId;
  final String title;
  final String targetLanguage;
  final List<String> _supportLanguages;
  List<String> get supportLanguages => List.unmodifiable(_supportLanguages);
  final int adoptedAtMs;
  final List<AdoptedCompositionResource> _resources;
  List<AdoptedCompositionResource> get resources =>
      List.unmodifiable(_resources);
  final List<AdoptedCompositionRendition> _renditions;
  List<AdoptedCompositionRendition> get renditions =>
      List.unmodifiable(_renditions);

  AdoptedCompositionResource? resourceOfKind(String kind) {
    for (final resource in _resources) {
      if (resource.kind == kind) return resource;
    }
    return null;
  }

  /// The playable derived media rendition of the composition, when the
  /// composition carries one with embedded bytes.
  AdoptedCompositionRendition? get derivedMediaRendition {
    for (final rendition in _renditions) {
      if (rendition.kind == 'media' &&
          rendition.origin == 'derived' &&
          rendition.blobAvailable) {
        return rendition;
      }
    }
    return null;
  }
}
