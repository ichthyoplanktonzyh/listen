import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/semantic_search_view_model.dart';
import 'package:llplayer_next/data/repositories/semantic_search_repository.dart';
import 'package:llplayer_next/models/semantic_embedding.dart';

const _ready = SemanticEmbeddingCapabilityView(
  status: 'ready',
  indexedSourceCount: 1,
);

SemanticSearchResultView _result(String query, String text) =>
    SemanticSearchResultView(
      capability: _ready,
      query: query,
      hits: [
        SemanticSearchHitView(
          source: SemanticSearchSourceView(
            kind: 'subtitle',
            sourceId: text,
            language: 'en',
            text: text,
            startMs: 0,
            endMs: 1,
          ),
          similarity: 0.9,
          modelFingerprint: 'fingerprint',
        ),
      ],
    );

class _Repository implements SemanticSearchRepository {
  final searches = <Completer<SemanticSearchResultView>>[];

  @override
  Future<SemanticEmbeddingCapabilityView> capability() async => _ready;

  @override
  Future<SemanticEmbeddingCapabilityView> disable() async => _ready;

  @override
  Future<SemanticEmbeddingCapabilityView> enable() async => _ready;

  @override
  Future<SemanticEmbeddingCapabilityView> install() async => _ready;

  @override
  Future<SemanticEmbeddingCapabilityView> rebuild() async => _ready;

  @override
  Future<SemanticSearchResultView> search({
    required String query,
    required String language,
  }) {
    final completer = Completer<SemanticSearchResultView>();
    searches.add(completer);
    return completer.future;
  }

  @override
  Future<SemanticEmbeddingCapabilityView> uninstall() async => _ready;
}

void main() {
  group('SemanticSearchViewModel', () {
    test('loads capability and exposes an immutable snapshot', () async {
      final viewModel = SemanticSearchViewModel(_Repository());

      await viewModel.loadCapability();

      expect(viewModel.state.busy, isFalse);
      expect(viewModel.state.capability, same(_ready));
      expect(
        () => viewModel.hits.add(_result('q', 'hit').hits.single),
        throwsUnsupportedError,
      );
      viewModel.dispose();
    });

    test('a stale search cannot overwrite the latest result', () async {
      final repository = _Repository();
      final viewModel = SemanticSearchViewModel(repository);
      await viewModel.loadCapability();

      final first = viewModel.search(query: 'old', language: 'en');
      final second = viewModel.search(query: 'new', language: 'en');
      repository.searches[1].complete(_result('new', 'new result'));
      await second;
      repository.searches[0].complete(_result('old', 'old result'));
      await first;

      expect(viewModel.state.hits.single.source.text, 'new result');
      expect(viewModel.state.busy, isFalse);
      viewModel.dispose();
    });
  });
}
