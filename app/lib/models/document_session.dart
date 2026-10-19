import 'composition.dart';
import 'api_failure.dart';
import 'learning_material.dart';
import 'document_format.dart';

/// The direct document session state machine (Stage B / Phase 1 Slice 2).
///
/// Pure and immutable. The session is a *direct view* of one document
/// rendition (Core 4.0 `DocumentRendition`) backed by its exact Source Asset
/// bytes: it never fabricates paragraphs, cues, anchors, or structured-reading
/// structure, and it never carries a file location. Direct viewing is
/// deliberately not Structured Reading.
sealed class DocumentSessionState {
  const DocumentSessionState();
}

/// Nothing is open. The pane offers the primary "choose a document file"
/// action and the secondary paste entry.
final class DocumentSessionIdle extends DocumentSessionState {
  const DocumentSessionIdle();
}

/// A file or pasted text is being read/validated or a material is being
/// created. The picker itself is still part of [DocumentSessionIdle]'s story:
/// [DocumentSessionController.openFile] reports a cancelled picker by
/// returning to idle, not by entering [DocumentSessionFailed].
final class DocumentSessionOpening extends DocumentSessionState {
  const DocumentSessionOpening();
}

/// A library entry has several document renditions; the learner must choose
/// one explicitly. Never silently selects the first.
final class DocumentSessionChoosingAsset extends DocumentSessionState {
  DocumentSessionChoosingAsset({
    required this.details,
    required List<DocumentRendition> documentRenditions,
  }) : documentRenditions = List.unmodifiable(documentRenditions);

  final MaterialDetails details;
  final List<DocumentRendition> documentRenditions;
}

/// A document is open and readable. The chosen rendition's exact text (when a
/// text layer exists) is the document; the Source Asset's exact bytes back the
/// renderer for container formats. Retention is membership state, never a copy
/// or a move.
final class DocumentSessionReady extends DocumentSessionState {
  const DocumentSessionReady({
    required this.details,
    required this.documentRendition,
    required this.sourceAsset,
    this.capabilities,
    this.composition,
    this.retentionFailure,
    this.retentionInFlight = false,
  });

  /// Rebuilds this state with selected fields replaced.
  ///
  /// Every progressive load (capabilities, composition) and every membership
  /// result rebuilds the ready state, and each one used to re-list the fields
  /// it wanted to keep. A load that forgot one silently dropped it — the
  /// composition disappearing the moment Keep was pressed is exactly that bug.
  DocumentSessionReady copyWith({
    MaterialDetails? details,
    List<MaterialCapabilityProjection>? capabilities,
    ResolvedComposition? composition,
    ApiFailure? retentionFailure,
    bool? retentionInFlight,
  }) => DocumentSessionReady(
    details: details ?? this.details,
    documentRendition: documentRendition,
    sourceAsset: sourceAsset,
    capabilities: capabilities ?? this.capabilities,
    composition: composition ?? this.composition,
    // Unlike the others, a failure is cleared by the next attempt rather than
    // carried forward: passing null means "no failure now", not "keep the old
    // one". Callers that want to keep it pass it explicitly.
    retentionFailure: retentionFailure,
    retentionInFlight: retentionInFlight ?? this.retentionInFlight,
  );

  final MaterialDetails details;

  /// The explicitly chosen document rendition of the current revision, or
  /// null when the source carries no text layer (e.g. a scanned PDF).
  final DocumentRendition? documentRendition;

  /// The Source Asset backing the direct view. Present for documents created
  /// in this session; library entries opened from Core always carry it.
  final SourceAsset? sourceAsset;

  /// The durable capability projection for the open material, once loaded.
  /// Null while loading or when the projection is unavailable. A failed
  /// attempt is honest evidence — it never invalidates the direct view.
  final List<MaterialCapabilityProjection>? capabilities;

  /// The material's adopted composition, once resolved — the same material
  /// seen through its generated edition rather than its original bytes.
  ///
  /// Null while loading and whenever nothing is adopted, which is the ordinary
  /// state of a document that has never been sent to Gen. It is additive: the
  /// original document stays exactly as it was underneath.
  final ResolvedComposition? composition;

  /// The format of the open document, for renderer dispatch. Media types
  /// outside the supported family degrade to plain text rendering.
  DocumentFormat get format =>
      formatFromMediaType(
        documentRendition?.mediaType ?? sourceAsset?.mediaType ?? 'text/plain',
      ) ??
      DocumentFormat.plainText;

  /// A failed Keep/Unkeep left the document fully readable; the typed failure
  /// is only for the explicit disclosure component.
  final ApiFailure? retentionFailure;

  /// Whether a Keep/Unkeep operation is in flight (guards double submission).
  final bool retentionInFlight;

  /// Current Personal Library membership, read off [details] so the wire is
  /// the single source of truth.
  bool get isRetained => details.isRetained;
}

/// A typed, stable failure. [failure] names the kind for a localized message;
/// only [DocumentSessionFailure.apiFailure] additionally carries the typed
/// [ApiFailure], and only behind the explicit disclosure component. Ordinary
/// state and prose never leak raw exceptions, paths, or transport text.
final class DocumentSessionFailed extends DocumentSessionState {
  const DocumentSessionFailed(this.failure);

  final DocumentSessionFailure failure;
}

/// A named failure kind the UI can speak (CONTEXT.md: name the failure, hand
/// the detail to the disclosure).
enum DocumentSessionFailureKind {
  coreUnavailable,
  tooLarge,
  invalidUtf8,
  emptyDocument,
  unreadable,
  unsupported,
  corrupt,
  encrypted,
  missingTitle,
  apiFailure,
}

/// A failed session's named state plus the optional typed [ApiFailure] detail.
final class DocumentSessionFailure {
  const DocumentSessionFailure(this.kind, {this.apiFailure});

  final DocumentSessionFailureKind kind;
  final ApiFailure? apiFailure;
}
