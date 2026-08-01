import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/semantic_search_view_model.dart';
import 'package:llplayer_next/data/repositories/semantic_search_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/semantic_embedding.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/vocabulary/semantic_search_dialog.dart';

const _ready = SemanticEmbeddingCapabilityView(
  status: 'ready',
  indexedSourceCount: 1,
);

class _Repository implements SemanticSearchRepository {
  String? query;

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
  }) async {
    this.query = query;
    return SemanticSearchResultView(
      capability: _ready,
      query: query,
      hits: const [
        SemanticSearchHitView(
          source: SemanticSearchSourceView(
            kind: 'subtitle',
            sourceId: 'source',
            language: 'en',
            text: 'A matching sentence',
            startMs: 0,
            endMs: 10,
          ),
          similarity: 0.875,
          modelFingerprint: 'fingerprint',
        ),
      ],
    );
  }

  @override
  Future<SemanticEmbeddingCapabilityView> uninstall() async => _ready;
}

LocalApi _unusedApi() => LocalApi.withTransport(
  baseUrl: 'http://unused',
  token: 'token',
  transport: (method, path, body) async =>
      (statusCode: 500, body: 'must not be called'),
);

void main() {
  testWidgets('renders and searches through an injected view model', (
    tester,
  ) async {
    final repository = _Repository();
    final viewModel = SemanticSearchViewModel(repository);
    await viewModel.loadCapability();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SemanticSearchDialog(
            api: _unusedApi(),
            language: 'en',
            viewModel: viewModel,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '  meaning  ');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(repository.query, 'meaning');
    expect(find.text('A matching sentence'), findsOneWidget);
    expect(find.text('0.875'), findsOneWidget);
    viewModel.dispose();
  });
}
