import 'api_failure.dart';
import 'learning_material.dart';

/// The direct document session state machine (Stage B).
///
/// Pure and immutable. The session is a *direct view* of one plain-text
/// document asset (Core 3.2's plain-text compatibility representation, the
/// first adapter — not a full Document Rendition schema): it never fabricates
/// paragraphs, cues, anchors, or structured-reading structure, and it never
/// carries a file location. Direct viewing is deliberately not Structured
/// Reading.
sealed class DocumentSessionState {
  const DocumentSessionState();
}

/// Nothing is open. The pane offers the primary "choose a text file" action
/// and the secondary paste entry.
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

/// A library entry has several document assets; the learner must choose one
/// explicitly. Never silently selects the first.
final class DocumentSessionChoosingAsset extends DocumentSessionState {
  DocumentSessionChoosingAsset({
    required this.details,
    required List<DocumentTextMaterialAsset> documentAssets,
  }) : documentAssets = List.unmodifiable(documentAssets);

  final MaterialDetails details;
  final List<DocumentTextMaterialAsset> documentAssets;
}

/// A document is open and readable. The chosen asset's exact text is the
/// document; retention is membership state, never a copy or a move.
final class DocumentSessionReady extends DocumentSessionState {
  const DocumentSessionReady({
    required this.details,
    required this.documentAsset,
    this.retentionFailure,
    this.retentionInFlight = false,
  });

  final MaterialDetails details;

  /// The explicitly chosen document-text asset of the current revision.
  final DocumentTextMaterialAsset documentAsset;

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
  missingTitle,
  apiFailure,
}

/// A failed session's named state plus the optional typed [ApiFailure] detail.
final class DocumentSessionFailure {
  const DocumentSessionFailure(this.kind, {this.apiFailure});

  final DocumentSessionFailureKind kind;
  final ApiFailure? apiFailure;
}
