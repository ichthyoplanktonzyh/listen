import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/provider_settings_view_models.dart';
import 'package:llplayer_next/data/repositories/settings_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/settings/syntax_capability_settings.dart';

void main() {
  testWidgets('uninstalled capability is quiet and install is an explicit action', (
    tester,
  ) async {
    final requests = <String>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        requests.add('$method $path');
        return (
          statusCode: 200,
          body:
              '{"status":"not_installed","progress":0,"enabled":false,'
              '"runtime_version":"3.8.13","model_version":"3.8.0",'
              '"provider_version":"jsonl-v2","delivery_checksum_sha256":"delivery",'
              '"model_checksum_sha256":"abc","expected_install_bytes":162250752,'
              '"installed_bytes":0,"error":null,"updated_at_ms":1}',
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SyntaxCapabilitySettings(
            viewModel: SyntaxCapabilitySettingsViewModel(
              LocalSyntaxCapabilityRepository(api),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Install'), findsOneWidget);
    expect(find.text('Uninstall'), findsNothing);
    expect(requests, ['GET /v1/syntax/capability']);

    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(requests, contains('POST /v1/syntax/capability/install'));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ready capability automatically analyzes the current track', (
    tester,
  ) async {
    final requests = <String>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        requests.add('$method $path');
        if (path.endsWith('/syntax-analysis')) {
          return (
            statusCode: 200,
            body:
                '{"status":"ready","fingerprint":"f","cache_hit":false,'
                '"sentence_count":2,"analyzed_sentence_count":2,'
                '"fallback_sentence_count":0}',
          );
        }
        return (
          statusCode: 200,
          body:
              '{"status":"ready","progress":1,"enabled":true,'
              '"runtime_version":"3.8.13","provider_version":"jsonl-v2",'
              '"model_version":"3.8.0","model_checksum_sha256":"abc",'
              '"delivery_checksum_sha256":"delivery",'
              '"expected_install_bytes":162250752,"installed_bytes":142000000,'
              '"error":null,"updated_at_ms":1}',
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SyntaxCapabilitySettings(
            viewModel: SyntaxCapabilitySettingsViewModel(
              LocalSyntaxCapabilityRepository(api),
              currentTrackId: 'track-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, contains('POST /v1/subtitles/track-1/syntax-analysis'));
    expect(find.textContaining('2/2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
