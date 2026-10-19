import 'package:flutter/foundation.dart';

import '../data/repositories/learning_assets_repository.dart';
import '../models/runtime_resources.dart';
import '../models/types.dart';
import '../models/named_failure.dart';

@immutable
class LearningAssetsState {
  LearningAssetsState({
    List<LexicalEntryDetails> values = const [],
    this.kind = 'phrase',
    this.status,
    this.search = '',
    this.loading = true,
  }) : values = List.unmodifiable(values);

  final List<LexicalEntryDetails> values;
  final String kind;
  final String? status;
  final String search;
  final bool loading;
}

class LearningAssetsViewModel extends ChangeNotifier {
  LearningAssetsViewModel(this._repository, {required this.language});

  final LearningAssetsRepository _repository;
  final String language;
  LearningAssetsState _state = LearningAssetsState();
  int _generation = 0;
  bool _disposed = false;

  LearningAssetsState get state => _state;

  Future<void> load() => _load(++_generation);

  Future<void> setKind(String value) {
    _publish(
      LearningAssetsState(
        values: _state.values,
        kind: value,
        status: _state.status,
        search: _state.search,
      ),
    );
    return _load(++_generation);
  }

  Future<void> setSearch(String value) {
    _publish(
      LearningAssetsState(
        values: _state.values,
        kind: _state.kind,
        status: _state.status,
        search: value,
      ),
    );
    return _load(++_generation);
  }

  Future<void> saveEntry({
    required LexicalEntry entry,
    required String status,
    required String definition,
    required String note,
  }) async {
    await _repository.upsertLexicalEntry({
      'language': entry.language,
      'kind': entry.kind,
      'canonical_form': entry.normalizedForm,
      'display_form': entry.displayForm,
      'status': status,
      'user_definition': definition,
      'personal_note': note,
    });
    await load();
  }

  Future<void> _load(int generation) async {
    final values = await _repository.lexicalEntries(
      language: language,
      kind: _state.kind,
      status: _state.status,
      search: _state.search,
    );
    if (_disposed || generation != _generation) return;
    _publish(
      LearningAssetsState(
        values: values,
        kind: _state.kind,
        status: _state.status,
        search: _state.search,
        loading: false,
      ),
    );
  }

  void _publish(LearningAssetsState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

@immutable
class LearningResourcesState {
  LearningResourcesState({
    List<LearningResourceDescriptor> resources = const [],
    this.busyId,
  }) : resources = List.unmodifiable(resources);

  final List<LearningResourceDescriptor> resources;
  final String? busyId;
}

class LearningResourcesViewModel extends ChangeNotifier {
  LearningResourcesViewModel(this._repository);
  final LearningAssetsRepository _repository;
  LearningResourcesState _state = LearningResourcesState();
  int _generation = 0;
  bool _disposed = false;

  LearningResourcesState get state => _state;

  Future<void> load() async {
    final generation = ++_generation;
    final values = await _repository.learningResources();
    if (!_isCurrent(generation)) return;
    _publish(LearningResourcesState(resources: values));
  }

  Future<void> toggle(LearningResourceDescriptor value) async {
    final generation = ++_generation;
    _publish(
      LearningResourcesState(resources: _state.resources, busyId: value.id),
    );
    try {
      if (value.state == 'installed') {
        await _repository.removeLearningResource(value.id);
      } else {
        await _repository.installLearningResource(value.id);
      }
      if (!_isCurrent(generation)) return;
      final values = await _repository.learningResources();
      if (!_isCurrent(generation)) return;
      _publish(LearningResourcesState(resources: values));
    } finally {
      if (_isCurrent(generation)) {
        _publish(LearningResourcesState(resources: _state.resources));
      }
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _publish(LearningResourcesState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

class PhraseCandidateViewModel extends ChangeNotifier {
  PhraseCandidateViewModel(
    this._repository, {
    required this.candidate,
    required Map<String, dynamic> source,
    String? initialStatus,
  }) : source = Map<String, dynamic>.unmodifiable(source),
       _status = initialStatus ?? 'known_not_recognized';

  final LearningAssetsRepository _repository;
  final PhraseCandidate candidate;
  final Map<String, dynamic> source;
  String _status;
  bool _saving = false;
  bool _disposed = false;

  String get status => _status;
  bool get saving => _saving;

  void setStatus(String value) {
    if (_disposed || _status == value) return;
    _status = value;
    notifyListeners();
  }

  Future<LexicalEntryDetails> save() async {
    if (_disposed) {
      throw StateError('PhraseCandidateViewModel is disposed');
    }
    _saving = true;
    notifyListeners();
    try {
      return await _repository.upsertLexicalEntry({
        'language': source['language'] as String? ?? 'en',
        'kind': 'phrase',
        'canonical_form': candidate.canonicalForm,
        'display_form': candidate.displayForm,
        'status': _status,
        'source': {
          ...source,
          'original_form': candidate.displayForm,
          'token_start': candidate.tokenStart,
          'token_end': candidate.tokenEnd,
        },
      });
    } finally {
      if (!_disposed) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

@immutable
class OpenSubtitlesSearchState {
  OpenSubtitlesSearchState({
    this.mode = 'title',
    this.query = '',
    List<OpenSubtitleCandidate> values = const [],
    this.loading = false,
    this.failure,
  }) : values = List.unmodifiable(values);

  final String mode;
  final String query;
  final List<OpenSubtitleCandidate> values;
  final bool loading;
  final NamedFailure? failure;
}

class OpenSubtitlesSearchViewModel extends ChangeNotifier {
  OpenSubtitlesSearchViewModel(
    this._repository, {
    required this.apiKey,
    required this.initialTitle,
    required this.initialFilename,
    required this.mediaPath,
  }) : _state = OpenSubtitlesSearchState(query: initialTitle);

  final LearningAssetsRepository _repository;
  final String apiKey;
  final String initialTitle;
  final String initialFilename;
  final String? mediaPath;
  OpenSubtitlesSearchState _state;
  int _generation = 0;
  bool _disposed = false;

  OpenSubtitlesSearchState get state => _state;

  void setMode(String value) {
    _generation++;
    _publish(
      OpenSubtitlesSearchState(
        mode: value,
        query: value == 'title'
            ? initialTitle
            : value == 'filename'
            ? initialFilename
            : _state.query,
        values: _state.values,
      ),
    );
  }

  void setQuery(String value) {
    _generation++;
    _publish(
      OpenSubtitlesSearchState(
        mode: _state.mode,
        query: value,
        values: _state.values,
      ),
    );
  }

  Future<void> search() async {
    final generation = ++_generation;
    _publish(
      OpenSubtitlesSearchState(
        mode: _state.mode,
        query: _state.query,
        values: _state.values,
        loading: true,
      ),
    );
    try {
      final hash = _state.mode == 'hash' && mediaPath != null
          ? await _repository.openSubtitlesMovieHash(mediaPath!)
          : null;
      final values = await _repository.searchOpenSubtitles(
        apiKey: apiKey,
        query: _state.mode == 'hash' ? null : _state.query,
        moviehash: hash,
      );
      if (_disposed || generation != _generation) return;
      _publish(
        OpenSubtitlesSearchState(
          mode: _state.mode,
          query: _state.query,
          values: values,
        ),
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _publish(
        OpenSubtitlesSearchState(
          mode: _state.mode,
          query: _state.query,
          values: _state.values,
          failure: NamedFailure(
            'semanticSearchQueryFailed',
            detail: _repository.failureDetail(error),
          ),
        ),
      );
    }
  }

  Future<String> download(int fileId) =>
      _repository.downloadOpenSubtitle(apiKey: apiKey, fileId: fileId);

  void _publish(OpenSubtitlesSearchState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
