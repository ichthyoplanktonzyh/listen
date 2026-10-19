import 'package:flutter/foundation.dart';

import '../data/repositories/external_vocabulary_repository.dart';
import '../data/repositories/lexical_repository.dart';
import '../models/types.dart';
import '../services/file_transfer_service.dart';

/// Owns the persistence command behind the lemma-correction dialog.
class LemmaCorrectionViewModel {
  const LemmaCorrectionViewModel(
    this._repository, {
    required this.original,
    required this.language,
  });

  final LexicalRepository _repository;
  final String original;
  final String language;

  Future<void> save(String corrected) =>
      _repository.correctLemma(original, corrected, language: language);
}

@immutable
class ExternalVocabularyImportState {
  ExternalVocabularyImportState({
    List<Map<String, dynamic>> entries = const [],
    this.formatFailure,
    this.importing = false,
  }) : entries = List.unmodifiable(
         entries.map(Map<String, dynamic>.unmodifiable),
       );

  final List<Map<String, dynamic>> entries;
  final String? formatFailure;
  final bool importing;
}

/// Owns file selection/parsing and the external-vocabulary write. The flow
/// only renders the preview and forwards the user's import choices.
class ExternalVocabularyImportViewModel extends ChangeNotifier {
  ExternalVocabularyImportViewModel(
    this._repository, {
    required this.language,
    required this.onImported,
    required this.fileService,
  });

  final ExternalVocabularyRepository _repository;
  final ExternalWordListFileService fileService;
  final String language;
  final Future<void> Function() onImported;
  ExternalVocabularyImportState _state = ExternalVocabularyImportState();
  bool _disposed = false;

  ExternalVocabularyImportState get state => _state;

  /// Returns false only when the user dismisses the platform picker.
  Future<bool> pick() async {
    final result = await fileService.pickAndRead();
    if (result == null) return false;
    switch (result) {
      case ExternalWordListReadSuccess(:final entries):
        _publish(ExternalVocabularyImportState(entries: entries));
      case ExternalWordListFormatFailure(:final message):
        _publish(ExternalVocabularyImportState(formatFailure: message));
    }
    return true;
  }

  Future<ExternalVocabularyImportSummary> import({
    required String defaultStatus,
    required bool overwriteExisting,
  }) async {
    _publish(
      ExternalVocabularyImportState(
        entries: _state.entries,
        formatFailure: _state.formatFailure,
        importing: true,
      ),
    );
    try {
      final summary = await _repository.importEntries(
        _state.entries,
        language: language,
        defaultStatus: defaultStatus,
        overwriteExisting: overwriteExisting,
      );
      await onImported();
      return summary;
    } finally {
      _publish(
        ExternalVocabularyImportState(
          entries: _state.entries,
          formatFailure: _state.formatFailure,
        ),
      );
    }
  }

  void _publish(ExternalVocabularyImportState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
