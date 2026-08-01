import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/provider_settings_view_models.dart';
import 'package:llplayer_next/data/repositories/settings_repository.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/settings/realtime_provider_settings.dart';

/// #27, carried over to the settings domain by #87: the realtime voice form
/// builds six TextEditingControllers per mount (one of them holding the API
/// key). Every mount must release all six — the leak tracker fails this test
/// if any survives undisposed.
void main() {
  LeakTesting.enable();

  testWidgets(
    'remounting the realtime voice form leaks no controllers',
    experimentalLeakTesting: LeakTesting.settings.withTrackedAll().withIgnored(
      // The trailing empty frame is still mounted when the test ends; its
      // own two framework objects are not what this test is guarding.
      notDisposed: {
        'SingleChildRenderObjectElement': 1,
        'RenderConstrainedBox': 1,
      },
    ),
    (tester) async {
      // The form is taller than the default 800×600 test surface; give it a
      // desktop-sized window so it lays out without overflowing.
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'token',
        transport: (method, path, body) async {
          if (method == 'GET' && path == '/v1/realtime/providers') {
            return (statusCode: 200, body: '[]');
          }
          throw StateError('Unexpected request: $method $path ${body ?? ''}');
        },
      );
      final viewModels = <RealtimeProviderSettingsViewModel>[];

      for (var round = 0; round < 3; round++) {
        final viewModel = RealtimeProviderSettingsViewModel(
          LocalRealtimeProviderRepository(api),
        );
        viewModels.add(viewModel);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RealtimeProviderSettings(
                  key: ValueKey('round-$round'),
                  viewModel: viewModel,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Add a realtime voice'), findsOneWidget);
      }

      // Unmount the tree so the only undisposed objects left are real leaks.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final viewModel in viewModels) {
        viewModel.dispose();
      }
    },
  );
}
