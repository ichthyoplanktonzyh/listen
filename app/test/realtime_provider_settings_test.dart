import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/provider_settings_view_models.dart';
import 'package:llplayer_next/data/repositories/settings_repository.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/settings/realtime_provider_settings.dart';

const _workspaceErrorText = 'Enter the Workspace ID to complete the endpoint.';

void main() {
  testWidgets('saving without a Qwen workspace ID reports the missing field '
      'instead of silently doing nothing', (tester) async {
    // The provider form stacks eight fields; give it room so the test
    // exercises feedback, not viewport overflow.
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final registerBodies = <Map<String, dynamic>>[];
    final api = _api(registerBodies);

    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    // The default Qwen endpoint still carries the <workspace-id>
    // placeholder: saving must surface the missing field rather than
    // no-op silently.
    await tester.tap(find.text('Save securely'));
    await tester.pumpAndSettle();
    expect(find.text(_workspaceErrorText), findsOneWidget);
    expect(registerBodies, isEmpty);

    // Typing a workspace ID clears the error and unblocks saving.
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace ID'),
      'ws-123',
    );
    await tester.pumpAndSettle();
    expect(find.text(_workspaceErrorText), findsNothing);

    await tester.tap(find.text('Save securely'));
    await tester.pumpAndSettle();
    expect(registerBodies, hasLength(1));
    expect(
      registerBodies.single['base_url'],
      'wss://ws-123.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime',
    );

    // The saved voice appears in the list; the key is never echoed back.
    expect(find.text('Qwen'), findsOneWidget);
    expect(find.text('Key stored'), findsOneWidget);
  });

  testWidgets('a registered voice can be removed only after confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final registerBodies = <Map<String, dynamic>>[];
    final deleted = <String>[];
    final api = _api(registerBodies, deleted: deleted, seeded: true);

    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(find.text('Qwen'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Remove this realtime voice?'), findsOneWidget);

    // Backing out leaves the voice — and its stored key — alone.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(deleted, ['profile-1']);
  });

  testWidgets(
    'local Speech-to-Speech protocol autofills loopback defaults, drops the '
    'Qwen-only fields, and saves without an API key',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final registerBodies = <Map<String, dynamic>>[];
      final api = _api(registerBodies);

      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();

      // The default protocol is Qwen, so its workspace scaffolding is present.
      expect(find.text('Workspace ID'), findsOneWidget);

      await tester.tap(find.text('Qwen Omni Realtime'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local voice (Speech-to-Speech)').last);
      await tester.pumpAndSettle();

      // Qwen-only fields disappear; the thin loopback defaults fill the form.
      expect(find.text('Workspace ID'), findsNothing);
      expect(
        find.widgetWithText(TextField, localRealtimeBaselineEndpoint),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, localRealtimeBaselineModel),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, localRealtimeBaselineVoice),
        findsOneWidget,
      );
      expect(
        find.text('Optional for local services; the backend skips the keychain.'),
        findsOneWidget,
      );

      // Saving with the empty key is allowed and lands on the wire as-is:
      // the backend owns the credential-free branch for this adapter kind.
      await tester.tap(find.text('Save securely'));
      await tester.pumpAndSettle();
      expect(registerBodies, hasLength(1));
      final body = registerBodies.single;
      expect(body['adapter_kind'], 'local_cascade_realtime');
      expect(body['base_url'], localRealtimeBaselineEndpoint);
      expect(body['model_id'], localRealtimeBaselineModel);
      expect(body['voice'], localRealtimeBaselineVoice);
      expect(body['secret'], '');
    },
  );
}

Widget _host(LocalApi api) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: RealtimeProviderSettings(
        viewModel: RealtimeProviderSettingsViewModel(
          LocalRealtimeProviderRepository(api),
        ),
      ),
    ),
  ),
);

LocalApi _api(
  List<Map<String, dynamic>> registerBodies, {
  List<String>? deleted,
  bool seeded = false,
}) => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'token',
  transport: (method, path, body) async {
    if (method == 'GET' && path == '/v1/realtime/providers') {
      final present =
          (seeded || registerBodies.isNotEmpty) &&
          (deleted == null || deleted.isEmpty);
      return (statusCode: 200, body: present ? '[${_profileJson()}]' : '[]');
    }
    if (method == 'POST' && path == '/v1/realtime/providers') {
      registerBodies.add(jsonDecode(body!) as Map<String, dynamic>);
      return (statusCode: 200, body: _profileJson());
    }
    if (method == 'DELETE' && path == '/v1/realtime/providers/profile-1') {
      deleted?.add('profile-1');
      return (statusCode: 200, body: 'null');
    }
    throw StateError('Unexpected request: $method $path ${body ?? ''}');
  },
);

String _profileJson() => jsonEncode({
  'id': 'profile-1',
  'display_name': 'Qwen',
  'adapter_kind': 'qwen_omni_realtime',
  'base_url': 'wss://ws-123.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime',
  'model_id': 'qwen',
  'voice': 'Tina',
  'has_credential': true,
  'timeout_ms': 30000,
});
