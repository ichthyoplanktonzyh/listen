import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/repositories/learning_material_repository.dart';
import '../models/document_session.dart';
import '../models/learning_material.dart';
import '../models/personal_library.dart';
import '../services/document_decoding/document_format.dart';
import '../services/document_intake_service.dart';
import '../services/document_reference_store.dart';
import '../services/document_source_resolver.dart';
import '../services/managed_asset_store.dart';

/// Owns one direct document session (Slice 2): intake (file or pasted text),
/// material creation through the Core 4.0 Source Asset / Document Rendition
/// boundary, opening retained library entries, Keep/Unkeep membership, and the
/// exact-byte resolution backing the direct view.
///
/// The controller holds no transport, file-system, or picker implementation:
/// [DocumentIntakeFileService], [LearningMaterialRepository], the managed
/// asset store, and the reference map are injected boundaries. Everything here
/// is latest-request-wins: every open intent and [close] bumps a session
/// generation, and an async result that arrives late — after a newer intent,
/// after [close], or after [dispose] — never writes state.
class DocumentSessionController extends ChangeNotifier {
  DocumentSessionController({
    required this.materialRepository,
    required this.fileService,
    required this.codec,
    required this.store,
    required this.referenceStore,
    required this.sourceResolver,
    this.refreshLibrary,
    this.referenceInPlace = false,
  });

  final LearningMaterialRepository materialRepository;
  final DocumentIntakeFileService fileService;
  final DocumentIntakeCodec codec;
  final ManagedAssetStoreService store;
  final DocumentReferenceStore referenceStore;

  /// Resolves a Source Asset's exact bytes for the direct view.
  final DocumentSourceResolver sourceResolver;

  final Future<void> Function()? refreshLibrary;

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
    _setState(
      DocumentSessionReady(
        details: current.details,
        documentRendition: current.documentRendition,
        sourceAsset: current.sourceAsset,
        retentionInFlight: true,
      ),
    );
    try {
      final details = retain
          ? await materialRepository.retainLearningMaterial(materialId)
          : await materialRepository.unretainLearningMaterial(materialId);
      if (_stale(generation)) return;
      if (_state is! DocumentSessionReady) return;
      final ready = _state as DocumentSessionReady;
      if (ready.details.material.id != materialId) return;
      // Keep the chosen rendition: membership changes do not touch revisions,
      // and the text on screen must not flicker.
      _setState(
        DocumentSessionReady(
          details: details,
          documentRendition: ready.documentRendition,
          sourceAsset: ready.sourceAsset,
        ),
      );
      await refreshLibrary?.call();
    } catch (error) {
      if (_stale(generation)) return;
      if (_state is! DocumentSessionReady) return;
      final ready = _state as DocumentSessionReady;
      if (ready.details.material.id != materialId) return;
      // The document stays readable; only the typed detail is surfaced.
      _setState(
        DocumentSessionReady(
          details: ready.details,
          documentRendition: ready.documentRendition,
          sourceAsset: ready.sourceAsset,
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
        DocumentSessionReady(
          details: current.details,
          documentRendition: current.documentRendition,
          sourceAsset: current.sourceAsset,
          capabilities: projections,
          retentionInFlight: current.retentionInFlight,
          retentionFailure: current.retentionFailure,
        ),
      );
    } catch (_) {
      // The projection is progressive detail; its absence never breaks the
      // direct view. A failed read stays silent.
    }
  }

  /// Enters the ready state and starts the capability load.
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
    DocumentIntakeInput input;
    try {
      input = await codec.decodeDocument(
        bytes: bytes,
        title: title,
        format: format,
      );
    } on DocumentIntakeFailure catch (failure) {
      if (_stale(generation)) return;
      _setState(
        DocumentSessionFailed(
          DocumentSessionFailure(_intakeFailureKind(failure.kind)),
        ),
      );
      return;
    }

    // Binding decision: the default Keep copies the exact bytes into the
    // managed store (verified before the create); Reference in Place records
    // the original location and binds by the app-owned reference key.
    var binding = const SourceAssetBinding(
      type: SourceAssetBindingType.managed,
    );
    String? createdStoreCopy;
    try {
      if (referenceInPlace && sourcePath != null) {
        await referenceStore.save(input.sha256Digest, sourcePath);
        binding = SourceAssetBinding(
          type: SourceAssetBindingType.referenced,
          reference: input.sha256Digest,
        );
      } else {
        // Pasted text (or a file with no location) is always copied: there is
        // no original location to reference.
        referenceInPlace = false;
        final copy = await store.copyBytesIntoStore(
          bytes: bytes,
          mediaKind: 'document',
        );
        createdStoreCopy = copy.createdNew ? copy.path : null;
      }
    } on Exception catch (error) {
      if (_stale(generation)) return;
      // The store or reference map is unavailable: the document must not
      // appear to have been kept. The typed failure is honest and the raw
      // error stays behind the disclosure.
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

    final MaterialDetails details;
    try {
      details = await materialRepository.createLearningMaterial(
        CreateLearningMaterialInput(
          title: input.title,
          sourceAssets: [
            SourceAssetInput(
              mediaType: input.mediaType,
              byteLength: input.byteLength,
              sha256Digest: input.sha256Digest,
              // The binding is an app-owned fact, never a file location the
              // wire may dereference.
              binding: binding,
            ),
          ],
          documentRenditions: [
            // The Source Document Rendition is the exact Source Asset bytes:
            // same digest, same size, bound to the Source Asset. The material
            // never carries a fabricated extracted-text body.
            DocumentRenditionInput(
              mediaType: input.mediaType,
              digest: input.sha256Digest,
              byteSize: input.byteLength,
              sourceAssetIndex: 0,
            ),
          ],
          mediaRenditions: const [],
        ),
        retain: const MaterialRetainExplicit(false),
      );
    } catch (error) {
      // The create failed: roll back the store copy only when this call
      // created it (a deduplicated pre-existing target is shared and stays),
      // and drop the reference mapping for a failed referenced create.
      final copy = createdStoreCopy;
      if (copy != null) {
        try {
          await store.deleteStoreCopy(copy);
        } on Exception {
          // Rollback is best effort; the failure surface stays typed.
        }
      }
      if (binding.type == SourceAssetBindingType.referenced) {
        try {
          await referenceStore.remove(input.sha256Digest);
        } on Exception {
          // Best effort.
        }
      }
      if (_stale(generation)) return;
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
    // The create succeeded; a fresh store copy is now owned by the material
    // and must not be rolled back.
    createdStoreCopy = null;
    final rendition = matchingDocumentRendition(details, input.sha256Digest);
    if (rendition == null) {
      // The response holds no source document rendition bound to the exact
      // submitted bytes. Refuse to guess: showing another rendition's body as
      // the picked document breaks direct-view integrity. The diagnostic
      // travels only inside the typed ApiFailure, behind the explicit
      // disclosure; ordinary prose stays localized and stable.
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
    DocumentIntakeFailureKind.encrypted =>
      DocumentSessionFailureKind.encrypted,
  };

  /// The created material's source document rendition whose exact bytes are
  /// the submitted Source Asset's, or null when no rendition matches.
  ///
  /// Core 4.0 may converge an equal-content create onto an already retained
  /// material; its persisted revision then holds the same bytes, so an exact
  /// digest match still exists. A response without an exact match must be
  /// refused by the caller, never guessed.
  static DocumentRendition? matchingDocumentRendition(
    MaterialDetails details,
    String sourceSha256,
  ) {
    for (final rendition in details.currentRevision.documentRenditions) {
      if (rendition.origin != RenditionOrigin.source) continue;
      if (rendition.digest == sourceSha256) return rendition;
    }
    return null;
  }

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
