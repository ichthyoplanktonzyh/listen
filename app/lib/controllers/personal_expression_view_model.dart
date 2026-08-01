import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/personal_expression_repository.dart';
import '../models/api_failure.dart';
import '../models/personal_expression.dart';
import '../services/api_service.dart' show describeApiFailure;

PersonalExpressionAttemptView? _latestWriting(
  List<PersonalExpressionAttemptView> attempts,
) {
  PersonalExpressionAttemptView? latest;
  for (final attempt in attempts) {
    if (attempt.channel != 'writing') continue;
    if (latest == null || attempt.completedAtMs > latest.completedAtMs) {
      latest = attempt;
    }
  }
  return latest;
}

/// Owns the list query and the state derived from its results.
class PersonalExpressionViewModel extends ChangeNotifier {
  PersonalExpressionViewModel(
    this._repository, {
    required this.language,
    this.searchDebounce = const Duration(milliseconds: 300),
  });

  final PersonalExpressionRepository _repository;
  final String language;
  final Duration searchDebounce;

  List<SentencePatternAssetView> _patterns = const [];
  Map<String, PersonalExpressionAttemptView> _lastWritten = const {};
  String _query = '';
  bool _loading = true;
  ApiFailure? _failure;
  Timer? _searchTimer;
  int _generation = 0;
  bool _disposed = false;

  List<SentencePatternAssetView> get patterns => List.unmodifiable(_patterns);
  Map<String, PersonalExpressionAttemptView> get lastWritten =>
      Map.unmodifiable(_lastWritten);
  String get query => _query;
  bool get loading => _loading;
  ApiFailure? get failure => _failure;

  Future<void> load() => _runQuery(++_generation);

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    final generation = ++_generation;
    _searchTimer?.cancel();
    _loading = true;
    _failure = null;
    notifyListeners();
    _searchTimer = Timer(searchDebounce, () {
      unawaited(_runQuery(generation));
    });
  }

  Future<void> refresh() {
    _searchTimer?.cancel();
    return _runQuery(++_generation);
  }

  Future<void> _runQuery(int generation) async {
    _loading = true;
    _failure = null;
    notifyListeners();
    try {
      final patterns = await _repository.listPatterns(
        language: language,
        query: _query,
      );
      final entries = await Future.wait(
        patterns.map((pattern) async {
          try {
            final attempts = await _repository.listAttempts(pattern.id);
            return MapEntry(pattern.id, _latestWriting(attempts));
          } catch (_) {
            return MapEntry<String, PersonalExpressionAttemptView?>(
              pattern.id,
              null,
            );
          }
        }),
      );
      if (_disposed || generation != _generation) return;
      _patterns = patterns;
      _lastWritten = {
        for (final entry in entries)
          if (entry.value != null) entry.key: entry.value!,
      };
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _failure = describeApiFailure(error);
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<PersonalExpressionExportBundleView> export() =>
      _repository.export(language: language);

  Future<void> create({
    required PersonalExpressionSourceView source,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
  }) async {
    await _repository.create(
      language: language,
      source: source,
      name: name,
      patternText: patternText,
      slots: slots,
      note: note,
    );
  }

  Future<void> revise({
    required SentencePatternAssetView pattern,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
  }) async {
    await _repository.revise(
      id: pattern.id,
      name: name,
      patternText: patternText,
      slots: slots,
      note: note,
      systemConstructionId: pattern.currentVersion.systemConstructionId,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    super.dispose();
  }
}

/// Owns one pattern's independently retryable detail state and writes.
class PersonalExpressionDetailViewModel extends ChangeNotifier {
  PersonalExpressionDetailViewModel(this._repository, {required this.pattern});

  final PersonalExpressionRepository _repository;
  final SentencePatternAssetView pattern;

  List<PersonalExpressionAttemptView> _attempts = const [];
  List<SentencePatternVersionView> _versions = const [];
  bool _loading = true;
  ApiFailure? _failure;
  int _generation = 0;
  bool _disposed = false;

  List<PersonalExpressionAttemptView> get attempts =>
      List.unmodifiable(_attempts);
  List<SentencePatternVersionView> get versions => List.unmodifiable(_versions);
  bool get loading => _loading;
  ApiFailure? get failure => _failure;

  Future<void> load() async {
    final generation = ++_generation;
    _loading = true;
    _failure = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        _repository.listAttempts(pattern.id),
        _repository.listVersions(pattern.id),
      ]);
      if (_disposed || generation != _generation) return;
      _attempts = values[0] as List<PersonalExpressionAttemptView>;
      _versions = values[1] as List<SentencePatternVersionView>;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _failure = describeApiFailure(error);
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> delete() => _repository.delete(pattern.id);

  Future<void> recordWritingAttempt({
    required String assistance,
    required String responseText,
    required String selfAssessment,
  }) async {
    await _repository.recordAttempt(
      patternId: pattern.id,
      patternVersionId: pattern.currentVersion.id,
      channel: 'writing',
      assistance: assistance,
      responseText: responseText,
      selfAssessment: selfAssessment,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
