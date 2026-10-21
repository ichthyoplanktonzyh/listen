import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/data/repositories/hunting_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/vocabulary/hunting_list_panel.dart';

void main() {
  testWidgets('hunting panel shows saved listening targets and opens entries', (
    tester,
  ) async {
    final requests = <String>[];
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async {
        requests.add('$method $path');
        if (method == 'GET' && path.startsWith('/v1/hunting/targets?')) {
          return (statusCode: 200, body: jsonEncode([_target]));
        }
        throw StateError('unexpected $method $path');
      },
    );
    final controller = HuntingController(
      repository: LocalHuntingRepository(() => api),
    );
    addTearDown(controller.dispose);
    expect(
      await controller.load(),
      isTrue,
      reason:
          'requests=$requests; error=${controller.state.error?.detail?.raw}',
    );

    String? openedEntry;
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
          body: HuntingListPanel(
            controller: controller,
            onRefresh: () async {},
            onArchiveTarget: (_) async {},
            onOpenEntry: (id) => openedEntry = id,
          ),
        ),
      ),
    );

    expect(find.text('Hunting List'), findsOneWidget);
    expect(find.text('would have'), findsOneWidget);
    expect(find.text('1 of 5 active targets'), findsOneWidget);

    await tester.tap(find.text('would have'));
    expect(openedEntry, 'lexical-1');
  });
}

final _target = <String, dynamic>{
  'id': 'target-1',
  'lexical_entry_id': 'lexical-1',
  'source_kind': 'manual',
  'source_id': null,
  'target_snapshot': 'would have',
  'status': 'active',
  'created_at_ms': 1,
  'updated_at_ms': 1,
};
