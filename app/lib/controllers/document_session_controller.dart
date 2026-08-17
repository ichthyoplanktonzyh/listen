import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/repositories/learning_material_repository.dart';
import '../models/composition.dart';
import '../models/document_session.dart';
import '../models/learning_material.dart';
import '../models/personal_library.dart';
import '../services/document_decoding/document_format.dart';
import '../services/document_intake_flow.dart';
import '../services/document_intake_service.dart';
import '../services/document_source_resolver.dart';

/// Owns one direct document session (Slice 2): intake (file or pasted text),
/// material creation through the Core 4.0 Source Asset / Document Rendition
/// boundary, opening retained library entries, Keep/Unkeep membership, and the
/// exact-byte resolution backing the direct view.
///
/// The controller holds no transport, file-system, or picker implementation:
/// [DocumentIntakeFileService], [DocumentIntakeFlow], and the reference map
/// are injected boundaries. Everything here is latest-request-wins: every
/// open intent and [close] bumps a session generation, and an async result
/// that arrives late — after a newer intent, after [close], or after
/// [dispose] — never writes state.
class DocumentSessionController extends ChangeNotifier {
  DocumentSessionController({
    required this.materialRepository,
    required this.fileService,
    required this.intakeFlow,
    required this.sourceResolver,
    this.resolveComposition,
    this.refreshLibrary,
    this.referenceInPlace = false,
  });

  final LearningMaterialRepository materialRepository;
  final DocumentIntakeFileService fileService;

  /// The shared intake: decode, bind, create, exact rendition match — the
  /// same path a discovered article travels.
  final DocumentIntakeFlow intakeFlow;

  /// Resolves a Source Asset's exact bytes for the direct view.
  final DocumentSourceResolver sourceResolver;

  /// Resolves the material's adopted composition, when one exists. Injected so
  /// the controller keeps no transport: null in tests and on hosts that have
  /// no composition surface wired.
  final Future<ResolvedComposition?> Function(String materialId)?
  resolveComposition;

  final Future<void> Function(MaterialDetails details)? refreshLibrary;

  /// Whether intake references the picked file in place instead of copying
  /// into the managed store. Explicit only: never auto-selected, and the
  /// direct view then depends on the original location.
  bool referenceInPlace;

  DocumentSessionState _state = const DocumentSessionIdle();
  int _generation = 0;
  bool _disposed = false;

  /// The last paste submission, kept only so a failed paste can be retried
  /// with the same input.
  ({String title, String body})? _pendingPaste;

  DocumentSessionState get state => _state;
  int get generation => _generation;

  /// Opens the `.txt` picker. A cancelled picker is a normal result: the
  /// session stays idle, shows no error, and creates no material.
  Future<void> openFile() async {
    final generation = _beginOpen();
    if (!materialRepository.isAvailable) {
      _setState(
        const DocumentSessionFailed(
          DocumentSessionFailure(DocumentSessionFailureKind.coreUnavailable),
        ),
      );
      return;
    }
    // The platform picker or the read itself can throw (permissions, I/O,
    // unexpected platform errors). That is a typed, stable failure — never an
    // escaping exception from the unawaited UI call. Only Exceptions are
    // caught: a Dart Error is a programming bug and stays loud. The raw
    // exception is deliberately not stored anywhere the UI can print it.
    final DocumentFileRead read;
    try {
      read = await fileService.pickAndReadDocumentFile();
    } on Exception {
      if (_stale(generation)) return;
      _setState(
        DocumentSessionFailed(
          DocumentSessionFailure(DocumentSessionFailureKind.unreadable),
        ),
      );
      return;
    }
    if (_stale(generation)) return;
    switch (read) {
      case DocumentFileCancelled():
        _pendingPaste = null;
        _setState(const DocumentSessionIdle());
      case DocumentFileFailure(:final failure):
        _setState(
          DocumentSessionFailed(
            DocumentSessionFailure(_intakeFailureKind(failure.kind)),
          ),
        );
      case DocumentFileData(:final path, :final bytes):
        final format = formatForPath(path);
        if (format == null) {
          // The picker only offers supported extensions, but a renamed or
          // otherwise unsupported file must still fail honestly.
          _setState(
            DocumentSessionFailed(
              DocumentSessionFailure(DocumentSessionFailureKind.unsupported),
            ),
          );
          return;
        }
        final title = titleFromFileName(fileService.basename(path));
        if (title.trim().isEmpty) {
          // A basename like ".txt" leaves no title. Never invent "Untitled"
          // and never send an empty title to Core: fail as missingTitle
          // without a create call.
          _setState(
            DocumentSessionFailed(
              DocumentSessionFailure(DocumentSessionFailureKind.missingTitle),
            ),
          );
          return;
        }
        await _createDocument(
          generation: generation,
          title: title,
          bytes: bytes,
          format: format,
          sourcePath: path,
        );
      default:
        throw StateError('unexpected DocumentFileRead: $read');
    }
  }

  /// Opens pasted text: a secondary convenience entry on the same intake
  /// path, never a separate product category. Requires a non-empty title.
  Future<void> openPastedText({
    required String title,
    required String body,
  }) async {
    final generation = _beginOpen();
    if (!materialRepository.isAvailable) {
      _setState(
        const DocumentSessionFailed(
          DocumentSessionFailure(DocumentSessionFailureKind.coreUnavailable),
        ),
      );
      return;
    }
    if (title.trim().isEmpty) {
      _setState(
        const DocumentSessionFailed(
          DocumentSessionFailure(DocumentSessionFailureKind.missingTitle),
        ),
      );
      return;
    }
    _pendingPaste = (title: title, body: body);
    final bytes = utf8.encode(body);
    await _createDocument(
      generation: generation,
      title: title.trim(),
      bytes: bytes,
      format: DocumentFormat.plainText,
    );
  }

  /// Opens a Personal Library entry for reading. Entries without document
  /// renditions carry no Read intent and are ignored; exactly one rendition
  /// opens directly, several require an explicit choice.
  void openLibraryEntry(PersonalLibraryEntry entry) {
    final renditions = entry.documentRenditions;
    if (renditions.isEmpty) return;
    ++_generation;
    if (renditions.length == 1) {
      final rendition = renditions.single;
      _enterReady(
        details: entry.details,
        rendition: rendition,
        sourceAsset: _sourceAssetFor(entry.details, rendition),
      );
    } else {
      _setState(
        DocumentSessionChoosingAsset(
          details: entry.details,
          documentRenditions: renditions,
        ),
      );
    }
  }

  /// Completes a multi-document library entry: the learner explicitly picks
  /// one rendition; nothing is ever selected silently.
  void chooseDocumentAsset(String assetId) {
    final current = _state;
    if (current is! DocumentSessionChoosingAsset) return;
    for (final rendition in current.documentRenditions) {
      if (rendition.id == assetId) {
        _enterReady(
          details: current.details,
          rendition: rendition,
          sourceAsset: _sourceAssetFor(current.details, rendition),
        );
        return;
      }
    }
  }

  /// The Source Asset bound to [rendition], or the sole Source Asset of the
  /// revision when the rendition names none.
  static SourceAsset? _sourceAssetFor(
    MaterialDetails details,
    DocumentRendition rendition,
  ) {
    final assets = details.currentRevision.sourceAssets;
    if (assets.isEmpty) return null;
    final bound = rendition.sourceAssetId;
    if (bound != null) {
      for (final asset in assets) {
        if (asset.id == bound) return asset;
      }
    }
    return assets.length == 1 ? assets.single : null;
  }

  /// Retries the last failed intent: a failed file open re-picks, a failed
  /// paste re-submits the same input.
  Future<void> retry() async {
    final pending = _pendingPaste;
    if (pending == null) {
      await openFile();
      return;
    }
    await openPastedText(title: pending.title, body: pending.body);
  }

  /// Closes the session. Any in-flight result of an earlier generation is
  /// dropped on arrival.
  void close() {
    ++_generation;
    _pendingPaste = null;
    _setState(const DocumentSessionIdle());
  }

  /// Adds the open document to the Personal Library. Membership only: the
  /// document stays exactly as it was, and a failure leaves it fully readable.
  Future<void> retain() => _changeMembership(retain: true);

  /// Removes the open document from the Personal Library. Membership only: the
  /// document stays readable, and a failure changes nothing.
  Future<void> unretain() => _changeMembership(retain: false);

  Future<void> _changeMembership({required bool retain}) async {
    final current = _state;
    if (current is! DocumentSessionReady) return;
    if (current.retentionInFlight) return;
    if (current.isRetained == retain) return;
    final materialId = current.details.material.id;
    final generation = _generation;
    _setState(current.copyWith(retentionInFlight: true));
    try {
      final details = retain
          ? await materialRepository.retainLearningMaterial(materialId)
          : await materialRepository.unretainLearningMaterial(materialId);
      if (_stale(generation)) return;
      if (_state is! DocumentSessionReady) return;
      final ready = _state as DocumentSessionReady;
      if (ready.details.material.id != materialId) return;
      // Rebuilt from `ready`, not from the pre-flight snapshot: a capability
      // projection or an adopted composition can land while the round trip is
      // in flight, and rebuilding from the older state would drop it. Keeps
      // the chosen rendition too — membership never touches revisions, so the
      // text on screen must not flicker.
      _setState(ready.copyWith(details: details, retentionInFlight: false));
      await refreshLibrary?.call(details);
    } catch (error) {
      if (_stale(generation)) return;
      if (_state is! DocumentSessionReady) return;
      final ready = _state as DocumentSessionReady;
      if (ready.details.material.id != materialId) return;
      // The document stays readable; only the typed detail is surfaced.
      _setState(
        ready.copyWith(
          retentionInFlight: false,
          retentionFailure: materialRepository.failureDetail(error),
        ),
      );
    }
  }

  /// Whether [generation] can still publish: false after [dispose], after
  /// [close], or once a newer intent has started.
  bool _stale(int generation) => _disposed || generation != _generation;

  /// Resolves the exact bytes backing the open document for direct rendering.
  /// A missing referenced location reports unavailable — it is never a crash
  /// and never a reason to remove the Material.
  Future<DocumentSourceBytes> resolveSourceBytes(SourceAsset asset) =>
      sourceResolver.bytesFor(asset);

  /// Loads the material's capability projection and attaches it to the ready
  /// state. Latest-request-wins: a stale arrival after [close], a newer open,
  /// or a newer material is dropped. A failed projection is not a failure of
  /// the document — the ready state simply stays without it.
  Future<void> _loadCapabilities(int generation, String materialId) async {
    try {
      final projections = await materialRepository.listMaterialCapabilities(
        materialId,
      );
      if (_stale(generation)) return;
      final current = _state;
      if (current is! DocumentSessionReady) return;
      if (current.details.material.id != materialId) return;
      _setState(
        current.copyWith(
          capabilities: projections,
          retentionFailure: current.retentionFailure,
        ),
      );
    } catch (_) {
      // The projection is progressive detail; its absence never breaks the
      // direct view. A failed read stays silent.
    }
  }

  /// Re-reads the adopted composition of the open document and attaches it to
  /// the ready state.
  ///
  /// This is what a finished generation calls: the workbench refreshes in
  /// place, on the same material, instead of sending the learner to a separate
  /// "open the result" surface. Same latest-request-wins rules as every other
  /// load, and the same honesty — nothing adopted, an unresolvable payload, or
  /// a failed read all leave the original document exactly as it was.
  Future<void> refreshComposition() async {
    final current = _state;
    if (current is! DocumentSessionReady) return;
    await _loadComposition(_generation, current.details.material.id);
  }

  Future<void> _loadComposition(int generation, String materialId) async {
    final resolve = resolveComposition;
    if (resolve == null) return;
    try {
      final composition = await resolve(materialId);
      if (composition == null || _stale(generation)) return;
      final current = _state;
      if (current is! DocumentSessionReady) return;
      if (current.details.material.id != materialId) return;
      _setState(
        current.copyWith(
          composition: composition,
          retentionFailure: current.retentionFailure,
        ),
      );
    } catch (_) {
      // The adopted edition is additive detail. Its absence — nothing adopted,
      // an unreadable payload, an unreachable core — never takes the original
      // document away.
    }
  }

  /// Enters the ready state and starts the progressive loads.
  void _enterReady({
    required MaterialDetails details,
    required DocumentRendition? rendition,
    required SourceAsset? sourceAsset,
  }) {
    final generation = _generation;
    _setState(
      DocumentSessionReady(
        details: details,
        documentRendition: rendition,
        sourceAsset: sourceAsset,
      ),
    );
    unawaited(_loadCapabilities(generation, details.material.id));
    unawaited(_loadComposition(generation, details.material.id));
  }

  int _beginOpen() {
    final generation = ++_generation;
    _setState(const DocumentSessionOpening());
    return generation;
  }

  Future<void> _createDocument({
    required int generation,
    required String title,
    required List<int> bytes,
    required DocumentFormat format,
    String? sourcePath,
  }) async {
    final DocumentIntakeOutcome outcome;
    try {
      outcome = await intakeFlow.takeInDocument(
        title: title,
        bytes: bytes,
        format: format,
        sourcePath: sourcePath,
        referenceInPlace: referenceInPlace,
      );
    } on DocumentIntakeFailure catch (failure) {
      if (_stale(generation)) return;
      _setState(
        DocumentSessionFailed(
          DocumentSessionFailure(_intakeFailureKind(failure.kind)),
        ),
      );
      return;
    } catch (error) {
      if (_stale(generation)) return;
      // A failed intake (store/reference map unavailable, Core rejected the
      // create, a response without an exact byte match) has rolled back what
      // it created. The typed failure is honest and the raw error stays
      // behind the disclosure.
      _setState(
        DocumentSessionFailed(
          DocumentSessionFailure(
            DocumentSessionFailureKind.apiFailure,
            apiFailure: materialRepository.failureDetail(error),
          ),
        ),
      );
      return;
    }
    if (_stale(generation)) return;
    final details = outcome.details;
    final rendition = DocumentIntakeFlow.matchingDocumentRendition(
      details,
      outcome.sha256Digest,
    );
    if (rendition == null) {
      // Unreachable: the flow refuses a response without an exact match. Kept
      // as a typed guard so a future caller change cannot render another
      // rendition's body as the picked document.
      _setState(
        DocumentSessionFailed(
          DocumentSessionFailure(
            DocumentSessionFailureKind.apiFailure,
            apiFailure: materialRepository.failureDetail(
              StateError(
                'create response has no document rendition matching the '
                'submitted bytes',
              ),
            ),
          ),
        ),
      );
      return;
    }
    _enterReady(
      details: details,
      rendition: rendition,
      sourceAsset: _sourceAssetFor(details, rendition),
    );
  }

  static DocumentSessionFailureKind _intakeFailureKind(
    DocumentIntakeFailureKind kind,
  ) => switch (kind) {
    DocumentIntakeFailureKind.tooLarge => DocumentSessionFailureKind.tooLarge,
    DocumentIntakeFailureKind.invalidUtf8 =>
      DocumentSessionFailureKind.invalidUtf8,
    DocumentIntakeFailureKind.emptyDocument =>
      DocumentSessionFailureKind.emptyDocument,
    DocumentIntakeFailureKind.unreadable =>
      DocumentSessionFailureKind.unreadable,
    DocumentIntakeFailureKind.unsupported =>
      DocumentSessionFailureKind.unsupported,
    DocumentIntakeFailureKind.corrupt => DocumentSessionFailureKind.corrupt,
    DocumentIntakeFailureKind.encrypted => DocumentSessionFailureKind.encrypted,
  };

  void _setState(DocumentSessionState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
