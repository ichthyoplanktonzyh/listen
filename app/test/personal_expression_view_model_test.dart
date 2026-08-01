import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/personal_expression_view_model.dart';
import 'package:llplayer_next/data/repositories/personal_expression_repository.dart';
import 'package:llplayer_next/models/personal_expression.dart';

SentencePatternAssetView _pattern(String id) => SentencePatternAssetView(
  id: id,
  language: 'en',
  source: const PersonalExpressionSourceView(kind: 'manual', text: 'source'),
  currentVersion: SentencePatternVersionView(
    id: 'version-$id',
    patternId: id,
    version: 1,
    name: id,
    patternText: '$id {slot}',
    slots: const [SentencePatternSlotView(name: 'slot')],
    createdAtMs: 1,
  ),
  createdAtMs: 1,
  updatedAtMs: 1,
);

class _FakeRepository implements PersonalExpressionRepository {
  final queries = <String>[];
  final queryResults = <String, Completer<List<SentencePatternAssetView>>>{};
  Object? detailFailure;
  var detailLoads = 0;

  @override
  Future<List<SentencePatternAssetView>> listPatterns({
    required String language,
    String query = '',
  }) {
    queries.add(query);
    return queryResults.putIfAbsent(query, Completer.new).future;
  }

  @override
  Future<List<PersonalExpressionAttemptView>> listAttempts(String patternId) {
    detailLoads++;
    if (detailFailure case final failure?) return Future.error(failure);
    return Future.value(const []);
  }

  @override
  Future<List<SentencePatternVersionView>> listVersions(String patternId) {
    if (detailFailure case final failure?) return Future.error(failure);
    return Future.value([_pattern(patternId).currentVersion]);
  }

  @override
  Future<SentencePatternAssetView> create({
    required String language,
    required PersonalExpressionSourceView source,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
  }) => throw UnimplementedError();

  @override
  Future<void> delete(String patternId) => throw UnimplementedError();

  @override
  Future<PersonalExpressionExportBundleView> export({
    required String language,
  }) => throw UnimplementedError();

  @override
  Future<PersonalExpressionAttemptView> recordAttempt({
    required String patternId,
    required String patternVersionId,
    required String channel,
    required String assistance,
    required String responseText,
    required String selfAssessment,
  }) => throw UnimplementedError();

  @override
  Future<SentencePatternAssetView> revise({
    required String id,
    required String name,
    required String patternText,
    required List<SentencePatternSlotView> slots,
    String? note,
    String? systemConstructionId,
  }) => throw UnimplementedError();
}

void main() {
  group('PersonalExpressionViewModel', () {
    test(
      'an older search response cannot replace the newest results',
      () async {
        final repository = _FakeRepository();
        final viewModel = PersonalExpressionViewModel(
          repository,
          language: 'en',
          searchDebounce: Duration.zero,
        );
        addTearDown(viewModel.dispose);

        viewModel.setQuery('old');
        await Future<void>.delayed(Duration.zero);
        expect(repository.queries, ['old']);

        viewModel.setQuery('new');
        await Future<void>.delayed(Duration.zero);
        expect(repository.queries, ['old', 'new']);

        repository.queryResults['new']!.complete([_pattern('new-result')]);
        await Future<void>.delayed(Duration.zero);
        expect(viewModel.patterns.single.id, 'new-result');
        expect(viewModel.loading, isFalse);

        repository.queryResults['old']!.complete([_pattern('old-result')]);
        await Future<void>.delayed(Duration.zero);
        expect(viewModel.patterns.single.id, 'new-result');
        expect(viewModel.loading, isFalse);
      },
    );
  });

  group('PersonalExpressionDetailViewModel', () {
    test('a failed detail load is named and can be retried', () async {
      final repository = _FakeRepository()..detailFailure = StateError('down');
      final viewModel = PersonalExpressionDetailViewModel(
        repository,
        pattern: _pattern('detail'),
      );
      addTearDown(viewModel.dispose);

      await viewModel.load();
      expect(viewModel.loading, isFalse);
      expect(viewModel.failure, isNotNull);

      repository.detailFailure = null;
      await viewModel.load();
      expect(viewModel.failure, isNull);
      expect(viewModel.versions, hasLength(1));
    });
  });
}
