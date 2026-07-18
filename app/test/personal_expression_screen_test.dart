import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/screens/personal_expression_screen.dart';
import 'package:llplayer_next/services/api_service.dart';

const _asset = {
  'id': 'pattern-1',
  'language': 'en',
  'source': {
    'kind': 'reading',
    'text': 'I ended up fixing it.',
    'title': 'Real media',
    'media_id': null,
    'media_fingerprint': null,
    'track_id': null,
    'sentence_id': null,
    'semantic_attempt_id': null,
    'start_ms': null,
    'end_ms': null,
    'candidate_ref': null,
  },
  'current_version': {
    'id': 'version-1',
    'pattern_id': 'pattern-1',
    'version': 1,
    'name': 'Ended up',
    'pattern_text': 'I ended up {result}.',
    'slots': [
      {
        'name': 'result',
        'prompt': 'What happened?',
        'example_value': null,
        'required': true,
      },
    ],
    'note': null,
    'system_construction_id': null,
    'created_at_ms': 1,
  },
  'created_at_ms': 1,
  'updated_at_ms': 1,
};

void main() {
  testWidgets('no-text writing assistance actually hides template and slots', (
    tester,
  ) async {
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        if (path.startsWith('/v1/personal-expression/patterns?')) {
          return (statusCode: 200, body: jsonEncode([_asset]));
        }
        if (path.endsWith('/attempts') || path.endsWith('/versions')) {
          return (
            statusCode: 200,
            body: path.endsWith('/versions')
                ? jsonEncode([_asset['current_version']])
                : '[]',
          );
        }
        throw StateError('$method $path was not expected');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PersonalExpressionScreen(api: api, language: 'en'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ended up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写自己的句子'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('I ended up {result}.')),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏模板').last);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: dialog, matching: find.text('I ended up {result}.')),
      findsNothing,
    );
    expect(find.text('模板与槽位提示已隐藏，请直接写出自己的表达。'), findsOneWidget);
  });
}
