import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/provider_settings_view_models.dart';
import 'package:llplayer_next/data/repositories/settings_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/llm_provider.dart';
import 'package:llplayer_next/widgets/settings/llm_provider_settings.dart';

void main() {
  testWidgets(
    'provider setup selects only the semantic task uses the learner enables',
    (tester) async {
      final repository = _ProviderRepository();
      final viewModel = LlmProviderSettingsViewModel(repository);
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: LlmProviderSettings(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rubric generation'), findsOneWidget);
      expect(find.text('Semantic judgment'), findsOneWidget);
      expect(find.text('Sense-group analysis'), findsOneWidget);

      final fields = find.byType(TextField);
      Future<void> fillProviderForm() async {
        await tester.ensureVisible(fields.at(0));
        await tester.enterText(fields.at(0), 'Local language helper');
        await tester.ensureVisible(fields.at(1));
        await tester.enterText(fields.at(1), 'http://127.0.0.1:8000/v1');
        await tester.ensureVisible(fields.at(2));
        await tester.enterText(fields.at(2), 'model');
        await tester.ensureVisible(fields.at(3));
        await tester.enterText(fields.at(3), 'write-only-secret');
      }

      await fillProviderForm();

      final senseGroupCheckbox = find.ancestor(
        of: find.text('Sense-group analysis'),
        matching: find.byType(CheckboxListTile),
      );
      final rubricCheckbox = find.ancestor(
        of: find.text('Rubric generation'),
        matching: find.byType(CheckboxListTile),
      );
      final judgmentCheckbox = find.ancestor(
        of: find.text('Semantic judgment'),
        matching: find.byType(CheckboxListTile),
      );
      await tester.ensureVisible(senseGroupCheckbox);
      expect(tester.widget<CheckboxListTile>(senseGroupCheckbox).value, isTrue);
      expect(tester.widget<CheckboxListTile>(judgmentCheckbox).value, isTrue);
      expect(tester.widget<CheckboxListTile>(rubricCheckbox).value, isFalse);
      await tester.tap(senseGroupCheckbox);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(senseGroupCheckbox).value,
        isFalse,
      );
      await tester.ensureVisible(find.text('Save provider'));
      await tester.tap(find.text('Save provider'));
      await tester.pumpAndSettle();
      expect(repository.registered?.allowedUses, ['semantic_judgment']);

      await fillProviderForm();
      await tester.ensureVisible(rubricCheckbox);
      await tester.tap(rubricCheckbox);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(rubricCheckbox).value, isTrue);
      await tester.ensureVisible(find.text('Save provider'));
      await tester.tap(find.text('Save provider'));
      await tester.pumpAndSettle();
      expect(repository.registered?.allowedUses, [
        'rubric_generation',
        'semantic_judgment',
      ]);
      expect(repository.registered?.secret, 'write-only-secret');
    },
  );
}

class _ProviderRepository implements LlmProviderRepository {
  LlmProviderDraft? registered;

  @override
  Future<List<LlmProviderProfileView>> list() async => const [];

  @override
  Future<LlmProviderProfileView> register(LlmProviderDraft draft) async {
    registered = draft;
    return const LlmProviderProfileView(
      id: 'provider-1',
      displayName: 'Local listening helper',
      adapterKind: 'openai_chat_completions',
      baseUrl: 'http://127.0.0.1:8000/v1',
      modelId: 'model',
      hasCredential: true,
      timeoutMs: 30000,
      maxRetries: 1,
      retention: 'unknown',
      allowedUses: ['sense_group_partition'],
      capability: LlmProviderCapability(
        structuredOutput: LlmCapabilityClaim(state: 'unknown'),
        streaming: LlmCapabilityClaim(state: 'unknown'),
        multilingual: LlmCapabilityClaim(state: 'unknown'),
        audioInput: LlmCapabilityClaim(state: 'unknown'),
      ),
      createdAtMs: 1,
    );
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<LlmProbeResult> probe(String id) async => const LlmProbeResult(
    structuredOutput: LlmCapabilityClaim(state: 'unknown'),
  );
}
