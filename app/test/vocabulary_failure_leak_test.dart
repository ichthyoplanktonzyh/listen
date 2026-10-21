import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/semantic_search_view_model.dart';
import 'package:llplayer_next/data/repositories/semantic_search_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/vocabulary/semantic_search_dialog.dart';

void main() {
  testWidgets('the meaning-search dialog names a failure without leaking it', (
    tester,
  ) async {
    const envelope =
        '{"code":"validation_error","message":"private provider detail",'
        '"correlation_id":"api-853","retryable":false}';
    final api = LocalApi.withTransport(
      baseUrl: 'http://127.0.0.1:62645',
      token: 'token',
      transport: (method, path, body) async =>
          (statusCode: 503, body: envelope),
    );

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
            viewModel: SemanticSearchViewModel(
              LocalSemanticSearchRepository(api),
            ),
            language: 'en',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n');
    expect(rendered, contains('Could not read the meaning-search state'));
    for (final leak in const [
      'HttpException',
      'correlation_id',
      'api-853',
      '127.0.0.1',
      '62645',
      'validation_error',
      'private provider detail',
      'uri =',
      '/v1/',
    ]) {
      expect(rendered, isNot(contains(leak)), reason: leak);
    }
  });
}
