import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/provider_settings_view_models.dart';
import 'package:llplayer_next/data/repositories/settings_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/settings/llm_provider_settings.dart';
import 'package:llplayer_next/widgets/settings/syntax_capability_settings.dart';

/// Retained settings panels use the shared spacing and icon-size tokens.
///
/// `icon_size_discipline_test` and `spacing_discipline_test` can only see that
/// a literal is gone; these checks pin the actual values rendered in the
/// retained provider and syntax panels.
void main() {
  LocalApi api({Map<String, String> ok = const {}}) => LocalApi.withTransport(
    baseUrl: 'http://127.0.0.1:62645',
    token: 'token',
    transport: (method, path, body) async {
      for (final entry in ok.entries) {
        if (path.contains(entry.key)) {
          return (statusCode: 200, body: entry.value);
        }
      }
      return (statusCode: 200, body: '{}');
    },
  );

  Future<void> pump(WidgetTester tester, Widget panel) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: SingleChildScrollView(child: panel)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The `Container` that wraps [icon] — the notice strip itself.
  EdgeInsetsGeometry? noticePadding(WidgetTester tester, IconData icon) =>
      tester
          .widgetList<Container>(
            find.ancestor(
              of: find.byIcon(icon),
              matching: find.byType(Container),
            ),
          )
          .first
          .padding;

  double? iconSize(WidgetTester tester, IconData icon) =>
      tester.widget<Icon>(find.byIcon(icon)).size;

  testWidgets('the AI provider privacy notice insets and sizes from tokens', (
    tester,
  ) async {
    await pump(
      tester,
      LlmProviderSettings(
        viewModel: LlmProviderSettingsViewModel(
          LocalLlmProviderRepository(api()),
        ),
      ),
    );

    expect(
      iconSize(tester, Icons.privacy_tip_outlined),
      ListenIconSize.control,
    );
    expect(
      noticePadding(tester, Icons.privacy_tip_outlined),
      ListenPadding.row,
    );
  });

  testWidgets('the sentence-analysis status icon sits on the control step', (
    tester,
  ) async {
    await pump(
      tester,
      SyntaxCapabilitySettings(
        viewModel: SyntaxCapabilitySettingsViewModel(
          LocalSyntaxCapabilityRepository(
            api(
              ok: {
                '/v1/syntax/capability':
                    '{"status":"not_installed",'
                    '"enabled":false,"runtime_version":"3.7",'
                    '"model_version":"en_core_web_sm"}',
              },
            ),
          ),
        ),
      ),
    );

    // Was 20 — a step nobody chose, two points off the row icons beside it.
    expect(iconSize(tester, Icons.extension_outlined), ListenIconSize.control);
  });
}
