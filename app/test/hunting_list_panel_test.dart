import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/data/repositories/hunting_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/vocabulary/hunting_list_panel.dart';

import 'hunting_controller_test.dart' show candidateJson, targetJson;

void main() {
  testWidgets(
    'hunting panel shows active targets and confirms review candidates',
    (tester) async {
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (path == '/v1/hunting/targets?status=active&limit=100&offset=0') {
            return (statusCode: 200, body: jsonEncode([targetJson]));
          }
          if (path ==
              '/v1/hunting/candidates?status=active&limit=100&offset=0') {
            return (statusCode: 200, body: jsonEncode([candidateJson]));
          }
          if (method == 'POST' && path == '/v1/hunting/targets') {
            return (
              statusCode: 200,
              body: jsonEncode({
                ...targetJson,
                'id': 'target-2',
                'lexical_entry_id': 'lexical-2',
                'source_kind': 'review_candidate',
                'source_id': 'candidate-1',
                'target_snapshot': 'would have',
              }),
            );
          }
          throw StateError('unexpected $method $path');
        },
      );
      final controller = HuntingController(
        repository: LocalHuntingRepository(() => api),
      );
      addTearDown(controller.dispose);
      await controller.load();

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
              onPromoteCandidate: (candidate) async {
                await controller.promoteCandidate(candidate);
              },
              onArchiveTarget: (_) async {},
            ),
          ),
        ),
      );

      expect(find.text('Hunting List'), findsOneWidget);
      expect(find.text('notice'), findsOneWidget);
      expect(find.text('would have'), findsOneWidget);
      expect(find.text('1 of 5 active targets'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('2 of 5 active targets'), findsOneWidget);
      expect(
        find.text('No review-failure candidates waiting.'),
        findsOneWidget,
      );
    },
  );
}
