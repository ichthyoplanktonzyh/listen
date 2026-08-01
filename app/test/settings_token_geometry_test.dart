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
import 'package:llplayer_next/widgets/settings/realtime_provider_settings.dart';
import 'package:llplayer_next/widgets/settings/syntax_capability_settings.dart';

/// The settings family's side of the S2 token migration, asserted on the built
/// widget tree rather than on the source text.
///
/// `icon_size_discipline_test` and `spacing_discipline_test` can only see that
/// a literal is gone; they cannot see which step replaced it. These three
/// panels each opened with the same shape — a one-row notice carrying an icon
/// and a sentence — and each had reached for its own numbers: `EdgeInsets.all(10)`
/// twice and icon sizes of 18 and 20. So the checks below pin the *values* the
/// notices now render at, which is what a reader actually perceives as "the two
/// provider panels open the same way".
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

  testWidgets('the speech provider honesty notice matches it step for step', (
    tester,
  ) async {
    await pump(
      tester,
      RealtimeProviderSettings(
        viewModel: RealtimeProviderSettingsViewModel(
          LocalRealtimeProviderRepository(api()),
        ),
      ),
    );

    expect(iconSize(tester, Icons.hearing_outlined), ListenIconSize.control);
    expect(noticePadding(tester, Icons.hearing_outlined), ListenPadding.row);

    // The point of the migration: the two provider panels no longer open at
    // two different insets. Kept as an explicit cross-panel assertion because
    // that mismatch is invisible in either panel read on its own.
    await pump(
      tester,
      LlmProviderSettings(
        viewModel: LlmProviderSettingsViewModel(
          LocalLlmProviderRepository(api()),
        ),
      ),
    );
    final llm = noticePadding(tester, Icons.privacy_tip_outlined);
    await pump(
      tester,
      RealtimeProviderSettings(
        viewModel: RealtimeProviderSettingsViewModel(
          LocalRealtimeProviderRepository(api()),
        ),
      ),
    );
    expect(noticePadding(tester, Icons.hearing_outlined), llm);
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
