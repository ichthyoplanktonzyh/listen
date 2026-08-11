import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/repositories/learning_material_repository.dart';
import '../models/document_session.dart';
import '../models/learning_material.dart';
import '../models/personal_library.dart';
import '../services/document_intake_service.dart';
import '../services/document_text_projection.dart';

/// Owns one direct document session (Stage B): intake (file or pasted text),
/// material creation through Core 3.2, opening retained library entries, and
/// Keep/Unkeep membership operations.
///
/// The controller holds no transport, file-system, or picker implementation:
/// [DocumentIntakeFileService] and [LearningMaterialRepository] are injected
/// boundaries. Everything here is latest-request-wins: every open intent and
/// [close] bumps a session generation, and an async result that arrives late —
/// after a newer intent, after [close], or after [dispose] — never writes
/// state.
class DocumentSessionController extends ChangeNotifier {
  DocumentSessionController({
    required this.materialRepository,
    required this.fileService,
    required this.codec,
    this.refreshLibrary,
  });

  final LearningMaterialRepository materialRepository;
  final DocumentIntakeFileService fileService;
  final DocumentIntakeCodec codec;
  final Future<void> Function()? refreshLibrary;

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
      read = await fileService.pickAndReadTextFile();
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
        final title = titleFromFileName(fileService.basename(path));
        if (title.trim().isEmpty) {
          // A basename of ".txt" (or only whitespace around it) leaves no
          // title. Never invent "Untitled" and never send an empty title to
          // Core: fail as missingTitle without a create call.
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
    );
  }

  /// Opens a Personal Library entry for reading. Entries without document
  /// assets carry no Read intent and are ignored; exactly one asset opens
  /// directly, several require an explicit choice.
  void openLibraryEntry(PersonalLibraryEntry entry) {
    final assets = entry.documentAssets;
    if (assets.isEmpty) return;
    ++_generation;
    if (assets.length == 1) {
      _setState(
        DocumentSessionReady(
          details: entry.details,
          documentAsset: assets.single,
        ),
      );
    } else {
      _setState(
        DocumentSessionChoosingAsset(
          details: entry.details,
          documentAssets: assets,
        ),
      );
    }
  }

  /// Completes a multi-document library entry: the learner explicitly picks
  /// one asset; nothing is ever selected silently.
  void chooseDocumentAsset(String assetId) {
    final current = _state;
    if (current is! DocumentSessionChoosingAsset) return;
    for (final asset in current.documentAssets) {
      if (asset.id == assetId) {
        _setState(
          DocumentSessionReady(details: current.details, documentAsset: asset),
        );
        return;
      }
    }
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
        documentAsset: current.documentAsset,
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
      // Keep the chosen asset: membership changes do not touch revisions, and
      // the text on screen must not flicker.
      _setState(
        DocumentSessionReady(
          details: details,
          documentAsset: ready.documentAsset,
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
          documentAsset: ready.documentAsset,
          retentionFailure: materialRepository.failureDetail(error),
        ),
      );
    }
  }

  /// Whether [generation] can still publish: false after [dispose], after
  /// [close], or once a newer intent has started.
  bool _stale(int generation) => _disposed || generation != _generation;

  int _beginOpen() {
    final generation = ++_generation;
    _setState(const DocumentSessionOpening());
    return generation;
  }

  Future<void> _createDocument({
    required int generation,
    required String title,
    required List<int> bytes,
  }) async {
    DocumentIntakeInput input;
    try {
      input = codec.decodeDocumentText(bytes: bytes, title: title);
    } on DocumentIntakeFailure catch (failure) {
      if (_stale(generation)) return;
      _setState(
        DocumentSessionFailed(
          DocumentSessionFailure(_intakeFailureKind(failure.kind)),
        ),
      );
      return;
    }
    try {
      final details = await materialRepository.createLearningMaterial(
        CreateLearningMaterialInput(
          title: input.title,
          assets: [
            // Core 3.2 plain-text compatibility projection (the current
            // executable adapter, not a full Document Rendition schema);
            // Slice 2 replaces it with the canonical intake path.
            documentTextAssetInput(input.text),
          ],
        ),
        retain: const MaterialRetainExplicit(false),
      );
      if (_stale(generation)) return;
      final asset = matchingDocumentTextAsset(details, input.text);
      if (asset == null) {
        // The response holds no document asset whose text matches the
        // submitted text. Refuse to guess: showing another asset's body as
        // the picked document breaks direct-view integrity. The diagnostic
        // travels only inside the typed ApiFailure, behind the explicit
        // disclosure; ordinary prose stays localized and stable.
        _setState(
          DocumentSessionFailed(
            DocumentSessionFailure(
              DocumentSessionFailureKind.apiFailure,
              apiFailure: materialRepository.failureDetail(
                StateError(
                  'create response has no document_text asset matching the '
                  'submitted text',
                ),
              ),
            ),
          ),
        );
        return;
      }
      _setState(DocumentSessionReady(details: details, documentAsset: asset));
    } catch (error) {
      if (_stale(generation)) return;
      _setState(
        DocumentSessionFailed(
          DocumentSessionFailure(
            DocumentSessionFailureKind.apiFailure,
            apiFailure: materialRepository.failureDetail(error),
          ),
        ),
      );
    }
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
